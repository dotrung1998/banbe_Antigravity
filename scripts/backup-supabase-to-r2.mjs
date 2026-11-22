#!/usr/bin/env node
// Backs up the production Supabase project to a PRIVATE R2 bucket.
//
//   node scripts/backup-supabase-to-r2.mjs                 # run now
//   node scripts/backup-supabase-to-r2.mjs --keep 30       # retention
//   node scripts/backup-supabase-to-r2.mjs --skip-storage  # database only
//   node scripts/backup-supabase-to-r2.mjs --download <key> --out tmp/restore
//
// What it writes to R2 (under backups/<UTC timestamp>/):
//   banbe-backup.tar.gz   schema + data + storage files + internal manifest
//   manifest.json         sizes, checksums, row counts, storage totals
// plus backups/index.json, used for retention without needing bucket LIST.
//
// Secrets come from .r2-secrets.local / .env.local (scripts/lib/secrets.mjs)
// or the environment on CI. Nothing here prints a credential.
//
// Dump source:
//   SUPABASE_DB_URL set -> `supabase db dump --db-url ...` (CI)
//   otherwise           -> `supabase db dump --linked` (a linked local CLI)
//
// Bucket:
//   R2_BACKUP_BUCKET when set. Otherwise the private staging bucket is used
//   with a warning: that bucket may have a short lifecycle rule, so it is not
//   a durable backup target until a dedicated bucket + token exist.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { loadSecrets, missingNames } from './lib/secrets.mjs';
import { deleteObject, getObject, putObject, r2Config } from '../api/_lib/r2.js';

const CORE_TABLES = [
  'profiles',
  'bookings',
  'payment_audit_log',
  'payment_webhook_events',
  'payment_documents',
  'events',
  'event_photos',
];

const args = parseArgs(process.argv.slice(2));
const { values } = loadSecrets();
const REQUIRED = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY'];
const missing = missingNames(values, REQUIRED);
if (missing.length) {
  console.error(`Missing credentials: ${missing.join(', ')}. See .r2-secrets.local.example.`);
  process.exit(2);
}

const cfg = { ...r2Config(values), region: 'auto' };
if (!cfg.ok) {
  console.error(`Missing R2 configuration: ${cfg.missing.join(', ')}`);
  process.exit(2);
}
const bucket = args.bucket || values.R2_BACKUP_BUCKET || cfg.stagingBucket;
const usingFallback = !args.bucket && !values.R2_BACKUP_BUCKET;
const prefix = String(args.prefix || 'backups').replace(/^\/+|\/+$/g, '');
const keep = Math.max(1, Number(args.keep) || 30);

if (args.download) {
  if (typeof args.download !== 'string') {
    console.error('Usage: node scripts/backup-supabase-to-r2.mjs --download <object-key> --out <dir>');
    process.exit(2);
  }
  await downloadOnly(args.download, args.out || 'tmp/restore');
  process.exit(0);
}

const created = new Date();
const stamp = created.toISOString().replace(/[:.]/g, '-');
const root = resolve(args.out || join('tmp', 'backups', stamp));
const dumpDir = join(root, 'database');
const storageDir = join(root, 'storage');
const archivePath = join(root, 'banbe-backup.tar.gz');
const db = createClient(values.SUPABASE_URL, values.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

mkdirSync(dumpDir, { recursive: true });
mkdirSync(storageDir, { recursive: true });
console.log(`Backup ${stamp} -> ${root}`);
if (usingFallback) {
  console.warn(`! R2_BACKUP_BUCKET is not set: writing to the private staging bucket "${bucket}" under ${prefix}/.`);
  console.warn('  That bucket may have a 1-day lifecycle rule. Create a dedicated "banbe-backups" bucket + token before relying on it.');
}

// ---- database dumps -------------------------------------------------------
const dumpTarget = values.SUPABASE_DB_URL ? ['--db-url', values.SUPABASE_DB_URL] : ['--linked'];
function dump(extra, file) {
  const cmdArgs = ['db', 'dump', ...dumpTarget, ...extra, '-f', file];
  try {
    execFileSync('supabase', cmdArgs, {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env,
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (e) {
    throw new Error(`supabase db dump failed (${extra.join(' ')}): ${redact(`${e.stderr || ''} ${e.stdout || ''}`).slice(0, 1200)}`);
  }
}

dump(['--schema', 'public'], join(dumpDir, 'schema-public.sql'));
console.log('  · public schema');
dump(['--schema', 'public', '--data-only', '--use-copy'], join(dumpDir, 'data-public.sql'));
console.log('  · public data');
dump(['--schema', 'auth'], join(dumpDir, 'schema-auth.sql'));
console.log('  · auth schema');
dump(['--schema', 'auth', '--data-only', '--use-copy'], join(dumpDir, 'data-auth.sql'));
console.log('  · auth data');

const schemaPublic = readFileSync(join(dumpDir, 'schema-public.sql'), 'utf8');
const schemaAuth = readFileSync(join(dumpDir, 'schema-auth.sql'), 'utf8');
const dataAuthSql = readFileSync(join(dumpDir, 'data-auth.sql'), 'utf8');
const countTables = (sql) => (sql.match(/^CREATE TABLE (?:IF NOT EXISTS )?/gm) || []).length;
/** Rows in one COPY block. pg_dump escapes embedded newlines, so one line = one row. */
function countCopyRows(sql, schema, table) {
  const marker = `COPY "${schema}"."${table}"`;
  const start = sql.indexOf(marker);
  if (start < 0) return null;
  const bodyStart = sql.indexOf('\n', start) + 1;
  const bodyEnd = sql.indexOf('\n\\.', bodyStart);
  const body = sql.slice(bodyStart, bodyEnd < 0 ? undefined : bodyEnd);
  return body.split('\n').filter((line) => line.length > 0).length;
}

// ---- row counts -----------------------------------------------------------
const counts = {};
for (const table of CORE_TABLES) {
  const { count, error } = await db.from(table).select('*', { count: 'exact', head: true });
  counts[table] = error ? null : count;
}
counts.auth_users = countCopyRows(dataAuthSql, 'auth', 'users');

// ---- Storage copy ---------------------------------------------------------
const buckets = [];
let storageObjects = 0;
let storageBytes = 0;
const storageEntries = [];
if (!args.skipStorage) {
  const { data: list, error } = await db.storage.listBuckets();
  if (error) throw new Error(`storage.listBuckets: ${error.message}`);
  for (const b of list) {
    const objects = await listObjects(b.name);
    const bucketBytes = objects.reduce((sum, o) => sum + o.size, 0);
    console.log(`  · storage ${b.name}: ${objects.length} object(s), ${formatBytes(bucketBytes)}`);
    buckets.push({ name: b.name, public: !!b.public, objects: objects.length, bytes: bucketBytes });
    for (const obj of objects) {
      const { data, error: dlError } = await db.storage.from(b.name).download(obj.path);
      if (dlError) throw new Error(`storage download ${b.name}/${obj.path}: ${dlError.message}`);
      const buf = Buffer.from(await data.arrayBuffer());
      const local = join(storageDir, safeSegment(b.name), ...obj.path.split('/').map(safeSegment));
      mkdirSync(dirname(local), { recursive: true });
      writeFileSync(local, buf);
      storageEntries.push({ bucket: b.name, path: obj.path, bytes: buf.length, sha256: sha256(buf), contentType: obj.contentType });
      storageObjects += 1;
      storageBytes += buf.length;
    }
  }
  writeJson(join(root, 'storage-manifest.json'), { generatedAt: created.toISOString(), bucketCount: buckets.length, objects: storageObjects, bytes: storageBytes, buckets, files: storageEntries });
}

// ---- manifest -------------------------------------------------------------
const artifacts = {
  schemaPublic: await fileInfo(join(dumpDir, 'schema-public.sql')),
  dataPublic: await fileInfo(join(dumpDir, 'data-public.sql')),
  schemaAuth: await fileInfo(join(dumpDir, 'schema-auth.sql')),
  dataAuth: await fileInfo(join(dumpDir, 'data-auth.sql')),
};
if (!args.skipStorage) artifacts.storageManifest = await fileInfo(join(root, 'storage-manifest.json'));

const manifest = {
  version: 1,
  createdAt: created.toISOString(),
  source: { projectRef: projectRef(values.SUPABASE_URL), database: 'postgres' },
  git: gitInfo(),
  database: {
    publicTables: countTables(schemaPublic),
    authTables: countTables(schemaAuth),
    counts,
  },
  storage: { buckets, bucketCount: buckets.length, objects: storageObjects, bytes: storageBytes },
  artifacts,
  r2: {
    bucket,
    prefix,
    fallback: usingFallback,
    warning: usingFallback
      ? 'R2_BACKUP_BUCKET is not set; this backup lives in the private staging bucket, which may expire objects. Set R2_BACKUP_BUCKET to a dedicated bucket for durable backups.'
      : null,
  },
  restore: {
    order: [
      'create extensions schema + pgcrypto/uuid-ossp/pg_trgm',
      'restore auth schema (trigger creation may fail until public functions exist)',
      'restore public schema',
      'recreate auth triggers on_auth_phone_confirmed / on_auth_user_created / on_auth_user_deleted',
      'restore auth data',
      'restore public data',
    ],
    docs: 'docs/cloudflare-sepay-migration.md',
  },
};
writeJson(join(root, 'manifest.json'), manifest);

// ---- archive + checksums --------------------------------------------------
if (existsSync(archivePath)) rmSync(archivePath);
const archiveInputs = ['database', 'storage', 'storage-manifest.json', 'manifest.json']
  .filter((p) => existsSync(join(root, p)));
execFileSync('tar', ['-czf', archivePath, '-C', root, ...archiveInputs]);
const archiveInfo = await fileInfo(archivePath);
manifest.artifacts.archive = { file: basename(archivePath), bytes: archiveInfo.bytes, sha256: archiveInfo.sha256 };
writeJson(join(root, 'manifest.json'), manifest);

// ---- upload ---------------------------------------------------------------
const keyBase = `${prefix}/${stamp}`;
const archiveKey = `${keyBase}/banbe-backup.tar.gz`;
const manifestKey = `${keyBase}/manifest.json`;
console.log(`  · uploading ${formatBytes(archiveInfo.bytes)} to ${bucket}/${archiveKey}`);
await putObject(cfg, bucket, archiveKey, readFileSync(archivePath), { contentType: 'application/gzip' });
await putObject(cfg, bucket, manifestKey, Buffer.from(JSON.stringify(manifest, null, 2)), { contentType: 'application/json' });
console.log('  · uploaded');

const indexKey = `${prefix}/index.json`;
let index = { version: 1, backups: [] };
try {
  const existing = await getObject(cfg, bucket, indexKey, 4 * 1024 * 1024);
  if (existing) index = JSON.parse(existing.toString('utf8'));
} catch { /* first backup or unreadable index: start a new one */ }
if (!Array.isArray(index.backups)) index.backups = [];
index.backups.unshift({
  createdAt: manifest.createdAt,
  archiveKey,
  manifestKey,
  bytes: archiveInfo.bytes,
  sha256: archiveInfo.sha256,
  counts,
  storageObjects,
  storageBytes,
  publicTables: manifest.database.publicTables,
});
const removed = index.backups.splice(keep);
index.updatedAt = new Date().toISOString();
await putObject(cfg, bucket, indexKey, Buffer.from(JSON.stringify(index, null, 2)), { contentType: 'application/json' });
for (const old of removed) {
  try { await deleteObject(cfg, bucket, old.archiveKey); } catch { /* best effort */ }
  try { await deleteObject(cfg, bucket, old.manifestKey); } catch { /* best effort */ }
}

console.log(`✓ archive   ${archiveKey}  (${formatBytes(archiveInfo.bytes)}, sha256 ${archiveInfo.sha256.slice(0, 16)}…)`);
console.log(`✓ manifest  ${manifestKey}`);
console.log(`✓ counts    ${JSON.stringify(counts)}`);
console.log(`✓ storage   ${storageObjects} object(s), ${formatBytes(storageBytes)} across ${buckets.length} bucket(s)`);
console.log(`✓ tables    public=${manifest.database.publicTables} auth=${manifest.database.authTables}`);
if (usingFallback) console.log('! fallback bucket in use — see the warning above');

// ---- helpers --------------------------------------------------------------
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const name = a.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) { out[name] = next; i += 1; }
    else out[name] = true;
  }
  return out;
}

function redact(text) {
  return String(text)
    .replace(/postgres(?:ql)?:\/\/[^\s"']+/gi, 'postgresql://<redacted>')
    .replace(/PGPASSWORD="[^"]*"/gi, 'PGPASSWORD="<redacted>"')
    .replace(/password=[^\s&"']+/gi, 'password=<redacted>')
    .replace(/\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b/g, '<jwt>');
}

function sha256(buf) { return createHash('sha256').update(buf).digest('hex'); }
function sha256File(file) {
  return new Promise((resolvePromise, reject) => {
    const hash = createHash('sha256');
    createReadStream(file).on('data', (d) => hash.update(d)).on('error', reject).on('end', () => resolvePromise(hash.digest('hex')));
  });
}
async function fileInfo(file) {
  const { stat } = await import('node:fs/promises');
  const info = await stat(file);
  return { file: basename(file), bytes: info.size, sha256: await sha256File(file) };
}
function writeJson(file, value) { writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`); }
function safeSegment(segment) { return String(segment).replace(/[^A-Za-z0-9._-]/g, '_').replace(/^\.+$/, '_'); }
function projectRef(url) { try { return new URL(url).hostname.split('.')[0]; } catch { return 'unknown'; } }
function gitInfo() {
  try {
    const commit = execFileSync('git', ['rev-parse', '--short=12', 'HEAD'], { encoding: 'utf8' }).trim();
    const branch = execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8' }).trim();
    return { commit, branch };
  } catch { return null; }
}
function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

async function listObjects(bucketName, path = '') {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.storage.from(bucketName).list(path, { limit: 1000, offset });
    if (error) throw new Error(`storage list ${bucketName}/${path}: ${error.message}`);
    if (!data || !data.length) break;
    for (const entry of data) {
      const full = path ? `${path}/${entry.name}` : entry.name;
      if (!entry.id) out.push(...await listObjects(bucketName, full));
      else out.push({ path: full, size: Number(entry.metadata?.size) || 0, contentType: entry.metadata?.mimetype || null });
    }
    if (data.length < 1000) break;
  }
  return out;
}

async function downloadOnly(key, outDir) {
  if (!key || typeof key !== 'string') { console.error('--download needs an object key, e.g. backups/2026-…/banbe-backup.tar.gz'); process.exit(2); }
  mkdirSync(outDir, { recursive: true });
  const filename = basename(key);
  const dest = join(outDir, filename);
  const buf = await getObject(cfg, bucket, key);
  if (!buf) { console.error(`Not found: ${key} in ${bucket}`); process.exit(1); }
  writeFileSync(dest, buf);
  console.log(`${dest} (${formatBytes(buf.length)}, sha256 ${sha256(buf).slice(0, 16)}…)`);
}

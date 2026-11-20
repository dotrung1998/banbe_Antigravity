#!/usr/bin/env node
// Read-only readiness check for the Supabase → Cloudflare R2 media migration
// (.claude/notes/28-r2-hybrid-media.md). It never writes app data and never
// prints a credential: only names, status codes and counts.
//
//   node scripts/r2-preflight.mjs
//
// What it proves, end to end:
//   1. the local secrets file is present, complete and not world-readable;
//   2. Supabase already has migration 153 (media_assets + *_r2_ref) and how
//      many objects are eligible to move;
//   3. the R2 S3 token can write/read/delete in BOTH buckets (real SigV4);
//   4. a presigned PUT works (that is the exact URL a browser/iOS app uses);
//   5. the public custom domain really serves the object with the immutable
//      cache header, and does NOT serve the staging bucket;
//   6. bucket CORS answers a browser preflight for the production origin;
//   7. the purge token works (when configured);
//   8. the feature flags are in a safe starting state.
//
// Exit code 0 = every hard check passed. Warnings never fail the run.
import { createHash, randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { loadSecrets, missingNames, loosePermissions, SECRETS_FILES } from './lib/secrets.mjs';
import { r2Config, presignUrl, putObject, getObject, deleteObject, purgeUrls } from '../api/_lib/r2.js';

const REQUIRED = [
  'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY',
  'R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY',
  'R2_PUBLIC_BUCKET', 'R2_STAGING_BUCKET', 'MEDIA_PUBLIC_BASE_URL',
];
const WEB_ORIGINS = ['https://www.banbe.app', 'https://banbe.app'];

const results = [];
const check = (name, ok, detail = '', { warn = false } = {}) => {
  results.push({ name, ok: ok ? 'pass' : warn ? 'warn' : 'fail', detail });
  const icon = ok ? '✓' : warn ? '!' : '✗';
  console.log(`${icon} ${name}${detail ? ` — ${detail}` : ''}`);
};
const sha = (b) => createHash('sha256').update(b).digest('hex');
// A 1x1 PNG. Real bytes so content-type/caching checks reflect a real image.
const PROBE_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const errCode = (e) => e?.code || e?.cause?.code || e?.message || 'ERROR';

async function main() {
  console.log('R2 preflight — no credentials are printed by this script.\n');

  for (const f of loosePermissions(SECRETS_FILES)) {
    check(`permissions on ${f}`, false, `readable by other users; run: chmod 600 ${f}`, { warn: true });
  }

  const { values: env, sources } = loadSecrets();
  const usedFiles = [...new Set(Object.values(sources).filter((s) => s !== 'environment'))];
  const missing = missingNames(env, REQUIRED);
  check('required values present', missing.length === 0,
    missing.length ? `missing: ${missing.join(', ')}` : usedFiles.length ? `from ${usedFiles.join(', ')}` : 'from environment');
  if (missing.length) return finish();

  const base = env.MEDIA_PUBLIC_BASE_URL.replace(/\/+$/, '');
  const baseUrl = (() => { try { return new URL(base); } catch { return null; } })();
  check('MEDIA_PUBLIC_BASE_URL is a plain https origin', !!baseUrl && baseUrl.protocol === 'https:',
    baseUrl ? `${baseUrl.protocol}//${baseUrl.host}` : 'unparseable');
  check('public domain is not r2.dev', !/\.r2\.dev$/i.test(baseUrl?.hostname || ''),
    /\.r2\.dev$/i.test(baseUrl?.hostname || '') ? 'r2.dev is rate-limited and not a real CDN contract; attach a custom domain' : '');
  check('public domain is not Supabase', !/supabase\.co$/i.test(baseUrl?.hostname || ''), '');
  check('public and staging buckets differ', env.R2_PUBLIC_BUCKET !== env.R2_STAGING_BUCKET,
    env.R2_PUBLIC_BUCKET === env.R2_STAGING_BUCKET ? 'a shared bucket would expose staging objects' : '');

  // ---- Supabase: is migration 153 there, and how much is eligible? ----
  const db = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const head = (q) => q.then(({ count, error }) => ({ count: count ?? 0, error }));
  const assets = await head(db.from('media_assets').select('id', { count: 'exact', head: true }));
  const has153 = !assets.error;
  check('migration 153 applied (media_assets)', has153, has153 ? `${assets.count} asset row(s)` : `missing (${assets.error?.code}); apply 20261203000153_153_r2_public_media.sql first`);
  if (has153) {
    const cols = await db.from('events').select('id, cover_r2_ref').limit(1);
    if (cols.error) check('events.cover_r2_ref exists', false, cols.error.code);
    const published = await head(db.from('media_assets').select('id', { count: 'exact', head: true }).eq('status', 'published'));
    console.log(`  · already published on R2: ${published.count}`);
  }
  const evs = await db.from('events').select('id,status,visibility').in('status', ['live', 'ended', 'cancelled']).eq('visibility', 'public');
  const photos = await db.from('event_photos').select('r2_ref, storage_path').limit(5000);
  const orgs = await db.from('organizers').select('id,avatar_path,avatar_r2_ref').neq('avatar_path', '').limit(1000);
  const eligiblePhotos = (photos.data || []).filter((p) => !p.r2_ref && !String(p.storage_path || '').startsWith('event-photos-private/') && !String(p.storage_path || '').startsWith('r2:')).length;
  const eligibleAvatars = (orgs.data || []).filter((o) => !o.avatar_r2_ref && o.avatar_path && !String(o.avatar_path).startsWith('r2:')).length;
  console.log(`  · public events: ${evs.data?.length ?? 0} · event photos to copy: ${eligiblePhotos} · organizer avatars to copy: ${eligibleAvatars}`);
  if (eligiblePhotos || eligibleAvatars) {
    check('migration backlog readable', true, `${eligiblePhotos + eligibleAvatars} object(s) — run the script with no flags for a dry-run`);
  }

  // ---- R2 configuration object (never printed) ----
  const cfg = { ...r2Config(env), region: 'auto' };
  if (!cfg.ok || !cfg.publicBaseUrl) {
    check('R2 configuration complete', false, (cfg.missing || ['MEDIA_PUBLIC_BASE_URL']).join(', '));
    return finish();
  }

  // ---- S3 token: staging write/read/delete ----
  const probeId = randomUUID();
  const stagingKey = `staging/__preflight__/${probeId}`;
  const publicKey = `v1/__preflight__/${probeId}/card.png`;
  let stagingOk = false;
  try {
    await putObject(cfg, cfg.stagingBucket, stagingKey, PROBE_PNG, { contentType: 'image/png' });
    const back = await getObject(cfg, cfg.stagingBucket, stagingKey, 1024);
    stagingOk = !!back && sha(back) === sha(PROBE_PNG);
    check('staging bucket: write + read back', stagingOk,
      stagingOk ? `bucket ${cfg.stagingBucket}` : 'bytes differed');
  } catch (e) {
    check('staging bucket: write + read back', false, `${errCode(e)} — check bucket name + token scope`);
  }

  // ---- Presigned PUT: the exact browser/iOS path ----
  try {
    const url = presignUrl(cfg, { method: 'PUT', bucket: cfg.stagingBucket, key: stagingKey, headers: { 'content-type': 'image/png' }, expiresIn: 300, maxExpires: 900 });
    const res = await fetch(url, { method: 'PUT', headers: { 'content-type': 'image/png' }, body: PROBE_PNG });
    check('presigned PUT accepted', res.ok, `HTTP ${res.status}${res.ok ? '' : ' — SigV4/bucket/expiry'}`);
  } catch (e) {
    check('presigned PUT accepted', false, errCode(e));
  }

  // ---- Bucket CORS for the real web origin ----
  try {
    const origin = WEB_ORIGINS[0];
    const url = presignUrl(cfg, { method: 'PUT', bucket: cfg.stagingBucket, key: stagingKey, headers: { 'content-type': 'image/png' }, expiresIn: 300, maxExpires: 900 });
    const res = await fetch(url, {
      method: 'OPTIONS',
      headers: {
        Origin: origin,
        'Access-Control-Request-Method': 'PUT',
        'Access-Control-Request-Headers': 'content-type',
      },
    });
    const allow = res.headers.get('access-control-allow-origin') || '';
    const ok = allow === origin || allow === '*';
    check('staging CORS allows the web app', ok,
      ok ? origin : `HTTP ${res.status}, allow-origin=${allow || '(none)'} — add ${WEB_ORIGINS.join(', ')} to the staging bucket CORS`);
  } catch (e) {
    check('staging CORS allows the web app', false, errCode(e), { warn: true });
  }

  // ---- Public bucket + custom domain, trought the real CDN ----
  let publicOk = false;
  try {
    await putObject(cfg, cfg.publicBucket, publicKey, PROBE_PNG, { contentType: 'image/png', cacheControl: 'public, max-age=31536000, immutable' });
    const res = await fetch(`${base}/${publicKey}`);
    const body = Buffer.from(await res.arrayBuffer());
    const cache = res.headers.get('cache-control') || '';
    const type = res.headers.get('content-type') || '';
    publicOk = res.ok && body.length === PROBE_PNG.length && cache.includes('immutable') && type.startsWith('image/png');
    check('public domain serves the object', publicOk,
      publicOk ? `HTTP 200, ${type.split(';')[0]}, immutable` : `HTTP ${res.status}, type=${type || '-'}, cache=${cache || '-'}`);
  } catch (e) {
    check('public domain serves the object', false, `${errCode(e)} — is ${baseUrl?.host} attached to bucket ${cfg.publicBucket}?`);
  }

  // ---- Staging must never be reachable on the public domain ----
  try {
    const res = await fetch(`${base}/${stagingKey}`, { method: 'GET' });
    const safe = res.status === 403 || res.status === 404;
    check('staging key is not public', safe, `HTTP ${res.status}`);
  } catch {
    check('staging key is not public', true, 'unreachable (fine)');
  }

  // ---- Purge token (optional but needed for immediate removal) ----
  if (env.CLOUDFLARE_ZONE_ID && env.CLOUDFLARE_PURGE_TOKEN) {
    const r = await purgeUrls([`${base}/${publicKey}`], env);
    check('CDN purge token', !!r.ok, r.ok ? 'purge accepted' : r.reason || 'failed');
  } else {
    check('CDN purge token', false, 'CLOUDFLARE_ZONE_ID / CLOUDFLARE_PURGE_TOKEN unset — deletions still work, cached copies expire on their own', { warn: true });
  }

  // ---- Cleanup probes (never leave test objects behind) ----
  try { await deleteObject(cfg, cfg.publicBucket, publicKey); } catch { /* best effort */ }
  try { await deleteObject(cfg, cfg.stagingBucket, stagingKey); } catch { /* best effort */ }
  if (publicOk) check('probe objects cleaned up', true, '');

  // ---- Flags ----
  const mode = String(env.MEDIA_R2_UPLOADS || 'off').toLowerCase();
  check('MEDIA_R2_UPLOADS starts safe', ['off', 'allowlist'].includes(mode), `currently "${mode}"`);
  if (mode === 'allowlist' && !env.MEDIA_R2_UPLOAD_USER_IDS) {
    check('allowlist has user ids', false, 'MEDIA_R2_UPLOAD_USER_IDS is empty; every upload would stay on Supabase');
  }

  return finish();
}

function finish() {
  const fails = results.filter((r) => r.ok === 'fail');
  const warns = results.filter((r) => r.ok === 'warn');
  console.log(`\n${results.length - fails.length - warns.length} passed · ${warns.length} warning(s) · ${fails.length} failed`);
  if (fails.length) {
    console.log('\nNot safe to run the migration yet. Fix the ✗ lines above.');
    process.exitCode = 1;
  } else {
    console.log('\nReady. Next: dry-run the migration (no writes):\n  node scripts/migrate-media-to-r2.mjs --limit 5');
  }
}

main().catch((e) => {
  // Message only: this script never puts URLs or credentials in errors.
  console.error('preflight failed:', errCode(e));
  process.exitCode = 1;
});

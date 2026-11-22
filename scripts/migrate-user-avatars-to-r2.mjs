#!/usr/bin/env node
// Copies USER profile avatars (bucket `avatars`) to the public R2 bucket and
// points `profiles.avatar_url` at the immutable R2 URL. The Supabase object is
// never deleted or changed, so `--rollback` restores the original URL.
//
// Why not media_assets/*_r2_ref: profiles have no avatar_r2_ref column and iOS
// renders `profiles.avatar_url` directly. Adding a ref column would require a
// schema + iOS change; this data-only copy works for web and iOS unchanged.
//
//   node scripts/migrate-user-avatars-to-r2.mjs              # dry run
//   node scripts/migrate-user-avatars-to-r2.mjs --apply      # copy + update URLs
//   node scripts/migrate-user-avatars-to-r2.mjs --rollback --apply
//
// Idempotent: a profile already on an R2 URL is skipped; the key contains the
// sha256, so a re-run maps the same bytes to the same object.
import { createHash } from 'node:crypto';
import { appendFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { inspectImage } from '../api/_lib/imageSafe.js';
import { r2Config, putObject, getObject } from '../api/_lib/r2.js';
import { IMMUTABLE_CACHE } from '../api/_lib/media.js';
import { loadSecrets } from './lib/secrets.mjs';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const ROLLBACK = args.includes('--rollback');
const LIMIT = Number((args[args.indexOf('--limit') + 1] || 0)) || Infinity;
const STATE = '.migration-state/user-avatars-r2.jsonl';
const sha = (b) => createHash('sha256').update(b).digest('hex');

const env = loadSecrets().values;
if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
  console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY required');
  process.exit(2);
}
const cfg = r2Config(env);
if (!cfg.ok || !cfg.publicBaseUrl) {
  console.error('R2_* and MEDIA_PUBLIC_BASE_URL required', cfg.missing || '');
  process.exit(2);
}
const db = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const audit = (rec) => {
  mkdirSync('.migration-state', { recursive: true });
  appendFileSync(STATE, JSON.stringify({ at: new Date().toISOString(), ...rec }) + '\n');
};
const fail = (msg) => { console.error(`  FAILED ${msg}`); process.exitCode = 1; };

function parseAvatarUrl(url) {
  const m = String(url || '').match(/\/storage\/v1\/object\/public\/avatars\/([^?#]+)/);
  if (!m) return null;
  return decodeURIComponent(m[1]);
}

async function rollback() {
  if (!existsSync(STATE)) { console.log('No state file; nothing to roll back.'); return; }
  const latest = new Map();
  for (const line of readFileSync(STATE, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { const r = JSON.parse(line); if (r.profileId && r.publicUrl && r.originalUrl) latest.set(r.profileId, r); } catch { /* ignore */ }
  }
  let n = 0;
  for (const [profileId, r] of latest) {
    if (!APPLY) {
      const { data } = await db.from('profiles').select('avatar_url').eq('id', profileId).maybeSingle();
      if (data?.avatar_url === r.publicUrl) { n++; console.log(`  would restore ${profileId} -> Supabase original`); }
      else console.log(`  skip ${profileId}: avatar_url no longer points at ${r.publicUrl}`);
      continue;
    }
    const { data, error } = await db.from('profiles').update({ avatar_url: r.originalUrl }).eq('id', profileId).eq('avatar_url', r.publicUrl).select('id');
    if (error) { fail(`${profileId}: ${error.message}`); continue; }
    if (data?.length) { n++; console.log(`  restored ${profileId} -> Supabase original`); audit({ profileId, status: 'rolled-back', url: r.originalUrl }); }
    else console.log(`  skip ${profileId}: avatar_url no longer points at ${r.publicUrl}`);
  }
  console.log(`${n} avatar(s) ${APPLY ? 'restored' : 'would be restored (dry-run: add --apply)'}`);
}

async function run() {
  if (ROLLBACK) return rollback();
  const { data: profiles, error } = await db.from('profiles').select('id,handle,display_name,avatar_url').not('avatar_url', 'is', null);
  if (error) throw new Error(error.message);
  const targets = (profiles || []).filter((p) => parseAvatarUrl(p.avatar_url)).slice(0, LIMIT);
  console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'}: ${targets.length} profile avatar(s) on Supabase Storage`);
  let copied = 0, updated = 0, skipped = 0;
  for (const p of targets) {
    const originalUrl = p.avatar_url;
    const path = parseAvatarUrl(originalUrl);
    try {
      if (String(originalUrl).startsWith(cfg.publicBaseUrl + '/')) { skipped++; console.log(`  skip ${p.id}: already R2`); continue; }
      const { data: blob, error: dl } = await db.storage.from('avatars').download(path);
      if (dl || !blob) throw new Error(`download ${path}: ${dl?.message || 'missing'}`);
      const bytes = Buffer.from(await blob.arrayBuffer());
      const img = inspectImage(bytes, { maxBytes: 5 * 1024 * 1024, maxLongEdge: 4000, maxPixels: 16_000_000 });
      const hash = sha(bytes);
      const key = `v1/user-avatars/${p.id}/${hash}.${img.ext}`;
      const publicUrl = `${cfg.publicBaseUrl}/${key}`;
      console.log(`${APPLY ? 'copy' : 'would copy'} ${p.id} (${p.handle || p.display_name || 'no handle'}) ${bytes.length} bytes -> ${key}`);
      if (!APPLY) { copied++; continue; }
      await putObject(cfg, cfg.publicBucket, key, bytes, { contentType: img.mime, cacheControl: IMMUTABLE_CACHE });
      const back = await getObject(cfg, cfg.publicBucket, key, bytes.length + 1);
      if (!back || sha(back) !== hash) throw new Error(`checksum mismatch after upload (${key})`);
      copied++;
      const { data: row, error: up } = await db.from('profiles').update({ avatar_url: publicUrl }).eq('id', p.id).eq('avatar_url', originalUrl).select('id');
      if (up) throw new Error(`update ${p.id}: ${up.message}`);
      if (!row?.length) { console.log(`  skip ${p.id}: profile changed during copy; URL not updated`); skipped++; continue; }
      updated++;
      audit({ profileId: p.id, handle: p.handle, originalUrl, path, key, publicUrl, sha256: hash, bytes: bytes.length, status: 'ok' });
      console.log(`  ok ${p.id} -> ${publicUrl}`);
    } catch (e) {
      fail(`${p.id}: ${e.message}`);
      audit({ profileId: p.id, status: 'failed', error: e.message, path });
    }
  }
  console.log(JSON.stringify({ profiles: targets.length, copied, updated, skipped, applied: APPLY }));
  console.log('Supabase originals were NOT deleted or changed. State:', STATE);
}

run().catch((e) => { console.error(e.message); process.exit(1); });

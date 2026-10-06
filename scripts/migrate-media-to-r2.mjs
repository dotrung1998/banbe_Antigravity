#!/usr/bin/env node
// Copies ELIGIBLE, PUBLIC legacy Supabase media to Cloudflare R2 (phase one).
// See .claude/notes/28-r2-hybrid-media.md. SAFE BY DEFAULT:
//   * dry-run unless --apply is passed (dry-run does no downloads and no writes)
//   * --apply requires an explicit allowlist (--event-ids / --organizer-ids) or --all
//   * originals in Supabase Storage are NEVER deleted or modified; legacy columns are never rewritten
//   * each object is copied, read back and checksummed BEFORE any reference (*_r2_ref) is set
//   * resumable: finished items are skipped (state file + media_assets legacy_* unique index)
//   * --rollback nulls *_r2_ref for migrated assets (clients fall back to the untouched legacy copy)
//
// Eligible = event photos whose event is status IN (live,ended,cancelled) AND visibility='public'
//            and whose bucket is the public 'event-photos'; organizer profile photos.
// NEVER: draft/review/invite-only events, stories, chat/dispute/payment/refund files, avatars.
//
// Needs: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, R2_* and MEDIA_PUBLIC_BASE_URL (see .env.example),
//        macOS `sips` for resizing. Usage:
//   node scripts/migrate-media-to-r2.mjs                              # dry-run, everything eligible
//   node scripts/migrate-media-to-r2.mjs --apply --event-ids e1,e2    # real copy for two events
//   node scripts/migrate-media-to-r2.mjs --apply --organizer-ids o1
//   node scripts/migrate-media-to-r2.mjs --rollback [--event-ids e1]  # drop R2 pointers
import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, appendFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { inspectImage } from '../api/_lib/imageSafe.js';
import { r2Config, putObject, getObject } from '../api/_lib/r2.js';
import { VARIANTS, publicKey, refOf, IMMUTABLE_CACHE, eventIsPublic } from '../api/_lib/media.js';

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const opt = (n) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : null; };
const list = (n) => (opt(n) || '').split(',').map((s) => s.trim()).filter(Boolean);
const APPLY = flag('apply'), ROLLBACK = flag('rollback'), ALL = flag('all');
const LIMIT = Number(opt('limit') || 0) || Infinity;
const STATE = opt('state') || '.migration-state/media-r2.jsonl';
const eventIds = list('event-ids'), orgIds = list('organizer-ids');

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY required'); process.exit(2); }
const admin = createClient(url, key, { auth: { persistSession: false } });
const cfg = r2Config();
if (APPLY && (!cfg.ok || !cfg.publicBaseUrl)) { console.error('R2_* and MEDIA_PUBLIC_BASE_URL required for --apply', cfg.missing || ''); process.exit(2); }
if (APPLY && !ALL && !eventIds.length && !orgIds.length) { console.error('--apply needs --event-ids / --organizer-ids (or --all)'); process.exit(2); }

const done = new Set();
if (existsSync(STATE)) for (const l of readFileSync(STATE, 'utf8').split('\n').filter(Boolean)) { const r = JSON.parse(l); if (r.status === 'ok') done.add(r.id); }
const audit = (rec) => { mkdirSafe(STATE); appendFileSync(STATE, JSON.stringify({ at: new Date().toISOString(), ...rec }) + '\n'); };
function mkdirSafe(p) { execFileSync('mkdir', ['-p', p.split('/').slice(0, -1).join('/') || '.']); }
const sha = (b) => createHash('sha256').update(b).digest('hex');
const must = ({ data, error }) => { if (error) throw new Error(error.message); return data; };

async function rollback() {
  let n = 0;
  let q = admin.from('media_assets').select('*').eq('source', 'migration').eq('status', 'published');
  if (eventIds.length) q = q.in('event_id', eventIds);
  if (orgIds.length) q = q.in('organizer_id', orgIds);
  for (const a of must(await q)) {
    const ref = refOf(a.scope, a.id, a.ext);
    console.log(`${APPLY ? 'rollback' : 'would rollback'} ${ref}`);
    if (!APPLY) continue;
    must(await admin.from('event_photos').update({ r2_ref: null }).eq('r2_ref', ref));
    must(await admin.from('events').update({ cover_r2_ref: null }).eq('cover_r2_ref', ref));
    must(await admin.from('organizers').update({ avatar_r2_ref: null }).eq('avatar_r2_ref', ref));
    must(await admin.from('media_assets').update({ status: 'failed' }).eq('id', a.id));   // objects stay in R2 until purged deliberately
    audit({ id: a.legacy_path, status: 'rolled-back', ref }); n++;
  }
  console.log(`${n} asset(s) rolled back${APPLY ? '' : ' (dry-run: pass --apply)'}; legacy Supabase copies were never touched.`);
}

function makeVariants(buf, ext) {
  const dir = mkdtempSync(join(tmpdir(), 'r2mig-'));
  try {
    const src = join(dir, `src.${ext}`); writeFileSync(src, buf);
    const out = {};
    for (const [name, cap] of Object.entries(VARIANTS)) {
      const dst = join(dir, `${name}.${ext}`);
      const sipsArgs = ['-Z', String(cap.maxEdge), src, '--out', dst];
      if (ext === 'jpg') sipsArgs.push('-s', 'format', 'jpeg', '-s', 'formatOptions', name === 'thumb' ? '70' : '82');
      execFileSync('sips', sipsArgs, { stdio: 'ignore' });
      // same gatekeeper the live API uses: real format/dimensions, metadata stripped
      out[name] = inspectImage(readFileSync(dst), { maxBytes: cap.maxBytes * 4, maxLongEdge: cap.maxEdge });
      if (out[name].data.length > cap.maxBytes) throw new Error(`variant ${name} too large (${out[name].data.length})`);
    }
    return out;
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

async function copyOne({ bucket, path, kind, scope, eventId, organizerId, label }) {
  const id = `${bucket}/${path}`;
  if (done.has(id)) return 'skipped-done';
  const dup = must(await admin.from('media_assets').select('id,status').eq('legacy_bucket', bucket).eq('legacy_path', path).neq('status', 'deleted').maybeSingle());
  if (dup?.status === 'published') { audit({ id, status: 'ok', note: 'already migrated' }); return 'skipped-done'; }

  const { data: blob, error } = await admin.storage.from(bucket).download(path);
  if (error || !blob) throw new Error(`download failed: ${error?.message}`);
  const original = Buffer.from(await blob.arrayBuffer());
  const originalSha = sha(original);
  const head = inspectImage(original, { maxBytes: 60 * 1024 * 1024, maxLongEdge: 20000, maxPixels: 200_000_000 });
  if (head.ext === 'webp') throw new Error('webp source not supported by sips; skipped');
  const variants = makeVariants(original, head.ext);

  const assetId = dup?.id || randomUUID();
  const ref = refOf(scope, assetId, head.ext);
  const stored = {};
  for (const [name, v] of Object.entries(variants)) {
    const k = publicKey(scope, assetId, name, head.ext);
    await putObject(cfg, cfg.publicBucket, k, v.data, { contentType: v.mime, cacheControl: IMMUTABLE_CACHE });
    const back = await getObject(cfg, cfg.publicBucket, k, VARIANTS[name].maxBytes + 1);          // verify BEFORE switching refs
    if (!back || sha(back) !== sha(v.data)) throw new Error(`checksum mismatch after upload (${name})`);
    stored[name] = { key: k, bytes: v.data.length, w: v.width, h: v.height, sha256: sha(v.data) };
  }

  if (!dup) {
    must(await admin.from('media_assets').insert({
      id: assetId, kind, scope, event_id: eventId, organizer_id: organizerId, owner_user_id: await ownerOf(eventId, organizerId),
      ext: head.ext, status: 'pending', source: 'migration', legacy_bucket: bucket, legacy_path: path, legacy_sha256: originalSha,
      variants: stored, declared: {},
    }));
  }
  return { assetId, ref, stored, originalSha, label, id };
}

async function ownerOf(eventId, organizerId) {
  const orgId = organizerId || must(await admin.from('events').select('organizer_id').eq('id', eventId).maybeSingle())?.organizer_id;
  const o = must(await admin.from('organizers').select('owner_id,user_id').eq('id', orgId).maybeSingle());
  const u = o?.owner_id || o?.user_id;
  if (!u) throw new Error('no owner for ' + orgId);
  return u;
}

async function publish(res) {   // reference switch: only after copy + checksum verification
  must(await admin.from('media_assets').update({ status: 'published', published_at: new Date().toISOString() }).eq('id', res.assetId));
}

async function run() {
  if (ROLLBACK) return rollback();
  const report = { candidates: 0, migrated: 0, skipped: 0, failed: 0, bytesLegacy: 0 };
  const work = [];

  // --- event photos ---
  let evQ = admin.from('events').select('id,status,visibility,cover_image,organizer_id');
  if (eventIds.length) evQ = evQ.in('id', eventIds);
  const events = must(await evQ).filter(eventIsPublic);
  for (const ev of events) {
    const photos = must(await admin.from('event_photos').select('id,storage_path,r2_ref').eq('event_id', ev.id).is('r2_ref', null));
    for (const p of photos) {
      if (p.storage_path.startsWith('event-photos-private/') || p.storage_path.startsWith('r2:')) continue;   // restricted / already R2
      const path = p.storage_path.replace(/^event-photos\//, '');
      work.push({ bucket: 'event-photos', path, kind: 'event_photo', scope: `ev-${ev.id}`, eventId: ev.id, organizerId: null, label: `event ${ev.id}`, apply: async (res) => {
        const r = await admin.from('event_photos').update({ r2_ref: res.ref }).eq('id', p.id).eq('storage_path', p.storage_path).select('id');   // compare-and-set
        if (!must(r)?.length) throw new Error('row changed during migration; ref not set');
        if (ev.cover_image === p.storage_path) must(await admin.from('events').update({ cover_r2_ref: res.ref }).eq('id', ev.id).eq('cover_image', p.storage_path));
      } });
    }
  }
  // --- organizer profile photos ---
  if (!eventIds.length || orgIds.length) {
    let oQ = admin.from('organizers').select('id,avatar_path,avatar_r2_ref').is('avatar_r2_ref', null).neq('avatar_path', '');
    if (orgIds.length) oQ = oQ.in('id', orgIds);
    for (const o of must(await oQ)) {
      if (!o.avatar_path || o.avatar_path.startsWith('r2:')) continue;
      work.push({ bucket: 'organizer-photos', path: o.avatar_path, kind: 'organizer_avatar', scope: `org-${o.id}`, eventId: null, organizerId: o.id, label: `organizer ${o.id}`, apply: async (res) => {
        const r = await admin.from('organizers').update({ avatar_r2_ref: res.ref }).eq('id', o.id).eq('avatar_path', o.avatar_path).select('id');
        if (!must(r)?.length) throw new Error('row changed during migration; ref not set');
      } });
    }
  }

  report.candidates = work.length;
  console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'}: ${work.length} eligible object(s) (public events + organizer photos).`);
  for (const w of work.slice(0, LIMIT)) {
    if (!APPLY) { console.log(`  would copy ${w.bucket}/${w.path}  [${w.label}]`); continue; }
    try {
      const res = await copyOne(w);
      if (typeof res === 'string') { report.skipped++; continue; }
      await w.apply(res);
      await publish(res);
      audit({ id: res.id, status: 'ok', ref: res.ref, originalSha256: res.originalSha, variants: res.stored });
      report.migrated++;
      console.log(`  ok ${res.id} -> ${res.ref}`);
    } catch (e) {
      report.failed++;
      audit({ id: `${w.bucket}/${w.path}`, status: 'failed', error: e.message });
      console.error(`  FAILED ${w.bucket}/${w.path}: ${e.message}`);
    }
  }
  console.log(JSON.stringify(report));
  console.log('Originals in Supabase Storage were NOT modified or deleted. Audit log:', STATE);
  if (!APPLY) console.log('Dry-run only. Re-run with --apply and an allowlist to copy.');
}
run().catch((e) => { console.error(e.message); process.exit(1); });

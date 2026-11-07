#!/usr/bin/env node
// Recompresses EXISTING oversized public photos in place on Supabase Storage (no Cloudflare needed).
// Companion to scripts/migrate-media-to-r2.mjs (which also shrinks, but moves to R2). Use this one when R2
// isn't set up yet: it cuts per-view bytes and, because each new object is uploaded with a 1-year
// Cache-Control, also fixes the old 1h-header objects described in .claude/notes/22-supabase-bandwidth-optimization.md.
// SAFE BY DEFAULT:
//   * dry-run unless --apply (dry-run lists candidates only: no downloads, no writes)
//   * never overwrites: the compressed copy goes to a NEW path; the original is kept (rollback + --purge later)
//   * the DB reference (event_photos.storage_path / events.cover_image / organizers.avatar_path) is switched with a
//     compare-and-set only after the new object uploaded and read back byte-identical
//   * resumable (state file), skips rows already on R2 (r2_ref / 'r2:' prefix), private/invite-only buckets, and
//     anything that wouldn't shrink by at least --min-saving (default 15%)
// Needs: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, macOS `sips`. Usage:
//   node scripts/compress-supabase-media.mjs                          # dry-run
//   node scripts/compress-supabase-media.mjs --apply --limit 5        # try five first
//   node scripts/compress-supabase-media.mjs --apply
//   node scripts/compress-supabase-media.mjs --rollback [--apply]     # point rows back at the originals
//   node scripts/compress-supabase-media.mjs --purge --older-than-days 7 [--apply]   # delete originals once confirmed good
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, appendFileSync, existsSync, rmSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import { inspectImage } from '../api/_lib/imageSafe.js';

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
const opt = (n, d = null) => { const i = args.indexOf(`--${n}`); return i >= 0 ? args[i + 1] : d; };
const APPLY = flag('apply'), ROLLBACK = flag('rollback'), PURGE = flag('purge');
const LIMIT = Number(opt('limit', 0)) || Infinity;
const MIN_BYTES = Number(opt('min-bytes', 400 * 1024));       // below this the file is already fine
const MIN_SAVING = Number(opt('min-saving', 0.15));
const OLDER_DAYS = Number(opt('older-than-days', 7));
const STATE = opt('state', '.migration-state/compress-supabase.jsonl');
const BUDGETS = { 'event-photos': { maxEdge: 1600, quality: 82 }, 'organizer-photos': { maxEdge: 512, quality: 82 } };
const CACHE = '31536000';

const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) { console.error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY required'); process.exit(2); }
const admin = createClient(url, key, { auth: { persistSession: false } });
const must = ({ data, error }) => { if (error) throw new Error(error.message); return data; };
const sha = (b) => createHash('sha256').update(b).digest('hex');
const mb = (n) => (n / 1048576).toFixed(2) + 'MB';

const log = () => (existsSync(STATE) ? readFileSync(STATE, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : []);
const audit = (rec) => { mkdirSync(dirname(STATE), { recursive: true }); appendFileSync(STATE, JSON.stringify({ at: new Date().toISOString(), ...rec }) + '\n'); };
const doneKeys = new Set(log().filter((r) => r.status === 'ok').map((r) => r.key));

function shrink(buf, ext, { maxEdge, quality }) {
  const dir = mkdtempSync(join(tmpdir(), 'cmp-'));
  try {
    const src = join(dir, `src.${ext}`), dst = join(dir, 'out.jpg');
    writeFileSync(src, buf);
    execFileSync('sips', ['-Z', String(maxEdge), src, '--out', dst, '-s', 'format', 'jpeg', '-s', 'formatOptions', String(quality)], { stdio: 'ignore' });
    // same gatekeeper the live API uses: real format/dimensions, metadata (EXIF/GPS) stripped
    return inspectImage(readFileSync(dst), { maxBytes: buf.length, maxLongEdge: maxEdge });
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

const newPathFor = (path) => `${path.replace(/\/[^/]*$/, '')}${path.includes('/') ? '/' : ''}opt-${Date.now()}-${path.split('/').pop().replace(/\.[^.]+$/, '')}.jpg`;

async function candidates() {
  const out = [];
  const photos = must(await admin.from('event_photos').select('id,event_id,storage_path,r2_ref'));
  for (const p of photos) {
    if (p.r2_ref || !p.storage_path || p.storage_path.startsWith('r2:') || p.storage_path.startsWith('event-photos-private/')) continue;
    out.push({ bucket: 'event-photos', path: p.storage_path.replace(/^event-photos\//, ''), prefix: p.storage_path.startsWith('event-photos/') ? 'event-photos/' : '', table: 'event_photos', id: p.id, col: 'storage_path', current: p.storage_path, eventId: p.event_id });
  }
  const orgs = must(await admin.from('organizers').select('id,avatar_path,avatar_r2_ref'));
  for (const o of orgs) {
    if (o.avatar_r2_ref || !o.avatar_path || o.avatar_path.startsWith('r2:')) continue;
    out.push({ bucket: 'organizer-photos', path: o.avatar_path, prefix: '', table: 'organizers', id: o.id, col: 'avatar_path', current: o.avatar_path });
  }
  return out.filter((c) => !/(^|\/)opt-\d+-/.test(c.path));
}

async function sizeOf(bucket, path) {
  const dir = path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : '';
  const name = path.split('/').pop();
  const rows = must(await admin.storage.from(bucket).list(dir, { search: name, limit: 5 }));
  return rows.find((r) => r.name === name)?.metadata?.size ?? null;
}

async function compressOne(c) {
  const k = `${c.bucket}/${c.path}`;
  if (doneKeys.has(k)) return 'skipped-done';
  const { data: blob, error } = await admin.storage.from(c.bucket).download(c.path);
  if (error || !blob) throw new Error(`download failed: ${error?.message}`);
  const original = Buffer.from(await blob.arrayBuffer());
  if (original.length < MIN_BYTES) { audit({ key: k, status: 'skip-small', bytes: original.length }); return 'skipped-small'; }
  const head = inspectImage(original, { maxBytes: 60 * 1024 * 1024, maxLongEdge: 20000, maxPixels: 200_000_000 });
  if (head.ext === 'webp') throw new Error('webp source not supported by sips; skipped');
  const out = shrink(original, head.ext, BUDGETS[c.bucket]);
  if (out.data.length > original.length * (1 - MIN_SAVING)) { audit({ key: k, status: 'skip-small-gain', before: original.length, after: out.data.length }); return 'skipped-gain'; }

  const newPath = newPathFor(c.path);
  must(await admin.storage.from(c.bucket).upload(newPath, out.data, { contentType: 'image/jpeg', cacheControl: CACHE, upsert: false }));
  const { data: back, error: e2 } = await admin.storage.from(c.bucket).download(newPath);   // verify BEFORE switching the reference
  if (e2 || !back || sha(Buffer.from(await back.arrayBuffer())) !== sha(out.data)) throw new Error('read-back mismatch');

  const newRef = `${c.prefix}${newPath}`;
  const r = await admin.from(c.table).update({ [c.col]: newRef }).eq('id', c.id).eq(c.col, c.current).select('id');   // compare-and-set
  if (!must(r)?.length) throw new Error('row changed during compression; reference not switched');
  if (c.table === 'event_photos') must(await admin.from('events').update({ cover_image: newRef }).eq('id', c.eventId).eq('cover_image', c.current));
  audit({ key: k, status: 'ok', table: c.table, id: c.id, col: c.col, eventId: c.eventId || null, oldRef: c.current, newRef, bucket: c.bucket, oldPath: c.path, newPath, before: original.length, after: out.data.length });
  return { before: original.length, after: out.data.length, newRef };
}

async function rollback() {
  let n = 0;
  for (const r of log().filter((x) => x.status === 'ok' && !x.rolledBack)) {
    console.log(`${APPLY ? 'rollback' : 'would rollback'} ${r.table}.${r.col} ${r.id}: ${r.newRef} -> ${r.oldRef}`);
    if (!APPLY) continue;
    must(await admin.from(r.table).update({ [r.col]: r.oldRef }).eq('id', r.id).eq(r.col, r.newRef));
    if (r.table === 'event_photos' && r.eventId) must(await admin.from('events').update({ cover_image: r.oldRef }).eq('id', r.eventId).eq('cover_image', r.newRef));
    audit({ ...r, rolledBack: true, status: 'rolled-back' }); n++;
  }
  console.log(`${n} reference(s) restored${APPLY ? '' : ' (dry-run: pass --apply)'}. Compressed copies stay in Storage.`);
}

async function purge() {
  const cutoff = Date.now() - OLDER_DAYS * 86400000;
  const rolled = new Set(log().filter((x) => x.rolledBack).map((x) => x.key));
  const purged = new Set(log().filter((x) => x.status === 'purged').map((x) => x.key));
  let n = 0, freed = 0;
  for (const r of log().filter((x) => x.status === 'ok' && !rolled.has(x.key) && !purged.has(x.key) && new Date(x.at).getTime() < cutoff)) {
    // only delete the original if NOTHING references it any more
    const still = must(await admin.from(r.table).select('id').eq(r.col, r.oldRef).limit(1));
    if (still.length) { console.log(`keep ${r.oldRef} (still referenced)`); continue; }
    console.log(`${APPLY ? 'delete' : 'would delete'} ${r.bucket}/${r.oldPath} (${mb(r.before)})`);
    if (!APPLY) continue;
    must(await admin.storage.from(r.bucket).remove([r.oldPath]));
    audit({ key: r.key, status: 'purged', bytes: r.before }); n++; freed += r.before;
  }
  console.log(`${n} original(s) deleted, ${mb(freed)} freed${APPLY ? '' : ' (dry-run: pass --apply)'}.`);
}

async function run() {
  if (ROLLBACK) return rollback();
  if (PURGE) return purge();
  const all = (await candidates()).filter((c) => !doneKeys.has(`${c.bucket}/${c.path}`));
  console.log(`${APPLY ? 'APPLY' : 'DRY-RUN'}: ${all.length} candidate object(s) (>= ${mb(MIN_BYTES)} each, public buckets only).`);
  const report = { candidates: all.length, compressed: 0, skipped: 0, failed: 0, savedBytes: 0 };
  for (const c of all.slice(0, LIMIT)) {
    if (!APPLY) {
      const size = await sizeOf(c.bucket, c.path).catch(() => null);
      if (size != null && size < MIN_BYTES) { report.skipped++; continue; }
      console.log(`  would compress ${c.bucket}/${c.path}${size != null ? `  (${mb(size)})` : ''}`);
      continue;
    }
    try {
      const res = await compressOne(c);
      if (typeof res === 'string') { report.skipped++; continue; }
      report.compressed++; report.savedBytes += res.before - res.after;
      console.log(`  ok ${c.bucket}/${c.path}: ${mb(res.before)} -> ${mb(res.after)}`);
    } catch (e) {
      report.failed++; audit({ key: `${c.bucket}/${c.path}`, status: 'failed', error: e.message });
      console.error(`  FAILED ${c.bucket}/${c.path}: ${e.message}`);
    }
  }
  console.log(JSON.stringify({ ...report, savedMB: +(report.savedBytes / 1048576).toFixed(2) }));
  console.log('Originals were NOT modified or deleted. State/rollback log:', STATE);
  if (!APPLY) console.log('Dry-run only. Re-run with --apply (try --limit 5 first). Delete originals later with --purge.');
}
run().catch((e) => { console.error(e.message); process.exit(1); });

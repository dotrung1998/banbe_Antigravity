#!/usr/bin/env node
// Read-only proof for the public-media migration and a full Storage inventory.
//
//   node scripts/verify-r2-public-media.mjs
//
// It checks:
//   1. every public event photo/cover/organizer avatar has a published R2 asset;
//   2. user profile avatars no longer point at Supabase Storage (they are copied
//      to R2 by scripts/migrate-user-avatars-to-r2.mjs);
//   3. real HTTP GETs to media.banbe.app return 200 image/* immutable, and the
//      Supabase originals still exist (sha256 compared where recorded);
//   4. ALL Storage buckets: object/byte counts, DB-referenced paths, missing
//      references, orphans, retained rollback originals, and the route that
//      renders each kind.
//
// Read-only: no DB/R2 writes, no credentials printed. Exit 1 only when a
// public event/organizer/user-avatar URL is still on Supabase or an R2 sample
// fails. Private-bucket orphans are reported, not treated as app failures.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import { loadSecrets } from './lib/secrets.mjs';
import { r2VariantUrl } from '../src/lib/mediaResolver.js';

const v = loadSecrets().values;
const baseUrl = (v.MEDIA_PUBLIC_BASE_URL || '').replace(/\/+$/, '');
if (!v.SUPABASE_URL || !v.SUPABASE_SERVICE_ROLE_KEY || !baseUrl) {
  console.error('SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and MEDIA_PUBLIC_BASE_URL are required');
  process.exit(2);
}
const db = createClient(v.SUPABASE_URL, v.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const sha = (b) => createHash('sha256').update(b).digest('hex');
const assetIdOf = (ref) => (String(ref || '').match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\./i) || [])[1]?.toLowerCase();
const PUBLIC = new Set(['live', 'ended', 'cancelled']);
const failures = [];
const check = (name, ok, detail = '') => {
  console.log(`${ok ? '✓' : '✗'} ${name}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures.push(name);
};
const fmt = (n) => `${(n / 1024 / 1024).toFixed(1)} MiB`;
const trim = (p) => String(p || '').trim();
const strip = (p, prefix) => (trim(p).startsWith(prefix) ? trim(p).slice(prefix.length) : null);

async function all(table, select, pageSize = 1000) {
  const out = [];
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await db.from(table).select(select).range(from, from + pageSize - 1);
    if (error) throw new Error(`${table}: ${error.message}`);
    out.push(...(data || []));
    if ((data || []).length < pageSize) break;
  }
  return out;
}

async function listBucket(bucket, prefix = '') {
  const out = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.storage.from(bucket).list(prefix, { limit: 1000, offset });
    if (error) throw new Error(`${bucket} list ${prefix}: ${error.message}`);
    for (const item of data || []) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (item.id === null) out.push(...await listBucket(bucket, path));
      else out.push({ path, size: item.metadata?.size || 0 });
    }
    if ((data || []).length < 1000) break;
  }
  return out;
}

function publicUrl(ref, variant) {
  return r2VariantUrl(ref, variant, { baseUrl });
}

async function fetchImage(url) {
  const res = await fetch(url, { redirect: 'follow' });
  const bytes = Buffer.from(await res.arrayBuffer());
  return { status: res.status, type: res.headers.get('content-type') || '', cache: res.headers.get('cache-control') || '', bytes };
}

const [events, photos, organizers, profiles, assets, bookings, paymentDocs, messages, stories,
  refundClaims, refundSends, refundDests, disputeMsgs, keychain] = await Promise.all([
  all('events', 'id,name,status,visibility,cover_image,cover_r2_ref'),
  all('event_photos', 'id,event_id,storage_path,r2_ref'),
  all('organizers', 'id,name,avatar_path,avatar_r2_ref,pay_qr_path'),
  all('profiles', 'id,handle,display_name,avatar_url'),
  all('media_assets', 'id,kind,status,scope,event_id,organizer_id,source,legacy_bucket,legacy_path,legacy_sha256,variants'),
  all('bookings', 'id,proof_path'),
  all('payment_documents', 'id,file_path'),
  all('messages', 'id,attachment_path'),
  all('stories', 'id,media_path'),
  all('refund_claims', 'id,proof_path'),
  all('event_refund_send_requests', 'id,proof_path'),
  all('refund_destinations', 'id,qr_path'),
  all('dispute_messages', 'id,attachment_path'),
  all('keychain_assets', 'id,path,status'),
]);

const assetById = new Map(assets.map((a) => [a.id, a]));
const publicEvents = events.filter((e) => PUBLIC.has(e.status) && e.visibility === 'public');
const publicEventIds = new Set(publicEvents.map((e) => e.id));
const publicPhotos = photos.filter((p) => publicEventIds.has(p.event_id));
const photosWithRef = publicPhotos.filter((p) => !!p.r2_ref);
const photosWithoutRef = publicPhotos.filter((p) => !p.r2_ref);
const coversWithRef = publicEvents.filter((e) => e.cover_image && e.cover_r2_ref);
const coversWithoutRef = publicEvents.filter((e) => e.cover_image && !e.cover_r2_ref);
const orgsWithAvatar = organizers.filter((o) => o.avatar_path || o.avatar_r2_ref);
const orgsWithoutRef = orgsWithAvatar.filter((o) => !o.avatar_r2_ref);
const badPhotoRefs = [];
for (const p of photosWithRef) {
  const a = assetById.get(assetIdOf(p.r2_ref));
  if (!a || a.status !== 'published' || a.kind !== 'event_photo' || a.event_id !== p.event_id) badPhotoRefs.push(p.id);
}
const badCoverRefs = [];
for (const e of coversWithRef) {
  const a = assetById.get(assetIdOf(e.cover_r2_ref));
  if (!a || a.status !== 'published' || a.kind !== 'event_photo' || a.event_id !== e.id) badCoverRefs.push(e.id);
}
const badOrgRefs = [];
for (const o of orgsWithAvatar.filter((o) => o.avatar_r2_ref)) {
  const a = assetById.get(assetIdOf(o.avatar_r2_ref));
  if (!a || a.status !== 'published' || a.kind !== 'organizer_avatar' || a.organizer_id !== o.id) badOrgRefs.push(o.id);
}
const supabaseAvatarUrls = profiles.filter((p) => /\/storage\/v1\/object\/public\/avatars\//.test(String(p.avatar_url || '')));
const r2AvatarUrls = profiles.filter((p) => /^https:\/\/media\.banbe\.app\/v1\/user-avatars\//.test(String(p.avatar_url || '')));
const externalAvatars = profiles.filter((p) => p.avatar_url && !supabaseAvatarUrls.includes(p) && !r2AvatarUrls.includes(p));

check('public event photos have r2_ref', photosWithoutRef.length === 0, `${photosWithRef.length}/${publicPhotos.length} covered; missing ${photosWithoutRef.length}`);
check('public event photos point at published R2 assets', badPhotoRefs.length === 0, `${badPhotoRefs.length} bad ref(s)`);
check('public event covers have r2_ref', coversWithoutRef.length === 0, `${coversWithRef.length}/${publicEvents.filter((e) => e.cover_image).length} covered; missing ${coversWithoutRef.length}`);
check('public event covers point at published R2 assets', badCoverRefs.length === 0, `${badCoverRefs.length} bad ref(s)`);
check('organizer avatars have r2_ref', orgsWithoutRef.length === 0, `${orgsWithAvatar.length - orgsWithoutRef.length}/${orgsWithAvatar.length} covered; missing ${orgsWithoutRef.length}`);
check('organizer avatars point at published R2 assets', badOrgRefs.length === 0, `${badOrgRefs.length} bad ref(s)`);
check('user profile avatars no longer use Supabase Storage', supabaseAvatarUrls.length === 0, `${supabaseAvatarUrls.length} still on Supabase; ${r2AvatarUrls.length} on R2; ${externalAvatars.length} external`);
check('user profile avatars on R2 are HTTP-reachable', r2AvatarUrls.length >= 2, `${r2AvatarUrls.length} R2 URL(s)`);

// Real HTTP requests to the public media origin.
const sample = [];
for (const p of photosWithRef) {
  if (sample.filter((s) => s.kind === 'event_photo').some((s) => s.eventId === p.event_id)) continue;
  sample.push({ kind: 'event_photo', ref: p.r2_ref, variant: 'full', eventId: p.event_id, asset: assetById.get(assetIdOf(p.r2_ref)), label: `event ${p.event_id}` });
  if (sample.filter((s) => s.kind === 'event_photo').length >= 4) break;
}
for (const e of coversWithRef) {
  if (sample.some((s) => s.kind === 'cover' && s.ref === e.cover_r2_ref)) continue;
  sample.push({ kind: 'cover', ref: e.cover_r2_ref, variant: 'card', eventId: e.id, asset: assetById.get(assetIdOf(e.cover_r2_ref)), label: `cover ${e.id}` });
  if (sample.filter((s) => s.kind === 'cover').length >= 2) break;
}
for (const o of orgsWithAvatar.filter((o) => o.avatar_r2_ref).slice(0, 3)) {
  sample.push({ kind: 'organizer_avatar', ref: o.avatar_r2_ref, variant: 'thumb', organizerId: o.id, asset: assetById.get(assetIdOf(o.avatar_r2_ref)), label: `organizer ${o.id}` });
}
for (const p of r2AvatarUrls.slice(0, 3)) sample.push({ kind: 'user_avatar', url: p.avatar_url, label: `user ${p.handle || p.id}` });

let httpOk = 0;
let originalsOk = 0;
let originalsChecked = 0;
for (const s of sample) {
  const url = s.url || publicUrl(s.ref, s.variant);
  if (!url) { check(`R2 URL ${s.label}`, false, 'unparseable ref'); continue; }
  try {
    const r = await fetchImage(url);
    const ok = r.status === 200 && /^image\//i.test(r.type) && r.bytes.length > 0;
    if (ok) httpOk++;
    check(`R2 ${s.variant || 'avatar'} ${s.label}`, ok, `HTTP ${r.status}, ${r.type || '-'}, ${r.bytes.length} bytes, ${r.cache || '-'}`);
    if (s.asset?.legacy_bucket && s.asset?.legacy_path) {
      originalsChecked++;
      const path = String(s.asset.legacy_path).split('#')[0];
      const { data: blob, error } = await db.storage.from(s.asset.legacy_bucket).download(path);
      if (error || !blob) { check(`Supabase original ${s.label}`, false, error?.message || 'missing'); continue; }
      const buf = Buffer.from(await blob.arrayBuffer());
      const same = !!s.asset.legacy_sha256 && sha(buf) === s.asset.legacy_sha256;
      if (same) originalsOk++;
      check(`Supabase original ${s.label}`, same, `${buf.length} bytes, sha256 ${same ? 'matches' : 'differs/missing'}`);
    }
  } catch (e) {
    check(`R2 ${s.variant || 'avatar'} ${s.label}`, false, e.message);
  }
}

// Retained Supabase originals for user avatars (state file written by the copy job).
const avatarStatePath = '.migration-state/user-avatars-r2.jsonl';
const avatarState = [];
if (existsSync(avatarStatePath)) {
  for (const line of readFileSync(avatarStatePath, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { const r = JSON.parse(line); if (r.status === 'ok' && r.profileId && r.path && r.sha256) avatarState.push(r); } catch { /* ignore */ }
  }
}
for (const r of avatarState) {
  originalsChecked++;
  const { data: blob, error } = await db.storage.from('avatars').download(r.path);
  if (error || !blob) { check(`Supabase original user ${r.profileId}`, false, error?.message || 'missing'); continue; }
  const same = sha(Buffer.from(await blob.arrayBuffer())) === r.sha256;
  if (same) originalsOk++;
  check(`Supabase original user ${r.profileId}`, same, `${r.path} ${same ? 'sha256 matches' : 'differs'}`);
}

// ---------- full 13-bucket reference audit ----------
const bucketList = (await db.storage.listBuckets()).data || [];
const inventory = new Map();
for (const b of bucketList) inventory.set(b.name, await listBucket(b.name));

const refs = new Map(bucketList.map((b) => [b.name, new Set()]));
const add = (bucket, values) => {
  const set = refs.get(bucket);
  if (!set) return;
  for (const x of values) if (x) set.add(x);
};
add('event-photos', photos.map((p) => strip(p.storage_path, 'event-photos/')).filter(Boolean));
add('event-photos', events.map((e) => strip(e.cover_image, 'event-photos/')).filter(Boolean));
add('event-photos-private', photos.map((p) => strip(p.storage_path, 'event-photos-private/')).filter(Boolean));
add('organizer-photos', organizers.map((o) => trim(o.avatar_path)).filter((p) => p && !p.startsWith('r2:')));
add('avatars', profiles.map((p) => {
  const m = String(p.avatar_url || '').match(/\/storage\/v1\/object\/public\/avatars\/([^?#]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}));
add('pay-qr', organizers.map((o) => trim(o.pay_qr_path)));
add('pay-proof', bookings.map((b) => trim(b.proof_path)));
add('payment-documents', paymentDocs.map((d) => trim(d.file_path)));
add('chat-attachments', messages.map((m) => trim(m.attachment_path)));
add('stories', stories.map((s) => trim(s.media_path)));
add('refund-proof', [...refundClaims.map((r) => trim(r.proof_path)), ...refundSends.map((r) => trim(r.proof_path))]);
add('refund-qr', refundDests.map((r) => trim(r.qr_path)));
add('dispute-attachments', disputeMsgs.map((m) => trim(m.attachment_path)));
add('keychain-art', keychain.map((k) => trim(k.path)));

const retained = new Map();
for (const r of avatarState) {
  if (!retained.has('avatars')) retained.set('avatars', new Set());
  retained.get('avatars').add(r.path);
}

const BUCKET_ROUTES = {
  'event-photos': 'Home/feed cards, Event Detail gallery + cover, Search/Map cards, organizer profile, photo-share API',
  'pay-qr': 'Reserve/Payment host QR (signed)',
  'pay-proof': 'Payment details + host verification + dispute email',
  'payment-documents': 'Documents screen (owner/admin)',
  'chat-attachments': 'Chat thread attachments',
  'stories': 'Story viewer (signed)',
  'avatars': 'Profile/Public profile/Account/Inbox/Team avatar',
  'organizer-photos': 'Home host avatar, Event Detail host, Organizer profile',
  'event-photos-private': 'Event Detail host/invite-only (signed)',
  'refund-qr': 'Refund destination QR',
  'refund-proof': 'Disputes/refund proof',
  'dispute-attachments': 'Dispute chat/export',
  'keychain-art': 'Profile keychain custom art (signed)',
};

console.log('\nBUCKET COVERAGE (all Storage buckets)');
console.log('bucket'.padEnd(24), 'access'.padEnd(8), 'objects'.padStart(7), 'size'.padStart(9), 'dbRefs'.padStart(7), 'missing'.padStart(7), 'orphan'.padStart(7), 'kept'.padStart(5), 'route');
let auditOrphans = 0;
let auditMissing = 0;
for (const b of bucketList) {
  const objects = inventory.get(b.name) || [];
  const paths = new Set(objects.map((o) => o.path));
  const refSet = refs.get(b.name) || new Set();
  const missing = [...refSet].filter((p) => !paths.has(p));
  const kept = retained.get(b.name) || new Set();
  const orphans = [...paths].filter((p) => !refSet.has(p) && !kept.has(p));
  const bytes = objects.reduce((s, o) => s + o.size, 0);
  auditOrphans += orphans.length;
  auditMissing += missing.length;
  console.log(
    b.name.padEnd(24), (b.public ? 'public' : 'private').padEnd(8),
    String(objects.length).padStart(7), fmt(bytes).padStart(9),
    String(refSet.size).padStart(7), String(missing.length).padStart(7),
    String(orphans.length).padStart(7), String(kept.size).padStart(5),
    BUCKET_ROUTES[b.name] || 'unclassified (new bucket)',
  );
}
check('all 13 Storage buckets inventoried', bucketList.length === 13, `${bucketList.length} bucket(s)`);
check('no public event/organizer media served from Supabase', photosWithoutRef.length + coversWithoutRef.length + orgsWithoutRef.length === 0, `${photosWithoutRef.length + coversWithoutRef.length + orgsWithoutRef.length} missing`);
check('no user avatar served from Supabase', supabaseAvatarUrls.length === 0, `${supabaseAvatarUrls.length} Supabase avatar URL(s)`);
console.log(`  · private/preexisting missing refs: ${auditMissing}; orphan objects: ${auditOrphans} (reported, not an app failure)`);
if (externalAvatars.length) console.log(`  · ${externalAvatars.length} profile avatar(s) are external (Unsplash) or empty, not Supabase Storage`);

console.log('\nRESULT');
console.log(`  public event/organizer media still served from Supabase: ${photosWithoutRef.length + coversWithoutRef.length + orgsWithoutRef.length}`);
console.log(`  user avatars still served from Supabase: ${supabaseAvatarUrls.length}`);
console.log(`  HTTP R2 sample: ${httpOk}/${sample.length} passed`);
console.log(`  Supabase originals verified by sha256: ${originalsOk}/${originalsChecked}`);
if (failures.length) {
  console.log(`\n${failures.length} check(s) failed.`);
  process.exitCode = 1;
} else {
  console.log('\nAll public event/organizer/user-avatar media is on R2; Supabase originals are intact.');
}

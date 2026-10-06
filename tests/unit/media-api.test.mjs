import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { handleMediaRequest, sweep, publicKey, stagingKey, refOf } from '../../api/_lib/media.js';
import { presignUrl } from '../../api/_lib/r2.js';

// ---- tiny valid images (built in-test) ----
function jpeg({ w = 100, h = 50, exif = false } = {}) {
  const parts = [Buffer.from([0xff, 0xd8])];
  if (exif) parts.push(Buffer.concat([Buffer.from([0xff, 0xe1, 0x00, 0x10]), Buffer.from('Exif\0\0GPS-SECRET', 'latin1').subarray(0, 14)]));
  parts.push(Buffer.from([0xff, 0xdb, 0x00, 0x04, 0x00, 0x00]));
  const sof = Buffer.alloc(8 + 1); // length 11 total incl. 2 length bytes
  const seg = Buffer.concat([Buffer.from([0xff, 0xc0, 0x00, 0x0b, 0x08]), Buffer.from([h >> 8, h & 255, w >> 8, w & 255]), Buffer.from([0x01, 0x01, 0x11, 0x00])]);
  parts.push(seg, Buffer.from([0xff, 0xda, 0x00, 0x04, 0x00, 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 0xff, 0xd9]));
  void sof;
  return Buffer.concat(parts);
}

function makeCtx({ env = { MEDIA_R2_UPLOADS: 'on' }, events = {}, orgs = {}, admins = [] } = {}) {
  const store = { assets: new Map(), photos: [], covers: {}, avatars: {}, staging: new Map(), pub: new Map(), purged: [], privateUploads: [] };
  const ctx = {
    env,
    auth: {
      verify: async (t) => ({ tokA: 'userA', tokB: 'userB', tokAdmin: 'admin1' }[t] || null),
      gate: async () => true,
    },
    db: {
      getEvent: async (id) => events[id] || null,
      getOrganizer: async (id) => orgs[id] || null,
      isAdmin: async (u) => admins.includes(u),
      countRecentAssets: async (u) => [...store.assets.values()].filter((a) => a.owner_user_id === u).length,
      countPendingAssets: async (u) => [...store.assets.values()].filter((a) => a.owner_user_id === u && a.status === 'pending').length,
      findAssetByIdem: async (u, k) => [...store.assets.values()].find((a) => a.owner_user_id === u && a.idempotency_key === k) || null,
      getAsset: async (id) => store.assets.get(id) || null,
      getAssetByRef: async (ref) => [...store.assets.values()].find((a) => refOf(a.scope, a.id, a.ext) === ref) || null,
      insertAsset: async (row) => { const r = { created_at: new Date().toISOString(), ...row }; store.assets.set(r.id, r); return r; },
      updateAsset: async (id, p) => Object.assign(store.assets.get(id), p),
      findEventPhotoByRef: async (ref) => store.photos.find((p) => p.r2_ref === ref) || null,
      insertEventPhoto: async (row) => { store.photos.push({ id: randomUUID(), ...row }); },
      setEventCoverRef: async (e, ref) => { store.covers[e] = ref; },
      getOrganizerAvatarRef: async (o) => store.avatars[o] || null,
      setOrganizerAvatarRef: async (o, ref) => { store.avatars[o] = ref; },
      listEventPhotosByRef: async (ref) => store.photos.filter((p) => p.r2_ref === ref),
      clearEventPhotoRef: async (id, path) => { const p = store.photos.find((x) => x.id === id); p.r2_ref = null; if (path) p.storage_path = path; },
      clearRefs: async (kind, ref) => { store.photos = store.photos.filter((p) => !(p.r2_ref === ref && p.storage_path === ref)); for (const o of Object.keys(store.avatars)) if (store.avatars[o] === ref) delete store.avatars[o]; },
      clearCoverRef: async () => {},
      replaceCoverPath: async () => {},
      uploadPrivateEventPhoto: async (p, b) => { store.privateUploads.push(p); },
      listStalePending: async () => [...store.assets.values()].filter((a) => a.status === 'pending'),
      listPublishedEventAssets: async () => [...store.assets.values()].filter((a) => a.status === 'published' && a.kind === 'event_photo'),
      listPublishedEventAssetsForEvent: async (e) => [...store.assets.values()].filter((a) => a.status === 'published' && a.event_id === e),
      listOrphanedPublishedAssets: async () => [...store.assets.values()].filter((a) => a.status === 'published' && !a.deleted_at && (
        a.kind === 'organizer_avatar' ? store.avatars[a.organizer_id] !== refOf(a.scope, a.id, a.ext) : !store.photos.some((p) => p.r2_ref === refOf(a.scope, a.id, a.ext)))),
      listDeletionIntents: async () => [...store.assets.values()].filter((a) => a.deleted_at && a.status !== 'deleted'),
    },
    r2: {
      configured: true,
      presignStagingPut: (key) => `https://r2.example/staging/${key}?sig=x`,
      getStaging: async (k) => store.staging.get(k) || null,
      deleteStaging: async (k) => { store.staging.delete(k); },
      putPublic: async (k, b, o) => { store.pub.set(k, { b, o }); },
      getPublic: async (k) => store.pub.get(k)?.b || null,
      deletePublic: async (k) => { store.pub.delete(k); },
      publicUrl: (k) => `https://media.example/${k}`,
      purge: async (urls) => { store.purged.push(...urls); return { ok: true }; },
    },
  };
  return { ctx, store };
}

const publicEvent = { id: 'e1', status: 'live', visibility: 'public', organizer_id: 'o1' };
const baseOrgs = { o1: { id: 'o1', owner_id: 'userA', user_id: null }, o2: { id: 'o2', owner_id: 'userB', user_id: null } };
const call = (ctx, token, body) => handleMediaRequest(ctx, { method: 'POST', headers: { authorization: token ? `Bearer ${token}` : '' }, body });
const files = (type = 'image/jpeg') => ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: type, bytes: 100 }));
const initBody = (o = {}) => ({ op: 'init', kind: 'event_photo', eventId: 'e1', idempotencyKey: randomUUID(), files: files(), ...o });
function stageAll(store, assetId, buf) { for (const v of ['thumb', 'card', 'full']) store.staging.set(stagingKey(assetId, v), buf); }

test('unauthenticated / bad token rejected', async () => {
  const { ctx } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  assert.equal((await call(ctx, '', initBody())).status, 401);
  assert.equal((await call(ctx, 'garbage', initBody())).status, 401);
});

test('flag off => legacy provider, no asset created', async () => {
  const { ctx, store } = makeCtx({ env: {}, events: { e1: publicEvent }, orgs: baseOrgs });
  const r = await call(ctx, 'tokA', initBody());
  assert.deepEqual(r.json, { provider: 'supabase' });
  assert.equal(store.assets.size, 0);
});

test('allowlist flag only enables listed users', async () => {
  const env = { MEDIA_R2_UPLOADS: 'allowlist', MEDIA_R2_UPLOAD_USER_IDS: 'userB' };
  const { ctx } = makeCtx({ env, events: { e1: publicEvent }, orgs: baseOrgs });
  assert.equal((await call(ctx, 'tokA', initBody())).json.provider, 'supabase');
});

test('cross-account: non-owner cannot init for someone else\'s event', async () => {
  const { ctx } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  assert.equal((await call(ctx, 'tokB', initBody())).status, 403);
  assert.equal((await call(ctx, 'tokB', initBody({ eventId: 'missing' }))).status, 403);   // same answer as missing
});

test('draft, review, withdrawn and invite-only events never get R2 uploads', async () => {
  for (const ev of [{ status: 'draft', visibility: 'public' }, { status: 'review', visibility: 'public' }, { status: 'live', visibility: 'invite' }, { status: 'cancelled', visibility: 'invite' }]) {
    const { ctx, store } = makeCtx({ events: { e1: { ...publicEvent, ...ev } }, orgs: baseOrgs });
    const r = await call(ctx, 'tokA', initBody());
    assert.deepEqual(r.json, { provider: 'supabase' }, JSON.stringify(ev));
    assert.equal(store.assets.size, 0);
  }
});

test('init: spoofed/invalid declarations', async () => {
  const { ctx } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  assert.equal((await call(ctx, 'tokA', initBody({ files: files('image/gif') }))).status, 415);
  assert.equal((await call(ctx, 'tokA', initBody({ files: files().map((f) => ({ ...f, bytes: 50 * 1024 * 1024 })) }))).status, 413);
  assert.equal((await call(ctx, 'tokA', initBody({ files: files().slice(0, 2) }))).status, 400);
  assert.equal((await call(ctx, 'tokA', initBody({ idempotencyKey: 'nope' }))).status, 400);
  const mixed = files(); mixed[0].contentType = 'image/png';
  assert.equal((await call(ctx, 'tokA', initBody({ files: mixed }))).status, 400);
});

test('init returns object-scoped presigns; same idempotency key returns same asset', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const body = initBody();
  const a = (await call(ctx, 'tokA', body)).json;
  const b = (await call(ctx, 'tokA', body)).json;
  assert.equal(a.provider, 'r2'); assert.equal(a.assetId, b.assetId); assert.equal(store.assets.size, 1);
  assert.equal(a.uploads.length, 3);
  for (const u of a.uploads) assert.match(u.url, new RegExp(`staging/${a.assetId}/`));
  assert.equal(store.assets.get(a.assetId).owner_user_id, 'userA');   // from JWT, not client
});

test('rate limit', async () => {
  const { ctx } = makeCtx({ env: { MEDIA_R2_UPLOADS: 'on', MEDIA_UPLOADS_PER_HOUR: '2' }, events: { e1: publicEvent }, orgs: baseOrgs });
  await call(ctx, 'tokA', initBody()); await call(ctx, 'tokA', initBody());
  assert.equal((await call(ctx, 'tokA', initBody())).status, 429);
});

test('finalize: happy path, EXIF stripped, idempotent, row created once', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg({ exif: true }));
  const f1 = await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId, setCover: true });
  assert.equal(f1.status, 200);
  const f2 = await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId, setCover: true });
  assert.deepEqual(f2.json, f1.json);
  assert.equal(store.photos.length, 1);
  assert.equal(store.photos[0].r2_ref, f1.json.ref);
  assert.equal(store.covers.e1, f1.json.ref);
  const a = store.assets.get(init.assetId);
  const published = store.pub.get(publicKey(a.scope, a.id, 'full', 'jpg'));
  assert.ok(published); assert.equal(published.o.cacheControl, 'public, max-age=31536000, immutable');
  assert.ok(!published.b.includes(Buffer.from('GPS-SECRET')), 'EXIF/GPS must be stripped');
  assert.equal(store.staging.size, 0, 'staging cleaned');
});

test('finalize: other account cannot finalize/delete; looks like not found', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg());
  assert.equal((await call(ctx, 'tokB', { op: 'finalize', assetId: init.assetId })).status, 404);
  assert.equal((await call(ctx, 'tokB', { op: 'delete', assetId: init.assetId })).status, 404);
});

test('finalize rejects spoofed content: wrong magic, oversize dims, mismatched format', async () => {
  for (const [buf, want] of [
    [Buffer.from('<?php system($_GET[0]); ?>'.padEnd(64, ' ')), 415],
    [jpeg({ w: 4000, h: 3000 }), 422],                                   // exceeds 1600 (and thumb/card) caps
    [Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(40)]), 415 + 7], // PNG declared as JPEG: corrupt/mismatch
  ]) {
    const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
    const init = (await call(ctx, 'tokA', initBody())).json;
    stageAll(store, init.assetId, buf);
    const r = await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId });
    assert.ok(r.status >= 413 && r.status < 500, `status ${r.status}`);
    assert.equal(store.pub.size, 0, 'nothing published');
    assert.equal(store.photos.length, 0);
    assert.equal(store.assets.get(init.assetId).status, 'failed');
  }
  void 0;
});

test('finalize: incomplete upload keeps asset pending (retryable)', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  const r = await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId });
  assert.equal(r.status, 409);
  assert.equal(store.assets.get(init.assetId).status, 'pending');
});

test('privacy change between init and finalize blocks publish', async () => {
  const events = { e1: { ...publicEvent } };
  const { ctx, store } = makeCtx({ events, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg());
  events.e1.visibility = 'invite';
  assert.equal((await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId })).status, 409);
  assert.equal(store.pub.size, 0);
});

test('delete removes public objects, purges CDN, clears refs', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg());
  await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId });
  const r = await call(ctx, 'tokA', { op: 'delete', assetId: init.assetId });
  assert.equal(r.status, 200);
  assert.equal(store.pub.size, 0);
  assert.equal(store.purged.length, 3);
  assert.equal(store.photos.length, 0);
  assert.equal(store.assets.get(init.assetId).status, 'deleted');
});

test('reconcile + sweep: event turning invite-only unpublishes R2 copies and keeps bytes privately', async () => {
  const events = { e1: { ...publicEvent } };
  const { ctx, store } = makeCtx({ events, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg());
  await call(ctx, 'tokA', { op: 'finalize', assetId: init.assetId });
  // still public: reconcile is a no-op, and a stranger cannot trigger it
  assert.equal((await call(ctx, 'tokA', { op: 'reconcile', eventId: 'e1' })).json.unpublished, 0);
  assert.equal((await call(ctx, 'tokB', { op: 'reconcile', eventId: 'e1' })).status, 403);
  events.e1.visibility = 'invite';
  const stats = await sweep(ctx);
  assert.equal(stats.demoted, 1);
  assert.equal(store.pub.size, 0);
  assert.equal(store.purged.length, 3);
  assert.equal(store.privateUploads.length, 1);
  assert.match(store.photos[0].storage_path, /^event-photos-private\//);
  assert.equal(store.photos[0].r2_ref, null);
});

test('stale pending uploads are discarded by sweep', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const init = (await call(ctx, 'tokA', initBody())).json;
  stageAll(store, init.assetId, jpeg());
  await sweep(ctx);
  assert.equal(store.staging.size, 0);
  assert.equal(store.assets.get(init.assetId).status, 'failed');
});

test('organizer avatar: only the organizer owner; replaces and retires previous', async () => {
  const { ctx, store } = makeCtx({ events: {}, orgs: baseOrgs });
  const body = () => ({ op: 'init', kind: 'organizer_avatar', organizerId: 'o1', idempotencyKey: randomUUID(), files: files() });
  assert.equal((await call(ctx, 'tokB', body())).status, 403);
  const a = (await call(ctx, 'tokA', body())).json; stageAll(store, a.assetId, jpeg());
  const fa = await call(ctx, 'tokA', { op: 'finalize', assetId: a.assetId });
  const b = (await call(ctx, 'tokA', body())).json; stageAll(store, b.assetId, jpeg());
  const fb = await call(ctx, 'tokA', { op: 'finalize', assetId: b.assetId });
  assert.equal(store.avatars.o1, fb.json.ref);
  assert.equal(store.assets.get(a.assetId).status, 'deleted');
  assert.notEqual(fa.json.ref, fb.json.ref);
});

// ---- SigV4 correctness: the official AWS documented presigned-GET example ----
test('presignUrl reproduces the AWS documented SigV4 signature', () => {
  const cfg = { endpoint: 'https://examplebucket.s3.amazonaws.com', region: 'us-east-1', accessKeyId: 'AKIAIOSFODNN7EXAMPLE', secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY' };
  const url = presignUrl(cfg, { method: 'GET', bucket: '', key: 'test.txt', expiresIn: 86400, maxExpires: 604800, now: new Date('2013-05-24T00:00:00Z') });
  assert.ok(url.endsWith('X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404'), url);
});

test('presignUrl binds signed headers (changing content-length changes the signature)', () => {
  const cfg = { endpoint: 'https://acct.r2.cloudflarestorage.com', accessKeyId: 'k', secretAccessKey: 's' };
  const now = new Date('2026-10-06T00:00:00Z');
  const mk = (len) => presignUrl(cfg, { method: 'PUT', bucket: 'b', key: 'k/a b.jpg', headers: { 'content-type': 'image/jpeg', 'content-length': len }, now });
  const a = mk('10'), b = mk('11');
  assert.match(a, /X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost/);
  assert.notEqual(a.split('X-Amz-Signature=')[1], b.split('X-Amz-Signature=')[1]);
  assert.ok(a.includes('/b/k/a%20b.jpg?'));
});

test('sweep retires published assets that nothing references (replaced avatar / deleted photo row), keeps referenced ones', async () => {
  const { ctx, store } = makeCtx({ events: { e1: publicEvent }, orgs: baseOrgs });
  const i1 = (await call(ctx, 'tokA', initBody())).json; stageAll(store, i1.assetId, jpeg());
  const f1 = await call(ctx, 'tokA', { op: 'finalize', assetId: i1.assetId });
  const i2 = (await call(ctx, 'tokA', initBody())).json; stageAll(store, i2.assetId, jpeg());
  const f2 = await call(ctx, 'tokA', { op: 'finalize', assetId: i2.assetId });
  store.photos = store.photos.filter((p) => p.r2_ref !== f1.json.ref);          // another client deleted photo 1's row
  const stats = await sweep(ctx);
  assert.equal(stats.orphansRetired, 1);
  assert.equal(store.assets.get(i1.assetId).status, 'deleted');
  assert.equal(store.assets.get(i2.assetId).status, 'published');
  assert.equal([...store.pub.keys()].filter((k) => k.includes(i1.assetId)).length, 0);
  assert.equal([...store.pub.keys()].filter((k) => k.includes(i2.assetId)).length, 3);
  assert.equal((await sweep(ctx)).orphansRetired, 0);
});

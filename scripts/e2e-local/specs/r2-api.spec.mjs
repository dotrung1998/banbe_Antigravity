// REAL /api/media + /api/cron handlers over HTTP, real local Supabase (auth, RLS, storage) and a real
// SigV4-validating S3 server for R2. Browser-less: this is the authorization / validation / lifecycle matrix.
import { test, expect } from '@playwright/test';
import { admin, API, MEDIA, cfg, LOCAL, RUN, makeUser, dropUser, makeOrg, makeEvent, media, setFlags, mockCalls, resetMock, uuid,
  initAndPut, png, jpegStruct, set3, buf, s3Has, s3Get, sha } from './_lib.mjs';
import { createClient } from '@supabase/supabase-js';

test.describe.configure({ mode: 'serial' });
let A, B, ORG_A, ORG_B, LIVE, DRAFT, INVITE;
const created = { assets: [], events: [], orgs: [] };

test.beforeAll(async () => {
  await setFlags({ MEDIA_R2_UPLOADS: 'on', MEDIA_UPLOADS_PER_HOUR: 500, MEDIA_MAX_PENDING: 200, MEDIA_DEMOTE_LEGACY_INVITE: null, MEDIA_SWEEP_STORIES: null });
  A = await makeUser('a'); B = await makeUser('b');
  ORG_A = await makeOrg(A.id, `e2e-r2-orgA-${RUN}`); ORG_B = await makeOrg(B.id, `e2e-r2-orgB-${RUN}`);
  LIVE = await makeEvent(`e2e-r2-live-${RUN}`, ORG_A, 'live', 'public');
  DRAFT = await makeEvent(`e2e-r2-draft-${RUN}`, ORG_A, 'draft', 'public');
  INVITE = await makeEvent(`e2e-r2-inv-${RUN}`, ORG_A, 'live', 'invite');
  created.events.push(LIVE, DRAFT, INVITE); created.orgs.push(ORG_A, ORG_B);
});
test.afterAll(async () => {
  await setFlags({ MEDIA_R2_UPLOADS: 'on', MEDIA_UPLOADS_PER_HOUR: null, MEDIA_MAX_PENDING: null });
  await admin.from('event_photos').delete().in('event_id', created.events);
  await admin.from('media_assets').delete().in('owner_user_id', [A.id, B.id]);
  await admin.from('events').delete().in('id', created.events);
  await admin.from('organizers').delete().in('id', created.orgs);
  for (const u of [A, B]) await dropUser(u);
  await admin.from('email_registrations').delete().like('email', 'e2e-r2-%');
});

const std = () => set3(png(300, 200));
async function publish(user, body, buffers = std(), finalize = {}) {
  const { init, puts } = await initAndPut(user.token, body, buffers);
  expect(init.json.provider, JSON.stringify(init.json)).toBe('r2');
  expect(Object.values(puts)).toEqual([200, 200, 200]);
  const fin = await media(user.token, { op: 'finalize', assetId: init.json.assetId, ...finalize });
  return { init: init.json, fin };
}
const keyOf = (ref, variant) => { const m = /^r2:(.+)\/([0-9a-f-]{36})\.(\w+)$/.exec(ref); return `v1/${m[1]}/${m[2]}/${variant}.${m[3]}`; };

test('authorized upload: presign -> PUT -> finalize -> published, readable on the media domain, row + metadata written', async () => {
  const { init, fin } = await publish(A, { kind: 'event_photo', eventId: LIVE }, { thumb: buf(png(320, 213)), card: buf(png(800, 533)), full: buf(png(1600, 1066)) }, { sortOrder: 3 });
  expect(fin.status).toBe(200);
  const ref = fin.json.ref; created.assets.push(init.assetId);
  expect(ref).toMatch(new RegExp(`^r2:ev-${LIVE}/${init.assetId}\\.png$`));
  for (const v of ['thumb', 'card', 'full']) {
    const res = await fetch(`${MEDIA}/${keyOf(ref, v)}`);
    expect(res.status, v).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/png');
    expect(res.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
  }
  expect(await s3Has(cfg.stagingBucket, `staging/${init.assetId}/thumb`)).toBe(false);                      // staging cleaned
  const { data: asset } = await admin.from('media_assets').select('*').eq('id', init.assetId).single();
  expect(asset).toMatchObject({ status: 'published', provider: 'r2', kind: 'event_photo', owner_user_id: A.id, event_id: LIVE, source: 'upload' });
  expect([asset.variants.thumb.w, asset.variants.card.w, asset.variants.full.w]).toEqual([320, 800, 1600]);   // real dimensions recorded
  const served = Buffer.from(await (await fetch(`${MEDIA}/${asset.variants.full.key}`)).arrayBuffer());
  expect(await sha(served)).toBe(asset.variants.full.sha256);                                                // checksum matches what is served
  const { data: row } = await admin.from('event_photos').select('storage_path, r2_ref, sort_order').eq('event_id', LIVE).eq('r2_ref', ref).single();
  expect(row).toMatchObject({ storage_path: ref, r2_ref: ref, sort_order: 3 });
  const anon = createClient(LOCAL.supabase, process.env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  expect((await anon.from('event_photos').select('r2_ref').eq('r2_ref', ref)).data).toHaveLength(1);       // public event: ref is readable
});

test('EXIF / GPS / text metadata is removed from what is published (JPEG and PNG)', async () => {
  const j = await publish(A, { kind: 'event_photo', eventId: LIVE }, set3(jpegStruct(300, 200, { exif: true }), 'image/jpeg'));
  expect(j.fin.status).toBe(200); created.assets.push(j.init.assetId);
  for (const v of ['thumb', 'card', 'full']) {
    const body = Buffer.from(await (await fetch(`${MEDIA}/${keyOf(j.fin.json.ref, v)}`)).arrayBuffer());
    expect(body.includes(Buffer.from('GPSLatitude')), `jpeg ${v}`).toBe(false);
    expect(body.includes(Buffer.from('Exif')), `jpeg ${v}`).toBe(false);
  }
  const staged = jpegStruct(300, 200, { exif: true }); expect(staged.includes(Buffer.from('GPSLatitude'))).toBe(true);   // the input really had it
  const p = await publish(A, { kind: 'event_photo', eventId: LIVE }, set3(png(300, 200, { text: 'GPSLatitude=10.77' })));
  expect(p.fin.status).toBe(200); created.assets.push(p.init.assetId);
  const pb = Buffer.from(await (await fetch(`${MEDIA}/${keyOf(p.fin.json.ref, 'full')}`)).arrayBuffer());
  expect(pb.includes(Buffer.from('GPSLatitude'))).toBe(false);
});

test('real format validation: declared MIME is never trusted', async () => {
  const cases = [
    ['HTML disguised as PNG', set3(Buffer.from('<html><script>alert(1)</script></html>'.padEnd(64, ' ')), 'image/png'), 415, 'IMAGE_UNSUPPORTED_FORMAT'],
    ['JPEG declared as PNG', set3(jpegStruct(300, 200), 'image/png'), 415, 'IMAGE_FORMAT_MISMATCH'],
    ['truncated PNG', set3(png(300, 200).subarray(0, 80)), 422, 'IMAGE_CORRUPT'],
    ['thumb larger than its 320px cap', { thumb: buf(png(900, 600)), card: buf(png(800, 533)), full: buf(png(1600, 1066)) }, 422, 'IMAGE_DIMENSIONS_EXCEEDED'],
    ['full larger than its 1600px cap', { thumb: buf(png(320, 213)), card: buf(png(800, 533)), full: buf(png(2400, 1600)) }, 422, 'IMAGE_DIMENSIONS_EXCEEDED'],
  ];
  const before = (await admin.from('event_photos').select('id').eq('event_id', LIVE)).data.length;
  for (const [name, buffers, status, code] of cases) {
    const { init, puts } = await initAndPut(A.token, { kind: 'event_photo', eventId: LIVE }, buffers);
    expect(init.json.provider, name).toBe('r2');
    expect(Object.values(puts), name).toEqual([200, 200, 200]);                       // S3 accepts bytes; the SERVER decides
    const fin = await media(A.token, { op: 'finalize', assetId: init.json.assetId });
    expect([fin.status, fin.json.error], name).toEqual([status, code]);
    const { data: a } = await admin.from('media_assets').select('status').eq('id', init.json.assetId).single();
    expect(a.status, name).toBe('failed');
    expect(await s3Has(cfg.publicBucket, keyOf(refOfAsset(init.json.assetId, LIVE, 'png'), 'full')), name).toBe(false);   // nothing published
    expect(await s3Has(cfg.stagingBucket, `staging/${init.json.assetId}/full`), name).toBe(false);                         // staging cleaned
  }
  const { data: rows } = await admin.from('event_photos').select('id').eq('event_id', LIVE);
  expect(rows.length).toBe(before);                                                    // no rejected upload created a photo row
});
const refOfAsset = (id, ev, ext) => `r2:ev-${ev}/${id}.${ext}`;

test('init validation: oversize, unsupported type, mixed formats, missing variants, bad idempotency key', async () => {
  const f = (o = {}) => ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 1000, ...o }));
  const base = { op: 'init', kind: 'event_photo', eventId: LIVE, idempotencyKey: uuid() };
  expect((await media(A.token, { ...base, files: f({ bytes: 50 * 1024 * 1024 }) })).status).toBe(413);
  expect((await media(A.token, { ...base, files: f({ contentType: 'image/gif' }) })).status).toBe(415);
  expect((await media(A.token, { ...base, files: f().slice(0, 2) })).status).toBe(400);
  const mixed = f(); mixed[0].contentType = 'image/jpeg';
  expect((await media(A.token, { ...base, files: mixed })).status).toBe(400);
  expect((await media(A.token, { ...base, idempotencyKey: 'x', files: f() })).status).toBe(400);
  expect((await media(A.token, { ...base, kind: 'story', files: f() })).status).toBe(400);
  expect((await media(A.token, { ...base, eventId: '../etc', files: f() })).status).toBe(400);
});

test('presigned URLs are object-scoped: cannot overwrite another asset, a published key or a different variant', async () => {
  const one = await initAndPut(A.token, { kind: 'event_photo', eventId: LIVE }, std());
  const two = await media(A.token, { op: 'init', kind: 'event_photo', eventId: LIVE, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 123 })) });
  const urlOne = one.init.json.uploads.find((u) => u.variant === 'full');
  const urlTwo = two.json.uploads.find((u) => u.variant === 'full');
  const body = png(300, 200);
  // use asset one's signature against asset two's key, and against the PUBLIC bucket key
  const swapped = urlOne.url.replace(one.init.json.assetId, two.json.assetId);
  expect((await fetch(swapped, { method: 'PUT', headers: urlOne.headers, body })).status).toBe(403);
  const toPublic = urlOne.url.replace('banbe-media-staging', 'banbe-media-public').replace(`staging/${one.init.json.assetId}/full`, `v1/ev-${LIVE}/${one.init.json.assetId}/full.png`);
  expect((await fetch(toPublic, { method: 'PUT', headers: urlOne.headers, body })).status).toBe(403);
  expect((await fetch(urlTwo.url, { method: 'PUT', headers: { ...urlTwo.headers, 'content-length': String(body.length) }, body })).status).toBe(403);   // wrong length vs declared 123
  await media(A.token, { op: 'delete', assetId: one.init.json.assetId }); await media(A.token, { op: 'delete', assetId: two.json.assetId });
});

test('duplicate finalize and retried init are idempotent', async () => {
  const idem = uuid();
  const body = { kind: 'event_photo', eventId: LIVE, idempotencyKey: idem };
  const first = await initAndPut(A.token, body, std());
  const again = await media(A.token, { op: 'init', ...body, files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) });
  expect(again.json.assetId).toBe(first.init.json.assetId);                                                  // same asset, fresh presign
  const f1 = await media(A.token, { op: 'finalize', assetId: first.init.json.assetId });
  const f2 = await media(A.token, { op: 'finalize', assetId: first.init.json.assetId });
  expect(f1.status).toBe(200); expect(f2.json).toEqual(f1.json);
  created.assets.push(first.init.json.assetId);
  expect((await admin.from('event_photos').select('id').eq('r2_ref', f1.json.ref)).data).toHaveLength(1);
  const published = await media(A.token, { op: 'init', ...body, files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) });
  expect(published.json).toMatchObject({ provider: 'r2', alreadyPublished: true, ref: f1.json.ref });
});

test('cross-account and unauthenticated access is refused at every endpoint', async () => {
  const { init } = await initAndPut(A.token, { kind: 'event_photo', eventId: LIVE }, std());
  const id = init.json.assetId;
  const body = { kind: 'event_photo', eventId: LIVE, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) };
  expect((await media(null, { op: 'init', ...body })).status).toBe(401);
  expect((await media('garbage.token.value', { op: 'init', ...body })).status).toBe(401);
  expect((await media(B.token, { op: 'init', ...body })).status).toBe(403);                                  // not the event's organizer
  expect((await media(B.token, { op: 'init', ...body, eventId: 'does-not-exist' })).status).toBe(403);     // indistinguishable from "not yours"
  expect((await media(B.token, { op: 'finalize', assetId: id })).status).toBe(404);
  expect((await media(B.token, { op: 'delete', assetId: id })).status).toBe(404);
  expect((await media(B.token, { op: 'reconcile', eventId: LIVE })).status).toBe(403);
  expect((await media(null, { op: 'finalize', assetId: id })).status).toBe(401);
  expect((await media(null, { op: 'delete', assetId: id })).status).toBe(401);
  expect((await media(A.token, { op: 'nonsense' })).status).toBe(400);
  expect((await fetch(`${API}/api/media`)).status).toBe(405);
  const { data: viaB } = await B.client.from('media_assets').select('id').eq('id', id);
  expect(viaB).toHaveLength(0);                                                                              // RLS: others cannot read asset rows
  await media(A.token, { op: 'delete', assetId: id });
});

test('draft, review and invite-only events never get R2 uploads (server answers legacy provider)', async () => {
  for (const ev of [DRAFT, INVITE]) {
    const r = await media(A.token, { op: 'init', kind: 'event_photo', eventId: ev, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) });
    expect(r.json, ev).toEqual({ provider: 'supabase' });
  }
  const { data } = await admin.from('media_assets').select('id').in('event_id', [DRAFT, INVITE]);
  expect(data).toHaveLength(0);                                                                              // no row, no staging object, no URL issued
});

test('privacy change (public -> invite-only): reconcile removes public objects, purges the CDN, keeps the host\'s copy private', async () => {
  const ev = await makeEvent(`e2e-r2-priv-${RUN}`, ORG_A, 'live', 'public'); created.events.push(ev);
  const { init, fin } = await publish(A, { kind: 'event_photo', eventId: ev }, std(), { setCover: true });
  const ref = fin.json.ref; created.assets.push(init.assetId);
  await admin.from('events').update({ cover_image: ref }).eq('id', ev);
  const url = `${MEDIA}/${keyOf(ref, 'full')}`;
  expect((await fetch(url)).status).toBe(200);
  await resetMock();
  await admin.from('events').update({ visibility: 'invite' }).eq('id', ev);                                  // what set_event_visibility does
  const r = await media(A.token, { op: 'reconcile', eventId: ev });
  expect(r.status).toBe(200); expect(r.json.unpublished).toBe(1);
  expect((await fetch(url)).status).toBe(404);
  for (const v of ['thumb', 'card', 'full']) expect(await s3Has(cfg.publicBucket, keyOf(ref, v)), v).toBe(false);
  const purged = (await mockCalls()).flatMap((c) => c.files);
  expect(purged.sort()).toEqual(['thumb', 'card', 'full'].map((v) => `${MEDIA}/${keyOf(ref, v)}`).sort());  // exact CDN URLs purged
  const { data: row } = await admin.from('event_photos').select('storage_path, r2_ref').eq('event_id', ev).single();
  expect(row.r2_ref).toBeNull();
  expect(row.storage_path).toBe(`event-photos-private/${ev}/${init.assetId}.png`);
  expect(((await admin.storage.from('event-photos-private').download(`${ev}/${init.assetId}.png`)).error)).toBeNull();   // host keeps the photo, privately
  const { data: evRow } = await admin.from('events').select('cover_image, cover_r2_ref').eq('id', ev).single();
  expect(evRow).toEqual({ cover_image: `event-photos-private/${ev}/${init.assetId}.png`, cover_r2_ref: null });
  const anon = createClient(LOCAL.supabase, process.env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  expect((await anon.from('event_photos').select('id').eq('event_id', ev)).data).toHaveLength(0);           // invisible to the public via RLS
  expect((await anon.storage.from('event-photos-private').download(`${ev}/${init.assetId}.png`)).error).toBeTruthy();
  expect((await B.client.storage.from('event-photos-private').download(`${ev}/${init.assetId}.png`)).error).toBeTruthy();
  expect((await admin.from('media_assets').select('status').eq('id', init.assetId).single()).data.status).toBe('deleted');
  expect((await media(A.token, { op: 'init', kind: 'event_photo', eventId: ev, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) })).json).toEqual({ provider: 'supabase' });
});

test('owner delete: objects gone, CDN purged, row removed; repeatable; only the owner may', async () => {
  const { init, fin } = await publish(A, { kind: 'event_photo', eventId: LIVE }, std());
  await resetMock();
  expect((await media(B.token, { op: 'delete', assetId: init.assetId })).status).toBe(404);
  expect((await fetch(`${MEDIA}/${keyOf(fin.json.ref, 'card')}`)).status).toBe(200);
  const d = await media(A.token, { op: 'delete', assetId: init.assetId });
  expect(d.status).toBe(200); expect(d.json.cdnPurged).toBe(true);
  expect((await fetch(`${MEDIA}/${keyOf(fin.json.ref, 'card')}`)).status).toBe(404);
  expect((await mockCalls()).flatMap((c) => c.files)).toHaveLength(3);
  expect((await admin.from('event_photos').select('id').eq('r2_ref', fin.json.ref)).data).toHaveLength(0);
  expect((await media(A.token, { op: 'delete', assetId: init.assetId })).json).toEqual({ ok: true });
});

test('sweep (cron endpoint): demotes assets of events that stopped being public, discards stale uploads, needs the secret', async () => {
  const ev = await makeEvent(`e2e-r2-sweep-${RUN}`, ORG_A, 'live', 'public'); created.events.push(ev);
  const { init, fin } = await publish(A, { kind: 'event_photo', eventId: ev }, std()); created.assets.push(init.assetId);
  const stale = await initAndPut(A.token, { kind: 'event_photo', eventId: LIVE }, std());                    // never finalized
  await admin.from('media_assets').update({ created_at: new Date(Date.now() - 3 * 3600_000).toISOString() }).eq('id', stale.init.json.assetId);
  await admin.from('events').update({ status: 'draft' }).eq('id', ev);                                       // withdrawn, no client call
  expect((await fetch(`${API}/api/cron?job=media-sweep`)).status).toBe(401);
  expect((await fetch(`${API}/api/cron?job=media-sweep`, { headers: { authorization: 'Bearer wrong' } })).status).toBe(401);
  await resetMock();
  const r = await fetch(`${API}/api/cron?job=media-sweep`, { headers: { authorization: 'Bearer local-cron-secret' } });
  const stats = await r.json();
  expect(r.status).toBe(200); expect(stats.demoted).toBeGreaterThanOrEqual(1); expect(stats.orphanedPending).toBeGreaterThanOrEqual(1);
  expect(await s3Has(cfg.publicBucket, keyOf(fin.json.ref, 'full'))).toBe(false);
  expect((await mockCalls()).flatMap((c) => c.files).length).toBeGreaterThanOrEqual(3);
  expect(await s3Has(cfg.stagingBucket, `staging/${stale.init.json.assetId}/full`)).toBe(false);
  expect((await admin.from('media_assets').select('status').eq('id', stale.init.json.assetId).single()).data.status).toBe('failed');
  const again = await (await fetch(`${API}/api/cron?job=media-sweep`, { headers: { authorization: 'Bearer local-cron-secret' } })).json();
  expect(again.demoted).toBe(0);                                                                             // idempotent
});

test('rate limit and pending-upload cap', async () => {
  await setFlags({ MEDIA_UPLOADS_PER_HOUR: 3, MEDIA_MAX_PENDING: 200 });
  const U = await makeUser('rl'); const O = await makeOrg(U.id, `e2e-r2-rl-${RUN}`); const E = await makeEvent(`e2e-r2-rl-ev-${RUN}`, O); created.events.push(E); created.orgs.push(O);
  const go = () => media(U.token, { op: 'init', kind: 'event_photo', eventId: E, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) });
  const codes = []; for (let i = 0; i < 5; i++) codes.push((await go()).status);
  expect(codes).toEqual([200, 200, 200, 429, 429]);
  await setFlags({ MEDIA_UPLOADS_PER_HOUR: 500, MEDIA_MAX_PENDING: 2 });
  expect((await go()).status).toBe(429);                                                                      // 3 pending already >= cap 2
  await setFlags({ MEDIA_UPLOADS_PER_HOUR: 500, MEDIA_MAX_PENDING: 200 });
  await admin.from('media_assets').delete().eq('owner_user_id', U.id); await admin.from('events').delete().eq('id', E); await admin.from('organizers').delete().eq('id', O); await dropUser(U);
});

test('legacy fallback: flag off, allowlist and percent rollout all answer the legacy provider for excluded users', async () => {
  const body = { op: 'init', kind: 'event_photo', eventId: LIVE, idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) };
  await setFlags({ MEDIA_R2_UPLOADS: 'off' });
  expect((await media(A.token, body)).json).toEqual({ provider: 'supabase' });
  await setFlags({ MEDIA_R2_UPLOADS: 'allowlist', MEDIA_R2_UPLOAD_USER_IDS: B.id });
  expect((await media(A.token, { ...body, idempotencyKey: uuid() })).json).toEqual({ provider: 'supabase' });
  await setFlags({ MEDIA_R2_UPLOADS: 'allowlist', MEDIA_R2_UPLOAD_USER_IDS: A.id });
  expect((await media(A.token, { ...body, idempotencyKey: uuid() })).json.provider).toBe('r2');
  await setFlags({ MEDIA_R2_UPLOADS: 'percent', MEDIA_R2_UPLOAD_PERCENT: 0 });
  expect((await media(A.token, { ...body, idempotencyKey: uuid() })).json).toEqual({ provider: 'supabase' });
  await setFlags({ MEDIA_R2_UPLOADS: 'percent', MEDIA_R2_UPLOAD_PERCENT: 100 });
  expect((await media(A.token, { ...body, idempotencyKey: uuid() })).json.provider).toBe('r2');
  await setFlags({ MEDIA_R2_UPLOADS: 'on', MEDIA_R2_UPLOAD_USER_IDS: null, MEDIA_R2_UPLOAD_PERCENT: null });
});

test('organizer avatar: owner only; replacing retires the previous asset and purges it', async () => {
  const body = () => ({ kind: 'organizer_avatar', organizerId: ORG_A });
  const nope = await media(B.token, { op: 'init', ...body(), idempotencyKey: uuid(), files: ['thumb', 'card', 'full'].map((variant) => ({ variant, contentType: 'image/png', bytes: 100 })) });
  expect(nope.status).toBe(403);
  const first = await publish(A, body()); created.assets.push(first.init.assetId);
  expect((await admin.from('organizers').select('avatar_r2_ref').eq('id', ORG_A).single()).data.avatar_r2_ref).toBe(first.fin.json.ref);
  await resetMock();
  const second = await publish(A, body(), set3(png(280, 190, { seed: 9 }))); created.assets.push(second.init.assetId);
  expect((await admin.from('organizers').select('avatar_r2_ref').eq('id', ORG_A).single()).data.avatar_r2_ref).toBe(second.fin.json.ref);
  expect((await fetch(`${MEDIA}/${keyOf(first.fin.json.ref, 'thumb')}`)).status).toBe(404);                 // old one gone
  expect((await fetch(`${MEDIA}/${keyOf(second.fin.json.ref, 'thumb')}`)).status).toBe(200);
  expect((await mockCalls()).flatMap((c) => c.files).length).toBe(3);
});

test('pointer consistency: a client changing the legacy avatar/cover can never leave a stale R2 pointer; orphaned assets are retired by the sweep', async () => {
  // --- avatar: R2 first, then the owner replaces it through the legacy column (what the web/iOS legacy path does) ---
  const org = await makeOrg(A.id, `e2e-r2-ptr-org-${RUN}`); created.orgs.push(org);
  const av = await publish(A, { kind: 'organizer_avatar', organizerId: org }); created.assets.push(av.init.assetId);
  expect((await admin.from('organizers').select('avatar_r2_ref').eq('id', org).single()).data.avatar_r2_ref).toBe(av.fin.json.ref);
  const upd = await A.client.from('organizers').update({ avatar_path: `${org}/avatar-legacy.png` }).eq('id', org).select('avatar_path, avatar_r2_ref');
  expect(upd.error, upd.error?.message).toBeNull();
  expect(upd.data[0]).toEqual({ avatar_path: `${org}/avatar-legacy.png`, avatar_r2_ref: null });                // trigger cleared the stale pointer
  const forged = await A.client.from('organizers').update({ avatar_r2_ref: av.fin.json.ref }).eq('id', org);
  expect(forged.error, 'client must not be able to re-point it').toBeTruthy();
  // --- cover: two R2 photos; switching the cover through the real RPC follows the photo's own ref ---
  const ev = await makeEvent(`e2e-r2-ptr-ev-${RUN}`, org, 'live', 'public'); created.events.push(ev);
  const p1 = await publish(A, { kind: 'event_photo', eventId: ev }, std(), { setCover: true }); created.assets.push(p1.init.assetId);
  const p2 = await publish(A, { kind: 'event_photo', eventId: ev }, set3(png(300, 200, { seed: 9 }))); created.assets.push(p2.init.assetId);
  const cover = async () => (await admin.from('events').select('cover_image, cover_r2_ref').eq('id', ev).single()).data;
  expect((await cover()).cover_r2_ref).toBe(p1.fin.json.ref);
  const r2 = await A.client.rpc('update_event_media_and_details', { p_event_id: ev, p_cover_image: p2.fin.json.ref });
  expect(r2.error, r2.error?.message).toBeNull();
  expect(await cover()).toEqual({ cover_image: p2.fin.json.ref, cover_r2_ref: p2.fin.json.ref });
  const legacyRow = await A.client.from('event_photos').insert({ event_id: ev, storage_path: `event-photos/${ev}/legacy.jpg`, sort_order: 9 });
  expect(legacyRow.error, legacyRow.error?.message).toBeNull();
  const r3 = await A.client.rpc('update_event_media_and_details', { p_event_id: ev, p_cover_image: `event-photos/${ev}/legacy.jpg` });
  expect(r3.error, r3.error?.message).toBeNull();
  expect(await cover()).toEqual({ cover_image: `event-photos/${ev}/legacy.jpg`, cover_r2_ref: null });          // legacy photo has no R2 copy
  // --- the replaced avatar asset + the now-unreferenced photos are orphans: the sweep retires them and purges the CDN ---
  await admin.from('event_photos').delete().eq('r2_ref', p1.fin.json.ref);                                     // host deleted photo 1 elsewhere
  await resetMock();
  const stats = await (await fetch(`${API}/api/cron?job=media-sweep`, { headers: { authorization: 'Bearer local-cron-secret' } })).json();
  expect(stats.orphansRetired).toBeGreaterThanOrEqual(2);
  expect(await s3Has(cfg.publicBucket, keyOf(av.fin.json.ref, 'full'))).toBe(false);                            // old avatar gone
  expect(await s3Has(cfg.publicBucket, keyOf(p1.fin.json.ref, 'full'))).toBe(false);                            // orphaned photo gone
  expect(await s3Has(cfg.publicBucket, keyOf(p2.fin.json.ref, 'full'))).toBe(true);                             // still referenced: untouched
  expect((await mockCalls()).flatMap((c) => c.files).length).toBeGreaterThanOrEqual(6);
});

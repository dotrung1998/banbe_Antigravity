// Header-signed SERVER-SIDE requests (api/_lib/r2.js: getObject/putObject/deleteObject/signedFetch) and presigned
// browser PUTs, verified by a REAL SigV4-validating S3 server (versitygw). Also the "media domain" boundary.
// What this cannot prove: Cloudflare R2's own behaviour (see note 28 "What the local emulator cannot prove").
import { test, expect } from '@playwright/test';
import { cfg, signedFetch, MEDIA, LOCAL } from './_lib.mjs';
import { r2Config, putObject, getObject, deleteObject, presignUrl } from '../../../api/_lib/r2.js';

test.describe.configure({ mode: 'serial' });
const key = (s) => `v1/e2e-s3/${Date.now().toString(36)}/${s}`;

test('header-signed PUT/GET/DELETE round trip, content-type + cache-control stored', async () => {
  const k = key('a.png'), body = Buffer.from('hello-r2');
  await putObject(cfg, cfg.publicBucket, k, body, { contentType: 'image/png', cacheControl: 'public, max-age=31536000, immutable' });
  expect((await getObject(cfg, cfg.publicBucket, k, 1000)).toString()).toBe('hello-r2');
  const r = await signedFetch(cfg, { method: 'GET', bucket: cfg.publicBucket, key: k });
  expect(r.headers.get('content-type')).toBe('image/png');
  expect(r.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
  await deleteObject(cfg, cfg.publicBucket, k);
  expect(await getObject(cfg, cfg.publicBucket, k, 1000)).toBeNull();
  await deleteObject(cfg, cfg.publicBucket, k);            // deleting a missing key is not an error
});

test('keys with spaces, unicode and reserved characters sign correctly', async () => {
  for (const name of ['with space.png', 'ảnh-đẹp.png', 'plus+and&amp=eq(1)!*\'.png', 'a/b/c d/é.png']) {
    const k = key(name);
    await putObject(cfg, cfg.publicBucket, k, Buffer.from(name), { contentType: 'image/png' });
    expect((await getObject(cfg, cfg.publicBucket, k, 1000)).toString()).toBe(name);
    await deleteObject(cfg, cfg.publicBucket, k);
  }
});

test('size cap is enforced when reading', async () => {
  const k = key('big.bin');
  await putObject(cfg, cfg.publicBucket, k, Buffer.alloc(5000, 1), { contentType: 'application/octet-stream' });
  await expect(getObject(cfg, cfg.publicBucket, k, 1000)).rejects.toThrow(/R2_OBJECT_TOO_LARGE/);
  await deleteObject(cfg, cfg.publicBucket, k);
});

test('bad credentials, unsigned and tampered requests are rejected by the server', async () => {
  const bad = { ...cfg, secretAccessKey: 'definitely-wrong' };
  await expect(getObject(bad, cfg.publicBucket, key('x'), 100)).rejects.toThrow(/R2_GET_403/);
  await expect(putObject(bad, cfg.publicBucket, key('x'), Buffer.from('x'), {})).rejects.toThrow(/R2_PUT_403/);
  expect((await fetch(`${LOCAL.s3}/${cfg.publicBucket}/v1/whatever`)).status).toBe(403);                  // unsigned
  // Unknown access key id: real S3/R2 answer 403 InvalidAccessKeyId; this emulator answers 404 instead (a quirk we record, not
  // rely on). What must hold either way: an EXISTING object is never returned to a caller with an unknown key id.
  const k = key('guarded.bin');
  await putObject(cfg, cfg.publicBucket, k, Buffer.from('top-secret'), {});
  const outcome = await getObject({ ...cfg, accessKeyId: 'someone-else' }, cfg.publicBucket, k, 100).catch((e) => e);
  expect(outcome === null || outcome instanceof Error, 'unknown access key id must never receive object bytes').toBe(true);
  await deleteObject(cfg, cfg.publicBucket, k);
});

test('presigned PUT: exact headers work; changed length, swapped key, wrong content-type and expiry are refused', async () => {
  const k = key('staging-thumb');
  const headers = { 'content-type': 'image/png', 'content-length': '3' };
  const url = presignUrl(cfg, { method: 'PUT', bucket: cfg.stagingBucket, key: k, headers });
  expect((await fetch(url, { method: 'PUT', headers, body: Buffer.from('abc') })).status).toBe(200);
  expect((await fetch(url, { method: 'PUT', headers: { ...headers, 'content-length': '4' }, body: Buffer.from('abcd') })).status).toBe(403);
  expect((await fetch(url.replace(k, key('other')), { method: 'PUT', headers, body: Buffer.from('abc') })).status).toBe(403);
  expect((await fetch(url, { method: 'PUT', headers: { ...headers, 'content-type': 'text/html' }, body: Buffer.from('abc') })).status).toBe(403);
  const old = presignUrl(cfg, { method: 'PUT', bucket: cfg.stagingBucket, key: key('old'), headers, expiresIn: 1, now: new Date(Date.now() - 60_000) });
  expect((await fetch(old, { method: 'PUT', headers, body: Buffer.from('abc') })).status).toBe(403);
  const getUrl = presignUrl(cfg, { method: 'GET', bucket: cfg.stagingBucket, key: k });
  expect((await fetch(url.split('?')[0].replace('PUT', 'GET'))).status).toBe(403);                         // no signature at all
  expect((await fetch(getUrl)).status).toBe(200);                                                           // a GET presign is separately valid
  await deleteObject(cfg, cfg.stagingBucket, k);
});

test('media domain model: serves ONLY public-bucket keys under v1/, GET/HEAD only, no listing, never staging', async () => {
  const pub = key('p.png'), stg = `staging/${Date.now()}/x`;
  await putObject(cfg, cfg.publicBucket, pub, Buffer.from('PNGDATA'), { contentType: 'image/png', cacheControl: 'public, max-age=31536000, immutable' });
  await putObject(cfg, cfg.stagingBucket, stg, Buffer.from('SECRET'), { contentType: 'image/png' });
  const ok = await fetch(`${MEDIA}/${pub}`);
  expect(ok.status).toBe(200);
  expect(ok.headers.get('cache-control')).toBe('public, max-age=31536000, immutable');
  expect((await fetch(`${MEDIA}/${pub}`, { method: 'HEAD' })).status).toBe(200);
  expect((await fetch(`${MEDIA}/${stg}`)).status).toBe(404);                               // staging key under the same path
  expect((await fetch(`${MEDIA}/banbe-media-staging/${stg}`)).status).toBe(404);          // bucket-style addressing
  expect((await fetch(`${MEDIA}/`)).status).toBe(404);                                     // no listing
  expect((await fetch(`${MEDIA}/v1/`)).status).toBe(404);
  expect((await fetch(`${MEDIA}/v1/../staging/${Date.now()}/x`)).status).toBe(404);       // traversal
  expect((await fetch(`${MEDIA}/${pub}`, { method: 'PUT', body: 'x' })).status).toBe(405); // read-only
  expect((await fetch(`${MEDIA}/${pub}`, { method: 'DELETE' })).status).toBe(405);
  await deleteObject(cfg, cfg.publicBucket, pub); await deleteObject(cfg, cfg.stagingBucket, stg);
});

test('config: missing R2 settings are reported, never defaulted to real endpoints', () => {
  const none = r2Config({});
  expect(none.ok).toBe(false);
  expect(none.missing).toEqual(expect.arrayContaining(['R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_PUBLIC_BUCKET', 'R2_STAGING_BUCKET']));
});

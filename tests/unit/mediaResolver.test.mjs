import test from 'node:test';
import assert from 'node:assert/strict';
import { r2VariantUrl, resolveMediaUrl, isR2Ref, parseR2Ref, getMediaConfig } from '../../src/lib/mediaResolver.js';

const UUID = '123e4567-e89b-12d3-a456-426614174000';
const EV = '9b2f6a4e-1111-4222-8333-444455556666';
const REF = `r2:ev-${EV}/${UUID}.jpg`;
const BASE = 'https://media.example.com';

test('valid ref builds the immutable variant URL', () => {
  assert.equal(r2VariantUrl(REF, 'card', { baseUrl: BASE }), `${BASE}/v1/ev-${EV}/${UUID}/card.jpg`);
  assert.equal(r2VariantUrl(`r2:org-${EV}/${UUID}.webp`, 'thumb', { baseUrl: `${BASE}//` }), `${BASE}/v1/org-${EV}/${UUID}/thumb.webp`);
  assert.deepEqual(parseR2Ref(REF), { scope: `ev-${EV}`, assetId: UUID, ext: 'jpg' });
  assert.ok(isR2Ref(REF));
});

test('malicious or malformed refs never produce a URL', () => {
  const bad = [
    `r2:ev-../${UUID}.jpg`, `r2:ev-${EV}/../${UUID}.jpg`, `r2:../ev-${EV}/${UUID}.jpg`,
    `r2:usr-${EV}/${UUID}.jpg`, `r2:${EV}/${UUID}.jpg`,
    `r2:ev-${EV}/not-a-uuid.jpg`, `r2:ev-${EV}/${UUID}.gif`, `r2:ev-${EV}/${UUID}.jpg.exe`,
    `r2:ev-${EV}//${UUID}.jpg`, `r2:ev-${EV}/x/${UUID}.jpg`, `r2:ev-a/b/${UUID}.jpg`,
    `http://evil.com/${UUID}.jpg`, `https://evil.com/x.jpg`, `javascript:alert(1)`,
    `r2:ev-${EV}/${UUID}.jpg?x=1`, `r2:ev-${EV}/${UUID}.jpg#h`, ` ${REF}`, '', null, undefined, 42,
  ];
  for (const ref of bad) {
    assert.equal(isR2Ref(ref), false, String(ref));
    assert.equal(r2VariantUrl(ref, 'card', { baseUrl: BASE }), null, String(ref));
    assert.equal(resolveMediaUrl({ r2Ref: ref, legacyUrl: 'L', variant: 'card', baseUrl: BASE, readsEnabled: true }), 'L', String(ref));
  }
});

test('unknown variant and unusable base URL give null', () => {
  assert.equal(r2VariantUrl(REF, 'huge', { baseUrl: BASE }), null);
  assert.equal(r2VariantUrl(REF, 'card', { baseUrl: 'javascript:alert(1)' }), null);
  assert.equal(r2VariantUrl(REF, 'card', {}), null);
});

test('reads flag off => legacy', () => {
  assert.equal(resolveMediaUrl({ r2Ref: REF, legacyUrl: 'L', variant: 'card', baseUrl: BASE, readsEnabled: false }), 'L');
});

test('base URL missing => legacy', () => {
  assert.equal(resolveMediaUrl({ r2Ref: REF, legacyUrl: 'L', variant: 'card', baseUrl: '', readsEnabled: true }), 'L');
  assert.equal(resolveMediaUrl({ r2Ref: REF, legacyUrl: 'L', variant: 'card', baseUrl: null, readsEnabled: true }), 'L');
});

test('no ref => legacy; all flags on + ref => r2', () => {
  assert.equal(resolveMediaUrl({ r2Ref: null, legacyUrl: 'L', variant: 'full', baseUrl: BASE, readsEnabled: true }), 'L');
  assert.equal(resolveMediaUrl({ r2Ref: REF, legacyUrl: 'L', variant: 'full', baseUrl: BASE, readsEnabled: true }), `${BASE}/v1/ev-${EV}/${UUID}/full.jpg`);
});

test('variant mapping', () => {
  for (const v of ['thumb', 'card', 'full']) {
    assert.ok(r2VariantUrl(REF, v, { baseUrl: BASE }).endsWith(`/${v}.jpg`));
  }
});

test('config getter reads injected env', () => {
  assert.deepEqual(getMediaConfig({ VITE_MEDIA_PUBLIC_BASE_URL: `${BASE}/`, VITE_MEDIA_R2_READS: '1' }), { baseUrl: BASE, readsEnabled: true });
  assert.deepEqual(getMediaConfig({ VITE_MEDIA_R2_READS: 'true' }), { baseUrl: '', readsEnabled: false });
  assert.deepEqual(getMediaConfig({}), { baseUrl: '', readsEnabled: false });
});

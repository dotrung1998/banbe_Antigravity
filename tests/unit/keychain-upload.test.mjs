import test from 'node:test';
import assert from 'node:assert/strict';
import {
  sniffImageFormat, validatePickedBytes, validateProcessed, isAnimated, mapKeychainError,
  uploadAndSaveCustomArt, KEYCHAIN_MAX_BYTES, KEYCHAIN_MAX_EDGE, KeychainUploadError,
} from '../../src/lib/keychainUpload.js';

const png = (extra = []) => Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, ...[..."IHDR"].map(c => c.charCodeAt(0)), ...new Array(13).fill(0), 0, 0, 0, 0, ...extra]);
const webp = (vp8x = 0) => Uint8Array.from([..."RIFF"].map(c => c.charCodeAt(0)), ) && Uint8Array.from([...[..."RIFF"].map(c => c.charCodeAt(0)), 0, 0, 0, 0, ...[..."WEBP"].map(c => c.charCodeAt(0)), ...[..."VP8X"].map(c => c.charCodeAt(0)), 10, 0, 0, 0, vp8x, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
const text = (s) => new TextEncoder().encode(s.padEnd(32, ' '));

test('sniff accepts real PNG/WebP only', () => {
  assert.equal(sniffImageFormat(png()), 'png');
  assert.equal(sniffImageFormat(webp()), 'webp');
});

test('SVG / HTML / GIF / JPEG renamed as png are rejected', () => {
  for (const b of [text('<svg xmlns="http://www.w3.org/2000/svg"></svg>'), text('<!doctype html><html></html>'),
    text('GIF89a......'), Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, ...new Array(20).fill(0)]), new Uint8Array(3)]) {
    assert.equal(sniffImageFormat(b), null);
    const v = validatePickedBytes(b, 'image/png');
    assert.deepEqual(v, { ok: false, code: 'BAD_FORMAT' });
  }
});

test('declared type mismatch and animation rejected', () => {
  assert.equal(validatePickedBytes(png(), 'image/webp').code, 'BAD_FORMAT');
  assert.equal(validatePickedBytes(png(), 'image/png').ok, true);
  const apng = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 8, ...[..."acTL"].map(c => c.charCodeAt(0)), 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0]);
  assert.ok(isAnimated(apng, 'png'));
  assert.equal(validatePickedBytes(apng, 'image/png').code, 'ANIMATED');
  assert.equal(validatePickedBytes(webp(0x02), 'image/webp').code, 'ANIMATED');
  assert.equal(validatePickedBytes(webp(0), 'image/webp').ok, true);
});

test('size and dimension limits', () => {
  assert.equal(validateProcessed({ bytes: 1000, width: 512, height: 300 }).ok, true);
  assert.equal(validateProcessed({ bytes: 1000, width: 513, height: 10 }).code, 'TOO_BIG_DIMENSIONS');
  assert.equal(validateProcessed({ bytes: KEYCHAIN_MAX_BYTES + 1, width: 10, height: 10 }).code, 'TOO_LARGE');
  assert.equal(validateProcessed({ bytes: KEYCHAIN_MAX_BYTES, width: KEYCHAIN_MAX_EDGE, height: 1 }).ok, true);
  assert.equal(validateProcessed({ bytes: 1, width: 0, height: 0 }).code, 'BAD_FORMAT');
});

test('error mapping', () => {
  assert.equal(mapKeychainError('QUOTA_EXCEEDED'), 'QUOTA');
  assert.equal(mapKeychainError({ error: 'rate_limited' }), 'RATE_LIMITED');
  assert.equal(mapKeychainError('HTTP_429'), 'RATE_LIMITED');
  assert.equal(mapKeychainError('BAD_MAGIC_BYTES'), 'BAD_FORMAT');
  assert.equal(mapKeychainError('whatever'), 'GENERIC');
});

function harness({ initStatus = 200, initBody, upErr = null, saveRes, finalizeStatus = 200 } = {}) {
  const calls = [];
  const fetchImpl = async (url, opts) => {
    const body = JSON.parse(opts.body);
    calls.push(['fetch', body.op, body]);
    assert.equal(url, '/api/media');
    assert.equal(opts.headers.Authorization, 'Bearer tok');
    if (body.op === 'keychain_init') return { ok: initStatus === 200, status: initStatus, json: async () => initBody || { assetId: 'new1', path: 'u/new1.png', token: 'T' } };
    if (body.op === 'keychain_finalize') return { ok: finalizeStatus === 200, status: finalizeStatus, json: async () => ({ assetId: 'new1', path: 'u/new1.png', width: 10, height: 10 }) };
    return { ok: true, status: 200, json: async () => ({ ok: true }) };
  };
  const supabase = {
    storage: { from: (b) => ({ uploadToSignedUrl: async (path, token, blob) => { calls.push(['put', b, path, token, blob.size]); return { error: upErr }; } }) },
    rpc: async (name, args) => { calls.push(['rpc', name, args]); return { data: saveRes || { success: true, keychain: { designId: 'custom' } }, error: null }; },
  };
  return { calls, fetchImpl, supabase };
}
const blob = { size: 1234 };
const args = { blob, contentType: 'image/png', config: { enabled: true, anchor: 'top_left', size: 'm', motionEnabled: true }, oldAssetId: 'old1' };

test('sequence init -> put -> finalize -> save -> delete old', async () => {
  const h = harness();
  const r = await uploadAndSaveCustomArt({ supabase: h.supabase, fetchImpl: h.fetchImpl, accessToken: 'tok' }, args);
  assert.deepEqual(h.calls.map(c => c[1] === 'keychain_init' || c[1] === 'keychain_finalize' || c[1] === 'keychain_delete' ? c[1] : c[0] === 'put' ? 'put' : c[1]),
    ['keychain_init', 'put', 'keychain_finalize', 'save_my_keychain', 'keychain_delete']);
  assert.equal(h.calls[0][2].bytes, 1234);
  assert.equal(h.calls[1][1], 'keychain-art');
  assert.equal(h.calls[3][2].p_config.designId, 'custom');
  assert.equal(h.calls[3][2].p_config.customAssetId, 'new1');
  assert.equal(h.calls[4][2].assetId, 'old1');
  assert.equal(r.asset.assetId, 'new1');
});

test('quota error from init maps and nothing else runs', async () => {
  const h = harness({ initStatus: 409, initBody: { error: 'QUOTA_EXCEEDED' } });
  await assert.rejects(uploadAndSaveCustomArt({ supabase: h.supabase, fetchImpl: h.fetchImpl, accessToken: 'tok' }, args), (e) => e instanceof KeychainUploadError && e.code === 'QUOTA');
  assert.equal(h.calls.length, 1);
});

test('failure after init deletes the new asset and keeps the old one', async () => {
  const h = harness({ saveRes: { success: false, error: 'BAD_FORMAT' } });
  await assert.rejects(uploadAndSaveCustomArt({ supabase: h.supabase, fetchImpl: h.fetchImpl, accessToken: 'tok' }, args), (e) => e.code === 'BAD_FORMAT');
  const dels = h.calls.filter(c => c[1] === 'keychain_delete');
  assert.equal(dels.length, 1);
  assert.equal(dels[0][2].assetId, 'new1');
});

test('missing token is an AUTH error without network', async () => {
  const h = harness();
  await assert.rejects(uploadAndSaveCustomArt({ supabase: h.supabase, fetchImpl: h.fetchImpl, accessToken: null }, args), (e) => e.code === 'AUTH');
  assert.equal(h.calls.length, 0);
});

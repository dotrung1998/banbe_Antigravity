import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { handleMediaRequest } from '../../api/_lib/media.js';

// ---- tiny image builders ----
const u32be = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
const chunk = (type, data) => Buffer.concat([u32be(data.length), Buffer.from(type, 'latin1'), data, Buffer.alloc(4)]);
function png(w, h, extra = [], pad = 0) {
  const ihdr = Buffer.concat([u32be(w), u32be(h), Buffer.from([8, 6, 0, 0, 0])]);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), ...extra, chunk('IDAT', Buffer.alloc(3 + pad, 1)), chunk('IEND', Buffer.alloc(0))]);
}
function riff(chunks) {
  const body = Buffer.concat(chunks.map(([t, d]) => { const h = Buffer.alloc(8); h.write(t, 0, 'latin1'); h.writeUInt32LE(d.length, 4); return Buffer.concat([h, d, d.length & 1 ? Buffer.from([0]) : Buffer.alloc(0)]); }));
  const h = Buffer.alloc(12); h.write('RIFF', 0, 'latin1'); h.writeUInt32LE(body.length + 4, 4); h.write('WEBP', 8, 'latin1');
  return Buffer.concat([h, body]);
}
const vp8l = (w, h) => { const d = Buffer.alloc(5); d[0] = 0x2f; d.writeUInt32LE(((w - 1) & 0x3fff) | (((h - 1) & 0x3fff) << 14), 1); return d; };
const webp = (w, h, extra = []) => riff([['VP8L', vp8l(w, h)], ...extra]);

function makeCtx(env = {}) {
  const store = { rows: new Map(), objects: new Map(), profiles: new Map(), removed: [] };
  const ctx = {
    env,
    auth: { verify: async (t) => ({ tokA: 'userA', tokB: 'userB', tokGated: 'userG' }[t] || null), gate: async (t) => t !== 'tokGated' },
    db: {},
    keychain: {
      countActive: async (u) => [...store.rows.values()].filter((r) => r.owner_id === u && r.status !== 'deleted').length,
      countRecent: async (u) => [...store.rows.values()].filter((r) => r.owner_id === u).length,
      listStalePending: async () => [],
      getAsset: async (id) => store.rows.get(id) || null,
      insertAsset: async (row) => { store.rows.set(row.id, { ...row }); return row; },
      updateAsset: async (id, p) => { Object.assign(store.rows.get(id), p); },
      createSignedUpload: async (path) => ({ token: `tok:${path}` }),
      download: async (p) => store.objects.get(p) || null,
      upload: async (p, b) => { store.objects.set(p, b); },
      remove: async (p) => { store.objects.delete(p); store.removed.push(p); },
      clearActiveRef: async (u, id) => { const p = store.profiles.get(u); if (p && p.custom_asset_id === id) { p.design_id = 'sky-star'; p.custom_asset_id = null; } },
    },
  };
  return { ctx, store };
}
const call = (ctx, token, body) => handleMediaRequest(ctx, { method: 'POST', headers: { authorization: token ? `Bearer ${token}` : '' }, body });
const init = (ctx, tok = 'tokA', o = {}) => call(ctx, tok, { op: 'keychain_init', contentType: 'image/png', bytes: 1000, ...o });
async function upload(ctx, store, buf, { tok = 'tokA', contentType = 'image/png' } = {}) {
  const r = await init(ctx, tok, { contentType, bytes: Math.min(buf.length, 262144) });
  assert.equal(r.status, 200);
  store.objects.set(r.json.path, buf);
  return r.json;
}

test('unauthenticated / bad token / gated account rejected', async () => {
  const { ctx, store } = makeCtx();
  for (const op of ['keychain_init', 'keychain_finalize', 'keychain_delete']) {
    assert.equal((await call(ctx, '', { op })).status, 401);
    assert.equal((await call(ctx, 'garbage', { op })).status, 401);
  }
  assert.equal((await call(ctx, 'tokGated', { op: 'keychain_init', contentType: 'image/png', bytes: 10 })).status, 403);
  assert.equal(store.rows.size, 0);
});

test('init: server-generated path under uid, validates declaration, never trusts client path', async () => {
  const { ctx, store } = makeCtx();
  const r = await call(ctx, 'tokA', { op: 'keychain_init', contentType: 'image/webp', bytes: 500, path: '../userB/x.png', ownerId: 'userB' });
  assert.equal(r.status, 200);
  assert.match(r.json.path, /^userA\/[0-9a-f-]{36}\.webp$/);
  assert.equal(r.json.token, `tok:${r.json.path}`);
  assert.equal(store.rows.get(r.json.assetId).owner_id, 'userA');
  for (const [o, s] of [[{ contentType: 'image/svg+xml' }, 415], [{ contentType: 'image/jpeg' }, 415], [{ contentType: 'text/html' }, 415], [{ bytes: 262145 }, 413], [{ bytes: 0 }, 400], [{ bytes: '10' }, 400]]) {
    assert.equal((await init(ctx, 'tokA', o)).status, s, JSON.stringify(o));
  }
});

test('finalize: happy path, metadata stripped from stored bytes, idempotent', async () => {
  const { ctx, store } = makeCtx();
  const a = await upload(ctx, store, png(64, 96, [chunk('tEXt', Buffer.from('GPS=secret')), chunk('eXIf', Buffer.from('exif-gps'))]));
  const f1 = await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId });
  assert.equal(f1.status, 200);
  assert.deepEqual(f1.json, { assetId: a.assetId, path: a.path, width: 64, height: 96 });
  const stored = store.objects.get(a.path);
  assert.ok(!stored.includes(Buffer.from('GPS=secret')) && !stored.includes(Buffer.from('exif-gps')), 'EXIF/GPS/text stripped');
  assert.equal(store.rows.get(a.assetId).status, 'ready');
  const before = store.objects.get(a.path);
  const f2 = await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId });
  assert.deepEqual(f2.json, f1.json);
  assert.equal(store.objects.get(a.path), before, 'second finalize does not rewrite');
});

test('finalize: webp EXIF/XMP stripped', async () => {
  const { ctx, store } = makeCtx();
  const a = await upload(ctx, store, webp(40, 40, [['EXIF', Buffer.from('GPS-SECRET')], ['XMP ', Buffer.from('xmp-secret')]]), { contentType: 'image/webp' });
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId })).status, 200);
  const stored = store.objects.get(a.path);
  assert.ok(!stored.includes(Buffer.from('GPS-SECRET')) && !stored.includes(Buffer.from('xmp-secret')));
});

test('finalize rejects SVG / HTML / oversize / spoofed MIME / animated / bad dimensions; nothing ready', async () => {
  const animatedPng = png(64, 64, [chunk('acTL', Buffer.alloc(8))]);
  const animatedWebp = riff([['ANIM', Buffer.alloc(6)], ['VP8L', vp8l(64, 64)]]);
  const cases = [
    ['svg', Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><script>1</script></svg>'), 'image/png', 415],
    ['html', Buffer.from('<html><script>alert(1)</script></html>'.padEnd(64, ' ')), 'image/png', 415],
    ['oversize', png(64, 64, [], 270000), 'image/png', 413],
    ['jpeg-as-png', Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64)]), 'image/png', 422],
    ['webp-declared-png', webp(64, 64), 'image/png', 415],
    ['png-declared-webp', png(64, 64), 'image/webp', 415],
    ['animated-png', animatedPng, 'image/png', 422],
    ['animated-webp', animatedWebp, 'image/webp', 422],
    ['huge-dim', png(4000, 4000), 'image/png', 422],
    ['long-edge-513', png(513, 64), 'image/png', 422],
    ['tiny', png(31, 64), 'image/png', 422],
    ['corrupt', png(64, 64).subarray(0, 40), 'image/png', 422],
  ];
  for (const [name, buf, contentType, want] of cases) {
    const { ctx, store } = makeCtx();
    const r = await init(ctx, 'tokA', { contentType, bytes: Math.min(buf.length, 262144) });
    store.objects.set(r.json.path, buf);
    const f = await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: r.json.assetId });
    assert.equal(f.status, want, `${name}: ${f.status} ${JSON.stringify(f.json)}`);
    assert.equal(store.rows.get(r.json.assetId).status, 'deleted', `${name} not ready`);
    assert.equal(store.objects.has(r.json.path), false, `${name} object removed`);
  }
});

test('finalize: nothing uploaded yet -> 409, stays pending and retryable', async () => {
  const { ctx, store } = makeCtx();
  const r = (await init(ctx)).json;
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: r.assetId })).status, 409);
  assert.equal(store.rows.get(r.assetId).status, 'pending');
  store.objects.set(r.path, png(64, 64));
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: r.assetId })).status, 200);
});

test('cross-account finalize/delete look like 404 and change nothing', async () => {
  const { ctx, store } = makeCtx();
  const a = await upload(ctx, store, png(64, 64));
  assert.equal((await call(ctx, 'tokB', { op: 'keychain_finalize', assetId: a.assetId })).status, 404);
  assert.equal((await call(ctx, 'tokB', { op: 'keychain_delete', assetId: a.assetId })).status, 404);
  assert.equal((await call(ctx, 'tokB', { op: 'keychain_delete', assetId: '11111111-1111-1111-1111-111111111111' })).status, 404);
  assert.equal((await call(ctx, 'tokB', { op: 'keychain_delete', assetId: 'nope' })).status, 400);
  assert.equal(store.rows.get(a.assetId).status, 'pending');
  assert.ok(store.objects.has(a.path));
});

test('quota: 4th init rejected; deleting frees a slot', async () => {
  const { ctx } = makeCtx();
  const ids = [];
  for (let i = 0; i < 3; i++) ids.push((await init(ctx)).json.assetId);
  assert.equal((await init(ctx)).status, 409);
  assert.equal((await init(ctx, 'tokB')).status, 200, 'other user unaffected');
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_delete', assetId: ids[0] })).status, 200);
  assert.equal((await init(ctx)).status, 200);
});

test('rate limit', async () => {
  const { ctx } = makeCtx({ KEYCHAIN_UPLOADS_PER_HOUR: '2' });
  await init(ctx); await init(ctx);
  assert.equal((await init(ctx)).status, 429);
});

test('delete: removes object, marks deleted, clears active reference (falls back, enabled kept)', async () => {
  const { ctx, store } = makeCtx();
  const a = await upload(ctx, store, png(64, 64));
  await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId });
  store.profiles.set('userA', { enabled: true, design_id: 'custom', custom_asset_id: a.assetId });
  const r = await call(ctx, 'tokA', { op: 'keychain_delete', assetId: a.assetId });
  assert.deepEqual(r.json, { ok: true });
  assert.equal(store.objects.has(a.path), false);
  assert.equal(store.rows.get(a.assetId).status, 'deleted');
  assert.deepEqual(store.profiles.get('userA'), { enabled: true, design_id: 'sky-star', custom_asset_id: null });
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_delete', assetId: a.assetId })).status, 200, 'idempotent');
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId })).status, 404, 'deleted cannot be revived');
});

test('replacement flow: new art, save, delete old; only the active reference is touched', async () => {
  const { ctx, store } = makeCtx();
  const a = await upload(ctx, store, png(64, 64)); await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: a.assetId });
  store.profiles.set('userA', { enabled: true, design_id: 'custom', custom_asset_id: a.assetId });
  const b = await upload(ctx, store, webp(80, 80), { contentType: 'image/webp' }); await call(ctx, 'tokA', { op: 'keychain_finalize', assetId: b.assetId });
  store.profiles.get('userA').custom_asset_id = b.assetId;   // save_my_keychain
  await call(ctx, 'tokA', { op: 'keychain_delete', assetId: a.assetId });
  assert.equal(store.profiles.get('userA').design_id, 'custom', 'new art stays active');
  assert.equal(store.profiles.get('userA').custom_asset_id, b.assetId);
  assert.equal(store.rows.get(b.assetId).status, 'ready');
});

test('unknown keychain op falls through to UNKNOWN_OP', async () => {
  const { ctx } = makeCtx();
  assert.equal((await call(ctx, 'tokA', { op: 'keychain_nope' })).status, 400);
});

// ---- static SQL-shape checks (no Postgres available in unit tests) ----
const sql = readFileSync(new URL('../../supabase/migrations/20261211000164_164_profile_keychain.sql', import.meta.url), 'utf8');
const live = sql.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
test('migration 164 shape: private bucket, RLS, owner-only, no anon grants, no client write policy on storage', () => {
  assert.match(live, /'keychain-art', 'keychain-art', false, 262144, ARRAY\['image\/png', 'image\/webp'\]/);
  assert.match(live, /ALTER TABLE public\.profile_keychains ENABLE ROW LEVEL SECURITY/);
  assert.match(live, /ALTER TABLE public\.keychain_assets ENABLE ROW LEVEL SECURITY/);
  assert.ok(!/GRANT[^;]*\bTO\s+(anon|public)\b/i.test(live), 'nothing granted to anon/public');
  for (const op of ['select', 'insert', 'update', 'delete']) assert.match(live, new RegExp(`profile_keychains_owner_${op}[\\s\\S]*?user_id = auth\\.uid\\(\\)`));
  assert.ok(!/ON storage\.objects\s+FOR (INSERT|UPDATE|DELETE|ALL)/i.test(live), 'no client write policy on storage.objects');
  assert.ok(!/POLICY[^;]*ON public\.keychain_assets\s+FOR (INSERT|UPDATE|DELETE|ALL)/i.test(live));
  for (const fn of ['get_my_keychain()', 'save_my_keychain(jsonb)', 'get_profile_keychain(text)']) {
    assert.match(live, new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn.replace(/[()]/g, '\\$&')} FROM anon, PUBLIC`));
    assert.match(live, new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn.replace(/[()]/g, '\\$&')} TO authenticated`));
  }
  assert.equal((live.match(/SECURITY DEFINER SET search_path = public, pg_temp/g) || []).length >= 5, true);
  assert.match(live, /enabled boolean NOT NULL DEFAULT false/);
  assert.match(live, /KEYCHAIN_QUOTA_EXCEEDED/);
});

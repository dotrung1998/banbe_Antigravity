// Shared helpers for the R2 local specs. Everything targets the isolated local stack / loopback services.
import { createClient } from '@supabase/supabase-js';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import zlib from 'node:zlib';
import { assertIsolated, LOCAL } from '../guard.mjs';
import { r2Config, signedFetch, getObject } from '../../../api/_lib/r2.js';

assertIsolated();
export const API = LOCAL.api, MEDIA = LOCAL.mediaBase, MOCK = LOCAL.cloudflareMock;
export const PW = 'BanbeE2e!Test1234';
export const RUN = Date.now().toString(36);
export const admin = createClient(LOCAL.supabase, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
export const cfg = r2Config({ R2_ACCOUNT_ID: 'local', R2_ACCESS_KEY_ID: LOCAL.s3Key, R2_SECRET_ACCESS_KEY: LOCAL.s3Secret, R2_PUBLIC_BUCKET: 'banbe-media-public', R2_STAGING_BUCKET: 'banbe-media-staging', R2_ENDPOINT: LOCAL.s3 });

export async function makeUser(label) {
  const email = `e2e-r2-${label}-${RUN}@example.test`;
  const { data, error } = await admin.auth.admin.createUser({ email, password: PW, email_confirm: true });
  if (error) throw error;
  await admin.from('account_phone_grandfathered').upsert({ user_id: data.user.id, cohort: 'local-e2e-fixture' });
  const client = createClient(LOCAL.supabase, process.env.VITE_SUPABASE_ANON_KEY, { auth: { persistSession: false } });
  const { data: s, error: se } = await client.auth.signInWithPassword({ email, password: PW });
  if (se) throw se;
  return { id: data.user.id, email, client, token: s.session.access_token };
}
export async function dropUser(u) {
  await admin.from('account_phone_grandfathered').delete().eq('user_id', u.id);
  await admin.auth.admin.deleteUser(u.id).catch(() => {});
}
export async function makeOrg(ownerId, id) { await admin.from('organizers').insert({ id, owner_id: ownerId, name: id, verified: true }); return id; }
export async function makeEvent(id, orgId, status = 'live', visibility = 'public') {
  const { error } = await admin.from('events').insert({ id, key: id, slug: id, organizer_id: orgId, name: id, price_vnd: 1, capacity: 5, seats_remaining: 5, status, approval: 'instant', visibility, starts_at: new Date(Date.now() + 7 * 86400_000).toISOString() });
  if (error) throw error; return id;
}

export async function media(token, body) {
  const res = await fetch(`${API}/api/media`, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
  return { status: res.status, json: await res.json().catch(() => null) };
}
export const setFlags = (flags) => fetch(`${API}/__env`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(flags) }).then((r) => r.json());
export const mockCalls = () => fetch(`${MOCK}/__calls`).then((r) => r.json());
export const resetMock = () => Promise.all([fetch(`${MOCK}/__calls`, { method: 'DELETE' }), fetch(`${MOCK}/__stats`, { method: 'DELETE' })]);
export const mediaStats = () => fetch(`${MOCK}/__stats`).then((r) => r.json());
export const uuid = () => globalThis.crypto.randomUUID();

/** init -> PUT every variant to its presigned URL exactly as returned -> returns init json + put statuses. */
export async function initAndPut(token, body, buffers) {
  const init = await media(token, { op: 'init', idempotencyKey: uuid(), ...body, files: ['thumb', 'card', 'full'].map((v) => ({ variant: v, contentType: buffers[v].type, bytes: buffers[v].data.length })) });
  const puts = {};
  if (init.json?.provider === 'r2') {
    for (const u of init.json.uploads) {
      const r = await fetch(u.url, { method: u.method, headers: u.headers, body: buffers[u.variant].data });
      puts[u.variant] = r.status;
    }
  }
  return { init, puts };
}

// ---------- image builders (hand-built, decodable by the server's parser; PNG/JPEG also decode in Chromium) ----------
const crcTable = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
const crc32 = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function chunk(type, data) { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const t = Buffer.from(type); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data]))); return Buffer.concat([len, t, data, crc]); }
/** Valid PNG, w x h, optional tEXt chunk carrying a GPS-looking string (to prove it is stripped). */
export function png(w, h, { text, seed = 3 } = {}) {
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const row = Buffer.alloc(1 + w * 3); for (let x = 0; x < w; x++) { row[1 + x * 3] = (x * seed) & 255; row[2 + x * 3] = (x * 5) & 255; row[3 + x * 3] = 90; }
  const raw = Buffer.concat(Array.from({ length: h }, () => row));
  const parts = [Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr)];
  if (text) parts.push(chunk('tEXt', Buffer.from(text)));
  parts.push(chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)));
  return Buffer.concat(parts);
}
/** Structurally valid JPEG (SOI, APPn, DQT, SOF0, SOS, EOI) — optionally with an EXIF/GPS APP1 segment. Enough for the server's parser (not a viewable picture). */
export function jpegStruct(w, h, { exif = false } = {}) {
  const segs = [Buffer.from([0xff, 0xd8])];
  if (exif) { const body = Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), Buffer.from('GPSLatitude=10.7769,GPSLongitude=106.7009')]); const len = Buffer.alloc(2); len.writeUInt16BE(body.length + 2); segs.push(Buffer.from([0xff, 0xe1]), len, body); }
  segs.push(Buffer.from([0xff, 0xdb, 0x00, 0x04, 0x00, 0x00]));
  segs.push(Buffer.concat([Buffer.from([0xff, 0xc0, 0x00, 0x0b, 0x08, h >> 8, h & 255, w >> 8, w & 255, 0x01, 0x01, 0x11, 0x00])]));
  segs.push(Buffer.from([0xff, 0xda, 0x00, 0x04, 0x00, 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 0xff, 0xd9]));
  return Buffer.concat(segs);
}
/** A real photo-sized JPEG via macOS `sips` (for byte measurements only). */
export function realJpeg(w, h) {
  const dir = mkdtempSync(join(tmpdir(), 'e2e-jpg-')); const src = join(dir, 'a.png'), dst = join(dir, 'a.jpg');
  try {
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
    const rows = []; let s = 12345;
    for (let y = 0; y < h; y++) { const row = Buffer.alloc(1 + w * 3); for (let x = 0; x < w; x++) { s = (s * 1103515245 + 12345) & 0x7fffffff; const n = (s >> 16) & 15; row[1 + x * 3] = ((x + y) / 8 + n) & 255; row[2 + x * 3] = (y / 6 + n) & 255; row[3 + x * 3] = ((x * y) / 4000 + n) & 255; } rows.push(row); }
    writeFileSync(src, Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0))]));
    execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '85', src, '--out', dst], { stdio: 'ignore' });
    return readFileSync(dst);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}
export const buf = (data, type = 'image/png') => ({ data, type });
export const set3 = (data, type) => ({ thumb: buf(data, type), card: buf(data, type), full: buf(data, type) });

export async function s3Has(bucket, key) { return (await getObject(cfg, bucket, key, 20 * 1024 * 1024)) !== null; }
export async function s3Get(bucket, key) { return getObject(cfg, bucket, key, 20 * 1024 * 1024); }
export const sha = (b) => globalThis.crypto.subtle.digest('SHA-256', b).then((d) => Buffer.from(d).toString('hex'));
export { signedFetch, LOCAL };

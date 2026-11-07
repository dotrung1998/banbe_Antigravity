// Custom keychain art (private Supabase Storage bucket `keychain-art`).
// Ops dispatched from handleMediaRequest (api/_lib/media.js): keychain_init,
// keychain_finalize, keychain_delete. They need only the Supabase service-role
// client (NO R2). Contract: .claude/notes/35-foryou-alert-organizer-ensure-keychain.md
//
// Clients never write to the bucket directly (no storage INSERT policy): init
// issues a signed upload token for a server-generated path, finalize re-reads
// the uploaded bytes, validates the REAL format/size/dimensions, strips
// metadata, overwrites the object with the sanitised bytes and only then marks
// the row `ready`. Nothing the client declares (MIME, size) is trusted.
import { randomUUID } from 'node:crypto';
import { inspectImage } from './imageSafe.js';

export const BUCKET = 'keychain-art';
export const MAX_BYTES = 256 * 1024;
export const MIN_EDGE = 32;
export const MAX_EDGE = 512;
export const MAX_ASSETS = 3;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MIME_EXT = { 'image/png': 'png', 'image/webp': 'webp' };
const FORMAT_MIME = { png: 'image/png', webp: 'image/webp' };
const STALE_PENDING_MS = 3600_000;
const INSPECT_STATUS = {
  IMAGE_TOO_LARGE: [413, 'FILE_TOO_LARGE'],
  IMAGE_UNSUPPORTED_FORMAT: [415, 'UNSUPPORTED_MEDIA_TYPE'],
  IMAGE_ANIMATED: [422, 'ANIMATION_NOT_ALLOWED'],
  IMAGE_DIMENSIONS_EXCEEDED: [422, 'IMAGE_DIMENSIONS_INVALID'],
  IMAGE_CORRUPT: [422, 'IMAGE_CORRUPT'],
};

/** Service-role data + storage access (bypasses RLS: authorization is in the ops below). */
export function makeKeychainDb(admin) {
  const one = async (q) => { const { data, error } = await q; if (error) throw new Error(error.message); return data; };
  const A = () => admin.from('keychain_assets');
  const S = () => admin.storage.from(BUCKET);
  return {
    countActive: async (uid) => { const { count, error } = await A().select('id', { count: 'exact', head: true }).eq('owner_id', uid).neq('status', 'deleted'); if (error) throw new Error(error.message); return count || 0; },
    countRecent: async (uid, sinceIso) => { const { count, error } = await A().select('id', { count: 'exact', head: true }).eq('owner_id', uid).gte('created_at', sinceIso); if (error) throw new Error(error.message); return count || 0; },
    listStalePending: async (uid, beforeIso) => (await one(A().select('*').eq('owner_id', uid).eq('status', 'pending').lt('created_at', beforeIso))) || [],
    getAsset: (id) => one(A().select('*').eq('id', id).maybeSingle()),
    insertAsset: (row) => one(A().insert(row).select('*').single()),
    async updateAsset(id, patch) { await one(A().update(patch).eq('id', id)); },
    async createSignedUpload(path) { const { data, error } = await S().createSignedUploadUrl(path); if (error) throw new Error(error.message); return { token: data.token }; },
    async download(path) {
      const { data, error } = await S().download(path);
      if (error || !data) return null;
      return Buffer.from(await data.arrayBuffer());
    },
    async upload(path, buf, contentType) { const { error } = await S().upload(path, buf, { contentType, upsert: true, cacheControl: '3600' }); if (error) throw new Error(error.message); },
    async remove(path) { await S().remove([path]); },
    // Active reference falls back to the default design; `enabled` is preserved.
    async clearActiveRef(uid, assetId) {
      await one(admin.from('profile_keychains').update({ design_id: 'sky-star', custom_asset_id: null, updated_at: new Date().toISOString() }).eq('user_id', uid).eq('custom_asset_id', assetId).eq('design_id', 'custom'));
      await one(admin.from('profile_keychains').update({ custom_asset_id: null }).eq('user_id', uid).eq('custom_asset_id', assetId));
    },
    // Account deletion: remove every object under `<uid>/`.
    async removeFolder(uid) {
      const { data } = await S().list(uid, { limit: 1000 });
      if (data?.length) await S().remove(data.map((f) => `${uid}/${f.name}`));
    },
  };
}

const validAssetId = (v) => typeof v === 'string' && UUID_RE.test(v);

async function ownedAsset(ctx, userId, body, fail) {
  if (!validAssetId(body.assetId)) fail(400, 'VALID_ASSET_REQUIRED');
  const a = await ctx.keychain.getAsset(body.assetId);
  if (!a || a.owner_id !== userId) fail(404, 'NOT_FOUND');   // same answer for missing and foreign
  return a;
}

async function discard(ctx, asset) {
  try { await ctx.keychain.remove(asset.path); } catch { /* best effort */ }
  await ctx.keychain.updateAsset(asset.id, { status: 'deleted' });
}

async function init(ctx, userId, body, { fail }) {
  const mime = body.contentType;
  if (typeof mime !== 'string' || !MIME_EXT[mime]) fail(415, 'UNSUPPORTED_MEDIA_TYPE');
  if (!Number.isInteger(body.bytes) || body.bytes <= 0) fail(400, 'VALID_BYTES_REQUIRED');
  if (body.bytes > MAX_BYTES) fail(413, 'FILE_TOO_LARGE');
  const now = ctx.now ? ctx.now() : new Date();
  const perHour = Number(ctx.env?.KEYCHAIN_UPLOADS_PER_HOUR || 10);
  if ((await ctx.keychain.countRecent(userId, new Date(now.getTime() - 3600_000).toISOString())) >= perHour) fail(429, 'RATE_LIMITED');
  if ((await ctx.keychain.countActive(userId)) >= MAX_ASSETS) {
    // Reclaim abandoned pending uploads before refusing.
    for (const s of await ctx.keychain.listStalePending(userId, new Date(now.getTime() - STALE_PENDING_MS).toISOString())) await discard(ctx, s);
    if ((await ctx.keychain.countActive(userId)) >= MAX_ASSETS) fail(409, 'KEYCHAIN_ART_QUOTA');
  }
  const id = randomUUID();
  const path = `${userId}/${id}.${MIME_EXT[mime]}`;
  await ctx.keychain.insertAsset({ id, owner_id: userId, path, content_type: mime, bytes: body.bytes, status: 'pending' });
  const { token } = await ctx.keychain.createSignedUpload(path);
  return { assetId: id, path, token };
}

async function finalize(ctx, userId, body, { fail }) {
  const a = await ownedAsset(ctx, userId, body, fail);
  if (a.status === 'deleted') fail(404, 'NOT_FOUND');
  if (a.status === 'ready') return { assetId: a.id, path: a.path, width: a.width, height: a.height };   // idempotent
  const raw = await ctx.keychain.download(a.path);
  if (!raw) fail(409, 'UPLOAD_INCOMPLETE');                  // stays pending, retryable
  let img;
  try {
    if (raw.length > MAX_BYTES) throw new Error('IMAGE_TOO_LARGE');
    img = inspectImage(raw, { maxBytes: MAX_BYTES, maxLongEdge: MAX_EDGE });
    if (!FORMAT_MIME[img.format]) throw new Error('IMAGE_UNSUPPORTED_FORMAT');          // jpeg etc.
    if (FORMAT_MIME[img.format] !== a.content_type) throw new Error('IMAGE_UNSUPPORTED_FORMAT');   // declared != real
    if (img.width < MIN_EDGE || img.height < MIN_EDGE) throw new Error('IMAGE_DIMENSIONS_EXCEEDED');
  } catch (e) {
    await discard(ctx, a);                                   // nothing is ever marked ready
    const [status, code] = INSPECT_STATUS[e.message] || [422, 'IMAGE_CORRUPT'];
    return fail(status, code);
  }
  await ctx.keychain.upload(a.path, img.data, img.mime);     // overwrite with sanitised bytes
  await ctx.keychain.updateAsset(a.id, { status: 'ready', width: img.width, height: img.height, bytes: img.data.length });
  return { assetId: a.id, path: a.path, width: img.width, height: img.height };
}

async function del(ctx, userId, body, { fail }) {
  const a = await ownedAsset(ctx, userId, body, fail);
  if (a.status !== 'deleted') {
    try { await ctx.keychain.remove(a.path); } catch { /* row is the source of truth; object is private anyway */ }
    await ctx.keychain.updateAsset(a.id, { status: 'deleted' });
  }
  await ctx.keychain.clearActiveRef(userId, a.id);
  return { ok: true };
}

/** @returns result json, or undefined when `op` is not a keychain op. */
export async function handleKeychainOp(ctx, token, body, helpers) {
  const fns = { keychain_init: init, keychain_finalize: finalize, keychain_delete: del };
  const fn = fns[body.op];
  if (!fn) return undefined;
  const userId = await helpers.authenticate(ctx, token);
  if (!ctx.keychain) helpers.fail(503, 'MEDIA_NOT_CONFIGURED');
  return fn(ctx, userId, body, helpers);
}

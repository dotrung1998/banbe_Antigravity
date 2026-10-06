// Core of /api/media — every authorization decision for R2-delivered public
// media lives here. All collaborators arrive through `ctx` so the whole policy
// is unit-testable without Supabase/R2 (tests/unit/media-api.test.mjs).
//
//   ctx.auth.verify(token)  -> userId | null      (Supabase JWT validated server-side)
//   ctx.auth.gate(token)    -> boolean            (account_gate_ok)
//   ctx.db.*                                       (service-role data access, see mediaDb.js)
//   ctx.r2.*                                       (R2 + CDN purge, see mediaR2.js)
//   ctx.env                                        (feature flags / limits)
//
// R2 is NOT protected by Supabase RLS, so ownership + eligibility are checked
// here at init, finalize and delete. Never log tokens, URLs or file content.
import { randomUUID, createHash } from 'node:crypto';
import { inspectImage, MIME_TO_EXT } from './imageSafe.js';

export const VARIANTS = {
  thumb: { maxEdge: 320, maxBytes: 200 * 1024 },
  card: { maxEdge: 800, maxBytes: 600 * 1024 },
  full: { maxEdge: 1600, maxBytes: 2.5 * 1024 * 1024 },
};
const VARIANT_NAMES = Object.keys(VARIANTS);
const PUBLIC_EVENT_STATUSES = ['live', 'ended', 'cancelled'];
const KEY_VERSION = 'v1';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const IMMUTABLE_CACHE = 'public, max-age=31536000, immutable';

export class ApiError extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
const fail = (status, code) => { throw new ApiError(status, code); };

export const publicKey = (scope, assetId, variant, ext) => `${KEY_VERSION}/${scope}/${assetId}/${variant}.${ext}`;
export const stagingKey = (assetId, variant) => `staging/${assetId}/${variant}`;
export const refOf = (scope, assetId, ext) => `r2:${scope}/${assetId}.${ext}`;

/** An event's media may be served from the public CDN only while the event itself is public. */
export const eventIsPublic = (ev) => !!ev && PUBLIC_EVENT_STATUSES.includes(ev.status) && ev.visibility === 'public';

// ---------- feature flag ----------
export function uploadsEnabledFor(userId, env) {
  const mode = (env.MEDIA_R2_UPLOADS || 'off').toLowerCase();
  if (mode === 'on') return true;
  if (mode === 'allowlist') return (env.MEDIA_R2_UPLOAD_USER_IDS || '').split(',').map((s) => s.trim()).filter(Boolean).includes(userId);
  if (mode === 'percent') {
    const pct = Math.max(0, Math.min(100, Number(env.MEDIA_R2_UPLOAD_PERCENT || 0)));
    return createHash('sha256').update(userId).digest().readUInt16BE(0) % 100 < pct;
  }
  return false;
}

// ---------- shared guards ----------
async function authenticate(ctx, token) {
  if (!token) fail(401, 'AUTH_REQUIRED');
  const userId = await ctx.auth.verify(token);
  if (!userId) fail(401, 'AUTH_REQUIRED');
  if (!(await ctx.auth.gate(token))) fail(403, 'ACCOUNT_GATE_REQUIRED');
  return userId;
}

async function ownsOrganizer(ctx, userId, organizerId) {
  const org = await ctx.db.getOrganizer(organizerId);
  return !!org && (org.owner_id === userId || org.user_id === userId) ? org : null;
}

/** Resolves who may attach media to the target and whether it may be public. Throws 403 for any non-owner (same answer for "missing"). */
async function resolveTarget(ctx, userId, body) {
  if (body.kind === 'event_photo') {
    if (typeof body.eventId !== 'string' || !ID_RE.test(body.eventId)) fail(400, 'VALID_EVENT_REQUIRED');
    const ev = await ctx.db.getEvent(body.eventId);
    if (!ev || !ev.organizer_id || !(await ownsOrganizer(ctx, userId, ev.organizer_id))) fail(403, 'FORBIDDEN');
    return { scope: `ev-${ev.id}`, eventId: ev.id, organizerId: null, eligible: eventIsPublic(ev) };
  }
  if (body.kind === 'organizer_avatar') {
    if (typeof body.organizerId !== 'string' || !ID_RE.test(body.organizerId)) fail(400, 'VALID_ORGANIZER_REQUIRED');
    if (!(await ownsOrganizer(ctx, userId, body.organizerId))) fail(403, 'FORBIDDEN');
    return { scope: `org-${body.organizerId}`, eventId: null, organizerId: body.organizerId, eligible: true };
  }
  return fail(400, 'VALID_KIND_REQUIRED');
}

function presignAll(ctx, asset) {
  return VARIANT_NAMES.map((variant) => {
    const d = asset.declared[variant];
    const headers = { 'content-type': d.contentType, 'content-length': String(d.bytes) };
    return { variant, method: 'PUT', url: ctx.r2.presignStagingPut(stagingKey(asset.id, variant), headers), headers };
  });
}

// ---------- op: init ----------
export async function opInit(ctx, token, body) {
  const userId = await authenticate(ctx, token);
  if (!uploadsEnabledFor(userId, ctx.env)) return { provider: 'supabase' };
  if (!ctx.r2.configured) return { provider: 'supabase' };

  if (typeof body.idempotencyKey !== 'string' || !UUID_RE.test(body.idempotencyKey)) fail(400, 'VALID_IDEMPOTENCY_KEY_REQUIRED');
  const files = Array.isArray(body.files) ? body.files : [];
  const declared = {};
  for (const f of files) {
    if (!f || !VARIANTS[f.variant] || declared[f.variant]) fail(400, 'VALID_FILES_REQUIRED');
    if (!MIME_TO_EXT[f.contentType]) fail(415, 'UNSUPPORTED_MEDIA_TYPE');
    if (!Number.isInteger(f.bytes) || f.bytes <= 0) fail(400, 'VALID_FILES_REQUIRED');
    if (f.bytes > VARIANTS[f.variant].maxBytes) fail(413, 'FILE_TOO_LARGE');
    declared[f.variant] = { contentType: f.contentType, bytes: f.bytes };
  }
  if (VARIANT_NAMES.some((v) => !declared[v])) fail(400, 'VALID_FILES_REQUIRED');
  if (new Set(VARIANT_NAMES.map((v) => declared[v].contentType)).size !== 1) fail(400, 'MIXED_FORMATS');

  const target = await resolveTarget(ctx, userId, body);
  if (!target.eligible) return { provider: 'supabase' };          // draft / invite-only / withdrawn: never public

  // Retry of the same logical upload: hand back the same asset.
  const existing = await ctx.db.findAssetByIdem(userId, body.idempotencyKey);
  if (existing) {
    if (existing.scope !== target.scope || existing.kind !== body.kind) fail(409, 'IDEMPOTENCY_CONFLICT');
    if (existing.status === 'published') return { provider: 'r2', assetId: existing.id, ref: refOf(existing.scope, existing.id, existing.ext), alreadyPublished: true };
    if (existing.status === 'pending') return { provider: 'r2', assetId: existing.id, expiresIn: 300, uploads: presignAll(ctx, existing) };
    fail(409, 'IDEMPOTENCY_CONFLICT');
  }

  const now = ctx.now ? ctx.now() : new Date();
  const perHour = Number(ctx.env.MEDIA_UPLOADS_PER_HOUR || 60);
  const maxPending = Number(ctx.env.MEDIA_MAX_PENDING || 24);
  if ((await ctx.db.countRecentAssets(userId, new Date(now.getTime() - 3600_000).toISOString())) >= perHour) fail(429, 'RATE_LIMITED');
  if ((await ctx.db.countPendingAssets(userId)) >= maxPending) fail(429, 'TOO_MANY_PENDING');

  const asset = await ctx.db.insertAsset({
    id: randomUUID(), kind: body.kind, scope: target.scope, event_id: target.eventId, organizer_id: target.organizerId,
    owner_user_id: userId, ext: MIME_TO_EXT[declared.full.contentType], status: 'pending', declared,
    idempotency_key: body.idempotencyKey, source: 'upload',
  });
  return { provider: 'r2', assetId: asset.id, expiresIn: 300, uploads: presignAll(ctx, asset) };
}

// ---------- finalize ----------
async function readAndValidateVariants(ctx, asset) {
  const out = {};
  for (const variant of VARIANT_NAMES) {
    const cap = VARIANTS[variant];
    const staged = await ctx.r2.getStaging(stagingKey(asset.id, variant), cap.maxBytes + 1);
    if (!staged) fail(409, 'UPLOAD_INCOMPLETE');
    let img;
    try { img = inspectImage(staged, { maxBytes: cap.maxBytes, maxLongEdge: cap.maxEdge }); }
    catch (e) {
      const code = e.message || 'IMAGE_CORRUPT';
      if (code === 'IMAGE_TOO_LARGE') fail(413, code);
      if (code === 'IMAGE_UNSUPPORTED_FORMAT') fail(415, code);
      fail(422, code.startsWith('IMAGE_') ? code : 'IMAGE_CORRUPT');
    }
    if (img.ext !== asset.ext) fail(415, 'IMAGE_FORMAT_MISMATCH');           // declared type is not trusted
    out[variant] = { img, sha256: createHash('sha256').update(img.data).digest('hex') };
  }
  return out;
}

async function discard(ctx, asset, keys) {
  await Promise.all(keys.map((k) => ctx.r2.deletePublic(k).catch(() => {})));
  await Promise.all(VARIANT_NAMES.map((v) => ctx.r2.deleteStaging(stagingKey(asset.id, v)).catch(() => {})));
}

export async function opFinalize(ctx, token, body) {
  const userId = await authenticate(ctx, token);
  if (typeof body.assetId !== 'string' || !UUID_RE.test(body.assetId)) fail(400, 'VALID_ASSET_REQUIRED');
  const asset = await ctx.db.getAsset(body.assetId);
  if (!asset || asset.owner_user_id !== userId) fail(404, 'NOT_FOUND');      // cross-account looks identical to "missing"
  const ref = refOf(asset.scope, asset.id, asset.ext);
  if (asset.status === 'published') return { provider: 'r2', assetId: asset.id, ref };   // idempotent
  if (asset.status !== 'pending') fail(409, 'ASSET_NOT_PENDING');

  // Re-check at publish time: ownership/eligibility may have changed since init.
  const target = await resolveTarget(ctx, userId, { kind: asset.kind, eventId: asset.event_id, organizerId: asset.organizer_id });
  if (!target.eligible) { await discard(ctx, asset, []); await ctx.db.updateAsset(asset.id, { status: 'failed' }); fail(409, 'NOT_ELIGIBLE'); }

  const written = [];
  try {
    const checked = await readAndValidateVariants(ctx, asset);
    const variants = {};
    for (const variant of VARIANT_NAMES) {
      const { img, sha256 } = checked[variant];
      const key = publicKey(asset.scope, asset.id, variant, asset.ext);
      await ctx.r2.putPublic(key, img.data, { contentType: img.mime, cacheControl: IMMUTABLE_CACHE });
      written.push(key);
      variants[variant] = { key, bytes: img.data.length, w: img.width, h: img.height, sha256 };
    }

    if (asset.kind === 'event_photo') {
      if (!(await ctx.db.findEventPhotoByRef(ref))) {
        await ctx.db.insertEventPhoto({ event_id: asset.event_id, storage_path: ref, r2_ref: ref, sort_order: Number.isInteger(body.sortOrder) ? body.sortOrder : 0 });
      }
      if (body.setCover === true) await ctx.db.setEventCoverRef(asset.event_id, ref);
    } else {
      const prev = await ctx.db.getOrganizerAvatarRef(asset.organizer_id);
      await ctx.db.setOrganizerAvatarRef(asset.organizer_id, ref);
      if (prev && prev !== ref) await retireByRef(ctx, prev).catch(() => {});  // best effort; sweep retries
    }
    await ctx.db.updateAsset(asset.id, { status: 'published', published_at: (ctx.now ? ctx.now() : new Date()).toISOString(), variants });
  } catch (e) {
    if (e instanceof ApiError && e.status === 409 && e.code === 'UPLOAD_INCOMPLETE') throw e;   // client may still be uploading; keep pending
    await discard(ctx, asset, written);
    if (e instanceof ApiError) { await ctx.db.updateAsset(asset.id, { status: 'failed' }); throw e; }
    throw e;
  }
  await Promise.all(VARIANT_NAMES.map((v) => ctx.r2.deleteStaging(stagingKey(asset.id, v)).catch(() => {})));
  return { provider: 'r2', assetId: asset.id, ref };
}

// ---------- delete / unpublish ----------
async function retireByRef(ctx, ref) {
  const asset = await ctx.db.getAssetByRef(ref);
  if (asset) await unpublishAsset(ctx, asset, { demote: false });
}

/**
 * Removes public objects, purges the CDN, and clears references.
 * `demote:true` is used when an R2-only event photo must stay visible to its
 * host after the event stopped being public: the bytes move to the PRIVATE
 * Supabase bucket first, so nothing is lost. Already-downloaded external copies
 * cannot be recalled — this only stops further delivery.
 */
export async function unpublishAsset(ctx, asset, { demote }) {
  const ref = refOf(asset.scope, asset.id, asset.ext);
  await ctx.db.updateAsset(asset.id, { deleted_at: (ctx.now ? ctx.now() : new Date()).toISOString() });   // intent: sweep retries if we crash

  if (demote && asset.kind === 'event_photo') {
    const rows = await ctx.db.listEventPhotosByRef(ref);
    const fullKey = publicKey(asset.scope, asset.id, 'full', asset.ext);
    const bytes = rows.some((r) => r.storage_path === ref) ? await ctx.r2.getPublic(fullKey, VARIANTS.full.maxBytes + 1) : null;
    for (const row of rows) {
      if (row.storage_path !== ref) { await ctx.db.clearEventPhotoRef(row.id, null); continue; }   // has a legacy fallback
      if (!bytes) { await ctx.db.clearEventPhotoRef(row.id, null); continue; }
      const privatePath = `${asset.event_id}/${asset.id}.${asset.ext}`;
      await ctx.db.uploadPrivateEventPhoto(privatePath, bytes, `image/${asset.ext === 'jpg' ? 'jpeg' : asset.ext}`);
      await ctx.db.clearEventPhotoRef(row.id, `event-photos-private/${privatePath}`);
      await ctx.db.replaceCoverPath(asset.event_id, ref, `event-photos-private/${privatePath}`);
    }
  } else {
    await ctx.db.clearRefs(asset.kind, ref);
  }
  await ctx.db.clearCoverRef(asset.event_id, ref);

  const keys = VARIANT_NAMES.map((v) => publicKey(asset.scope, asset.id, v, asset.ext));
  for (const k of keys) await ctx.r2.deletePublic(k);
  await Promise.all(VARIANT_NAMES.map((v) => ctx.r2.deleteStaging(stagingKey(asset.id, v)).catch(() => {})));
  const purge = await ctx.r2.purge(keys.map((k) => ctx.r2.publicUrl(k)));
  await ctx.db.updateAsset(asset.id, { status: 'deleted' });
  return { purge };
}

export async function opDelete(ctx, token, body) {
  const userId = await authenticate(ctx, token);
  if (typeof body.assetId !== 'string' || !UUID_RE.test(body.assetId)) fail(400, 'VALID_ASSET_REQUIRED');
  const asset = await ctx.db.getAsset(body.assetId);
  if (!asset) fail(404, 'NOT_FOUND');
  let allowed = asset.owner_user_id === userId;
  if (!allowed) {   // current host/organizer owner or platform admin may also retire it
    const orgId = asset.organizer_id || (asset.event_id ? (await ctx.db.getEvent(asset.event_id))?.organizer_id : null);
    allowed = (orgId && !!(await ownsOrganizer(ctx, userId, orgId))) || (await ctx.db.isAdmin(userId));
  }
  if (!allowed) fail(404, 'NOT_FOUND');
  if (asset.status === 'deleted') return { ok: true };
  const r = await unpublishAsset(ctx, asset, { demote: false });
  return { ok: true, cdnPurged: !!r.purge?.ok };
}

/** Host-triggered, immediate version of the sweep for ONE event (call right after a privacy/status change). */
export async function opReconcile(ctx, token, body) {
  const userId = await authenticate(ctx, token);
  if (typeof body.eventId !== 'string' || !ID_RE.test(body.eventId)) fail(400, 'VALID_EVENT_REQUIRED');
  const ev = await ctx.db.getEvent(body.eventId);
  if (!ev || !ev.organizer_id || !(await ownsOrganizer(ctx, userId, ev.organizer_id))) fail(403, 'FORBIDDEN');
  let unpublished = 0;
  if (!eventIsPublic(ev)) {
    for (const a of await ctx.db.listPublishedEventAssetsForEvent(ev.id)) { await unpublishAsset(ctx, a, { demote: true }); unpublished++; }
  }
  return { ok: true, unpublished };
}

// ---------- scheduled sweep (called by api/_lib/handlers/cronMediaSweep.js) ----------
export async function sweep(ctx) {
  const stats = { orphanedPending: 0, demoted: 0, retried: 0, errors: 0 };
  const now = ctx.now ? ctx.now() : new Date();

  for (const a of await ctx.db.listStalePending(new Date(now.getTime() - 3600_000).toISOString())) {
    try { await discard(ctx, a, []); await ctx.db.updateAsset(a.id, { status: 'failed' }); stats.orphanedPending++; } catch { stats.errors++; }
  }
  // Published event photos whose event stopped being public (invite-only switch, withdrawn, back to draft…).
  for (const a of await ctx.db.listPublishedEventAssets()) {
    try {
      const ev = await ctx.db.getEvent(a.event_id);
      if (ev && eventIsPublic(ev)) continue;
      await unpublishAsset(ctx, a, { demote: !!ev });   // event deleted => nothing to keep
      stats.demoted++;
    } catch { stats.errors++; }
  }
  // Half-finished deletions (R2/purge failed earlier).
  for (const a of await ctx.db.listDeletionIntents()) {
    try { await unpublishAsset(ctx, a, { demote: false }); stats.retried++; } catch { stats.errors++; }
  }
  return stats;
}

export async function handleMediaRequest(ctx, { method, headers, body }) {
  try {
    if (method !== 'POST') fail(405, 'METHOD_NOT_ALLOWED');
    const token = String(headers?.authorization || '').replace(/^Bearer\s+/i, '').trim();
    const b = body && typeof body === 'object' ? body : {};
    if (b.op === 'init') return { status: 200, json: await opInit(ctx, token, b) };
    if (b.op === 'finalize') return { status: 200, json: await opFinalize(ctx, token, b) };
    if (b.op === 'reconcile') return { status: 200, json: await opReconcile(ctx, token, b) };
    if (b.op === 'delete') return { status: 200, json: await opDelete(ctx, token, b) };
    return fail(400, 'UNKNOWN_OP');
  } catch (e) {
    if (e instanceof ApiError) return { status: e.status, json: { error: e.code } };
    console.error('media: unexpected failure', e?.message);   // message only: never URLs/headers/tokens
    return { status: 500, json: { error: 'MEDIA_INTERNAL_ERROR' } };
  }
}

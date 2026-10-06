// Upload via the media API (/api/media -> R2). See .claude/notes/28-r2-hybrid-media.md.
// Resolves `{provider:'supabase'}` whenever the caller should use the legacy
// upload unchanged (server says so, or init/network failed). Throws
// MediaUploadError only when failure happens after bytes were PUT.
import { normalizeImageForUpload } from './proofUpload.js';
import { parseR2Ref } from './mediaResolver.js';

export class MediaUploadError extends Error {
  constructor(code, assetId) {
    super(code);
    this.name = 'MediaUploadError';
    this.code = code;
    this.assetId = assetId || null;
  }
}

const VARIANT_SPECS = [
  { variant: 'thumb', maxDimension: 320, maxBytes: 150 * 1024 },
  { variant: 'card', maxDimension: 800, maxBytes: 500 * 1024 },
  { variant: 'full', maxDimension: 1600, maxBytes: 2 * 1024 * 1024 },
];

async function postMedia(apiBase, accessToken, body) {
  const res = await fetch(`${apiBase || ''}/api/media`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-JSON */ }
  return { ok: res.ok, json };
}

/** Builds the 3 same-format variants, or null if they cannot share one format. */
async function buildVariants(file) {
  const out = [];
  for (const spec of VARIANT_SPECS) {
    const n = await normalizeImageForUpload(file, spec);
    out.push({ variant: spec.variant, blob: n.blob, contentType: n.contentType });
  }
  return out.every(v => v.contentType === out[0].contentType) ? out : null;
}

export async function uploadViaMediaApi({ kind, eventId, organizerId, file, accessToken, apiBase = '', setCover = false, sortOrder = 0 }) {
  const legacy = { provider: 'supabase' };
  if (!accessToken || !file) return legacy;
  let variants, init;
  try {
    variants = await buildVariants(file);
    if (!variants) return legacy;
    const idempotencyKey = (globalThis.crypto?.randomUUID?.()) || undefined;
    if (!idempotencyKey) return legacy;
    const r = await postMedia(apiBase, accessToken, {
      op: 'init', kind,
      ...(kind === 'event_photo' ? { eventId } : { organizerId }),
      idempotencyKey,
      files: variants.map(v => ({ variant: v.variant, contentType: v.contentType, bytes: v.blob.size })),
    });
    if (!r.ok || !r.json || r.json.provider !== 'r2' || !r.json.assetId || !Array.isArray(r.json.uploads)) return legacy;
    init = r.json;
  } catch {
    return legacy;
  }

  const byVariant = Object.fromEntries(variants.map(v => [v.variant, v.blob]));
  let putCount = 0;
  for (const u of init.uploads) {
    const blob = byVariant[u.variant];
    if (!blob || !u.url) {
      if (putCount === 0) return legacy;
      throw new MediaUploadError('UPLOAD_FAILED', init.assetId);
    }
    try {
      const res = await fetch(u.url, { method: u.method || 'PUT', headers: u.headers || {}, body: blob });
      if (!res.ok) throw new Error('PUT_FAILED');
      putCount++;
    } catch {
      if (putCount === 0) return legacy;
      throw new MediaUploadError('UPLOAD_FAILED', init.assetId);
    }
  }

  const finalizeBody = { op: 'finalize', assetId: init.assetId, ...(setCover ? { setCover: true } : {}), sortOrder };
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await postMedia(apiBase, accessToken, finalizeBody);
      if (r.ok && r.json?.ref) return { provider: 'r2', assetId: r.json.assetId || init.assetId, ref: r.json.ref };
    } catch { /* retry once */ }
  }
  throw new MediaUploadError('FINALIZE_FAILED', init.assetId);
}

/** Best-effort owner delete of a published asset by its ref. Never throws. */
export async function deleteViaMediaApi({ ref, accessToken, apiBase = '' }) {
  const parsed = parseR2Ref(ref);
  if (!parsed || !accessToken) return false;
  try {
    const r = await postMedia(apiBase, accessToken, { op: 'delete', assetId: parsed.assetId });
    return r.ok;
  } catch {
    return false;
  }
}

/** Fire-and-forget: asks the server to unpublish R2 copies of an event that is no longer public. Never throws. */
export async function reconcileEventViaMediaApi({ eventId, accessToken, apiBase = '' }) {
  if (!eventId || !accessToken) return false;
  try {
    const r = await postMedia(apiBase, accessToken, { op: 'reconcile', eventId });
    return r.ok;
  } catch {
    return false;
  }
}

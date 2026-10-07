// Custom keychain art: local validation + re-encode + the contract upload flow
// (keychain_init -> uploadToSignedUrl -> keychain_finalize -> save_my_keychain).
// Only local files are ever read; no remote URL is fetched. SVG is never accepted.
export const KEYCHAIN_MAX_EDGE = 512;
export const KEYCHAIN_MAX_BYTES = 256 * 1024;
export const KEYCHAIN_BUCKET = 'keychain-art';
export const KEYCHAIN_INPUT_ACCEPT = 'image/png,image/webp';

const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const ascii = (b, o, s) => [...s].every((c, i) => b[o + i] === c.charCodeAt(0));

/** Real format from magic bytes: 'png' | 'webp' | null (SVG/HTML/GIF/JPEG/anything else). */
export function sniffImageFormat(bytes) {
  if (!bytes || bytes.length < 12) return null;
  if (PNG_SIG.every((v, i) => bytes[i] === v)) return 'png';
  if (ascii(bytes, 0, 'RIFF') && ascii(bytes, 8, 'WEBP')) return 'webp';
  return null;
}

/** True for APNG (acTL chunk before IDAT) or animated WebP (VP8X animation flag / ANIM chunk). */
export function isAnimated(bytes, format) {
  if (format === 'png') {
    let o = 8;
    while (o + 8 <= bytes.length) {
      const len = ((bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3]) >>> 0;
      if (ascii(bytes, o + 4, 'acTL')) return true;
      if (ascii(bytes, o + 4, 'IDAT')) return false;
      o += 12 + len;
    }
    return false;
  }
  if (format === 'webp') {
    if (ascii(bytes, 12, 'VP8X') && bytes.length > 20 && (bytes[20] & 0x02)) return true;
    return false;
  }
  return false;
}

/** Pure pre-decode validation of the picked file's leading bytes. Returns {ok,format} or {ok:false,code}. */
export function validatePickedBytes(bytes, declaredType) {
  const format = sniffImageFormat(bytes);
  if (!format) return { ok: false, code: 'BAD_FORMAT' };
  if (declaredType && declaredType !== `image/${format}`) return { ok: false, code: 'BAD_FORMAT' };
  if (isAnimated(bytes, format)) return { ok: false, code: 'ANIMATED' };
  return { ok: true, format };
}

/** Pure post-encode validation. */
export function validateProcessed({ bytes, width, height }) {
  if (!(width > 0 && height > 0)) return { ok: false, code: 'BAD_FORMAT' };
  if (Math.max(width, height) > KEYCHAIN_MAX_EDGE) return { ok: false, code: 'TOO_BIG_DIMENSIONS' };
  if (bytes > KEYCHAIN_MAX_BYTES) return { ok: false, code: 'TOO_LARGE' };
  return { ok: true };
}

export const KEYCHAIN_ERRORS = {
  BAD_FORMAT: ['Chỉ nhận ảnh PNG hoặc WebP thật (không nhận SVG, GIF hay file đổi đuôi).', 'Only real PNG or WebP images are accepted (no SVG, GIF or renamed files).'],
  ANIMATED: ['Không nhận ảnh động. Hãy dùng ảnh tĩnh.', 'Animated images are not accepted. Use a still image.'],
  TOO_LARGE: ['Ảnh vẫn quá nặng (tối đa 256 KB) sau khi nén. Thử ảnh đơn giản hơn.', 'Image is still over 256 KB after compression. Try a simpler image.'],
  TOO_BIG_DIMENSIONS: ['Ảnh quá lớn (cạnh dài tối đa 512 px).', 'Image is too large (long edge max 512 px).'],
  QUOTA: ['Bạn đã dùng hết 3 ảnh tuỳ chỉnh. Hãy xoá bớt một ảnh trước.', 'You have reached the limit of 3 custom images. Remove one first.'],
  RATE_LIMITED: ['Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.', 'Too many attempts. Please try again in a few minutes.'],
  DECODE: ['Không đọc được ảnh này.', 'This image could not be read.'],
  AUTH: ['Vui lòng đăng nhập lại.', 'Please sign in again.'],
  NETWORK: ['Lỗi mạng. Vui lòng thử lại.', 'Network error. Please try again.'],
  GENERIC: ['Không thể lưu ảnh. Vui lòng thử lại.', 'Could not save the image. Please try again.'],
};

/** Maps any backend / local error code or message to a KEYCHAIN_ERRORS key. */
export function mapKeychainError(err) {
  const raw = String(typeof err === 'string' ? err : (err?.code || err?.error || err?.message || '')).toUpperCase();
  if (KEYCHAIN_ERRORS[raw]) return raw;
  if (/QUOTA|LIMIT_REACHED|TOO_MANY_ASSETS|MAX_ASSETS/.test(raw)) return 'QUOTA';
  if (/RATE|THROTTLE|429/.test(raw)) return 'RATE_LIMITED';
  if (/ANIM/.test(raw)) return 'ANIMATED';
  if (/DIMENSION|RESOLUTION/.test(raw)) return 'TOO_BIG_DIMENSIONS';
  if (/LARGE|SIZE|TOO_BIG/.test(raw)) return 'TOO_LARGE';
  if (/FORMAT|MAGIC|CONTENT_?TYPE|MIME|SVG/.test(raw)) return 'BAD_FORMAT';
  if (/UNAUTH|AUTH|TOKEN|401|403/.test(raw)) return 'AUTH';
  if (/NETWORK|FETCH/.test(raw)) return 'NETWORK';
  return 'GENERIC';
}

export class KeychainUploadError extends Error {
  constructor(code, cause) { super(code); this.name = 'KeychainUploadError'; this.code = mapKeychainError(code); this.cause = cause; }
}

async function postMedia(fetchImpl, apiBase, token, body) {
  let res;
  try {
    res = await fetchImpl(`${apiBase || ''}/api/media`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(body),
    });
  } catch (e) { throw new KeychainUploadError('NETWORK', e); }
  let json = null;
  try { json = await res.json(); } catch { /* non-JSON */ }
  if (!res.ok || (json && json.error)) throw new KeychainUploadError(json?.error || json?.code || `HTTP_${res.status}`);
  return json || {};
}

/**
 * Contract flow. `blob` must already be a validated PNG/WebP Blob.
 * deps: { supabase, fetchImpl, accessToken, apiBase }
 * `config` = the config to save (enabled/anchor/size/motionEnabled/...); designId is forced to 'custom'.
 * `oldAssetId` is deleted AFTER the save succeeds. Returns { keychain, asset }.
 */
export async function uploadAndSaveCustomArt({ supabase, fetchImpl = globalThis.fetch, accessToken, apiBase = '' }, { blob, contentType, config, oldAssetId }) {
  if (!accessToken) throw new KeychainUploadError('AUTH');
  const init = await postMedia(fetchImpl, apiBase, accessToken, { op: 'keychain_init', contentType, bytes: blob.size });
  if (!init.assetId || !init.path || !init.token) throw new KeychainUploadError('GENERIC');
  const cleanup = async () => { try { await postMedia(fetchImpl, apiBase, accessToken, { op: 'keychain_delete', assetId: init.assetId }); } catch { /* best effort */ } };
  try {
    const { error: upErr } = await supabase.storage.from(KEYCHAIN_BUCKET).uploadToSignedUrl(init.path, init.token, blob, { contentType });
    if (upErr) throw new KeychainUploadError(upErr.message || 'GENERIC', upErr);
    const fin = await postMedia(fetchImpl, apiBase, accessToken, { op: 'keychain_finalize', assetId: init.assetId });
    const { data, error } = await supabase.rpc('save_my_keychain', {
      p_config: { ...config, designId: 'custom', customAssetId: init.assetId },
    });
    if (error || !data?.success) throw new KeychainUploadError(error?.message || data?.error || 'GENERIC', error);
    if (oldAssetId && oldAssetId !== init.assetId) {
      try { await postMedia(fetchImpl, apiBase, accessToken, { op: 'keychain_delete', assetId: oldAssetId }); } catch { /* old asset leak is non-fatal */ }
    }
    return { keychain: data.keychain, asset: { assetId: init.assetId, path: fin.path || init.path, width: fin.width, height: fin.height } };
  } catch (e) {
    await cleanup();
    throw e instanceof KeychainUploadError ? e : new KeychainUploadError('GENERIC', e);
  }
}

export async function deleteCustomArt({ fetchImpl = globalThis.fetch, accessToken, apiBase = '' }, assetId) {
  if (!accessToken) throw new KeychainUploadError('AUTH');
  await postMedia(fetchImpl, apiBase, accessToken, { op: 'keychain_delete', assetId });
}

// ---- Browser-only: decode + canvas re-encode (strips EXIF/GPS and any ancillary chunks) ----

/** Reads the picked File, rejects non-PNG/WebP by magic bytes, downscales to <=512, re-encodes PNG <=256KB. */
export async function prepareCustomArt(file) {
  if (!file || (file.type && !/^image\/(png|webp)$/.test(file.type))) throw new KeychainUploadError('BAD_FORMAT');
  const head = new Uint8Array(await file.slice(0, 64).arrayBuffer());
  const v = validatePickedBytes(head, null);
  if (!v.ok) throw new KeychainUploadError(v.code);
  if (v.format === 'png' || v.format === 'webp') {
    // Animated PNG chunks can sit past 64 bytes; scan the first 4 KB.
    const more = new Uint8Array(await file.slice(0, 4096).arrayBuffer());
    if (isAnimated(more, v.format)) throw new KeychainUploadError('ANIMATED');
  }
  let bmp;
  try { bmp = await createImageBitmap(file); } catch { throw new KeychainUploadError('DECODE'); }
  try {
    let edge = Math.min(KEYCHAIN_MAX_EDGE, Math.max(bmp.width, bmp.height));
    for (let i = 0; i < 6; i++) {
      const scale = Math.min(1, edge / Math.max(bmp.width, bmp.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.round(bmp.width * scale));
      canvas.height = Math.max(1, Math.round(bmp.height * scale));
      canvas.getContext('2d').drawImage(bmp, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise((res) => canvas.toBlob(res, 'image/png'));
      if (!blob) throw new KeychainUploadError('DECODE');
      const chk = validateProcessed({ bytes: blob.size, width: canvas.width, height: canvas.height });
      if (chk.ok) return { blob, contentType: 'image/png', width: canvas.width, height: canvas.height };
      if (chk.code !== 'TOO_LARGE') throw new KeychainUploadError(chk.code);
      edge = Math.round(edge * 0.8);
    }
    throw new KeychainUploadError('TOO_LARGE');
  } finally { bmp.close?.(); }
}

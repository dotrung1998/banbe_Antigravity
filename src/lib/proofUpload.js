// Normalizes a picked receipt file before it's handed to Supabase Storage.
//
// The 'pay-proof' bucket only allows image/jpeg, image/png, image/webp and
// application/pdf, capped at 5 MB (supabase/migrations/20260913000024_024_payments_and_documents.sql).
// A browser's <input type="file" accept="image/*,...">, though, will happily
// hand back anything the OS considers a photo — HEIC straight off an iPhone,
// a GIF, a BMP, a TIFF scan, or a file whose MIME type the browser couldn't
// determine at all (some Android file pickers report an empty `file.type`
// for a renamed file) — and a full-resolution phone camera photo commonly
// runs 6-12 MB even as a JPEG, well past that cap on its own, format aside.
//
// Rather than reject either case up front, re-encode anything outside the
// allowlist OR over the size cap to a JPEG via canvas, downscaling as far as
// it takes to land under the limit — any format a browser can paint into an
// <img> (which includes HEIC in Safari) it can also read back out of a
// canvas as image/jpeg, so this makes the upload succeed regardless of the
// source format or resolution instead of asking the guest to go find a
// smaller, "supported" photo themselves.
export const ALLOWED_PROOF_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);
export const MAX_PROOF_BYTES = 5 * 1024 * 1024;

const EXT_BY_TYPE = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' };
// A receipt only needs to be legible, not print-quality — capping the long
// edge keeps a 12MP+ photo comfortably under MAX_PROOF_BYTES without a long
// quality-reduction hunt.
const START_MAX_DIMENSION = 2000;
const QUALITY_STEPS = [0.85, 0.7, 0.55, 0.4];

function looksLikePdf(file) {
  return file.type === 'application/pdf' || /\.pdf$/i.test(file.name || '');
}

/** Decodes `file` into a paintable source, however the browser can manage it. */
async function decodeToPaintable(file) {
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(file);
    } catch {
      // Falls through to the <img> path below — some browsers' createImageBitmap
      // doesn't understand a given source (e.g. certain HEIC variants) even
      // though an <img> tag, which uses the OS/platform decoder, still can.
    }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = new Image();
    img.src = url;
    if (img.decode) await img.decode();
    else await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; });
    return img;
  } finally {
    URL.revokeObjectURL(url);
  }
}

function canvasToBlob(canvas, quality) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('CONVERT_FAILED'))), 'image/jpeg', quality);
  });
}

/**
 * Draws `source` onto a canvas no larger than `maxDim` on its long edge,
 * then tries each quality step until the resulting JPEG blob fits under
 * MAX_PROOF_BYTES — shrinking the canvas further and repeating if even the
 * lowest quality step doesn't. Always returns *something* (the smallest
 * attempt) rather than looping forever, even if it can't get under the cap.
 */
async function reencodeUnderLimit(source, width, height) {
  let dim = Math.min(START_MAX_DIMENSION, Math.max(width, height));
  let lastBlob = null;
  for (let attempt = 0; attempt < 6; attempt++) {
    const scale = Math.min(1, dim / Math.max(width, height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    const ctx = canvas.getContext('2d');
    ctx.drawImage(source, 0, 0, canvas.width, canvas.height);

    for (const quality of QUALITY_STEPS) {
      const blob = await canvasToBlob(canvas, quality);
      lastBlob = blob;
      if (blob.size <= MAX_PROOF_BYTES) return blob;
    }
    dim = Math.round(dim * 0.7);
  }
  return lastBlob; // best effort — smallest size this device could produce
}

/**
 * Returns `{ blob, ext, contentType }` ready to upload to 'pay-proof'.
 * A file already in the bucket's allowlist AND under its size cap passes
 * through unchanged (still worth doing even then — it's what lets the
 * caller always pass an explicit `contentType` instead of trusting the
 * browser's own MIME sniff, which supabase-js otherwise falls back to).
 * Anything else — wrong format, oversized, or both — is re-encoded to a
 * downscaled JPEG that fits. Throws CONVERT_FAILED if the browser genuinely
 * cannot decode the file at all (a truly corrupt file, not just an unusual
 * format or a large one).
 */
export async function normalizeProofFile(file) {
  if (ALLOWED_PROOF_TYPES.has(file.type) && file.size <= MAX_PROOF_BYTES) {
    if (file.type === 'application/pdf') return { blob: file, ext: 'pdf', contentType: 'application/pdf', width: null, height: null };
    // Chat attachments (07-notifications.md) need the true intrinsic
    // width/height to render an aspect-ratio-correct bubble — probe it even
    // on the pass-through path (no re-encode needed, just a decode).
    const { width, height } = await probeImageDimensions(file);
    return { blob: file, ext: EXT_BY_TYPE[file.type], contentType: file.type, width, height };
  }
  if (looksLikePdf(file)) {
    // Canvas can't re-encode a PDF — nothing to do but pass it through and
    // let the real error (oversized/rejected) surface from Storage.
    return { blob: file, ext: 'pdf', contentType: 'application/pdf', width: null, height: null };
  }

  let source;
  try {
    source = await decodeToPaintable(file);
  } catch {
    throw new Error('CONVERT_FAILED');
  }
  const width = source.width || source.naturalWidth;
  const height = source.height || source.naturalHeight;
  const blob = await reencodeUnderLimit(source, width, height);
  if (source.close) source.close(); // release an ImageBitmap's backing memory
  return { blob, ext: 'jpg', contentType: 'image/jpeg', width, height };
}

async function probeImageDimensions(file) {
  try {
    const source = await decodeToPaintable(file);
    const width = source.width || source.naturalWidth;
    const height = source.height || source.naturalHeight;
    if (source.close) source.close();
    return { width: width || null, height: height || null };
  } catch {
    return { width: null, height: null }; // not fatal — caller falls back to a default box
  }
}

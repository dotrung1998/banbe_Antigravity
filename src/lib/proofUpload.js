// Normalizes a picked receipt file before it's handed to Supabase Storage.
//
// The 'pay-proof' bucket only allows image/jpeg, image/png, image/webp and
// application/pdf (supabase/migrations/20260913000024_024_payments_and_documents.sql).
// A browser's <input type="file" accept="image/*,...">, though, will happily
// hand back anything the OS considers a photo — HEIC straight off an iPhone,
// a GIF, a BMP, a TIFF scan, or a file whose MIME type the browser couldn't
// determine at all (some Android file pickers report an empty `file.type`
// for a renamed file). Uploading any of those as-is is rejected by the
// bucket's own allowlist, which is exactly the "Couldn't submit" a tester
// hits when trying "some random image" rather than a fresh camera JPEG.
//
// Rather than reject those up front, re-encode anything outside the
// allowlist to a JPEG via canvas — any format a browser can paint into an
// <img> (which includes HEIC in Safari) it can also read back out of a
// canvas as image/jpeg, so this makes the upload succeed regardless of the
// source format instead of asking the guest to go find a "supported" photo.
export const ALLOWED_PROOF_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

const EXT_BY_TYPE = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'application/pdf': 'pdf' };

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

/**
 * Returns `{ blob, ext, contentType }` ready to upload to 'pay-proof'.
 * A file already in the bucket's allowlist passes through unchanged (still
 * worth doing — it's what lets the caller always pass an explicit
 * `contentType` instead of trusting the browser's own MIME sniff, which
 * supabase-js otherwise falls back to). Anything else is re-encoded to JPEG.
 * Throws CONVERT_FAILED if the browser genuinely cannot decode the file at
 * all (a truly corrupt file, not just an unusual format).
 */
export async function normalizeProofFile(file) {
  if (ALLOWED_PROOF_TYPES.has(file.type)) {
    return { blob: file, ext: EXT_BY_TYPE[file.type], contentType: file.type };
  }
  if (looksLikePdf(file)) {
    return { blob: file, ext: 'pdf', contentType: 'application/pdf' };
  }

  let source;
  try {
    source = await decodeToPaintable(file);
  } catch {
    throw new Error('CONVERT_FAILED');
  }
  const width = source.width || source.naturalWidth;
  const height = source.height || source.naturalHeight;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(source, 0, 0, width, height);
  if (source.close) source.close(); // release an ImageBitmap's backing memory

  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('CONVERT_FAILED'))), 'image/jpeg', 0.9);
  });
  return { blob, ext: 'jpg', contentType: 'image/jpeg' };
}

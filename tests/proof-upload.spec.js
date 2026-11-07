// @ts-check
import { test, expect } from '@playwright/test';
import { normalizeProofFile, ALLOWED_PROOF_TYPES } from '../src/lib/proofUpload.js';

test('an oversized PNG (allowed type, over the 5MB bucket cap) is downscaled to fit', async ({ page }) => {
  // A real full-resolution phone photo commonly exceeds the bucket's 5MB
  // cap on its own, format aside — this was still failing after the
  // format-only fix, since an already-allowed type short-circuited straight
  // to a pass-through upload with no size check at all.
  await page.goto('/');
  const result = await page.evaluate(async () => {
    const canvas = document.createElement('canvas');
    canvas.width = 4000; canvas.height = 3000;
    const ctx = canvas.getContext('2d');
    // Noise, not a flat fill — flat colors compress to almost nothing and
    // would never exceed the cap, defeating the point of this test.
    const imgData = ctx.createImageData(canvas.width, canvas.height);
    for (let i = 0; i < imgData.data.length; i++) imgData.data[i] = Math.floor(Math.random() * 256);
    ctx.putImageData(imgData, 0, 0);
    const pngBlob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    const file = new File([pngBlob], 'huge.png', { type: 'image/png' });

    const mod = await import('/src/lib/proofUpload.js');
    const before = file.size;
    const { blob, ext, contentType } = await mod.normalizeProofFile(file);
    return { before, after: blob.size, ext, contentType, maxBytes: mod.MAX_PROOF_BYTES };
  });
  expect(result.before).toBeGreaterThan(result.maxBytes); // sanity: the source really was oversized
  expect(result.ext).toBe('jpg');
  expect(result.contentType).toBe('image/jpeg');
  expect(result.after).toBeLessThanOrEqual(result.maxBytes);
});

// Only the synchronous, non-canvas branches are exercised here (Node has no
// Image/createImageBitmap/<canvas>) — the re-encode path itself is covered
// by the app build + manual verification, since it needs a real browser.
test.describe('normalizeProofFile — pass-through branches', () => {
  // 07-notifications.md follow-up (chat-image aspect ratio) — normalizeProofFile
  // now also returns width/height, probed via decodeToPaintable() even on
  // this pass-through path. A plain mock object (not a real decodable
  // Blob/File) can't actually be decoded, so probeImageDimensions()'s own
  // catch branch returns null/null here — width/height are only ever
  // non-null against a real image in a real browser (see Chat.jsx's own
  // manual verification, not exercised by this Node-side mock).
  test('an already-allowed image type passes through unchanged', async () => {
    const file = { type: 'image/png', name: 'receipt.png', size: 1024 };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'png', contentType: 'image/png', width: null, height: null });
  });

  test('a PDF by MIME type passes through unchanged', async () => {
    const file = { type: 'application/pdf', name: 'receipt.pdf' };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'pdf', contentType: 'application/pdf', width: null, height: null });
  });

  test('a PDF with a generic/blank MIME type is still recognized by extension', async () => {
    const file = { type: '', name: 'Scanned Receipt.PDF' };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'pdf', contentType: 'application/pdf', width: null, height: null });
  });

  test('the allowlist matches the pay-proof bucket exactly', () => {
    expect([...ALLOWED_PROOF_TYPES].sort()).toEqual(
      ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'].sort()
    );
  });
});

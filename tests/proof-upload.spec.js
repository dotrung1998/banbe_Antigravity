// @ts-check
import { test, expect } from '@playwright/test';
import { normalizeProofFile, ALLOWED_PROOF_TYPES } from '../src/lib/proofUpload.js';

// Only the synchronous, non-canvas branches are exercised here (Node has no
// Image/createImageBitmap/<canvas>) — the re-encode path itself is covered
// by the app build + manual verification, since it needs a real browser.
test.describe('normalizeProofFile — pass-through branches', () => {
  test('an already-allowed image type passes through unchanged', async () => {
    const file = { type: 'image/png', name: 'receipt.png' };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'png', contentType: 'image/png' });
  });

  test('a PDF by MIME type passes through unchanged', async () => {
    const file = { type: 'application/pdf', name: 'receipt.pdf' };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'pdf', contentType: 'application/pdf' });
  });

  test('a PDF with a generic/blank MIME type is still recognized by extension', async () => {
    const file = { type: '', name: 'Scanned Receipt.PDF' };
    const result = await normalizeProofFile(file);
    expect(result).toEqual({ blob: file, ext: 'pdf', contentType: 'application/pdf' });
  });

  test('the allowlist matches the pay-proof bucket exactly', () => {
    expect([...ALLOWED_PROOF_TYPES].sort()).toEqual(
      ['application/pdf', 'image/jpeg', 'image/png', 'image/webp'].sort()
    );
  });
});

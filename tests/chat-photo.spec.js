// @ts-check
import { test, expect } from '@playwright/test';
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

// A small standalone CRC32 (PNG's own algorithm) rather than relying on
// `zlib.crc32`, which isn't available on every Node version this suite
// might run under — needed for a browser's PNG decoder to accept the file
// at all (a bad chunk CRC is rejected, not just ignored).
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// Task 1/2 (07-notifications.md follow-up) — the chat-image aspect-ratio
// fix and its dedicated fullscreen viewer, tested against a REAL seeded
// event with a real organizer_id (`phong302` — 010_seed_data.sql, has a
// matching `events`/`organizers` row, unlike most of the static demo
// catalogue) so openChatFor() actually creates/opens a real `threads` row.

function makePng(dir, name, w, h) {
  // A minimal, valid, uncompressed PNG built by hand (no canvas — this
  // runs in Node, not a browser) so the upload path has a real decodable
  // image at an EXACT, known w/h — normalizeProofFile passes an
  // already-allowed, under-cap image straight through with no re-encode,
  // so the browser's own naturalWidth/naturalHeight matches these exactly.
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const typeBuf = Buffer.from(type);
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0; // 8-bit RGB
  const rowBytes = w * 3;
  const raw = Buffer.alloc((rowBytes + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (rowBytes + 1)] = 0;
    for (let x = 0; x < rowBytes; x++) raw[y * (rowBytes + 1) + 1 + x] = (x + y) % 200 + 20;
  }
  const idat = zlib.deflateSync(raw);
  const png = Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
  mkdirSync(dir, { recursive: true });
  const file = path.join(dir, name);
  writeFileSync(file, png);
  return file;
}

// This thread (`phong302`'s organizer, opened by the shared persistent test
// account) is a real DB row that accumulates messages across every run of
// this file/session — neither `.last()` nor a before/after element-count
// diff proved reliable against it (both raced the async
// loadChatMessages()/sign fetch in earlier iterations of this test,
// directly observed reading as low as a stale 0 before that fetch had even
// started). Matching by the uploaded image's own EXACT pixel dimensions
// sidesteps the ordering/timing race entirely — there is exactly one
// message in this thread with this test's own size at any given moment.
// Returns the matching element's index among all `[data-testid="chat-attachment"]`
// nodes, so the caller can build a normal, interactable Locator from it.
async function findAttachmentIndex(page, w, h) {
  return await expect.poll(async () => {
    return await page.evaluate(([width, height]) => {
      const imgs = Array.from(document.querySelectorAll('[data-testid="chat-attachment"]'));
      return imgs.findIndex(el => el.tagName === 'IMG' && el.naturalWidth === width && el.naturalHeight === height);
    }, [w, h]);
  }, { timeout: 20000, message: `no chat-attachment img with naturalWidth=${w}/naturalHeight=${h} appeared` }).not.toBe(-1)
    .then(() => page.evaluate(([width, height]) => {
      const imgs = Array.from(document.querySelectorAll('[data-testid="chat-attachment"]'));
      return imgs.findIndex(el => el.tagName === 'IMG' && el.naturalWidth === width && el.naturalHeight === height);
    }, [w, h]));
}

async function openChatWithPhong302(page) {
  await page.goto('/?org=phong302');
  await expect(page.locator('[data-screen-label="Organizer"]')).toBeVisible({ timeout: 8000 });
  // A fresh full-page navigation re-hydrates the storageState session
  // asynchronously (confirmed by direct observation — the button is
  // interactive immediately, but goChat()/openChatFor() reads `s.user`
  // before that hydration resolves and silently bounces to Login if
  // clicked too early). Waiting here, not a shorter arbitrary amount.
  await page.waitForTimeout(2500);
  await page.click('[data-testid="organizer-message"]');
  await page.waitForSelector('[data-screen-label="Chat"]');
}

test.describe('Chat photo — aspect ratio + fullscreen viewer (Task 1/2, 07-notifications.md)', () => {
  test('a portrait image renders as a tall box (not square/letterboxed) and opens fullscreen', async ({ page }, testInfo) => {
    await openChatWithPhong302(page);
    await expect(page.locator('[data-testid="chat-back"]')).toBeVisible();

    const w = 301, h = 602; // 1:2 portrait, an odd size unlikely to collide with a prior run's upload
    const file = makePng(testInfo.outputDir, 'portrait.png', w, h);
    await page.click('[data-testid="chat-attach-toggle"]');
    await page.click('[data-testid="chat-attach-file"]');
    await page.setInputFiles('[data-testid="chat-file-input"]', file);

    const index = await findAttachmentIndex(page, w, h);
    const img = page.locator('[data-testid="chat-attachment"]').nth(index);
    const box = await img.boundingBox();
    expect(box).toBeTruthy();
    // Portrait source (~1:2) inside the 240x320 max box lands well short of
    // 220 wide — taller than wide, not the old fixed 220x220 square.
    expect(box.height).toBeGreaterThan(box.width);
    expect(box.width).toBeLessThan(220);

    await img.click();
    await expect(page.locator('[data-screen-label="Chat photo viewer"]')).toBeVisible();
    await expect(page.locator('[data-testid="chat-photo-viewer-image"]')).toBeVisible();
    await page.click('[data-testid="chat-photo-close"]');
    await expect(page.locator('[data-screen-label="Chat"]')).toBeVisible(); // dismiss returns to the exact same chat
  });

  test('a landscape image renders as a wide box, a square image as a square box', async ({ page }, testInfo) => {
    await openChatWithPhong302(page);

    const w1 = 603, h1 = 301; // landscape
    const landscape = makePng(testInfo.outputDir, 'landscape.png', w1, h1);
    await page.click('[data-testid="chat-attach-toggle"]');
    await page.click('[data-testid="chat-attach-file"]');
    await page.setInputFiles('[data-testid="chat-file-input"]', landscape);
    const index1 = await findAttachmentIndex(page, w1, h1);
    const box1 = await page.locator('[data-testid="chat-attachment"]').nth(index1).boundingBox();
    expect(box1.width).toBeGreaterThan(box1.height);

    const w2 = 401, h2 = 401; // square
    const square = makePng(testInfo.outputDir, 'square.png', w2, h2);
    await page.click('[data-testid="chat-attach-toggle"]');
    await page.click('[data-testid="chat-attach-file"]');
    await page.setInputFiles('[data-testid="chat-file-input"]', square);
    const index2 = await findAttachmentIndex(page, w2, h2);
    const box2 = await page.locator('[data-testid="chat-attachment"]').nth(index2).boundingBox();
    expect(Math.abs(box2.width - box2.height)).toBeLessThan(3); // square, allowing sub-pixel rounding
  });

  test('the viewer does NOT churn the signed URL on a 4s+ poll cycle (the bc4724d bug class)', async ({ page }, testInfo) => {
    await openChatWithPhong302(page);

    const w = 305, h = 305;
    const file = makePng(testInfo.outputDir, 'stable.png', w, h);
    await page.click('[data-testid="chat-attach-toggle"]');
    await page.click('[data-testid="chat-attach-file"]');
    await page.setInputFiles('[data-testid="chat-file-input"]', file);
    const index = await findAttachmentIndex(page, w, h);
    const img = page.locator('[data-testid="chat-attachment"]').nth(index);
    const srcBefore = await img.getAttribute('src');
    await page.waitForTimeout(5500); // past one 4s poll cycle
    const srcAfter = await img.getAttribute('src');
    expect(srcAfter).toBe(srcBefore);
  });
});

/* Audit the onboarding frame set: 8 steps × 4 viewports.
   For every live step/size:
     - documentElement.scrollWidth === clientWidth
     - exactly that step's section is visible
     - no broken images
     - at 390, no visible control is shorter than 44 px
     - no console.error and no pageerror
   For the files: exactly the 32 frames + the overview, each a PNG of the
   expected size.

   Usage (preview server already running):
     node docs/prototypes/day-01-baseline/onboarding/check-frames.mjs
     node ... --url http://127.0.0.1:4174/day-01-baseline/onboarding/index.html
*/
import { chromium } from 'playwright';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const urlAt = args.indexOf('--url');
const baseUrl = urlAt >= 0 && args[urlAt + 1]
  ? args[urlAt + 1]
  : 'http://127.0.0.1:4174/day-01-baseline/onboarding/index.html';
const framesDir = path.resolve(here, '../frames');
const STEPS = [1, 2, 3, 4, 5, 6, 7, 8];
const SIZES = [
  { w: 390, h: 844 },
  { w: 834, h: 1194 },
  { w: 1194, h: 834 },
  { w: 1440, h: 900 },
];
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const pngSize = (bytes) => ({ w: bytes.readUInt32BE(16), h: bytes.readUInt32BE(20) });
const pad2 = (n) => String(n).padStart(2, '0');
const failures = [];

/* ── files: the 32 frames + one 8×4 overview, and nothing else ─────── */
const frames = STEPS.flatMap((step) => SIZES.map((size) => ({
  size,
  name: `onboarding-${pad2(step)}-${size.w}.png`,
})));
const overviewName = 'onboarding-overview-1440.png';
const present = (await readdir(framesDir)).filter((name) => name.startsWith('onboarding-') && name.endsWith('.png'));
const expected = [...frames.map((frame) => frame.name), overviewName];
if (present.sort().join('|') !== expected.sort().join('|')) {
  failures.push(`file set mismatch: expected ${frames.length} frames + overview, found ${present.length} PNGs`);
}
for (const frame of frames) {
  if (!present.includes(frame.name)) continue;
  const bytes = await readFile(path.join(framesDir, frame.name));
  if (!bytes.subarray(0, 8).equals(PNG_SIG)) {
    failures.push(`${frame.name}: not a PNG`);
    continue;
  }
  const { w, h } = pngSize(bytes);
  if (w !== frame.size.w || h !== frame.size.h) failures.push(`${frame.name}: ${w}×${h}, expected ${frame.size.w}×${frame.size.h}`);
}
let overview = null;
if (present.includes(overviewName)) {
  const overviewBytes = await readFile(path.join(framesDir, overviewName));
  overview = overviewBytes.subarray(0, 8).equals(PNG_SIG) ? pngSize(overviewBytes) : null;
  if (!overview) failures.push(`${overviewName}: not a PNG`);
  else if (overview.w !== 1440) failures.push(`${overviewName}: width ${overview.w}, expected 1440`);
}
console.log(`files: ${frames.length} frames + overview${overview ? ` (${overview.w}×${overview.h})` : ''}, ${present.length} PNGs`);

/* ── live pages: every step at every size ──────────────────────────── */
const browser = await chromium.launch();
let passed = 0;
try {
  for (const step of STEPS) {
    for (const size of SIZES) {
      const context = await browser.newContext({
        viewport: { width: size.w, height: size.h },
        deviceScaleFactor: 1,
        colorScheme: 'light',
        locale: 'vi-VN',
        timezoneId: 'Asia/Ho_Chi_Minh',
        reducedMotion: 'reduce',
      });
      const page = await context.newPage();
      const errors = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error') errors.push(`console: ${msg.text()}`);
      });
      page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`));

      const target = new URL(baseUrl);
      target.searchParams.set('embed', '1');
      target.searchParams.set('step', String(step));
      target.searchParams.set('capture', '1');
      target.hash = '';
      await page.goto(target.toString(), { waitUntil: 'load', timeout: 30_000 });
      await page.waitForFunction(() => document.documentElement.dataset.stageReady === '1', null, { timeout: 10_000 });
      await page.evaluate(async () => {
        if (document.fonts?.ready) await document.fonts.ready;
        await Promise.all([...document.images].map((image) => (image.complete
          ? Promise.resolve()
          : new Promise((resolve) => {
              image.addEventListener('load', resolve, { once: true });
              image.addEventListener('error', resolve, { once: true });
            }))));
      });
      await page.waitForTimeout(150);

      const m = await page.evaluate((expectedStep) => {
        const doc = document.documentElement;
        const visible = [...document.querySelectorAll('[data-step]')]
          .filter((section) => {
            const rect = section.getBoundingClientRect();
            return !section.hidden && getComputedStyle(section).display !== 'none' && rect.width > 0 && rect.height > 0;
          })
          .map((section) => Number(section.dataset.step));
        const broken = [...document.images]
          .filter((img) => img.complete && img.naturalWidth === 0)
          .map((img) => img.currentSrc || img.src);
        const small = [...document.querySelectorAll('button, a[href], input:not([type="hidden"]), select, textarea, [role="button"], [role="switch"]')]
          .filter((el) => {
            const rect = el.getBoundingClientRect();
            const style = getComputedStyle(el);
            return rect.width > 0 && rect.height > 0
              && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) > 0
              && !el.closest('[hidden]');
          })
          .map((el) => {
            const rect = el.getBoundingClientRect();
            return {
              tag: el.tagName.toLowerCase(),
              cls: String(el.className || '').split(/\s+/).filter(Boolean).join('.'),
              text: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ').slice(0, 42),
              w: Math.round(rect.width),
              h: Math.round(rect.height),
            };
          })
          .filter((control) => control.h < 44);
        return {
          doc: [doc.scrollWidth, doc.clientWidth],
          visible,
          expectedVisible: visible.length === 1 && visible[0] === expectedStep,
          broken,
          small,
        };
      }, step);

      const overflow = m.doc[0] !== m.doc[1];
      const small = size.w === 390 ? m.small : [];
      const ok = !overflow && m.expectedVisible && m.broken.length === 0 && small.length === 0 && errors.length === 0;
      const detail = [
        `doc ${m.doc[0]}/${m.doc[1]}`,
        `sections ${m.visible.join(',') || 'none'}${m.expectedVisible ? '' : ' FAIL'}`,
        `broken ${m.broken.length}`,
        size.w === 390 ? `small@390 ${small.length}` : null,
        `errors ${errors.length}`,
      ].filter(Boolean).join(' · ');
      console.log(`${ok ? 'PASS' : 'FAIL'} step ${step} ${size.w}: ${detail}`);
      if (ok) passed += 1;
      else {
        failures.push(`step ${step} ${size.w}: ${detail}`);
        for (const img of m.broken) failures.push(`  broken image: ${img}`);
        for (const control of small) failures.push(`  under 44px: ${control.tag}.${control.cls} h=${control.h} w=${control.w} “${control.text}”`);
        for (const error of errors) failures.push(`  ${error}`);
      }
      await context.close();
    }
  }
} finally {
  await browser.close();
}

console.log(`\n${passed}/${STEPS.length * SIZES.length} live frames pass`);
if (failures.length) {
  console.error(`\n${failures.length} failure(s):\n${failures.join('\n')}`);
  process.exitCode = 1;
} else {
  console.log('PASS: all frames — no overflow, one section, no broken images, 390 controls >=44, 0 console/page errors.');
}

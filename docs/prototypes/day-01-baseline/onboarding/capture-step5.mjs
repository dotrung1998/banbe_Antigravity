/* Capture step 5 in the answered state from the owner's screenshot.
   It seeds the prototype's own sessionStorage state (`bb:onboarding:state`),
   loads the same `?embed=1&step=5&capture=1` page as capture-stage, checks the
   three rows and the aligned action column, then writes the four PNGs.

   Values: Sở thích: Chưa chọn · Thời gian: Buổi tối, Ban ngày · Ngân sách: Đến 600.000đ.

   Usage (preview server already running):
     node docs/prototypes/day-01-baseline/onboarding/capture-step5.mjs
     node ... --url http://127.0.0.1:4174/day-01-baseline/onboarding/index.html
*/
import { chromium } from 'playwright';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const framesDir = path.resolve(here, '../frames');
const args = process.argv.slice(2);
const urlAt = args.indexOf('--url');
const baseUrl = urlAt >= 0 && args[urlAt + 1]
  ? args[urlAt + 1]
  : 'http://127.0.0.1:4174/day-01-baseline/onboarding/index.html';
const SIZES = [
  { w: 390, h: 844 },
  { w: 834, h: 1194 },
  { w: 1194, h: 834 },
  { w: 1440, h: 900 },
];
const STATE = {
  interests: [],
  availability: ['evening', 'daytime'],
  budget: 'medium',
  digest: false,
  hosting: false,
  login: { email: '', password: '', method: 'code', submitted: false },
};
const EXPECTED = [
  'Sở thích: Chưa chọn',
  'Thời gian: Buổi tối, Ban ngày',
  'Ngân sách: Đến 600.000₫',
];

const browser = await chromium.launch();
try {
  for (const size of SIZES) {
    const context = await browser.newContext({
      viewport: { width: size.w, height: size.h },
      deviceScaleFactor: 1,
      colorScheme: 'light',
      locale: 'vi-VN',
      timezoneId: 'Asia/Ho_Chi_Minh',
      reducedMotion: 'reduce',
    });
    await context.addInitScript((state) => {
      sessionStorage.setItem('bb:onboarding:state', JSON.stringify(state));
    }, STATE);
    const page = await context.newPage();
    const target = new URL(baseUrl);
    target.searchParams.set('embed', '1');
    target.searchParams.set('step', '5');
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
    await page.waitForTimeout(250);

    const state = await page.evaluate(() => {
      const wrap = document.querySelector('[data-reveal-answers]');
      const rows = [...wrap.querySelectorAll('.chip')];
      return {
        doc: [document.documentElement.scrollWidth, document.documentElement.clientWidth],
        card: Math.round(wrap.getBoundingClientRect().width),
        labels: rows.map((row) => row.querySelector('.chip-copy').innerText.replace(/\s+/g, ' ').trim()),
        actions: rows.map((row) => {
          const rect = row.querySelector('a').getBoundingClientRect();
          return { left: Math.round(rect.left), height: Math.round(rect.height) };
        }),
      };
    });
    if (state.doc[0] !== state.doc[1]) throw new Error(`${size.w}: horizontal overflow ${state.doc.join('/')}`);
    if (JSON.stringify(state.labels) !== JSON.stringify(EXPECTED)) {
      throw new Error(`${size.w}: unexpected rows ${JSON.stringify(state.labels)}`);
    }
    if (state.actions.some((action) => action.height < 44)) throw new Error(`${size.w}: action under 44px`);
    if (new Set(state.actions.map((action) => action.left)).size !== 1) {
      throw new Error(`${size.w}: action column is not aligned: ${JSON.stringify(state.actions)}`);
    }

    const file = `onboarding-05-${size.w}.png`;
    await page.screenshot({ path: path.join(framesDir, file), animations: 'disabled' });
    console.log(`shot ${file} · ${EXPECTED.join(' · ')} · action x ${state.actions[0].left}`);
    await context.close();
  }
} finally {
  await browser.close();
}

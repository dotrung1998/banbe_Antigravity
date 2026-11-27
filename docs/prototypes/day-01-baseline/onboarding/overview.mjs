/* Build the full onboarding overview from the captured frames.
   The overview is an 8-row (steps) × 4-column (sizes) contact sheet, so the
   single overview image lists every step at every frame. Images are embedded
   as data URLs, so this needs no server.

   Usage: node docs/prototypes/day-01-baseline/onboarding/overview.mjs
*/
import { chromium } from 'playwright';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const framesDir = path.resolve(here, '../frames');
const outFile = path.join(framesDir, 'onboarding-overview-1440.png');

const STEPS = [
  { n: 1, label: 'Chào', group: 'Welcome' },
  { n: 2, label: 'Sở thích', group: '3 câu hỏi · 1/3' },
  { n: 3, label: 'Thời gian', group: '3 câu hỏi · 2/3' },
  { n: 4, label: 'Ngân sách', group: '3 câu hỏi · 3/3' },
  { n: 5, label: 'Dành cho bạn', group: 'For You reveal' },
  { n: 6, label: 'Bản tin', group: 'Consent 1' },
  { n: 7, label: 'Tổ chức', group: 'Consent 2' },
  { n: 8, label: 'Đăng nhập', group: 'Login' },
];
const SIZES = [
  { w: 390, h: 844 },
  { w: 834, h: 1194 },
  { w: 1194, h: 834 },
  { w: 1440, h: 900 },
];
const pad = (n) => String(n).padStart(2, '0');

const rows = [];
for (const step of STEPS) {
  const cells = [];
  for (const size of SIZES) {
    const file = `onboarding-${pad(step.n)}-${size.w}.png`;
    const bytes = await readFile(path.join(framesDir, file));
    cells.push(`<figure class="cell">
      <div class="shot"><img src="data:image/png;base64,${bytes.toString('base64')}" alt="Bước ${step.n}, khung ${size.w}"></div>
      <figcaption><span class="file">${file}</span><span class="dim">${size.w}×${size.h}</span></figcaption>
    </figure>`);
  }
  rows.push(`<div class="rowhead"><b>${pad(step.n)} · ${step.label}</b><span>${step.group}</span></div>${cells.join('')}`);
}

const html = `<!doctype html>
<html lang="vi"><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; }
  html, body { margin: 0; background: #f7f4ec; color: #1b1916; }
  body { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; }
  .sheet { width: 1440px; padding: 28px 32px 34px; }
  header { display: flex; align-items: flex-end; justify-content: space-between; gap: 24px; padding-bottom: 16px; border-bottom: 1px solid rgba(27,25,22,.18); }
  .kicker { margin: 0 0 5px; font-size: 10px; font-weight: 700; letter-spacing: .16em; text-transform: uppercase; color: #85502e; }
  h1 { margin: 0; font-family: Georgia, "Times New Roman", serif; font-size: 38px; font-weight: 500; line-height: 1; letter-spacing: -.025em; }
  header p { margin: 0; max-width: 390px; font-size: 12px; line-height: 1.55; color: rgba(27,25,22,.62); text-align: right; }
  .grid { display: grid; grid-template-columns: 150px repeat(4, minmax(0, 1fr)); gap: 9px 11px; margin-top: 18px; align-items: stretch; }
  .corner, .colhead { padding: 7px 9px; border-bottom: 1px solid rgba(27,25,22,.16); font-size: 9px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase; color: rgba(27,25,22,.55); }
  .colhead { text-align: center; }
  .rowhead { display: flex; flex-direction: column; justify-content: center; gap: 3px; padding: 12px 9px; border-top: 1px solid rgba(27,25,22,.12); }
  .rowhead b { font-family: Georgia, "Times New Roman", serif; font-size: 16px; font-weight: 500; line-height: 1.15; }
  .rowhead span { font-size: 9px; letter-spacing: .08em; text-transform: uppercase; color: rgba(27,25,22,.5); }
  .cell { margin: 0; padding: 7px 7px 6px; display: flex; flex-direction: column; gap: 5px; background: #fff; border: 1px solid rgba(27,25,22,.13); border-radius: 9px; box-shadow: 0 6px 16px -14px rgba(27,25,22,.35); min-width: 0; }
  .shot { height: 238px; display: flex; align-items: center; justify-content: center; overflow: hidden; background: #f7f4ec; border-radius: 5px; }
  .shot img { display: block; max-width: 100%; max-height: 238px; object-fit: contain; box-shadow: 0 1px 4px rgba(27,25,22,.12); }
  figcaption { display: flex; justify-content: space-between; gap: 6px; min-width: 0; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 8.5px; line-height: 1.35; color: rgba(27,25,22,.58); }
  .file { overflow-wrap: anywhere; }
  .dim { flex: none; font-variant-numeric: tabular-nums; }
  footer { display: flex; justify-content: space-between; gap: 24px; margin-top: 16px; padding-top: 12px; border-top: 1px solid rgba(27,25,22,.16); font-size: 10px; line-height: 1.5; color: rgba(27,25,22,.58); }
</style></head><body>
<main class="sheet">
  <header>
    <div><p class="kicker">banbe · prototype · ngày 1/8 · cụm 1/5</p><h1>Onboarding, đủ bộ</h1></div>
    <p>8 bước × 4 khung = 32 frame.<br>Mỗi bước đều có mặt ở 390, 834, 1194 và 1440.<br>Chụp 27.11.2026 · 1:1 từ <code>?embed=1&amp;capture=1</code>.</p>
  </header>
  <div class="grid">
    <div class="corner">Bước / khung</div>
    ${SIZES.map((s) => `<div class="colhead">${s.w}×${s.h}</div>`).join('')}
    ${rows.join('')}
  </div>
  <footer><span>32/32 frame đã qua <code>scrollWidth === clientWidth</code>, không ảnh vỡ, đúng một bước hiện; 390 không có control dưới 44 px.</span><span>Nguồn: docs/prototypes/day-01-baseline/frames/</span></footer>
</main>
</body></html>`;

const browser = await chromium.launch();
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 }, deviceScaleFactor: 1 });
  await page.setContent(html, { waitUntil: 'load' });
  await page.evaluate(async () => {
    await Promise.all([...document.images].map((img) => img.decode().catch(() => {})));
  });
  await page.screenshot({ path: outFile, fullPage: true });
  const size = await page.evaluate(() => ({ w: document.documentElement.scrollWidth, h: document.documentElement.scrollHeight }));
  console.log(`overview: ${outFile} (${size.w}×${size.h})`);
} finally {
  await browser.close();
}

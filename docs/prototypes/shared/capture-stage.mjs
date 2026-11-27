// Capture a cluster prototype at the four stage sizes, plus one 4-up overview.
// Requires a static server (the stage uses fetch for the cross-cluster links):
//   npx --yes serve docs/prototypes -l 4173
// Then:
//   node docs/prototypes/shared/capture-stage.mjs \
//     --url http://127.0.0.1:4173/day-01-baseline/onboarding/index.html \
//     --out docs/prototypes/day-01-baseline/frames \
//     --cluster onboarding --steps 1,3,5
//
// Writes <cluster>-<step>-<size>.png and <cluster>-overview-1440.png, then
// appends a table to <out>/capture.md with the exact URL and date.
import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const SIZES = {
  '390': { w: 390, h: 844 },
  '834': { w: 834, h: 1194 },
  '1194': { w: 1194, h: 834 },
  '1440': { w: 1440, h: 900 },
};

const args = process.argv.slice(2);
const arg = (name, fallback = '') => {
  const index = args.indexOf(`--${name}`);
  return index > -1 ? String(args[index + 1] || '') : fallback;
};

const url = arg('url');
if (!url) {
  console.error('capture-stage: --url is required (serve docs/prototypes first)');
  process.exit(2);
}
const out = path.resolve(arg('out', 'docs/prototypes/frames'));
const cluster = arg('cluster', 'cluster');
const steps = arg('steps', '1')
  .split(',')
  .map((value) => Number.parseInt(value, 10))
  .filter((value) => Number.isFinite(value) && value > 0);
const sizes = arg('sizes', '390,834,1194,1440')
  .split(',')
  .map((value) => value.trim())
  .filter((value) => SIZES[value]);
if (!steps.length || !sizes.length) {
  console.error('capture-stage: --steps and --sizes need at least one value');
  process.exit(2);
}

const date = new Date().toISOString().slice(0, 10);
const pad2 = (value) => String(value).padStart(2, '0');
const withParams = (base, step) => {
  const target = new URL(base);
  target.searchParams.set('embed', '1');
  target.searchParams.set('step', String(step));
  target.searchParams.set('capture', '1');
  target.hash = '';
  return target.toString();
};

await mkdir(out, { recursive: true });
const browser = await chromium.launch();
const rows = [];

try {
  for (const step of steps) {
    for (const size of sizes) {
      const box = SIZES[size];
      const context = await browser.newContext({
        viewport: { width: box.w, height: box.h },
        deviceScaleFactor: 1,
        colorScheme: 'light',
        locale: 'vi-VN',
        timezoneId: 'Asia/Ho_Chi_Minh',
        reducedMotion: 'reduce',
      });
      const page = await context.newPage();
      const target = withParams(url, step);
      await page.goto(target, { waitUntil: 'load', timeout: 30_000 });
      await page.waitForFunction(() => document.documentElement.dataset.stageReady === '1', null, {
        timeout: 10_000,
      });
      await page.evaluate(async () => {
        if (document.fonts?.ready) await document.fonts.ready;
        const images = [...document.images];
        await Promise.all(
          images.map((image) =>
            image.complete
              ? Promise.resolve()
              : new Promise((resolve) => {
                  image.addEventListener('load', resolve, { once: true });
                  image.addEventListener('error', resolve, { once: true });
                })
          )
        );
      });
      await page.waitForTimeout(250);
      const file = `${cluster}-${pad2(step)}-${size}.png`;
      await page.screenshot({ path: path.join(out, file), animations: 'disabled' });
      rows.push(`| \`${file}\` | ${step} | ${box.w}×${box.h} | ${target} | ${date} |`);
      console.log(`shot ${file}`);
      await context.close();
    }
  }

  // One 4-up overview at the desktop stage size.
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1,
    colorScheme: 'light',
    locale: 'vi-VN',
    timezoneId: 'Asia/Ho_Chi_Minh',
    reducedMotion: 'reduce',
  });
  const page = await context.newPage();
  const base = new URL(url);
  base.searchParams.set('capture', '1');
  base.searchParams.delete('embed');
  base.searchParams.delete('step');
  base.hash = '';
  await page.goto(base.toString(), { waitUntil: 'load', timeout: 30_000 });
  await page.waitForFunction(() => document.documentElement.dataset.stageReady === '1', null, {
    timeout: 10_000,
  });
  await page.click('[data-size="all"]');
  await page.waitForTimeout(900);
  const overviewFile = `${cluster}-overview-1440.png`;
  await page.locator('[data-overview]').screenshot({ path: path.join(out, overviewFile) });
  rows.push(`| \`${overviewFile}\` | cả 4 | 1440×900 | ${base.toString()} | ${date} |`);
  console.log(`shot ${overviewFile}`);
  await context.close();
} finally {
  await browser.close();
}

const captureFile = path.join(out, 'capture.md');
let existing = '';
try {
  existing = await readFile(captureFile, 'utf8');
} catch {
  existing = '# Capture log\n\n| File | Bước | Khung | Nguồn | Ngày |\n| --- | --- | --- | --- | --- |\n';
}
const section = `\n## ${cluster} — ${date}\n\n| File | Bước | Khung | Nguồn | Ngày |\n| --- | --- | --- | --- | --- |\n${rows.join('\n')}\n`;
await writeFile(captureFile, `${existing.trimEnd()}\n${section}`, 'utf8');
console.log(`capture-stage: ${rows.length} image(s) → ${out}`);
console.log(`capture-stage: log → ${captureFile}`);

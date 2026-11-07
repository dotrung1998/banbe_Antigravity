// Rasterise assets/keychains/svg/*.svg -> transparent 256x384 PNGs, write to web + iOS dirs.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = path.join(root, 'assets/keychains');
const outs = [path.join(root, 'public/keychains'), path.join(root, 'apps/ios/BanbeApp/Resources/Keychains')];
const W = 256, H = 384, MAX = 30 * 1024;

const manifest = JSON.parse(fs.readFileSync(path.join(src, 'manifest.json'), 'utf8'));
const ids = manifest.designs.map((d) => d.id).sort();
const svgIds = fs.readdirSync(path.join(src, 'svg')).filter((f) => f.endsWith('.svg')).map((f) => f.slice(0, -4)).sort();
if (JSON.stringify(ids) !== JSON.stringify(svgIds)) throw new Error('manifest ids != svg files');

let executablePath;
try {
  const dir = path.join(os.homedir(), 'Library/Caches/ms-playwright');
  const ch = fs.existsSync(dir) && fs.readdirSync(dir).find((d) => d.startsWith('chromium-'));
  const cands = ch ? [path.join(dir, ch, 'chrome-mac/Chromium.app/Contents/MacOS/Chromium'), path.join(dir, ch, 'chrome-mac-arm64/Chromium.app/Contents/MacOS/Chromium')] : [];
  executablePath = cands.find((p) => fs.existsSync(p));
} catch {}
let browser;
try { browser = await chromium.launch(); } catch { browser = await chromium.launch({ executablePath }); }
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });

for (const o of outs) fs.mkdirSync(o, { recursive: true });
for (const id of ids) {
  const svg = fs.readFileSync(path.join(src, 'svg', id + '.svg'), 'utf8');
  await page.setContent(`<!doctype html><html><body style="margin:0;background:transparent">${svg}</body></html>`);
  const shot = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: W, height: H }, type: 'png' });
  // Re-encode (Paeth filter, max deflate, 5-bit opaque colour) to shrink gradient-heavy art.
  const img = PNG.sync.read(shot);
  for (let i = 0; i < img.data.length; i += 4) {
    if (img.data[i + 3] === 255) for (let k = 0; k < 3; k++) img.data[i + k] = Math.min(255, Math.round(img.data[i + k] / 8) * 8); // 5-bit colour: less gradient noise
  }
  const png = PNG.sync.write(img, { colorType: 6, deflateLevel: 9, filterType: 4 });
  if (png.readUInt32BE(16) !== W || png.readUInt32BE(20) !== H) throw new Error(id + ': bad size');
  if (![4, 6].includes(png[25])) throw new Error(id + ': no alpha');
  if (png.length > MAX) console.warn(`WARN ${id}.png is ${png.length} bytes (> 30 KB)`);
  for (const o of outs) fs.writeFileSync(path.join(o, id + '.png'), png);
}
await browser.close();
const json = JSON.stringify(manifest, null, 2) + '\n';
for (const o of outs) fs.writeFileSync(path.join(o, 'manifest.json'), json);
console.log(`built ${ids.length} keychains -> ${outs.join(', ')}`);

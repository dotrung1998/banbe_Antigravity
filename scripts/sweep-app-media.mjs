#!/usr/bin/env node
// Browser-level proof that the running web app requests images from R2, not
// Supabase Storage. Start the app with R2 flags first, then:
//
//   APP_ORIGIN=http://127.0.0.1:5173 node scripts/sweep-app-media.mjs
//
// Read-only: it only navigates public routes and records image requests. A
// request to *.supabase.co/storage is a hard failure. External profile
// avatars (Unsplash seed data) and local static assets are listed separately.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';

const ORIGIN = (process.env.APP_ORIGIN || 'http://127.0.0.1:5173').replace(/\/+$/, '');
const ROUTES = [
  ['home', '/'],
  ['browse', '/browse'],
  ['search', '/search'],
  ['map', '/map'],
  ['event', '/event/dembass'],
  ['organizer', '/org/org_a96236c5'],
  ['user-profile-1', '/u/tdk404'],
  ['user-profile-2', '/u/banbetestadmin'],
  ['profile-guest', '/profile'],
];
const IMAGE_RE = /\.(jpe?g|png|webp|avif|gif)(\?|$)/i;

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
await context.addInitScript(() => {
  try {
    localStorage.setItem('banbe.preferences', JSON.stringify({ lang: 'vi', theme: 'light', located: false }));
    // Skip the post-welcome onboarding preview; the welcome CTA then opens Home as a guest.
    localStorage.setItem('banbe.guestOnboarding.v1', '1');
  } catch { /* ignore */ }
});
const page = await context.newPage();
let route = null;
const seen = new Map();

page.on('response', (res) => {
  if (!route) return;
  const req = res.request();
  const url = res.url();
  const type = req.resourceType();
  const isImage = type === 'image' || IMAGE_RE.test(url) || /\/storage\/v1\/object\//.test(url);
  if (!isImage || url.startsWith('data:') || url.startsWith('blob:')) return;
  const key = `${route}\t${url}`;
  if (!seen.has(key)) {
    seen.set(key, {
      route,
      url,
      status: res.status(),
      contentType: res.headers()['content-type'] || '',
      resourceType: type,
    });
  }
});
page.on('requestfailed', (req) => {
  if (!route) return;
  const url = req.url();
  if (!(req.resourceType() === 'image' || IMAGE_RE.test(url) || /\/storage\/v1\/object\//.test(url))) return;
  const key = `${route}\t${url}`;
  if (!seen.has(key)) seen.set(key, { route, url, status: 0, contentType: '', resourceType: req.resourceType(), failed: req.failure()?.errorText || 'request failed' });
});

const hostOf = (url) => { try { return new URL(url).hostname.toLowerCase(); } catch { return ''; } };
const kindOf = (url) => {
  const host = hostOf(url);
  if (host === 'media.banbe.app') return 'r2';
  if (host.endsWith('.supabase.co') && /\/storage\/v1\//.test(url)) return 'supabase';
  if (host === '127.0.0.1' || host === 'localhost') return 'local';
  return 'external';
};

const rows = [];
// The first visit lands on Welcome (the app's public entry), not Home. Click the
// guest CTA once so the actual home/feed screen is what the `/` sweep measures.
route = 'warmup';
try {
  await page.goto(ORIGIN + '/', { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await page.waitForTimeout(8000);
  const explore = page.getByTestId('welcome-explore');
  if (await explore.count()) { await explore.click(); await page.waitForTimeout(6000); }
} catch { /* the route sweep below still reports what loaded */ }

for (const [name, path] of ROUTES) {
  route = name;
  try {
    await page.goto(ORIGIN + path, { waitUntil: 'domcontentloaded', timeout: 30_000 });
    await page.waitForTimeout(8000);
    // A direct `/` load always starts at the public Welcome entry; click its
    // guest CTA so this row measures the real home/feed, not the welcome card.
    if (path === '/') {
      const explore = page.getByTestId('welcome-explore');
      if (await explore.count()) { await explore.click(); await page.waitForTimeout(6000); }
    }
    // Load lazy card/gallery images below the fold; the app scrolls its own viewport.
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => {
        const el = document.querySelector('[data-testid="app-scroll-viewport"]');
        if (el) el.scrollBy(0, 700); else window.scrollBy(0, 700);
      });
      await page.waitForTimeout(600);
    }
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.waitForTimeout(1500);
    const finalUrl = page.url();
    const title = await page.title().catch(() => '');
    rows.push({ name, path, finalUrl, title });
  } catch (e) {
    rows.push({ name, path, error: e.message });
  }
}
await browser.close();

const all = [...seen.values()];
mkdirSync('tmp', { recursive: true });
writeFileSync('tmp/app-media-sweep.json', JSON.stringify({ generatedAt: new Date().toISOString(), origin: ORIGIN, routes: rows, images: all }, null, 2));

console.log('APP ROUTES');
for (const r of rows) console.log(`  ${r.name.padEnd(18)} ${r.path.padEnd(28)} -> ${r.finalUrl || r.error}`);
console.log('\nIMAGE REQUESTS BY ROUTE');
console.log('route'.padEnd(18), 'images'.padStart(7), 'r2'.padStart(5), 'supabase'.padStart(9), 'local'.padStart(6), 'external'.padStart(8));
let supabase = 0;
for (const r of rows) {
  const list = all.filter((i) => i.route === r.name);
  const count = (k) => list.filter((i) => kindOf(i.url) === k).length;
  supabase += count('supabase');
  console.log(r.name.padEnd(18), String(list.length).padStart(7), String(count('r2')).padStart(5), String(count('supabase')).padStart(9), String(count('local')).padStart(6), String(count('external')).padStart(8));
}

const bad = all.filter((i) => kindOf(i.url) === 'supabase');
const badR2 = all.filter((i) => kindOf(i.url) === 'r2' && (i.status >= 400 || !i.status));
const r2 = [...new Set(all.filter((i) => kindOf(i.url) === 'r2').map((i) => i.url))];
const external = [...new Set(all.filter((i) => kindOf(i.url) === 'external').map((i) => i.url))];
const local = [...new Set(all.filter((i) => kindOf(i.url) === 'local').map((i) => i.url))];
console.log(`\nUnique R2 image URLs: ${r2.length}`);
console.log(`Unique local image URLs: ${local.length}`);
console.log(`Unique external (non-Supabase) image URLs: ${external.length}`);
for (const u of external.slice(0, 8)) console.log(`  external: ${u}`);
if (bad.length) {
  console.log(`\n✗ ${bad.length} image request(s) still hit Supabase Storage:`);
  for (const b of bad) console.log(`  ${b.route}: HTTP ${b.status} ${b.url}`);
  process.exitCode = 1;
} else {
  console.log('\n✓ 0 image requests to *.supabase.co/storage on all swept routes.');
}
if (badR2.length) {
  console.log(`\n✗ ${badR2.length} R2 image request(s) failed:`);
  for (const b of badR2) console.log(`  ${b.route}: HTTP ${b.status} ${b.url}`);
  process.exitCode = 1;
}
if (r2.length === 0) console.log('  (warning: no media.banbe.app image requests were observed)');

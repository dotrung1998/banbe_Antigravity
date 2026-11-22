#!/usr/bin/env node
/**
 * Golden screenshots for the agent-os vault.
 *
 * Three of the five screens cannot be reached by a cold URL: `/event/<key>/reserve`
 * needs a draft (routes.js falls back to the event), `/ticket` cold-loads Home
 * (`confirmed` has `parent: '/'` and `needs: () => false`), and `/profile` needs a
 * session. The script therefore drives the dev server's own state setter
 * (`window.__banbeDevSet`, `import.meta.env.DEV` only) with fixed fixtures, then
 * asserts the screen label before it writes anything. No login, no database writes.
 *
 *   npm run dev                                  # in another shell
 *   node scripts/golden-shots.mjs                # rewrite the committed golden set (intentional UI change only)
 *   node scripts/golden-shots.mjs --out docs/audits/2026-11-21/golden   # audit copy, golden untouched
 *   node scripts/golden-shots.mjs --only home    # one screen, all widths
 *
 * Requires `npx playwright install chromium` (and its system libraries; on a minimal
 * Linux `npx playwright install-deps chromium` needs root). If the browser cannot
 * start, the script exits non-zero with the underlying error — never a placeholder.
 */
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from '@playwright/test';

const BASE = process.env.GOLDEN_BASE_URL || 'http://127.0.0.1:5173';
const arg = (name) => (process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : null);
const OUT = path.resolve(arg('--out') || 'docs/agent-os/vault/golden/shots');
const ONLY = arg('--only');

// Fixed clock: the ticket strip says "N days to go", so a capture must not drift with the day.
const NOW = new Date('2026-11-21T12:00:00Z');
const START = '2026-11-26T12:00:00.000Z'; // Thu 26 Nov, 19:00 ICT

const USER = { id: '00000000-0000-4000-8000-0000000000a1', name: 'Trung', email: 't@example.com', handle: 'trungtest' };
const BASE_STATE = { lang: 'en', theme: 'light', accountType: 'participant', user: USER };

const SCREENS = [
  { key: 'home', label: 'Home', setup: null },
  {
    key: 'event', label: 'Event',
    state: { ...BASE_STATE, screen: 'event', eventKey: 'bepnho', liveEvent: { status: 'live', starts_at: START, tz: 'Asia/Ho_Chi_Minh' } },
  },
  {
    key: 'reserve', label: 'Reserve',
    state: {
      ...BASE_STATE, screen: 'reserve', eventKey: 'bepnho', qty: 1,
      liveEvent: { status: 'live', starts_at: START, tz: 'Asia/Ho_Chi_Minh' },
      attendeeDrafts: [{ name: 'Linh', dob: '1995-04-12', email: '', useProfileDob: false, profileDob: '' }],
    },
  },
  {
    key: 'ticket', label: 'Confirmed',
    state: {
      ...BASE_STATE, screen: 'confirmed', eventKey: 'bepnho', confirmedBack: 'home',
      liveEvent: { status: 'live', starts_at: START, tz: 'Asia/Ho_Chi_Minh' },
      booking: { id: 'b-golden', event_id: 'bepnho', status: 'confirmed', payment_state: 'confirmed', qty: 1, code: '1B159C', admission_token: 'tok-golden-admission' },
      bookingAttendees: [],
    },
  },
  { key: 'account', label: 'Account', state: { ...BASE_STATE, screen: 'profile' } },
];

const SIZES = [
  { name: '390', viewport: { width: 390, height: 844 } },
  { name: '1440', viewport: { width: 1440, height: 900 } },
];

async function reachHome(page) {
  await page.goto(BASE);
  for (let i = 0; i < 14; i++) {
    const labels = await page.locator('[data-screen-label]').evaluateAll((els) => els.map((e) => e.getAttribute('data-screen-label')));
    if (labels.includes('Home')) break;
    if (labels.includes('Splash')) await page.locator('[data-screen-label="Splash"]').click().catch(() => {});
    else if (labels.includes('Language')) await page.getByTestId('lang-en').click().catch(() => {});
    else if (labels.includes('Appearance')) {
      await page.getByTestId('theme-light').click().catch(() => {});
      await page.getByTestId('onboarding-continue').click().catch(() => {});
    } else if (labels.includes('Welcome')) await page.getByTestId('welcome-explore').click().catch(() => {});
    await page.waitForTimeout(900);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 10_000 });
}

// The brand face is a webfont with `font-display: swap`, so a screenshot taken too
// early silently records the fallback. Load every weight the app asks for, then fail
// loudly instead of committing a golden set in the wrong typeface.
async function waitForBrandFont(page) {
  const info = await page.evaluate(async () => {
    const family = 'Be Vietnam Pro';
    const weights = ['300', '400', '500', '600', '700', '800'];
    const specs = weights.map((w) => `${w} 16px "${family}"`).concat(`italic 400 16px "${family}"`);
    await Promise.all(specs.map((s) => document.fonts.load(s).catch(() => [])));
    await document.fonts.ready;
    const faces = [...document.fonts].filter((f) => f.family.replace(/["']/g, '') === family);
    const missing = weights.filter((w) => !faces.some((f) => f.status === 'loaded' && f.style === 'normal' && f.weight === w));
    if (!faces.some((f) => f.status === 'loaded' && f.style === 'italic')) missing.push('italic');
    return { faces: faces.length, loaded: faces.filter((f) => f.status === 'loaded').length, missing };
  });
  if (info.missing.length) {
    throw new Error(`Be Vietnam Pro is not fully loaded (faces=${info.faces}, loaded=${info.loaded}, missing=${info.missing.join(',')}) — check the Google Fonts request; refusing to write golden shots in a fallback font`);
  }
}

async function capture(page, screen, file) {
  if (screen.state) {
    const has = await page.evaluate(() => typeof window.__banbeDevSet === 'function');
    if (!has) throw new Error('window.__banbeDevSet is missing — this only runs against the dev server (npm run dev), not a production build');
    const apply = () => page.evaluate((patch) => window.__banbeDevSet(patch), screen.state);
    await apply();
    await page.waitForSelector(`[data-screen-label="${screen.label}"]`, { timeout: 10_000 });
    await page.waitForTimeout(900);
    await apply(); // a late fetch must not overwrite the fixture
    await page.waitForSelector(`[data-screen-label="${screen.label}"]`, { timeout: 5_000 });
  }
  await waitForBrandFont(page);
  await page.waitForTimeout(300);
  await page.screenshot({ path: file });
  const label = await page.locator(`[data-screen-label="${screen.label}"]`).getAttribute('data-screen-label');
  if (label !== screen.label) throw new Error(`${screen.key}: expected "${screen.label}", got "${label}"`);
}

fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch();
const written = [];
try {
  for (const size of SIZES) {
    const ctx = await browser.newContext({ viewport: size.viewport, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    await page.clock.setFixedTime(NOW);
    await page.addInitScript(() => { try { localStorage.setItem('banbe.guestOnboarding.v1', '1'); } catch { /* */ } });
    await reachHome(page);
    for (const screen of SCREENS) {
      if (ONLY && screen.key !== ONLY) continue;
      const file = path.join(OUT, `${screen.key}-${size.name}-light.png`);
      await capture(page, screen, file);
      written.push(path.relative(process.cwd(), file));
      console.log(`✓ ${screen.key} ${size.name}`);
      // Back to Home so each state patch starts from the same shell.
      await page.evaluate(() => window.__banbeDevSet({ screen: 'home', eventKey: null })).catch(() => {});
      await page.waitForTimeout(300);
    }
    await ctx.close();
  }
} finally {
  await browser.close();
}
console.log(`\n${written.length} golden shot(s) in ${path.relative(process.cwd(), OUT)}`);

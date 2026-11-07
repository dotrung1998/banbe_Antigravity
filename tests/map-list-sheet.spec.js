// @ts-check
// Map E+ (note 79, step 5): the list sheet. It slides up to just under the shared controls with no handle and no header of
// its own; a veil in its own colour covers the strip above it. Pulling the list down while it is scrolled to its top slides
// it away and fades the veil with the finger; a short pull springs back. Every gesture has a button (Map) and a key (Esc).
// Runs as a guest (read-only browsing), so the shared test account's date-of-birth gate can't block it.
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

/** Same as guestToHome but in Vietnamese (the long strings), for the narrow-screen test. */
async function guestToHomeVi(page, theme = 'theme-light') {
  await page.goto('/');
  for (let i = 0; i < 10; i++) {
    const sc = await page.locator('[data-screen-label]').evaluateAll(els => els.map(e => e.getAttribute('data-screen-label')));
    if (sc.includes('Home')) return;
    if (sc.includes('Splash')) await page.locator('[data-screen-label="Splash"]').click().catch(() => {});
    else if (sc.includes('Language')) await page.getByTestId('lang-vi').click().catch(() => {});
    else if (sc.includes('Appearance')) { await page.getByTestId(theme).click().catch(() => {}); await page.getByTestId('onboarding-continue').click().catch(() => {}); }
    else if (sc.includes('Welcome')) await page.getByTestId('welcome-explore').click().catch(() => {});
    await page.waitForTimeout(1200);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
}

async function openMap(page, { theme = 'theme-light', vi = false } = {}) {
  await (vi ? guestToHomeVi(page, theme) : guestToHome(page, theme));
  await page.click('[data-testid="home-layout-map"]');
  await page.waitForSelector('[data-screen-label="MapExplore"]');
  await expect(page.getByTestId('map-result-count')).toContainText(/\d+ (sự kiện|events?)/, { timeout: 15000 });
  await page.waitForFunction(() => !!window.__mapExploreMapForTests && (window.__mapExploreCommits || 0) >= 1);
  await page.waitForTimeout(600);
}
async function openList(page) {
  await page.click('[data-testid="map-list-button"]');
  await expect(page.getByTestId('map-list-sheet')).toBeVisible();
  await page.waitForTimeout(500); // the slide-up has finished
}

const sheetBox = (page) => page.getByTestId('map-list-sheet').boundingBox();
const shift = (page) => page.getByTestId('map-list-sheet').evaluate(e => new DOMMatrix(getComputedStyle(e).transform).m42);
const veilOpacity = (page) => page.getByTestId('map-list-veil').evaluate(e => Number(getComputedStyle(e).opacity));
const isOpen = (page) => page.getByTestId('map-list-sheet').evaluate(e => getComputedStyle(e).visibility === 'visible');
const pillOpacity = (page) => page.getByTestId('map-list-map-button').evaluate(e => Number(getComputedStyle(e).opacity));
const commits = (page) => page.evaluate(() => window.__mapExploreCommits || 0);

/** A mouse pull from inside the list: `dy` px down in `steps` moves `gap` ms apart. Returns a function to release. */
async function pull(page, dy, { steps = 10, gap = 30, fromY = 220 } = {}) {
  const b = await sheetBox(page);
  const x = b.x + b.width / 2, y0 = b.y + fromY;
  await page.mouse.move(x, y0);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) { await page.mouse.move(x, y0 + (dy * i) / steps); if (gap) await page.waitForTimeout(gap); }
  const release = async () => page.mouse.up();
  release.more = async (to, n = 8) => { for (let i = 1; i <= n; i++) { await page.mouse.move(x, y0 + dy + ((to - dy) * i) / n); await page.waitForTimeout(gap); } };
  return release;
}

for (const theme of ['theme-light', 'theme-dark']) {
  test.describe(`list sheet · ${theme}`, () => {
    test('flush under the controls, no handle, no header of its own; a veil in the list colour covers the strip above', async ({ page }) => {
      await openMap(page, { theme });
      await expect(page.getByTestId('map-list-veil')).toHaveCSS('opacity', '0'); // closed: no veil
      await openList(page);
      await expect(page.getByTestId('map-sheet-handle')).toHaveCount(0);
      await expect(page.locator('[data-testid="map-list-sheet"] [role="slider"], [data-testid="map-list-sheet"] [data-testid*="grab"]')).toHaveCount(0);
      const sheet = await sheetBox(page);
      const top = await page.getByTestId('map-top').boundingBox();
      expect(Math.abs(sheet.y - (top.y + top.height + 8))).toBeLessThan(3);
      // The veil reaches from the top of the screen to the list, in the list's own colour.
      const veil = await page.getByTestId('map-list-veil').boundingBox();
      expect(veil.y).toBeLessThanOrEqual(1);
      expect(Math.abs(veil.y + veil.height - sheet.y)).toBeLessThan(4);
      expect(await veilOpacity(page)).toBe(1);
      const same = await page.evaluate(() => getComputedStyle(document.querySelector('[data-testid="map-list-veil"]')).backgroundColor === getComputedStyle(document.querySelector('[data-testid="map-list-sheet"]')).backgroundColor);
      expect(same).toBe(true);
      // The shared controls stay above the veil and keep working.
      await expect(page.getByTestId('map-search-input')).toBeVisible();
      expect(await page.evaluate(() => { const r = document.querySelector('[data-testid="map-search-input"]').getBoundingClientRect(); const el = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2); return el?.getAttribute('data-testid'); })).toBe('map-search-input');
    });

    test('a long pull from the top closes it and the veil fades with the finger; no row opens behind the pull', async ({ page }) => {
      await openMap(page, { theme });
      await openList(page);
      const count0 = await page.getByTestId('map-result-count').textContent();
      const release = await pull(page, 65); // half way: the veil is about half gone
      const mid = await veilOpacity(page);
      expect(mid).toBeGreaterThan(0.3); expect(mid).toBeLessThan(0.75);
      expect(await shift(page)).toBeGreaterThan(40);
      expect(await pillOpacity(page)).toBeLessThan(0.8); // the Map button rides down with the sheet, so it fades with the veil
      await release.more(150); // on past the close distance
      expect(await veilOpacity(page)).toBe(0); // fully faded by the time the sheet is this far down
      await release();
      await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
      await expect.poll(() => veilOpacity(page), { timeout: 3000 }).toBe(0);
      await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toHaveCount(0); // the click after the pull was swallowed
      await expect(page.getByTestId('map-list-button')).toBeVisible();
      expect(await page.getByTestId('map-result-count').textContent()).toBe(count0);
    });
  });
}

test.describe('list sheet · pulling', () => {
  test('a short slow pull springs back: the list stays open and the veil returns', async ({ page }) => {
    await openMap(page);
    await openList(page);
    const before = await commits(page);
    const release = await pull(page, 50, { steps: 10, gap: 30 });
    expect(await shift(page)).toBeGreaterThan(20);
    expect(await veilOpacity(page)).toBeLessThan(0.8);
    await release();
    await page.waitForTimeout(700);
    expect(await isOpen(page)).toBe(true);
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    expect(await veilOpacity(page)).toBe(1);
    expect(await pillOpacity(page)).toBe(1);
    expect(await commits(page)).toBe(before); // the map never moved
  });

  test('a quick flick (short but fast) also closes it', async ({ page }) => {
    await openMap(page);
    await openList(page);
    // The whole gesture in one task (about 70 px in a few ms), so its speed does not depend on the test driver's latency.
    await page.evaluate(() => {
      const sheet = document.querySelector('[data-testid="map-list-sheet"]');
      const r = sheet.getBoundingClientRect();
      const x = r.x + r.width / 2, y = r.y + 220;
      const ev = (type, yy) => new PointerEvent(type, { pointerType: 'mouse', button: 0, buttons: 1, clientX: x, clientY: yy, bubbles: true, composed: true });
      sheet.dispatchEvent(ev('pointerdown', y));
      for (const d of [20, 45, 70]) window.dispatchEvent(ev('pointermove', y + d));
      window.dispatchEvent(ev('pointerup', y + 70));
    });
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
  });

  test('a pull only starts at the top: scrolled down, a downward drag scrolls the list back instead', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await page.getByTestId('map-list-scroll').evaluate(e => { e.scrollTop = 160; });
    await page.waitForTimeout(250);
    const y0 = await page.getByTestId('map-list-scroll').evaluate(e => e.scrollTop);
    expect(y0).toBeGreaterThan(80);
    const release = await pull(page, 120);
    expect(Math.abs(await shift(page))).toBeLessThan(1); // the sheet did not move
    await release();
    await page.waitForTimeout(400);
    expect(await isOpen(page)).toBe(true);
  });

  test('a sideways drag on the photos is not a pull', async ({ page }) => {
    await openMap(page);
    await openList(page);
    const b = await sheetBox(page);
    await page.mouse.move(b.x + b.width * 0.8, b.y + 150);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) await page.mouse.move(b.x + b.width * 0.8 - i * 20, b.y + 150 + i * 2);
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    await page.mouse.up();
    await page.waitForTimeout(300);
    expect(await isOpen(page)).toBe(true);
  });

  test('the wheel at the top pulls too: a long one closes it, a small one springs back', async ({ page }) => {
    await openMap(page);
    await openList(page);
    const b = await sheetBox(page);
    await page.mouse.move(b.x + b.width / 2, b.y + 200);
    await page.mouse.wheel(0, -60);
    await page.waitForTimeout(500);
    expect(await isOpen(page)).toBe(true);
    await expect.poll(async () => Math.abs(await shift(page)), { timeout: 2000 }).toBeLessThan(1);
    await expect.poll(() => veilOpacity(page), { timeout: 2000 }).toBe(1); // eased back, not stuck part way
    await page.mouse.wheel(0, -400);
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
  });

  test('a finger swipe (touch events) pulls it down: short springs back, long closes', async ({ page, browserName }) => {
    test.skip(browserName !== 'chromium', 'touch events are driven through the Chrome protocol');
    await openMap(page);
    await openList(page);
    const cdp = await page.context().newCDPSession(page);
    const b = await sheetBox(page);
    const x = b.x + b.width / 2, y = b.y + 220;
    const touch = (type, yy) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y: yy, id: 1 }] });
    // short, slow: springs back
    await touch('touchStart', y);
    for (let i = 1; i <= 8; i++) { await touch('touchMove', y + i * 6); await page.waitForTimeout(30); }
    expect(await shift(page)).toBeGreaterThan(15);
    await touch('touchEnd', 0);
    await page.waitForTimeout(700);
    expect(await isOpen(page)).toBe(true);
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    // long: closes
    await touch('touchStart', y);
    for (let i = 1; i <= 12; i++) { await touch('touchMove', y + i * 14); await page.waitForTimeout(25); }
    await touch('touchEnd', 0);
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
    await expect.poll(() => veilOpacity(page), { timeout: 3000 }).toBe(0);
  });

  test('without a gesture: the Map button, Esc and "List · N" again', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await page.click('[data-testid="map-list-map-button"]');
    await expect(page.getByTestId('map-list-sheet')).toBeHidden();
    await expect.poll(() => veilOpacity(page)).toBe(0);
    await openList(page);
    await page.keyboard.press('Escape');
    await expect(page.getByTestId('map-list-sheet')).toBeHidden();
    await openList(page); // and it opens cleanly again after a close
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    expect(await veilOpacity(page)).toBe(1);
  });

  test('after a pull-close the list opens again from "List · N" at rest', async ({ page }) => {
    await openMap(page);
    await openList(page);
    const release = await pull(page, 140);
    await release();
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
    await page.waitForTimeout(500);
    await openList(page);
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    expect(await veilOpacity(page)).toBe(1);
  });
});

test.describe('list sheet · small screens, long Vietnamese strings, reduced motion', () => {
  test.use({ viewport: { width: 320, height: 640 } });
  test.setTimeout(75000);

  test('320 px wide in Vietnamese: nothing overflows sideways; the controls, time bar, buttons and Map pill all fit', async ({ page }) => {
    await openMap(page, { vi: true });
    const overflow = () => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(await overflow()).toBeLessThanOrEqual(0);
    for (const id of ['map-back', 'map-search-box', 'map-chip-filters', 'map-time-bar', 'map-list-button', 'map-compass']) {
      const r = await page.getByTestId(id).boundingBox();
      expect(r, id).not.toBeNull();
      expect(r.x, id).toBeGreaterThanOrEqual(-1); expect(r.x + r.width, id).toBeLessThanOrEqual(321);
    }
    await expect(page.getByTestId('map-list-button')).toContainText('Danh sách'); // the Vietnamese label
    // The time bar: the day button and the range both fit, and the hour labels thin out instead of touching.
    const bar = await page.getByTestId('map-time-bar').boundingBox();
    const range = await page.getByTestId('map-time-range').boundingBox();
    expect(range.width).toBeGreaterThan(90);
    expect(range.x + range.width).toBeLessThanOrEqual(bar.x + bar.width);
    const tickBoxes = await page.getByTestId('map-time-range').locator(':scope > span[aria-hidden="true"]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return [r.left, r.right]; }));
    expect(tickBoxes.length).toBeGreaterThanOrEqual(3);
    for (let i = 1; i < tickBoxes.length; i++) expect(tickBoxes[i][0] - tickBoxes[i - 1][1]).toBeGreaterThanOrEqual(2); // the labels never touch
    // The list: heading cut with an ellipsis, never wrapped past the switch; the Map pill is on screen.
    await page.click('[data-testid="map-list-button"]');
    await page.waitForTimeout(600);
    const sheet = await sheetBox(page);
    expect(sheet.x).toBe(0);
    const pill = await page.getByTestId('map-list-map-button').boundingBox();
    expect(pill.y + pill.height).toBeLessThanOrEqual(641);
    expect(pill.x).toBeGreaterThanOrEqual(0); expect(pill.x + pill.width).toBeLessThanOrEqual(320);
    const head = await page.getByTestId('map-list-count').boundingBox();
    const sw = await page.getByTestId('map-layout-switch').boundingBox();
    expect(head.x + head.width).toBeLessThanOrEqual(sw.x + 1); // beside the switch, not under it
    expect(await overflow()).toBeLessThanOrEqual(0);
    // And the pull still works at this size.
    const release = await pull(page, 130);
    await release();
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
  });

  test('reduced motion: the sheet and veil switch state instantly (no slide, no fade), the pull still follows the finger', async ({ page }) => {
    await openMap(page);
    // Switched on once the Map is up (the guest onboarding before it behaves differently with motion reduced); the sheet
    // reads the setting every time it renders, and opening the list renders it.
    await page.emulateMedia({ reducedMotion: 'reduce' });
    const dur = (id) => page.getByTestId(id).evaluate(e => getComputedStyle(e).transitionDuration);
    await page.click('[data-testid="map-list-button"]');
    expect(await dur('map-list-sheet')).toMatch(/^0s(, 0s)*$/);
    expect(await dur('map-list-veil')).toMatch(/^0s(, 0s)*$/);
    await expect(page.getByTestId('map-list-sheet')).toBeVisible();
    expect(Math.abs(await shift(page))).toBeLessThan(1); // already at rest: it did not slide in
    expect(await veilOpacity(page)).toBe(1);
    const release = await pull(page, 60, { steps: 6, gap: 20 });
    expect(await shift(page)).toBeGreaterThan(30); // direct manipulation still follows the finger
    await release();
    await page.waitForTimeout(300);
    expect(await isOpen(page)).toBe(true); // 60 px slow: back to rest, instantly
    expect(Math.abs(await shift(page))).toBeLessThan(1);
    const r2 = await pull(page, 140);
    await r2();
    await expect(page.getByTestId('map-list-sheet')).toBeHidden({ timeout: 3000 });
    expect(await veilOpacity(page)).toBe(0);
  });
});

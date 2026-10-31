// @ts-check
// Map redesign phase 2: the map area being explored (not the viewer's distance) defines the results. Pins, list and
// count come from ONE committed area; it changes once after the camera settles from a pan/zoom, never because the
// sheet moved or a selection was revealed, and panning makes no network request (the whole public set is loaded).
// Runs as a guest (read-only browsing), so the shared test account's date-of-birth gate can't block it.
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

async function openMap(page) {
  await guestToHome(page);
  await page.click('[data-testid="home-layout-map"]');
  await page.waitForSelector('[data-screen-label="MapExplore"]');
  await expect(page.getByTestId('map-result-count')).toContainText(/\d+ (sự kiện|events?)/, { timeout: 15000 });
  await page.waitForFunction(() => !!window.__mapExploreMapForTests && (window.__mapExploreCommits || 0) >= 1);
  await page.waitForTimeout(600); // the canvas' own first settle
}

const commits = (page) => page.evaluate(() => window.__mapExploreCommits || 0);
const area = (page) => page.evaluate(() => window.__mapExploreArea);
const countText = (page) => page.getByTestId('map-result-count').textContent();

/** A real mouse drag on the map canvas (a user gesture). */
async function dragMap(page, dx, dy) {
  await page.mouse.move(195, 300);
  await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(195 + (dx * i) / 10, 300 + (dy * i) / 10);
  return async () => page.mouse.up();
}

test.describe('Map — viewport-driven discovery', () => {
  test('opens at mid with pins framed above the sheet and a settled count', async ({ page }) => {
    await openMap(page);
    const sheetTop = await page.getByTestId('map-sheet').evaluate(e => e.getBoundingClientRect().top);
    expect(sheetTop).toBeGreaterThan(844 * 0.5); // mid: more than half the screen is map
    const pinTops = await page.locator('[data-testid^="map-pin-"]').evaluateAll(els => els.map(e => e.getBoundingClientRect().top));
    expect(pinTops.length).toBeGreaterThan(0);
    // Every result pin of the first framing sits in the free area above the mid sheet.
    for (const t of pinTops) expect(t).toBeLessThan(sheetTop);
    // Pins and count are the same list.
    const n = Number((await countText(page)).match(/\d+/)[0]);
    expect(await page.locator('[data-testid^="map-pin-"]').count()).toBe(n);
  });

  test('a pan keeps the list still while dragging, then commits exactly once after it settles, with no fetch', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    let eventsRequests = 0;
    page.on('request', r => { if (/\/rest\/v1\/events\?/.test(r.url())) eventsRequests++; });
    const release = await dragMap(page, -160, 120);
    // Mid-gesture: nothing committed yet, list unchanged.
    expect(await commits(page)).toBe(before);
    expect(await countText(page)).toBe(textBefore);
    await release();
    await page.waitForTimeout(1200);
    expect(await commits(page)).toBe(before + 1);
    const areaAfter = await area(page);
    expect(areaAfter.west).not.toBeCloseTo(areaBefore.west, 6);
    expect(eventsRequests).toBe(0); // the complete set is local: panning never hits the network
  });

  test('moving the sheet never changes the area, the results or the count', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    await page.click('[data-testid="map-sheet-list-large"]');
    await page.waitForTimeout(800);
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before);
    expect(await area(page)).toEqual(areaBefore);
    expect(await countText(page)).toBe(textBefore);
  });

  test('selecting a result reveals it without a new search', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const textBefore = await countText(page);
    await page.locator('[data-testid^="map-list-item-"][role="button"]').first().click();
    await expect(page.getByTestId('map-selected-card')).toBeVisible();
    await page.waitForTimeout(1500);
    expect(await commits(page)).toBe(before);
    expect(await countText(page)).toBe(textBefore);
  });

  test('a filter keeps the area; an excluded selection is cleared, never moved to another event', async ({ page }) => {
    await openMap(page);
    const areaBefore = await area(page);
    await page.locator('[data-testid^="map-list-item-"][role="button"]').first().click();
    await expect(page.getByTestId('map-selected-card')).toBeVisible();
    // Search for something no event matches: the selection must go, the area must stay.
    await page.fill('[data-testid="map-search-input"]', 'zzzz-no-such-event');
    await expect(page.getByTestId('map-selected-card')).toHaveCount(0);
    await expect(page.getByTestId('map-search-no-results')).toBeVisible();
    await expect(page.getByTestId('map-clear-filters')).toBeVisible();
    expect(await area(page)).toEqual(areaBefore);
    await page.click('[data-testid="map-clear-filters"]');
    await expect(page.getByTestId('map-search-input')).toHaveValue('');
    expect(await area(page)).toEqual(areaBefore);
  });

  test('an empty part of the map says so and "Show nearest" commits one new area with results', async ({ page }) => {
    await openMap(page);
    // Programmatically fly far away as if the user had panned there (a gesture-less move counts as the user's).
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ center: [2.35, 48.85], zoom: 12 }));
    await expect(page.getByTestId('map-area-empty')).toBeVisible({ timeout: 5000 });
    const before = await commits(page);
    await page.click('[data-testid="map-show-nearest"]');
    await expect(page.locator('[data-testid^="map-list-item-"][role="button"]').first()).toBeVisible({ timeout: 8000 });
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before + 1);
  });

  test('back from Event Detail restores the area, the selection, the detent and the list without a loading frame', async ({ page }) => {
    await openMap(page);
    // A user pan first, so a restore that re-framed or re-committed would be visible.
    const release = await dragMap(page, -60, 40);
    await release();
    await page.waitForTimeout(1200);
    const row = page.locator('[data-testid^="map-list-item-"][role="button"]').first();
    await row.click();
    await expect(page.getByTestId('map-selected-card')).toBeVisible();
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.waitForTimeout(500);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    const title = await page.getByTestId('map-card-title').textContent();
    const commitsBefore = await commits(page);

    await page.getByTestId('map-card-cta').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.getByTestId('event-detail-back').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    // The first frame already has the list: never "Loading".
    await expect(page.getByTestId('map-loading')).toHaveCount(0);
    expect(await countText(page)).toBe(textBefore);
    await expect(page.getByTestId('map-card-title')).toHaveText(title);
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'true');
    await page.waitForTimeout(1500);
    // The saved area came back as-is: no re-framing, no new commit.
    expect(await commits(page)).toBe(commitsBefore);
    expect(await area(page)).toEqual(areaBefore);
  });

  // ---- phase 3: shared, contextual filters ----
  test('time chips filter in place: the area never moves and the chip survives a pan', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const n0 = Number((await countText(page)).match(/\d+/)[0]);
    await page.click('[data-testid="map-chip-weekend"]');
    await expect(page.getByTestId('map-chip-weekend')).toHaveAttribute('aria-pressed', 'true');
    const n1 = Number((await countText(page)).match(/\d+/)[0]);
    expect(n1).toBeLessThanOrEqual(n0);
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before); // a filter never moves the camera or commits an area
    expect(await area(page)).toEqual(areaBefore);
    const release = await dragMap(page, -40, 30);
    await release();
    await page.waitForTimeout(1200);
    await expect(page.getByTestId('map-chip-weekend')).toHaveAttribute('aria-pressed', 'true'); // never silently dropped
    // Pins still equal the count under the filter.
    const n2 = Number((await countText(page)).match(/\d+/)[0]);
    expect(await page.locator('[data-testid^="map-pin-"]').count()).toBe(n2);
  });

  test('filter sheet: Close discards the draft; Apply commits it and "Show N" is the resulting list', async ({ page }) => {
    await openMap(page);
    const text0 = await countText(page);
    await page.click('[data-testid="map-chip-filters"]');
    await expect(page.getByTestId('home-filter-sheet')).toBeVisible();
    await expect(page.getByTestId('home-filter-area')).toHaveCount(0); // the map is the location
    await expect(page.getByTestId('home-filter-date-tonight')).toBeVisible();
    await page.click('[data-testid="home-filter-date-week"]');
    await page.click('[data-testid="home-filter-close"]');
    expect(await countText(page)).toBe(text0);
    await expect(page.getByTestId('map-chip-filters')).not.toContainText('·');

    await page.click('[data-testid="map-chip-filters"]');
    await page.click('[data-testid="home-filter-date-week"]');
    const shown = Number(await page.getByTestId('home-filter-apply').getAttribute('data-count'));
    if (shown > 0) {
      await page.click('[data-testid="home-filter-apply"]');
      await expect(page.getByTestId('home-filter-sheet')).toHaveCount(0);
      expect(Number((await countText(page)).match(/\d+/)[0])).toBe(shown);
      await expect(page.getByTestId('map-chip-filters')).toContainText('· 1');
    }
  });

  test('Home hands its filters to the Map (Home "Next 7 days" arrives as an applied Map filter)', async ({ page }) => {
    await guestToHome(page);
    await page.click('[data-testid="home-filters-button"]');
    await page.click('[data-testid="home-filter-date-week"]');
    const homeCount = Number(await page.getByTestId('home-filter-apply').getAttribute('data-count'));
    test.skip(homeCount === 0, 'no live event in the next 7 days to hand over');
    await page.click('[data-testid="home-filter-apply"]');
    await page.click('[data-testid="home-layout-map"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-chip-filters')).toContainText('· 1');
    await page.click('[data-testid="map-chip-filters"]');
    await expect(page.getByTestId('home-filter-date-week')).toHaveAttribute('aria-pressed', 'true');
  });

  test('the area chip says "Map area" once the user pans', async ({ page }) => {
    await openMap(page);
    const release = await dragMap(page, -80, 40);
    await release();
    await page.waitForTimeout(1200);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Vùng bản đồ|Map area/);
  });

  test('rows show venue time and price per ticket, never a far-away distance', async ({ page }) => {
    await openMap(page);
    const when = await page.locator('[data-testid^="map-list-item-when-"]').first().textContent();
    expect(when).toMatch(/\d{2}\.\d{2} · \d{2}:\d{2}/);
    const price = await page.locator('[data-testid^="map-list-item-price-"]').first().textContent();
    expect(price).toMatch(/\/ vé|\/ ticket|Miễn phí|Free/);
    const rows = await page.locator('[data-testid^="map-list-item-area-"]').allTextContents();
    for (const r of rows) expect(r).not.toMatch(/\d{3,} ?km/);
  });
});

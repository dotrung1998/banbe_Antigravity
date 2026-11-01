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

/** Map v5: a user pan drops the sheet to peek; tapping the peek strip brings the list (and the chips) back at mid. */
async function backToMid(page) {
  if (await page.getByTestId('map-peek-summary').count()) await page.click('[data-testid="map-peek-summary"]');
  await expect(page.getByTestId('map-search-input')).toBeVisible();
}

const commits = (page) => page.evaluate(() => window.__mapExploreCommits || 0);
const area = (page) => page.evaluate(() => window.__mapExploreArea);
const countText = (page) => page.getByTestId('map-result-count').textContent();
/** Every result is in exactly one marker: pins count 1, clusters and stacks count their events. */
const markerTotal = (page) => page.evaluate(() => {
  const pins = document.querySelectorAll('[data-testid^="map-pin-"]').length;
  // Map v5: zoomed out, city bubbles (map-city-vn-… / map-city-us-…) count their events too.
  const groups = [...document.querySelectorAll('[data-testid^="map-cluster-"], [data-testid^="map-stack-"], [data-testid^="map-city-vn-"], [data-testid^="map-city-us-"]')]
    .reduce((n, el) => n + Number(el.getAttribute('data-count') || 0), 0);
  return pins + groups;
});

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
    const pinTops = await page.locator('[data-testid^="map-pin-"], [data-testid^="map-cluster-"], [data-testid^="map-stack-"]').evaluateAll(els => els.map(e => e.getBoundingClientRect().top));
    expect(pinTops.length).toBeGreaterThan(0);
    // Every result pin of the first framing sits in the free area above the mid sheet.
    for (const t of pinTops) expect(t).toBeLessThan(sheetTop);
    // Pins and count are the same list.
    const n = Number((await countText(page)).match(/\d+/)[0]);
    expect(await markerTotal(page)).toBe(n);
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
    // Inertia can carry the camera a little after release (WebKit especially): wait for the settle, then make sure
    // it was exactly ONE commit and stays one.
    await expect.poll(() => commits(page), { timeout: 5000 }).toBeGreaterThan(before);
    await page.waitForTimeout(1000);
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
    await expect(page.getByTestId('map-selected-row')).toBeVisible();
    await page.waitForTimeout(1500);
    expect(await commits(page)).toBe(before);
    expect(await countText(page)).toBe(textBefore);
  });

  test('a filter keeps the area; an excluded selection is cleared, never moved to another event', async ({ page }) => {
    await openMap(page);
    const areaBefore = await area(page);
    await page.locator('[data-testid^="map-list-item-"][role="button"]').first().click();
    await expect(page.getByTestId('map-selected-row')).toBeVisible();
    // Search for something no event matches: the selection must go, the area must stay. (Map v5: a selection folds
    // the search + chips into the summary line; tapping it opens them.)
    await page.click('[data-testid="map-filter-summary"]');
    await page.fill('[data-testid="map-search-input"]', 'zzzz-no-such-event');
    await expect(page.getByTestId('map-selected-row')).toHaveCount(0);
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
    await backToMid(page);
    const row = page.locator('[data-testid^="map-list-item-"][role="button"]').first();
    await row.click();
    await expect(page.getByTestId('map-selected-row')).toBeVisible();
    await page.click('[data-testid="map-sheet-list-large"]');
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
    await expect(page.getByTestId('map-sheet-list-large')).toHaveAttribute('aria-pressed', 'true');
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
    // At peek the strip names the filter; back at mid the chip is still on.
    await expect(page.getByTestId('map-peek-summary-text')).toContainText(/Cuối tuần|weekend/i);
    await backToMid(page);
    await expect(page.getByTestId('map-chip-weekend')).toHaveAttribute('aria-pressed', 'true'); // never silently dropped
    // Pins still equal the count under the filter.
    const n2 = Number((await countText(page)).match(/\d+/)[0]);
    expect(await markerTotal(page)).toBe(n2);
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
    await backToMid(page);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Vùng bản đồ|Map area/);
  });

  // ---- phase 4: price pins, clusters, stacks, bounded mode ----
  test('price pins show the price per ticket of their event, with its category icon', async ({ page }) => {
    await openMap(page);
    const pin = page.locator('[data-testid^="map-pin-"]').first();
    // Map v5: the category's line icon sits before the price, and the screen reader hears the category too.
    await expect(pin.locator('svg')).toHaveCount(1);
    expect(await pin.getAttribute('data-cat')).toBeTruthy();
    const id = (await pin.getAttribute('data-testid')).replace('map-pin-', '');
    const pinText = (await pin.textContent()).trim();
    const rowPrice = await page.getByTestId(`map-list-item-price-${id}`).textContent();
    expect(pinText).toMatch(/\d|Miễn phí|Free/);
    if (/Miễn phí|Free/.test(rowPrice)) expect(pinText).toMatch(/Miễn phí|Free/);
    else expect(rowPrice.replace(/[^\d]/g, '').startsWith(pinText.replace(/[^\d]/g, ''))).toBe(true);
  });

  test('zoomed out, events cluster; markers still add up to the count; a cluster tap zooms in and commits once', async ({ page }) => {
    await openMap(page);
    // Zoom 9 = the closest city-scale zoom: below it markers become city bubbles (Map v5), at it grid clusters.
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ zoom: 9 }));
    const cluster = page.locator('[data-testid^="map-cluster-"]').first();
    await expect(cluster).toBeVisible({ timeout: 5000 });
    await page.waitForTimeout(800);
    const n = Number((await countText(page)).match(/\d+/)[0]);
    expect(await markerTotal(page)).toBe(n);
    const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
    const before = await commits(page);
    await cluster.click();
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThan(z0);
    expect(await commits(page)).toBe(before + 1);
    expect(await markerTotal(page)).toBe(Number((await countText(page)).match(/\d+/)[0]));
  });

  test('events at the same place stack; the card steps through them', async ({ page }) => {
    // Move the second event onto the first one's place (mocked response; production has no shared venue yet).
    let spot = null;
    await page.route(/\/rest\/v1\/events\?/, async (route) => {
      const res = await route.fetch();
      const rows = await res.json();
      if (Array.isArray(rows) && rows.length > 1 && rows[0].lat != null) {
        rows[1].lat = rows[0].lat; rows[1].lng = rows[0].lng;
        spot = [rows[0].lng, rows[0].lat];
      }
      await route.fulfill({ response: res, json: rows });
    });
    await openMap(page);
    expect(spot).not.toBeNull();
    await page.evaluate((c) => window.__mapExploreMapForTests.jumpTo({ center: c, zoom: 17 }), spot);
    const stack = page.locator('[data-testid^="map-stack-"]').first();
    await expect(stack).toBeVisible({ timeout: 5000 });
    expect(await stack.getAttribute('data-count')).toBe('2');
    await stack.click();
    await expect(page.getByTestId('map-card-stack')).toContainText('1/2');
    const first = await page.getByTestId('map-card-title').textContent();
    await page.click('[data-testid="map-card-stack-next"]');
    await expect(page.getByTestId('map-card-stack')).toContainText('2/2');
    await expect(page.getByTestId('map-card-title')).not.toHaveText(first);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('bounded mode only when the set is larger than the cap: honest notice + an area request', async ({ page }) => {
    let boundedRequests = 0;
    await page.route(/\/rest\/v1\/events\?/, async (route) => {
      if (/lat=gte\./.test(route.request().url())) boundedRequests++;
      const res = await route.fetch();
      const headers = { ...res.headers(), 'content-range': '0-4/900' };
      await route.fulfill({ response: res, headers });
    });
    await openMap(page);
    await expect(page.getByTestId('map-incomplete')).toBeVisible();
    await expect.poll(() => boundedRequests, { timeout: 5000 }).toBeGreaterThan(0);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
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

  // ---- Map v5 (note 73): dock on demand, selection in the sheet, sticky filters, pan → peek, cities ----
  test('the dock is hidden at mid and peek, shown at tall, and back when the Map closes', async ({ page }) => {
    await openMap(page);
    await expect(page.getByTestId('dock-row')).toHaveAttribute('data-hidden', 'true');
    await page.click('[data-testid="map-sheet-list-small"]');
    await expect(page.getByTestId('dock-row')).toHaveAttribute('data-hidden', 'true');
    await page.click('[data-testid="map-sheet-list-large"]');
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
    await page.click('[data-testid="map-sheet-list-small"]');
    await expect(page.getByTestId('dock-row')).toHaveAttribute('data-hidden', 'true');
    await page.click('[data-testid="map-back"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]', { state: 'detached' });
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
  });

  test('a user pan drops the sheet to peek with the count and the filters; the strip brings it back', async ({ page }) => {
    await openMap(page);
    const release = await dragMap(page, -80, 50);
    await release();
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByTestId('map-peek-summary')).toBeVisible();
    await expect(page.getByTestId('map-result-count')).toBeVisible();
    await expect(page.getByTestId('map-peek-summary-text')).toContainText(/Chưa lọc|No filters/);
    await page.click('[data-testid="map-peek-summary"]');
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'false');
    // A programmatic move (selection reveal, restore, destination) never drops the sheet.
    await page.locator('[data-testid^="map-list-item-"][role="button"]').first().click();
    await page.waitForTimeout(1200);
    await expect(page.getByTestId('map-peek-summary')).toHaveCount(0);
  });

  test('selecting puts the event at the top of the list, once, with its actions; nothing floats over the map', async ({ page }) => {
    await openMap(page);
    const row = page.locator('[data-testid^="map-list-item-"][role="button"]').first();
    const id = (await row.getAttribute('data-testid')).replace('map-list-item-', '');
    await row.click();
    const selected = page.getByTestId('map-sheet').getByTestId('map-selected-row');
    await expect(selected).toBeVisible();
    await expect(page.getByTestId(`map-list-item-${id}`)).toHaveCount(0); // not listed twice
    await expect(selected.getByTestId('map-card-cta')).toBeVisible();
    await expect(selected.getByTestId('map-card-share')).toBeVisible();
    // The row sits inside the sheet, below its top edge: the map above stays clear.
    const sheetTop = await page.getByTestId('map-sheet').evaluate(e => e.getBoundingClientRect().top);
    const rowTop = await selected.evaluate(e => e.getBoundingClientRect().top);
    expect(rowTop).toBeGreaterThan(sheetTop);
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'false'); // mid
    await selected.getByTestId('map-card-close').click();
    await expect(page.getByTestId('map-selected-row')).toHaveCount(0);
    await expect(page.getByTestId(`map-list-item-${id}`)).toBeVisible();
  });

  test('filters stay visible: the header folds into one summary line that names them, and opens again', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-chip-weekend"]');
    const row = page.locator('[data-testid^="map-list-item-"][role="button"]').first();
    test.skip(await row.count() === 0, 'no event this weekend in the framed area');
    await row.click();
    const line = page.getByTestId('map-filter-summary');
    await expect(line).toBeVisible();
    await expect(page.getByTestId('map-filter-summary-text')).toContainText(/Cuối tuần|weekend/i);
    await expect(page.getByTestId('map-filter-summary-count')).toHaveText('1');
    await line.click();
    await expect(page.getByTestId('map-search-input')).toBeVisible();
    await expect(page.getByTestId('map-chip-weekend')).toHaveAttribute('aria-pressed', 'true');
    // Clear from the folded line resets everything.
    await page.locator('[data-testid^="map-list-item-"][role="button"]').first().click();
    await page.click('[data-testid="map-filter-summary-clear"]');
    await expect(page.getByTestId('map-filter-summary-text')).toContainText(/Tìm|Search/);
  });

  test('searching a city lists it first; Go flies there and commits that area once', async ({ page }) => {
    await openMap(page);
    await page.fill('[data-testid="map-search-input"]', 'da lat');
    const go = page.getByTestId('map-city-row-vn-dalat');
    await expect(go).toBeVisible();
    await expect(page.getByTestId('map-search-no-results')).toHaveCount(0);
    const before = await commits(page);
    await go.click();
    await expect(page.getByTestId('map-search-input')).toHaveValue('');
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 1);
    const a = await area(page);
    // The committed area is around Da Lat (11.94 N, 108.46 E), even with no events there.
    expect(a.south).toBeLessThan(11.95); expect(a.north).toBeGreaterThan(11.93);
    expect(a.west).toBeLessThan(108.46); expect(a.east).toBeGreaterThan(108.45);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Đà Lạt|Da Lat/);
    // Accent-free alias back to Saigon.
    await page.fill('[data-testid="map-search-input"]', 'sai gon');
    await page.click('[data-testid="map-city-row-vn-hcm"]');
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 2);
    await expect(page.locator('[data-testid^="map-list-item-"][role="button"]').first()).toBeVisible();
  });

  test('zoomed out, one bubble per city adds up to the count; a tap flies to that city', async ({ page }) => {
    await openMap(page);
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ center: [106.7, 10.78], zoom: 6 }));
    const hcm = page.getByTestId('map-city-vn-hcm');
    await expect(hcm).toBeVisible({ timeout: 5000 });
    await page.waitForTimeout(800);
    const n = Number((await countText(page)).match(/\d+/)[0]);
    expect(await markerTotal(page)).toBe(n);
    await expect(page.locator('[data-testid^="map-cluster-"]')).toHaveCount(0);
    const before = await commits(page);
    await hcm.click();
    await page.waitForTimeout(1500);
    // Past city zoom: the bubble gives way to the city's own pins/clusters (never the same bubble again).
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThan(9);
    await expect(page.getByTestId('map-city-vn-hcm')).toHaveCount(0);
    expect(await commits(page)).toBe(before + 1);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Hồ Chí Minh|Ho Chi Minh/);
  });

  test('the area picker lists cities first; picking one flies the map there', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-chip-area"]');
    const row = page.getByTestId('area-city:vn-hanoi');
    await expect(row).toBeVisible();
    const before = await commits(page);
    await row.click();
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 1);
    const a = await area(page);
    expect(a.south).toBeLessThan(21.03); expect(a.north).toBeGreaterThan(21.02);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Hà Nội|Hanoi/);
  });

  // ---- Map v6 (note 74): city in the area tree + one tap, full height with photo cards, peek → full, peek strip ----
  test('the area tree has the city level; one tap on a name picks it, closes the sheet and flies there once', async ({ page }) => {
    await openMap(page);
    // Pan away first, so the pick is a real move (and lands at peek → back to mid for the area chip).
    const release = await dragMap(page, -160, 80);
    await release();
    await page.waitForTimeout(1200);
    await backToMid(page);
    await page.click('[data-testid="map-chip-area"]');
    const city = 'loc:VN|c:TP. Hồ Chí Minh';
    await expect(page.getByTestId(`area-node:${city}`)).toBeVisible();
    await expect(page.getByTestId(`area-chevron:${city}`)).toBeVisible();
    await expect(page.locator('[data-testid^="area-node-all-in"]')).toHaveCount(0); // no "All in X" rows any more
    await expect(page.getByTestId('area-node-all')).toBeVisible(); // "All locations" stays
    // The chevron only browses: the sheet stays open.
    await page.click(`[data-testid="area-chevron:${city}"]`);
    await expect(page.getByTestId('area-sheet-tree')).toBeVisible();
    const before = await commits(page);
    await page.click(`[data-testid="area-node:${city}"]`);
    await expect(page.getByTestId('area-sheet-tree')).toHaveCount(0);
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 1);
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before + 1);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Hồ Chí Minh|Ho Chi Minh/);
  });

  test('the peek strip has search, quick chips and All filters; a chip filters and opens the list to mid', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-sheet-list-small"]');
    await expect(page.getByTestId('map-peek-search')).toBeVisible();
    await expect(page.getByTestId('map-peek-chip-tonight')).toBeVisible();
    await expect(page.getByTestId('map-peek-all-filters')).toBeAttached();
    await page.click('[data-testid="map-peek-chip-weekend"]');
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'false'); // mid
    await expect(page.getByTestId('map-sheet-list-large')).toHaveAttribute('aria-pressed', 'false');
    await expect(page.getByTestId('map-chip-weekend')).toHaveAttribute('aria-pressed', 'true');
  });

  test('a pull up from peek goes straight to full height with Large photo cards; Compact shows rows', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.waitForTimeout(500);
    const h = await page.getByTestId('map-sheet-handle').boundingBox();
    const x = h.x + h.width / 2, y = h.y + h.height / 2;
    await page.mouse.move(x, y);
    await page.mouse.down();
    for (let i = 1; i <= 8; i++) await page.mouse.move(x, y - i * 10);
    await page.waitForTimeout(200); // a slow pull, not a flick: the distance alone decides
    await page.mouse.up();
    await expect(page.getByTestId('map-sheet-list-large')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByTestId('map-layout-large')).toHaveAttribute('aria-checked', 'true');
    // Full height: the sheet's top sits just under the Close / compass row.
    await page.waitForTimeout(500);
    const sheetTop = await page.getByTestId('map-sheet').evaluate(e => e.getBoundingClientRect().top);
    const backBottom = await page.getByTestId('map-back').evaluate(e => e.getBoundingClientRect().bottom);
    expect(sheetTop).toBeGreaterThan(backBottom - 1);
    expect(sheetTop).toBeLessThan(backBottom + 24);
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
    const card = page.locator('[data-testid^="map-list-item-"][role="button"]').first();
    await expect(card.locator('[data-testid^="photo-pager-"]').first()).toBeVisible();
    await page.click('[data-testid="map-layout-compact"]');
    await expect(page.getByTestId('map-layout-compact')).toHaveAttribute('aria-checked', 'true');
    await expect(page.locator('[data-testid^="map-list-item-when-"]').first()).toBeVisible();
    await expect(page.getByTestId('map-sheet').locator('[data-testid^="photo-pager-"]')).toHaveCount(0);
    // Remembered for the session: down and up again keeps Compact.
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.click('[data-testid="map-sheet-list-large"]');
    await expect(page.getByTestId('map-layout-compact')).toHaveAttribute('aria-checked', 'true');
  });

  test('the peek search button opens full height with the input focused, recents and cities; Cancel goes back', async ({ page }) => {
    await page.addInitScript(() => { try { localStorage.setItem('banbe_map_recent_searches_v1', JSON.stringify(['supper club'])); } catch { /* ignore */ } });
    await openMap(page);
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.click('[data-testid="map-peek-search"]');
    await expect(page.getByTestId('map-sheet-list-large')).toHaveAttribute('aria-pressed', 'true');
    // Focused in the same tap (iOS Safari only raises the keyboard for a focus inside the gesture).
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).toBe('map-search-input');
    await expect(page.getByTestId('map-search-recent')).toBeVisible();
    await expect(page.getByTestId('map-search-recent')).toContainText('supper club');
    await expect(page.getByTestId('map-search-cities')).toBeVisible();
    await expect(page.getByTestId('map-search-city-vn-hcm')).toBeVisible();
    await expect(page.getByTestId('map-search-quick')).toBeVisible();
    await page.click('[data-testid="map-search-cancel"]');
    await expect(page.getByTestId('map-sheet-list-small')).toHaveAttribute('aria-pressed', 'true'); // back to peek
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).not.toBe('map-search-input');
    // Typing behaves as before (v5): a recent tap fills the search and the results come back.
    await page.click('[data-testid="map-peek-search"]');
    await page.click('[data-testid="map-search-recent-0"]');
    await expect(page.getByTestId('map-search-input')).toHaveValue('supper club');
    await expect(page.getByTestId('map-search-suggest')).toHaveCount(0);
  });

  test('Large card photos page sideways; a drag or a wheel on the photos never leaves the Map', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-sheet-list-large"]');
    const counter = page.getByTestId('map-sheet').locator('[data-testid^="photo-pager-counter-"]').first();
    test.skip(await counter.count() === 0, 'no event with more than one photo in this map area');
    const id = (await counter.getAttribute('data-testid')).replace('photo-pager-counter-', '');
    const pager = page.getByTestId(`photo-pager-${id}`);
    await expect(counter).toHaveText(/^1\/\d+$/);
    await pager.hover(); // the arrows show on hover / focus (desktop)
    await page.click(`[data-testid="photo-pager-next-${id}"]`);
    await expect(counter).toHaveText(/^2\/\d+$/);
    await expect(pager).toHaveAttribute('data-index', '1');
    // A horizontal mouse drag and a sideways wheel move the photos, never the screen or the selection.
    const b = await pager.boundingBox();
    await page.mouse.move(b.x + b.width * 0.8, b.y + b.height / 2);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) await page.mouse.move(b.x + b.width * 0.8 - i * 20, b.y + b.height / 2);
    await page.mouse.up();
    await expect(counter).toHaveText(/^3\/\d+$/);
    await page.mouse.wheel(300, 0);
    await page.waitForTimeout(600);
    await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible();
    await expect(page.getByTestId('map-selected-row')).toHaveCount(0);
  });
});

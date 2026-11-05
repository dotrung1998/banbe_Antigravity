// @ts-check
// Map E+ (note 79, step 2): the map is full screen. The map area being explored (not the viewer's distance) defines the
// results. Pins, list and count come from ONE committed area; it changes once after the camera settles from a pan/zoom,
// never because the list or a panel opened, and panning makes no network request (the whole public set is loaded).
// The list is a layer opened from "List · N"; a pin opens Event Detail. Runs as a guest (read-only browsing), so the
// shared test account's date-of-birth gate can't block it.
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

/** The list is a layer: open it from "List · N", close it with its Map button. */
async function openList(page) {
  await page.click('[data-testid="map-list-button"]');
  await expect(page.getByTestId('map-list-sheet')).toBeVisible();
  await page.waitForTimeout(500); // the slide-up (0.38 s) has finished: positions below are the resting ones
}
async function closeList(page) {
  await page.click('[data-testid="map-list-map-button"]');
  await expect(page.getByTestId('map-list-sheet')).toBeHidden();
}

const commits = (page) => page.evaluate(() => window.__mapExploreCommits || 0);
const area = (page) => page.evaluate(() => window.__mapExploreArea);
const countText = (page) => page.getByTestId('map-result-count').textContent();
const countNum = async (page) => Number((await countText(page)).match(/\d+/)[0]);
const listRows = (page) => page.locator('[data-testid^="map-list-item-"][role="button"]');
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
  await page.mouse.move(195, 400);
  await page.mouse.down();
  for (let i = 1; i <= 10; i++) await page.mouse.move(195 + (dx * i) / 10, 400 + (dy * i) / 10);
  return async () => page.mouse.up();
}

test.describe('Map — full-screen viewport discovery', () => {
  test('opens full screen with pins framed between the controls and the buttons and a settled count', async ({ page }) => {
    await openMap(page);
    await expect(page.getByTestId('map-list-sheet')).toBeHidden(); // a fresh open is the map itself
    const topBottom = await page.getByTestId('map-top').evaluate(e => e.getBoundingClientRect().bottom);
    const stackTop = await page.getByTestId('map-list-button').evaluate(e => e.getBoundingClientRect().top);
    const pins = await page.locator('[data-testid^="map-pin-"], [data-testid^="map-cluster-"], [data-testid^="map-stack-"]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return [r.top, r.bottom]; }));
    expect(pins.length).toBeGreaterThan(0);
    // Every pin of the first framing sits in the free area: under the shared controls, above the buttons.
    for (const [t, b] of pins) { expect(t).toBeGreaterThan(topBottom - 4); expect(b).toBeLessThan(stackTop + 4); }
    // Pins and count are the same list; "List · N" says the same N.
    const n = await countNum(page);
    expect(await markerTotal(page)).toBe(n);
    await expect(page.getByTestId('map-list-button')).toContainText(String(n));
  });

  test('a pan keeps the count still while dragging, then commits exactly once after it settles, with no fetch', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    let eventsRequests = 0;
    page.on('request', r => { if (/\/rest\/v1\/events\?/.test(r.url())) eventsRequests++; });
    const release = await dragMap(page, -160, 120);
    // Mid-gesture: nothing committed yet, count unchanged.
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

  test('opening and closing the list never changes the area, the results or the count', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    await openList(page);
    await page.waitForTimeout(600);
    await closeList(page);
    await page.waitForTimeout(600);
    expect(await commits(page)).toBe(before);
    expect(await area(page)).toEqual(areaBefore);
    expect(await countText(page)).toBe(textBefore);
  });

  test('the list opens from "List · N", shows the same count, and closes with the Map button and with Esc', async ({ page }) => {
    await openMap(page);
    const n = await countNum(page);
    await expect(page.getByTestId('map-list-sheet')).toHaveAttribute('aria-hidden', 'true'); // hidden from screen readers while closed
    await openList(page);
    await expect(page.getByTestId('map-list-count')).toContainText(String(n));
    expect(await listRows(page).count()).toBe(n);
    // Focus moves to the heading when it opens.
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).toBe('map-list-count');
    // The list sits flush under the shared controls.
    const sheetTop = await page.getByTestId('map-list-sheet').evaluate(e => e.getBoundingClientRect().top);
    const topBottom = await page.getByTestId('map-top').evaluate(e => e.getBoundingClientRect().bottom);
    expect(Math.abs(sheetTop - (topBottom + 8))).toBeLessThan(3);
    await closeList(page);
    // Focus returns to the button that opened it.
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).toBe('map-list-button');
    await openList(page);
    await page.keyboard.press('Escape');
    await expect(page.getByTestId('map-list-sheet')).toBeHidden();
  });

  test('a pin opens Event Detail; Back restores the area, the count and the pan', async ({ page }) => {
    await openMap(page);
    // A user pan first, so a restore that re-framed or re-committed would be visible.
    const release = await dragMap(page, -60, 40);
    await release();
    await page.waitForTimeout(1200);
    const areaBefore = await area(page);
    const textBefore = await countText(page);
    const commitsBefore = await commits(page);
    const centerBefore = await page.evaluate(() => { const c = window.__mapExploreMapForTests.getCenter(); return [c.lng, c.lat]; });
    const pin = page.locator('[data-testid^="map-pin-"]').first();
    test.skip(await pin.count() === 0, 'no single pin in the panned area');
    await pin.click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.getByTestId('event-detail-back').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    // The first frame already has the results: never "Loading".
    await expect(page.getByTestId('map-loading')).toHaveCount(0);
    expect(await countText(page)).toBe(textBefore);
    await page.waitForTimeout(1500);
    // The saved area came back as-is: no re-framing, no new commit.
    expect(await commits(page)).toBe(commitsBefore);
    expect(await area(page)).toEqual(areaBefore);
    const centerAfter = await page.evaluate(() => { const c = window.__mapExploreMapForTests.getCenter(); return [c.lng, c.lat]; });
    expect(centerAfter[0]).toBeCloseTo(centerBefore[0], 4);
    expect(centerAfter[1]).toBeCloseTo(centerBefore[1], 4);
  });

  test('a list row opens Event Detail; Back brings the list back open in its layout', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await page.click('[data-testid="map-layout-compact"]');
    const textBefore = await countText(page);
    await listRows(page).first().click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.getByTestId('event-detail-back').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-list-sheet')).toBeVisible();
    await expect(page.getByTestId('map-layout-compact')).toHaveAttribute('aria-checked', 'true');
    expect(await countText(page)).toBe(textBefore);
  });

  test('a filter keeps the area; nothing found says so with a way back, never moves the map', async ({ page }) => {
    await openMap(page);
    const areaBefore = await area(page);
    await page.fill('[data-testid="map-search-input"]', 'zzzz-no-such-event');
    await page.getByTestId('map-search-input').blur();
    await expect(page.getByTestId('map-search-no-results')).toBeVisible(); // floats over the map, no list needed
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
    await expect.poll(() => countNum(page), { timeout: 8000 }).toBeGreaterThan(0);
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before + 1);
    await expect(page.getByTestId('map-area-empty')).toHaveCount(0);
  });

  // ---- shared, contextual filters ----
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
    await expect(page.getByTestId('map-chip-filters')).not.toContainText(/\d/); // no badge

    await page.click('[data-testid="map-chip-filters"]');
    await page.click('[data-testid="home-filter-date-week"]');
    const shown = Number(await page.getByTestId('home-filter-apply').getAttribute('data-count'));
    if (shown > 0) {
      await page.click('[data-testid="home-filter-apply"]');
      await expect(page.getByTestId('home-filter-sheet')).toHaveCount(0);
      expect(await countNum(page)).toBe(shown);
      await expect(page.getByTestId('map-chip-filters')).toContainText('1'); // the badge
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
    await expect(page.getByTestId('map-chip-filters')).toContainText('1');
    await page.click('[data-testid="map-chip-filters"]');
    await expect(page.getByTestId('home-filter-date-week')).toHaveAttribute('aria-pressed', 'true');
  });

  test('the category chips count what tapping them would show; a pick filters in place and survives a pan', async ({ page }) => {
    await openMap(page);
    const before = await commits(page);
    const areaBefore = await area(page);
    const chip = page.locator('[data-testid^="map-cat-"][role="tab"]:not([data-testid="map-cat-all"])').first();
    const key = (await chip.getAttribute('data-testid')).replace('map-cat-', '');
    const n = Number(await page.getByTestId(`map-cat-count-${key}`).textContent());
    test.skip(n === 0, 'first category has no event in the framed area');
    await chip.click();
    await expect(chip).toHaveAttribute('aria-selected', 'true');
    expect(await countNum(page)).toBe(n);
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before); // a filter never moves the camera or commits an area
    expect(await area(page)).toEqual(areaBefore);
    const release = await dragMap(page, -40, 30);
    await release();
    await page.waitForTimeout(1200);
    await expect(chip).toHaveAttribute('aria-selected', 'true'); // never silently dropped
    expect(await markerTotal(page)).toBe(await countNum(page));
  });

  test('the area chip says "Map area" once the user pans', async ({ page }) => {
    await openMap(page);
    const release = await dragMap(page, -80, 40);
    await release();
    await page.waitForTimeout(1200);
    await expect(page.getByTestId('map-chip-area')).toContainText(/Vùng bản đồ|Map area/);
  });

  // ---- price pins, clusters, stacks, bounded mode ----
  test('price pins show the price per ticket of their event, with its category icon', async ({ page }) => {
    await openMap(page);
    const pin = page.locator('[data-testid^="map-pin-"]').first();
    // Map v5: the category's line icon sits before the price, and the screen reader hears the category too.
    await expect(pin.locator('svg')).toHaveCount(1);
    expect(await pin.getAttribute('data-cat')).toBeTruthy();
    const id = (await pin.getAttribute('data-testid')).replace('map-pin-', '');
    const pinText = (await pin.textContent()).trim();
    await openList(page);
    await page.click('[data-testid="map-layout-compact"]'); // the price test ids live on the compact rows
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
    expect(await markerTotal(page)).toBe(await countNum(page));
    const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
    const before = await commits(page);
    await cluster.click();
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThan(z0);
    expect(await commits(page)).toBe(before + 1);
    expect(await markerTotal(page)).toBe(await countNum(page));
  });

  test('events at the same place stack; tapping the stack opens the list (the area panel takes over in step 3)', async ({ page }) => {
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
    await expect(page.getByTestId('map-list-sheet')).toBeVisible();
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
    await openList(page); // the notice lives in the list's header
    await expect(page.getByTestId('map-incomplete')).toBeVisible();
    await expect.poll(() => boundedRequests, { timeout: 5000 }).toBeGreaterThan(0);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('rows show venue time and price per ticket, never a far-away distance', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await page.click('[data-testid="map-layout-compact"]');
    const when = await page.locator('[data-testid^="map-list-item-when-"]').first().textContent();
    expect(when).toMatch(/\d{2}\.\d{2} · \d{2}:\d{2}/);
    // The amount sits beside a ticket icon; "/ ticket" is the row's accessible label.
    const priceEl = page.locator('[data-testid^="map-list-item-price-"]').first();
    expect(`${await priceEl.textContent()} ${await priceEl.getAttribute('aria-label')}`).toMatch(/\/ vé|\/ ticket|Miễn phí|Free/);
    const rows = await page.locator('[data-testid^="map-list-item-area-"]').allTextContents();
    for (const r of rows) expect(r).not.toMatch(/\d{3,} ?km/);
  });

  // ---- the dock stays; cities; search ----
  test('the dock stays visible on the map and under the open list, and is still there when the Map closes', async ({ page }) => {
    await openMap(page);
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
    await openList(page);
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
    // The last row clears the dock and the Map button.
    await page.getByTestId('map-list-scroll').evaluate(e => { e.scrollTop = e.scrollHeight; });
    await page.waitForTimeout(200);
    const lastBottom = await listRows(page).last().evaluate(e => e.getBoundingClientRect().bottom);
    const dockTop = await page.getByTestId('dock-row').evaluate(e => e.getBoundingClientRect().top);
    expect(lastBottom).toBeLessThan(dockTop + 2);
    await closeList(page);
    await page.click('[data-testid="map-back"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]', { state: 'detached' });
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
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
    await openList(page);
    await expect(listRows(page).first()).toBeVisible();
  });

  test('zoomed out, one bubble per city adds up to the count; a tap flies to that city', async ({ page }) => {
    await openMap(page);
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ center: [106.7, 10.78], zoom: 6 }));
    const hcm = page.getByTestId('map-city-vn-hcm');
    await expect(hcm).toBeVisible({ timeout: 5000 });
    await page.waitForTimeout(800);
    expect(await markerTotal(page)).toBe(await countNum(page));
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

  test('the area tree has the city level; one tap on a name picks it, closes the sheet and flies there once', async ({ page }) => {
    await openMap(page);
    // Pan away first, so the pick is a real move.
    const release = await dragMap(page, -160, 80);
    await release();
    await page.waitForTimeout(1200);
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

  test('focusing the search shows recents, cities and quick filters; Cancel puts the keyboard away; a recent fills the search', async ({ page }) => {
    await page.addInitScript(() => { try { localStorage.setItem('banbe_map_recent_searches_v1', JSON.stringify(['supper club'])); } catch { /* ignore */ } });
    await openMap(page);
    await page.click('[data-testid="map-search-input"]');
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).toBe('map-search-input');
    await expect(page.getByTestId('map-search-recent')).toBeVisible();
    await expect(page.getByTestId('map-search-recent')).toContainText('supper club');
    await expect(page.getByTestId('map-search-cities')).toBeVisible();
    await expect(page.getByTestId('map-search-city-vn-hcm')).toBeVisible();
    await expect(page.getByTestId('map-search-quick')).toBeVisible();
    await page.click('[data-testid="map-search-cancel"]');
    await expect(page.getByTestId('map-search-panel')).toHaveCount(0);
    expect(await page.evaluate(() => document.activeElement?.getAttribute('data-testid'))).not.toBe('map-search-input');
    // A recent tap fills the search; the panel then offers the results.
    await page.click('[data-testid="map-search-input"]');
    await page.click('[data-testid="map-search-recent-0"]');
    await expect(page.getByTestId('map-search-input')).toHaveValue('supper club');
    await expect(page.getByTestId('map-search-suggest')).toHaveCount(0);
    await page.click('[data-testid="map-search-show-list"]');
    await expect(page.getByTestId('map-list-sheet')).toBeVisible();
  });

  test('the list shows Large photo cards by default; Compact shows rows and is remembered for the session', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await expect(page.getByTestId('map-layout-large')).toHaveAttribute('aria-checked', 'true');
    await expect(listRows(page).first().locator('[data-testid^="photo-pager-"]').first()).toBeVisible();
    await page.click('[data-testid="map-layout-compact"]');
    await expect(page.getByTestId('map-layout-compact')).toHaveAttribute('aria-checked', 'true');
    await expect(page.locator('[data-testid^="map-list-item-when-"]').first()).toBeVisible();
    await expect(page.getByTestId('map-list-sheet').locator('[data-testid^="photo-pager-"]')).toHaveCount(0);
    await closeList(page);
    await openList(page);
    await expect(page.getByTestId('map-layout-compact')).toHaveAttribute('aria-checked', 'true');
  });

  test('Large card photos page sideways; a drag or a wheel on the photos never leaves the Map', async ({ page }) => {
    await openMap(page);
    await openList(page);
    const counter = page.getByTestId('map-list-sheet').locator('[data-testid^="photo-pager-counter-"]').first();
    test.skip(await counter.count() === 0, 'no event with more than one photo in this map area');
    const id = (await counter.getAttribute('data-testid')).replace('photo-pager-counter-', '');
    const pager = page.getByTestId(`photo-pager-${id}`);
    await expect(counter).toHaveText(/^1\/\d+$/);
    await pager.hover(); // the arrows show on hover / focus (desktop)
    await page.click(`[data-testid="photo-pager-next-${id}"]`);
    await expect(counter).toHaveText(/^2\/\d+$/);
    await expect(pager).toHaveAttribute('data-index', '1');
    // A horizontal mouse drag and a sideways wheel move the photos, never the screen.
    const b = await pager.boundingBox();
    await page.mouse.move(b.x + b.width * 0.8, b.y + b.height / 2);
    await page.mouse.down();
    for (let i = 1; i <= 10; i++) await page.mouse.move(b.x + b.width * 0.8 - i * 20, b.y + b.height / 2);
    await page.mouse.up();
    await expect(counter).toHaveText(/^3\/\d+$/);
    await page.mouse.wheel(300, 0);
    await page.waitForTimeout(600);
    await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible();
    await expect(page.getByTestId('map-list-sheet')).toBeVisible();
  });
});

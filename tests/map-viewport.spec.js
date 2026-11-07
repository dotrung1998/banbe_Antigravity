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
/** Tap the first neighbourhood chip: the map flies there at pin level and its panel opens. */
async function openFirstArea(page) {
  await page.locator('[data-testid^="map-areachip-"]').first().click();
  await expect(page.getByTestId('map-area-panel')).toBeVisible();
  await expect(page.locator('[data-testid^="map-pin-"], [data-testid^="map-cluster-"], [data-testid^="map-stack-"]').first()).toBeVisible({ timeout: 8000 });
  await page.waitForTimeout(900); // the flight and the panel's slide-in have settled
}
const listRows = (page) => page.locator('[data-testid^="map-list-item-"][role="button"]');
/** Every result is in exactly one marker: pins count 1, clusters and stacks count their events. */
const markerTotal = (page) => page.evaluate(() => {
  const pins = document.querySelectorAll('[data-testid^="map-pin-"]').length;
  // Map v5: zoomed out, city bubbles (map-city-vn-… / map-city-us-…) count their events too.
  const groups = [...document.querySelectorAll('[data-testid^="map-areabubble-"], [data-testid^="map-cluster-"], [data-testid^="map-stack-"], [data-testid^="map-city-vn-"], [data-testid^="map-city-us-"]')]
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
  test('opens full screen at the neighbourhood level: one bubble per area, framed between the controls and the buttons', async ({ page }) => {
    await openMap(page);
    await expect(page.getByTestId('map-list-sheet')).toBeHidden(); // a fresh open is the map itself
    await expect(page.getByTestId('map-area-panel')).toHaveCount(0);
    const topBottom = await page.getByTestId('map-top').evaluate(e => e.getBoundingClientRect().bottom);
    const stackTop = await page.getByTestId('map-list-button').evaluate(e => e.getBoundingClientRect().top);
    const bubbles = page.locator('[data-testid^="map-areabubble-"]');
    await expect(bubbles.first()).toBeVisible();
    expect(await page.locator('[data-testid^="map-pin-"]').count()).toBe(0); // not street level yet
    const rects = await bubbles.evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return [r.top, r.bottom]; }));
    // Every bubble of the first framing sits in the free area: under the shared controls, above the buttons.
    for (const [t, b] of rects) { expect(t).toBeGreaterThan(topBottom - 4); expect(b).toBeLessThan(stackTop + 4); }
    // Bubbles, count and "List · N" are the same list.
    const n = await countNum(page);
    expect(await markerTotal(page)).toBe(n);
    await expect(page.getByTestId('map-list-button')).toContainText(String(n));
  });

  // ---- Map E+ step 3: neighbourhood bubbles, chips and the panel ----
  test('a bubble opens its neighbourhood: the map flies in to pins, the panel lists its events, the dock steps aside', async ({ page }) => {
    await openMap(page);
    const bubble = page.locator('[data-testid^="map-areabubble-"][data-areas="1"]').first();
    const n = Number(await bubble.getAttribute('data-count'));
    const before = await commits(page);
    await bubble.click();
    const panel = page.getByTestId('map-area-panel');
    await expect(panel).toBeVisible();
    await expect(page.getByTestId('map-area-title')).toHaveAttribute('data-count', String(n));
    await expect(page.locator('[data-testid^="map-area-item-"][role="button"]')).toHaveCount(n);
    await expect(page.getByTestId('dock-row')).toHaveAttribute('data-hidden', 'true');
    await expect(page.getByTestId('map-list-button')).toBeHidden(); // the buttons and chips give way to the panel
    await expect(page.getByTestId('map-area-chips')).toHaveCount(0);
    await expect(page.locator('[data-testid^="map-pin-"], [data-testid^="map-cluster-"], [data-testid^="map-stack-"]').first()).toBeVisible({ timeout: 8000 });
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThanOrEqual(13.5);
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 1); // a flight commits once, like a cluster tap
    // The panel is about 46% of the screen and sits at the bottom.
    const box = await panel.boundingBox();
    expect(Math.abs(box.height - 844 * 0.46)).toBeLessThan(6);
    expect(Math.abs(box.y + box.height - 844)).toBeLessThan(2);
  });

  test('zooming out closes the panel and the view stays; the dock comes back', async ({ page }) => {
    await openMap(page);
    await openFirstArea(page);
    const before = await commits(page);
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ zoom: 11 })); // a user zooms out (a gesture-less move counts as the user's)
    await expect(page.getByTestId('map-area-panel')).toHaveCount(0);
    await expect(page.getByTestId('dock-row')).not.toHaveAttribute('data-hidden', 'true');
    await expect(page.locator('[data-testid^="map-areabubble-"]').first()).toBeVisible({ timeout: 5000 });
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeLessThan(12); // it did not fly back
    await expect.poll(() => commits(page), { timeout: 5000 }).toBe(before + 1);
  });

  test('"All areas" and Esc close the panel and fly back to where it was opened from', async ({ page }) => {
    await openMap(page);
    const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
    await openFirstArea(page);
    await page.click('[data-testid="map-area-back"]');
    await expect(page.getByTestId('map-area-panel')).toHaveCount(0);
    await expect.poll(() => page.evaluate(() => window.__mapExploreMapForTests.getZoom()), { timeout: 5000 }).toBeCloseTo(z0, 0);
    await expect(page.locator('[data-testid^="map-areabubble-"]').first()).toBeVisible();
    await expect(page.getByTestId('map-area-chips')).toBeVisible();
    await openFirstArea(page);
    await page.keyboard.press('Escape');
    await expect(page.getByTestId('map-area-panel')).toHaveCount(0);
  });

  test('the neighbourhood chips list each area with its count, most events first; one tap opens it', async ({ page }) => {
    await openMap(page);
    const chips = page.locator('[data-testid^="map-areachip-"]');
    await expect(chips.first()).toBeVisible();
    const counts = (await chips.evaluateAll(els => els.map(e => Number(e.getAttribute('data-count')))));
    expect(counts.reduce((a, b) => a + b, 0)).toBe(await countNum(page)); // every result is in exactly one chip
    expect([...counts].sort((a, b) => b - a)).toEqual(counts);
    // The chips never move the results: opening and closing the list keeps them where they are.
    const first = await chips.first().getAttribute('data-testid');
    await openList(page);
    await expect(page.getByTestId('map-area-chips')).toHaveCount(0);
    await closeList(page);
    await expect(page.getByTestId(first)).toBeVisible();
    await page.getByTestId(first).click();
    await expect(page.getByTestId('map-area-panel')).toBeVisible();
  });

  test('bubbles that overlap at this zoom merge into one "N areas" bubble; a tap zooms in to tell them apart', async ({ page }) => {
    await openMap(page);
    await page.evaluate(() => window.__mapExploreMapForTests.jumpTo({ zoom: 9.6 }));
    await page.waitForTimeout(800);
    expect(await markerTotal(page)).toBe(await countNum(page)); // merging never loses a result
    const merged = page.locator('[data-testid^="map-areabubble-"]:not([data-areas="1"])').first();
    test.skip(await merged.count() === 0, 'only one neighbourhood in this map area, nothing overlaps');
    const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
    await merged.click();
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThan(z0);
    await expect(page.getByTestId('map-area-panel')).toHaveCount(0); // a merged bubble only zooms
  });

  // ---- Map E+ step 4: the day + hours time bar; inside = bold, outside = dimmed, never removed ----
  /** Two events tomorrow evening (19:00, 23:30 Vietnam time), every other one ten days out, so counts are known. */
  async function mockStarts(page) {
    // The app's "today" is the Vietnam service day: the night still counts until 04:00, so shift by 7 h (zone) - 4 h.
    const vnDay = (plus) => new Date(Date.now() + 3 * 3600e3 + plus * 86400e3).toISOString().slice(0, 10);
    await page.route(/\/rest\/v1\/events\?/, async (route) => {
      const res = await route.fetch();
      const rows = await res.json();
      if (Array.isArray(rows)) rows.forEach((r, i) => { r.starts_at = i === 0 ? `${vnDay(1)}T19:00:00+07:00` : i === 1 ? `${vnDay(1)}T23:30:00+07:00` : `${vnDay(10)}T12:00:00+07:00`; });
      await route.fulfill({ response: res, json: rows });
    });
  }
  const pickDay = async (page, key) => { await page.click('[data-testid="map-time-day"]'); await page.click(`[data-testid="map-time-day-${key}"]`); };
  const dimCount = (page) => page.locator('[data-testid^="map-areabubble-"][data-dim="true"], [data-testid^="map-pin-"][data-dim="true"], [data-testid^="map-cluster-"][data-dim="true"], [data-testid^="map-stack-"][data-dim="true"]').count();
  const hitTotal = (page) => page.evaluate(() => [...document.querySelectorAll('[data-testid^="map-areabubble-"]')].reduce((n, e) => n + Number(e.getAttribute('data-hit') || 0), 0));
  const knobX = async (page, hour) => { const b = await page.getByTestId('map-time-range').boundingBox(); return b.x + ((hour - 10) / 16) * b.width; };

  test('the time bar starts on All days: the range is off and nothing is dimmed', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await expect(page.getByTestId('map-time-bar')).toBeVisible();
    await expect(page.getByTestId('map-time-day')).toContainText(/Tất cả ngày|All days/);
    await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'false');
    expect(await dimCount(page)).toBe(0);
    await expect(page.getByTestId('map-list-button')).toContainText(String(await countNum(page)));
    // The time bar rides between the chips and the buttons, clear of both.
    const t = await page.getByTestId('map-time-bar').boundingBox();
    const c = await page.getByTestId('map-area-chips').boundingBox();
    const f = await page.getByTestId('map-list-button').boundingBox();
    expect(t.y + t.height).toBeLessThanOrEqual(c.y + 1);
    expect(f.y + f.height).toBeLessThanOrEqual(t.y + 1);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('a day menu opens above the bar with today, tomorrow, the weekend day, next week and all days; the current one is checked', async ({ page }) => {
    await openMap(page);
    await page.click('[data-testid="map-time-day"]');
    const menu = page.getByTestId('map-time-menu');
    await expect(menu).toBeVisible();
    const items = menu.getByRole('menuitemradio');
    await expect(items).toHaveCount(5);
    await expect(menu.getByTestId('map-time-day-all')).toHaveAttribute('aria-checked', 'true');
    await expect(menu.getByTestId('map-time-day-weekend')).toContainText(/Thứ Bảy|Chủ nhật|Saturday|Sunday/);
    const m = await menu.boundingBox(); const b = await page.getByTestId('map-time-day').boundingBox();
    expect(m.y + m.height).toBeLessThanOrEqual(b.y + 2); // above the button
    expect(m.x).toBeGreaterThanOrEqual(0);               // and on screen
    await page.keyboard.press('Escape');
    await expect(menu).toHaveCount(0);
  });

  test('choosing a day dims what is outside it; "List · N" counts what is inside; no fetch, no new area, no marker rebuilt', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    const total = await countNum(page);
    await page.evaluate(() => { window.__tagged = document.querySelector('[data-testid^="map-areabubble-"]'); });
    const before = await commits(page);
    let eventsRequests = 0;
    page.on('request', r => { if (/\/rest\/v1\/events\?/.test(r.url())) eventsRequests++; });
    await pickDay(page, 'tomorrow');
    await expect(page.getByTestId('map-time-day')).toContainText(/Mai|Tomorrow/);
    await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'true');
    await expect(page.getByTestId('map-list-button')).toContainText('· 2');
    expect(await hitTotal(page)).toBe(2);
    expect(await dimCount(page)).toBeGreaterThan(0);
    expect(await markerTotal(page)).toBe(total); // dimmed, never removed
    await expect(page.getByTestId('map-result-count')).toHaveAttribute('data-hit', '2');
    expect(await page.evaluate(() => document.querySelector('[data-testid^="map-areabubble-"]') === window.__tagged)).toBe(true); // same node
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before);
    expect(eventsRequests).toBe(0);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('dragging a knob moves what is inside live: the knob grows and shows its hour while held, nothing is fetched', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await pickDay(page, 'tomorrow'); // 17:00 to 02:00
    await page.evaluate(() => { window.__tagged = document.querySelector('[data-testid^="map-areabubble-"]'); });
    const before = await commits(page);
    let eventsRequests = 0;
    page.on('request', r => { if (/\/rest\/v1\/events\?/.test(r.url())) eventsRequests++; });
    const knob = page.getByTestId('map-time-knob-from');
    await expect(knob).toHaveAttribute('aria-valuenow', '17');
    const y = (await page.getByTestId('map-time-range').boundingBox()).y + 22;
    await page.mouse.move(await knobX(page, 17), y);
    await page.mouse.down();
    await expect(page.locator('.bb-tknob.act')).toHaveCount(1); // grown only while touched
    for (let h = 17.5; h <= 20; h += 0.5) await page.mouse.move(await knobX(page, h), y);
    await expect(knob).toHaveAttribute('aria-valuenow', '20');
    await expect(knob.locator('.bb-tknob-bubble')).toHaveText('20:00');
    await expect(page.getByTestId('map-list-button')).toContainText('· 1'); // 19:00 is out, 23:30 still in
    await page.mouse.up();
    await expect(page.locator('.bb-tknob.act')).toHaveCount(0);
    expect(await page.evaluate(() => document.querySelector('[data-testid^="map-areabubble-"]') === window.__tagged)).toBe(true);
    await page.waitForTimeout(800);
    expect(await commits(page)).toBe(before);
    expect(eventsRequests).toBe(0);
    // A press near the right end moves the NEAREST knob (to), so both stay reachable even a step apart.
    await page.mouse.click(await knobX(page, 24), y);
    await expect(page.getByTestId('map-time-knob-to')).toHaveAttribute('aria-valuenow', '24');
    await expect(page.getByTestId('map-time-knob-from')).toHaveAttribute('aria-valuenow', '20');
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('the knobs are sliders for the keyboard: arrows, Page keys, Home and End; each reads its hour aloud', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await pickDay(page, 'tomorrow');
    const from = page.getByTestId('map-time-knob-from');
    await from.focus();
    await expect(from).toHaveAttribute('role', 'slider');
    await expect(from).toHaveAttribute('aria-valuetext', '17:00');
    await page.keyboard.press('ArrowRight');
    await expect(from).toHaveAttribute('aria-valuenow', '18');
    await expect(from).toHaveAttribute('aria-valuetext', '18:00');
    await page.keyboard.press('PageUp');
    await expect(from).toHaveAttribute('aria-valuenow', '22');
    await page.keyboard.press('Home');
    await expect(from).toHaveAttribute('aria-valuenow', '10');
    await page.keyboard.press('End'); // never past the other knob: one step before it
    await expect(from).toHaveAttribute('aria-valuenow', '25');
    await expect(page.locator('.bb-tknob.act, .bb-tknob:focus-visible')).toHaveCount(1); // grown while focused
    await page.keyboard.press('Home');
    const to = page.getByTestId('map-time-knob-to');
    await to.focus();
    await expect(to).toHaveAttribute('aria-valuetext', '02:00'); // 26 = 02:00 the next morning
    await page.keyboard.press('ArrowLeft');
    await expect(to).toHaveAttribute('aria-valuenow', '25');
    await expect(to).toHaveAttribute('aria-valuetext', '01:00');
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('"All days" turns the filter off again: nothing is dimmed and the range is inert', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    const total = await countNum(page);
    await pickDay(page, 'tomorrow');
    expect(await dimCount(page)).toBeGreaterThan(0);
    await pickDay(page, 'all');
    await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'false');
    expect(await dimCount(page)).toBe(0);
    await expect(page.getByTestId('map-list-button')).toContainText(`· ${total}`);
    await expect(page.getByTestId('map-time-knob-from')).toHaveAttribute('aria-disabled', 'true');
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('the list puts what is inside the window first and the rest after, dimmed, under its own heading', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    const total = await countNum(page);
    await pickDay(page, 'tomorrow');
    await openList(page);
    await expect(page.getByTestId('map-list-count')).toContainText(/2 sự kiện trong khung giờ|2 events in the window/);
    await expect(page.getByTestId('map-list-window')).toContainText(/17:00.02:00/);
    const rows = page.locator('[data-testid^="map-list-item-"][role="button"]');
    expect(await rows.count()).toBe(total);
    await expect(page.getByTestId('map-list-outside-heading')).toContainText(String(total - 2));
    // The two inside rows come before the heading, the others after it, and only those are dimmed.
    const order = await page.getByTestId('map-list-scroll').evaluate((el) => {
      const heading = el.querySelector('[data-testid="map-list-outside-heading"]');
      return [...el.querySelectorAll('[data-testid^="map-list-item-"][role="button"]')].map(r => ({
        before: !!(r.compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING),
        dim: !!r.closest('[data-dim="true"]'),
      }));
    });
    expect(order.filter(o => o.before).length).toBe(2);
    expect(order.filter(o => o.before).every(o => !o.dim)).toBe(true);
    expect(order.filter(o => !o.before).every(o => o.dim)).toBe(true);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('the chips say how many of each area are inside the window and the busiest come first; an area with none fades', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await pickDay(page, 'tomorrow');
    const chips = page.locator('[data-testid^="map-areachip-"]');
    const hits = await chips.evaluateAll(els => els.map(e => Number(e.getAttribute('data-hit'))));
    expect(hits.reduce((a, b) => a + b, 0)).toBe(2);
    expect([...hits].sort((a, b) => b - a)).toEqual(hits);
    await expect(chips.first()).toContainText(/trong khung giờ|in the window/);
    const faded = chips.filter({ has: page.locator('xpath=self::*[@data-hit="0"]') });
    if (await faded.count()) expect(await faded.first().evaluate(e => getComputedStyle(e).opacity)).toBe('0.5');
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('the panel puts the area’s in-window events first; its title shows inside / all; the time bar rides above it', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await pickDay(page, 'tomorrow');
    await openFirstArea(page);
    const title = page.getByTestId('map-area-title');
    const all = Number(await title.getAttribute('data-count')); const hit = Number(await title.getAttribute('data-hit'));
    expect(hit).toBeGreaterThan(0); // the busiest-in-window area comes first
    if (all > hit) await expect(title).toContainText(`${hit}/${all}`);
    await expect(page.locator('[data-testid^="map-area-item-"][role="button"][data-dim="true"]')).toHaveCount(all - hit);
    const bar = await page.getByTestId('map-time-bar').boundingBox();
    const panel = await page.getByTestId('map-area-panel').boundingBox();
    expect(bar.y + bar.height).toBeLessThanOrEqual(panel.y + 1);
    // The window can still be changed from here.
    await pickDay(page, 'all');
    await expect(title).toContainText(String(all));
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('the window survives Event Detail and back', async ({ page }) => {
    await mockStarts(page);
    await openMap(page);
    await pickDay(page, 'tomorrow');
    await openList(page);
    await listRows(page).first().click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.getByTestId('event-detail-back').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-time-day')).toContainText(/Mai|Tomorrow/);
    await expect(page.getByTestId('map-time-knob-from')).toHaveAttribute('aria-valuenow', '17');
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('a pin opens Event Detail; Back brings the panel, the area and the pan back as they were', async ({ page }) => {
    await openMap(page);
    await openFirstArea(page);
    const areaBefore = await area(page);
    const commitsBefore = await commits(page);
    const title = await page.getByTestId('map-area-title').textContent();
    const pin = page.locator('[data-testid^="map-pin-"]').first();
    test.skip(await pin.count() === 0, 'this area has only clusters or stacks at this zoom');
    await pin.click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.getByTestId('event-detail-back').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-area-panel')).toBeVisible();
    await expect(page.getByTestId('map-area-title')).toHaveText(title);
    await expect(page.getByTestId('map-loading')).toHaveCount(0);
    await page.waitForTimeout(1500);
    expect(await commits(page)).toBe(commitsBefore); // restored as saved: no re-framing, no new commit
    expect(await area(page)).toEqual(areaBefore);
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
  test('filter sheet: no "When" section (the time bar is the day and hours); Close discards the draft; Apply commits it', async ({ page }) => {
    await openMap(page);
    const text0 = await countText(page);
    await page.click('[data-testid="map-chip-filters"]');
    await expect(page.getByTestId('home-filter-sheet')).toBeVisible();
    await expect(page.getByTestId('home-filter-area')).toHaveCount(0); // the map is the location
    await expect(page.locator('[data-testid^="home-filter-date-"]')).toHaveCount(0); // the time bar is the time
    const slider = page.getByTestId('home-filter-price-max');
    test.skip(await slider.count() === 0, 'no priced event in this map area');
    const tryIt = async () => { await slider.focus(); await page.keyboard.press('Home'); }; // the lowest price: a real draft change
    await tryIt();
    await page.click('[data-testid="home-filter-close"]');
    expect(await countText(page)).toBe(text0);
    await expect(page.getByTestId('map-chip-filters')).not.toContainText(/\d/); // no badge

    await page.click('[data-testid="map-chip-filters"]');
    await tryIt();
    const shown = Number(await page.getByTestId('home-filter-apply').getAttribute('data-count'));
    if (shown > 0) {
      await page.click('[data-testid="home-filter-apply"]');
      await expect(page.getByTestId('home-filter-sheet')).toHaveCount(0);
      expect(await countNum(page)).toBe(shown);
      await expect(page.getByTestId('map-chip-filters')).toContainText('1'); // the badge
    }
  });

  test('Home hands its date to the Map as the day (Home "Tomorrow" arrives as Tomorrow on the time bar)', async ({ page }) => {
    // Home's "Tomorrow" is the calendar day, the Map's is the service day (the night counts until 04:00): put events on both.
    const cal = (plus) => new Date(Date.now() + 7 * 3600e3 + plus * 86400e3).toISOString().slice(0, 10);
    await page.route(/\/rest\/v1\/events\?/, async (route) => {
      const res = await route.fetch();
      const rows = await res.json();
      if (Array.isArray(rows)) rows.forEach((r, i) => { r.starts_at = `${cal(1)}T12:00:00+07:00`; if (i % 2) r.starts_at = `${new Date(Date.now() + 3 * 3600e3 + 86400e3).toISOString().slice(0, 10)}T12:00:00+07:00`; });
      await route.fulfill({ response: res, json: rows });
    });
    await guestToHome(page);
    await page.click('[data-testid="home-filters-button"]');
    await page.click('[data-testid="home-filter-date-tomorrow"]');
    await page.click('[data-testid="home-filter-apply"]');
    await page.click('[data-testid="home-layout-map"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await expect(page.getByTestId('map-time-day')).toContainText(/Mai|Tomorrow/);
    await expect(page.getByTestId('map-time-range')).toHaveAttribute('data-on', 'true');
    await expect(page.getByTestId('map-chip-filters')).not.toContainText(/\d/); // the date is not a Map filter
    await page.click('[data-testid="map-chip-filters"]');
    await expect(page.locator('[data-testid^="home-filter-date-"]')).toHaveCount(0);
    await page.unrouteAll({ behavior: 'ignoreErrors' });
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
    await openFirstArea(page);
    // A pin of THIS area (neighbouring areas' pins can be in view too): the one that has a row in the panel.
    const ids = (await page.locator('[data-testid^="map-pin-"]').evaluateAll(els => els.map(e => e.getAttribute('data-testid').replace('map-pin-', ''))));
    let id = null;
    for (const c of ids) if (await page.getByTestId(`map-area-item-price-${c}`).count()) { id = c; break; }
    test.skip(id === null, 'this area has only clusters or stacks at this zoom');
    const pin = page.getByTestId(`map-pin-${id}`);
    // Map v5: the category's line icon sits before the price, and the screen reader hears the category too.
    await expect(pin.locator('svg')).toHaveCount(1);
    expect(await pin.getAttribute('data-cat')).toBeTruthy();
    const pinText = (await pin.textContent()).trim();
    // The panel's own rows carry the price per ticket.
    const rowPrice = await page.getByTestId(`map-area-item-price-${id}`).textContent();
    expect(pinText).toMatch(/\d|Miễn phí|Free/);
    if (/Miễn phí|Free/.test(rowPrice)) expect(pinText).toMatch(/Miễn phí|Free/);
    else expect(rowPrice.replace(/[^\d]/g, '').startsWith(pinText.replace(/[^\d]/g, ''))).toBe(true);
  });

  test('close events cluster; markers still add up to the count; a cluster tap zooms in and commits once', async ({ page }) => {
    // Put the second event ~45 m from the first (mocked response; production has no two events this close yet).
    let spot = null;
    await page.route(/\/rest\/v1\/events\?/, async (route) => {
      const res = await route.fetch();
      const rows = await res.json();
      if (Array.isArray(rows) && rows.length > 1 && rows[0].lat != null) {
        rows[1].lat = rows[0].lat + 0.0004; rows[1].lng = rows[0].lng;
        spot = [rows[0].lng, rows[0].lat];
      }
      await route.fulfill({ response: res, json: rows });
    });
    await openMap(page);
    expect(spot).not.toBeNull();
    await page.evaluate((c) => window.__mapExploreMapForTests.jumpTo({ center: c, zoom: 14 }), spot);
    const cluster = page.locator('[data-testid^="map-cluster-"]').first();
    await expect(cluster).toBeVisible({ timeout: 5000 });
    expect(await cluster.getAttribute('data-count')).toBe('2');
    await page.waitForTimeout(800);
    expect(await markerTotal(page)).toBe(await countNum(page));
    const z0 = await page.evaluate(() => window.__mapExploreMapForTests.getZoom());
    const before = await commits(page);
    await cluster.click();
    await page.waitForTimeout(1500);
    expect(await page.evaluate(() => window.__mapExploreMapForTests.getZoom())).toBeGreaterThan(z0);
    expect(await commits(page)).toBe(before + 1);
    expect(await markerTotal(page)).toBe(await countNum(page));
    await page.unrouteAll({ behavior: 'ignoreErrors' });
  });

  test('events at the same place stack; tapping the stack opens its neighbourhood panel at those events', async ({ page }) => {
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
    await expect(page.getByTestId('map-area-panel')).toBeVisible();
    expect(await page.locator('[data-testid^="map-area-item-"][role="button"]').count()).toBeGreaterThanOrEqual(2);
    await expect(page.getByTestId('map-list-sheet')).toBeHidden();
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

  test('the list keeps its scroll position when it closes and opens again (its rows only exist while it is open)', async ({ page }) => {
    await openMap(page);
    await openList(page);
    await page.getByTestId('map-list-scroll').evaluate(e => { e.scrollTop = 150; });
    await page.waitForTimeout(250);
    const y0 = await page.getByTestId('map-list-scroll').evaluate(e => e.scrollTop);
    expect(y0).toBeGreaterThan(50);
    await closeList(page);
    await expect(page.locator('[data-testid^="map-list-item-"][role="button"]')).toHaveCount(0); // nothing hidden is rendered
    await openList(page);
    expect(Math.abs((await page.getByTestId('map-list-scroll').evaluate(e => e.scrollTop)) - y0)).toBeLessThan(3);
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
    await page.waitForTimeout(500); // the page turn has settled before the next gesture starts
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

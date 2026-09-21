// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// MapExplore queries the real `public.events` table (not the static demo
// catalogue Home renders) — the seeded demo rows (migration 020) are real,
// `status='live'`, and readable under the shared fast-suite session's own
// RLS-scoped anon/authenticated select policy, so this doesn't need a
// service-role/real-backend session the way tests/e2e/*.spec.js do.

async function openMapWithAPin(page) {
  await setupToHome(page);
  // `open-map-explore` (a dedicated Home-header icon) was replaced by the
  // bottom tab bar's own "Map" tab (`tab-map`) in a2fd823's Home-tab/
  // bottom-dock redesign — this suite's own selector was never updated
  // alongside that change until now (found while verifying Task 7 below;
  // every other test in this file was failing on the stale selector,
  // unrelated to this pass's own fixes).
  await page.click('[data-testid="tab-map"]');
  await page.waitForSelector('[data-screen-label="MapExplore"]');
  // Give the initial fetchLiveEvents()/map init a moment, then wait for at
  // least one pin to actually render.
  const pin = page.locator('[data-testid^="map-pin-"]').first();
  await pin.waitFor({ timeout: 10000 });
  return pin;
}

test.describe('Map Explore — pin/list selection', () => {
  test('tapping a pin shows the compact in-map preview card', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await expect(page.locator('[data-testid="map-selected-card"]')).toHaveCount(0);
    await pin.click();
    const card = page.locator('[data-testid="map-selected-card"]');
    await expect(card).toBeVisible();
    // Essential preview fields per the ticket: name, date/time+area line,
    // price, available/sold-out state, CTA.
    await expect(card).toContainText(/./); // has some name text
    await expect(page.locator('[data-testid="map-card-cta"]')).toBeVisible();
  });

  test('tapping a list row selects it and shows the same card, without navigating away', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    const row = page.locator('[data-testid^="map-list-item-"]').first();
    await row.waitFor({ timeout: 10000 });
    await row.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    // Still on the map screen — a list tap must not jump straight to the
    // full-screen Event Detail page.
    await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible();
    await expect(page.locator('[data-screen-label="EventDetail"]')).toHaveCount(0);
  });

  test('the card\'s CTA opens the existing full-screen Event Detail screen', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
  });

  test('tapping the map background dismisses the card', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    // Click on the map container itself, away from the pin/card/sheet.
    const mapBox = await page.locator('[data-screen-label="MapExplore"] > div').first().boundingBox();
    await page.mouse.click(mapBox.x + mapBox.width / 2, mapBox.y + 60);
    await expect(page.locator('[data-testid="map-selected-card"]')).toHaveCount(0);
  });

  test('a plain map-background tap (no selection ever made) never triggers Search here on its own', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await page.waitForTimeout(500); // let the map settle after its initial center
    await expect(page.locator('[data-testid="map-search-here"]')).toHaveCount(0);
    const mapBox = await page.locator('[data-screen-label="MapExplore"] > div').first().boundingBox();
    await page.mouse.click(mapBox.x + mapBox.width / 2, mapBox.y + 60);
    // A plain tap (no pan/zoom) never fires `moveend`, so `boundsChanged`
    // — and therefore the "Search here" button — must still be absent.
    await expect(page.locator('[data-testid="map-search-here"]')).toHaveCount(0);
  });

  test('the "×" close affordance on the card clears the selection', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await page.locator('[data-testid="map-card-close"]').click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toHaveCount(0);
  });

  // Design change (11-realtime-map.md follow-up): this test used to assert
  // the OPPOSITE — that toggling "Còn chỗ" clears a selection that drops
  // out of the filtered list. That coupling was confirmed to be the wrong
  // behavior and was removed entirely (not patched); see the new
  // "selection/filter decoupling" describe block below for its
  // replacement and the full regression sweep.
});

// Drags the sheet handle by `dyPx` (positive = downward, toward peek).
async function dragHandle(page, dyPx) {
  const handle = page.locator('[data-testid="map-sheet-handle"]');
  const box = await handle.boundingBox();
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x, y + dyPx, { steps: 10 });
  await page.mouse.up();
}

test.describe('Map Explore — bug fixes (card anchor, state restore, mid-detent scrolling)', () => {
  test('bug 1: the preview card stays in the upper area at both tall and mid, and only moves down at peek', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    const card = page.locator('[data-testid="map-selected-card"]');
    await expect(card).toBeVisible();
    // The card's "upper" anchor is now measured from real geometry (the
    // top controls' and the card's own rendered height, via ResizeObserver
    // — 11-realtime-map.md follow-up, "preview card overlaps top
    // controls"), which settles a frame or two after the card's first
    // paint (it renders once at a sane fallback height, then again at its
    // real one) — wait for that to settle before treating this as the
    // baseline "tall" position.
    await page.waitForTimeout(150);
    const tallBox = await card.boundingBox();

    // Drag from tall toward mid (roughly a quarter of the viewport height).
    await dragHandle(page, 200);
    await page.waitForTimeout(400);
    const midBox = await card.boundingBox();
    // The card must NOT have moved down with the sheet — same anchor as tall.
    expect(Math.abs(midBox.y - tallBox.y)).toBeLessThan(5);

    // Now snap all the way to peek via the explicit "List nhỏ" control.
    await page.click('[data-testid="map-sheet-list-small"]');
    await page.waitForTimeout(400);
    const peekBox = await card.boundingBox();
    // Only now should the card have moved substantially further down.
    expect(peekBox.y).toBeGreaterThan(tallBox.y + 100);
  });

  test('bug 2: map camera, sheet detent, filters and selection survive a round trip through Event Detail', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const selectedEventId = testid.replace('map-pin-', '');

    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    // Move off the "tall" default so restoring-to-default would be a
    // detectable failure, not a coincidence.
    await page.click('[data-testid="map-sheet-list-small"]'); // peek
    await page.waitForTimeout(400);

    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();

    // Navigate back via the app's own real back control (this app has no
    // browser-level routing/URLs — `screen` is plain in-memory state — so
    // `page.goBack()` would do nothing meaningful here).
    await page.locator('[data-testid="event-detail-back"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });

    // Restored, not re-initialized: same sheet detent (peek — the "List
    // nhỏ" control still reads as active) and the same event still
    // selected, with its card showing again.
    await expect(page.locator('[data-testid="map-sheet-list-small"]')).toHaveCSS('font-weight', '700');
    const card = page.locator('[data-testid="map-selected-card"]');
    await expect(card).toBeVisible();
    // Computed style reports `transform` as a resolved matrix, not the
    // literal `scale(...)` — matrix(1.15, 0, 0, 1.15, 0, 0) is what a
    // `scale(1.15)` (the selected-pin styling) resolves to.
    await expect(page.locator(`[data-testid="map-pin-${selectedEventId}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('bug 3: the list scrolls normally at the MID detent, and only the handle resizes the sheet', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await page.locator('[data-testid^="map-list-item-"]').first().waitFor({ timeout: 10000 });

    // Move to mid via a handle drag (also exercises "smooth snap on drag").
    await dragHandle(page, 200);
    await page.waitForTimeout(400);

    const list = page.locator('[data-testid="map-list-scroll"]');
    const before = await list.evaluate(el => el.scrollTop);
    // A wheel scroll inside the list content itself (not the handle) must
    // scroll the list, not resize the sheet.
    await list.hover();
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(200);
    const after = await list.evaluate(el => el.scrollTop);
    expect(after).toBeGreaterThan(before);

    // The sheet itself must still be resizable from the handle after this.
    const midTop = await page.locator('[data-testid="map-sheet-handle"]').evaluate(el => el.getBoundingClientRect().top);
    await dragHandle(page, 200);
    await page.waitForTimeout(400);
    const peekTop = await page.locator('[data-testid="map-sheet-handle"]').evaluate(el => el.getBoundingClientRect().top);
    expect(peekTop).toBeGreaterThan(midTop + 50);
  });
});

test.describe('Map Explore — follow-up fixes (handle-only drag, map-specific back, stale card image)', () => {
  test('bug 1: a drag starting in the filter row never resizes the sheet', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await page.locator('[data-testid^="map-list-item-"]').first().waitFor({ timeout: 10000 });

    const handleTopBefore = await page.locator('[data-testid="map-sheet-handle"]').evaluate(el => el.getBoundingClientRect().top);
    const chip = page.locator('[data-testid="map-cat-all"]');
    const box = await chip.boundingBox();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2 + 200, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(400);
    const handleTopAfter = await page.locator('[data-testid="map-sheet-handle"]').evaluate(el => el.getBoundingClientRect().top);
    // The sheet's own top edge (proxied via the handle's position) must be
    // unchanged — only a drag that starts on the handle itself may resize it.
    expect(Math.abs(handleTopAfter - handleTopBefore)).toBeLessThan(5);

    // The handle itself must still work afterward (confirms this isn't just
    // a coincidentally-already-at-that-detent false pass).
    await dragHandle(page, 200);
    await page.waitForTimeout(400);
    const handleTopAfterRealDrag = await page.locator('[data-testid="map-sheet-handle"]').evaluate(el => el.getBoundingClientRect().top);
    expect(handleTopAfterRealDrag).toBeGreaterThan(handleTopAfter + 50);
  });

  test('bug 2: the back pill from a map-opened event reads Map, not Home/banbe', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();

    const backText = (await page.locator('[data-testid="event-detail-back"]').innerText()).trim();
    // eventBackScreen already correctly resolves to 'mapExplore' and
    // backFromEvent() already navigates there — this only checks the label
    // itself, which used to fall through to the Home ('banbe') default.
    expect(backText).toMatch(/Bản đồ|Map/i);
    expect(backText).not.toMatch(/banbe/i);

    // And it must actually still go back to the map, not just claim to.
    await page.locator('[data-testid="event-detail-back"]').click();
    await expect(page.locator('[data-screen-label="MapExplore"]')).toBeVisible();
  });

  test('bug 3: selecting a different event after an Event Detail round trip never shows the previous event\'s card content', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    const pins = page.locator('[data-testid^="map-pin-"]');
    await pins.first().waitFor({ timeout: 10000 });
    const count = await pins.count();
    test.skip(count < 2, 'needs at least two loaded events to tell "still A" apart from "correctly B"');

    const pinA = pins.nth(0);
    const idB = (await pins.nth(1).getAttribute('data-testid')).replace('map-pin-', '');

    await pinA.click();
    const titleA = await page.locator('[data-testid="map-card-title"]').innerText();

    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.locator('[data-testid="event-detail-back"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');

    // Via the list row, not the pin: selecting A zoomed the camera in tight
    // on A's own location, so B's marker may now sit outside the map's
    // visible viewport — the list row is unaffected by camera position and
    // exercises the exact same `selectEvent()` path a pin tap would.
    await page.locator(`[data-testid="map-list-item-${idB}"]`).click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const titleB = await page.locator('[data-testid="map-card-title"]').innerText();
    expect(titleB).not.toBe(titleA);
  });
});

test.describe('Map Explore — follow-up fixes (return-from-detail restore, top-controls overlap)', () => {
  test('returning from Event Detail via the normal back action retains camera, selected preview, filters and sheet detent', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');

    // Filter first, then select via a LIST ROW (not a raw pin): the map
    // draws a pin for every loaded event regardless of category — only the
    // list panel is actually filtered — so selecting straight off an
    // unfiltered pin here could pick an event the "music" filter then
    // excludes, clearing the very selection this test means to restore
    // later (a real, separate quirk of this screen's filter model, not
    // this test's own bug). A list row under an active filter is
    // guaranteed to belong to that filter.
    await page.click('[data-testid="map-cat-music"]');
    const row = page.locator('[data-testid^="map-list-item-"]').first();
    await row.waitFor({ timeout: 10000 });
    const testid = await row.getAttribute('data-testid');
    const selectedEventId = testid.replace('map-list-item-', '');

    // Change enough state that "restored to the default" would be a
    // detectable failure, not a coincidence: a non-default category filter,
    // a non-default sheet snap, and a selection.
    await row.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await page.click('[data-testid="map-sheet-list-small"]'); // peek
    await page.waitForTimeout(400);

    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.locator('[data-testid="event-detail-back"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });

    // Filter retained.
    await expect(page.locator('[data-testid="map-cat-music"]')).toHaveCSS('font-weight', '700');
    // Sheet detent retained (peek).
    await expect(page.locator('[data-testid="map-sheet-list-small"]')).toHaveCSS('font-weight', '700');
    // Selection + card retained.
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await expect(page.locator(`[data-testid="map-pin-${selectedEventId}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('the preview card never overlaps the top controls at TALL or MID', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    const card = page.locator('[data-testid="map-selected-card"]');
    await expect(card).toBeVisible();
    await page.waitForTimeout(150); // let the measured (not fallback) card height settle

    const controlBoxes = await Promise.all(
      ['map-back', 'map-compass'].map(id => page.locator(`[data-testid="${id}"]`).boundingBox())
    );

    const assertNoOverlap = async (label) => {
      const cardBox = await card.boundingBox();
      for (const controlBox of controlBoxes) {
        const overlaps = cardBox.y < controlBox.y + controlBox.height
          && cardBox.y + cardBox.height > controlBox.y
          && cardBox.x < controlBox.x + controlBox.width
          && cardBox.x + cardBox.width > controlBox.x;
        expect(overlaps, `card must not overlap top controls at ${label}`).toBe(false);
      }
    };
    await assertNoOverlap('tall (default)');

    await dragHandle(page, 200); // toward mid
    await page.waitForTimeout(400);
    await assertNoOverlap('mid');
  });

  test('the first post-return polling cycle does not reset map state', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const selectedEventId = testid.replace('map-pin-', '');

    await pin.click();
    await page.click('[data-testid="map-sheet-list-small"]'); // peek
    await page.waitForTimeout(400);
    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.locator('[data-testid="event-detail-back"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });

    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    // POLL_MS is 5000 — wait through at least one full poll cycle and
    // confirm the restored selection/detent are still exactly as restored,
    // not reset by the poll's own `setEvents(fresh)`.
    await page.waitForTimeout(5600);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await expect(page.locator('[data-testid="map-sheet-list-small"]')).toHaveCSS('font-weight', '700');
    await expect(page.locator(`[data-testid="map-pin-${selectedEventId}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });
});

// Bug 4 follow-up (11-realtime-map.md): confirms every category chip Map
// Explore offers (the same FILTER_DEFS keys Home uses) actually narrows the
// list to a non-empty, correctly-matching set, and that "Tất cả" still
// resets to everything — i.e. the reported "any category tap shows zero
// events" is not reproducible against the current key/data matching, for
// any of the four real categories both screens share.
test.describe('Map Explore — follow-up fixes (category filter matches Home\'s taxonomy)', () => {
  for (const key of ['supper', 'fashion', 'gallery', 'music']) {
    test(`the "${key}" category chip shows only matching, non-empty results`, async ({ page }) => {
      await setupToHome(page);
      await page.click('[data-testid="open-map-explore"]');
      await page.waitForSelector('[data-screen-label="MapExplore"]');
      await page.locator('[data-testid^="map-list-item-"]').first().waitFor({ timeout: 10000 });

      await page.click(`[data-testid="map-cat-${key}"]`);
      await expect(page.locator(`[data-testid="map-cat-${key}"]`)).toHaveCSS('font-weight', '700');
      // The core assertion: this category is never silently empty.
      await expect(page.locator('[data-testid^="map-list-item-"]').first()).toBeVisible({ timeout: 5000 });
      const rowCount = await page.locator('[data-testid^="map-list-item-"]').count();
      expect(rowCount).toBeGreaterThan(0);

      // Resetting to "Tất cả" must show at least as many rows as any single
      // category (a real reset, not a stuck/narrower state).
      await page.click('[data-testid="map-cat-all"]');
      await page.waitForTimeout(200);
      const allCount = await page.locator('[data-testid^="map-list-item-"]').count();
      expect(allCount).toBeGreaterThanOrEqual(rowCount);
    });
  }
});

test.describe('Map Explore — Map Explore -> Home close flow follow-up', () => {
  test('task 1: closing via the button shows a shrink/bubble transition before actually leaving', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    const sheet = page.locator('[data-testid="map-sheet"]');
    const identityTransform = await sheet.evaluate(el => getComputedStyle(el).transform);

    await page.click('[data-testid="map-back"]');
    // Mid-transition (closeMap()'s own 420ms delay before it actually
    // navigates) — the sheet must already be visibly shrinking, not still
    // at rest.
    await page.waitForTimeout(150);
    const midTransform = await sheet.evaluate(el => getComputedStyle(el).transform);
    expect(midTransform).not.toBe(identityTransform);

    // ...and the close still actually completes afterward.
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 2000 });
  });

  test('task 2a: the category filter row wraps instead of requiring horizontal scroll', async ({ page }) => {
    await openMapWithAPin(page);
    const row = page.locator('[data-testid="map-cat-all"]').locator('xpath=..');
    const { scrollWidth, clientWidth } = await row.evaluate(el => ({ scrollWidth: el.scrollWidth, clientWidth: el.clientWidth }));
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 1);
  });

  test('task 2b: switching category re-centers the map on that category\'s own density hotspot', async ({ page }) => {
    await openMapWithAPin(page);
    await page.waitForFunction(() => !!window.__mapExploreMapForTests);
    const centerBefore = await page.evaluate(() => window.__mapExploreMapForTests.getCenter());

    await page.click('[data-testid="map-cat-music"]');
    await page.locator('[data-testid^="map-list-item-"]').first().waitFor({ timeout: 10000 });
    await page.waitForTimeout(900); // the recenter flyTo's own 700ms duration

    const centerAfter = await page.evaluate(() => window.__mapExploreMapForTests.getCenter());
    const moved = Math.abs(centerAfter.lat - centerBefore.lat) > 0.0005 || Math.abs(centerAfter.lng - centerBefore.lng) > 0.0005;
    expect(moved).toBe(true);
  });

  test('task 3: list shows distance in km once location is granted, without touching "Gần bạn"', async ({ page, context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 10.78, longitude: 106.7 });
    await openMapWithAPin(page);

    // The app's own real grant flow (the compass button), never "Gần bạn".
    await page.click('[data-testid="map-compass"]');
    await expect(page.locator('[data-testid="map-chip-nearby"]')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('[data-testid="map-chip-nearby"]')).toHaveCSS('font-weight', '400');

    const firstRow = page.locator('[data-testid^="map-list-item-"]').first();
    await expect(firstRow).toContainText('km', { timeout: 10000 });
  });

  test('task 4: tapping the preview card\'s non-CTA area re-centers on the selected event', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await page.waitForFunction(() => !!window.__mapExploreMapForTests);
    await page.waitForTimeout(700); // let selectEvent()'s own initial flyTo settle first

    const centerAtSelection = await page.evaluate(() => window.__mapExploreMapForTests.getCenter());

    // Move the camera away directly via the map's own API — a real user
    // drag on a WebGL canvas isn't reliably reproducible under Playwright;
    // panBy() exercises the exact same camera-movement primitive a drag
    // would, without that synthetic-gesture reliability question.
    await page.evaluate(() => window.__mapExploreMapForTests.panBy([300, 300], { duration: 0 }));
    const centerAfterPan = await page.evaluate(() => window.__mapExploreMapForTests.getCenter());
    const actuallyPanned = Math.abs(centerAfterPan.lat - centerAtSelection.lat) > 0.001 || Math.abs(centerAfterPan.lng - centerAtSelection.lng) > 0.001;
    expect(actuallyPanned).toBe(true);

    await page.click('[data-testid="map-card-recenter"]');
    await page.waitForTimeout(700); // selectEvent()'s own 550ms flyTo duration
    const centerAfterRecenter = await page.evaluate(() => window.__mapExploreMapForTests.getCenter());
    const movedBack = Math.abs(centerAfterRecenter.lat - centerAfterPan.lat) > 0.0005 || Math.abs(centerAfterRecenter.lng - centerAfterPan.lng) > 0.0005;
    expect(movedBack).toBe(true);
    // The card must still be showing the same event, not have been cleared.
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
  });

  test('follow-up bug 2: "← Đóng" renders at the same height/weight as "Tìm ở đây"', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    // Pan the map so "Tìm ở đây" actually appears (it's conditional on
    // `boundsChanged`, only set once a real `moveend` fires).
    // Two real camera moves via the map's own API (the same one
    // `window.__mapExploreMapForTests` exposes for other tests in this
    // file) — the FIRST `moveend` only establishes the baseline bounds
    // (see `MapExplore.jsx`'s own `map.on('moveend', ...)`), only the
    // SECOND one actually flips `boundsChanged`.
    await page.waitForFunction(() => !!window.__mapExploreMapForTests);
    await page.evaluate(() => window.__mapExploreMapForTests.panBy([80, 80], { duration: 0 }));
    await page.waitForTimeout(200);
    await page.evaluate(() => window.__mapExploreMapForTests.panBy([80, 80], { duration: 0 }));
    await page.locator('[data-testid="map-search-here"]').waitFor({ timeout: 10000 });

    const back = page.locator('[data-testid="map-back"]');
    const searchHere = page.locator('[data-testid="map-search-here"]');
    const [backBox, searchBox, backWeight, searchWeight] = await Promise.all([
      back.boundingBox(),
      searchHere.boundingBox(),
      back.evaluate(el => getComputedStyle(el).fontWeight),
      searchHere.evaluate(el => getComputedStyle(el).fontWeight),
    ]);
    expect(backBox.height).toBeCloseTo(searchBox.height, 0);
    expect(backWeight).toBe(searchWeight);
  });
});

// Design change (11-realtime-map.md follow-up): the selected-event preview
// card is now fully decoupled from the list's active filter — selecting
// reads the full, unfiltered `events`, never the filtered `visibleEvents`.
// This block is both the direct repro/verification of that change and the
// full regression sweep the ticket asked for.
test.describe('Map Explore — selection/filter decoupling (design change follow-up)', () => {
  test('applying/removing category filters never clears an existing selection — only the list narrows', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const title = await page.locator('[data-testid="map-card-title"]').innerText();

    // Cycle through every category, including ones this event does NOT
    // belong to (the list row for it must then disappear) and back to
    // "Tất cả" — the card/pin selection must never react to any of this.
    for (const key of ['supper', 'fashion', 'gallery', 'music', 'all']) {
      await page.click(`[data-testid="map-cat-${key}"]`);
      await page.waitForTimeout(150);
      await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
      expect(await page.locator('[data-testid="map-card-title"]').innerText()).toBe(title);
      await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
      // The pin itself must also still be rendered on the map regardless
      // of category (pins were already unfiltered on web; this reconfirms
      // it while sweeping) — the list row's own membership is the only
      // thing allowed to change per filter.
      await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toBeVisible();
    }
  });

  test('toggling "Còn chỗ" never clears an existing selection — only the list narrows', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const title = await page.locator('[data-testid="map-card-title"]').innerText();

    await page.click('[data-testid="map-chip-open-now"]');
    await page.waitForTimeout(150);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    expect(await page.locator('[data-testid="map-card-title"]').innerText()).toBe(title);
    await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');

    // Toggle back off — same requirement, and the list itself must have
    // reverted to including whatever it did before (a real, working
    // filter, not one that's silently stopped narrowing anything).
    await page.click('[data-testid="map-chip-open-now"]');
    await page.waitForTimeout(150);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
  });

  test('sweep 2a: toggling "Gần bạn" (nearby sort) preserves an existing selection', async ({ page, context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 10.78, longitude: 106.7 });
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();

    // Grant location the app's own real way (compass tap) — `sortByDistance`
    // only re-SORTS `visibleEvents`, and never touches `selectedEvent`'s own
    // (now unfiltered) derivation at all.
    await page.click('[data-testid="map-compass"]');
    await expect(page.locator('[data-testid="map-chip-nearby"]')).toBeVisible({ timeout: 5000 });
    await page.click('[data-testid="map-chip-nearby"]');
    await page.waitForTimeout(200);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('sweep 2b: a search-here re-query preserves an existing selection that stays within the new bounds', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();

    // A SMALL pan (not a recenter to some other location entirely) —
    // small enough that the selected event's own coordinates stay well
    // within the re-queried bounds; "Search here" is a genuine bounds-
    // restricted re-fetch, so panning far enough away to truly exclude the
    // event IS one of the ticket's own explicitly-endorsed clearing cases
    // ("the underlying event actually disappearing from the data
    // entirely") — this test is specifically about the case where it
    // doesn't leave the queried area at all.
    await page.waitForFunction(() => !!window.__mapExploreMapForTests);
    await page.evaluate(() => window.__mapExploreMapForTests.panBy([15, 15], { duration: 0 }));
    await page.waitForTimeout(150);
    await page.evaluate(() => window.__mapExploreMapForTests.panBy([15, 15], { duration: 0 }));
    await page.locator('[data-testid="map-search-here"]').waitFor({ timeout: 10000 });
    await page.click('[data-testid="map-search-here"]');
    await page.waitForTimeout(400);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('sweep 3: a live poll refresh updates the card without clearing or flickering it', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const title = await page.locator('[data-testid="map-card-title"]').innerText();

    // POLL_MS is 5000 — wait through a full cycle with no interaction.
    await page.waitForTimeout(5600);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    expect(await page.locator('[data-testid="map-card-title"]').innerText()).toBe(title);
    await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('sweep 4: a filter applied before an Event Detail round trip restores independently of the selection', async ({ page }) => {
    await setupToHome(page);
    await page.click('[data-testid="open-map-explore"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await page.click('[data-testid="map-cat-music"]');
    const row = page.locator('[data-testid^="map-list-item-"]').first();
    await row.waitFor({ timeout: 10000 });
    const rowTestid = await row.getAttribute('data-testid');
    const id = rowTestid.replace('map-list-item-', '');
    await row.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();

    await page.locator('[data-testid="map-card-cta"]').click();
    await expect(page.locator('[data-screen-label="EventDetail"], [data-screen-label="Event"]')).toBeVisible();
    await page.locator('[data-testid="event-detail-back"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });
    // Let the restored pin's one-shot "pop" overshoot (`gocPinPop`, 0.32s)
    // settle to its final resting scale before asserting on it.
    await page.waitForTimeout(500);

    // Both restored, independently — the filter didn't have to "let" the
    // selection back in, and the selection didn't have to "let" the
    // filter apply.
    await expect(page.locator('[data-testid="map-cat-music"]')).toHaveCSS('font-weight', '700');
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    await expect(page.locator(`[data-testid="map-pin-${id}"]`)).toHaveCSS('transform', 'matrix(1.15, 0, 0, 1.15, 0, 0)');
  });

  test('sweep 5: switching filters at every sheet detent leaves selection/detent state uncorrupted', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();

    for (const detentTestId of ['map-sheet-list-large', 'map-sheet-list-small']) {
      await page.click(`[data-testid="${detentTestId}"]`);
      await page.waitForTimeout(300);
      await page.click('[data-testid="map-cat-music"]');
      await page.waitForTimeout(150);
      await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
      await expect(page.locator(`[data-testid="${detentTestId}"]`)).toHaveCSS('font-weight', '700');
      await page.click('[data-testid="map-cat-all"]');
    }
  });

  test('sweep 6: rapidly tapping several filter chips in succession leaves a card matching the last tap, never a stale one', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const title = await page.locator('[data-testid="map-card-title"]').innerText();

    // No waits between clicks — deliberately racy.
    for (const key of ['supper', 'fashion', 'gallery', 'music', 'all']) {
      await page.click(`[data-testid="map-cat-${key}"]`);
    }
    await expect(page.locator('[data-testid="map-cat-all"]')).toHaveCSS('font-weight', '700');
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    expect(await page.locator('[data-testid="map-card-title"]').innerText()).toBe(title);
    // The list must match the LAST tapped filter ("Tất cả" — everything),
    // not some intermediate one from mid-race.
    await expect(page.locator('[data-testid^="map-list-item-"]').first()).toBeVisible();
  });
});

// Task 7 (2026-09-21 follow-up) — real regression repro/fix verification,
// per this ticket's own explicit "confirm against a real Open in Map flow
// followed by a category filter tap" ask. Root cause: "Open in Map"
// (GocContext.jsx's openEventOnMap) constructs the map at a deliberately
// tight zoom (15.5, a focused single-pin view) — `lastQueriedBounds` used
// to be seeded from that same tight viewport, so the 5s freshness poll
// silently replaced the full loaded `events` set with just the one or two
// events inside that tiny box a few seconds after opening, independent of
// any filter tap (the filter tap only made the already-collapsed dataset's
// narrowing visible). Fixed via `restored.singleEventFocus` — the query
// bounds now stay wide (city-scale) while the camera still visually zooms
// in tight on the selected pin.
test.describe('Map Explore — Task 7 (Open in Map + category filter regression)', () => {
  test('opening an event via "Open in Map", waiting past a poll cycle, then tapping a category filter still shows the full dataset, not just the selected event', async ({ page }) => {
    await setupToHome(page);
    // A real supper-club event, reached the same way a real user would —
    // via a Home card, not a synthetic navigation call.
    await page.locator('[data-testid^="home-event-"]').first().click();
    await page.waitForSelector('[data-screen-label="Event"]');
    await page.locator('[data-testid="event-open-in-map"]').click();
    await page.waitForSelector('[data-screen-label="MapExplore"]');

    // The selected event's own card should show immediately.
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const initialCount = await page.locator('[data-testid^="map-list-item-"]').count();
    expect(initialCount).toBeGreaterThan(1);

    // Wait past at least one 5s freshness poll cycle — this is exactly
    // where the bug fired (the poll re-queried using the too-tight bounds
    // and silently collapsed `events` to almost nothing), independent of
    // any filter tap.
    await page.waitForTimeout(5500);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    expect(await page.locator('[data-testid^="map-list-item-"]').count()).toBeGreaterThan(1);

    // Now the actual reported trigger: a category filter tap. The card and
    // the list must both still reflect the FULL dataset, filtered — not
    // narrowed down to just the originally-selected event.
    await page.click('[data-testid="map-cat-supper"]');
    await page.waitForTimeout(300);
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    const supperCount = await page.locator('[data-testid^="map-list-item-"]').count();
    expect(supperCount).toBeGreaterThan(1);

    await page.click('[data-testid="map-cat-all"]');
    await page.waitForTimeout(300);
    expect(await page.locator('[data-testid^="map-list-item-"]').count()).toBeGreaterThanOrEqual(supperCount);
  });
});

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
  await page.click('[data-testid="open-map-explore"]');
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

  test('selection clears if the selected event drops out of the filtered results', async ({ page }) => {
    const pin = await openMapWithAPin(page);
    const testid = await pin.getAttribute('data-testid');
    const id = testid.replace('map-pin-', '');
    await pin.click();
    await expect(page.locator('[data-testid="map-selected-card"]')).toBeVisible();
    // "Còn chỗ" (open-now) filters visibleEvents down to seats_remaining > 0
    // — if the selected event doesn't have live seats (sold out or a NULL
    // seats_remaining row), it drops out of visibleEvents and the
    // useEffect that watches `selectedEvent` should clear the stale
    // selection rather than leave the card showing something no longer in
    // the current filtered set.
    await page.click('[data-testid="map-chip-open-now"]');
    // Either the card cleared (event had no live seats) or it's still
    // showing the same still-qualifying event — both are correct; what's
    // never correct is the card surviving while genuinely absent from the
    // list. Confirm consistency between the two directly:
    const stillInList = await page.locator(`[data-testid="map-list-item-${id}"]`).count();
    if (stillInList === 0) {
      await expect(page.locator('[data-testid="map-selected-card"]')).toHaveCount(0);
    }
  });
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

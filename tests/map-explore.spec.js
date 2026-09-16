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

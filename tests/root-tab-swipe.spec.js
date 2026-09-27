// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Stage 2 (2026-09-27 nav/discovery pass) — at root-tab level, a
// left/right horizontal swipe should move to the adjacent tab in dock
// order (Home, Map, Notifications, Inbox, Account), exactly as tapping
// that tab does, without stealing the gesture from vertical scroll,
// Home's own horizontal rails (data-hscroll), or the reserved edge zone.

// The app renders centered with its own maxWidth (480px) — on a wider
// Playwright viewport (default 1280px) that leaves empty space on both
// sides, so gesture coordinates must be computed against THIS container's
// own bounding box, not the raw page viewport. A real phone has no such
// margin (the app fills the whole screen), which specifically matters for
// the Map edge-zone case below — there's no room to drag further right
// than the container's own edge on a wide desktop viewport, so this suite
// uses a phone-sized one instead.
test.use({ viewport: { width: 390, height: 844 } });

async function appBox(page) {
  return page.locator('[data-bb-theme] > div').first().boundingBox();
}

test.describe('Root-tab horizontal swipe', () => {
  test('swiping left from Home goes to Map, then Map to Notifications from its edge zone', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const box = await appBox(page);
    const midY = box.y + Math.min(box.height, 600) / 2;
    const startX = box.x + box.width * 0.6; // clear of the left edge-reserve zone

    // Swipe left (finger moves right-to-left) -> next tab (Map).
    await page.mouse.move(startX, midY);
    await page.mouse.down();
    for (let x = startX; x > startX - 160; x -= 20) {
      await page.mouse.move(x, midY);
    }
    await page.mouse.up();

    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });

    // On Map, the gesture only engages from a narrow strip near the RIGHT
    // edge (map panning owns the rest of the canvas — see App.jsx's own
    // EDGE_RESERVE_PX comment) — physically, that only leaves room to drag
    // LEFT (inward) from there, which advances to the NEXT tab
    // (Notifications), the same direction Android's own right-edge
    // gesture convention uses.
    const box2 = await appBox(page);
    const mapStartX = box2.x + box2.width - 8;
    await page.mouse.move(mapStartX, midY);
    await page.mouse.down();
    for (let x = mapStartX; x > mapStartX - 160; x -= 20) {
      await page.mouse.move(x, midY);
    }
    await page.mouse.up();

    await page.waitForSelector('[data-screen-label="Notifications"]', { timeout: 5000 });

    // From a non-Map root screen, swiping right (mid-screen, no edge
    // restriction) goes back to the PREVIOUS tab (Map) — confirms the
    // "previous" direction works normally wherever Map's own pan
    // conflict doesn't apply.
    const box3 = await appBox(page);
    const notifStartX = box3.x + box3.width * 0.4;
    await page.mouse.move(notifStartX, midY);
    await page.mouse.down();
    for (let x = notifStartX; x < notifStartX + 160; x += 20) {
      await page.mouse.move(x, midY);
    }
    await page.mouse.up();

    await page.waitForSelector('[data-screen-label="MapExplore"]', { timeout: 5000 });
  });

  test('a short drag under the commit threshold snaps back without navigating', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const box = await appBox(page);
    const midY = box.y + Math.min(box.height, 600) / 2;
    const startX = box.x + box.width * 0.6;

    await page.mouse.move(startX, midY);
    await page.mouse.down();
    await page.mouse.move(startX - 25, midY); // well under the 70px commit threshold
    await page.mouse.up();

    await page.waitForTimeout(400);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('a horizontal drag starting over a horizontal rail does not navigate', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');
    const rail = page.locator('[data-hscroll="true"]').first();
    await rail.waitFor();
    const railBox = await rail.boundingBox();
    const startX = railBox.x + railBox.width * 0.5;
    const midY = railBox.y + railBox.height / 2;

    await page.mouse.move(startX, midY);
    await page.mouse.down();
    for (let x = startX; x > startX - 160; x -= 20) {
      await page.mouse.move(x, midY);
    }
    await page.mouse.up();

    await page.waitForTimeout(400);
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });
});

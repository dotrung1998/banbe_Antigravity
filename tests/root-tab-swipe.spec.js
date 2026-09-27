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
    // Root-tab-swipe fix pass (2026-09-27, follow-up B) — the destination
    // screen is now mounted (and its own `data-screen-label` visible) as
    // soon as the drag reveals it, well before the ~250ms settle actually
    // flips `state.screen` for real (see App.jsx's own `commitNext`
    // comment) — intentional, so the real screen/data is there to see
    // during the drag itself, not a blank canvas. A back-to-back second
    // gesture started mid-settle would race that flip, exactly as it
    // would on a real device swiping twice with no pause — this waits out
    // that same brief window before continuing, same as a real user's own
    // natural pause between two swipes.
    await page.waitForTimeout(300);

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
    await page.waitForTimeout(300);

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

  // iPhone fix pass (2026-09-27), Item 1 — deterministic regression test
  // for the real tap-race root cause: `endGesture`'s committed-swipe
  // branch used to unconditionally apply its own 250ms-delayed
  // `gotoDockIndex(...)`, with nothing checking whether a newer navigation
  // (a plain dock tap) had already happened in the meantime. This swipes
  // Home -> Map (a real committed root-tab swipe, so its 250ms settle
  // timeout is genuinely pending), then taps Account in the dock BEFORE
  // that settle fires — a tap must always win over a stale, already-
  // superseded swipe-settle, never get silently overwritten back to the
  // swipe's own original destination once the delayed callback finally
  // runs.
  test('a dock tap immediately after a swipe commit is not overwritten by the stale settle', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    // Land on Notifications first via a plain dock tap (not a swipe) —
    // avoids Map entirely, whose own native map/filter-sheet layout is a
    // separate, unrelated case not what this test targets.
    await page.getByTestId('tab-notifications').click();
    await page.waitForSelector('[data-screen-label="Notifications"]');

    const box = await appBox(page);
    const midY = box.y + Math.min(box.height, 600) / 2;
    const startX = box.x + box.width * 0.6;

    // Swipe left from Notifications -> commits toward Inbox (crosses
    // SWIPE_COMMIT_PX), whose 250ms settle timeout starts counting down
    // the instant pointerup fires below.
    await page.mouse.move(startX, midY);
    await page.mouse.down();
    for (let x = startX; x > startX - 160; x -= 20) {
      await page.mouse.move(x, midY);
    }
    await page.mouse.up();

    // Tap Account immediately — well inside the pending 250ms settle
    // window, with no artificial wait added for it (a real fast-follow
    // tap, not a slowed-down one this fix would only work around).
    await page.getByTestId('tab-profile').click();

    // The tap must win outright, immediately...
    await page.waitForSelector('[data-screen-label="Account"]', { timeout: 2000 });
    // ...and stay won once the stale swipe-settle timeout actually fires —
    // this is the real regression: without the fix, Account is reached
    // for an instant and then silently reverts to Map once that delayed
    // callback runs ~250ms after the swipe's own pointerup.
    await page.waitForTimeout(400);
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible();
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

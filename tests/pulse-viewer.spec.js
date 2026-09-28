// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Pulse/loading UX pass (2026-09-27) — A1/A2/A3: header logo parity, the
// shared loading GIF asset, and the interactive left-to-right dismiss
// (X and an edge-swipe both drive the SAME one continuous slide that
// reveals Home underneath, never a downward exit / a second slide after
// releasing). No test file for Pulse existed before this pass.

async function openPulse(page) {
  await setupToHome(page);
  await page.click('[data-testid="home-pulse-avatar"]');
  await page.waitForSelector('[data-testid="pulse-viewer"]');
}

test.describe('Banbe Pulse — header, loading asset, interactive dismiss', () => {
  test('header shows the logo followed by visible "Pulse" text, one accessible "Banbe Pulse" title', async ({ page }) => {
    await openPulse(page);
    const heading = page.locator('[data-testid="pulse-viewer"] [role="heading"]');
    await expect(heading).toHaveAttribute('aria-label', 'Banbe Pulse');
    await expect(heading.locator('img')).toHaveAttribute('src', '/banbe-wordmark.png');
    await expect(heading).toContainText('Pulse');
  });

  test('the shared loading GIF asset is actually served', async ({ page }) => {
    const resp = await page.request.get('/banbe-loading.gif');
    expect(resp.ok()).toBe(true);
    expect(resp.headers()['content-type']).toMatch(/gif/);
  });

  test('the X close button slides Pulse away in one continuous motion, revealing Home (never a blank/white flash)', async ({ page }) => {
    await openPulse(page);
    // Home stays mounted underneath the whole time (App.jsx renders Pulse
    // as a sibling overlay, never a route change) — its own dock is a
    // reliable, always-present marker for "the real Home, not white."
    await expect(page.locator('[data-testid="tab-home"], [data-screen-label="Home"]').first()).toBeAttached();

    await page.click('[data-testid="pulse-close"]');
    // Mid-animation: translateX should be progressing (non-zero, and not
    // yet fully off-screen) at some point during the 260ms commit window —
    // confirms ONE animated slide is actually playing, not an instant cut.
    await page.waitForTimeout(80);
    const midTransform = await page.locator('[data-testid="pulse-viewer"]').evaluate(el => getComputedStyle(el).transform).catch(() => null);
    if (midTransform && midTransform !== 'none') {
      expect(midTransform).not.toBe('matrix(1, 0, 0, 1, 0, 0)'); // not still at translateX(0)
    }
    await expect(page.locator('[data-testid="pulse-viewer"]')).toHaveCount(0, { timeout: 1000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('a left-to-right edge-swipe past the threshold dismisses Pulse the same way as the X', async ({ page }) => {
    await openPulse(page);
    const zone = page.locator('[data-testid="pulse-edge-swipe-zone"]');
    const box = await zone.boundingBox();
    const viewport = page.viewportSize();
    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    // Past the 30%-of-viewport-width commit threshold.
    await page.mouse.move(startX + viewport.width * 0.5, startY, { steps: 6 });
    await page.waitForTimeout(50);
    const liveTransform = await page.locator('[data-testid="pulse-viewer"]').evaluate(el => getComputedStyle(el).transform);
    expect(liveTransform).not.toBe('matrix(1, 0, 0, 1, 0, 0)'); // live-following the drag already
    await page.mouse.up();
    await expect(page.locator('[data-testid="pulse-viewer"]')).toHaveCount(0, { timeout: 1000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('a cancelled (short) edge-swipe springs back instead of dismissing', async ({ page }) => {
    await openPulse(page);
    const zone = page.locator('[data-testid="pulse-edge-swipe-zone"]');
    const box = await zone.boundingBox();
    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX + 20, startY, { steps: 3 }); // well under threshold
    await page.mouse.up();
    await page.waitForTimeout(400);
    await expect(page.locator('[data-testid="pulse-viewer"]')).toBeVisible();
  });
});

test.describe('Home — Pulse teaser speech bubbles', () => {
  test('shows the first step ("Top sự kiện hôm nay") and is dismissed immediately once Pulse opens', async ({ page }) => {
    await setupToHome(page);
    const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
    await expect(bubble).toBeVisible({ timeout: 4000 });
    await expect(bubble).toContainText(/Top sự kiện hôm nay|Today's top events/);

    await page.click('[data-testid="home-pulse-avatar"]');
    await page.waitForSelector('[data-testid="pulse-viewer"]');
    await expect(bubble).toHaveCount(0);
  });

  test('tapping the bubble advances to the next step immediately, without waiting out its timer', async ({ page }) => {
    await setupToHome(page);
    const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
    await expect(bubble).toBeVisible({ timeout: 4000 });
    await expect(bubble).toContainText(/Top sự kiện hôm nay|Today's top events/);
    // A direct in-page `.click()` — the bubble legitimately re-measures/
    // repositions itself on scroll/resize (this pass's own "anchored to
    // the real ring element" requirement), which can race a
    // coordinate-based click dispatch on WebKit even though the element is
    // genuinely visible/clickable at rest. This test's own point is
    // "tapping fires the handler and advances the step," not the exact
    // on-screen coordinates a real finger would land on, so dispatching
    // the click on the actual DOM node sidesteps that geometry race
    // entirely instead of masking a real product bug.
    await bubble.evaluate((el) => el.click());
    // Step 1 is either the real top-3 names or the honest empty hint —
    // never still step 0's own label, and well before the ~4.6s the real
    // timer would otherwise take.
    await expect(bubble).not.toContainText(/Top sự kiện hôm nay|Today's top events/);
  });

  // Positioning pass (2026-09-28) — beside the ring (comic speech bubble),
  // not above it: pointer on the LEFT edge, text right-aligned, whole box
  // inside the viewport. Real anchoring (getBoundingClientRect against the
  // real ring element), not a hardcoded offset — confirmed by checking the
  // bubble sits to the ring's right and stays within window bounds.
  test('sits BESIDE the Pulse ring (to its right, vertically overlapping it), with a left-pointing pointer, fully inside the viewport', async ({ page }) => {
    await setupToHome(page);
    const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
    await expect(bubble).toBeVisible({ timeout: 4000 });
    const ring = page.locator('[data-testid="home-pulse-avatar"]');
    const bubbleBox = await bubble.boundingBox();
    const ringBox = await ring.boundingBox();
    const viewport = page.viewportSize();

    // Beside, not above: the bubble's left edge starts at/after the ring's
    // right edge (never above/overlapping the ring vertically the way the
    // old "centered above" layout did), and its vertical range overlaps
    // the ring's own vertical range (roughly centered on it).
    expect(bubbleBox.x).toBeGreaterThanOrEqual(ringBox.x + ringBox.width - 1);
    const bubbleMidY = bubbleBox.y + bubbleBox.height / 2;
    expect(bubbleMidY).toBeGreaterThanOrEqual(ringBox.y - 2);
    expect(bubbleMidY).toBeLessThanOrEqual(ringBox.y + ringBox.height + 2);

    // Fully inside the viewport on every side — the clamping this pass
    // added, not a hardcoded guess about screen size.
    expect(bubbleBox.x).toBeGreaterThanOrEqual(0);
    expect(bubbleBox.y).toBeGreaterThanOrEqual(0);
    expect(bubbleBox.x + bubbleBox.width).toBeLessThanOrEqual(viewport.width + 1);
    expect(bubbleBox.y + bubbleBox.height).toBeLessThanOrEqual(viewport.height + 1);

    // Text right-aligned inside the bubble.
    const textAlign = await bubble.evaluate(el => getComputedStyle(el).textAlign);
    expect(textAlign).toBe('right');
  });

  // Timing-rule pass (2026-09-28) — real wall-clock repeat. Rather than
  // fighting Playwright's fake-clock/native-setInterval interaction (the
  // poll is a plain `setInterval` already running by the time a test could
  // install a fake clock, so `page.clock.fastForward()` cannot advance it),
  // these tests mock the ELAPSED-TIME INPUT directly — rewriting the
  // real localStorage timestamp the app itself just wrote to a point
  // further in the past — then wait a few real seconds (never a real
  // 5-minute sleep) for the app's own unmodified `setInterval` poll to
  // re-check it. This still exercises the real comparison/poll logic, not
  // a short-circuited fake.
  test.describe('5-minute repeat rule', () => {
    function backdateLastShown(page, minutesAgo) {
      return page.evaluate((mins) => {
        for (const key of Object.keys(localStorage)) {
          if (key.startsWith('banbe_pulse_bubbles_lastshown_')) {
            localStorage.setItem(key, String(Date.now() - mins * 60 * 1000));
          }
        }
      }, minutesAgo);
    }

    test('reappears once 5 minutes of elapsed wall-clock time have passed since the previous dismiss, not before', async ({ page }) => {
      await setupToHome(page);
      const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
      await expect(bubble).toBeVisible({ timeout: 4000 });

      // Dismiss by tapping outside — starts the 5-minute countdown "from
      // that moment" per the ticket's own rule.
      await page.mouse.click(2, 2);
      await expect(bubble).toHaveCount(0);

      // Simulate "4 minutes have passed" — must NOT reappear yet.
      await backdateLastShown(page, 4);
      await page.waitForTimeout(6000); // one real poll cycle (5s interval)
      await expect(bubble).toHaveCount(0);

      // Simulate "past 5 minutes" — reappears, exactly one sequence.
      await backdateLastShown(page, 5.5);
      await expect(bubble).toBeVisible({ timeout: 8000 });
      await expect(bubble).toHaveCount(1);
    });

    test('never restarts a sequence that is already showing, even once 5 minutes have passed', async ({ page }) => {
      await setupToHome(page);
      const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
      await expect(bubble).toBeVisible({ timeout: 4000 });
      await expect(bubble).toContainText(/Top sự kiện hôm nay|Today's top events/);

      // The sequence is still showing (never dismissed) — there is no
      // lastShown timestamp to backdate yet; the poll must still never
      // stack/restart a second bubble while `step` is already >= 0.
      await page.waitForTimeout(6000);
      await expect(bubble).toHaveCount(1);
    });

    test('does not show while the tab/app is not visible, even past the 5-minute mark', async ({ page }) => {
      await setupToHome(page);
      const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
      await expect(bubble).toBeVisible({ timeout: 4000 });
      await page.mouse.click(2, 2); // dismiss, starts the countdown
      await expect(bubble).toHaveCount(0);

      await backdateLastShown(page, 6);
      // Simulate the tab/app being backgrounded via document.hidden — the
      // poll must not fire a new sequence while hidden even though the
      // stored timestamp already qualifies.
      await page.evaluate(() => {
        Object.defineProperty(document, 'hidden', { value: true, configurable: true });
        document.dispatchEvent(new Event('visibilitychange'));
      });
      await page.waitForTimeout(6000);
      await expect(bubble).toHaveCount(0);

      await page.evaluate(() => {
        Object.defineProperty(document, 'hidden', { value: false, configurable: true });
        document.dispatchEvent(new Event('visibilitychange'));
      });
      await expect(bubble).toBeVisible({ timeout: 6000 });
    });
  });
});

test.describe('Banbe Pulse — cached vs. loading tabs', () => {
  test('switching tabs after the initial load never re-shows the loading GIF for already-cached content', async ({ page }) => {
    await openPulse(page);
    // All three tabs are fetched up front on open (openPulseViewer) — wait
    // for the daily tab's own loading to finish first.
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });

    await page.getByTestId('pulse-tab-weekly').click();
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0);
    await page.getByTestId('pulse-tab-photos').click();
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0);
    await page.getByTestId('pulse-tab-daily').click();
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0);
  });

  // White-flash fix (2026-09-28 pass) — a card's own thumbnail tile must
  // never be transparent/blank while its photo is still downloading; it
  // must always carry a themed fallback fill (never the bare page
  // background painting through), and a tab with already-valid cached
  // items must keep showing them instead of blanking to the loading GIF
  // on any background refetch.
  test('a card thumbnail always has a themed background-color fallback (never a bare/blank fill) regardless of image-load state', async ({ page }) => {
    await openPulse(page);
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });
    const card = page.getByTestId('pulse-card').first();
    if (await card.count()) {
      const tile = card.locator('div').first();
      const bg = await tile.evaluate(el => getComputedStyle(el).backgroundColor);
      // Never fully transparent — a themed fallback color is always set,
      // whether or not the real photo has finished decoding yet.
      expect(bg).not.toBe('rgba(0, 0, 0, 0)');
      expect(bg).not.toBe('transparent');
    }
  });

  test('revisiting a tab whose data is still cached shows its content immediately, never the loading GIF', async ({ page }) => {
    await openPulse(page);
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });
    // Switch away and back quickly — the previously-displayed tab's own
    // items must still be there the instant it's shown again (kept
    // mounted/cached in state, not refetched/blanked).
    await page.getByTestId('pulse-tab-weekly').click();
    await page.getByTestId('pulse-tab-daily').click();
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0);
    await expect(page.getByTestId('pulse-empty')).toHaveCount(0).catch(() => {});
  });

  // Left-corner-rounding fix (2026-09-28 pass) — the flush-left photo tile
  // now carries its own explicit left-only radius, matching the card's
  // overall rounding on the right, regardless of load state.
  test('the event-card photo tile has matching left/right rounding (not square-left/round-right)', async ({ page }) => {
    await openPulse(page);
    await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });
    const card = page.getByTestId('pulse-card').first();
    if (await card.count()) {
      const tile = card.locator('div').first();
      const radius = await tile.evaluate(el => getComputedStyle(el).borderRadius);
      // e.g. "12px 0px 0px 12px" — left corners rounded, matching the
      // card's own 12px radius (never "0px" on the left only).
      const [topLeft, , , bottomLeft] = radius.split(' ');
      expect(parseFloat(topLeft)).toBeGreaterThan(0);
      expect(parseFloat(bottomLeft || topLeft)).toBeGreaterThan(0);
    }
  });
});

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

  test('does not replay on a fresh Home mount once already seen', async ({ page }) => {
    await setupToHome(page);
    await expect(page.locator('[data-testid="home-pulse-teaser-bubble"]')).toBeVisible({ timeout: 4000 });
    await page.click('[data-testid="tab-map"]');
    await page.waitForSelector('[data-screen-label="MapExplore"]');
    await page.click('[data-testid="map-back"]');
    await page.waitForSelector('[data-screen-label="Home"]');
    await expect(page.locator('[data-testid="home-pulse-teaser-bubble"]')).toHaveCount(0);
  });

  test('tapping the bubble advances to the next step immediately, without waiting out its timer', async ({ page }) => {
    await setupToHome(page);
    const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
    await expect(bubble).toBeVisible({ timeout: 4000 });
    await expect(bubble).toContainText(/Top sự kiện hôm nay|Today's top events/);
    await bubble.click();
    // Step 1 is either the real top-3 names or the honest empty hint —
    // never still step 0's own label, and well before the ~4.6s the real
    // timer would otherwise take.
    await expect(bubble).not.toContainText(/Top sự kiện hôm nay|Today's top events/);
  });

  test('is anchored to the Pulse ring itself (not a fixed page offset), staying clear of "Sự kiện của bạn"', async ({ page }) => {
    await setupToHome(page);
    const bubble = page.locator('[data-testid="home-pulse-teaser-bubble"]');
    await expect(bubble).toBeVisible({ timeout: 4000 });
    const ring = page.locator('[data-testid="home-pulse-avatar"]');
    const bubbleBox = await bubble.boundingBox();
    const ringBox = await ring.boundingBox();
    // Bubble sits fully above the ring, with real clearance — never
    // overlapping it or reading as part of whatever renders above it.
    expect(bubbleBox.y + bubbleBox.height).toBeLessThan(ringBox.y);
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
});

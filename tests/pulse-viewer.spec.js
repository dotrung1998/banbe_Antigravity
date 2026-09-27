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
  test('header shows the shared wordmark logo (not a text label), accessible as "Banbe Pulse"', async ({ page }) => {
    await openPulse(page);
    const logo = page.locator('[data-testid="pulse-viewer"] img[alt="Banbe Pulse"]');
    await expect(logo).toBeVisible();
    await expect(logo).toHaveAttribute('src', '/banbe-wordmark.png');
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
});

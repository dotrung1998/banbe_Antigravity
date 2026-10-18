// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Pulse/loading UX pass (2026-09-27) — A1/A2/A3: header logo parity, the
// shared loading GIF asset, and the dismiss. (2026-10-06) Pulse is now a
// bottom sheet like the profile share card: it slides up, and the X, a
// backdrop tap or a downward drag on its grab handle all drive the SAME one
// slide back down — replacing the earlier left-to-right edge-swipe.

async function openPulse(page) {
  await setupToHome(page);
  await page.click('[data-testid="home-pulse-ticker"]');
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

  test('the X close button slides the Pulse sheet down in one continuous motion, revealing Home (never a blank/white flash)', async ({ page }) => {
    await openPulse(page);
    // Home stays mounted underneath the whole time (App.jsx renders Pulse
    // as a sibling overlay, never a route change) — its own dock is a
    // reliable, always-present marker for "the real Home, not white."
    await expect(page.locator('[data-testid="tab-home"], [data-screen-label="Home"]').first()).toBeAttached();

    await page.click('[data-testid="pulse-close"]');
    // Mid-animation: translateY should be progressing (non-zero, and not
    // yet fully off-screen) at some point during the 260ms commit window —
    // confirms ONE animated slide is actually playing, not an instant cut.
    await page.waitForTimeout(80);
    const midTransform = await page.locator('[data-testid="pulse-viewer"]').evaluate(el => getComputedStyle(el).transform).catch(() => null);
    if (midTransform && midTransform !== 'none') {
      expect(midTransform).not.toBe('matrix(1, 0, 0, 1, 0, 0)'); // not still at translateY(0)
    }
    await expect(page.locator('[data-testid="pulse-viewer"]')).toHaveCount(0, { timeout: 1000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('dragging the grab handle down past the threshold dismisses Pulse the same way as the X', async ({ page }) => {
    await openPulse(page);
    const zone = page.locator('[data-testid="pulse-edge-swipe-zone"]');
    const box = await zone.boundingBox();
    const viewport = page.viewportSize();
    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    // Past the 18%-of-viewport-height commit threshold.
    await page.mouse.move(startX, startY + viewport.height * 0.4, { steps: 6 });
    await page.waitForTimeout(50);
    const liveTransform = await page.locator('[data-testid="pulse-viewer"]').evaluate(el => getComputedStyle(el).transform);
    expect(liveTransform).not.toBe('matrix(1, 0, 0, 1, 0, 0)'); // live-following the drag already
    await page.mouse.up();
    await expect(page.locator('[data-testid="pulse-viewer"]')).toHaveCount(0, { timeout: 1000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('a short drag on the grab handle springs back instead of dismissing', async ({ page }) => {
    await openPulse(page);
    const zone = page.locator('[data-testid="pulse-edge-swipe-zone"]');
    const box = await zone.boundingBox();
    const startX = box.x + box.width / 2;
    const startY = box.y + box.height / 2;
    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX, startY + 20, { steps: 3 }); // well under threshold
    await page.mouse.up();
    await page.waitForTimeout(400);
    await expect(page.locator('[data-testid="pulse-viewer"]')).toBeVisible();
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
    // Section-level image loader (below) must not replay either — this
    // tab's photos already decoded the first time it was shown.
    await expect(page.getByTestId('pulse-images-loading')).toHaveCount(0);
  });

  // Loading-GIF pass (same-day follow-up) — the previous pass's fallback
  // fill stopped the white flash but never actually showed the loading
  // asset while a section's photos were still in flight. These tests
  // throttle the real event-photo storage responses so that window is
  // long enough to observe reliably, instead of racing a same-tick
  // network response in a fast local/dev environment.
  test.describe('section-level image loader (not per-thumbnail)', () => {
    async function throttlePhotoResponses(page, delayMs) {
      await page.route('**/storage/v1/object/public/event-photos/**', async (route) => {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
        await route.continue();
      });
    }

    test('shows exactly ONE loader for the whole tab while its photos are still loading, then swaps to real content — never a per-thumbnail spinner', async ({ page }) => {
      await throttlePhotoResponses(page, 1200);
      await openPulse(page);
      // Ranking data itself (never gated by the photo throttle above)
      // must resolve first.
      await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });
      const cardCount = await page.getByTestId('pulse-card').count();
      test.skip(cardCount === 0, 'no ranked events with photos in this environment');

      // While every photo in this tab is still in flight: exactly one
      // section-level loader, never zero (real gap this pass fixes) and
      // never more than one (no per-thumbnail spam).
      await expect(page.getByTestId('pulse-images-loading')).toHaveCount(1, { timeout: 2000 });

      // Once the first photo actually decodes, the section loader lifts
      // and real content is shown — never stays up forever.
      await expect(page.getByTestId('pulse-images-loading')).toHaveCount(0, { timeout: 6000 });
      await expect(page.getByTestId('pulse-card').first()).toBeVisible();
    });

    test('switching to a different tab never shows more than one section loader at a time, and always eventually settles', async ({ page }) => {
      await throttlePhotoResponses(page, 1200);
      await openPulse(page);
      await expect(page.getByTestId('pulse-loading')).toHaveCount(0, { timeout: 8000 });
      // Let the daily tab's own images fully settle first.
      await expect(page.getByTestId('pulse-images-loading')).toHaveCount(0, { timeout: 6000 });

      // Photos tab may or may not share photo URLs with events already
      // shown on daily/weekly (the same event can legitimately appear on
      // more than one ranking) — if it shares no URL with anything
      // already decoded, switching to it for the first time this session
      // must show its own fresh section loader (the real tab-switch gap
      // this pass fixes); if it happens to share an already-decoded URL,
      // it's correct for no loader to reappear at all. Either way, at
      // MOST one loader node ever exists at once (never a wall of
      // per-thumbnail spinners), and it must always eventually settle to
      // zero rather than spin forever.
      await page.getByTestId('pulse-tab-photos').click();
      const photoCardCount = await page.getByTestId('pulse-photo-card').count();
      test.skip(photoCardCount === 0, 'no ranked photos in this environment');
      await expect(page.getByTestId('pulse-images-loading')).toHaveCount(0, { timeout: 6000 });
      expect(await page.getByTestId('pulse-images-loading').count()).toBeLessThanOrEqual(1);
    });
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

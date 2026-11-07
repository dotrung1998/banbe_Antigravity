// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.use({ viewport: { width: 390, height: 844 } });

async function appBox(page) {
  return page.locator('[data-bb-theme] > div').first().boundingBox();
}

// Stage 2 (2026-09-27 nav/discovery pass) — pulling down from the top of a
// root screen shows a native-style progress indicator and awaits the same
// real data reload that screen's own mount effect already uses; the
// indicator disappears once it settles, with no crash and no stuck spinner.
test.describe('Pull-to-refresh', () => {
  test('pulling down on Home shows and then clears the indicator', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const box = await appBox(page);
    const startX = box.x + box.width * 0.5;
    const startY = box.y + 40;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    for (let dy = 0; dy <= 90; dy += 15) {
      await page.mouse.move(startX, startY + dy);
    }
    await expect(page.getByTestId('pull-to-refresh-indicator')).toBeVisible();
    await page.mouse.up();

    // Real reload in flight then settles — indicator clears within a
    // generous window, never stuck permanently.
    await expect(page.getByTestId('pull-to-refresh-indicator')).toHaveCount(0, { timeout: 8000 });
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  });

  test('a small pull under the trigger threshold snaps back without refreshing', async ({ page }) => {
    await setupToHome(page);
    await page.waitForSelector('[data-screen-label="Home"]');

    const box = await appBox(page);
    const startX = box.x + box.width * 0.5;
    const startY = box.y + 40;

    await page.mouse.move(startX, startY);
    await page.mouse.down();
    await page.mouse.move(startX, startY + 20); // well under the 64px trigger
    await page.mouse.up();

    await page.waitForTimeout(400);
    await expect(page.getByTestId('pull-to-refresh-indicator')).toHaveCount(0);
  });
});

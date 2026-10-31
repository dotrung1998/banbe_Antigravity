// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Note 68 — the personal profile identity card on a 6.1" phone (390×844), as a visitor (signed out, read-only guest
// browsing). banbetestadmin's real data has interests ["Admin", "Admin"]: the regression was two identical chips.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const HANDLE = 'banbetestadmin';

test.describe('Public profile — identity card (note 68)', () => {
  for (const theme of ['theme-light', 'theme-dark']) {
    test(`left-aligned compact card, one chip per interest, no wide empty bands (${theme})`, async ({ page }) => {
      await guestToHome(page, theme);
      // Client-side navigation (useUrlSync listens to popstate), so the guest session stays.
      await page.evaluate((h) => { history.pushState({}, '', `/u/${h}`); window.dispatchEvent(new PopStateEvent('popstate')); }, HANDLE);
      const card = page.getByTestId('public-profile-card');
      await expect(card).toBeVisible({ timeout: 10000 });
      await page.waitForTimeout(600);

      const box = await card.boundingBox();
      expect(box.height, 'card + stats stay compact').toBeLessThanOrEqual(220);
      expect(box.width, 'full width with a 16px gutter').toBeGreaterThanOrEqual(390 - 2 * 16 - 1);
      // Left-aligned: the name starts near the avatar, not in a centred narrow column.
      const name = await page.getByTestId('public-profile-display-name').boundingBox();
      expect(name.x - box.x).toBeLessThanOrEqual(20 + 80 + 16 + 2);
      expect(await page.getByTestId('public-profile-display-name').evaluate(el => getComputedStyle(el.parentElement).alignItems)).not.toBe('center');

      // One chip per interest (regression: "Admin", "Admin").
      await expect(page.getByText('Admin', { exact: true })).toHaveCount(1);

      // Every action is at least 44px tall.
      for (const id of ['public-profile-qr-cta', 'public-profile-share', 'public-profile-back']) {
        expect((await page.getByTestId(id).boundingBox()).height, id).toBeGreaterThanOrEqual(44);
      }
      // No vertical gap above 24px between the card, the actions and the sections below.
      const qr = await page.getByTestId('public-profile-qr-cta').boundingBox();
      expect(qr.y - (box.y + box.height)).toBeLessThanOrEqual(24);

      await page.screenshot({ path: process.env.SHOT_DIR ? `${process.env.SHOT_DIR}/public-profile-390-${theme}.png` : undefined });
    });
  }
});

// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// Calm Pass phase 4 (note 71): Reduce Transparency turns the glass opaque on web, and the round controls over an
// event's cover photo use the fixed deep clay. `prefers-reduced-transparency` is emulated through CDP, so the
// emulation tests run on Chromium only.
test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

async function reduceTransparency(page, on) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-transparency', value: on ? 'reduce' : 'no-preference' }] });
}
const style = (loc, prop) => loc.evaluate((el, p) => getComputedStyle(el)[p], prop);

test.describe('Reduce Transparency', () => {
  test.skip(({ browserName }) => browserName !== 'chromium', 'CDP media emulation');

  for (const theme of ['light', 'dark']) {
    test(`${theme}: the dock is frosted by default and opaque with the setting on`, async ({ page }) => {
      await guestToHome(page);
      await page.evaluate((t) => window.__banbeDevSet({ theme: t }), theme);
      const dock = page.getByTestId('bottom-tab-bar');
      await expect(dock).toBeVisible();
      expect(await style(dock, 'backdropFilter')).toContain('blur');
      await reduceTransparency(page, true);
      await expect.poll(() => style(dock, 'backdropFilter')).toBe('none');
      const bg = await style(dock, 'backgroundColor');
      expect(bg).toBe(theme === 'light' ? 'rgb(238, 232, 218)' : 'rgb(36, 33, 28)');   // surface-2, opaque
      await reduceTransparency(page, false);
      await expect.poll(() => style(dock, 'backdropFilter')).toContain('blur');
    });
  }
});

test('the controls over an event photo use the fixed deep clay in both themes', async ({ page }) => {
  await guestToHome(page);
  for (const theme of ['light', 'dark']) {
    await page.evaluate((t) => window.__banbeDevSet({ theme: t }), theme);
    await page.locator('[data-testid^="home-event-"]').first().click();
    const share = page.getByTestId('event-detail-share');
    await expect(share).toBeVisible();
    expect(await style(share, 'backgroundColor')).toBe('rgba(126, 69, 41, 0.9)');
    await page.getByTestId('event-detail-back').click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible();
  }
});

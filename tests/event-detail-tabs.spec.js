// @ts-check
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

// V8 tabs (note 75): the collapsed nav bar shows one tab per section with content; the lit tab follows the scroll, the
// very bottom always lights the last tab, a tapped tab stays lit while the page scrolls to it, and the collapsed top
// controls keep a 44px hit area. iOS twin: EventDetailCompactUITests.testTabsFollowTheScroll.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const scroller = (page) => page.getByTestId('event-hero-title').locator('..');
const activeTab = (page) => page.locator('[data-testid^="event-tab-"][aria-current="true"]');

test.describe('Event Detail — V8 tabs (note 75)', () => {
  test.beforeEach(async ({ page }) => {
    await guestToHome(page, 'theme-light');
    await page.click('[data-testid="home-event-bepnho"]');
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible();
    await page.waitForTimeout(900);
  });

  test('tabs appear with the nav bar and follow the scroll to the last section', async ({ page }) => {
    await expect(page.getByTestId('event-tabs')).toHaveCSS('opacity', '0');
    await scroller(page).evaluate((el) => { el.scrollTop = 600; el.dispatchEvent(new Event('scroll')); });
    await expect(page.getByTestId('event-tabs')).toHaveCSS('opacity', '1');
    // bepnho has a menu, a host, photos and is open for booking: all five tabs.
    for (const id of ['overview', 'menu', 'host', 'photos', 'safe']) await expect(page.getByTestId(`event-tab-${id}`)).toBeVisible();
    await scroller(page).evaluate((el) => { el.scrollTop = el.scrollHeight; el.dispatchEvent(new Event('scroll')); });
    await expect(activeTab(page)).toHaveAttribute('data-tab', 'safe');

    // The collapsed controls keep a 44px hit area.
    for (const id of ['event-detail-back', 'event-detail-more', 'event-detail-share', 'event-detail-save']) {
      const box = await page.getByTestId(id).boundingBox();
      expect(box.width, id).toBeGreaterThanOrEqual(44);
      expect(box.height, id).toBeGreaterThanOrEqual(44);
    }
  });

  test('a tapped tab stays lit and lands its section under the tab row; a wheel hands control back', async ({ page }) => {
    await scroller(page).evaluate((el) => { el.scrollTop = 600; el.dispatchEvent(new Event('scroll')); });
    await page.getByTestId('event-tab-host').click();
    await expect(activeTab(page)).toHaveAttribute('data-tab', 'host');
    await page.waitForTimeout(1200);
    await expect(activeTab(page)).toHaveAttribute('data-tab', 'host');
    const row = await page.getByTestId('event-tabs').boundingBox();
    const host = await page.getByTestId('event-host-section').boundingBox();
    expect(host.y).toBeGreaterThanOrEqual(row.y + row.height - 2);
    expect(host.y).toBeLessThan(row.y + row.height + 120);

    await page.mouse.move(195, 500);
    await page.mouse.wheel(0, -2000);
    await page.waitForTimeout(500);
    await expect(activeTab(page)).toHaveAttribute('data-tab', 'overview');
  });
});

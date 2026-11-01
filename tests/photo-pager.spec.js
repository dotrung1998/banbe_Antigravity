// @ts-check
// Map v6 (note 74): Home's card layout pages each event's photos sideways (src/components/PhotoPager.jsx). A swipe
// that starts on the photos moves the photos and never becomes a dock-tab switch (App.jsx honours data-hscroll).
// Runs as a guest (read-only browsing), so the shared test account's date-of-birth gate can't block it.
import { test, expect } from '@playwright/test';
import { guestToHome } from './helpers.js';

test.use({ storageState: { cookies: [], origins: [] }, viewport: { width: 390, height: 844 } });

const screens = (page) => page.locator('[data-screen-label]').evaluateAll(els => els.map(e => e.getAttribute('data-screen-label')));

async function firstMultiPhotoPager(page) {
  await guestToHome(page);
  await page.click('[data-testid="home-layout-cards"]');
  const counter = page.locator('[data-screen-label="Home"] [data-testid^="photo-pager-counter-"]').first();
  await expect(counter).toBeAttached({ timeout: 15000 });
  const id = (await counter.getAttribute('data-testid')).replace('photo-pager-counter-', '');
  const pager = page.getByTestId(`photo-pager-${id}`);
  await pager.scrollIntoViewIfNeeded();
  return { id, pager, counter };
}

test.describe('Home — photo pager on event cards', () => {
  test('the cards layout shows a pager with dots, a counter and arrows on hover', async ({ page }) => {
    const { id, pager, counter } = await firstMultiPhotoPager(page);
    await expect(counter).toHaveText(/^1\/\d+$/);
    await expect(pager).toHaveAttribute('data-index', '0');
    await pager.hover();
    await page.click(`[data-testid="photo-pager-next-${id}"]`);
    await expect(counter).toHaveText(/^2\/\d+$/);
    // The arrow moves the photos only: Home stays, the event did not open.
    expect(await screens(page)).toContain('Home');
    expect(await screens(page)).not.toContain('Event');
  });

  test('a sideways swipe on the photos moves them and never switches the dock tab', async ({ page }) => {
    const { pager, counter } = await firstMultiPhotoPager(page);
    const b = await pager.boundingBox();
    const y = b.y + b.height / 2;
    // A real pointer drag right → left, the same gesture that switches tabs anywhere else on Home.
    await page.mouse.move(b.x + b.width * 0.85, y);
    await page.mouse.down();
    for (let i = 1; i <= 12; i++) await page.mouse.move(b.x + b.width * 0.85 - i * 20, y);
    await page.mouse.up();
    await expect(counter).toHaveText(/^2\/\d+$/);
    await page.waitForTimeout(800);
    const now = await screens(page);
    expect(now).toContain('Home');
    expect(now).not.toContain('Event');
    // A sideways wheel / trackpad swipe scrolls the photos natively, again without leaving Home.
    await page.mouse.move(b.x + b.width / 2, y);
    await page.mouse.wheel(400, 0);
    await page.waitForTimeout(800);
    expect(await screens(page)).toContain('Home');
  });

  test('the list layout keeps the plain row (no pager)', async ({ page }) => {
    await guestToHome(page);
    await page.click('[data-testid="home-layout-list"]');
    await expect(page.locator('[data-screen-label="Home"] [data-testid^="home-event-"]').first()).toBeVisible();
    await expect(page.locator('[data-screen-label="Home"] [data-testid^="photo-pager-"]')).toHaveCount(0);
  });
});

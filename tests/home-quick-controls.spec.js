// @ts-check
import { test, expect } from '@playwright/test';

// Note 50 follow-up — Home's quick controls, as a signed-out visitor (guest browsing, note 49), so the shared test
// account's DOB gate does not apply:
//  - language + light/dark sit right beside the location pill, in the same plain-text style;
//  - the sort button opens a menu with ONLY the sort options (not the filter sheet);
//  - a category picked on Home is already ticked in the filter sheet and the other categories stay available;
//  - the location picker slides up over the filter sheet, and "Done" returns to it with the draft intact.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

async function openGuestHome(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); break; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(400);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
  await page.getByTestId('home-category-all').waitFor();
}

test.describe('Home quick controls', () => {
  test('language and theme sit on the location pill row and switch', async ({ page }) => {
    await openGuestHome(page);
    const area = await page.getByTestId('home-area-toggle').boundingBox();
    const lang = await page.getByTestId('home-lang-toggle').boundingBox();
    const theme = await page.getByTestId('home-theme-toggle').boundingBox();
    expect(Math.abs(area.y - lang.y)).toBeLessThan(4);
    expect(Math.abs(lang.y - theme.y)).toBeLessThan(4);
    expect(area.x).toBeLessThan(lang.x);
    expect(lang.x).toBeLessThan(theme.x);

    const before = (await page.getByTestId('home-theme-toggle').textContent()).trim();
    await page.getByTestId('home-theme-toggle').click();
    await expect(page.getByTestId('home-theme-toggle')).not.toHaveText(before);
    await page.getByTestId('home-theme-toggle').click();
    await expect(page.getByTestId('home-theme-toggle')).toHaveText(before);

    const placeholder = (await page.getByTestId('home-search-bar').textContent()).trim();
    await page.getByTestId('home-lang-toggle').click();
    await expect(page.getByTestId('home-search-bar')).not.toHaveText(placeholder);
  });

  test('sort opens a menu with only the sort options', async ({ page }) => {
    await openGuestHome(page);
    await page.getByTestId('home-sort-button').click();
    await expect(page.getByTestId('sort-menu')).toBeVisible();
    await expect(page.locator('[data-testid^="sort-menu-"][role="menuitemradio"]')).toHaveCount(4);
    await expect(page.getByTestId('home-filter-sheet')).toHaveCount(0);
    await page.getByTestId('sort-menu-price').click();
    await expect(page.getByTestId('sort-menu')).toHaveCount(0);
    await expect(page.getByTestId('home-filters-badge')).toHaveCount(0); // sort is not a filter
  });

  test('a category picked on Home is pre-selected in the filter sheet', async ({ page }) => {
    await openGuestHome(page);
    await page.getByTestId('home-category-supper').click();
    await page.getByTestId('home-filters-button').click();
    await expect(page.getByTestId('home-filter-sheet')).toBeVisible();
    await expect(page.getByTestId('home-filter-cat-supper')).toHaveAttribute('aria-pressed', 'true');
    // The sheet sees every category, not just the filtered feed: a category with events is still tappable.
    const others = page.locator('button[data-testid^="home-filter-cat-"]:not([data-testid="home-filter-cat-supper"])');
    const enabled = await others.evaluateAll(els => els.filter(e => !e.disabled).length);
    expect(enabled).toBeGreaterThan(0);
  });

  test('the location picker overlays the filter sheet and Done returns to it', async ({ page }) => {
    await openGuestHome(page);
    await page.getByTestId('home-category-supper').click();
    await page.getByTestId('home-filters-button').click();
    await page.getByTestId('home-filter-area').click();
    await expect(page.getByTestId('filter-area-sheet')).toBeVisible();
    await expect(page.getByTestId('home-filter-sheet')).toHaveCount(1); // still mounted underneath
    await page.locator('[data-testid^="area-node:"]').last().click();
    await expect(page.getByTestId('filter-area-sheet')).toBeVisible(); // a pick does not close it
    await page.getByTestId('filter-area-done').click();
    await expect(page.getByTestId('filter-area-sheet')).toHaveCount(0);
    await expect(page.getByTestId('home-filter-sheet')).toBeVisible();
    await expect(page.getByTestId('home-filter-cat-supper')).toHaveAttribute('aria-pressed', 'true'); // draft kept
  });
});

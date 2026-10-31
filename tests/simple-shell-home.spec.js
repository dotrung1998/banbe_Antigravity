// @ts-check
import { test, expect } from '@playwright/test';

// Simple Shell follow-up (note 66, plan "five fixes"): Home with the switch `simple_shell` ON, as a signed-out
// visitor (guest browsing, note 49) so the shared test account's DOB gate does not apply. The flag is mocked at the
// network edge (pattern: tests/rewards-switch.spec.js); the app code under test is the real one.
//  - Item 1: the Hosting segment is LOCKED without organizer mode (lock glyph, accessible label), a guest tap asks to
//    sign in and never shows the host Home.
//  - Item 2: the category row is back under the search bar; "Show all" opens the A-Z sheet with counts; the Filters
//    sheet no longer duplicates categories.
//  - Item 4 (guest variant): "+" > Host an event asks to sign in.
test.use({ viewport: { width: 390, height: 844 }, storageState: { cookies: [], origins: [] } });

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });

/** @param {import('@playwright/test').Page} page */
async function openGuestShellHome(page) {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json({ simple_shell: true })));
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.getByTestId('lang-en').isVisible().catch(() => false)) { await page.getByTestId('lang-en').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('onboarding-continue').isVisible().catch(() => false)) { await page.getByTestId('onboarding-continue').click(); await page.waitForTimeout(300); continue; }
    if (await page.getByTestId('welcome-explore').isVisible().catch(() => false)) { await page.getByTestId('welcome-explore').click(); break; }
    if (await page.locator('[data-screen-label="Home"]').isVisible().catch(() => false)) break;
    await page.waitForTimeout(400);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
  await expect(page.getByTestId('home-mode-switch')).toBeVisible({ timeout: 10000 });
}

test.describe('Simple Shell Home', () => {
  test('Hosting is locked without organizer mode and a guest tap asks to sign in', async ({ page }) => {
    await openGuestShellHome(page);
    const host = page.getByTestId('home-mode-host');
    await expect(host).toHaveAttribute('data-locked', 'true');
    await expect(host).toHaveAttribute('aria-label', 'Hosting, locked, double-tap to start hosting');
    await expect(host).toHaveAttribute('aria-checked', 'false');
    await expect(page.getByTestId('home-mode-goer')).toHaveAttribute('aria-checked', 'true');
    const box = await host.boundingBox();
    expect(box.height).toBeGreaterThanOrEqual(44);

    await host.click();
    await expect(page.getByTestId('guest-prompt')).toBeVisible();
    await expect(page.locator('#guest-prompt-title')).toHaveText('Host an event');
    await expect(page.getByTestId('home-host')).toHaveCount(0);
    await expect(page.getByTestId('home-host-hero')).toHaveCount(0);
    await page.getByTestId('guest-prompt-dismiss').click();
    await expect(page.getByTestId('home-mode-goer')).toHaveAttribute('aria-checked', 'true');
    await expect(page.getByTestId('home-host')).toHaveCount(0);
  });

  test('the category row is back under the search bar and Show all opens the A-Z sheet', async ({ page }) => {
    await openGuestShellHome(page);
    const row = page.getByTestId('home-category-row');
    await expect(row).toBeVisible();
    await expect(page.getByTestId('home-category-all')).toBeVisible();
    const search = await page.getByTestId('home-search-bar').boundingBox();
    const rowBox = await row.boundingBox();
    expect(rowBox.y).toBeGreaterThan(search.y);
    // Above the For You / quick chips / Filters row.
    const chips = await page.getByTestId('home-chip-row').boundingBox();
    expect(rowBox.y).toBeLessThan(chips.y);

    await page.getByTestId('home-category-show-all').click();
    const sheet = page.getByTestId('home-category-sheet');
    await expect(sheet).toBeVisible();
    const items = sheet.locator('[data-testid^="home-category-sheet-"][role="listitem"]');
    expect(await items.count()).toBeGreaterThan(0);
    // Every row says how many events it would show.
    for (const label of await items.evaluateAll(els => els.map(e => e.getAttribute('aria-label')))) expect(label).toMatch(/\d+ event/);
    await page.getByTestId('home-category-sheet-close').click();
    await expect(sheet).toHaveCount(0);

    // "All" stays selected with nothing picked: no type chips.
    await page.getByTestId('home-category-all').click();
    await expect(page.getByTestId('home-category-all')).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByTestId('home-type-chips')).toHaveCount(0);
  });

  test('the Filters sheet no longer repeats the categories (one source of truth)', async ({ page }) => {
    await openGuestShellHome(page);
    await page.getByTestId('home-filters-button').click();
    await expect(page.getByTestId('home-filter-sheet')).toBeVisible();
    await expect(page.locator('[data-testid^="home-filter-cat-"]')).toHaveCount(0);
    await expect(page.getByTestId('home-filter-sheet').getByTestId('home-category-row')).toHaveCount(0);
    await expect(page.getByTestId('home-category-row')).toHaveCount(1);
  });

  test('"+" > Host an event asks a guest to sign in first', async ({ page }) => {
    await openGuestShellHome(page);
    await page.getByTestId('dock-create-button').click();
    await expect(page.getByTestId('dock-create-menu')).toBeVisible();
    await page.getByTestId('dock-create-menu-host').click();
    await expect(page.getByTestId('dock-create-menu')).toHaveCount(0);
    await expect(page.getByTestId('guest-prompt')).toBeVisible();
    await expect(page.locator('#guest-prompt-title')).toHaveText('Host an event');
    await expect(page.getByTestId('start-hosting-sheet')).toHaveCount(0);
  });
});

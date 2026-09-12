// @ts-check
/// <reference types="@playwright/test" />

/**
 * Clears banbe.preferences from localStorage and reloads so the app
 * starts fresh at the splash screen.
 * @param {import('@playwright/test').Page} page
 */
export async function resetStorage(page) {
  await page.goto('/');
  await page.evaluate(() => localStorage.removeItem('banbe.preferences'));
  await page.reload();
}

/**
 * Navigates through onboarding (if shown) and lands on the Home screen.
 * Always picks Tiếng Việt + light theme for a predictable language baseline.
 * @param {import('@playwright/test').Page} page
 */
export async function setupToHome(page) {
  await resetStorage(page);

  // Splash. The click only skips the wait — the splash advances on its own
  // anyway, so it can detach between the visibility check and the click
  // landing. Playwright treats that as "element detached, retrying" and
  // burns the whole timeout in beforeEach, failing tests that never got
  // near their subject. Losing the click is the outcome it was after.
  const splash = page.locator('[data-screen-label="Splash"]');
  if (await splash.isVisible({ timeout: 3000 }).catch(() => false)) {
    await splash.click({ timeout: 2000 }).catch(() => {});
  }

  // Language
  const langScreen = page.locator('[data-screen-label="Language"]');
  if (await langScreen.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByText('Tiếng Việt', { exact: true }).click();
  }

  // Appearance (Vietnamese) — continue with default light theme
  const themeScreen = page.locator('[data-screen-label="Appearance"]');
  if (await themeScreen.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByText('Tiếp tục', { exact: true }).click();
  }

  // Wait for Home (page.waitForSelector works outside test context, no expect needed)
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 5000 });
}

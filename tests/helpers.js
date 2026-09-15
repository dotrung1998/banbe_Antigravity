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

  // playwright.config.js's shared storageState (tests/global-setup.js —
  // Task 1, mandatory login) means the browser is already signed in as a
  // real, persistent test account before the page even loads. Once that
  // account's own profile.prefs_saved is true (set the first time any test
  // run ever clicked through language/theme for it), GocContext's syncUser()
  // jumps straight from splash/langPick/themePick to 'home' entirely on its
  // own the moment the session resolves — which can happen mid-click here,
  // not just between the visibility check and the click landing. Every
  // click below is wrapped the same defensive way the splash click already
  // was: losing a click to a screen that's already moved on is exactly the
  // outcome being raced for, not a real failure.
  const splash = page.locator('[data-screen-label="Splash"]');
  if (await splash.isVisible({ timeout: 3000 }).catch(() => false)) {
    await splash.click({ timeout: 2000 }).catch(() => {});
  }

  // Language
  const langScreen = page.locator('[data-screen-label="Language"]');
  if (await langScreen.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByText('Tiếng Việt', { exact: true }).click({ timeout: 2000 }).catch(() => {});
  }

  // Appearance (Vietnamese) — continue with default light theme
  const themeScreen = page.locator('[data-screen-label="Appearance"]');
  if (await themeScreen.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByText('Tiếp tục', { exact: true }).click({ timeout: 2000 }).catch(() => {});
  }

  // Wait for Home (page.waitForSelector works outside test context, no expect needed)
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
}

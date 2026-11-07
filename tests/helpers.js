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
 * Waits for the current data-screen-label to become one of the given names,
 * without the false immediacy of Locator.isVisible({ timeout }) — that
 * option is deprecated and ignored by Playwright (isVisible never waits,
 * it checks the DOM instantly), which made every call site here race
 * React's render instead of actually waiting for it. This polls the real
 * attribute via a proper auto-retrying expect-less wait.
 * @param {import('@playwright/test').Page} page
 * @param {string[]} names
 * @param {number} timeout
 * @returns {Promise<string | null>} the matched name, or null on timeout
 */
async function waitForAnyScreen(page, names, timeout) {
  const selector = names.map((n) => `[data-screen-label="${n}"]`).join(', ');
  try {
    const handle = await page.waitForSelector(selector, { timeout });
    return await handle.getAttribute('data-screen-label');
  } catch {
    return null;
  }
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
  // account's own profile.prefs_saved is true (set once in global-setup),
  // BanBeContext's syncUser() jumps straight from splash/langPick/themePick to
  // 'home' entirely on its own the moment the session resolves — often
  // before the splash timer even fires, so Language/Appearance may never
  // appear at all. Each step below actually waits for its own screen (or
  // for Home to have already arrived instead) rather than probing an
  // instant, non-waiting isVisible() snapshot — racing that produced clicks
  // landing on whatever screen was live at the wrong moment.
  let current = await waitForAnyScreen(page, ['Splash', 'Language', 'Appearance', 'Home'], 5000);

  if (current === 'Splash') {
    await page.locator('[data-screen-label="Splash"]').click({ timeout: 2000 }).catch(() => {});
    current = await waitForAnyScreen(page, ['Language', 'Appearance', 'Home'], 4000);
  }

  if (current === 'Language') {
    const langScreen = page.locator('[data-screen-label="Language"]');
    await langScreen.getByText('Tiếng Việt', { exact: true }).click({ timeout: 2000 }).catch(() => {});
    current = await waitForAnyScreen(page, ['Appearance', 'Home'], 4000);
  }

  if (current === 'Appearance') {
    const themeScreen = page.locator('[data-screen-label="Appearance"]');
    await themeScreen.getByText('Tiếp tục', { exact: true }).click({ timeout: 2000 }).catch(() => {});
  }

  // Wait for Home (page.waitForSelector works outside test context, no expect needed)
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
}

/**
 * Note 68 — reach Home signed OUT (read-only guest browsing, note 49): Splash → Language (English) → Appearance
 * (`theme`) → Welcome "Explore". For layout specs that must not depend on the shared signed-in test account, which the
 * DOB account gate currently holds. Use with `test.use({ storageState: { cookies: [], origins: [] } })`.
 * @param {import('@playwright/test').Page} page
 * @param {'theme-light'|'theme-dark'} theme
 */
export async function guestToHome(page, theme = 'theme-light') {
  await page.goto('/');
  for (let i = 0; i < 10; i++) {
    const sc = await page.locator('[data-screen-label]').evaluateAll(els => els.map(e => e.getAttribute('data-screen-label')));
    if (sc.includes('Home')) return;
    if (sc.includes('Splash')) await page.locator('[data-screen-label="Splash"]').click().catch(() => {});
    else if (sc.includes('Language')) await page.getByTestId('lang-en').click().catch(() => {});
    else if (sc.includes('Appearance')) { await page.getByTestId(theme).click().catch(() => {}); await page.getByTestId('onboarding-continue').click().catch(() => {}); }
    else if (sc.includes('Welcome')) await page.getByTestId('welcome-explore').click().catch(() => {});
    await page.waitForTimeout(1200);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 8000 });
}

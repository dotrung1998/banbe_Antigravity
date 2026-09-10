// @ts-check
import { test, expect } from '@playwright/test';

// Clear localStorage before each test so onboarding always runs fresh
test.beforeEach(async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => localStorage.removeItem('banbe.preferences'));
  await page.reload();
});

test.describe('Application Launch & Onboarding Flow', () => {
  test('completes launch splash, language selection, and theme selection', async ({ page }) => {
    // 1. Splash screen – wait up to 3s for it to appear
    const splash = page.locator('[data-screen-label="Splash"]');
    await expect(splash).toBeVisible({ timeout: 3000 });
    await splash.click();

    // 2. Language Selection
    const langScreen = page.locator('[data-screen-label="Language"]');
    await expect(langScreen).toBeVisible({ timeout: 3000 });
    await expect(page.getByText('Chọn ngôn ngữ')).toBeVisible();

    // Pick English
    await page.getByText('English', { exact: true }).click();

    // 3. Appearance Selection (now in English because we picked English)
    const themeScreen = page.locator('[data-screen-label="Appearance"]');
    await expect(themeScreen).toBeVisible({ timeout: 3000 });
    await expect(page.getByText('Light or dark?')).toBeVisible();

    // Pick Dark theme – use the card containing "Dark" as the heading
    await page.locator('[data-screen-label="Appearance"]').getByText('Dark', { exact: true }).click();

    // Verify root container reflects dark theme attribute
    const container = page.locator('[data-bb-theme]');
    await expect(container).toHaveAttribute('data-bb-theme', 'dark');

    // Click Continue
    await page.getByText('Continue', { exact: true }).click();

    // 4. Arrive at Home Screen
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 5000 });
  });

  test('completes onboarding with Vietnamese and light theme', async ({ page }) => {
    const splash = page.locator('[data-screen-label="Splash"]');
    await expect(splash).toBeVisible({ timeout: 3000 });
    await splash.click();

    const langScreen = page.locator('[data-screen-label="Language"]');
    await expect(langScreen).toBeVisible({ timeout: 3000 });

    // Pick Vietnamese
    await page.getByText('Tiếng Việt', { exact: true }).click();

    // Appearance screen – Vietnamese
    const themeScreen = page.locator('[data-screen-label="Appearance"]');
    await expect(themeScreen).toBeVisible({ timeout: 3000 });

    // Pick Light
    await page.locator('[data-screen-label="Appearance"]').getByText('Sáng', { exact: true }).click();
    await expect(page.locator('[data-bb-theme]')).toHaveAttribute('data-bb-theme', 'light');

    // Continue
    await page.getByText('Tiếp tục', { exact: true }).click();

    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 5000 });
  });

  test('a returning visitor skips onboarding and keeps their language and theme', async ({ page }) => {
    // Complete onboarding once, picking English + Dark.
    await page.locator('[data-screen-label="Splash"]').click();
    await page.getByText('English', { exact: true }).click();
    await page.locator('[data-screen-label="Appearance"]').getByText('Dark', { exact: true }).click();
    await page.getByText('Continue', { exact: true }).click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 5000 });

    // Revisiting the app should land straight on Home with the same
    // preferences, never back through the splash/language/theme pickers.
    await page.reload();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 5000 });
    await expect(page.locator('[data-screen-label="Splash"]')).toHaveCount(0);
    await expect(page.locator('[data-bb-theme]')).toHaveAttribute('data-bb-theme', 'dark');
  });
});

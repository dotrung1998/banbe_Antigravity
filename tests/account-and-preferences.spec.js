// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Account & Preferences Screen', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('navigates to Account screen and opens Preferences', async ({ page }) => {
    // "Tài khoản" is the account link on Home (Vietnamese baseline)
    await page.getByText('Tài khoản').first().click();

    // Verify Account screen
    const accountScreen = page.locator('[data-screen-label="Account"]');
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    // Click "Ngôn ngữ & hiển thị" to open Preferences
    await page.getByText('Ngôn ngữ & hiển thị').click();

    // Verify Preferences screen
    const prefScreen = page.locator('[data-screen-label="Preferences"]');
    await expect(prefScreen).toBeVisible({ timeout: 3000 });

    // Switch language to English
    await prefScreen.getByText('English', { exact: true }).click();
    // Page heading should now appear in English
    await expect(page.getByText('Language & appearance')).toBeVisible({ timeout: 2000 });

    // Switch theme to Dark (now in English, scoped to Preferences screen)
    await prefScreen.getByText('Dark', { exact: true }).click();
    await expect(page.locator('[data-bb-theme]')).toHaveAttribute('data-bb-theme', 'dark');

    // Back button reads "‹ Account" (English, since we switched to English)
    await page.getByText('‹ Account').click();
    await expect(accountScreen).toBeVisible({ timeout: 3000 });
  });

  test('shows an organizer mode toggle instead of an organizer sign-up', async ({ page }) => {
    await page.getByText('Tài khoản').first().click();
    const accountScreen = page.locator('[data-screen-label="Account"]');
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    const toggle = accountScreen.getByTestId('organizer-mode-toggle');
    await expect(toggle).toBeVisible();
    await expect(toggle).toContainText('Chế độ tổ chức');

    // A guest has nothing to toggle yet, so the switch sends them to Login.
    await toggle.click();
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 3000 });
  });

  test('can return from Account to Home', async ({ page }) => {
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 3000 });

    // "Xong" button on Account returns to Home
    await page.getByText('Xong').click();
    await expect(page.locator('[data-screen-label="Home"]')).toBeVisible({ timeout: 3000 });
  });
});

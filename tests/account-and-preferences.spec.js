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

  test('Security opens from Account and offers a password form', async ({ page }) => {
    await page.getByText('Tài khoản').first().click();
    const accountScreen = page.locator('[data-screen-label="Account"]');
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    await accountScreen.getByTestId('account-security').click();
    const securityScreen = page.locator('[data-screen-label="Security"]');
    await expect(securityScreen).toBeVisible({ timeout: 3000 });

    // Signed out there's nothing to set a password on yet, so the form
    // must not render an empty/broken version of itself.
    await expect(securityScreen.getByText('Đăng nhập để đặt mật khẩu cho tài khoản.')).toBeVisible();
    await expect(securityScreen.locator('input[type="password"]')).toHaveCount(0);

    // One tap back returns to Account, not Home.
    await securityScreen.getByText('‹ Tài khoản').click();
    await expect(accountScreen).toBeVisible({ timeout: 3000 });
  });

  // An event opened from one of those lists returns to it — but the back
  // pill used to fall through to its "banbe" default and claim it went
  // Home, while actually (and correctly) going back to the list.
  test('an event opened from a list has a back pill naming that list', async ({ page }) => {
    // Saved is the one a signed-out guest can actually put an event into.
    await page.locator('[data-screen-label="Home"]').getByText('Lưu', { exact: true }).first().click();
    await page.getByText('Tài khoản').first().click();
    const accountScreen = page.locator('[data-screen-label="Account"]');
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    await accountScreen.getByTestId('account-saved-card').click();
    const savedScreen = page.locator('[data-screen-label="Saved"]');
    await expect(savedScreen).toBeVisible({ timeout: 3000 });

    await savedScreen.locator('[style*="cursor: pointer"]').filter({ hasText: /./ }).nth(1).click();
    const eventScreen = page.locator('[data-screen-label="Event"]');
    await expect(eventScreen).toBeVisible({ timeout: 3000 });

    // Names the list, not "banbe" — and following it goes there.
    await expect(eventScreen.getByText('‹ banbe')).toHaveCount(0);
    await expect(eventScreen.getByText('‹ Đã lưu')).toBeVisible();
    await eventScreen.getByText('‹ Đã lưu').click();
    await expect(savedScreen).toBeVisible({ timeout: 3000 });
  });

  // "Going"/"Saved" used to be inert stat cards; they now open their own
  // list view and — the point of the fix — a single tap back lands on
  // Account again, not Home.
  test('"Going" and "Saved" open their own list, and back returns to Account', async ({ page }) => {
    await page.getByText('Tài khoản').first().click();
    const accountScreen = page.locator('[data-screen-label="Account"]');
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    await accountScreen.getByTestId('account-going-card').click();
    await expect(page.locator('[data-screen-label="Going"]')).toBeVisible({ timeout: 3000 });
    await page.getByTestId('event-list-back').click();
    await expect(accountScreen).toBeVisible({ timeout: 3000 });

    await accountScreen.getByTestId('account-saved-card').click();
    await expect(page.locator('[data-screen-label="Saved"]')).toBeVisible({ timeout: 3000 });
    await page.getByTestId('event-list-back').click();
    await expect(accountScreen).toBeVisible({ timeout: 3000 });
  });
});

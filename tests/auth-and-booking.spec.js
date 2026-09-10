// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Authentication & Booking Flows', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('navigates to Login screen and switches between log in and sign up', async ({ page }) => {
    // Tap "Tài khoản" to open Account screen
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 3000 });

    // Tap "Đăng nhập để lưu sự kiện và nhắn tin"
    await page.getByText('Đăng nhập để lưu sự kiện và nhắn tin').click();

    // Verify Login screen
    const loginScreen = page.locator('[data-screen-label="Login"]');
    await expect(loginScreen).toBeVisible({ timeout: 3000 });

    // Log in is the default tab, and there is no account type to pick:
    // organizer mode is a toggle on the account, not a kind of account.
    await expect(page.getByText('Chào mừng trở lại')).toBeVisible();
    await expect(loginScreen.getByText('Quản trị viên', { exact: true })).toHaveCount(0);
    await expect(loginScreen.getByText('Người tổ chức', { exact: true })).toHaveCount(0);

    await page.getByText('Đăng ký', { exact: true }).click();
    await expect(page.getByText('Tạo tài khoản banbe')).toBeVisible();

    await page.getByText('Đăng nhập', { exact: true }).click();
    await expect(page.getByText('Chào mừng trở lại')).toBeVisible();

    // Verify email input exists and can be filled
    const emailInput = page.locator('input[type="email"], input[placeholder="ban@email.com"]');
    await expect(emailInput.first()).toBeVisible();
    await emailInput.first().fill('testuser@example.com');
  });

  test('prompts login when reserving tickets while unauthenticated', async ({ page }) => {
    // Click on "Bếp Nhỏ №12" event card
    await page.getByText('Bếp Nhỏ №12').first().click();

    // EventDetail screen uses data-screen-label="Event"
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 3000 });

    // Click the reserve/waitlist bar at the bottom (contains "Giữ chỗ")
    await page.locator('[data-screen-label="Event"]').getByText(/Giữ chỗ/).click();

    // Unauthenticated users are redirected to Login
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 3000 });
  });
});

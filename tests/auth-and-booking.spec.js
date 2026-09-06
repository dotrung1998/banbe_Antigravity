// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Authentication & Booking Flows', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('navigates to Login screen and switches account types', async ({ page }) => {
    // Tap "Tài khoản" to open Account screen
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 3000 });

    // Tap "Đăng nhập để lưu sự kiện và nhắn tin"
    await page.getByText('Đăng nhập để lưu sự kiện và nhắn tin').click();

    // Verify Login screen
    const loginScreen = page.locator('[data-screen-label="Login"]');
    await expect(loginScreen).toBeVisible({ timeout: 3000 });

    // The h2 shows "Tiếp tục với tư cách người tham gia" by default (participant)
    await expect(page.getByText('Tiếp tục với tư cách người tham gia')).toBeVisible();

    // Switch to Organizer
    await page.getByText('Người tổ chức', { exact: true }).click();
    await expect(page.getByText('Tiếp tục với tư cách người tổ chức')).toBeVisible();

    // Switch to Admin
    await page.getByText('Quản trị viên', { exact: true }).click();
    await expect(page.getByText('Tiếp tục với tư cách quản trị viên')).toBeVisible();

    // Switch back to Participant
    await page.getByText('Người tham gia', { exact: true }).click();
    await expect(page.getByText('Tiếp tục với tư cách người tham gia')).toBeVisible();

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

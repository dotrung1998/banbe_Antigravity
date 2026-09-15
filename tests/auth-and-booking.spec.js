// @ts-check
import { test, expect } from '@playwright/test';

// Task 1 (mandatory login, 2026-09-18) means neither test in this file can
// start from an authenticated Home the way most of the suite now does: both
// are specifically about the unauthenticated experience, which the shared,
// already-signed-in storageState (tests/global-setup.js) would short-circuit
// entirely — so this file opts out of it. Home/Event/Reserve are no longer
// reachable while signed out at all (the blanket guard in GocContext.jsx
// routes any non-guest-allowed screen straight to Login), so "browse
// anonymously, then get redirected only once you try to reserve" is no
// longer a real flow to test; a signed-out visitor lands on Login as soon
// as onboarding finishes, before ever seeing Home or an event card.
test.describe('Authentication & Booking Flows', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => localStorage.removeItem('banbe.preferences'));
    await page.reload();

    const splash = page.locator('[data-screen-label="Splash"]');
    await expect(splash).toBeVisible({ timeout: 3000 });
    await splash.click();
    await page.getByText('Tiếng Việt', { exact: true }).click();
    await page.locator('[data-screen-label="Appearance"]').getByText('Sáng', { exact: true }).click();
    await page.getByText('Tiếp tục', { exact: true }).click();

    // A signed-out visitor lands on Login directly — there is no Home to
    // browse first.
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 5000 });
  });

  test('lands on Login screen and switches between log in and sign up', async ({ page }) => {
    const loginScreen = page.locator('[data-screen-label="Login"]');

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
});

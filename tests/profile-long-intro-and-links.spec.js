// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Organizer Team pass (2026-09-27, Stage 3) — long intro + optional social
// links, personal profile. Server-side validation (sanitize_social_links,
// migration 102) was already verified via direct RPC calls during
// implementation; this covers the real UI: the "Thêm liên kết" reveal,
// saving, the public "Đọc thêm" preview, and that a rejected (invalid)
// link surfaces a real error instead of silently saving.
test.describe('Personal profile — long intro + social links (Stage 3)', () => {
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ intro_long: '', social_links: [] }).eq('id', data.auth_user_id);
  });

  test('save a long intro + a valid link, see both on the public profile with Đọc thêm', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-edit-profile').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });
    await page.getByTestId('public-profile-edit-personal').click();
    await expect(page.locator('[data-screen-label="Edit profile"]')).toBeVisible({ timeout: 5000 });

    const longText = 'Lorem ipsum dolor sit amet. '.repeat(20); // > 160 chars
    await page.getByTestId('edit-profile-intro-long').fill(longText);
    await page.getByTestId('edit-profile-link-toggle').click();
    await page.getByTestId('edit-profile-link-add').click();
    await page.getByTestId('edit-profile-link-platform-0').selectOption('website');
    await page.getByTestId('edit-profile-link-url-0').fill('https://banbe.app');
    await page.getByTestId('edit-profile-save').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });

    await page.getByTestId('account-edit-profile').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });

    await expect(page.getByTestId('long-intro-preview')).toBeVisible();
    await expect(page.getByTestId('long-intro-toggle')).toHaveText(/Đọc thêm|Read more/);
    await page.getByTestId('long-intro-toggle').click();
    await expect(page.getByTestId('long-intro-toggle')).toHaveText(/Thu gọn|Show less/);
    const link = page.getByTestId('social-link-website');
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute('href', 'https://banbe.app');
  });

  test('an invalid link (javascript:) is rejected server-side, never saved or rendered', async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-edit-profile').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });
    await page.getByTestId('public-profile-edit-personal').click();
    await expect(page.locator('[data-screen-label="Edit profile"]')).toBeVisible({ timeout: 5000 });

    await page.getByTestId('edit-profile-link-toggle').click();
    await page.getByTestId('edit-profile-link-add').click();
    await page.getByTestId('edit-profile-link-platform-0').selectOption('website');
    await page.getByTestId('edit-profile-link-url-0').fill('javascript:alert(1)');
    await page.getByTestId('edit-profile-save').click();

    // Stays on Edit profile with a real error — never silently "succeeds."
    await expect(page.locator('[data-screen-label="Edit profile"]')).toBeVisible();
    await expect(page.locator('text=/không hợp lệ|is invalid/')).toBeVisible({ timeout: 5000 });
  });
});

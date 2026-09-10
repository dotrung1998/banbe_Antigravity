// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Area picker & location sharing', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('an area\'s event count excludes invite-only events not shown in its feed', async ({ page }) => {
    await page.getByText(/banbe ▪︎ Sài Gòn/).click();
    const sheet = page.getByText('Khu vực').locator('..');

    // Bình Thạnh has two demo events (bepnho, banrieng), but banrieng is
    // invite-only and never appears in the actual browsable feed — so the
    // count must say 1, not 2.
    const row = sheet.locator('div', { hasText: 'Bình Thạnh' }).last();
    await expect(row.getByText('1 sự kiện')).toBeVisible();
  });

  test('location sharing can be turned on and back off from the area sheet', async ({ page, context }) => {
    await context.grantPermissions(['geolocation']);
    await context.setGeolocation({ latitude: 10.8, longitude: 106.7 });

    await page.getByText(/banbe ▪︎ Sài Gòn/).click();
    await expect(page.getByText('Dùng vị trí của tôi để xem khoảng cách')).toBeVisible();

    // Granting location closes the sheet (its existing behavior) — reopen it
    // to see the toggle's new state.
    await page.getByText('Dùng vị trí của tôi để xem khoảng cách').click();
    await page.getByText(/banbe ▪︎ Sài Gòn/).click();
    await expect(page.getByText('Tắt vị trí ▪︎ đang hiển thị khoảng cách')).toBeVisible({ timeout: 3000 });

    // Turning it back off does not close the sheet (only granting does), so
    // the updated label is visible immediately.
    await page.getByText('Tắt vị trí ▪︎ đang hiển thị khoảng cách').click();
    await expect(page.getByText('Dùng vị trí của tôi để xem khoảng cách')).toBeVisible({ timeout: 3000 });
  });
});

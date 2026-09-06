// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Navigation & Event Exploration', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  test('displays Home screen feed and allows event detail navigation', async ({ page }) => {
    const homeScreen = page.locator('[data-screen-label="Home"]');
    await expect(homeScreen).toBeVisible();

    // Click on "Bếp Nhỏ №12" event card in the main feed
    const eventCard = page.getByText('Bếp Nhỏ №12').first();
    await expect(eventCard).toBeVisible();
    await eventCard.click();

    // EventDetail screen has data-screen-label="Event" (not "EventDetail")
    const detailScreen = page.locator('[data-screen-label="Event"]');
    await expect(detailScreen).toBeVisible({ timeout: 3000 });
    await expect(page.getByText('Bếp Nhỏ №12').first()).toBeVisible();

    // Verify "Giữ chỗ" (Reserve) button is present
    await expect(page.getByText(/Giữ chỗ/).first()).toBeVisible();

    // Click back to Home – back button says "‹ banbe"
    await page.getByText('‹ banbe').first().click();
    await expect(homeScreen).toBeVisible({ timeout: 3000 });
  });

  test('filters events by category on Home screen', async ({ page }) => {
    // Click the "Thời trang" category filter
    const fashionFilter = page.getByText('Thời trang', { exact: true });
    await expect(fashionFilter).toBeVisible();
    await fashionFilter.click();

    // ORBIT: Afterlight is a fashion-category event
    await expect(page.getByText('ORBIT: Afterlight').first()).toBeVisible({ timeout: 3000 });
  });

  test('navigates to organizer profile from event detail', async ({ page }) => {
    // Open any event
    await page.getByText('Bếp Nhỏ №12').first().click();
    await expect(page.locator('[data-screen-label="Event"]')).toBeVisible({ timeout: 3000 });

    // Click the "Ghé … ›" organizer row
    const organizerLink = page.getByText(/Ghé.*›/).first();
    await expect(organizerLink).toBeVisible();
    await organizerLink.click();

    await expect(page.locator('[data-screen-label="Organizer"]')).toBeVisible({ timeout: 3000 });
  });
});

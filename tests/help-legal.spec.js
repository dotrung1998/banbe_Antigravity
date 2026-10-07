// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Help & Legal', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-help-legal').click();
  });

  test('lists Terms, guides and Q&A (no admin guide for non-admins)', async ({ page }) => {
    await expect(page.getByTestId('help-terms')).toBeVisible();
    await expect(page.getByTestId('help-guide-personal')).toBeVisible();
    await expect(page.getByTestId('help-guide-host')).toBeVisible();
    await expect(page.getByTestId('help-faq')).toBeVisible();
    await expect(page.getByTestId('help-guide-admin')).toHaveCount(0);
  });

  test('Terms opens the policy and returns to Help & Legal', async ({ page }) => {
    await page.getByTestId('help-terms').click();
    await expect(page.locator('[data-screen-label="Policy"]')).toBeVisible();
    await page.getByText('‹ Quay lại / Back').click();
    await expect(page.getByTestId('help-terms')).toBeVisible();
  });

  test('guide has a working TOC, search and jump buttons', async ({ page }) => {
    await page.getByTestId('help-guide-personal').click();
    await expect(page.getByTestId('guide-personal-toc')).toBeVisible();
    await page.getByTestId('guide-personal-toc-refund').click();
    await page.getByTestId('guide-personal-to-bottom').click();
    await page.getByTestId('guide-personal-to-top').click();
    await page.getByTestId('guide-personal-search').fill('hoan tien');
    await expect(page.getByTestId('guide-personal-result-count')).toBeVisible();
    await page.getByTestId('guide-personal-search').fill('zzzzqqq');
    await expect(page.getByTestId('guide-personal-toc')).toHaveCount(0);
  });

  test('Q&A opens and filters', async ({ page }) => {
    await page.getByTestId('help-faq').click();
    await page.getByTestId('faq-search').fill('apple wallet');
    await expect(page.getByTestId('faq-result-count')).toBeVisible();
    await page.getByTestId('faq-back').click();
    await expect(page.getByTestId('help-faq')).toBeVisible();
  });
});

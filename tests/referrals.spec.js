// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

// Redeeming a code needs a real signed-in session (the RPC runs as
// `authenticated`, not `anon`), so that half is validated directly against
// Postgres rather than through the browser — see the migration's own tests.
// What's covered here is the part that runs before any of that: capturing
// "?ref=CODE" off the URL into localStorage and cleaning the URL up, plus
// making sure a signed-out guest — who has no referral code of their own
// yet — doesn't see an invite card with nothing behind it.
test.describe('Referral link capture', () => {
  test('stores a "?ref=" code from the URL and strips it from the address bar', async ({ page }) => {
    await page.goto('/?ref=ABCD123');
    await page.waitForFunction(() => localStorage.getItem('banbe.pendingReferral') === 'ABCD123');

    // The query string is gone from what the user actually sees/could share.
    await expect(page).toHaveURL(/^[^?]*$/);
  });

  test('uppercases a lowercase referral code', async ({ page }) => {
    await page.goto('/?ref=abcd123');
    await page.waitForFunction(() => localStorage.getItem('banbe.pendingReferral') === 'ABCD123');
  });

  test('ignores an implausible ref value rather than storing it', async ({ page }) => {
    await page.goto('/?ref=' + encodeURIComponent('<script>alert(1)</script>'));
    await page.waitForTimeout(300);
    const stored = await page.evaluate(() => localStorage.getItem('banbe.pendingReferral'));
    expect(stored).toBeNull();
  });

  // Task 1 (mandatory login, 2026-09-18) means Account is no longer
  // reachable while signed out at all, so the "guest sees no invite card"
  // case this used to check can no longer happen — a signed-in user (the
  // only kind Account ever renders for now) always has a referral code,
  // so the card renders instead.
  test('a signed-in account has an invite-friends card with its own referral code', async ({ page }) => {
    await setupToHome(page);
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 3000 });

    await expect(page.getByText('Mời bạn bè')).toBeVisible();
  });
});

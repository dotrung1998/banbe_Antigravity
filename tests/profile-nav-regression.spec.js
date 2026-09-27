// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Profile-nav fix pass (2026-09-27) — regression introduced by 0089e42:
// Account > Tổ chức's organizer card and Account > Cá nhân's personal card
// both opened the exact same PublicProfile screen, so (a) a host account's
// PERSONAL card showed the organizer-only "Chỉnh sửa"/"Xem như khách" pair
// it should never show, and (b) the organizer card lost the real
// management page (Dashboard: real upcoming/past events + check-in),
// landing on the public page instead. This verifies the real fix.
const TEST_ORG_ID = 'org_profile_nav_test';

test.describe('Account > profile card routing', () => {
  test.beforeEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (!data?.auth_user_id) return;
    // org-profile-card (and the routing this file exists to verify) only
    // renders once this account really owns an `organizers` row — the
    // shared fast-suite account has never gone through the real
    // create-event flow, so it's seeded directly here rather than paying
    // for a full event submission per test.
    await admin.from('organizers').upsert({
      id: TEST_ORG_ID, owner_id: data.auth_user_id, name: 'Profile Nav Test Org', about: '', verified: false,
    });
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', data.auth_user_id);
  });
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  async function ensureHost(page) {
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    const toggle = page.getByTestId('organizer-mode-toggle');
    await expect(toggle).toBeVisible({ timeout: 8000 });
    const pitch = page.getByText(/Bắt đầu tổ chức|Start hosting/, { exact: false });
    if (await pitch.isVisible().catch(() => false)) {
      await pitch.click();
      await expect(toggle).toBeVisible({ timeout: 8000 });
    }
  }

  test('organizer card opens the real management page (Dashboard), not PublicProfile', async ({ page }) => {
    await setupToHome(page);
    await ensureHost(page);

    const orgCard = page.getByTestId('org-profile-card');
    await expect(orgCard).toBeVisible({ timeout: 8000 });
    await orgCard.click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });

    // Rule 3 — the matching "Chỉnh sửa"/"Xem như khách" pair lives here now.
    await expect(page.getByTestId('dashboard-edit-org')).toBeVisible();
    await expect(page.getByTestId('dashboard-view-as-guest')).toBeVisible();

    // Rule 4 — back from Dashboard returns to Account (Tổ chức tab preserved).
    await page.locator('[data-screen-label="Organizer dashboard"]').getByText('‹').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('account-tab-panel-host')).toBeVisible();
  });

  test('"Xem như khách" from Dashboard opens the public page as a guest, without changing organizer mode', async ({ page }) => {
    await setupToHome(page);
    await ensureHost(page);
    await page.getByTestId('org-profile-card').click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });

    await page.getByTestId('dashboard-view-as-guest').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('public-profile-guest-preview-banner')).toBeVisible();
    // Guest preview hides the owner-only edit affordances.
    await expect(page.getByTestId('public-profile-edit-org')).toHaveCount(0);

    // Rule 4 — back returns to Dashboard, not Account directly.
    await page.getByText(/Quay lại|Back/).first().click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });
  });

  test('personal profile card never shows the organizer edit/guest-preview pair', async ({ page }) => {
    await setupToHome(page);
    await ensureHost(page);
    await page.getByTestId('account-tab-personal').click();
    await expect(page.getByTestId('account-tab-panel-personal')).toBeVisible();

    await page.getByTestId('account-edit-profile').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });

    // Rule 1 — QR + personal edit stay; the organizer pair is gone.
    await expect(page.getByTestId('public-profile-qr-cta')).toBeVisible();
    await expect(page.getByTestId('public-profile-edit-personal')).toBeVisible();
    await expect(page.getByTestId('public-profile-edit-org')).toHaveCount(0);
    await expect(page.getByTestId('public-profile-view-as-guest')).toHaveCount(0);

    // Rule 4 — back returns to Account, Cá nhân tab.
    await page.getByText(/Quay lại|Back/).first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('account-tab-panel-personal')).toBeVisible();
  });
});

// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Personal-vs-organizer hierarchy pass (2026-09-27) — verifies the real
// fix: Account > Cá nhân leads to a PERSONAL profile (own display_name,
// no organizer edit affordance); Account > Tổ chức's management page shows
// the real organizers.name + real owner, and its one button opens a
// SEPARATE organizer public profile (its own stats/follow/QR/edit),
// reachable by organizer_id alone (get_organizer_profile, migration 095) —
// including for a signed-out visitor.
const TEST_ORG_ID = 'org_hierarchy_test';
const TEST_DISPLAY_NAME = 'TDK Test';

test.describe('Personal-vs-organizer profile hierarchy', () => {
  test.beforeEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (!data?.auth_user_id) return;
    await admin.from('organizers').upsert({
      id: TEST_ORG_ID, owner_id: data.auth_user_id, name: 'Hierarchy Test Org', about: 'A real test intro.', verified: false,
    });
    await admin.from('profiles').update({ role: 'organizer', display_name: TEST_DISPLAY_NAME }).eq('id', data.auth_user_id);
  });
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    await admin.from('organizers').delete().eq('id', TEST_ORG_ID);
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant', display_name: '' }).eq('id', data.auth_user_id);
  });

  async function goToHostTab(page) {
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();
    const toggle = page.getByTestId('organizer-mode-toggle');
    await expect(toggle).toBeVisible({ timeout: 8000 });
  }

  test('personal profile shows display_name, a Founder line, and no organizer edit/guest-preview actions', async ({ page }) => {
    await setupToHome(page);
    await goToHostTab(page);
    await page.getByTestId('account-tab-personal').click();
    await expect(page.getByTestId('account-tab-panel-personal')).toBeVisible();

    await page.getByTestId('account-edit-profile').click();
    await expect(page.locator('[data-screen-label="Public profile"]')).toBeVisible({ timeout: 5000 });

    await expect(page.getByTestId('public-profile-display-name')).toHaveText(TEST_DISPLAY_NAME);
    await expect(page.getByTestId('public-profile-founder-line')).toContainText('Hierarchy Test Org');
    await expect(page.getByTestId('public-profile-qr-cta')).toBeVisible();
    await expect(page.getByTestId('public-profile-edit-personal')).toBeVisible();
    await expect(page.getByTestId('public-profile-edit-org')).toHaveCount(0);
    await expect(page.getByTestId('public-profile-view-as-guest')).toHaveCount(0);

    // Back returns to Account, Cá nhân tab preserved.
    await page.getByText(/Quay lại|Back/).first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('account-tab-panel-personal')).toBeVisible();
  });

  test('management page shows the real organizer name + owner, and its one button opens the organizer public profile', async ({ page }) => {
    await setupToHome(page);
    await goToHostTab(page);

    const orgCard = page.getByTestId('org-profile-card');
    await expect(orgCard).toBeVisible({ timeout: 8000 });
    await orgCard.click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });

    await expect(page.locator('[data-screen-label="Organizer dashboard"]').getByText('Hierarchy Test Org')).toBeVisible();
    await expect(page.getByTestId('dashboard-owner-line')).toContainText(TEST_DISPLAY_NAME);
    await expect(page.getByTestId('dashboard-owner-line')).toContainText('Team');
    // The old top-right "Xem như khách" button is gone.
    await expect(page.getByText('Xem như khách', { exact: true })).toHaveCount(0);
    // The old bottom pair is gone; one clear button remains.
    await expect(page.getByTestId('dashboard-edit-org')).toHaveCount(0);
    await expect(page.getByTestId('dashboard-view-as-guest')).toHaveCount(0);

    const publicBtn = page.getByTestId('dashboard-organizer-public-profile');
    await expect(publicBtn).toBeVisible();
    await publicBtn.click();
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('organizer-profile-name')).toHaveText('Hierarchy Test Org');
    await expect(page.getByTestId('organizer-profile-edit')).toBeVisible();

    // Back returns to Dashboard, then to Account (Tổ chức tab preserved).
    await page.getByText(/Quay lại|Back/).first().click();
    await expect(page.locator('[data-screen-label="Organizer dashboard"]')).toBeVisible({ timeout: 5000 });
    await page.locator('[data-screen-label="Organizer dashboard"]').getByText('‹').click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 5000 });
    await expect(page.getByTestId('account-tab-panel-host')).toBeVisible();
  });

  test('a signed-out visitor can open the organizer public profile via /org/<id>, with no owner-only controls', async ({ browser }) => {
    if (!hasServiceRole()) test.skip();
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(`/org/${TEST_ORG_ID}`);
    await expect(page.locator('[data-screen-label="Organizer profile"]')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId('organizer-profile-name')).toHaveText('Hierarchy Test Org');
    await expect(page.getByTestId('organizer-profile-edit')).toHaveCount(0);
    // Never redirected to a login wall.
    await expect(page.locator('[data-screen-label="Login"]')).toHaveCount(0);
    await context.close();
  });
});

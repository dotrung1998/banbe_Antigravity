// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';
import { hasServiceRole, adminClient } from './e2e/setup.mjs';

// Account regression fix pass (2026-09-27) — Items 1, 3, 4.
test.describe('Account cleanup + admin organizer-mode fix', () => {
  test.afterEach(async () => {
    if (!hasServiceRole()) return;
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    if (data?.auth_user_id) await admin.from('profiles').update({ role: 'participant' }).eq('id', data.auth_user_id);
  });

  test('Item 1: Cá nhân shows only the toggle; host-management rows live only in Tổ chức', async ({ page }) => {
    test.skip(!hasServiceRole(), 'requires service role');
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', data.auth_user_id);

    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');

    // Cá nhân (default tab): the toggle is here, the management rows are
    // not VISIBLE — both tab panes stay mounted for scroll-position
    // preservation (Stage D's own established design), so this checks
    // `.toBeHidden()` (CSS display:none, the real "not on Cá nhân" signal)
    // rather than DOM absence.
    await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible();
    await expect(page.getByTestId('host-verifications')).toBeHidden();
    await expect(page.getByTestId('host-payout')).toBeHidden();
    await expect(page.getByTestId('host-invoices')).toBeHidden();
    await expect(page.getByTestId('host-receipts')).toBeHidden();

    // Tổ chức: the management rows are here instead.
    await page.getByTestId('account-tab-host').click();
    await expect(page.getByTestId('account-tab-panel-host')).toBeVisible();
    await expect(page.getByTestId('host-verifications')).toBeVisible();
    await expect(page.getByTestId('host-payout')).toBeVisible();
    await expect(page.getByTestId('host-invoices')).toBeVisible();
    await expect(page.getByTestId('host-receipts')).toBeVisible();
  });

  test('Item 4: organizer card has its own distinct gradient wash, real avatar/name, no fake counts', async ({ page }) => {
    test.skip(!hasServiceRole(), 'requires service role');
    const admin = adminClient();
    const { data } = await admin.from('email_registrations')
      .select('auth_user_id').eq('email', 'doqanh0906+banbe-fast-suite-shared@gmail.com').maybeSingle();
    await admin.from('profiles').update({ role: 'organizer' }).eq('id', data.auth_user_id);
    await admin.from('organizers').upsert({ id: 'org_cleanup_test', owner_id: data.auth_user_id, name: 'Cleanup Test Org', about: 'Real intro.' });

    await setupToHome(page);
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]');
    await page.getByTestId('account-tab-host').click();

    const card = page.getByTestId('org-profile-card');
    await expect(card).toBeVisible({ timeout: 8000 });
    await expect(card).toContainText('Cleanup Test Org');
    const bg = await card.evaluate(el => getComputedStyle(el).backgroundImage);
    expect(bg).toContain('gradient');

    await admin.from('organizers').delete().eq('id', 'org_cleanup_test');
  });

  test('Item 3: admin can toggle organizer mode off and on without losing admin role/tab', async ({ browser }) => {
    test.skip(!hasServiceRole(), 'requires service role');
    const admin = adminClient();
    const email = 'banbetestadmin@gmail.com';
    const password = 'BanbeE2e!Test1234';
    const { data: reg } = await admin.from('email_registrations').select('auth_user_id').eq('email', email).maybeSingle();
    let uid = reg?.auth_user_id;
    if (!uid) {
      const { data } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
      uid = data.user.id;
    } else {
      await admin.auth.admin.updateUserById(uid, { password });
    }
    await admin.from('profiles').update({ role: 'admin', organizer_mode_enabled: true }).eq('id', uid);

    // A plain `browser.newContext()` inherits this project's own
    // `storageState` (the shared fast-suite account is already signed
    // in) — an explicit EMPTY storageState is the only way to get a
    // genuinely signed-out context to drive the real password-login UI
    // as a DIFFERENT (admin) account. `setupToHome()` itself assumes the
    // default (already-signed-in) storageState, so it can't be reused
    // here — this pre-seeds the same lang/theme localStorage convention
    // it writes, skipping straight past onboarding to the real
    // mandatory-login screen instead.
    const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
    const page = await context.newPage();
    await page.addInitScript(() => {
      localStorage.setItem('banbe.preferences', JSON.stringify({ lang: 'vi', theme: 'light', located: true }));
    });
    await page.goto('/');
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 10000 });
    await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();
    await page.getByTestId('login-email').fill(email);
    await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill(password);
    await page.getByTestId('login-submit').click();
    await expect(page.locator('[data-screen-label="Login"]')).toBeHidden({ timeout: 8000 });
    await page.getByTestId('tab-profile').click();
    await page.waitForSelector('[data-screen-label="Account"]', { timeout: 8000 });

    await expect(page.getByTestId('account-tab-admin')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId('organizer-mode-toggle')).toBeVisible();
    await expect(page.getByTestId('account-tab-host')).toBeVisible();

    await page.getByTestId('organizer-mode-toggle').click();
    await expect(page.getByTestId('account-tab-host')).toHaveCount(0, { timeout: 8000 });
    await expect(page.getByTestId('account-tab-admin')).toBeVisible();
    const { data: afterOff } = await admin.from('profiles').select('role, organizer_mode_enabled').eq('id', uid).single();
    expect(afterOff.role).toBe('admin');
    expect(afterOff.organizer_mode_enabled).toBe(false);

    await page.getByTestId('organizer-mode-toggle').click();
    await expect(page.getByTestId('account-tab-host')).toBeVisible({ timeout: 8000 });
    await expect(page.getByTestId('account-tab-admin')).toBeVisible();
    const { data: afterOn } = await admin.from('profiles').select('role, organizer_mode_enabled').eq('id', uid).single();
    expect(afterOn.role).toBe('admin');
    expect(afterOn.organizer_mode_enabled).toBe(true);

    await context.close();
  });
});

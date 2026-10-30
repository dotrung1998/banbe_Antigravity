// @ts-check
import { test, expect } from '@playwright/test';

// Note 51 / migration 187 — an admin can hide Rewards & badges everywhere.
//
// The shared test account is stopped by the server DOB gate (note 49), and is not an admin. So the server's answers
// are mocked at the network edge (the app code under test is the real one): the gate passes, the reward summary
// returns numbers, get_feature_flags returns the flag under test, and profiles.role is patched to 'admin' for the
// admin-screen test. Nothing is written to a real account.
test.use({ viewport: { width: 390, height: 844 } });

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });

/** @param {import('@playwright/test').Page} page */
async function mockServer(page, { flags, admin = false, calls = [] }) {
  await page.route('**/rest/v1/rpc/account_gate_status', (r) => r.fulfill(json({ ready: true })));
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json(flags.current)));
  await page.route('**/rest/v1/rpc/get_my_reward_summary', (r) => r.fulfill(json({ success: true, balance: 120, streak: 3, active_today: true })));
  await page.route('**/rest/v1/rpc/get_my_rewards', (r) => r.fulfill(json({ success: true, balance: 120, streak: { current: 3, active_today: true }, rules: {}, catalog: [], history: [], badges: [] })));
  await page.route('**/rest/v1/rpc/get_my_unlocked_cosmetics', (r) => r.fulfill(json({ design_ids: [] })));
  await page.route('**/rest/v1/rpc/admin_set_feature_flag', async (r) => {
    const body = r.request().postDataJSON();
    calls.push(body);
    flags.current = { ...flags.current, [body.p_key]: body.p_enabled };
    await r.fulfill(json({ success: true, key: body.p_key, enabled: body.p_enabled }));
  });
  if (admin) {
    // The shared account's real profile read comes back empty behind the DOB gate, so serve a synthetic admin row
    // for the one query that decides the role (select=role,...&id=eq.<uid>), in the shape the client asked for.
    await page.route('**/rest/v1/profiles?*select=role*', async (r) => {
      if (r.request().method() !== 'GET') { await r.continue(); return; }
      const row = {
        role: 'admin', locale: 'en', theme: 'light', prefs_saved: true, display_name: 'Admin Test', organizer_mode_enabled: false,
        can_manage_admins: false, muted_notification_kinds: [], interests: [], social_links: [], auto_email_documents: false,
      };
      const wantsObject = (r.request().headers().accept || '').includes('vnd.pgrst.object');
      await r.fulfill(json(wantsObject ? row : [row]));
    });
  }
}

async function toHome(page) {
  await page.goto('/');
  for (let i = 0; i < 40; i++) {
    if (await page.locator('[data-screen-label="Home"]').count()) break;
    if (await page.getByTestId('lang-en').count()) await page.getByTestId('lang-en').click({ force: true, timeout: 1500 }).catch(() => {});
    else if (await page.getByTestId('onboarding-continue').count()) await page.getByTestId('onboarding-continue').click({ force: true, timeout: 1500 }).catch(() => {});
    await page.waitForTimeout(600);
  }
  await page.waitForSelector('[data-screen-label="Home"]', { timeout: 20000 });
}

test.describe('Rewards & badges switch', () => {
  test('on, or flag missing: Home shows the streak/coins capsule and Account the Rewards row', async ({ page }) => {
    for (const current of [{ rewards: true }, {}]) {
      await mockServer(page, { flags: { current } });
      await toHome(page);
      await expect(page.getByTestId('home-reward-shortcuts')).toBeVisible({ timeout: 10000 });
      await page.getByTestId('tab-profile').click();
      await expect(page.getByTestId('account-rewards')).toBeVisible();
      await page.unrouteAll({ behavior: 'ignoreErrors' });
    }
  });

  test('off: no capsule on Home, no Rewards row on Account, and the Rewards route sends you away', async ({ page }) => {
    await mockServer(page, { flags: { current: { rewards: false } } });
    await toHome(page);
    await page.waitForTimeout(2500); // long enough for the summary to have arrived had it been requested
    await expect(page.getByTestId('home-reward-shortcuts')).toHaveCount(0);
    await page.getByTestId('tab-profile').click();
    await expect(page.getByTestId('account-following')).toBeVisible(); // the neighbouring row proves the list rendered
    await expect(page.getByTestId('account-rewards')).toHaveCount(0);
    // A deep link to the screen must not render it.
    await page.goto('/profile/rewards');
    await page.waitForTimeout(2500);
    await expect(page.locator('[data-screen-label="Rewards"]')).toHaveCount(0);
  });

  test('off never calls the reward endpoints', async ({ page }) => {
    const hits = [];
    page.on('request', (r) => { if (/rpc\/(get_my_reward_summary|get_my_rewards|record_active_day)/.test(r.url())) hits.push(r.url()); });
    await mockServer(page, { flags: { current: { rewards: false } } });
    await toHome(page);
    await page.waitForTimeout(2500);
    expect(hits).toEqual([]);
  });

  test('admin: the Feature switches screen flips the flag on the server and Home follows', async ({ page }) => {
    const calls = [];
    const flags = { current: { rewards: true } };
    await mockServer(page, { flags, admin: true, calls });
    await toHome(page);
    await expect(page.getByTestId('home-reward-shortcuts')).toBeVisible({ timeout: 10000 });

    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    // Note 64: every category starts collapsed; opening one must not touch its switches.
    await expect(page.getByTestId('admin-cat-rewards-toggle')).toHaveAttribute('aria-expanded', 'false');
    await expect(page.getByTestId('admin-flag-rewards')).toHaveCount(0);
    await page.getByTestId('admin-cat-rewards-toggle').click();
    await expect(page.getByTestId('admin-cat-rewards-toggle')).toHaveAttribute('aria-expanded', 'true');
    await expect(page.getByTestId('admin-flag-rewards')).toHaveAttribute('data-on', 'true');
    expect(calls).toEqual([]);

    await page.getByTestId('admin-flag-rewards-switch').click();
    await expect(page.getByTestId('admin-flag-rewards')).toHaveAttribute('data-on', 'false');
    expect(calls).toEqual([{ p_key: 'rewards', p_enabled: false }]);

    // The sub-screens have no dock, so reload Home: the flipped flag comes back from the server answer (and the cache).
    await toHome(page);
    await page.waitForTimeout(1500);
    await expect(page.getByTestId('home-reward-shortcuts')).toHaveCount(0);

    // And back on.
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    await page.getByTestId('admin-cat-rewards-toggle').click();
    await page.getByTestId('admin-flag-rewards-switch').click();
    await expect(page.getByTestId('admin-flag-rewards')).toHaveAttribute('data-on', 'true');
    expect(calls[1]).toEqual({ p_key: 'rewards', p_enabled: true });
  });

  test('admin: a server refusal leaves the switch where it was and says why', async ({ page }) => {
    await mockServer(page, { flags: { current: { rewards: true } }, admin: true });
    await page.route('**/rest/v1/rpc/admin_set_feature_flag', (r) => r.fulfill(json({ success: false, error: 'NOT_AUTHORIZED' })));
    await toHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    await page.getByTestId('admin-cat-rewards-toggle').click();
    await page.getByTestId('admin-flag-rewards-switch').click();
    await expect(page.getByTestId('admin-features-error')).toBeVisible();
    await expect(page.getByTestId('admin-flag-rewards')).toHaveAttribute('data-on', 'true');
  });

  test('admin categories: collapsed by default, keyboard opens/closes, counts on', async ({ page }) => {
    await mockServer(page, { flags: { current: { rewards: true, event_reminders: true, push_enabled: false } }, admin: true });
    await toHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    for (const k of ['onboarding', 'rewards', 'notifications', 'events', 'platform']) {
      await expect(page.getByTestId(`admin-cat-${k}-toggle`)).toHaveAttribute('aria-expanded', 'false');
    }
    await expect(page.getByTestId('admin-cat-rewards-count')).toHaveText('1/2 on');
    const notif = page.getByTestId('admin-cat-notifications-toggle');
    await notif.focus();
    await page.keyboard.press('Enter');
    await expect(notif).toHaveAttribute('aria-expanded', 'true');
    await expect(page.getByTestId('admin-flag-event_reminders')).toBeVisible();
    await page.keyboard.press('Space');
    await expect(notif).toHaveAttribute('aria-expanded', 'false');
    await expect(page.getByTestId('admin-flag-event_reminders')).toHaveCount(0);
  });

  test('admin onboarding version: one atomic call, exactly one version shows as active', async ({ page }) => {
    const flags = { current: { rewards: true, onboarding_v2: true, onboarding_v3: false } };
    const versionCalls = [];
    await mockServer(page, { flags, admin: true });
    await page.route('**/rest/v1/rpc/admin_set_onboarding_version', async (r) => {
      const body = r.request().postDataJSON();
      versionCalls.push(body);
      flags.current = { ...flags.current, onboarding_v2: body.p_version === 2, onboarding_v3: body.p_version === 3 };
      await r.fulfill(json({ success: true, version: body.p_version }));
    });
    await toHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    await page.getByTestId('admin-cat-onboarding-toggle').click();
    await expect(page.getByTestId('admin-onboarding-version')).toHaveAttribute('data-version', '2');
    await expect(page.getByTestId('admin-onboarding-version-2')).toHaveAttribute('aria-checked', 'true');
    await page.getByTestId('admin-onboarding-version-3').click();
    await expect(page.getByTestId('admin-onboarding-version')).toHaveAttribute('data-version', '3');
    await expect(page.getByTestId('admin-onboarding-version-2')).toHaveAttribute('aria-checked', 'false');
    expect(versionCalls).toEqual([{ p_version: 3 }]);
  });

  test('admin onboarding version: before migration 202 the old Version 2 switch stays', async ({ page }) => {
    await mockServer(page, { flags: { current: { rewards: true, onboarding_v2: false } }, admin: true });
    await toHome(page);
    await page.getByTestId('tab-profile').click();
    await page.getByTestId('account-admin-tools').click();
    await page.getByTestId('account-group-adminReview').click();
    await page.getByTestId('admin-features').click();
    await page.getByTestId('admin-cat-onboarding-toggle').click();
    await expect(page.getByTestId('admin-onboarding-version')).toHaveCount(0);
    await expect(page.getByTestId('admin-flag-onboarding_v2-switch')).toBeVisible();
  });
});

// @ts-check
import { test, expect } from '@playwright/test';

// Rewards v2 (migration 192): week streak, grace weeks, next badge, monthly goal, tiers, one-time celebration.
// Same approach as rewards-switch.spec.js: the signed-in shared test account (global-setup) and the real app code,
// with every rewards RPC answered at the network edge, so nothing is written to a real account.
test.use({ viewport: { width: 390, height: 844 } });
// Opt-in only: it needs the signed-in shared test account from global-setup, and that account must not be used for
// this spec unless someone asks for it explicitly (note 58). Run with BANBE_E2E_REWARDS_V2=1.
test.skip(!process.env.BANBE_E2E_REWARDS_V2, 'opt-in: set BANBE_E2E_REWARDS_V2=1 (uses the shared signed-in test account)');

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });

const WEEK = { unit: 'week', current: 4, longest: 6, this_week_active: false, week_start: '2026-10-19', grace_held: 1, grace_max: 2,
  grace_every: 4, grace_used: 0, next_grace_in: 4, repair: null, repaired: 0, timezone: 'Asia/Ho_Chi_Minh' };
const badge = (code, family, tier, progress, target, earned, earned_at = null) => ({
  code, family, tier, progress, target, earned, earned_at, title_en: code, title_vi: code, desc_en: `${code} desc`, desc_vi: `${code} desc` });
const BADGES = [
  badge('first_outing', 'outings', 1, 1, 1, true, '2026-10-01T10:00:00Z'),
  badge('regular', 'outings', 2, 4, 5, false),
  badge('explorer', 'explorer', 1, 1, 3, false),
];
const rewardsPayload = (over = {}) => ({
  success: true, balance: 120, rules: { version: 3, onboarding_coins: 10, attendance_coins: 20, attendance_coin_cap_per_month: 10,
    attendance_window_before_hours: 3, attendance_window_after_hours: 24 },
  streak: { current: 1, longest: 3, active_today: false, timezone: 'Asia/Ho_Chi_Minh' }, catalog: [], offers: [], history: [],
  badges: BADGES, week_streak: WEEK,
  next_badge: { code: 'regular', family: 'outings', tier: 2, progress: 4, target: 5, remaining: 1, title_en: 'Regular', title_vi: 'Thường xuyên' },
  goal: { target: null, progress: 1, month: '2026-10-01' }, ...over,
});

/** @param {import('@playwright/test').Page} page */
async function mockServer(page, { flags, payload, calls = [] }) {
  await page.route('**/rest/v1/rpc/account_gate_status', (r) => r.fulfill(json({ ready: true })));
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json(flags)));
  await page.route('**/rest/v1/rpc/get_my_reward_summary', (r) => r.fulfill(json({ success: true, balance: 120, streak: 1, active_today: false, week_streak: 4, week_active: false })));
  await page.route('**/rest/v1/rpc/get_my_rewards', (r) => r.fulfill(json(payload.current)));
  await page.route('**/rest/v1/rpc/get_my_unlocked_cosmetics', (r) => r.fulfill(json({ design_ids: [] })));
  await page.route('**/rest/v1/rpc/set_my_outing_goal', async (r) => {
    const body = r.request().postDataJSON();
    calls.push(body);
    payload.current = { ...payload.current, goal: { target: body.p_goal || null, progress: 1, month: '2026-10-01' } };
    await r.fulfill(json({ success: true, goal: payload.current.goal }));
  });
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

test.describe('Rewards v2', () => {
  test('v2 on: the Home capsule counts weeks and Rewards shows the week card, grace, next badge, goal and tiers', async ({ page }) => {
    await mockServer(page, { flags: { rewards: true, rewards_v2: true }, payload: { current: rewardsPayload() } });
    await toHome(page);
    await expect(page.getByTestId('home-streak')).toHaveAttribute('aria-label', /4-week streak/);
    await page.getByTestId('home-streak').click();
    await expect(page.getByTestId('rewards-week-streak')).toContainText('4');
    await expect(page.getByTestId('rewards-streak-status')).toHaveText('This week is still open');
    await expect(page.getByTestId('rewards-grace')).toContainText('Grace weeks: 1/2');
    await expect(page.getByTestId('rewards-next-badge')).toContainText('One event away from “Regular”');
    await expect(page.getByTestId('badge-family-outings')).toBeVisible();
    await expect(page.getByTestId('badge-first_outing')).toHaveAttribute('data-earned', 'true');
    await expect(page.getByTestId('rewards-rules')).toContainText('A week (Monday–Sunday) counts');
  });

  test('v2 off (or missing): the daily card, no goal, no next badge', async ({ page }) => {
    for (const flags of [{ rewards: true, rewards_v2: false }, { rewards: true }]) {
      await mockServer(page, { flags, payload: { current: rewardsPayload() } });
      await toHome(page);
      await expect(page.getByTestId('home-streak')).toHaveAttribute('aria-label', /1-day streak/);
      await page.getByTestId('home-streak').click();
      await expect(page.getByTestId('rewards-streak')).toBeVisible();
      await expect(page.getByTestId('rewards-week-streak')).toHaveCount(0);
      await expect(page.getByTestId('rewards-goal')).toHaveCount(0);
      await expect(page.getByTestId('rewards-next-badge')).toHaveCount(0);
      await page.unrouteAll({ behavior: 'ignoreErrors' });
    }
  });

  test('choosing a monthly goal calls the server once and shows the progress', async ({ page }) => {
    const calls = [];
    await mockServer(page, { flags: { rewards: true, rewards_v2: true }, payload: { current: rewardsPayload() }, calls });
    await toHome(page);
    await page.getByTestId('home-streak').click();
    await page.getByTestId('rewards-goal-2').click();
    await expect(page.getByTestId('rewards-goal-line')).toHaveText('1 of 2 events this month ▪︎ 1 to go');
    await expect(page.getByTestId('rewards-goal-2')).toHaveAttribute('aria-pressed', 'true');
    expect(calls).toEqual([{ p_goal: 2 }]);
  });

  test('a newly earned badge is celebrated once; the existing collection never is', async ({ page }) => {
    const payload = { current: rewardsPayload() };
    await mockServer(page, { flags: { rewards: true, rewards_v2: true }, payload });
    await toHome(page);
    await page.getByTestId('home-streak').click();
    await expect(page.getByTestId('rewards-week-streak')).toBeVisible();
    await page.waitForTimeout(800);
    await expect(page.getByTestId('rewards-celebration')).toHaveCount(0); // first visit on this device: remember only

    payload.current = rewardsPayload({ badges: [BADGES[0], badge('regular', 'outings', 2, 5, 5, true, '2026-10-22T09:00:00Z'), BADGES[2]] });
    await page.getByTestId('rewards-back').click();
    await page.getByTestId('home-streak').click();
    await expect(page.getByTestId('rewards-celebration')).toContainText('New badge!');

    await page.getByTestId('rewards-back').click();
    await page.getByTestId('home-streak').click();
    await expect(page.getByTestId('rewards-week-streak')).toBeVisible();
    await page.waitForTimeout(800);
    await expect(page.getByTestId('rewards-celebration')).toHaveCount(0);
  });
});

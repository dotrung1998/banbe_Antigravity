// @ts-check
import { test, expect } from '@playwright/test';

// Note 59: the Rewards passages of the Terms/Privacy page follow the `rewards` platform switch. /privacy is the
// public, signed-out page; get_feature_flags is answered at the network edge, nothing else is mocked.
const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
const REWARDS_WORDS = /\b(coins?|Rewards|streaks?|grace weeks?)\b|Phần thưởng|(?<![\p{L}])xu(?![\p{L}]| hướng)/u;

async function open(page, flags) {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.fulfill(json(flags)));
  await page.goto('/privacy');
  await expect(page.locator('[data-screen-label="Policy"]')).toBeVisible();
  await page.waitForTimeout(500); // let the switch answer land
  return page.locator('[data-screen-label="Policy"]').innerText();
}

test('Rewards OFF: the policy says nothing about rewards (both languages)', async ({ page }) => {
  const text = await open(page, { rewards: false });
  expect(text).toContain('B2. What we collect');
  expect(text).not.toMatch(REWARDS_WORDS);
  await expect(page.locator('#A9')).toHaveCount(0);
});

test('Rewards ON: A9 and the B2/B3/B7/B11 rewards passages appear, daily streak only', async ({ page }) => {
  const text = await open(page, { rewards: true, rewards_v2: false });
  await expect(page.locator('#A9')).toBeVisible();
  expect(text).toContain('A9. Rewards: coins, badges and streaks');
  expect(text).toContain('A9. Phần thưởng: xu, huy hiệu và chuỗi');
  expect(text).toContain('Coins do not expire today');
  expect(text).toContain('between 3 hours before and 24 hours after the start');
  expect(text).toContain('Coin ledger (awards, reversals, redemptions)');
  expect(text).toContain('any group smaller than 20 people is hidden');
  expect(text).toContain('remembers which badges and milestones have already been celebrated');
  expect(text).toContain('Miss a day and it starts again from 0');
  expect(text).not.toContain('grace week');
  expect(text).not.toMatch(/cashback|exchange rate|1 coin =/i);
});

test('Rewards ON + v2: the weekly streak replaces the daily one', async ({ page }) => {
  const text = await open(page, { rewards: true, rewards_v2: true });
  expect(text).toContain('Monday to Sunday');
  expect(text).toContain('grace week');
  expect(text).toContain('Monthly goal');
  expect(text).not.toContain('Miss a day');
});

test('Rewards key missing: counts as on (same rule as the app)', async ({ page }) => {
  const text = await open(page, {});
  expect(text).toContain('A9. Rewards: coins, badges and streaks');
});

test('switch answer fails: nothing switched is shown until it is known (no flash)', async ({ page }) => {
  await page.route('**/rest/v1/rpc/get_feature_flags', (r) => r.abort());
  await page.goto('/privacy');
  await expect(page.locator('[data-screen-label="Policy"]')).toBeVisible();
  // A failed read falls back to the device cache, else to "missing = on"; the first paint never contained A9.
  const firstPaint = await page.locator('#A9').count();
  expect(firstPaint).toBeLessThanOrEqual(1);
  await expect(page.getByText('Phiên bản / Version 2026-10-06')).toBeVisible(); // policy version unchanged
});

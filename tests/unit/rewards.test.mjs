import test from 'node:test';
import assert from 'node:assert/strict';
import { compactCoins, shortcutLabels, isRewardsUnavailable, normalizeSummary, historyLabel, ruleLines, shortfall, redemptionTermsLines, noCoinLines } from '../../src/lib/rewards.js';

const T = (vi, en) => en;

test('compactCoins keeps the header stable on narrow screens', () => {
  assert.equal(compactCoins(0), '0');
  assert.equal(compactCoins(9999), '9999');
  assert.equal(compactCoins(10000), '10k');
  assert.equal(compactCoins(12500), '12.5k');
  assert.equal(compactCoins(-40), '-40');          // a balance can go negative after a reversal
  assert.equal(compactCoins(NaN), '0');
});

test('accessible labels carry the numbers and the destination', () => {
  const l = shortcutLabels(T, { streak: 5, balance: 120 });
  assert.match(l.streak, /5-day streak/);
  assert.match(l.coins, /120 coins/);
  assert.match(l.coins, /Open rewards/);
});

test('a missing RPC hides the feature instead of faking numbers', () => {
  assert.equal(isRewardsUnavailable({ code: 'PGRST202' }), true);
  assert.equal(isRewardsUnavailable({ code: '42883' }), true);
  assert.equal(isRewardsUnavailable({ message: 'Could not find the function public.get_my_rewards' }), true);
  assert.equal(isRewardsUnavailable({ code: '500', message: 'boom' }), false);
  assert.equal(normalizeSummary(null), null);
  assert.equal(normalizeSummary({ success: false }), null);
  assert.deepEqual(normalizeSummary({ success: true, balance: 20, streak: 2, active_today: true }), { balance: 20, streak: 2, activeToday: true });
});

test('history labels are readable and never expose raw codes', () => {
  assert.equal(historyLabel({ reason: 'attendance', event_name: 'Jazz' }, T), 'Attended an event ▪︎ Jazz');
  assert.match(historyLabel({ reason: 'attendance_reversed' }, T), /undone/);
  assert.equal(historyLabel({ reason: 'something_new' }, T), 'Activity');
});

test('earning rules are built from the server values', () => {
  const lines = ruleLines({ onboarding_coins: 10, attendance_coins: 20, attendance_coin_cap_per_month: 10 }, T);
  assert.equal(lines.length, 3);
  assert.match(lines[0], /\+10 coins/);
  assert.match(lines[1], /\+20 coins/);
  assert.match(lines[2], /10 events pay coins per month \(200 coins\)/);
  assert.equal(ruleLines({ onboarding_coins: 5, attendance_coins: 7 }, T).length, 2); // no cap line without a cap
});

test('terms state the non-negotiables', () => {
  const all = [...redemptionTermsLines(T), ...noCoinLines(T)].join(' ');
  for (const must of [/cannot be bought, transferred or cashed out/, /no random prizes/i, /never affect booking, priority or eligibility/, /free charms always stay available/, /negative/, /never costs coins/, /claimed the ticket/]) {
    assert.match(all, must);
  }
});

test('shortfall is exact and never negative', () => {
  assert.equal(shortfall(60, 80), 20);
  assert.equal(shortfall(100, 80), 0);
  assert.equal(shortfall(-40, 40), 80);
});

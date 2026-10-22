import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  normalizeWeekStreak, weekStreakHint, graceLine, groupBadgesByFamily, nextBadgeLine, normalizeGoal, goalLine,
  celebrationDiff, readCelebrated, writeCelebrated, normalizeSummary, capsuleStreak, shortcutLabels, ruleLines,
  redemptionTermsLines, historyLabel, weekStreakLines, streakHint, streakLines,
} from '../../src/lib/rewards.js';

// Rewards v2 (migration 192). The JSON vectors are shared with apps/ios/BanbeAppTests/RewardsV2Tests.swift.
const T = (vi, en) => en;
const V = JSON.parse(readFileSync(new URL('../fixtures/rewards-v2-week-streak.json', import.meta.url), 'utf8'));

test('week streak vectors (shared with iOS)', () => {
  for (const v of V.week_streak) {
    const ws = normalizeWeekStreak(v.raw);
    assert.equal(weekStreakHint(T, ws, 'en').status, v.expect.status, v.name);
    assert.equal(graceLine(T, ws), v.expect.grace, v.name);
  }
});

test('next badge + goal vectors (shared with iOS)', () => {
  for (const v of V.next_badge) assert.equal(nextBadgeLine(T, v.nb, 'en'), v.expect);
  for (const v of V.goal) assert.equal(goalLine(T, normalizeGoal(v.raw)), v.expect);
});

test('an older server (no week_streak / goal) gives null, never fake numbers', () => {
  assert.equal(normalizeWeekStreak(undefined), null);
  assert.equal(normalizeWeekStreak({ current: 3 }), null);
  assert.equal(normalizeGoal(undefined), null);
  const sum = normalizeSummary({ success: true, balance: 5, streak: 2, active_today: true });
  assert.equal(sum.weekStreak, null);
  assert.deepEqual(capsuleStreak(sum, true), { value: 2, unit: 'day' });
});

test('Home capsule switches to weeks only under v2 with a server value', () => {
  const sum = normalizeSummary({ success: true, balance: 5, streak: 2, active_today: true, week_streak: 7, week_active: false });
  assert.deepEqual(capsuleStreak(sum, false), { value: 2, unit: 'day' });
  assert.deepEqual(capsuleStreak(sum, true), { value: 7, unit: 'week' });
  assert.equal(shortcutLabels(T, sum, true).streak, '7-week streak. Open rewards');
  assert.equal(shortcutLabels(T, sum).streak, '2-day streak. Open rewards');
});

test('repair copy names a real date and never uses loss language', () => {
  const ws = normalizeWeekStreak(V.week_streak[2].raw);
  const h = weekStreakHint(T, ws, 'en');
  assert.match(h.how, /Oct 25/);
  for (const v of V.week_streak) {
    const x = weekStreakHint(T, normalizeWeekStreak(v.raw), 'en');
    assert.doesNotMatch(`${x.status} ${x.how}`, /lose|lost|hurry|last chance|don't break/i);
  }
});

test('badges group by family with tiers in order; a v1 payload keeps one row per badge', () => {
  const g = groupBadgesByFamily([
    { code: 'regular', family: 'outings', tier: 2, earned: false, progress: 4, target: 5 },
    { code: 'first_outing', family: 'outings', tier: 1, earned: true, progress: 1, target: 1 },
    { code: 'explorer', family: 'explorer', tier: 1, earned: false, progress: 1, target: 3 },
  ]);
  assert.deepEqual(g.map(x => x.family), ['outings', 'explorer']);
  assert.deepEqual(g[0].badges.map(b => b.code), ['first_outing', 'regular']);
  assert.equal(g[0].top.code, 'first_outing');
  assert.equal(g[0].next.code, 'regular');
  assert.equal(g[0].earnedCount, 1);
  const v1 = groupBadgesByFamily([{ code: 'a', earned: true }, { code: 'b', earned: false }]);
  assert.equal(v1.length, 2);
});

test('celebrations: first run on a device remembers, never bursts; then only new earnings', () => {
  const badges = [{ code: 'first_outing', earned: true, earned_at: '2026-10-01T10:00:00Z' }, { code: 'regular', earned: false }];
  const first = celebrationDiff(badges, null, null);
  assert.deepEqual(first.show, []);
  assert.deepEqual(first.keys, ['b:first_outing:2026-10-01T10:00:00Z']);
  const later = [...badges.slice(0, 1), { code: 'regular', earned: true, earned_at: '2026-10-20T10:00:00Z' }];
  const d = celebrationDiff(later, null, first.keys);
  assert.deepEqual(d.show.map(x => x.code), ['regular']);
  assert.deepEqual(celebrationDiff(later, null, d.keys).show, []);
  // Re-earned after a revocation (new earned_at) celebrates again.
  const again = celebrationDiff([{ code: 'regular', earned: true, earned_at: '2026-11-02T10:00:00Z' }], null, d.keys);
  assert.equal(again.show.length, 1);
});

test('week milestones celebrate once per run of the streak', () => {
  const ws = normalizeWeekStreak({ ...V.week_streak[1].raw, current: 4, week_start: '2026-10-19' });
  const d = celebrationDiff([], ws, []);
  assert.deepEqual(d.show.map(x => [x.kind, x.weeks, x.key]), [['weeks', 4, 'w:4:2026-09-28']]);
  assert.deepEqual(celebrationDiff([], ws, d.keys).show, []);
  assert.deepEqual(celebrationDiff([], normalizeWeekStreak({ ...V.week_streak[1].raw, current: 3 }), []).show, []);
});

test('celebrated keys persist per account and survive a broken store', () => {
  const m = new Map(); const store = { getItem: k => m.get(k) ?? null, setItem: (k, v) => m.set(k, v) };
  assert.equal(readCelebrated('u1', store), null);
  writeCelebrated('u1', ['x'], store);
  assert.deepEqual(readCelebrated('u1', store), ['x']);
  assert.equal(readCelebrated('u2', store), null);
  store.setItem('banbe_rewards_celebrated_v1:u1', '{bad');
  assert.equal(readCelebrated('u1', store), null);
  assert.doesNotThrow(() => writeCelebrated('u1', ['x'], { setItem() { throw new Error('quota'); } }));
});

test('rules v2 adds the attendance window line; v1 rules do not', () => {
  const v1 = { onboarding_coins: 10, attendance_coins: 20, attendance_coin_cap_per_month: 10 };
  assert.equal(ruleLines(v1, T).length, 3);
  const v2 = { ...v1, attendance_window_before_hours: 3, attendance_window_after_hours: 24 };
  assert.match(ruleLines(v2, T)[3], /between 3 hours before and 24 hours after the start/);
  assert.match(historyLabel({ reason: 'off_window' }, T), /outside the event time/);
});

test('weekly terms + rule lines never promise cash and say streaks pay nothing', () => {
  const all = [...redemptionTermsLines(T, true), ...weekStreakLines(T, normalizeWeekStreak(V.week_streak[0].raw))].join(' ');
  assert.match(all, /missing a week never costs coins/);
  assert.match(all, /never pay coins/);
  assert.doesNotMatch(all, /cashback|1 coin =|exchange rate/i);
});

test('daily streak copy (v1) is unchanged', () => {
  assert.equal(streakHint(T, true).status, "✓ Today's counted");
  assert.equal(streakLines(T, 0, null).length, 2);
});

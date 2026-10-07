import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeForSave, prefsIsEmpty, toggleMulti, pickBudgetTier, budgetTierLabel, budgetRegionDefault, budgetCap,
  everyone, normalizeCriteria, criteriaSummary, eligibilityGuidance, isMissingFunctionError,
} from '../../src/lib/eventPrefs.js';
import { forYouMatch, forYouRank, forYouTimeZone, forYouPriceCurrency } from '../../src/lib/forYou.js';

const NOW = Date.parse('2026-10-07T00:00:00Z');
const day = (n) => NOW + n * 86400000;
const ev = (key, over = {}) => ({
  key, categories: ['music'], priceAmount: 100000, priceCurrency: 'VND', isFree: false,
  startsAt: day(5), timeZone: 'Asia/Ho_Chi_Minh', isBookable: true, ...over,
});

test('deterministic ordering: score desc, soonest start, then key', () => {
  const prefs = { interests: ['music'] };
  const events = [ev('b', { startsAt: day(30) }), ev('a', { startsAt: day(30) }), ev('c', { startsAt: day(1) }), ev('far', { startsAt: day(30), categories: ['music'] })];
  const r1 = forYouRank(events, prefs, NOW).map(m => m.key);
  const r2 = forYouRank([...events].reverse(), prefs, NOW).map(m => m.key);
  assert.deepEqual(r1, ['c', 'a', 'b', 'far']);
  assert.deepEqual(r2, r1);
});

test('interest hard exclusion; unknown category passes', () => {
  const prefs = { interests: ['music'] };
  assert.equal(forYouMatch(ev('x', { categories: ['gallery'] }), prefs, NOW), null);
  assert.ok(forYouMatch(ev('y', { categories: ['music', 'gallery'] }), prefs, NOW));
  // unknown category: no interest signal, so needs another affirmative signal (goal here)
  const withGoal = { interests: ['music'], budget: { tier: 'flexible', currency: 'VND' } };
  assert.equal(forYouMatch(ev('z', { categories: ['mystery'] }), withGoal, NOW), null); // no signal at all
  const free = forYouMatch(ev('z2', { categories: ['mystery'], isFree: true, priceAmount: 0 }), { interests: ['music'], budget: { tier: 'low', currency: 'VND' } }, NOW);
  assert.ok(free); // not excluded by interests, matched on budget
  assert.deepEqual(free.reasons, ['budget']);
});

test('free-only budget excludes paid events', () => {
  const prefs = { budget: { tier: 'free' } };
  assert.equal(forYouMatch(ev('p'), prefs, NOW), null);
  assert.ok(forYouMatch(ev('f', { isFree: true, priceAmount: 0 }), prefs, NOW));
});

test('VN budget boundaries 200_000 and 600_000', () => {
  const low = { budget: { tier: 'low', currency: 'VND' } };
  const med = { budget: { tier: 'medium', currency: 'VND' } };
  assert.ok(forYouMatch(ev('a', { priceAmount: 200000 }), low, NOW));
  assert.equal(forYouMatch(ev('b', { priceAmount: 200001 }), low, NOW), null);
  assert.ok(forYouMatch(ev('c', { priceAmount: 600000 }), med, NOW));
  assert.equal(forYouMatch(ev('d', { priceAmount: 600001 }), med, NOW), null);
  assert.equal(budgetCap('VN', 'low'), 200000);
  assert.equal(budgetCap('US', 'medium'), 75);
});

test('USD budget vs VND-priced or unknown-currency event is neutral (never excludes)', () => {
  const usd = { interests: ['music'], budget: { tier: 'low', currency: 'USD' } };
  const m = forYouMatch(ev('v', { priceAmount: 5000000 }), usd, NOW);
  assert.ok(m); assert.deepEqual(m.reasons, ['interest']);
  const unk = forYouMatch(ev('u', { priceAmount: 99999, priceCurrency: null }), usd, NOW);
  assert.ok(unk);
  assert.equal(forYouPriceCurrency('US'), null);
  assert.equal(forYouPriceCurrency(undefined), 'VND');
});

test('availability is evaluated in the event time zone (explicit instants)', () => {
  // Friday 2026-10-09 18:00Z = Saturday 01:00 in Ho_Chi_Minh, Friday 11:00 in Los_Angeles
  const t = Date.parse('2026-10-09T18:00:00Z');
  const prefs = { interests: ['music'], availability: ['weekends'] };
  const vn = forYouMatch(ev('vn', { startsAt: t, timeZone: 'Asia/Ho_Chi_Minh' }), prefs, NOW);
  const la = forYouMatch(ev('la', { startsAt: t, timeZone: 'America/Los_Angeles' }), prefs, NOW);
  assert.ok(vn.reasons.includes('time'));
  assert.ok(!la.reasons.includes('time'));
  assert.equal(vn.score - la.score, 25); // +10 fit vs -15 miss
  // evening vs daytime: 2026-10-09T12:00Z = 19:00 VN (evening), 05:00 LA (daytime)
  const t2 = Date.parse('2026-10-09T12:00:00Z');
  const ev1 = forYouMatch(ev('e1', { startsAt: t2, timeZone: 'Asia/Ho_Chi_Minh' }), { interests: ['music'], availability: ['evening'] }, NOW);
  const ev2 = forYouMatch(ev('e2', { startsAt: t2, timeZone: 'America/Los_Angeles' }), { interests: ['music'], availability: ['evening'] }, NOW);
  assert.ok(ev1.reasons.includes('time')); assert.ok(!ev2.reasons.includes('time'));
  assert.equal(forYouTimeZone('US', 'CA'), 'America/Los_Angeles');
  assert.equal(forYouTimeZone('US', 'texas'), 'America/Chicago');
  assert.equal(forYouTimeZone('US', 'Zzz'), null);
  assert.equal(forYouTimeZone('FR', null), null);
  assert.equal(forYouTimeZone(null, null), 'Asia/Ho_Chi_Minh');
});

test('unknown time zone or start is neutral for availability', () => {
  const prefs = { interests: ['music'], availability: ['weekends'] };
  const base = forYouMatch(ev('n0', { timeZone: null }), prefs, NOW);
  const none = forYouMatch(ev('n1', { timeZone: 'Not/AZone' }), prefs, NOW);
  assert.ok(base); assert.ok(none);
  assert.equal(base.score, none.score);
  assert.ok(!base.reasons.includes('time'));
});

test('ended, sold-out/not bookable and past events are excluded', () => {
  const prefs = { interests: ['music'] };
  assert.equal(forYouMatch(ev('o', { isBookable: false }), prefs, NOW), null);
  assert.equal(forYouMatch(ev('p', { startsAt: day(-1) }), prefs, NOW), null);
  assert.ok(forYouMatch(ev('ok'), prefs, NOW));
});

test('missing optional data never excludes', () => {
  const prefs = { interests: ['music'], budget: { tier: 'low', currency: 'VND' }, availability: ['weekends'] };
  const m = forYouMatch(ev('m', { startsAt: null, timeZone: null, priceAmount: null, priceCurrency: null }), prefs, NOW);
  assert.ok(m); assert.deepEqual(m.reasons, ['interest']);
});

test('goal affinity is soft and capped at +20', () => {
  const m = forYouMatch(ev('g', { startsAt: null }), { goals: ['meet_people', 'experiences', 'networking'] }, NOW);
  assert.equal(m.score, 20);
});

test('normalizeForSave rules', () => {
  assert.deepEqual(normalizeForSave({}), { version: 1 });
  assert.deepEqual(normalizeForSave({ interests: [], goals: ['learn'] }), { version: 1, goals: ['learn'] });
  assert.deepEqual(normalizeForSave({ interests: ['music', 'no_preference'] }), { version: 1, interests: ['no_preference'] });
  assert.deepEqual(normalizeForSave({ budget: { tier: 'free', currency: 'VND' } }), { version: 1, budget: { tier: 'free' } });
  assert.deepEqual(normalizeForSave({ budget: { tier: 'no_preference', currency: 'USD' } }), { version: 1, budget: { tier: 'no_preference' } });
  assert.deepEqual(normalizeForSave({ version: 9, budget: { tier: 'low', currency: 'USD' } }), { version: 1, budget: { tier: 'low', currency: 'USD' } });
  assert.ok(prefsIsEmpty(null)); assert.ok(prefsIsEmpty({})); assert.ok(!prefsIsEmpty({ goals: ['learn'] }));
  assert.equal(toggleMulti(['music'], 'music'), undefined);
  assert.deepEqual(toggleMulti(['music'], 'no_preference'), ['no_preference']);
  assert.deepEqual(toggleMulti(['no_preference'], 'gallery'), ['gallery']);
  assert.deepEqual(pickBudgetTier(undefined, 'free', 'VN'), { tier: 'free' });
  assert.deepEqual(pickBudgetTier(undefined, 'low', 'US'), { tier: 'low', currency: 'USD' });
  assert.equal(pickBudgetTier({ tier: 'low', currency: 'VND' }, 'low', 'VN'), undefined);
});

test('budget labels and region default', () => {
  assert.equal(budgetTierLabel('VN', 'low', false), 'Low · up to 200.000₫');
  assert.equal(budgetTierLabel('VN', 'medium', true), 'Trung bình · 200.000₫ – 600.000₫');
  assert.equal(budgetTierLabel('US', 'medium', false), 'Medium · $25 – $75');
  assert.equal(budgetRegionDefault('en-US'), 'US');
  assert.equal(budgetRegionDefault('vi-VN'), 'VN');
  assert.equal(budgetRegionDefault('en'), 'VN');
});

test('preferences and criteria JSON shape', () => {
  const p = normalizeForSave({ interests: ['music'], goals: ['learn'], availability: ['weekends'], budget: { tier: 'medium', currency: 'VND' }, languages: ['vi'] });
  assert.equal(JSON.stringify(p), '{"version":1,"interests":["music"],"goals":["learn"],"availability":["weekends"],"budget":{"tier":"medium","currency":"VND"},"languages":["vi"]}');
  assert.deepEqual(everyone(), { version: 1, mode: 'everyone' });
  assert.deepEqual(normalizeCriteria({ mode: 'declared', interests: { rule: 'any', values: [] } }), { version: 1, mode: 'everyone' });
  const c = normalizeCriteria({ mode: 'declared', interests: { rule: 'any', values: ['music', 'gallery'] }, goals: { rule: 'all', values: ['learn'] } });
  assert.equal(JSON.stringify(c), '{"version":1,"mode":"declared","interests":{"rule":"any","values":["music","gallery"]},"goals":{"rule":"all","values":["learn"]}}');
  assert.equal(criteriaSummary(c, false), 'Interests: Any of: Music, Gallery  ▪︎  Goals: All of: Learn something');
  assert.equal(criteriaSummary(everyone(), true), 'Mọi người');
  assert.deepEqual(eligibilityGuidance({ missing_interests: ['music'], interest_rule: 'any', missing_goals: ['learn'], goal_rule: 'all' }, false),
    ['Interests: Pick at least one: Music', 'Goals: Add: Learn something']);
  assert.ok(isMissingFunctionError({ code: 'PGRST202' }));
  assert.ok(isMissingFunctionError({ message: 'Could not find the function public.x' }));
  assert.ok(!isMissingFunctionError({ code: '500' }));
});

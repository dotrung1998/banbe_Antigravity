import test from 'node:test';
import assert from 'node:assert/strict';
import { TOUR_STEPS, TOUR_CHAPTERS, TOUR_DO_IT, WEB_TARGETS, eligibleSteps, tourPlan, stepCopy, tourDoneKey } from '../../src/data/onboardingTour.js';

// Web follows the v5 prototype's tour; the iOS twin (OnboardingTourContent.swift) is not updated here, so no parity check.
test('every step has bilingual copy, a web target and a tour screen', () => {
  for (const s of TOUR_STEPS) {
    assert.ok(WEB_TARGETS[s.target], s.target);
    assert.equal(s.vi.length, 2); assert.equal(s.en.length, 2);
    assert.ok(s.vi.every(Boolean) && s.en.every(Boolean));
    assert.ok(['home', 'inbox', 'profile'].includes(s.screen));
  }
  assert.equal(new Set(TOUR_STEPS.map(s => s.id)).size, TOUR_STEPS.length);
});

test('hosting chapter only for organizers; every chapter step exists', () => {
  const ids = new Set(TOUR_STEPS.map(s => s.id));
  for (const c of TOUR_CHAPTERS) for (const id of c.stepIds) assert.ok(ids.has(id), id);
  assert.ok(!tourPlan({ organizerMode: false }).some(c => c.chapter.id === 'host'));
  assert.ok(tourPlan({ organizerMode: true }).some(c => c.chapter.id === 'host'));
  assert.equal(eligibleSteps({ organizerMode: true }).length, TOUR_STEPS.length);
});

test('do-it steps are the prototype taps: Tonight, Activity, Account, Hosting', () => {
  assert.deepEqual(Object.keys(TOUR_DO_IT).sort(), ['dock.account', 'dock.activity', 'home.tonight', 'host.tab']);
});

test('completion marker is per account', () => {
  assert.equal(tourDoneKey('abc'), 'banbe.tour.v3.done.abc');
});

test('account shortcuts copy follows the Rewards switch, computed at call time', () => {
  const st = TOUR_STEPS.find(s => s.id === 'account.shortcuts');
  assert.ok(st.copyWhenRewardsOff);
  assert.match(stepCopy(st, 'en', { rewardsEnabled: true })[1], /Saved events, and Rewards\.$/);
  assert.match(stepCopy(st, 'en', { rewardsEnabled: false })[1], /Saved events, and Help\.$/);
  assert.match(stepCopy(st, 'vi', { rewardsEnabled: true })[1], /Phần thưởng\.$/);
  assert.match(stepCopy(st, 'vi', { rewardsEnabled: false })[1], /Trợ giúp\.$/);
  // other steps are unaffected
  const other = TOUR_STEPS.find(s => s.id === 'home.search');
  assert.deepEqual(stepCopy(other, 'en', { rewardsEnabled: false }), other.en);
});

test('Filters step targets the one-line summary itself, not the whole By type block', () => {
  assert.equal(WEB_TARGETS['tour.home.filters'], '[data-testid="home-filter-summary"]');
  assert.equal(TOUR_STEPS.find(s => s.id === 'home.filters').target, 'tour.home.filters');
});

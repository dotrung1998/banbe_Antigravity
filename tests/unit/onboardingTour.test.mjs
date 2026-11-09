import test from 'node:test';
import assert from 'node:assert/strict';
import { TOUR_STEPS, TOUR_CHAPTERS, TOUR_DO_IT, WEB_TARGETS, eligibleSteps, tourPlan, tourDoneKey } from '../../src/data/onboardingTour.js';

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

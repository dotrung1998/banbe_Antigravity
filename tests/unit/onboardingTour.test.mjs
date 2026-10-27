import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { TOUR_STEPS, WEB_TARGETS, eligibleSteps, tourDoneKey } from '../../src/data/onboardingTour.js';

const swift = readFileSync(new URL('../../apps/ios/BanbeApp/Models/OnboardingTourContent.swift', import.meta.url), 'utf8');
const iosSteps = [...swift.matchAll(/TourStep\(id: "([^"]+)", target: "([^"]+)", screen: "([^"]+)", below: (true|false)(?:, requires: "([^"]+)")?/g)]
  .map(m => ({ id: m[1], target: m[2], screen: m[3], below: m[4] === 'true', requires: m[5] || null }));

test('web and iOS tour steps match: ids, targets, screens, placement, order', () => {
  assert.deepEqual(iosSteps, TOUR_STEPS.map(s => ({ id: s.id, target: s.target, screen: s.screen, below: s.placement === 'below', requires: s.requires || null })));
});

test('every step has bilingual copy and a web target', () => {
  for (const s of TOUR_STEPS) {
    assert.ok(WEB_TARGETS[s.target], s.target);
    assert.equal(s.vi.length, 2); assert.equal(s.en.length, 2); assert.equal(s.short.length, 2);
    assert.ok(s.vi.every(Boolean) && s.en.every(Boolean));
    assert.ok(['home', 'profile'].includes(s.screen));
  }
  assert.equal(new Set(TOUR_STEPS.map(s => s.id)).size, TOUR_STEPS.length);
});

test('eligibility drops host-only steps for guests of the dock "+"', () => {
  assert.ok(!eligibleSteps({ organizerMode: false }).some(s => s.id === 'dock.create'));
  assert.ok(eligibleSteps({ organizerMode: true }).some(s => s.id === 'dock.create'));
  assert.equal(eligibleSteps({ organizerMode: true }).length, TOUR_STEPS.length);
});

test('completion marker is per account', () => {
  assert.equal(tourDoneKey('abc'), 'banbe.tour.v3.done.abc');
});

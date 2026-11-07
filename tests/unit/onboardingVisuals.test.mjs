import test from 'node:test';
import assert from 'node:assert/strict';
import { INTERESTS, GOALS, AVAILABILITY, LANGUAGES, BUDGET_TIERS, NO_PREFERENCE, OPTION_EMOJI, CATEGORY_EMOJI, optionEmoji } from '../../src/lib/eventPrefs.js';
import { selectionFeedback } from '../../src/lib/onboardingFlow.js';

// Mirrored by apps/ios/BanbeAppTests/OnboardingVisualsTests.swift — change both together.

test('every server option id has its own emoji (ids are fixed by migration 162)', () => {
  const ids = [...INTERESTS, ...GOALS, ...AVAILABILITY, ...LANGUAGES].map(o => o.id).concat(BUDGET_TIERS, [NO_PREFERENCE]);
  for (const id of ids) assert.ok(OPTION_EMOJI[id], `${id} has no emoji`);
  // Within one question, no two answers share a face.
  for (const list of [INTERESTS, GOALS, AVAILABILITY, LANGUAGES]) {
    const faces = list.map(o => OPTION_EMOJI[o.id]);
    assert.equal(new Set(faces).size, faces.length);
  }
  assert.equal(new Set(BUDGET_TIERS.map(t => OPTION_EMOJI[t])).size, BUDGET_TIERS.length);
  assert.equal(optionEmoji('unknown'), '•');
});

test('categories look the same in onboarding and in Create event', () => {
  for (const o of INTERESTS) assert.equal(OPTION_EMOJI[o.id], CATEGORY_EMOJI[o.id]);
});

test('live feedback answers each tap, and stays quiet before one', () => {
  assert.equal(selectionFeedback('interests', [], false), null);
  assert.equal(selectionFeedback('budget', null, false), null);
  assert.equal(selectionFeedback('interests', ['music', 'supper'], false), '🎵 🍽️ · only these kinds get the ★');
  assert.equal(selectionFeedback('goals', ['learn'], true), '💡 · sự kiện hợp sẽ được xếp lên trước');
  assert.equal(selectionFeedback('availability', [NO_PREFERENCE], false), '🤷 · Nothing filtered here');
  assert.equal(selectionFeedback('budget', { tier: 'free' }, false), '🆓 · free events only');
  assert.equal(selectionFeedback('budget', { tier: 'medium' }, false), '💵 · hides events above this');
  assert.equal(selectionFeedback('budget', { tier: 'flexible' }, false), '💎 · no price limit');
  assert.equal(selectionFeedback('languages', ['vi'], false), "🇻🇳 · saved, doesn't filter yet");
});

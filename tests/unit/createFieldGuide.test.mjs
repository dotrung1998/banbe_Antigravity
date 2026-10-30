import test from 'node:test';
import assert from 'node:assert/strict';
import { CREATE_FIELD_STEP, stepOfField, isTextField, firstMissingField } from '../../src/lib/createFieldGuide.js';
import { recipeChecks } from '../../src/lib/eventRecipe.js';
import { isHiddenByKeyboard } from '../../src/lib/useKeepFocusedVisible.js';

// Mirrored by apps/ios/BanbeAppTests/CreateFieldGuideTests.swift — change both together.

test('every recipe ingredient points at a known field on the step it names', () => {
  const checks = recipeChecks({ name: '', description: '', photos: 0, keywords: [], priceVnd: 0, seats: 0, startsAt: null }, null, null, Date.now());
  assert.ok(checks.length >= 9);
  for (const c of checks) {
    assert.notEqual(stepOfField(c.fix.field), null, `${c.id} -> ${c.fix.field} has no anchor`);
    assert.equal(stepOfField(c.fix.field), c.fix.step, `${c.id}: field ${c.fix.field} lives on step ${stepOfField(c.fix.field)}, not ${c.fix.step}`);
  }
});

test('steps: Host 0, Basics 1, When & where 2, Tickets 3, Photos 4', () => {
  assert.equal(CREATE_FIELD_STEP.hostName, 0);
  assert.equal(stepOfField('intro'), 1);
  assert.equal(stepOfField('location'), 2);
  assert.equal(stepOfField('seats'), 3);
  assert.equal(stepOfField('photos'), 4);
  assert.equal(stepOfField('nope'), null);
  assert.equal(stepOfField('toString'), null);
});

test('only typing fields get focus (and the keyboard)', () => {
  for (const f of ['hostName', 'name', 'description', 'intro', 'greeting', 'keywords', 'location', 'price']) assert.ok(isTextField(f), f);
  for (const f of ['categories', 'included', 'date', 'seats', 'photos']) assert.ok(!isTextField(f), f);
});

test('first missing field follows the on-screen order', () => {
  assert.equal(firstMissingField({}), null);
  assert.equal(firstMissingField({ photos: true, name: true }), 'name');
  assert.equal(firstMissingField({ seats: true, location: true }), 'location');
  assert.equal(firstMissingField({ hostName: true, description: true }), 'hostName');
  assert.equal(firstMissingField({ included: false, date: true }), 'date');
  // Same order as the ring: price and the type facts count too (was a stale list without them).
  assert.equal(firstMissingField({ price: true, seats: true }), 'price');
  assert.equal(firstMissingField({ alcohol: true, location: true }), 'alcohol');
});

test('keyboard check: a field under the keyboard is hidden, one in view is not', () => {
  // 844pt screen, keyboard leaves the top 480pt visible.
  assert.equal(isHiddenByKeyboard({ top: 520, bottom: 640 }, 0, 480), true);
  assert.equal(isHiddenByKeyboard({ top: 200, bottom: 300 }, 0, 480), false);
  assert.equal(isHiddenByKeyboard({ top: 2, bottom: 60 }, 0, 480), true); // tucked under the top edge
  // Taller than the visible band: fine while its top shows.
  assert.equal(isHiddenByKeyboard({ top: 100, bottom: 900 }, 0, 480), false);
  assert.equal(isHiddenByKeyboard({ top: 460, bottom: 1200 }, 0, 480), true);
  assert.equal(isHiddenByKeyboard(null, 0, 480), false);
});

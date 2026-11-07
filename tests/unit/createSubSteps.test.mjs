import test from 'node:test';
import assert from 'node:assert/strict';
import { subStepParts, partOfField, subStepDone } from '../../src/lib/createSubSteps.js';
import { stepOfField, CREATE_FIELD_ORDER } from '../../src/lib/createFieldGuide.js';

// Same cases as apps/ios/BanbeAppTests/CreateSubStepsTests.swift.
test('only Basics and Tickets have parts', () => {
  assert.deepEqual(subStepParts(1).map(p => p.id), ['name', 'story', 'greeting', 'categories', 'details']);
  assert.deepEqual(subStepParts(3).map(p => p.id), ['price', 'seats', 'privacy', 'criteria']);
  for (const st of [0, 2, 4]) assert.deepEqual(subStepParts(st), []);
});
test('every Basics / Tickets field has a part', () => {
  for (const f of [...CREATE_FIELD_ORDER, 'intro', 'greeting', 'keywords', 'dietary', 'genre']) {
    const st = stepOfField(f);
    if (st === 1 || st === 3) assert.notEqual(partOfField(f, st), null, f);
  }
  assert.equal(partOfField('intro', 1), 1);
  assert.equal(partOfField('lineup', 1), 4);
  assert.equal(partOfField('alcohol', 1), 4);
  assert.equal(partOfField('seats', 3), 1);
  assert.equal(partOfField('location', 2), null);
});
test('done needs nothing missing and a visit', () => {
  assert.deepEqual(subStepDone(1, ['description', 'alcohol'], new Set([0, 1, 2])), [true, false, true, false, false]);
  assert.deepEqual(subStepDone(3, [], new Set()), [false, false, false, false]);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { computeCreateProgress, FIELD_ORDER, missingLabel } from '../../src/lib/createProgress.js';
import { stepOfField } from '../../src/lib/createFieldGuide.js';

// Mirrored by apps/ios/BanbeAppTests/CreateProgressTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/create-progress.json', import.meta.url), 'utf8'));

for (const c of fx.cases) {
  test(`create progress: ${c.case}`, () => {
    const missing = Object.fromEntries(c.missing.map(id => [id, true]));
    const p = computeCreateProgress(missing, c.required);
    assert.deepEqual(p.steps.map(x => x.done), c.expect.done);
    assert.equal(p.percent, c.expect.percent);
    assert.equal(p.stepsLeft, c.expect.stepsLeft);
    assert.equal(p.firstMissing, c.expect.firstMissing);
    assert.deepEqual(p.missing, c.expect.missing);
  });
}

test('ring, steps left and Still needed come from one result', () => {
  for (const c of fx.cases) {
    const p = computeCreateProgress(Object.fromEntries(c.missing.map(id => [id, true])), c.required);
    assert.equal(p.stepsLeft, p.steps.filter(x => !x.done).length);
    assert.deepEqual(p.steps.flatMap(x => x.missing), p.missing);
    assert.equal(p.percent, Math.round(((5 - p.stepsLeft) / 5) * 100));
  }
});

test('every field has a step and a label', () => {
  const T = (vi) => vi; // the Vietnamese label never equals the id, so a missing case shows up
  for (const id of FIELD_ORDER) {
    assert.notEqual(stepOfField(id), null, id);
    assert.notEqual(missingLabel(id, T, 4), id, id);
  }
});

// criteriaPlain (note 70) against the shared fixture; mirrored by apps/ios/BanbeAppTests/CriteriaPlainTests.swift.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { criteriaPlain, normalizeCriteria } from '../../src/lib/eventPrefs.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/criteria-plain.json', import.meta.url)));

for (const c of fx.cases) {
  test(`criteriaPlain: ${c.name}`, () => {
    const criteria = normalizeCriteria(c.criteria);
    assert.equal(criteriaPlain(criteria, false), c.en);
    assert.equal(criteriaPlain(criteria, true), c.vi);
    for (const out of [criteriaPlain(criteria, false), criteriaPlain(criteria, true)]) {
      if (out) assert.doesNotMatch(out, /Any of|All of|Interests:|Một trong|▪/);
    }
  });
}

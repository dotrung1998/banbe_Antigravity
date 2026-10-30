import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  TYPE_KEYS, profileFor, isShaped, cleanDetails, droppedDetailTypes, detailFacts, cardLine, homeFilters,
  matchesHomeFilter, keywordSuggestions, requiredFields,
} from '../../src/lib/eventTypes.js';
import { buildEventSearchDoc, matchesSearchQuery } from '../../src/lib/search.js';
import { applyDiscoveryFilters, optionCounts, activeFilterCount, relaxationHints } from '../../src/lib/homeDiscovery.js';
import { INTERESTS, CATEGORY_EMOJI } from '../../src/lib/eventPrefs.js';
import { FIELD_ORDER } from '../../src/lib/createProgress.js';
import { stepOfField } from '../../src/lib/createFieldGuide.js';

// Mirrored by apps/ios/BanbeAppTests/EventTypesTests.swift through the same fixture.
const fx = JSON.parse(readFileSync(new URL('../fixtures/event-types.json', import.meta.url), 'utf8'));
const filterById = (type, id) => homeFilters(profileFor(type)).find(f => f.id === id);

test('the five keys, in order, are the server ids', () => {
  assert.deepEqual(TYPE_KEYS, fx.keys);
  assert.deepEqual(INTERESTS.map(i => i.id), fx.keys);
  for (const k of fx.keys) assert.ok(CATEGORY_EMOJI[k], k);
});

test('which types shape the form', () => {
  for (const [k, v] of Object.entries(fx.shaped)) assert.equal(isShaped(profileFor(k)), v, k);
});

test('required fields are known create fields', () => {
  for (const k of TYPE_KEYS) {
    for (const f of requiredFields(profileFor(k))) {
      assert.ok(FIELD_ORDER.includes(f), `${k}: ${f}`);
      assert.notEqual(stepOfField(f), null, `${k}: ${f}`);
    }
  }
});

for (const c of fx.cleanDetails) test(`cleanDetails: ${c.case}`, () => assert.deepEqual(cleanDetails(profileFor(c.type), c.raw), c.expect));
for (const c of fx.droppedDetailTypes) test(`droppedDetailTypes: ${c.case}`, () => assert.deepEqual(droppedDetailTypes(c.primary, c.draft), c.expect));
for (const c of fx.detailFacts) test(`detailFacts: ${c.case}`, () => assert.deepEqual(detailFacts(profileFor(c.type), c.details, c.lang), c.expect));
for (const c of fx.cardLine) {
  test(`cardLine: ${c.case}`, () => assert.equal(cardLine(profileFor(c.type), { capacity: c.capacity, details: c.details }, c.lang), c.expect));
}
for (const c of fx.homeFilter) {
  test(`homeFilter: ${c.case}`, () => assert.equal(matchesHomeFilter(filterById(c.type, c.filter), c.details), c.expect));
}
for (const c of fx.keywordSuggestions) {
  test(`keywordSuggestions: ${c.case}`, () => {
    const { type, lang, area, benchmark, typed, dismissed } = c;
    assert.deepEqual(keywordSuggestions({ profile: profileFor(type), lang, area, benchmark, typed, dismissed }), c.expect);
  });
}
for (const c of fx.search) {
  test(`search: ${c.case}`, () => {
    const doc = buildEventSearchDoc({ name: 'Untitled', catKey: c.catKey, catLabel: '' });
    assert.equal(matchesSearchQuery(doc, c.query), c.expect);
  });
}

// Home with type chips: the same vectors drive apps/ios/BanbeAppTests/EventTypesTests.swift.
const disc = fx.discovery;
const discItems = disc.items.map(i => ({ ...i, startsAt: null, priceVnd: null, booked: null, capacity: null, soldOut: false }));
for (const c of disc.cases) {
  test(`discovery: ${c.case}`, () => {
    assert.deepEqual(applyDiscoveryFilters(discItems, c.filters, 0).map(i => i.key), c.expect);
    assert.equal(activeFilterCount(c.filters), c.badge);
  });
}
test('discovery: chip counts are what tapping would give', () => {
  assert.deepEqual(optionCounts(discItems, disc.counts.filters, 'typeFilters', disc.counts.options, 0), disc.counts.expect);
});
test('discovery: dropping the type chips is a relax hint', () => {
  const [h] = relaxationHints(discItems, disc.relax.filters, 0);
  assert.equal(h.id, disc.relax.expect.id);
  assert.equal(h.gain, disc.relax.expect.gain);
});

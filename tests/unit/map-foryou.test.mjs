import test from 'node:test';
import assert from 'node:assert/strict';
import { forYouRankEvents, mapForYouSet, applyForYouFilter, forYouCandidateFromEvent } from '../../src/lib/forYou.js';

const NOW = Date.parse('2026-10-07T00:00:00Z');
const day = (n) => new Date(NOW + n * 86400000).toISOString();
const PREFS = { interests: ['music', 'gallery'], budget: { tier: 'medium', currency: 'VND' } };
// Home-shaped (key) and Map-shaped (id) views of the same raw rows.
const RAW = [
  { id: 'a', catKey: 'music', priceVnd: 150000, startsAt: day(2), countryCode: 'VN', status: 'live' },
  { id: 'b', catKey: 'fashion', priceVnd: 100000, startsAt: day(3), countryCode: 'VN', status: 'live' },
  { id: 'c', catKey: 'gallery', priceVnd: 0, startsAt: day(1), countryCode: 'VN', status: 'live' },
  { id: 'd', catKey: 'music', priceVnd: 900000, startsAt: day(4), countryCode: 'VN', status: 'live' }, // over medium cap
  { id: 'e', catKey: 'music', priceVnd: 100000, startsAt: day(5), countryCode: 'VN', status: 'live', soldOut: true },
  { id: 'f', catKey: 'music', priceVnd: 100000, startsAt: day(-1), countryCode: 'VN', status: 'live' }, // already started
];
const home = RAW.map(r => ({ ...r, key: r.id, startsAtRaw: r.startsAt }));

test('Home and Map produce the identical ordered match set (one shared candidate builder)', () => {
  const homeKeys = forYouRankEvents(home, PREFS, true, NOW).map(m => m.key);
  const mapKeys = mapForYouSet(RAW, null, PREFS, true, NOW).ranked.map(m => m.key);
  assert.deepEqual(mapKeys, homeKeys);
  assert.deepEqual(homeKeys, ['a', 'c']);
});

test('no prefs -> empty; area filter is applied before ranking, same as Home', () => {
  assert.deepEqual(mapForYouSet(RAW, null, null, false, NOW).ranked, []);
  const onlyA = mapForYouSet(RAW, e => e.id === 'a', PREFS, true, NOW);
  assert.deepEqual(onlyA.ranked.map(m => m.key), ['a']);
});

test('composes with other filters by AND and never widens the list', () => {
  const { order } = mapForYouSet(RAW, null, PREFS, true, NOW);
  const afterOtherFilters = RAW.filter(e => e.catKey === 'music'); // e.g. category chip
  const out = applyForYouFilter(afterOtherFilters, true, order);
  assert.deepEqual(out.map(e => e.id), ['a']);
  assert.deepEqual(applyForYouFilter(afterOtherFilters, false, order), afterOtherFilters); // off = identity
});

test('pins and list share one set: toggling only changes membership, input is not mutated', () => {
  const { order } = mapForYouSet(RAW, null, PREFS, true, NOW);
  const list = [...RAW];
  const snapshot = list.map(e => e.id);
  const on = applyForYouFilter(list, true, order);
  assert.deepEqual(list.map(e => e.id), snapshot);
  assert.ok(on.every(e => order.has(e.id)));
  assert.equal(on.length, order.size);
});

test('keepOrder keeps distance order instead of rank order', () => {
  const { order } = mapForYouSet(RAW, null, PREFS, true, NOW);
  const byDistance = [RAW[2], RAW[0]]; // c, a (nearest first)
  assert.deepEqual(applyForYouFilter(byDistance, true, order, { keepOrder: true }).map(e => e.id), ['c', 'a']);
  assert.deepEqual(applyForYouFilter(byDistance, true, order).map(e => e.id), ['a', 'c']);
});

test('viewport refresh (Search here) changing the loaded set re-derives matches, empty is honest', () => {
  assert.deepEqual(mapForYouSet([], null, PREFS, true, NOW).ranked, []);
  const cand = forYouCandidateFromEvent({ ...RAW[0], key: 'a' });
  assert.equal(cand.isBookable, true);
  assert.equal(forYouCandidateFromEvent({ ...RAW[4], key: 'e' }).isBookable, false);
});

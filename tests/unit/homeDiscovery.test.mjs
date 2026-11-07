import test from 'node:test';
import assert from 'node:assert/strict';
import {
  dateWindow, fillBadge, applyDiscoveryFilters, activeFilterCount, optionCounts, relaxationHints,
  sortEvents, median, priceHistogram, bucketIndex, DEFAULT_FILTERS, dominantCurrency, pricesIn,
} from '../../src/lib/homeDiscovery.js';

// Mirrored 1:1 by apps/ios/BanbeAppTests/HomeDiscoveryTests.swift — change both together.
// Wednesday 2026-10-21 10:00 in Vietnam (UTC+7) = 03:00Z.
const WED_10 = Date.parse('2026-10-21T03:00:00Z');
const ict = (iso) => Date.parse(iso + '+07:00');

const ev = (key, over = {}) => ({
  key, startsAt: ict('2026-10-21T19:00:00'), priceVnd: 200000, catKeys: ['music'],
  booked: null, capacity: null, soldOut: false, distanceKm: null, popularity: null, ...over,
});

test('today runs from now to local midnight; tomorrow is the next local day', () => {
  assert.deepEqual(dateWindow('today', WED_10), [WED_10, ict('2026-10-22T00:00:00')]);
  assert.deepEqual(dateWindow('tomorrow', WED_10), [ict('2026-10-22T00:00:00'), ict('2026-10-23T00:00:00')]);
});

test('local midnight is computed in UTC+7, not UTC (23:30 local is still today)', () => {
  const late = ict('2026-10-21T23:30:00');
  assert.deepEqual(dateWindow('today', late), [late, ict('2026-10-22T00:00:00')]);
});

test('weekend = Friday 17:00 to Monday 00:00; on Saturday it starts now', () => {
  assert.deepEqual(dateWindow('weekend', WED_10), [ict('2026-10-23T17:00:00'), ict('2026-10-26T00:00:00')]);
  const sat = ict('2026-10-24T11:00:00');
  assert.deepEqual(dateWindow('weekend', sat), [sat, ict('2026-10-26T00:00:00')]);
  const sun = ict('2026-10-25T20:00:00');
  assert.deepEqual(dateWindow('weekend', sun), [sun, ict('2026-10-26T00:00:00')]);
});

test('week and a picked date', () => {
  assert.deepEqual(dateWindow('week', WED_10), [WED_10, WED_10 + 7 * 86400000]);
  assert.deepEqual(dateWindow('on:2026-10-30', WED_10), [ict('2026-10-30T00:00:00'), ict('2026-10-31T00:00:00')]);
  assert.equal(dateWindow('any', WED_10), null);
  assert.equal(dateWindow('on:nope', WED_10), null);
});

test('fill badge: unknown counts give nothing; almost full by seats or share; social proof from 5', () => {
  assert.deepEqual(fillBadge(null, 20), { left: null, almostFull: false, soldOut: false, going: null });
  assert.deepEqual(fillBadge(4, 0), { left: null, almostFull: false, soldOut: false, going: null });
  assert.deepEqual(fillBadge(17, 20), { left: 3, almostFull: true, soldOut: false, going: 17 });
  assert.deepEqual(fillBadge(40, 50), { left: 10, almostFull: true, soldOut: false, going: 40 });
  assert.deepEqual(fillBadge(4, 20), { left: 16, almostFull: false, soldOut: false, going: null });
  assert.deepEqual(fillBadge(20, 20), { left: 0, almostFull: false, soldOut: true, going: 20 });
  assert.deepEqual(fillBadge(25, 20), { left: 0, almostFull: false, soldOut: true, going: 25 });
});

const ITEMS = [
  ev('tonight-music', {}),
  ev('fri-late-supper', { startsAt: ict('2026-10-23T20:00:00'), catKeys: ['supper'], priceVnd: 450000, booked: 18, capacity: 20 }),
  ev('fri-noon', { startsAt: ict('2026-10-23T12:00:00'), priceVnd: 0 }),
  ev('sat-free-gallery', { startsAt: ict('2026-10-24T15:00:00'), catKeys: ['gallery'], priceVnd: 0 }),
  ev('sun-soldout', { startsAt: ict('2026-10-25T19:00:00'), soldOut: true, priceVnd: 300000 }),
  ev('next-month', { startsAt: ict('2026-11-20T19:00:00'), priceVnd: 800000, catKeys: ['supper', 'popup'] }),
  ev('demo-no-date', { startsAt: null, priceVnd: null }),
];
const keys = (xs) => xs.map(x => x.key);

test('filters combine; unknown dates/prices never pass a date/price filter', () => {
  assert.equal(applyDiscoveryFilters(ITEMS, DEFAULT_FILTERS, WED_10).length, ITEMS.length);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { date: 'weekend' }, WED_10)), ['fri-late-supper', 'sat-free-gallery', 'sun-soldout']);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { free: true }, WED_10)), ['fri-noon', 'sat-free-gallery']);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { priceMin: 250000, priceMax: 500000 }, WED_10)), ['fri-late-supper', 'sun-soldout']);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { cats: ['supper'] }, WED_10)), ['fri-late-supper', 'next-month']);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { cats: ['popup', 'gallery'] }, WED_10)), ['sat-free-gallery', 'next-month']);
  assert.ok(!keys(applyDiscoveryFilters(ITEMS, { seatsLeft: true }, WED_10)).includes('sun-soldout'));
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { almostFull: true }, WED_10)), ['fri-late-supper']);
  assert.deepEqual(keys(applyDiscoveryFilters(ITEMS, { date: 'weekend', free: true }, WED_10)), ['sat-free-gallery']);
});

test('active filter count', () => {
  assert.equal(activeFilterCount(DEFAULT_FILTERS), 0);
  assert.equal(activeFilterCount({ date: 'today', priceMin: 1, priceMax: 2, cats: ['music'], free: true }), 4);
});

test('option counts equal the length of the list you get by applying that option', () => {
  const filters = { free: true };
  const counts = optionCounts(ITEMS, filters, 'date', ['any', 'today', 'tomorrow', 'weekend', 'week'], WED_10);
  assert.deepEqual(counts, { any: 2, today: 0, tomorrow: 0, weekend: 1, week: 2 });
  for (const [opt, n] of Object.entries(counts)) {
    assert.equal(applyDiscoveryFilters(ITEMS, { ...filters, date: opt }, WED_10).length, n);
  }
  // Category counts ignore the current category pick (so every pill shows what tapping it gives).
  assert.deepEqual(optionCounts(ITEMS, { cats: ['music'] }, 'cats', ['music', 'supper', 'gallery'], WED_10), { music: 4, supper: 2, gallery: 1 });
  assert.deepEqual(optionCounts(ITEMS, { date: 'weekend' }, 'free', null, WED_10), { true: 1 });
});

test('relaxation hints pick the single change that adds the most events', () => {
  const hints = relaxationHints(ITEMS, { date: 'today', free: true }, WED_10);
  // date->any gives 2 (free events), free->off gives 1 (tonight-music): date wins.
  assert.deepEqual(hints.map(h => [h.id, h.gain]), [['date', 2], ['free', 1]]);
  assert.equal(applyDiscoveryFilters(ITEMS, hints[0].filters, WED_10).length, 2);
  assert.deepEqual(relaxationHints(ITEMS, DEFAULT_FILTERS, WED_10), []);
});

test('sorting is stable with nulls last', () => {
  assert.deepEqual(keys(sortEvents(ITEMS, 'soonest')), ['tonight-music', 'fri-noon', 'fri-late-supper', 'sat-free-gallery', 'sun-soldout', 'next-month', 'demo-no-date']);
  assert.deepEqual(keys(sortEvents(ITEMS, 'price')), ['fri-noon', 'sat-free-gallery', 'tonight-music', 'sun-soldout', 'fri-late-supper', 'next-month', 'demo-no-date']);
  const near = [ev('a', { distanceKm: 3 }), ev('b'), ev('c', { distanceKm: 1.2 })];
  assert.deepEqual(keys(sortEvents(near, 'nearest')), ['c', 'a', 'b']);
  const pop = [ev('a', { popularity: 2 }), ev('b', { popularity: 9 }), ev('c'), ev('d', { popularity: 9 })];
  assert.deepEqual(keys(sortEvents(pop, 'popular')), ['b', 'd', 'a', 'c']);
  assert.deepEqual(keys(sortEvents(pop, 'unknown')), ['a', 'b', 'c', 'd']);
});

test('median and histogram', () => {
  assert.equal(median([]), null);
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(priceHistogram([0, 0]), null);
  const h = priceHistogram([100, 200, 200, 300, 0], 4);
  assert.deepEqual(h, { min: 100, max: 300, counts: [1, 0, 2, 1] });
  assert.equal(bucketIndex(h, 100), 0);
  assert.equal(bucketIndex(h, 300), 3);
  assert.equal(bucketIndex(h, 5000), 3);
  assert.deepEqual(priceHistogram([500, 500], 3), { min: 500, max: 500, counts: [2, 0, 0] });
});

test('prices never mix currencies (migration 195: USD rows carry cents)', () => {
  const vnd = ev('vnd', { priceVnd: 200000 });
  const usd = ev('usd', { priceVnd: 1250, currency: 'USD' });
  const freeUsd = ev('free-usd', { priceVnd: 0, currency: 'USD' });
  const list = [vnd, usd, freeUsd];
  // VND bounds (the default) never let a USD price through, however small its number.
  assert.deepEqual(keys(applyDiscoveryFilters(list, { priceMax: 300000 }, WED_10)), ['vnd', 'free-usd']);
  assert.deepEqual(keys(applyDiscoveryFilters(list, { priceMax: 2000, priceCurrency: 'USD' }, WED_10)), ['usd', 'free-usd']);
  assert.equal(dominantCurrency(list), 'VND');
  assert.equal(dominantCurrency([usd, freeUsd]), 'USD');
  assert.equal(dominantCurrency([freeUsd]), 'VND');
  assert.deepEqual(pricesIn(list, 'VND'), [200000, 0]);
  assert.deepEqual(pricesIn(list, 'USD'), [1250, 0]);
  // Price sort: free first, then VND, then USD.
  assert.deepEqual(keys(sortEvents([usd, vnd, freeUsd], 'price')), ['free-usd', 'vnd', 'usd']);
});

// Note 66 follow-up: the restored Home category row counts with the SAME predicate the feed renders with. Shared
// fixture tests/fixtures/event-types.json `categoryRow` (iOS HomeDiscoveryTests mirrors it).
import { readFileSync } from 'node:fs';
import { categoryCounts, categoryRowKeys } from '../../src/lib/homeDiscovery.js';
const catFx = JSON.parse(readFileSync(new URL('../fixtures/event-types.json', import.meta.url), 'utf8')).categoryRow;
const CAT_KEYS = Object.keys(catFx.counts).filter(k => k !== 'all');
const catItems = catFx.items.map(i => ({ ...i, startsAt: null, priceVnd: null, booked: null, capacity: null, soldOut: false }));

test('category row: every count equals the results tapping that category renders', () => {
  for (const f of catFx.parityFilters) {
    const counts = categoryCounts(catItems, f, CAT_KEYS, 0);
    for (const k of CAT_KEYS) {
      assert.equal(counts[k], applyDiscoveryFilters(catItems, { ...f, cats: [k], typeFilters: [] }, 0).length, `${k} with ${JSON.stringify(f)}`);
    }
    assert.equal(counts.all, applyDiscoveryFilters(catItems, { ...f, cats: [], typeFilters: [] }, 0).length, `all with ${JSON.stringify(f)}`);
  }
});

test('category row: All first, most first, zero-count hidden unless selected', () => {
  for (const f of catFx.parityFilters) {
    const counts = categoryCounts(catItems, f, CAT_KEYS, 0);
    const row = categoryRowKeys(counts, CAT_KEYS, f.cats);
    assert.equal(row[0], 'all');
    const rest = row.slice(1);
    for (const k of rest) assert.ok(counts[k] > 0 || f.cats.includes(k), `${k} shown with 0`);
    for (const k of CAT_KEYS) if (counts[k] > 0) assert.ok(rest.includes(k), `${k} missing`);
    const nonSelected = rest.filter(k => counts[k] > 0);
    for (let i = 1; i < nonSelected.length; i++) assert.ok(counts[nonSelected[i - 1]] >= counts[nonSelected[i]], 'most first');
  }
});

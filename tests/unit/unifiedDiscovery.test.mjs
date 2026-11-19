// Note 99: the unified-discovery rules, against the fixture iOS reads too (Lib/UnifiedDiscovery.swift).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as U from '../../src/lib/unifiedDiscovery.js';

const fx = JSON.parse(readFileSync(new URL('../fixtures/unified-discovery.json', import.meta.url), 'utf8'));

test('tabs are the shared time', () => {
  for (const c of fx.tabForDate) assert.equal(U.tabForDate(c.date), c.tab, c.date);
  assert.deepEqual(U.DATE_FOR_TAB, fx.dateForTab);
});

test('type tiles: busiest first, ties in catalogue order', () => {
  for (const c of fx.topTypes) assert.deepEqual(U.topTypes(c.counts, fx.keys, c.n), c.expect);
});

test('the All types tile becomes a picked type that is not a tile', () => {
  for (const c of fx.pickedTileType) assert.equal(U.pickedTileType(c.selected, c.tiles), c.expect);
});

test('type sheet order and search', () => {
  for (const c of fx.typeSheetOrder) assert.deepEqual(U.typeSheetOrder(c.counts, fx.keys, k => k, c.query), c.expect);
  assert.deepEqual(U.typeSheetOrder({}, ['amnhac'], () => 'Âm nhạc', 'am nhac'), ['amnhac'], 'diacritics are folded');
});

test('area bubble glyphs', () => {
  for (const c of fx.areaGlyphs) assert.deepEqual(U.areaGlyphs(c.cats, fx.keys, c.max), { shown: c.shown, more: c.more });
});

test('the Filters badge counts only what Filters owns', () => {
  for (const c of fx.ownedFilterCount) assert.equal(U.ownedFilterCount(c.filters, c.sort), c.expect);
});

import { mapPlottable, mapPoints, anyOutside } from '../../src/lib/unifiedDiscovery.js';
import { inBounds } from '../../src/lib/mapDiscovery.js';
test('mapPlottable keeps only docs with a located map row; unloaded rows keep all', () => {
  const docs = [{ key: 'a' }, { key: 'b' }, { key: 'demo' }];
  const rows = [{ id: 'a', lat: 1, lng: 2 }, { id: 'b', lat: null, lng: null }];
  assert.deepEqual(mapPlottable(docs, rows).map(d => d.key), ['a']);
  assert.equal(mapPlottable(docs, null), docs);
  assert.deepEqual(mapPoints(docs, rows), [{ lat: 1, lng: 2 }]);
  assert.equal(anyOutside([{ lat: 1, lng: 2 }], { north: 3, south: 0, east: 3, west: 0 }, inBounds), false);
  assert.equal(anyOutside([{ lat: 9, lng: 2 }], { north: 3, south: 0, east: 3, west: 0 }, inBounds), true);
  // A demo-catalogue doc matches its live row by slug.
  const slugRows = [{ id: 'uuid-1', slug: 'demo', lat: 4, lng: 5 }];
  assert.deepEqual(mapPlottable(docs, slugRows).map(d => d.key), ['demo']);
  assert.deepEqual(mapPoints([{ key: 'demo' }], slugRows), [{ lat: 4, lng: 5 }]);
});

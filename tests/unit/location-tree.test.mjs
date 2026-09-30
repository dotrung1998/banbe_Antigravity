// Unit coverage for the data-driven location hierarchy (src/lib/locationTree.js,
// migration 112): legacy area-key migration, deterministic node ids,
// dedup-by-event-id counts (never re-summing child counts — same convention
// as src/lib/badges.js), descendant matching, and tree search.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildLocationTree, eventLocationIds, eventMatchesLocation, migrateLegacyAreaKey,
  locationShortLabel, buildLocationSearchIndex, searchLocationTree, LOCATION_ALL,
} from '../../src/lib/locationTree.js';

const EVENTS = [
  { key: 'a', countryCode: 'VN', area: 'Bình Thạnh', neighborhood: 'Khu phố 3' },
  { key: 'b', countryCode: 'VN', area: 'Bình Thạnh' },
  { key: 'c', countryCode: 'VN', area: 'Da Lat', stateProvince: 'Tỉnh Lâm Đồng' },
  { key: 'd', countryCode: 'vn', locationLabel: 'Quận 1' }, // static-catalogue shape
  { key: 'e', area: 'Quận 3' }, // no country_code (never backfilled)
];

test('legacy AREAS keys migrate to the equivalent new node id, never crash', () => {
  assert.equal(migrateLegacyAreaKey('q1'), 'loc:VN|a:Quận 1');
  assert.equal(migrateLegacyAreaKey('thaodien'), 'loc:VN|a:Thảo Điền');
  assert.equal(migrateLegacyAreaKey('binhthanh'), 'loc:VN|a:Bình Thạnh');
  assert.equal(migrateLegacyAreaKey('other'), 'loc:VN');
  assert.equal(migrateLegacyAreaKey('danang'), 'loc:VN|a:Đà Nẵng');
  assert.equal(migrateLegacyAreaKey('all'), LOCATION_ALL);
  assert.equal(migrateLegacyAreaKey(undefined), LOCATION_ALL);
  assert.equal(migrateLegacyAreaKey('garbage'), LOCATION_ALL);
  // already-new ids pass through untouched
  assert.equal(migrateLegacyAreaKey('loc:US|s:California'), 'loc:US|s:California');
});

test('a migrated legacy key actually matches that district\'s events', () => {
  assert.ok(eventMatchesLocation(EVENTS[3], migrateLegacyAreaKey('q1')));
  assert.ok(eventMatchesLocation(EVENTS[0], migrateLegacyAreaKey('binhthanh')));
  assert.ok(!eventMatchesLocation(EVENTS[2], migrateLegacyAreaKey('binhthanh')));
});

test('node ids are deterministic composites of raw values, not labels/indexes', () => {
  assert.deepEqual(eventLocationIds(EVENTS[0]), ['loc:VN', 'loc:VN|a:Bình Thạnh', 'loc:VN|a:Bình Thạnh|n:Khu phố 3']);
  assert.deepEqual(eventLocationIds(EVENTS[2]), ['loc:VN', 'loc:VN|s:Tỉnh Lâm Đồng', 'loc:VN|s:Tỉnh Lâm Đồng|a:Da Lat']);
  assert.deepEqual(eventLocationIds({ key: 'u', countryCode: 'US', stateProvince: 'California', city: 'San Francisco', neighborhood: 'Mission' }),
    ['loc:US', 'loc:US|s:California', 'loc:US|s:California|c:San Francisco', 'loc:US|s:California|c:San Francisco|n:Mission']);
});

test('VN and US roots always exist, US honestly empty with no US data', () => {
  const tree = buildLocationTree(EVENTS);
  assert.equal(tree.roots[0].id, 'loc:VN');
  assert.equal(tree.roots[1].id, 'loc:US');
  assert.equal(tree.byId.get('loc:US').count, 0);
  assert.equal(tree.byId.get('loc:US').children.length, 0);
  assert.equal(buildLocationTree([]).roots.length, 2);
});

test('parent counts dedupe by event id, never sum child counts', () => {
  // the same event listed twice (e.g. static + real feeds overlapping)
  const tree = buildLocationTree([...EVENTS, EVENTS[0]]);
  assert.equal(tree.byId.get('loc:VN|a:Bình Thạnh').count, 2); // a + b, "a" once
  assert.equal(tree.byId.get('loc:VN|a:Bình Thạnh|n:Khu phố 3').count, 1);
  assert.equal(tree.byId.get('loc:VN').count, 4); // a, b, c, d — not 2+1+1+... re-summed
});

test('selecting a parent matches all descendants; "all" matches everything', () => {
  assert.ok(eventMatchesLocation(EVENTS[0], 'loc:VN'));
  assert.ok(eventMatchesLocation(EVENTS[2], 'loc:VN|s:Tỉnh Lâm Đồng'));
  assert.ok(!eventMatchesLocation(EVENTS[0], 'loc:US'));
  assert.ok(EVENTS.every(e => eventMatchesLocation(e, LOCATION_ALL)));
});

test('short header label is node + immediate parent, not a full breadcrumb', () => {
  assert.equal(locationShortLabel('loc:VN|a:Bình Thạnh', 'vi'), 'Bình Thạnh, Việt Nam');
  assert.equal(locationShortLabel('loc:VN|a:Bình Thạnh|n:Khu phố 3', 'vi'), 'Khu phố 3, Bình Thạnh');
  assert.equal(locationShortLabel('loc:US', 'en'), 'United States');
});

test('tree search is accent-insensitive and reveals ancestors only', () => {
  const tree = buildLocationTree(EVENTS);
  const index = buildLocationSearchIndex(tree);
  const r = searchLocationTree(tree, index, 'binh thanh');
  assert.ok(r.matchIds.has('loc:VN|a:Bình Thạnh'));
  assert.ok(r.revealIds.has('loc:VN'));
  assert.ok(!r.revealIds.has('loc:VN|a:Bình Thạnh'));
  assert.ok(searchLocationTree(tree, index, 'hoa ky').matchIds.has('loc:US'));
  assert.equal(searchLocationTree(tree, index, '   '), null);
});

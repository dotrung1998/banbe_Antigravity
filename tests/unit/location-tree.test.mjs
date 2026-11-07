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

// ---- Map v6 (note 74): the VN city level (from src/data/cities.json, no DB change) ----
import { resolveCitylessId, locationNodeLabel, eventCity, cityOfNode } from '../../src/lib/locationTree.js';

const HCM_Q1 = { key: 'h1', countryCode: 'VN', area: 'Quận 1', lat: 10.776, lng: 106.70 }; // HCMC rows have no state
const HCM_Q3 = { key: 'h3', countryCode: 'VN', area: 'Quận 3', lat: 10.78, lng: 106.68, neighborhood: 'Phường 6' };
const HANOI = { key: 'hn', countryCode: 'VN', stateProvince: 'Thành phố Hà Nội', area: 'Hoàn Kiếm', lat: 21.03, lng: 105.85 };
const DALAT_BY_COLUMN = { key: 'dl', countryCode: 'VN', stateProvince: 'Tỉnh Lâm Đồng', city: 'Đà Lạt', area: 'Đà Lạt' };

test('an HCMC row without a state hangs under the city: loc:VN|c:TP. Hồ Chí Minh|a:Quận 1', () => {
  assert.deepEqual(eventLocationIds(HCM_Q1), ['loc:VN', 'loc:VN|c:TP. Hồ Chí Minh', 'loc:VN|c:TP. Hồ Chí Minh|a:Quận 1']);
  assert.deepEqual(eventLocationIds(HCM_Q3).slice(-1), ['loc:VN|c:TP. Hồ Chí Minh|a:Quận 3|n:Phường 6']);
  assert.equal(eventCity(HCM_Q1).id, 'vn-hcm');
  const tree = buildLocationTree([HCM_Q1, HCM_Q3]);
  const city = tree.byId.get('loc:VN|c:TP. Hồ Chí Minh');
  assert.equal(city.count, 2);
  assert.deepEqual(city.children.map(n => n.value).sort(), ['Quận 1', 'Quận 3']);
  assert.ok(eventMatchesLocation(HCM_Q3, 'loc:VN|c:TP. Hồ Chí Minh'));
});

test('a state that already names the city is not repeated (Thành phố Hà Nội has no Hà Nội under it)', () => {
  assert.deepEqual(eventLocationIds(HANOI), ['loc:VN', 'loc:VN|s:Thành phố Hà Nội', 'loc:VN|s:Thành phố Hà Nội|a:Hoàn Kiếm']);
});

test('the city comes from the city column too, and an area equal to the city is skipped', () => {
  assert.deepEqual(eventLocationIds(DALAT_BY_COLUMN), ['loc:VN', 'loc:VN|s:Tỉnh Lâm Đồng', 'loc:VN|s:Tỉnh Lâm Đồng|c:Đà Lạt']);
});

test('US keeps its raw city column; rows with no city or position keep the old path', () => {
  assert.deepEqual(eventLocationIds({ key: 'u', countryCode: 'US', stateProvince: 'California', city: 'San Francisco', lat: 37.77, lng: -122.42 }),
    ['loc:US', 'loc:US|s:California', 'loc:US|s:California|c:San Francisco']);
  assert.deepEqual(eventLocationIds(EVENTS[1]), ['loc:VN', 'loc:VN|a:Bình Thạnh']);
});

test('city node labels follow the language; the search finds the English name', () => {
  const tree = buildLocationTree([HCM_Q1]);
  const node = tree.byId.get('loc:VN|c:TP. Hồ Chí Minh');
  assert.equal(locationNodeLabel(node, 'vi'), 'TP. Hồ Chí Minh');
  assert.equal(locationNodeLabel(node, 'en'), 'Ho Chi Minh City');
  assert.equal(locationShortLabel('loc:VN|c:TP. Hồ Chí Minh|a:Quận 1', 'en'), 'Quận 1, Ho Chi Minh City');
  assert.ok(searchLocationTree(tree, buildLocationSearchIndex(tree), 'ho chi minh city').matchIds.has(node.id));
  assert.equal(cityOfNode(node.id).id, 'vn-hcm');
  assert.equal(cityOfNode('loc:VN|c:TP. Hồ Chí Minh|a:Quận 1'), null);
});

test('a legacy id without the city maps to the one node with the same tail plus a city', () => {
  const tree = buildLocationTree([HCM_Q1, HCM_Q3, ...EVENTS]);
  assert.equal(resolveCitylessId('loc:VN|a:Quận 1', tree), 'loc:VN|a:Quận 1'); // EVENTS[3] has no position: the old node still exists
  const cityOnly = buildLocationTree([HCM_Q1, HCM_Q3]);
  assert.equal(resolveCitylessId('loc:VN|a:Quận 1', cityOnly), 'loc:VN|c:TP. Hồ Chí Minh|a:Quận 1');
  assert.equal(resolveCitylessId('loc:VN|a:Quận 3|n:Phường 6', cityOnly), 'loc:VN|c:TP. Hồ Chí Minh|a:Quận 3|n:Phường 6');
  assert.equal(migrateLegacyAreaKey('q1', cityOnly), 'loc:VN|c:TP. Hồ Chí Minh|a:Quận 1');
  assert.equal(migrateLegacyAreaKey('loc:VN|a:Nowhere', cityOnly), 'loc:VN|a:Nowhere'); // no match: unchanged, never guessed
  // Two cities with the same district name: ambiguous, left as is.
  const twoCities = buildLocationTree([HCM_Q1, { key: 'x', countryCode: 'VN', area: 'Quận 1', lat: 21.03, lng: 105.85 }]);
  assert.equal(resolveCitylessId('loc:VN|a:Quận 1', twoCities), 'loc:VN|a:Quận 1');
});

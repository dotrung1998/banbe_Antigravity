import test from 'node:test';
import assert from 'node:assert/strict';
import { ofType, typeCounts, matchesQuery, browseList, browseFilters, browseFilterCount, hostsOf, deckLine, deckFaces, rotateHosts, tintIndex, filterHosts, browseEnd, browseDatesLabel } from '../../src/lib/browse.js';

const now = Date.UTC(2026, 10, 13, 5, 0);
const day = 864e5;
const item = (key, cat, org, extra = {}) => ({
  key, catKeys: [cat, extra.cat2].filter(Boolean), startsAt: now + (extra.d ?? 2) * day, priceVnd: extra.price ?? 200000, currency: 'VND',
  booked: null, capacity: null, soldOut: false, details: {},
  ev: { key, name: extra.name || key, area: extra.area || 'Quận 1', catDisplay: cat, organizerId: org && `org_${org}`, organizerName: org || '', organizerAvatarUrl: extra.avatar || '' },
});
const ITEMS = [
  item('bepnho', 'supper', 'Bếp Nhỏ', { name: 'Bếp Nhỏ №12', area: 'Bình Thạnh' }),
  item('banrieng', 'supper', 'Bếp Nhỏ', { price: 0 }),
  item('jazzgac', 'music', 'Gác', { avatar: 'https://x/gac.jpg' }),
  item('orbit', 'fashion', "Rue Miche L'Édition", { cat2: 'music' }),
  item('demo', 'gallery', null),
];

test('type filter counts the second category', () => {
  assert.equal(ofType(ITEMS, 'all').length, 5);
  assert.deepEqual(ofType(ITEMS, 'music').map(i => i.key), ['jazzgac', 'orbit']);
  assert.deepEqual(typeCounts(ITEMS), { supper: 2, music: 2, fashion: 1, gallery: 1 });
});

test('search is accent-insensitive over title, host, area and type', () => {
  assert.ok(matchesQuery(ITEMS[0], 'bep nho'));
  assert.ok(matchesQuery(ITEMS[0], 'BÌNH thạnh'));
  assert.ok(matchesQuery(ITEMS[2], 'gac'));
  assert.ok(matchesQuery(ITEMS[3], 'edition'));
  assert.ok(!matchesQuery(ITEMS[2], 'phở'));
  assert.ok(matchesQuery(ITEMS[2], '  '));
});

test('Browse filters never filter by category, and the list says how many the filters hide', () => {
  assert.deepEqual(browseFilters({ cats: ['music'], date: 'weekend' }).cats, []);
  const r = browseList({ items: ITEMS, type: 'supper', query: '', filters: { free: true }, now });
  assert.deepEqual(r.list.map(i => i.key), ['banrieng']);
  assert.equal(r.hidden, 1);
  assert.equal(browseFilterCount({ free: true, seatsLeft: true, cats: ['music'] }), 2);
  assert.equal(browseFilterCount(null), 0);
});

test('host deck: busiest first, real hosts only, names line and +N', () => {
  const hosts = hostsOf(ITEMS, 'en');
  assert.deepEqual(hosts.map(h => h.name), ['Bếp Nhỏ', 'Gác', "Rue Miche L'Édition"]);
  assert.equal(hosts[0].events.length, 2);
  assert.equal(hosts[1].avatarUrl, 'https://x/gac.jpg');
  assert.deepEqual(deckLine(hosts).more.en, 'and 1 more host');
  assert.equal(deckLine(hosts).names.en, 'Bếp Nhỏ, Gác');
  assert.equal(deckLine(hosts.slice(0, 1)).more.en, 'hosts every event here');
  assert.equal(deckLine([]).names.en, 'No hosts yet');
  const six = Array.from({ length: 6 }, (_, i) => ({ id: `o${i}`, name: `H${i}`, events: [] }));
  assert.deepEqual(deckFaces(six), { faces: six.slice(0, 4), more: 2 });
  assert.deepEqual(rotateHosts(six).map(h => h.id), ['o1', 'o2', 'o3', 'o4', 'o5', 'o0']);
  assert.equal(tintIndex('Gác', 4), tintIndex('Gác', 4));
  assert.deepEqual(filterHosts(hosts, 'bep').map(h => h.name), ['Bếp Nhỏ']);
});

test('end cards: filters, search, all types, one type (no Notify me)', () => {
  const others = [{ key: 'music', name: { vi: 'Nhạc', en: 'Music' }, count: 8 }, { key: 'gallery', name: { vi: 'Phòng tranh', en: 'Gallery' }, count: 5 }];
  const sup = { vi: 'Supper club', en: 'Supper club' };
  assert.equal(browseEnd({ type: 'supper', typeName: sup, list: [1, 2], hidden: 3, query: '', others }).title.en, '3 more are just outside your filters.');
  const s = browseEnd({ type: 'supper', typeName: sup, list: [1], hidden: 0, query: 'phở', others });
  assert.equal(s.kind, 'search');
  assert.deepEqual(s.actions.map(a => a.act), ['clear-search', 'type:all']);
  assert.equal(browseEnd({ type: 'all', typeName: null, list: [1], hidden: 0, query: '', others }).actions[0].act, 'host');
  const t = browseEnd({ type: 'supper', typeName: sup, list: [1], hidden: 0, query: '', others });
  assert.equal(t.title.en, 'Still curious? Music has 8 on.');
  assert.deepEqual(t.actions.map(a => a.act), ['type:music', 'type:gallery', 'type:all']);
  for (const c of [s, t]) {
    const all = [c.eyebrow, c.title, c.body, ...c.actions.map(a => a.label)].flatMap(x => [x.vi, x.en]).join(' | ');
    assert.doesNotMatch(all, /—|;| - /);
    assert.ok(!c.actions.some(a => a.act === 'nudge'));
  }
});

test('the line under a tab title names its real dates (Vietnam clock)', () => {
  const monday = Date.UTC(2026, 10, 16, 1, 0); // 2026-11-16 08:00 +07
  assert.equal(browseDatesLabel('weekend', monday, 'en'), 'Fri 20 – Sun 22 Nov');
  assert.equal(browseDatesLabel('weekend', monday, 'vi'), 'T6 20/11 – CN 22/11');
  assert.equal(browseDatesLabel('tonight', monday, 'en'), 'Mon 16 Nov');
  assert.equal(browseDatesLabel('all', monday, 'en'), null);
  assert.equal(browseDatesLabel('weekend', monday + 6 * 86400000, 'en'), 'Sun 22 Nov');
});

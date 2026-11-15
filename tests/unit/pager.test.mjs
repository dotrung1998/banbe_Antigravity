import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { paginate, pageRange, endCardRoom, showPageNav, inkFrames, pageAt, clampPage, pageWindow, PAGE_SIZE } from '../../src/lib/pager.js';
import { shortlistEnd, slimmed } from '../../src/lib/listEnd.js';

const fixture = JSON.parse(readFileSync(new URL('../fixtures/pager.json', import.meta.url), 'utf8'));
const ids = n => Array.from({ length: n }, (_, i) => `e${i + 1}`);

test('four rows a page', () => {
  assert.equal(PAGE_SIZE, 4);
  for (const c of fixture.pages) assert.deepEqual(paginate(ids(c.n)).map(p => p.length), c.sizes, `n=${c.n}`);
});

test('range line', () => {
  for (const c of fixture.ranges) {
    const pages = paginate(ids(c.n));
    assert.equal(pageRange(pages, c.page, 'en').text, c.en, `n=${c.n} page=${c.page}`);
    assert.equal(pageRange(pages, c.page, 'vi').text, c.vi, `n=${c.n} page=${c.page} vi`);
  }
});

test('end card is sized to the missing rows', () => {
  for (const c of fixture.endCard) assert.deepEqual(endCardRoom(paginate(ids(c.n))), { room: c.room, variant: c.variant }, `n=${c.n}`);
});

test('page navigation only with more than one page', () => {
  assert.equal(showPageNav(paginate(ids(3))), false);
  assert.equal(showPageNav(paginate(ids(4))), false);
  assert.equal(showPageNav(paginate(ids(5))), true);
});

test('ink stretches across both numbers, then settles on the new one', () => {
  assert.deepEqual(inkFrames({ left: 10, width: 44 }, { left: 110, width: 44 }), [
    { left: 10, width: 44 }, { left: 10, width: 144 }, { left: 110, width: 44 }]);
  assert.deepEqual(inkFrames({ left: 110, width: 44 }, { left: 10, width: 44 })[1], { left: 10, width: 144 });
});

test('the nearest page wins and indexes are clamped', () => {
  assert.equal(pageAt(0, 360, 3), 0);
  assert.equal(pageAt(190, 360, 3), 1);
  assert.equal(pageAt(9999, 360, 3), 2);
  assert.equal(pageAt(100, 0, 3), 0);
  assert.equal(clampPage(-2, 3), 0);
  assert.equal(clampPage(5, 0), 0);
});

test('Shortlist end: filters hide some, or the end of the list', () => {
  const f = shortlistEnd({ total: 8, shown: 5, filtersOn: true });
  assert.equal(f.kind, 'filters');
  assert.equal(f.title.en, '3 more are just outside your filters.');
  assert.equal(f.actions[0].act, 'clear-filters');
  assert.equal(f.actions[0].label.en, 'Show all 8');
  const one = shortlistEnd({ total: 6, shown: 5, filtersOn: true });
  assert.equal(one.title.en, '1 more is just outside your filters.');
  // The Shortlist follows the filters, not the hero tab, so the end names the whole list, never a tab.
  const end = shortlistEnd({ total: 3, shown: 3, filtersOn: false });
  assert.equal(end.kind, 'end');
  assert.equal(end.eyebrow.en, '3 events in all');
  assert.equal(end.actions[0].act, 'types');
  // filters on but nothing hidden: plain end of the list
  assert.equal(shortlistEnd({ total: 4, shown: 4, filtersOn: true }).kind, 'end');
  const s = slimmed(f);
  assert.equal(s.body, null);
  assert.equal(s.actions.length, 1);
});

test('end-card copy follows the copy rule (no dash or semicolon between ideas, no fake actions)', () => {
  const cards = [shortlistEnd({ total: 9, shown: 2, filtersOn: true }), shortlistEnd({ total: 2, shown: 2, filtersOn: false })];
  for (const c of cards) {
    const all = [c.eyebrow, c.title, c.body, ...c.actions.map(a => a.label)].flatMap(x => [x.vi, x.en]).join(' | ');
    assert.doesNotMatch(all, /—|;| - /);
    assert.ok(!c.actions.some(a => a.act === 'nudge'), 'no Notify me without a backend');
  }
});

test('at most five page numbers, always around the current page', () => {
  assert.deepEqual(pageWindow(0, 3), [0, 1, 2]);
  assert.deepEqual(pageWindow(0, 8), [0, 1, 2, 3, 4]);
  assert.deepEqual(pageWindow(4, 8), [2, 3, 4, 5, 6]);
  assert.deepEqual(pageWindow(7, 8), [3, 4, 5, 6, 7]);
  assert.deepEqual(pageWindow(6, 8), [3, 4, 5, 6, 7]);
  for (let p = 0; p < 12; p++) assert.ok(pageWindow(p, 12).includes(p));
});

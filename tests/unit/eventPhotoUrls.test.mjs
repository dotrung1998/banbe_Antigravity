// Map v6 (note 74): which photos an event card pages through (src/lib/eventPhotoUrls.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { groupPhotoRows, cardPhotoList, MAX_CARD_PHOTOS } from '../../src/lib/eventPhotoUrls.js';

test('rows group per event in sort order, capped, private paths dropped', () => {
  const rows = [
    { event_id: 'a', storage_path: 'event-photos/a/1.jpg' },
    { event_id: 'b', storage_path: 'event-photos-private/b/1.jpg' },
    { event_id: 'a', storage_path: 'event-photos/a/2.jpg' },
    { event_id: 'a', storage_path: null, r2_ref: 'r2/a/3.jpg' },
    { event_id: 'a', storage_path: null },
  ];
  const g = groupPhotoRows(rows, 2);
  assert.deepEqual(g.a.map(r => r.storage_path || r.r2_ref), ['event-photos/a/1.jpg', 'event-photos/a/2.jpg']);
  assert.equal(g.b, undefined);
  assert.equal(groupPhotoRows(rows, 6, { publicOnly: false }).b.length, 1);
  assert.equal(groupPhotoRows(rows).a.length, 3);
});

test('card list: cover first, no duplicates or blanks, at most six', () => {
  assert.deepEqual(cardPhotoList('c', ['x', 'c', null, 'y']), ['c', 'x', 'y']);
  assert.deepEqual(cardPhotoList(null, ['x']), ['x']);
  assert.deepEqual(cardPhotoList(null, []), []);
  assert.equal(cardPhotoList('c', ['1', '2', '3', '4', '5', '6', '7']).length, MAX_CARD_PHOTOS);
});

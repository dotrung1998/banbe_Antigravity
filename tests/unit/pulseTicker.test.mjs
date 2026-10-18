import test from 'node:test';
import assert from 'node:assert/strict';
import { tickerItems, tickerSeconds, MAX_ITEMS } from '../../src/lib/pulseTicker.js';

// Mirrored by apps/ios/BanbeAppTests/PulseTickerTests.swift — change both together.
const row = (id, name, score = 1) => ({ event_id: id, event_name: name, score });

test('keeps the server order, numbers from 1, and caps the list', () => {
  const items = tickerItems(Array.from({ length: 8 }, (_, i) => row(`e${i}`, `Event ${i}`)));
  assert.equal(items.length, MAX_ITEMS);
  assert.deepEqual(items.map(i => i.rank), [1, 2, 3, 4, 5]);
  assert.deepEqual(items.map(i => i.name), ['Event 0', 'Event 1', 'Event 2', 'Event 3', 'Event 4']);
});

test('skips rows with no usable name and trims the rest', () => {
  const items = tickerItems([row('a', '  Supper club  '), row('b', ''), row('c', '   '), { event_id: 'd' }, null, row('e', 'Jazz')]);
  assert.deepEqual(items.map(i => [i.id, i.rank, i.name]), [['a', 1, 'Supper club'], ['e', 2, 'Jazz']]);
});

test('empty or missing input gives no items', () => {
  assert.deepEqual(tickerItems([]), []);
  assert.deepEqual(tickerItems(null), []);
  assert.deepEqual(tickerItems(undefined), []);
});

test('speed: proportional to the text, with a floor so short lists are never frantic', () => {
  const short = tickerItems([row('a', 'Jazz')]);
  assert.equal(tickerSeconds(short), 14);
  const long = tickerItems(Array.from({ length: 5 }, (_, i) => row(`e${i}`, 'x'.repeat(40))));
  // 5 * (40 + 4) = 220 chars * 0.26 = 57.2 -> 57
  assert.equal(tickerSeconds(long), 57);
  assert.ok(tickerSeconds(long) > tickerSeconds(short));
  assert.equal(tickerSeconds([]), 14);
});

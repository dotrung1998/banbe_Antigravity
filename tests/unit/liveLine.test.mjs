import test from 'node:test';
import assert from 'node:assert/strict';
import { liveUpdates, liveSeconds, stepIndex, FEW_SEATS } from '../../src/lib/liveLine.js';

const PULSE = [
  { event_id: 'bepnho', event_name: 'Bếp Nhỏ №12', organizer_name: 'Bếp Nhỏ', booking_count: 2 },
  { event_id: 'jazzgac', event_name: 'Jazz Ở Gác', organizer_name: 'Gác', booking_count: 3 },
  { event_id: 'orbit', event_name: 'ORBIT: Afterlight', organizer_name: "Rue Miche L'Édition", booking_count: 0 },
  { event_id: 'gone', event_name: 'Ended thing', booking_count: 9 },
  { event_id: 'x', event_name: '  ', booking_count: 1 },
];
const FACTS = { bepnho: { seatsLeft: 2, when: 'SAT 21/11 · 19:00' }, jazzgac: { seatsLeft: 12, when: 'SUN 15/11 · 21:00' }, orbit: { seatsLeft: null, when: 'TMRW · 20:00' } };
const lookup = id => FACTS[id] || null;

test('updates are real: summary, few seats, bookings today, otherwise trending', () => {
  const u = liveUpdates({ pulse: PULSE, lookup, tonight: 3, weekend: 9 });
  assert.deepEqual(u.map(x => x.kind), ['summary', 'seats', 'booked', 'trending']);
  assert.equal(u[0].text.en, '3 events on tonight');
  assert.equal(u[0].eventId, null);
  assert.equal(u[1].text.en, 'Only 2 seats left at Bếp Nhỏ №12');
  assert.equal(u[1].when, 'SAT 21/11 · 19:00');
  assert.equal(u[2].text.en, '3 bookings for Jazz Ở Gác today');
  assert.equal(u[3].text.en, "ORBIT: Afterlight by Rue Miche L'Édition is getting attention");
  assert.ok(!u.some(x => x.eventId === 'gone'), 'events Home does not list are not shown');
});

test('summary falls back to the weekend, then to nothing', () => {
  assert.equal(liveUpdates({ pulse: [], lookup, tonight: 0, weekend: 1 })[0].text.en, '1 event this weekend');
  assert.deepEqual(liveUpdates({ pulse: [], lookup, tonight: 0, weekend: 0 }), []);
});

test('at most eight updates, singular forms, seat threshold', () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ event_id: `e${i}`, event_name: `E${i}`, booking_count: 1 }));
  const u = liveUpdates({ pulse: many, lookup: () => ({ seatsLeft: null, when: 'x' }), tonight: 2 });
  assert.equal(u.length, 8);
  assert.equal(u[1].text.en, '1 booking for E0 today');
  const one = liveUpdates({ pulse: [{ event_id: 'a', event_name: 'A', booking_count: 0 }], lookup: () => ({ seatsLeft: 1, when: '' }) });
  assert.equal(one[0].text.en, 'Only 1 seat left at A');
  const same = liveUpdates({ pulse: [{ event_id: 'b', event_name: 'Băng Cối', organizer_name: 'Băng Cối', booking_count: 0 }], lookup: () => ({ seatsLeft: null, when: '' }) });
  assert.equal(same[0].text.en, 'Băng Cối is getting attention');
  const six = liveUpdates({ pulse: [{ event_id: 'a', event_name: 'A', booking_count: 0 }], lookup: () => ({ seatsLeft: FEW_SEATS + 1, when: '' }) });
  assert.equal(six[0].kind, 'trending');
});

test('copy rule and speed', () => {
  const u = liveUpdates({ pulse: PULSE, lookup, tonight: 2 });
  for (const x of u) assert.doesNotMatch(`${x.text.vi} | ${x.text.en}`, /—|;| - /);
  assert.ok(liveSeconds(['a']) >= 16);
  assert.ok(liveSeconds(u.map(x => x.text.en)) >= liveSeconds(['short']));
  assert.equal(stepIndex(0, -1, 5), 0);
  assert.equal(stepIndex(4, 1, 5), 4);
  assert.equal(stepIndex(2, 1, 5), 3);
  assert.equal(stepIndex(0, 1, 0), 0);
});

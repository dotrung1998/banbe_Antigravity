import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  ONCE_KEYS, onceKey, seenOnce, claimOnce, typicalWaitText, fillText, savedComingUp, nextFromHost, isCheckedIn,
  isNewlyLive, whenLabel,
} from '../../src/lib/quickWins.js';
import { reserveBarState } from '../../src/lib/reserveBar.js';

// Phase 1 quick wins. Every vector in tests/fixtures/quick-wins.json is shared with
// apps/ios/BanbeAppTests/QuickWinsTests.swift — change both together.
const V = JSON.parse(readFileSync(new URL('../fixtures/quick-wins.json', import.meta.url), 'utf8'));

const memoryStorage = () => {
  const m = new Map();
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => { m.set(k, String(v)); }, keys: () => [...m.keys()] };
};

test('ended wins over the ticket; cancelled still wins (shared vectors)', () => {
  for (const v of V.endedPrecedence) {
    const { booking, ticket, cancelled, ended, soldOut } = v;
    assert.equal(reserveBarState({ booking, ticket, cancelled, ended, soldOut, blocked: false }), v.expect, v.case);
  }
});

test('once-only keys match the contract', () => {
  assert.deepEqual(ONCE_KEYS, V.onceKeys);
  assert.equal(onceKey('ticketReveal', 'B1'), V.onceKeys.ticketReveal.replace('<bookingId>', 'b1'));
  assert.equal(onceKey('checkIn', 'b1'), V.onceKeys.checkIn.replace('<bookingId>', 'b1'));
  assert.equal(onceKey('eventLive', 'ev-9'), V.onceKeys.eventLive.replace('<eventId>', 'ev-9'));
  assert.equal(onceKey('ticketReveal', ''), null);
  assert.equal(onceKey('nope', 'x'), null);
});

test('a celebration fires once per milestone per device, and never on a broken storage', () => {
  const st = memoryStorage();
  assert.equal(seenOnce('ticketReveal', 'b1', st), false);
  assert.equal(claimOnce('ticketReveal', 'b1', st), true);
  assert.equal(claimOnce('ticketReveal', 'b1', st), false);
  assert.equal(seenOnce('ticketReveal', 'b1', st), true);
  // Another booking / another milestone is its own moment.
  assert.equal(claimOnce('ticketReveal', 'b2', st), true);
  assert.equal(claimOnce('checkIn', 'b1', st), true);
  const broken = { getItem: () => { throw new Error('blocked'); }, setItem: () => { throw new Error('blocked'); } };
  assert.equal(claimOnce('eventLive', 'e1', broken), false);
  assert.equal(seenOnce('eventLive', 'e1', broken), true);
});

test('typical host wait reads as a person would say it (shared vectors)', () => {
  for (const v of V.typicalWait) {
    const got = typicalWaitText(v.minutes);
    if (v.vi == null) assert.equal(got, null, JSON.stringify(v));
    else assert.deepEqual(got, { vi: v.vi, en: v.en }, JSON.stringify(v));
  }
  assert.equal(typicalWaitText(-3), null);
  assert.equal(typicalWaitText(58).en, 'This host usually confirms within about 1 hour.');
  assert.equal(typicalWaitText(1430).en, 'This host usually confirms within about 1 day.');
});

test('fill text is real fill or nothing (shared vectors)', () => {
  for (const v of V.fillText) {
    const got = fillText(v.capacity, v.booked);
    if (v.vi == null) assert.equal(got, null, JSON.stringify(v));
    else assert.deepEqual(got, { vi: v.vi, en: v.en }, JSON.stringify(v));
  }
});

test('saved row: live, ahead, within 30 days, soonest first, at most 5 (shared vectors)', () => {
  const r = V.savedRow;
  const got = savedComingUp(r.events, r.now, { maxItems: r.maxItems, withinDays: r.withinDays });
  assert.deepEqual(got.map(e => e.key), r.expect);
  // The defaults are the contract's numbers.
  assert.deepEqual(savedComingUp(r.events, Date.parse(r.now)).map(e => e.key), r.expect);
  assert.deepEqual(savedComingUp([], r.now), []);
});

test('next from this host: the host’s other live events ahead, at most 3', () => {
  const now = '2027-03-01T03:00:00Z';
  const rows = [
    { key: 'this', status: 'live', startsAt: '2027-03-02T12:00:00Z' },
    { key: 'd', status: 'live', startsAt: '2027-04-02T12:00:00Z' },
    { key: 'a', status: 'live', startsAt: '2027-03-03T12:00:00Z' },
    { key: 'gone', status: 'ended', startsAt: '2027-03-03T12:00:00Z' },
    { key: 'past', status: 'live', startsAt: '2027-02-03T12:00:00Z' },
    { key: 'b', status: 'live', startsAt: '2027-03-04T12:00:00Z' },
    { key: 'c', status: 'live', startsAt: '2027-03-05T12:00:00Z' },
  ];
  assert.deepEqual(nextFromHost(rows, now, 'this').map(r => r.key), ['a', 'b', 'c']);
  assert.deepEqual(nextFromHost([], now, 'this'), []);
});

test('checked in: an attended booking or a scanned named ticket', () => {
  assert.equal(isCheckedIn(null), false);
  assert.equal(isCheckedIn({ id: 'b', status: 'confirmed' }), false);
  assert.equal(isCheckedIn({ id: 'b', status: 'attended' }), true);
  assert.equal(isCheckedIn({ id: 'b', status: 'confirmed' }, [{ booking_id: 'b', checked_in_at: '2027-03-01T12:00:00Z' }]), true);
  assert.equal(isCheckedIn({ id: 'b', status: 'confirmed' }, [{ booking_id: 'other', checked_in_at: '2027-03-01T12:00:00Z' }]), false);
});

test('newly live: approved within 7 days and still ahead', () => {
  const now = Date.parse('2027-03-10T00:00:00Z');
  assert.equal(isNewlyLive({ status: 'live', reviewedAt: '2027-03-09T00:00:00Z', startsAt: '2027-03-20T00:00:00Z' }, now), true);
  assert.equal(isNewlyLive({ status: 'live', reviewedAt: '2027-02-20T00:00:00Z', startsAt: '2027-03-20T00:00:00Z' }, now), false);
  assert.equal(isNewlyLive({ status: 'live', reviewedAt: '2027-03-09T00:00:00Z', startsAt: '2027-03-09T12:00:00Z' }, now), false);
  assert.equal(isNewlyLive({ status: 'review', reviewedAt: null, startsAt: '2027-03-20T00:00:00Z' }, now), false);
});

test('when label in the venue zone', () => {
  assert.equal(whenLabel('2027-03-05T12:00:00Z', 'Asia/Ho_Chi_Minh'), 'Th 6, 05.03 · 19:00');
  assert.equal(whenLabel('2027-03-05T12:00:00Z', null, true), 'Fri, 05.03 · 19:00');
  assert.equal(whenLabel(null), '');
});

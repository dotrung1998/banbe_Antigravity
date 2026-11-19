import test from 'node:test';
import assert from 'node:assert/strict';
import { eventEndsAt, isEventOver, OVER_FALLBACK_MS } from '../../src/lib/eventEnd.js';

// Audit 2026-11-19 row 6: ONE "is this event over" rule for every surface.
// Venue zone Asia/Ho_Chi_Minh = UTC+7 (no DST), so these instants are exact.
const TZ = 'Asia/Ho_Chi_Minh';
const at = (iso) => Date.parse(iso);

test('a host-set end time decides, in the venue zone', () => {
  const ev = { startsAt: '2026-11-19T12:00:00.000Z', tz: TZ, endTime: '21:00:00' }; // 19:00–21:00 ICT
  assert.equal(eventEndsAt(ev), at('2026-11-19T14:00:00.000Z'));
  assert.equal(isEventOver(ev, at('2026-11-19T13:59:00.000Z')), false);
  assert.equal(isEventOver(ev, at('2026-11-19T14:00:00.000Z')), true);
});

test('an end at or before the start means the next venue day', () => {
  const ev = { startsAt: '2026-11-19T15:00:00.000Z', tz: TZ, endTime: '02:00' }; // 22:00 ICT -> 02:00 next day
  assert.equal(eventEndsAt(ev), at('2026-11-19T19:00:00.000Z'));
  assert.equal(isEventOver(ev, at('2026-11-19T18:59:00.000Z')), false);
  assert.equal(isEventOver(ev, at('2026-11-19T19:00:00.000Z')), true);
});

test('open-ended and not-stated fall back to 12h after the start', () => {
  const open = { startsAt: '2026-11-19T12:00:00.000Z', tz: TZ, endOpen: true };
  const unstated = { startsAt: '2026-11-19T12:00:00.000Z', tz: TZ };
  assert.equal(eventEndsAt(open), at('2026-11-19T12:00:00.000Z') + OVER_FALLBACK_MS);
  assert.equal(eventEndsAt(unstated), eventEndsAt(open));
  assert.equal(isEventOver(unstated, at('2026-11-19T23:59:00.000Z')), false);
  assert.equal(isEventOver(unstated, at('2026-11-20T00:00:00.000Z')), true);
});

test('status wins: ended is over, cancelled is not, unknown start is never over', () => {
  assert.equal(isEventOver({ status: 'ended' }, 0), true);
  assert.equal(isEventOver({ status: 'cancelled', startsAt: '2020-01-01T00:00:00Z' }, Date.now()), false);
  assert.equal(isEventOver({ startsAt: null }, Date.now()), false);
  assert.equal(eventEndsAt({}), null);
});

test('snake_case rows from the API read the same', () => {
  const row = { starts_at: '2026-11-19T12:00:00+00:00', tz: TZ, end_time: '21:00:00', end_open: false };
  assert.equal(eventEndsAt(row), at('2026-11-19T14:00:00.000Z'));
  assert.equal(isEventOver(row, at('2026-11-19T14:00:00.000Z')), true);
});

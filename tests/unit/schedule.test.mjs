// Port of iOS SchedulePresentationTests / InAppCalendarStoreTests / CalendarExportTests (notes 44/45).
import test from 'node:test';
import assert from 'node:assert/strict';
import * as S from '../../src/lib/schedulePresentation.js';
import { calendarDraft, buildIcs, googleCalendarUrl, icsText, DEFAULT_DURATION_MS } from '../../src/lib/calendarExport.js';

const en = (_v, e) => e;
const NOW = new Date(2026, 9, 18, 10, 0).getTime(); // Sun 18 Oct 2026, 10:00 local
const H = 3600e3, D = 864e5;
const ev = (key, over = {}) => ({ key, title: key, start: NOW + D, end: null, timeZone: null, location: '', cancelled: false, ended: false, inviteOnly: false, soldOut: false, ...over });
const bk = (eventKey, over = {}) => ({ eventKey, status: 'confirmed', paymentState: 'confirmed', holdExpiresAt: null, giftedAway: false, ...over });
const memory = () => { const m = new Map(); return { getItem: k => m.get(k) ?? null, setItem: (k, v) => m.set(k, v), removeItem: k => m.delete(k) }; };

test('booking sources follow the payment rules', () => {
  assert.equal(S.bookingSource(bk('a'), NOW), 'booked');
  assert.equal(S.bookingSource(bk('a', { paymentState: 'pending_verification' }), NOW), 'awaiting');
  assert.equal(S.bookingSource(bk('a', { paymentState: 'holding', holdExpiresAt: NOW + 60e3 }), NOW), 'holding');
  assert.equal(S.bookingSource(bk('a', { paymentState: 'holding', holdExpiresAt: NOW - 1 }), NOW), null, 'an expired hold is not a plan');
  assert.equal(S.bookingSource(bk('a', { status: 'cancelled' }), NOW), null);
  assert.equal(S.bookingSource(bk('a', { giftedAway: true }), NOW), null, "a gifted ticket is the recipient's plan");
});

test('one row per event, strongest source wins, cancelled and undated handled honestly', () => {
  const events = { a: ev('a'), b: ev('b', { start: NOW + 2 * D }), c: ev('c', { cancelled: true }), d: ev('d', { start: null }), past: ev('past', { start: NOW - 3 * D, ended: true }) };
  const r = S.mySchedule({
    bookings: [bk('a', { paymentState: 'pending_verification' }), bk('a'), bk('c'), bk('past')],
    hostedKeys: ['b', 'd'], addedKeys: ['a', 'b'], events, now: NOW,
  });
  assert.deepEqual(r.items.map(i => [i.id, i.source]), [['past', 'booked'], ['a', 'booked'], ['b', 'hosting']]);
  assert.deepEqual(r.items.find(i => i.id === 'a').sources, ['booked', 'awaiting', 'added']);
  assert.equal(r.undatedCount, 1);
});

test('saved/favorited events are not a source', () => {
  const r = S.mySchedule({ bookings: [], hostedKeys: [], addedKeys: [], events: { a: ev('a') }, now: NOW });
  assert.equal(r.items.length, 0);
});

test('discover: upcoming, reservable, public, not already mine', () => {
  const list = [ev('ok'), ev('mine'), ev('past', { start: NOW - H }), ev('inv', { inviteOnly: true }), ev('sold', { soldOut: true }), ev('cx', { cancelled: true }), ev('early', { start: NOW + H })];
  assert.deepEqual(S.discover(list, new Set(['mine']), NOW).map(e => e.key), ['early', 'ok']);
  assert.equal(S.canAdd(ev('x'), NOW), true);
  assert.equal(S.canAdd(ev('x', { start: NOW - 1 }), NOW), false);
  assert.equal(S.canAdd(ev('x', { start: null }), NOW), false);
});

test('week honours the first weekday; busy days come from real items', () => {
  const wkMon = S.week(new Date(NOW), 1);
  assert.equal(wkMon[0].getDay(), 1);
  assert.equal(wkMon.length, 7);
  assert.ok(wkMon.some(d => S.sameDay(d, new Date(NOW))));
  const wkSun = S.week(new Date(NOW), 0);
  assert.equal(wkSun[0].getDay(), 0);
  const items = [{ event: ev('a', { start: NOW + 2 * H }) }];
  assert.deepEqual([...S.busyDays(wkMon, items)], [S.startOfDay(new Date(NOW)).getTime()]);
});

test('an item occurs on its start day only unless it has a real end', () => {
  const night = ev('n', { start: new Date(2026, 9, 18, 23, 0).getTime() });
  assert.equal(S.occurs(night, new Date(2026, 9, 18)), true);
  assert.equal(S.occurs(night, new Date(2026, 9, 19)), false);
  const overnight = { ...night, end: new Date(2026, 9, 19, 2, 0).getTime() };
  assert.equal(S.occurs(overnight, new Date(2026, 9, 19)), true);
});

test('month grid is whole weeks and the agenda groups by day', () => {
  const grid = S.monthGrid(new Date(2026, 9, 1), 1); // October 2026 starts on a Thursday
  assert.ok(grid.every(r => r.length === 7));
  assert.equal(grid[0][0].date.getDay(), 1);
  assert.equal(grid.flat().filter(d => d.inMonth).length, 31);
  const evs = [ev('a', { start: new Date(2026, 9, 20, 19).getTime() }), ev('b', { start: new Date(2026, 9, 20, 9).getTime() }), ev('x', { start: new Date(2026, 10, 2).getTime() })];
  const agenda = S.monthAgenda(evs, new Date(2026, 9, 1), 1);
  assert.equal(agenda.length, 1);
  assert.deepEqual(agenda[0].events.map(e => e.key), ['b', 'a']);
  assert.equal(S.dayCounts(evs, grid).get(new Date(2026, 9, 20).getTime()), 2);
  assert.equal(S.addMonths(new Date(2026, 11, 15), 1).getFullYear(), 2027);
});

test('proximity only claims overlap with real ends, otherwise "starts within 2 hours"', () => {
  const plans = [{ event: ev('p', { start: NOW + D }) }];
  assert.deepEqual(S.proximity(ev('c', { start: NOW + D + H }), plans), { kind: 'startsNear', count: 1 });
  assert.deepEqual(S.proximity(ev('c', { start: NOW + D + 3 * H }), plans), { kind: 'none', count: 0 });
  const withEnds = [{ event: ev('p', { start: NOW + D, end: NOW + D + 4 * H }) }];
  assert.deepEqual(S.proximity(ev('c', { start: NOW + D + 3 * H, end: NOW + D + 5 * H }), withEnds), { kind: 'overlaps', count: 1 });
  assert.equal(S.proximityText({ kind: 'startsNear', count: 1 }, en), 'Starts within 2 hours of 1 plan');
  assert.equal(S.proximityText({ kind: 'none', count: 0 }, en), null);
});

test('day bucket is analytics-safe', () => {
  const today = new Date(NOW);
  assert.equal(S.dayBucket(S.addDays(today, -1), today), 'past');
  assert.equal(S.dayBucket(today, today), 'today');
  assert.equal(S.dayBucket(S.addDays(today, 7), today), 'next7');
  assert.equal(S.dayBucket(S.addDays(today, 8), today), 'later');
});

test('manual adds: idempotent, per account, removable', () => {
  const st = memory();
  assert.equal(S.scheduleStore.add('e1', 'u1', st, 1), 'added');
  assert.equal(S.scheduleStore.add('e1', 'u1', st, 2), 'alreadyAdded');
  assert.deepEqual(S.scheduleStore.keys('u1', st), ['e1']);
  assert.deepEqual(S.scheduleStore.keys('u2', st), [], 'another account on this browser never sees them');
  S.scheduleStore.remove('e1', 'u1', st);
  assert.deepEqual(S.scheduleStore.keys('u1', st), []);
  assert.deepEqual(S.scheduleStore.keys(null, st), []);
});

// MARK: calendar export

test('calendar draft refuses a missing start and says when the end is estimated', () => {
  assert.equal(calendarDraft({ title: 'x', start: null, eventKey: 'k', origin: 'https://www.banbe.app' }, en), null);
  const d = calendarDraft({ title: 'Jazz', start: NOW, location: '  42 Nguyễn Huệ ', eventKey: 'a b', origin: 'https://www.banbe.app' }, en);
  assert.equal(d.end - d.start, DEFAULT_DURATION_MS);
  assert.equal(d.endIsEstimated, true);
  assert.equal(d.location, '42 Nguyễn Huệ');
  assert.equal(d.url, 'https://www.banbe.app/api/photo-share?eid=a%20b');
  assert.ok(d.notes.includes('filled in 2 hours'));
  const real = calendarDraft({ title: 'x', start: NOW, end: NOW + H, eventKey: 'k', origin: 'o' }, en);
  assert.equal(real.endIsEstimated, false);
});

test('ics is valid, escaped and folded', () => {
  const d = calendarDraft({ title: 'Supper; club, night', start: Date.UTC(2026, 9, 20, 12), location: 'Q1, HCMC', eventKey: 'k', origin: 'https://www.banbe.app' }, en);
  const ics = buildIcs(d, { uid: 'fixed', now: Date.UTC(2026, 9, 18) });
  assert.ok(ics.startsWith('BEGIN:VCALENDAR\r\n'));
  assert.ok(ics.includes('DTSTART:20261020T120000Z\r\n'));
  assert.ok(ics.includes('DTEND:20261020T140000Z\r\n'));
  assert.ok(ics.includes('SUMMARY:Supper\\; club\\, night\r\n'));
  assert.ok(ics.includes('LOCATION:Q1\\, HCMC\r\n'));
  assert.ok(ics.split('\r\n').every(l => new TextEncoder().encode(l).length <= 75), 'every line is folded to 75 octets');
  assert.equal(icsText('a\nb'), 'a\\nb');
  assert.ok(googleCalendarUrl(d).includes('dates=20261020T120000Z%2F20261020T140000Z'));
});

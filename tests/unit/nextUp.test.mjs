import test from 'node:test';
import assert from 'node:assert/strict';
import { nextUpGroups, nextUpChip, peopleLine, nextUpStatus, dayDiffInZone } from '../../src/lib/nextUp.js';

const NOW = Date.parse('2026-11-14T05:00:00Z'); // 12:00 in Saigon
const H = 3600000;
const TZ = 'Asia/Ho_Chi_Minh';
const iso = (t) => new Date(t).toISOString();
const bk = (o) => ({ id: 'b1', event_id: 'e1', qty: 2, status: 'confirmed', payment_state: 'confirmed', created_at: iso(NOW - H), ...o });
const EVS = { e1: { startMs: NOW + 15 * 24 * H }, e2: { startMs: NOW + 2 * 24 * H }, e3: { startMs: NOW - 2 * H, endMs: NOW + H }, old: { startMs: NOW - 20 * H } };

test('one card per event, soonest first, people across bookings, over and gifted left out', () => {
  const g = nextUpGroups([
    bk({}), bk({ id: 'b2', qty: 1, payment_state: 'holding', status: 'pending', hold_expires_at: iso(NOW + 20 * 60000) }),
    bk({ id: 'b3', event_id: 'e2', qty: 1 }), bk({ id: 'b4', event_id: 'old' }), bk({ id: 'b5', event_id: 'e2', recipient_name: 'Gift' }),
    bk({ id: 'b6', event_id: 'e3', payment_state: 'pending_verification', status: 'pending' }), bk({ id: 'b7', event_id: 'e2', status: 'cancelled' }),
  ], EVS, NOW);
  assert.deepEqual(g.map(x => x.eventId), ['e3', 'e2', 'e1']);
  const e1 = g.find(x => x.eventId === 'e1');
  assert.equal(e1.seats, 3);
  assert.equal(e1.state, 'pay');
  assert.equal(e1.mixed, true);
  assert.equal(e1.primaryId, 'b2');
  assert.equal(g[0].live, true);
  assert.equal(g.find(x => x.eventId === 'e2').seats, 1, 'cancelled and gifted not counted');
});

test('status, button and copy follow what the event needs', () => {
  const [e2] = nextUpGroups([bk({ event_id: 'e2' })], EVS, NOW);
  assert.equal(nextUpStatus(e2, NOW).button.en, 'Show ticket');
  assert.equal(nextUpStatus(e2, NOW).text.en, 'Ready');
  const [pay] = nextUpGroups([bk({ event_id: 'e2', payment_state: 'holding', status: 'pending', hold_expires_at: iso(NOW + 24 * 60000) })], EVS, NOW);
  assert.equal(nextUpStatus(pay, NOW).text.en, 'Payment due');
  assert.equal(nextUpStatus(pay, NOW).note.en, '24 min left');
  assert.equal(nextUpStatus(pay, NOW).action, 'pay');
  const [wait] = nextUpGroups([bk({ event_id: 'e2', payment_state: 'pending_verification', status: 'pending' })], EVS, NOW);
  assert.equal(nextUpStatus(wait, NOW).button.en, 'View status');
  const [mixed] = nextUpGroups([bk({}), bk({ id: 'x', qty: 1, payment_state: 'pending_verification', status: 'pending' })], EVS, NOW);
  assert.equal(nextUpStatus(mixed, NOW).text.en, '2 ready');
  assert.equal(nextUpStatus(mixed, NOW).note.en, '1 waiting');
  assert.equal(peopleLine(mixed).main.en, '3 people');
  assert.equal(peopleLine(mixed).note.en, '2 bookings');
  assert.equal(peopleLine(e2).main.vi, '2 người');
  assert.equal(peopleLine(e2).note, null);
});

test('chip: happening now, tonight / today, tomorrow, in N days (venue calendar days)', () => {
  assert.equal(nextUpChip({ live: true }, NOW, TZ).en, 'Happening now');
  assert.equal(nextUpChip({ live: false, startMs: Date.parse('2026-11-14T12:00:00Z') }, NOW, TZ).en, 'Tonight');
  assert.equal(nextUpChip({ live: false, startMs: Date.parse('2026-11-14T08:00:00Z') }, NOW, TZ).en, 'Today');
  assert.equal(nextUpChip({ live: false, startMs: Date.parse('2026-11-15T01:00:00Z') }, NOW, TZ).en, 'Tomorrow');
  assert.equal(nextUpChip({ live: false, startMs: NOW + 15 * 24 * H }, NOW, TZ).en, 'In 15 days');
  assert.equal(dayDiffInZone(Date.parse('2026-11-14T18:00:00Z'), NOW, TZ), 1, 'after midnight in Saigon is tomorrow');
});

import { dateBadge } from '../../src/lib/nextUp.js';
test('date badge in the venue zone', () => {
  assert.deepEqual(dateBadge(Date.parse('2026-11-22T12:30:00Z'), 'Asia/Ho_Chi_Minh', true), { weekday: 'SUN', day: '22', month: 'NOV' });
  assert.deepEqual(dateBadge(Date.parse('2026-11-22T18:30:00Z'), 'Asia/Ho_Chi_Minh', false), { weekday: 'T2', day: '23', month: 'TH 11' });
});

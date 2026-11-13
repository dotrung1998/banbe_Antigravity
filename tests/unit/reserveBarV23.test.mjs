import test from 'node:test';
import assert from 'node:assert/strict';
import { nextCompact, qtyControl, seatDots, guestLine, moreRefusal, totalSub, GROW_AT, COMPACT_AT } from '../../src/lib/reserveBarV23.js';

test('compact on arrival, full past 40 px, compact again near the top (no flicker in between)', () => {
  assert.equal(nextCompact(0, true), true);
  assert.equal(nextCompact(GROW_AT, true), true);
  assert.equal(nextCompact(GROW_AT + 1, true), false);
  assert.equal(nextCompact(30, false), false, 'between the thresholds it keeps its state');
  assert.equal(nextCompact(COMPACT_AT, false), true);
  assert.equal(nextCompact(-20, false), true, 'overscroll counts as the top');
});

test('1·2·3·4+: the fourth slot becomes a stepper up to 6, or the seats left', () => {
  assert.deepEqual(qtyControl(1, null), { max: 6, stepper: false, moreEnabled: true, canMinus: false, canPlus: true });
  assert.deepEqual(qtyControl(4, null), { max: 6, stepper: true, moreEnabled: true, canMinus: true, canPlus: true });
  assert.equal(qtyControl(6, null).canPlus, false);
  assert.deepEqual(qtyControl(4, 4), { max: 4, stepper: true, moreEnabled: true, canMinus: true, canPlus: false });
  assert.equal(qtyControl(2, 3).moreEnabled, false, '3 seats or fewer: 4+ stays visible but quiet');
  assert.equal(qtyControl(1, 0).max, 1);
});

test('six dots, you first', () => {
  assert.deepEqual(seatDots(4), ['me', 'guest', 'guest', 'guest', 'empty', 'empty']);
  assert.deepEqual(seatDots(1), ['me', 'empty', 'empty', 'empty', 'empty', 'empty']);
});

test('guest line says why it stops at the cap', () => {
  assert.equal(guestLine(4, null).en, 'You + 3 guests · up to 6');
  assert.equal(guestLine(2, null).en, 'You + 1 guest · up to 6');
  assert.equal(guestLine(6, null).en, 'You + 5 guests · 6 is the most per person');
  assert.equal(guestLine(4, 4).en, 'You + 3 guests · only 4 left');
  assert.equal(guestLine(1, null).en, 'Just you · up to 6');
  assert.equal(guestLine(4, null).vi, 'Bạn + 3 khách · tối đa 6');
  assert.equal(moreRefusal(3).en, 'Only 3 tickets left for this one');
  assert.equal(moreRefusal(1).en, 'Only 1 ticket left for this one');
});

test('total line multiplies, never repeats one ticket price', () => {
  assert.equal(totalSub(1, '850.000₫', false).en, 'per ticket');
  assert.equal(totalSub(2, '850.000₫', false).en, 'Total · 2 × 850.000₫');
  assert.equal(totalSub(3, '0', true).en, 'no charge');
  for (const t of [guestLine(4, null), guestLine(6, 6), totalSub(2, 'x', false), moreRefusal(2)]) assert.doesNotMatch(`${t.vi} | ${t.en}`, /—|;| - /);
});

import { holdsSeat, bookedQty, stampState, stampText, addControl, heldCopy, addGuestLine } from '../../src/lib/reserveBarV23.js';

const NOW = Date.parse('2026-11-14T10:00:00Z');
const at = (min) => new Date(NOW + min * 60000).toISOString();
const bk = (o) => ({ qty: 1, status: 'pending', payment_state: 'holding', hold_expires_at: at(25), ...o });

test('holdsSeat mirrors booking_holds_seat()', () => {
  assert.equal(holdsSeat(bk({}), NOW), true);
  assert.equal(holdsSeat(bk({ hold_expires_at: at(-1) }), NOW), false, 'a lapsed hold');
  assert.equal(holdsSeat(bk({ status: 'cancelled', payment_state: 'confirmed' }), NOW), false);
  assert.equal(holdsSeat(bk({ status: 'expired' }), NOW), false);
  assert.equal(holdsSeat(bk({ payment_state: 'pending_verification', hold_expires_at: at(-90) }), NOW), true, 'no timer once paid');
  assert.equal(holdsSeat(bk({ payment_state: 'disputed' }), NOW), true);
  assert.equal(holdsSeat(bk({ status: 'attended', payment_state: 'refunded' }), NOW), true);
  assert.equal(bookedQty([bk({ qty: 2 }), bk({ qty: 3, status: 'cancelled' }), bk({ qty: 1, payment_state: 'confirmed', status: 'confirmed' })], NOW), 3);
});

test('stamp: nothing, held (earliest deadline, hold vs verify), confirmed, mixed reads held', () => {
  assert.equal(stampState([], NOW), null);
  assert.equal(stampState([bk({ status: 'cancelled' })], NOW), null);
  assert.deepEqual(stampState([bk({})], NOW), { kind: 'held', until: Date.parse(at(25)), phase: 'hold' });
  assert.deepEqual(stampState([bk({ payment_state: 'pending_verification', verify_due_at: at(50) })], NOW), { kind: 'held', until: Date.parse(at(50)), phase: 'verify' });
  assert.equal(stampState([bk({ status: 'confirmed', payment_state: 'confirmed' })], NOW).kind, 'confirmed');
  assert.equal(stampState([bk({ status: 'confirmed', payment_state: 'confirmed' }), bk({})], NOW).kind, 'held');
  assert.equal(stampText(stampState([bk({})], NOW), NOW).en, 'Held · 25 min');
  assert.equal(stampText({ kind: 'held', until: NOW + 60 * 60000 }, NOW).en, 'Held · 1 h');
  assert.equal(stampText({ kind: 'held', until: NOW + 61 * 60000 }, NOW).vi, 'Đã giữ · 2 giờ');
  assert.equal(stampText({ kind: 'held', until: null }, NOW).en, 'Held');
  assert.equal(stampText({ kind: 'confirmed' }, NOW).vi, 'Đã xác nhận');
});

test('adding after a hold: never below what you hold, 6 per person or the seats free', () => {
  assert.deepEqual(addControl(2, 10, 2), { qty: 2, min: 2, max: 6, extra: 0, adding: false, stepper: false, moreEnabled: true, canMinus: false, canPlus: true });
  assert.equal(addControl(1, 10, 2).qty, 2, 'clamped up to what you hold');
  assert.equal(addControl(5, 10, 4).extra, 1);
  assert.equal(addControl(6, 1, 4).max, 5, 'only one seat free');
  assert.equal(addControl(6, 0, 6).moreEnabled, false);
  const c = heldCopy({ booked: 4, extra: 1, confirmed: false });
  assert.equal(c.button.en, 'Add 1 ticket');
  assert.equal(c.sub.en, '1 more · 5 in all');
  assert.equal(heldCopy({ booked: 2, extra: 0, confirmed: true }).button.en, 'View your ticket');
  assert.equal(heldCopy({ booked: 2, extra: 0, confirmed: false, phase: 'verify' }).trust.en, 'The host has 1 hour to confirm · banbe reminds them');
  assert.equal(addGuestLine(5, 4, 6).en, '4 held · adding 1 · up to 6');
  assert.equal(addGuestLine(6, 4, 6).en, '4 held · adding 2 · 6 is the most per person');
  assert.equal(addGuestLine(4, 4, 6), null);
  for (const t of [c.button, c.sub, c.trust, addGuestLine(5, 4, 5)]) assert.doesNotMatch(`${t.vi} | ${t.en}`, /—|;| - /);
});

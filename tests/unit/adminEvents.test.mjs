import test from 'node:test';
import assert from 'node:assert/strict';
import { en, isBlocked, blockerLine, summarize, ADMIN_EVENT_FILTERS, STATUS_LABELS } from '../../src/lib/adminEvents.js';

// Note 54: Admin > Manage events wording. The rules themselves are the server's (migration 189), verified on
// Postgres by supabase/_localtest/13_event_removal_assert.sql.
const T = (vi, en_) => en_;
const V = (vi) => vi;

test('English plurals', () => {
  assert.equal(en(1, 'event'), '1 event');
  assert.equal(en(3, 'event'), '3 events');
  assert.equal(en(0, 'event'), '0 events');
});

test('blocked only while money or a conversation is still in play', () => {
  assert.equal(isBlocked(undefined), false);
  assert.equal(isBlocked({ active_bookings: 0, unsettled_refunds: 0, open_disputes: 0, bookings_ever: 9 }), false, 'history alone never blocks');
  assert.equal(isBlocked({ active_bookings: 1, unsettled_refunds: 0, open_disputes: 0 }), true);
  assert.equal(isBlocked({ active_bookings: 0, unsettled_refunds: 2, open_disputes: 0 }), true);
  assert.equal(isBlocked({ active_bookings: 0, unsettled_refunds: 0, open_disputes: 1 }), true);
});

test('blocker line says exactly why, in both languages', () => {
  const c = { active_bookings: 3, unsettled_refunds: 1, open_disputes: 0 };
  assert.equal(blockerLine(c, T), '3 active bookings · 1 refund not settled — the host must cancel and refund first.');
  assert.equal(blockerLine(c, V), '3 đặt chỗ đang hiệu lực · 1 khoản hoàn tiền chưa xong — người tổ chức cần huỷ và hoàn tiền trước.');
  assert.equal(blockerLine({ active_bookings: 0, unsettled_refunds: 0, open_disputes: 0 }, T), '');
});

test('summary groups skipped events by reason', () => {
  assert.equal(summarize('remove', { done: 1, skipped: [] }, T), 'Removed 1 event.');
  assert.equal(summarize('remove', { done: 2, skipped: [{ error: 'HAS_OPEN_OBLIGATIONS' }, { error: 'HAS_OPEN_OBLIGATIONS' }, { error: 'ALREADY_REMOVED' }] }, T),
    'Removed 2 events. Skipped: 1 already removed, 2 still have bookings, refunds or disputes.');
  assert.equal(summarize('purge', { done: 0, skipped: [{ error: 'HAS_BOOKING_HISTORY' }] }, T), 'Permanently deleted 0 events. Skipped: 1 had bookings.');
  assert.equal(summarize('restore', { done: 1, skipped: [] }, V), 'Đã khôi phục 1 sự kiện.');
});

test('every filter has a label, and Removed is one of them', () => {
  for (const f of ADMIN_EVENT_FILTERS) if (f.key) assert.ok(STATUS_LABELS[f.key], f.key);
  assert.ok(ADMIN_EVENT_FILTERS.some(f => f.key === 'removed'));
});

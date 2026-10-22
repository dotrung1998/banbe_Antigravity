import test from 'node:test';
import assert from 'node:assert/strict';
import { en, isBlocked, blockerLine, summarize, ADMIN_EVENT_FILTERS, STATUS_LABELS, isOrphanEvent, needsAnotherPage, ORPHAN_FILTER } from '../../src/lib/adminEvents.js';

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
  assert.equal(blockerLine(c, T), '3 active bookings — the host must cancel the event · 1 refund not settled — the host must finish refunding.');
  assert.equal(blockerLine(c, V), '3 đặt chỗ đang hiệu lực — người tổ chức cần huỷ sự kiện · 1 khoản hoàn tiền chưa xong — người tổ chức cần hoàn tất hoàn tiền.');
  assert.equal(blockerLine({ active_bookings: 0, unsettled_refunds: 0, open_disputes: 0 }, T), '');
});

test('an open dispute on a cancelled, refunded event points at Payment Disputes, not "cancel and refund"', () => {
  const c = { active_bookings: 0, unsettled_refunds: 0, open_disputes: 1 };
  assert.equal(blockerLine(c, T), '1 open dispute — resolve it in Payment Disputes.');
  assert.equal(blockerLine({ ...c, open_disputes: 2 }, T), '2 open disputes — resolve them in Payment Disputes.');
  assert.equal(blockerLine(c, V), '1 tranh chấp đang mở — xử lý trong Tranh Chấp Thanh Toán.');
  assert.doesNotMatch(blockerLine(c, T), /cancel|refund/);
});

test('summary groups skipped events by reason', () => {
  assert.equal(summarize('remove', { done: 1, skipped: [] }, T), 'Removed 1 event.');
  assert.equal(summarize('remove', { done: 2, skipped: [{ error: 'HAS_OPEN_OBLIGATIONS' }, { error: 'HAS_OPEN_OBLIGATIONS' }, { error: 'ALREADY_REMOVED' }] }, T),
    'Removed 2 events. Skipped: 1 already removed, 2 still have bookings, refunds or disputes.');
  assert.equal(summarize('purge', { done: 0, skipped: [{ error: 'HAS_BOOKING_HISTORY' }] }, T), 'Permanently deleted 0 events. Skipped: 1 had bookings.');
  assert.equal(summarize('restore', { done: 1, skipped: [] }, V), 'Đã khôi phục 1 sự kiện.');
});

test('every filter has a label, and Removed is one of them', () => {
  for (const f of ADMIN_EVENT_FILTERS) if (f.key && !f.client) assert.ok(STATUS_LABELS[f.key], f.key);
  assert.ok(ADMIN_EVENT_FILTERS.some(f => f.key === 'removed'));
});

test('orphaned events: host account gone', () => {
  const live = { organizer_id: 'o1', organizer_owner_id: 'u1', organizer_user_id: null, organizer_name: 'Bếp Nhỏ' };
  assert.equal(isOrphanEvent(live), false);
  assert.equal(isOrphanEvent({ ...live, organizer_owner_id: null, organizer_user_id: 'u2' }), false, 'user_id alone still counts as a host');
  assert.equal(isOrphanEvent({ ...live, organizer_owner_id: null }), true, 'no owner and no user (profile cascade SET NULL)');
  assert.equal(isOrphanEvent({ ...live, organizer_name: 'Deleted organizer' }), true, 'anonymized by the account-deletion cleanup');
  assert.equal(isOrphanEvent({ ...live, organizer_id: null }), true, 'organizer row deleted');
  assert.equal(isOrphanEvent({ ...live, organizer_missing: true }), true, 'organizer not readable/missing');
  assert.ok(ADMIN_EVENT_FILTERS.some(f => f.key === ORPHAN_FILTER && f.client));
});

test('orphan blocker says banbe has to act, not the host', () => {
  const c = { active_bookings: 0, unsettled_refunds: 1, open_disputes: 0 };
  assert.match(blockerLine(c, T), /the host must finish refunding/);
  assert.match(blockerLine(c, T, true), /host account was deleted; banbe must contact the guests/);
  assert.match(blockerLine({ active_bookings: 2, unsettled_refunds: 0, open_disputes: 0 }, T, true), /banbe must cancel the event/);
  assert.equal(blockerLine({ active_bookings: 0, unsettled_refunds: 0, open_disputes: 0 }, T, true), '');
});

test('paging keeps going only while pages come back full, up to the cap', () => {
  assert.equal(needsAnotherPage(500, 500), true);
  assert.equal(needsAnotherPage(499, 999), false);
  assert.equal(needsAnotherPage(500, 5000), false, 'hard cap');
  assert.equal(needsAnotherPage(0, 0), false);
});

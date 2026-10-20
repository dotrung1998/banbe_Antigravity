// Admin > Manage events (migrations 188 + 189, note 54) — data calls + the pure wording helpers (unit-tested).
// Admins can remove (hide; bookings, payments, refunds and history are kept), restore, and permanently delete
// never-booked removed events, one or many at a time. The server enforces every rule (is_platform_admin + the
// account gate, row locks, money-in-play blockers); this only calls it and explains the outcome.
// iOS twin: apps/ios/BanbeApp/State/AppState+AdminManageEvents.swift. The TESTING-PHASE wipe is iOS-only, so it
// has no web call here. Network calls: src/lib/adminEventsApi.js (kept apart so this file stays testable in Node).

export const ADMIN_EVENT_FILTERS = [
  { key: null, vi: 'Tất cả', en: 'All' },
  { key: 'live', vi: 'Đang mở', en: 'Live' },
  { key: 'review', vi: 'Chờ duyệt', en: 'In review' },
  { key: 'draft', vi: 'Nháp', en: 'Draft' },
  { key: 'ended', vi: 'Đã kết thúc', en: 'Ended' },
  { key: 'cancelled', vi: 'Đã huỷ', en: 'Cancelled' },
  { key: 'removed', vi: 'Đã gỡ', en: 'Removed' },
];

export const STATUS_LABELS = {
  live: ['Đang mở', 'Live'], review: ['Chờ duyệt', 'In review'], draft: ['Nháp', 'Draft'],
  ended: ['Đã kết thúc', 'Ended'], cancelled: ['Đã huỷ', 'Cancelled'], removed: ['Đã gỡ', 'Removed'],
};

/** "1 event", "3 events" (Vietnamese has no plural form, so this is for the English side only). */
export const en = (n, noun) => `${n} ${noun}${n === 1 ? '' : 's'}`;

export function isBlocked(check) {
  return !!check && (check.active_bookings > 0 || check.unsettled_refunds > 0 || check.open_disputes > 0);
}

/** Why an event can't be removed yet, or '' when nothing is in play. */
export function blockerLine(check, T) {
  if (!isBlocked(check)) return '';
  const parts = [];
  if (check.active_bookings > 0) parts.push(T(`${check.active_bookings} đặt chỗ đang hiệu lực`, en(check.active_bookings, 'active booking')));
  if (check.unsettled_refunds > 0) parts.push(T(`${check.unsettled_refunds} khoản hoàn tiền chưa xong`, `${en(check.unsettled_refunds, 'refund')} not settled`));
  if (check.open_disputes > 0) parts.push(T(`${check.open_disputes} tranh chấp đang mở`, en(check.open_disputes, 'open dispute')));
  return parts.join(' · ') + T(' — người tổ chức cần huỷ và hoàn tiền trước.', ' — the host must cancel and refund first.');
}

const SKIP = {
  HAS_OPEN_OBLIGATIONS: ['còn đặt chỗ/hoàn tiền/tranh chấp', 'still have bookings, refunds or disputes'],
  ALREADY_REMOVED: ['đã gỡ trước đó', 'already removed'],
  NOT_REMOVED: ['chưa bị gỡ', 'not removed'],
  HAS_BOOKING_HISTORY: ['đã từng có đặt chỗ', 'had bookings'],
  NOT_FOUND: ['không còn tồn tại', 'no longer exist'],
};

export const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền.', 'You are not allowed to do this.'],
  REASON_REQUIRED: ['Hãy nhập lý do (ít nhất 3 ký tự).', 'Please give a reason (at least 3 characters).'],
  NOT_DEPLOYED: ['Máy chủ chưa có tính năng này (chạy migration 188–189).', "The server doesn't have this yet (apply migrations 188–189)."],
  INVALID_VALUE: ['Chọn tối đa 100 sự kiện mỗi lần.', 'Pick at most 100 events at a time.'],
  NETWORK: ['Không kết nối được. Thử lại nhé.', "Couldn't reach the server. Try again."],
};

/** One line after an action: what went through and, grouped, why the rest didn't. */
export function summarize(action, outcome, T) {
  const n = outcome.done;
  const done = {
    remove: T(`Đã gỡ ${n} sự kiện.`, `Removed ${en(n, 'event')}.`),
    restore: T(`Đã khôi phục ${n} sự kiện.`, `Restored ${en(n, 'event')}.`),
    purge: T(`Đã xoá vĩnh viễn ${n} sự kiện.`, `Permanently deleted ${en(n, 'event')}.`),
  }[action];
  if (!outcome.skipped.length) return done;
  const groups = {};
  outcome.skipped.forEach(r => { groups[r.error] = (groups[r.error] || 0) + 1; });
  const why = Object.keys(groups).sort().map(code => `${groups[code]} ${T(...(SKIP[code] || [code, code]))}`).join(', ');
  return `${done} ${T('Bỏ qua: ', 'Skipped: ')}${why}.`;
}

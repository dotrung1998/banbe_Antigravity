// Admin > Manage events (migrations 188 + 189, note 54) — data calls + the pure wording helpers (unit-tested).
// Admins can remove (hide; bookings, payments, refunds and history are kept), restore, and permanently delete
// never-booked removed events, one or many at a time. The server enforces every rule (is_platform_admin + the
// account gate, row locks, money-in-play blockers); this only calls it and explains the outcome.
// iOS twin: apps/ios/BanbeApp/State/AppState+AdminManageEvents.swift. The TESTING-PHASE wipe is iOS-only, so it
// has no web call here. Network calls: src/lib/adminEventsApi.js (kept apart so this file stays testable in Node).

export const ORPHAN_FILTER = 'orphan';
/** What api/_lib/organizerCleanup.js renames an organizer to when its owner deletes their account. */
export const DELETED_ORGANIZER_NAME = 'Deleted organizer';

/** True when the event's host account is gone (2026-10-21): no organizer, an organizer row that no longer exists, an
 *  organizer with neither owner nor user (profiles cascade SET NULL on account deletion), or one anonymized by the
 *  account-deletion cleanup. Such events can't be cancelled or refunded by anyone but banbe. */
export function isOrphanEvent(row) {
  if (!row) return false;
  if (!row.organizer_id || row.organizer_missing) return true;
  if (!row.organizer_owner_id && !row.organizer_user_id) return true;
  return row.organizer_name === DELETED_ORGANIZER_NAME;
}

/** Paging for the Manage events list: keep going while a page comes back full, up to `cap` rows in total. */
export const ADMIN_EVENTS_PAGE = 500;
export const ADMIN_EVENTS_CAP = 5000;
export function needsAnotherPage(lastPageCount, totalSoFar, pageSize = ADMIN_EVENTS_PAGE, cap = ADMIN_EVENTS_CAP) {
  return lastPageCount === pageSize && totalSoFar < cap;
}

export const ADMIN_EVENT_FILTERS = [
  { key: null, vi: 'Tất cả', en: 'All' },
  { key: 'live', vi: 'Đang mở', en: 'Live' },
  { key: 'review', vi: 'Chờ duyệt', en: 'In review' },
  { key: 'draft', vi: 'Nháp', en: 'Draft' },
  { key: 'ended', vi: 'Đã kết thúc', en: 'Ended' },
  { key: 'cancelled', vi: 'Đã huỷ', en: 'Cancelled' },
  { key: 'removed', vi: 'Đã gỡ', en: 'Removed' },
  // Not a status: events whose host account was deleted (filtered on the client, see isOrphanEvent).
  { key: ORPHAN_FILTER, vi: 'Host đã xoá', en: 'Host deleted', client: true },
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

/** Why an event can't be removed yet, or '' when nothing is in play. Each blocker says who has to do what, so an
 *  event that is already cancelled and refunded isn't told to "cancel and refund". With `orphan`, banbe acts
 *  instead of the host, who is gone. */
export function blockerLine(check, T, orphan = false) {
  if (!isBlocked(check)) return '';
  const parts = [];
  const b = check.active_bookings, r = check.unsettled_refunds, d = check.open_disputes;
  if (b > 0) parts.push(orphan
    ? T(`${b} đặt chỗ đang hiệu lực — banbe cần huỷ sự kiện`, `${en(b, 'active booking')} — banbe must cancel the event`)
    : T(`${b} đặt chỗ đang hiệu lực — người tổ chức cần huỷ sự kiện`, `${en(b, 'active booking')} — the host must cancel the event`));
  if (r > 0) parts.push(orphan
    ? T(`${r} khoản hoàn tiền chưa xong — host đã xoá tài khoản, banbe cần liên hệ khách để hoàn tiền`,
        `${en(r, 'refund')} not settled — the host account was deleted; banbe must contact the guests to settle refunds`)
    : T(`${r} khoản hoàn tiền chưa xong — người tổ chức cần hoàn tất hoàn tiền`, `${en(r, 'refund')} not settled — the host must finish refunding`));
  if (d > 0) parts.push(T(`${d} tranh chấp đang mở — xử lý trong Tranh Chấp Thanh Toán`,
    `${en(d, 'open dispute')} — resolve ${d === 1 ? 'it' : 'them'} in Payment Disputes`));
  return parts.join(' · ') + '.';
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

// Notification kinds -> categories (the Notifications glyphs) and the switch groups of Notification preferences
// (v5 prototype `sub:notifs`). Pure, no React. A group is "on" while none of its kinds is in
// profiles.muted_notification_kinds (migration 062; the push sender honours the same list, migration 194).

export const KIND_CATEGORY = {
  refund_marked_sent: 'refund', refund_confirmed: 'refund', refund_disputed: 'refund', refund_overdue: 'refund',
  dispute_message: 'dispute', dispute_resolved: 'dispute', payment_disputed: 'dispute',
  payment_awaiting_verification: 'payment', payment_confirmed: 'payment', payment_document_uploaded: 'payment',
  payment_document_replaced: 'payment', payment_verification_nudge: 'payment', payment_needs_info: 'payment',
  hold_created: 'payment', hold_expired: 'payment',
  booking_requested: 'booking', booking_cancelled: 'booking', booking_declined: 'booking',
  checked_in: 'booking', checkin_undo: 'booking', checkin_undone: 'booking', undo_check_in: 'booking',
  reject_pending_guest: 'booking', receipt_requested: 'booking',
  event_share: 'event', referral_joined: 'event',
  new_message: 'message', event_announcement: 'message',
  // iPhone fix pass (2026-09-27), Issue 1 — these fell to 'system' (the
  // generic bell/circle glyph) before; a distinct people icon reads as "a
  // Team thing" instead.
  organizer_invite: 'team', organizer_invite_response: 'team', event_credit_invite: 'team',
  // Phase 2-3 core loops (migrations 199/200): reminders get their own calendar-with-clock glyph; recaps, follow
  // alerts and the weekend digest are about an event.
  event_reminder_day: 'reminder', event_reminder_soon: 'reminder',
  event_recap: 'event', host_event_recap: 'event', follow_alert: 'event', weekly_digest: 'event',
};

const kindsOf = (...cats) => Object.keys(KIND_CATEGORY).filter(k => cats.includes(KIND_CATEGORY[k]));
const HOLDS = ['hold_created', 'hold_expired'];

// Disputes are never mutable: they carry deadlines and admin decisions. The weekly digest has its own opt-in
// (default off, set_my_digest_opt_in), and new messages are always delivered, so neither is muted through this list.
export const NOTIF_PREF_GROUPS = [
  { key: 'tickets', title: ['Vé', 'Tickets'], sub: ['Xác nhận, giữ chỗ, check-in', 'Confirmations, holds, check-in'],
    kinds: [...kindsOf('booking'), ...HOLDS] },
  { key: 'payments', title: ['Thanh toán', 'Payments'], sub: ['Nhắc hạn thanh toán, hoàn tiền', 'Pay-by reminders, refunds'],
    kinds: kindsOf('payment', 'refund').filter(k => !HOLDS.includes(k)) },
  { key: 'events', title: ['Sự kiện', 'Events'], sub: ['Thông báo, nhắc nhở, host bạn theo dõi', 'Announcements, reminders, hosts you follow'],
    kinds: kindsOf('event', 'reminder', 'team').concat('event_announcement').filter(k => k !== 'weekly_digest') },
];

export function groupOn(muted, group) {
  const m = muted || [];
  return !group.kinds.some(k => m.includes(k));
}

/** The muted list after flipping one group: on -> add all its kinds, off -> remove them. */
export function toggleGroup(muted, group) {
  const m = muted || [];
  return groupOn(m, group) ? [...new Set([...m, ...group.kinds])] : m.filter(k => !group.kinds.includes(k));
}

/** One-line summary for the Notifications row ("All on", "2 of 3 on", "All off"). */
export function notifPrefsSummary(muted, T) {
  const n = NOTIF_PREF_GROUPS.filter(g => groupOn(muted, g)).length;
  const total = NOTIF_PREF_GROUPS.length;
  if (n === total) return T('Đang bật hết', 'All on');
  if (n === 0) return T('Đang tắt hết', 'All off');
  return T(`Bật ${n}/${total}`, `${n} of ${total} on`);
}

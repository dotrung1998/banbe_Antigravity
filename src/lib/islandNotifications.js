// Real notifications -> island presentation (note 101). The notification rows already carry their own localized
// title/body (note 26), so this only decides the state colour, whether the island offers a button, and nothing else.
// Pure: no React, no browser APIs, so the unit test can cover every kind in KIND_CATEGORY.
import { KIND_CATEGORY } from './notificationPrefs.js';

// Something completed: money arrived, the booking was confirmed, a dispute closed.
const SUCCESS = new Set([
  'payment_confirmed', 'refund_confirmed', 'refund_marked_sent', 'dispute_resolved', 'checked_in',
  'checkin_undo', 'checkin_undone', 'undo_check_in', 'organizer_invite_response', 'referral_joined',
  'event_share', 'event_recap', 'host_event_recap',
]);

// Something needs a decision or failed: a declined card, a cancelled booking, a guest claiming they paid.
const ERROR = new Set([
  'payment_disputed', 'refund_disputed', 'booking_cancelled', 'booking_declined', 'hold_expired',
  'payment_needs_info',
]);

// Time-sensitive, but not a failure: a hold about to lapse, a payment due, a reminder, a host announcement.
const WARNING = new Set([
  'payment_awaiting_verification', 'payment_document_uploaded', 'payment_document_replaced',
  'payment_verification_nudge', 'hold_created', 'booking_requested', 'refund_overdue', 'receipt_requested',
  'event_reminder_day', 'event_reminder_soon', 'event_announcement', 'follow_alert', 'weekly_digest',
  'dispute_message',
]);

// Purely informational notices never grow an "Open" button; everything that routes somewhere does.
const NO_ACTION = new Set(['event_share', 'referral_joined', 'weekly_digest']);

/**
 * @param {{kind?: string}} notification
 * @returns {{type: 'success'|'error'|'warning'|'info', action: boolean}}
 */
export function islandPresentation(notification) {
  const kind = notification?.kind || '';
  const type = SUCCESS.has(kind) ? 'success'
    : ERROR.has(kind) ? 'error'
      : WARNING.has(kind) ? 'warning'
        : 'info';
  const category = KIND_CATEGORY[kind] || 'system';
  const action = !NO_ACTION.has(kind) && category !== 'system';
  return { type, action };
}

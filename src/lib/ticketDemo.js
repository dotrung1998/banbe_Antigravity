// Admin "Ticket demo" (migration 217, switch ticket_demo). An admin opens the real ticket screen on a sample booking in any
// status (Hold / Pay / Review included) to show it to colleagues. Pure helpers; the state lives in BanBeContext and
// Confirmed.jsx keeps every server call off while `ticketDemo` is true. iOS twin: Lib/TicketDemo.swift.
import { flagOn } from './featureFlags.js';

/** Scenario keys in picker order. */
export const TICKET_DEMO_CASES = ['holding', 'awaiting', 'review', 'upcoming', 'today', 'checkedIn', 'ended', 'cancelled', 'expired'];
export const TICKET_DEMO_LABELS = {
  holding: ['Giữ chỗ (đang giữ)', 'Hold (seats held)'],
  awaiting: ['Thanh toán (chờ xác nhận)', 'Pay (awaiting host)'],
  review: ['Đang xem xét (tranh chấp)', 'Review (dispute)'],
  upcoming: ['Vé sắp diễn ra', 'Ticket, upcoming'],
  today: ['Vé hôm nay', 'Ticket, today'],
  checkedIn: ['Đã check-in', 'Checked in'],
  ended: ['Sự kiện đã kết thúc', 'Event ended'],
  cancelled: ['Sự kiện bị huỷ', 'Event cancelled'],
  expired: ['Giữ chỗ hết hạn', 'Hold expired'],
};

const H = 3600000;
// [payment_state, booking.status, event status, event starts in (ms), extra booking fields (fn of now)]
const SPEC = {
  holding: ['holding', 'pending', 'live', 72 * H, (n) => ({ hold_expires_at: new Date(n + 20 * 60000).toISOString() })],
  awaiting: ['pending_verification', 'pending', 'live', 72 * H, (n) => ({ verify_due_at: new Date(n + H).toISOString() })],
  review: ['disputed', 'confirmed', 'live', 72 * H],
  upcoming: ['confirmed', 'confirmed', 'live', 72 * H],
  today: ['confirmed', 'confirmed', 'live', 2 * H],
  checkedIn: ['confirmed', 'attended', 'live', H],
  ended: ['confirmed', 'confirmed', 'ended', -13 * H],
  cancelled: ['confirmed', 'confirmed', 'cancelled', 72 * H],
  expired: ['expired', 'expired', 'live', 72 * H],
};

/** Who sees the entry: admins, and only while the switch is on. Missing switch = off. */
export function ticketDemoAllowed({ accountType, featureFlags } = {}) {
  return accountType === 'admin' && flagOn(featureFlags || {}, 'ticket_demo');
}

/** Everything the demo sets; clearing it (plus the previous event key) ends the demo. */
export const TICKET_DEMO_RESET = Object.freeze({ ticketDemo: false, booking: null, liveEvent: null, bookingAttendees: [], holdDeadline: null });

/** State patch that shows case `key` on the ticket screen. `named`: 3 named tickets; `gifted`: the ticket was gifted. */
export function ticketDemoState(key, { named = false, gifted = false, prevEventKey = 'home' } = {}, now = Date.now()) {
  const [pay, status, evStatus, start, extra] = SPEC[key] || SPEC.upcoming;
  const id = 'demo-ticket';
  const booking = { id, event_id: 'bepnho', status, payment_state: pay, qty: named ? 3 : 1, code: '1B159C', admission_token: 'demo-admission-token', ...(extra ? extra(now) : {}) };
  if (gifted) { booking.recipient_name = 'Linh'; booking.claim_code = 'DEMO-CLAIM'; }
  const scanned = key === 'checkedIn' ? new Date(now).toISOString() : null;
  const names = ['Linh', 'Minh', 'An'];
  return {
    ticketDemo: true, ticketDemoPrev: prevEventKey, eventKey: 'bepnho', screen: 'confirmed', confirmedBack: 'accountGroup',
    liveEvent: { status: evStatus, starts_at: new Date(now + start).toISOString(), tz: 'Asia/Ho_Chi_Minh' },
    booking, holdDeadline: null,
    bookingAttendees: named ? names.map((name, i) => ({ id: `demo-a-${i + 1}`, booking_id: id, seat_no: i + 1, name, ticket_code: `1B159${i + 1}`, admission_token: `demo-tok-${i + 1}`, date_of_birth: null, checked_in_at: scanned })) : [],
  };
}

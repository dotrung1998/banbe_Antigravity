import { distanceLabel } from './eventDetailPresentation.js';

// Ticket screen (note 78): which "What's next" case a booking is in, how its QR may be drawn, and the 3-3 entry code.
// Pure and flat on purpose: the caller derives isPaid / checkedIn / daysUntil with the existing helpers
// (isBookingTicket, isCheckedIn, daysUntilInZone), so this twin (apps/ios/BanbeApp/Lib/TicketStatus.swift) stays trivial.
// Vectors: tests/fixtures/ticket-status.json, shared with both test suites. Change all three together.

/** First matching row wins. `qr`: ok/in draw the real code; lock/void/past never do (see ticketQrShowsToken). */
export const TICKET_CASES = {
  cancelled: { tone: 'alert', qr: 'void' },
  expired: { tone: 'alert', qr: 'void' },
  review: { tone: 'honey', qr: 'lock' },
  holding: { tone: 'honey', qr: 'lock' },
  awaiting: { tone: 'plum', qr: 'lock' },
  ended: { tone: 'ink3', qr: 'past' },
  checkedIn: { tone: 'moss', qr: 'in' },
  today: { tone: 'clay', qr: 'ok' },
  upcoming: { tone: 'mist', qr: 'ok' },
};

/**
 * @param {{paymentState?: string|null, eventCancelled?: boolean, endedHoursAgo?: number|null,
 *          isPaid?: boolean, checkedIn?: boolean, daysUntil?: number|null}} input
 * @returns {{key: string, tone: string, qr: string}|null} null when there is no booking to explain.
 */
export function ticketCase({ paymentState = null, eventCancelled = false, endedHoursAgo = null, isPaid = false, checkedIn = false, daysUntil = null } = {}) {
  let key = null;
  if (eventCancelled || paymentState === 'cancelled') key = 'cancelled';
  else if (paymentState === 'expired') key = 'expired';
  else if (paymentState === 'disputed') key = 'review';
  else if (paymentState === 'holding') key = 'holding';
  else if (paymentState === 'pending_verification') key = 'awaiting';
  else if (isPaid && endedHoursAgo != null) key = 'ended';
  else if (isPaid && checkedIn) key = 'checkedIn';
  else if (isPaid && daysUntil === 0) key = 'today';
  else if (isPaid) key = 'upcoming';
  return key ? { key, ...TICKET_CASES[key] } : null;
}

/** The admission token may only be drawn as a real QR in these modes; everything else gets a placeholder. */
export function ticketQrShowsToken(qr) {
  return qr === 'ok' || qr === 'in';
}

/** "1B159C" -> "1B1 59C". Anything that is not 6 characters is returned unchanged. */
export function formatEntryCode(code) {
  const c = String(code ?? '').trim();
  return c.length === 6 ? `${c.slice(0, 3)} ${c.slice(3)}` : c;
}

/** Distance line for the event sheet: only when the viewer is located and it is within the 50 km rule. */
export function showDistance(km, located, en = false) {
  return located === true ? distanceLabel(km, en) : null;
}

// The door watch (note 78): the ticket screen polls for a scan from 3h before the start to 12h after, only while a scan
// is still to come. A booking with named tickets (migration 151) is done when EVERY ticket is scanned; any other booking
// is done once it reads checked in (status 'attended' or a scanned ticket), exactly as before.
export const DOOR_BEFORE_MS = 3 * 3600000;
export const DOOR_AFTER_MS = 12 * 3600000;

/** Strictly inside the window: the start minus 3h and the start plus 12h themselves are outside. */
export function inDoorWindow(startMs, nowMs) {
  return Number.isFinite(startMs) && nowMs > startMs - DOOR_BEFORE_MS && nowMs < startMs + DOOR_AFTER_MS;
}

/**
 * @param {{namedScans?: boolean[]|null, checkedIn?: boolean, startMs: number, nowMs: number}} input
 *   namedScans: one boolean per named ticket (scanned or not), or null/empty when the booking has none.
 */
export function doorWatchOpen({ namedScans = null, checkedIn = false, startMs, nowMs }) {
  if (!inDoorWindow(startMs, nowMs)) return false;
  const done = namedScans && namedScans.length > 0 ? namedScans.every(Boolean) : !!checkedIn;
  return !done;
}

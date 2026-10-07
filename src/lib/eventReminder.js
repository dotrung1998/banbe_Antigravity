// "Event reminder" state for the Home "Your events" strip: a ticket-holder's event
// is highlighted from 24h before it starts until it is over. Events carry no end
// time, so "ongoing" = started, not ended/cancelled, and within ONGOING_CAP_HOURS
// of the start (so a host who never closes the event does not pin it forever).
// Mirrored in iOS Lib/EventReminder.swift — keep the numbers in sync.
export const REMINDER_LEAD_HOURS = 24;
export const ONGOING_CAP_HOURS = 12;

const HOUR = 3600000;

/** @returns {'soon' | 'live' | null} */
export function reminderPhase(startsAt, { status = 'live', now = Date.now() } = {}) {
  if (!startsAt || status === 'ended' || status === 'cancelled') return null;
  const t = startsAt instanceof Date ? startsAt.getTime() : new Date(startsAt).getTime();
  if (!Number.isFinite(t)) return null;
  const delta = t - now;
  if (delta > REMINDER_LEAD_HOURS * HOUR) return null;
  if (delta > 0) return 'soon';
  return -delta <= ONGOING_CAP_HOURS * HOUR ? 'live' : null;
}

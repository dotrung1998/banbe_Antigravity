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

// Shared web styling for a reminder card (Home "Your events" + host Dashboard): a gold border plus a
// halo that pulses each time the screen mounts (i.e. whenever the user navigates back). The keyframes
// are finite, so staying on the screen lets the halo fade out; the border stays. The wrapper must be
// `position: relative` and exactly the photo's size; `--bb-rem-r` is its corner radius.
export const REMINDER_CSS = `
@keyframes bb-rem-halo { 0% { box-shadow: 0 0 0 0 rgba(224,165,38,0.65), 0 0 18px 2px rgba(224,165,38,0.55); } 100% { box-shadow: 0 0 0 10px rgba(224,165,38,0), 0 0 0 0 rgba(224,165,38,0); } }
.bb-rem-card::after { content: ''; position: absolute; inset: 0; box-sizing: border-box; border-radius: var(--bb-rem-r, 18px); border: 2px solid #E0A526; pointer-events: none; animation: bb-rem-halo 1.4s ease-out 3; }
@media (prefers-reduced-motion: reduce) { .bb-rem-card::after { animation: none; } }
`;
export const reminderRank = (r) => (r === 'live' ? 0 : r === 'soon' ? 1 : 2);

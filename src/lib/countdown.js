import { useEffect, useState } from 'react';

// Shared countdown formatting + a ticking clock, used everywhere a payment
// deadline is shown: Home's banners, the ticket screen, the payment screen,
// and the organizer's verification queue. One implementation so a PHASE 1
// hold and a PHASE 2 SLA never render their remaining time slightly
// differently from one screen to the next.

/** ms -> "12:04" (or "1:02:04" past an hour). Never negative. */
export function formatCountdown(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = String(h > 0 ? m : m).padStart(2, '0');
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

/**
 * Ticks a `now` timestamp once a second while `active` is true, and freezes
 * (stops re-rendering) as soon as it isn't — a countdown that isn't showing
 * has no business waking the component tree every second.
 */
export function useTicking(active) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return undefined;
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}

/** Milliseconds remaining until `iso`, floored at 0. */
export function msUntil(iso, now = Date.now()) {
  if (!iso) return 0;
  return Math.max(0, new Date(iso).getTime() - now);
}

/**
 * Out of a list of bookings in a given payment_state, the one whose
 * `dateField` deadline is soonest AND still in the future. A booking whose
 * deadline has already lapsed is excluded rather than sorted last — it is
 * moments away from being swept to 'expired' by the cron job, and showing a
 * banner for a hold that is effectively already gone is worse than showing
 * none.
 */
export function pickSoonest(bookings, phase, dateField) {
  const now = Date.now();
  return (bookings || [])
    .filter(b => b.payment_state === phase && msUntil(b[dateField], now) > 0)
    .sort((a, b) => new Date(a[dateField]) - new Date(b[dateField]))[0] || null;
}

function hoursSince(iso, now) {
  if (!iso) return null;
  return Math.max(0, (now - new Date(iso).getTime()) / 3600000);
}

/**
 * Reconciles a real `events` row's own status against the current clock,
 * overriding the static demo catalogue's hardcoded cancelled/ended flags
 * with a live read — so an organizer cancelling an event, or the daily
 * `goc_mark_past_events` sweep marking one 'ended' 12h after its start, is
 * reflected the moment this client re-fetches the row instead of never
 * (the static catalogue is fixed at build time and can't otherwise learn
 * about either).
 *
 * `staticEv` (the same event's row from the static catalogue) is only used
 * as a cosmetic fallback for the "N hours ago" text when the real row has
 * no timestamp of its own to compute one from (starts_at/cancelled_at are
 * both optional columns, unset for events created before either was wired
 * up) — never for the cancelled/ended booleans themselves, which always
 * come from the live `status` column so a change to it is never missed.
 *
 * Returns null when there is no real row to read at all (e.g. a
 * client-side-only event preview mid-creation) — the caller should leave
 * the static catalogue untouched in that case rather than treat "no data"
 * as "not ended".
 */
export function liveEventOverrides(liveEvent, staticEv, now = Date.now()) {
  if (!liveEvent) return null;
  if (liveEvent.status === 'cancelled') {
    return {
      cancelled: true,
      cancelledHoursAgo: hoursSince(liveEvent.cancelled_at, now) ?? staticEv?.cancelledHoursAgo ?? 0,
      endedHoursAgo: null,
    };
  }
  if (liveEvent.status === 'ended') {
    return {
      cancelled: false,
      cancelledHoursAgo: null,
      endedHoursAgo: hoursSince(liveEvent.starts_at, now) ?? staticEv?.endedHoursAgo ?? 0,
    };
  }
  // 'live' (or 'draft'/'review', which shouldn't be publicly reachable at
  // all) — the organizer hasn't cancelled it and no sweep has marked it
  // ended, so as far as this row is concerned, neither has happened.
  return { cancelled: false, cancelledHoursAgo: null, endedHoursAgo: null };
}

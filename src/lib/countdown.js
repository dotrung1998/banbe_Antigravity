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

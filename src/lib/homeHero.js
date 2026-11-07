// Simple Shell Home (note 66): exactly ONE main block at the top of Home per mode. Everything else sits lower.
// Goer priority: an event of yours within 24h (Next up) > the most urgent Action Center item > the new-user
// checklist > nothing (cards start right away). Guests get the guest banner. Host: the next event you host
// (not yet ended) > "Plan your next event". Pure + shared with iOS (apps/ios/BanbeApp/Lib/HomeHero.swift) through
// tests/fixtures/home-hero.json.

/**
 * @param {{ signedIn: boolean, nextUp?: object|null, actionCount?: number, checklistVisible?: boolean }} input
 * @returns {'guest'|'nextUp'|'action'|'checklist'|'none'}
 */
export function pickGoerHero({ signedIn, nextUp, actionCount = 0, checklistVisible = false }) {
  if (!signedIn) return 'guest';
  if (nextUp) return 'nextUp';
  if (actionCount > 0) return 'action';
  if (checklistVisible) return 'checklist';
  return 'none';
}

/**
 * The host's next event: the soonest one that has not ended yet (ongoing counts), ignoring cancelled/removed.
 * `events` items: { key, startsAt (ms), endsAt? (ms), status }. Returns the event or null ("Plan your next event").
 */
export function pickHostHero(events, now) {
  const live = (events || []).filter(e => e && Number.isFinite(e.startsAt)
    && !['cancelled', 'removed', 'ended', 'rejected'].includes(e.status)
    && (Number.isFinite(e.endsAt) ? e.endsAt > now : e.startsAt + 12 * 3600 * 1000 > now));
  live.sort((a, b) => a.startsAt - b.startsAt || String(a.key).localeCompare(String(b.key)));
  return live[0] || null;
}

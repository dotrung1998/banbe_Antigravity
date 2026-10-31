// Hosting Home guided empty states (Calm Pass pilot). Pure, no React; tests/unit/hostHomeEmpty.test.mjs, shared fixture
// tests/fixtures/host-home-empty.json (also read by apps/ios BanbeAppTests/HostHomeEmptyTests.swift against
// Lib/HostHomeEmpty.swift).
//
// "Coming up" used to vanish when no live event was ahead, so a host with only pending events saw blank space under
// Submitted events. It now always says what is true: an event needs fixing, events wait for review, or nothing is
// scheduled. Only real counts drive it; nothing is invented to fill the space.

/**
 * Which guided state "Coming up" shows, or null when the list itself shows (or the hero already shows the next event
 * and nothing waits). `needsFix` wins over `pending` because the host can act on it.
 */
export function comingUpEmptyVariant({ upcoming, hasHero, pending, needsFix }) {
  if (upcoming > 0) return null;
  if (needsFix > 0) return 'needsFix';
  if (pending > 0) return 'pending';
  return hasHero ? null : 'quiet';
}

/**
 * What the numbers section shows: 'hidden' (no organizer), 'tiles', 'loading', 'error' or 'empty'. Numbers already
 * on screen stay through a reload or a failed refresh. Before the first request lands it reads as loading.
 */
export function kpiSectionState({ hasOrganizer, loading, error, tiles, hasReport }) {
  if (!hasOrganizer) return 'hidden';
  if (tiles > 0) return 'tiles';
  if (loading) return 'loading';
  if (error) return 'error';
  return hasReport ? 'empty' : 'loading';
}

/** Heading for the numbers: the range Reports actually used (it follows the Reports range picker). */
export function kpiRangeHeading(range, T) {
  switch (String(range)) {
    case '7': return T('7 ngày qua', 'Last 7 days');
    case '90': return T('90 ngày qua', 'Last 90 days');
    case 'custom': return T('Khoảng ngày đã chọn', 'Your chosen dates');
    default: return T('30 ngày qua', 'Last 30 days');
  }
}

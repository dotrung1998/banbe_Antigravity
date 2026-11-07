// Pure eligibility logic for account deletion's open-event refusal — kept
// separate from api/auth/index.js's handleDeleteAccount so it can be unit
// tested without a live DB (tests/unit/account-deletion-open-event.test.mjs).
// Takes already-fetched rows, never queries anything itself.

// "Open" = still live or pending review — matches Policy's own "refused
// while you still own an open event" claim. A draft/cancelled/ended event
// never blocks (see supabase/migrations/20261023000111_..._account_deletion_requests.sql
// for the full reasoning).
const OPEN_STATUSES = new Set(['live', 'review']);

// Events have no end time and the DB only flips `live` -> `ended` via a cron
// (note 38). The apps already treat a live event that started 12h+ ago as
// over (host profile "Past events"), so it must not block deletion either —
// otherwise the host sees "0 upcoming" yet is told they own an open event.
const LAPSED_AFTER_MS = 12 * 60 * 60 * 1000;

function hasLapsed(event, now) {
  if (event?.status !== 'live' || !event?.starts_at) return false;
  const startsAt = Date.parse(event.starts_at);
  return Number.isFinite(startsAt) && now - startsAt >= LAPSED_AFTER_MS;
}

export function findOpenEventsBlockingDeletion(events, now = Date.now()) {
  return (events || []).filter(e => OPEN_STATUSES.has(e?.status) && !hasLapsed(e, now));
}

export function isDeletionBlockedByOpenEvents(events, now = Date.now()) {
  return findOpenEventsBlockingDeletion(events, now).length > 0;
}

// Pure eligibility logic for account deletion's open-event refusal — kept
// separate from api/auth/index.js's handleDeleteAccount so it can be unit
// tested without a live DB (tests/unit/account-deletion-open-event.test.mjs).
// Takes already-fetched rows, never queries anything itself.

// "Open" = still live or pending review — matches Policy's own "refused
// while you still own an open event" claim. A draft/cancelled/ended event
// never blocks (see supabase/migrations/20261023000111_..._account_deletion_requests.sql
// for the full reasoning).
const OPEN_STATUSES = new Set(['live', 'review']);

export function findOpenEventsBlockingDeletion(events) {
  return (events || []).filter(e => OPEN_STATUSES.has(e?.status));
}

export function isDeletionBlockedByOpenEvents(events) {
  return findOpenEventsBlockingDeletion(events).length > 0;
}

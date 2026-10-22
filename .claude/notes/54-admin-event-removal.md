# 54 — Admin event removal: remove / restore / purge (public) + testing-phase wipe (iOS only)

**Status:** IMPLEMENTED (web + iOS + migrations 188/189), committed in 3249d6d. Rows became expandable and orphaned events got a filter in note 56. **188/189 NOT applied anywhere

**Production check 2026-10-22 (`supabase migration list --linked`, note 58): 187, 188, 189 and 190 ARE applied on production. Statements below saying otherwise are outdated. Local-only (not on production): 182, 183, 184, 185.**
remote.** They need 187 (feature flags) applied first. The owner applies them with `supabase db push`.

**Owner decisions (2026-10-20):**
- Public version: hide and keep records, plus a separate permanent purge for never-booked events.
- Live events with guests: block removal until the host has cancelled and refunded.
- Testing phase: an iOS-only wipe of any event, no reason asked. **The owner will ask for it to be removed before
  public release.**

## Why not a plain DELETE
Audited 2026-10-20: every FK to `events` is ON DELETE CASCADE, apart from three.
- Deleting an event that ever had bookings silently destroys:
  - bookings
  - `payment_documents` (12-month retention, User Policy B7)
  - the append-only `payment_audit_log`
  - `refund_claims` and refund batch items
  - dispute threads and their transcripts
  - check-ins, per-attendee tickets and wallet passes
- It also orphans every Storage file (event photos, pay/refund proofs, documents, chat and dispute attachments).
- It FAILS for any event that was ever shared as a story. `stories.event_id ON DELETE SET NULL` is an UPDATE, and
  `stories_edit_guard` (147) rejects it. Expired stories are never purged, so this blocks those events forever.

## What exists now
**Migration 188** adds `'removed'` to `event_status`. It is its own file because a new enum value can't be used in the
transaction that adds it.

A status was chosen over `deleted_at` because every public read already filters by status, so removed events are
hidden everywhere with no other changes:
- `events_select_public` and `events_select_invited`
- discovery, Pulse, fill, benchmarks and organizer stats
- `hold_seats`, which requires `live`

The host keeps read access through `is_event_host`, and admins through `events_select_admin`.

**Migration 189:**

| Piece | What it does |
|---|---|
| `events.removed_at/by`, `removal_reason`, `removed_from_status` | Removal bookkeeping |
| `admin_action_log.target_event_id` (no FK) + `meta jsonb` | Log rows outlive a purged event |
| `events_guard_removal` (+ insert guard) | Nothing moves an event into or out of `removed`, or edits those columns, except these RPCs (they set `app.event_removal_allowed`). Hosts can UPDATE their own events directly under `events_update_own`, so without it a host could undo a removal |
| `event_removal_blockers(id)` (internal) | `active_bookings`: seat-holding pending/confirmed bookings on an event not yet ended (12h rule). `unsettled_refunds`: owed / host_marked_sent / disputed. `open_disputes`: `resolved_at IS NULL`. `bookings_ever` |
| `admin_event_removal_check(ids)` | Per event: the blockers plus `removable` / `purgeable` (read-only; the apps show why before anyone acts) |
| `admin_remove_events(ids, reason)` | Reason required (≥3 chars). Up to 100 ids. Per-event results: ALREADY_REMOVED / HAS_OPEN_OBLIGATIONS (with counts) / NOT_FOUND. Writes a history row (`admin_remove`) and an admin log row, and notifies the host (`event_removed`) |
| `admin_restore_events(ids)` | Back to `removed_from_status`. A live event past its time comes back as `ended`. History, log, and the host is notified (`event_restored`) |
| `admin_purge_events(ids, reason)` | PERMANENT, only for removed events with **zero bookings ever**. Deletes the event's `event_share` stories first. Logged in `admin_action_log` (the event's own history is deleted with it) |
| **TESTING-PHASE** `admin_wipe_events_testing(ids)` | Erases ANY event and everything tied to it, no reason. Only while `app_feature_flags.admin_event_wipe` is true. Seeded false; a missing row also means off. Logged as `event_wiped_testing`. **Storage files are left behind.** |
| `cancel_event` fixes | Refuses an already-cancelled event (re-cancelling overwrote `cancelled_at`, which `get_event_ticket_holders` matches bookings on) or a removed one. Locks the row. Writes a `cancel` history row. Says "banbe" when a non-host admin cancels |
| `event_status_history` CHECK | Now allows 109's `auto_withdraw_photo_count`. That path used to fail with a check violation (latent bug) |
| 142 i18n rows | Titles, plus body rules 52/53. " Lý do: " is handled by 142's rule 48, which runs first, so rule 52 must not contain it |

**Not changed (known):**
- Rewards (165:406) still count attendance at a removed event that had already ended (`NOT IN ('cancelled','draft','review')`).
- Owners can still write other event columns, and other statuses, directly (`events_update_own`). Only `removed` is guarded.
- No storage cleanup on purge or wipe.

## Apps
- **iOS:**
  - `State/AppState+AdminManageEvents.swift`
  - `Views/AdminManageEventsView.swift`:
    - entered from Account → Review & Moderation → **Manage events**
    - `Screen.adminManageEvents`, plus routing and back handling in AppState and RootView
  - The Feature switches row "Test event wipe (testing phase)" (`AdminFeaturesView`).
  - `FeatureFlags.offUnlessSet` gives the wipe switch a missing = OFF rule.
  - Notifications `event_removed` / `event_restored` open Dashboard. Dashboard shows a "Removed by banbe" box.
  - `organizerNames(for:)` is now internal.
- **Web:**
  - `src/lib/adminEvents.js` (pure, tested) and `src/lib/adminEventsApi.js` (calls)
  - `src/screens/AdminManageEvents.jsx`, route `/admin/events/manage`, row in AccountGroup `adminReview`
  - Same notification routing and dead-link map, and the Dashboard removed box
  - No wipe on web (owner: iOS only)
- **Dev only:** `window.__banbeDevSet` is in BanBeContext (from note 53). It's how the web screen was rendered locally;
  it is stripped from production builds.

## TESTING-PHASE removal checklist (when the owner asks)
1. Copy `supabase/rollbacks/20261226000189_189b_drop_testing_event_wipe.sql` into `supabase/migrations/` as the next
   number. It drops the RPC and the flag row, and restores the flag CHECK and `admin_set_feature_flag` whitelist.
2. Delete the iOS code marked `TESTING-PHASE`:
   - `AdminEventAction.wipeTesting` and its branch
   - `confirmWipe` / `wipeEnabled` / the wipe button in `AdminManageEventsView`
   - the `admin_event_wipe` row in `AdminFeaturesView`
   - `admin_event_wipe` in `FeatureFlags.keys` / `offUnlessSet`
   - the fixture `-uiFixtureWipe` and `testTestingWipeOnlyWithSwitchOn`
3. Remove the "Test event wipe" subsection (section `manage`) and its Feature switches bullet from `src/data/help/admin.js`,
   then run `node scripts/gen-help-content-ios.mjs`.
4. Keep everything else (remove / restore / purge are the public version).

The full revert of 189 is `supabase/rollbacks/20261226000189_189_revert_admin_event_removal.sql`. It moves removed
events back and keeps the `auto_withdraw_photo_count` fix. The 188 enum value can't be dropped.

## Verified (2026-10-21)
- **Database:**
  - All 178 migrations applied from zero to a throwaway `supabase/postgres:17.6.1.166` container. Its auth/storage
    schema structure was copied from the local stack; data was not touched.
  - `supabase/_localtest/13_event_removal_assert.sql` passes T1–T12:
    - admin-only (anon and host refused)
    - reason required
    - mixed batch: blockers, per-event results, records kept, history + log + host notification
    - hidden from anon and other users, the host still sees it and can't undo it
    - removal guard, even for a superuser session
    - a removed event can't be booked
    - restore
    - purge: only never-booked, story shares deleted, logged
    - wipe: off by default, on after the flip, wipes booked events, off again, a missing row counts as off
    - `cancel_event` guards
    - history CHECK
    - EN localization
  - Both rollback files apply cleanly.
- **iOS:**
  - Builds.
  - `AdminManageEventsUITests` 3/3: remove skips blocked events and needs a reason; restore and purge; the wipe only
    with the switch on.
  - `FeatureFlagsTests` 4/4.
- **Web:**
  - `npm run test:unit` 326/326 (`adminEvents.test.mjs` +5).
  - `vite build` OK.
  - Screen renders with no page errors. Against the current remote it shows "apply migrations 188–189", as expected.
- **NOT verified:**
  - A real Supabase project (needs `db push`).
  - A real device.
  - Web actions end to end (no admin session plus remote migrations).
  - Dark mode / VI screenshots.

## Follow-up (2026-10-22): stranded payment dispute chats + blocker wording — migration 190
**Status:** IMPLEMENTED LOCALLY, not committed. **190 NOT applied remotely.** 188/189 ARE live on the remote (checked
2026-10-22: Reminder tests were removed on 2026-10-20 and restored on 2026-10-22 11:02 UTC).

- **Symptom:** Manage events refused to remove *Test v2.2* (`test-v2-2-85895a`), saying "1 open dispute — the host must
  cancel and refund first", although the event was cancelled and its only refund was `guest_confirmed`.
- **Root cause:** a `kind='payment'` dispute thread ("transfer not found", 05/10 14:33) was never closed after the host
  confirmed the payment at 15:07. The auto-close trigger and backfill were added to migration **149 after it had been
  applied** (commit b14d5ad). `db push` never re-runs an applied version, so the remote never got them. The 2-day sweep
  only sees `pending_verification`/`holding` bookings, so it never closed the chat either. A second chat was stranded on
  *Test sự kiện* (`test-s-ki-n-8444c8`).
- **Lesson:** never edit an applied migration. Add a new one.
- **Migration 190** restates 149's committed `expire_not_found_bookings()`, trigger and backfill. It also adds
  `bookings_close_payment_dispute_thread_on_cancel` (booking `status` → cancelled/expired), because `cancel_event` never
  touches `payment_state`. Escalated (`payment_state='disputed'`) chats are never auto-closed, in either the triggers or
  the backfill. Tested on local Postgres: `supabase/_localtest/14_stranded_payment_dispute_assert.sql` (all pass) plus
  `10_not_found_window_assert.sql` re-run on top of 190 (all pass).
- **Wording:** `blockerLine` (web `src/lib/adminEvents.js`, iOS `AdminManageEventsView`) now gives one clause per
  blocker: bookings → host (or banbe for orphans) must cancel the event; refunds → host must finish refunding (orphan:
  banbe contacts guests); disputes → "resolve it in Payment Disputes". Web unit tests: 338/338. iOS
  `AdminManageEventsUITests` 3/3 + `testManageEventsOrphansAndExpand` pass.
- **Past events** on the host Dashboard deliberately excludes cancelled events (`DashboardView.past`). Not changed.

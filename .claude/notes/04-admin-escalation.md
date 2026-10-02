# Stage 7-8: Raise to banbe admin + admin decision

## Files / functions
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:129` `escalate_payment_dispute()` — sets `payment_state='disputed'`, opens `dispute_threads` row, notifies guest
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:223` `resolve_dispute()` — admin-only, `p_uphold` true→`verify_payment` (ticket issued) / false→`payment_state='expired'`
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:810` `resolve_dispute()` — OLD version (superseded by 033)
- `supabase/migrations/20260913000026_026_payment_state_machine.sql:62` `is_platform_admin()` — role check used by every admin RLS/RPC gate
- `supabase/migrations/20260914000040_040_admin_rbac.sql` — sets `banbetestadmin@gmail.com` role, extends `handle_new_user()`, admin bypass on `pay-proof` storage read policy
- `src/screens/Disputes.jsx:13` `Disputes()` — web admin dashboard (screen `'disputes'`, reached via `openDisputes` in `src/screens/Account.jsx:145`)
- `apps/ios/BanbeApp/Views/AdminDashboardView.swift:12` `AdminDashboardView` — iOS admin dashboard
- `apps/ios/BanbeApp/State/AppState+Payments.swift:656,666,707` `openAdminDashboard()`, `loadAdminDisputes()`, `resolveDispute()`
- `apps/ios/BanbeApp/Views/AccountView.swift` — "Admin Panel" row, gated `app.isAdmin`
- `apps/ios/BanbeApp/Views/RootView.swift:210` — `.disputes` screen case → `AdminDashboardView()` (was mis-wired to `VerificationsView()` before this pass)

## DB tables/columns
- `public.profiles.role` ('participant' | 'organizer' | 'admin') — NOT 'user'/'host'/'admin', pre-existing values kept
- `public.v_disputes` (view) — RLS via `security_invoker`, admin sees all, organizer sees own events only
- `public.payment_audit_log` — T1/T2/T3 trail, admin-readable via `payment_audit_select_party` policy

## Status: WORKING
Both platforms: list disputes, view receipt image (signed URL, admin bypass added in migration 040), view audit trail, view dispute chat, resolve (uphold/release). No client-side route guard beyond screen-gating + RLS backstop.

## TODO / open questions
- No UI test coverage added for iOS `AdminDashboardView` (web has `payment-state-machine.spec.js:79` for the account-menu gate only, not full resolve flow on either platform).
- ~~Only one designated admin email; no admin-management UI to promote/demote other accounts.~~ Addressed 2026-10-02 — see below.

## 2026-10-02 — Admin Team invites ("Admin Team"/"Invite Admin" in Account → Admin)

**Migration `supabase/migrations/20261102000121_121_admin_team_invites.sql`
— WRITTEN AND LOCALLY VERIFIED, NOT YET APPLIED to any deployed database**
(this environment has no `supabase` CLI/DB credentials, and migrations
require the user's own explicit approval gate before `supabase db push`).

**The actual RBAC decision**: a new `profiles.can_manage_admins boolean`,
distinct from `role = 'admin'` itself — checked separately in every RPC
(`public.can_manage_admins()`). Backfilled `true` for every account that
is ALREADY an admin today (there is only the one, `banbetestadmin@gmail.com`
from migration 040) so nothing existing loses capability. A newly-accepted
admin invite does **NOT** inherit this permission — it has to be explicitly
granted afterward via `set_admin_management_permission()`, by someone who
already has it. This is what stops an unbounded "any admin can mint
infinite admins" chain.

**Mechanics reused, not reinvented**: same shape as `event_invites` (113)/
`organizer_members` (098) — `admin_invites` table (RLS locked, zero direct
write policy, every mutation through a `SECURITY DEFINER` RPC), 32-random-
byte token stored only as its sha256 hash, `find_auth_user_by_email` for
existing-user resolution, identity re-verified against `auth.users.email`
at redemption (`redeem_admin_invite_token`) — a forwarded link cannot grant
a different account access. `admin_action_log` (new, append-only, no
credentials/tokens ever logged) records invite/accept/revoke/grant/revoke-
permission actions.

**RPCs**: `create_admin_invite`, `revoke_admin_invite`,
`redeem_admin_invite_token`, `respond_to_admin_invite` (the actual
privilege-granting step — atomic role flip + invite-row update in one
transaction), `set_admin_management_permission`, `revoke_admin` (demotes
to `participant`; blocks self-revocation unconditionally and blocks
revoking the last remaining admin), `list_admin_roster` (a dedicated,
tightly-scoped read — never a broadened `profiles` RLS policy, so this
doesn't widen any unrelated access to other accounts' profile data).
`expire_stale_admin_invites()` on `pg_cron` (same pattern as
`goc_expire_lapsed_pendings`) keeps the pending-invite badge honest even
without a redemption attempt; falls back to a no-op if `pg_cron` isn't
installed (lazy expiry on actual use still correctly refuses a stale
invite either way).

**Verified end-to-end against a real local Postgres** (Docker, throwaway
container + a minimal stub schema — `auth.users`/`profiles`/`notifications`
stand-ins, `authenticated`/`anon`/`service_role` roles, a `request`-style
session GUC standing in for `auth.uid()`), not guessed: authorized issuer
creates an invite; a non-admin AND an admin-without-`can_manage_admins` are
both correctly `NOT_AUTHORIZED`; a wrong-identity account cannot accept
someone else's invite; the intended recipient accepts and `role` flips to
`admin` (never inheriting `can_manage_admins`); a repeated/duplicate accept
on the same invite is correctly `INVITE_NOT_PENDING`; a revoked invite and
an expired invite are both correctly refused; an email-only invite's token
redemption correctly rejects the wrong identity (`IDENTITY_MISMATCH`) and
succeeds for the right one; `revoke_admin` correctly blocks self-revocation
and blocks revoking the last remaining admin, and succeeds otherwise.

**Client-side proactive resync** — `revoke_admin()` inserts an
`admin_access_revoked` notification; both platforms' existing 5s
notification poll (not just the tap handler) immediately patches
`accountType`/`canManageAdmins` and bounces off the Admin tab if it was
open — revocation invalidates access within one poll cycle, not at next
sign-in (same "proactive, not tap-gated" pattern `booking_declined`'s
Going-tag refetch already established, see this file's own 2026-09-17
section above).

**UI**: Account → Cá nhân gets the same conditional invite banner shape as
the existing Team-invite banner (reachable regardless of current role —
the invitee isn't an admin yet); Account → Admin gets a new "Đội Ngũ Quản
Trị"/"Admin Team" group card (badge = real pending-invite count, only ever
populated for a `can_manage_admins` account — RLS denies the read
otherwise) opening the shared `AccountGroup`/`AccountGroupView` child
screen (`adminTeam` key) — invite form with an explicit confirm step
(type email → "Invite \<email\> as a banbe admin?" → Confirm/Cancel, never
sent on one tap), pending-invites list with inline revoke+confirm, and the
current-admin roster with inline revoke+confirm (self-row has no revoke
button at all).

**Files**: migration 121 (new); web `src/state/GocContext.jsx` (state,
`loadMyAdminInvite`/`respondToAdminInvite`/`loadAdminTeam`/
`confirmAdminInvite`/`confirmRevokeAdminInvite`/`confirmRevokeAdmin` etc.,
`syncUser`'s profile select, the notification poll's `admin_access_revoked`
branch, `openNotification`'s three new cases), `src/screens/Account.jsx`
(banner + group card), `src/screens/AccountGroup.jsx` (`adminTeam` content);
iOS `apps/ios/BanbeApp/State/AppState+AdminTeam.swift` (new),
`AppState.swift` (published fields, `accountGroupTitle`),
`AppState+Data.swift` (`applySession`'s `canManageAdmins` read, the
notification poll's `admin_access_revoked` branch, `openNotification`'s
three new cases), `Models/Profile.swift` (`canManageAdmins` field),
`Views/AccountView.swift` (banner + group card + `ROW_ACCENT_COLORS`),
`Views/AccountGroupView.swift` (`adminTeamContent`).

**Verification performed**: migration verified against a real local
Postgres (above) — not a substitute for confirming it on the real project.
`npx vite build` clean; `xcodebuild -scheme PersonalTeamDebug -sdk
iphonesimulator build` → BUILD SUCCEEDED; `npm run test:unit` 24/24
(pre-existing suite, unaffected). No simulator/device UI run.

**Not done / blockers**:
- **Migration 121 is NOT deployed** — run `supabase db push` (after review)
  before ANY of this works against the real project; until then
  `can_manage_admins`/`admin_invites`/the four new RPCs don't exist there,
  so every call above will error against production as-is.
- **Email delivery for an email-only invite** — `create_admin_invite`
  returns the plaintext token (once, never persisted), but nothing calls
  `/api/notify` yet to actually send it — same gap `create_event_invites`
  (113) already has, same fix shape (`api/notify.js` would need a new
  `admin_invite` case). Only the existing-user, in-app-notification path
  is wired end-to-end today.
- **No admin-permission audit viewer UI** — `admin_action_log` is written
  on every action and RLS-readable by `can_manage_admins()`, but nothing
  reads/displays it yet (direct-query-only for now, same as every other
  not-yet-surfaced audit table in this schema).

## 2026-09-14 — "Khách đúng ▪︎ cấp vé" / "Mở lại chỗ" appeared to do nothing (see 03-dispute-chat.md diagnosis #3 for full detail)

Not caused by the dispute-thread linkage bug (separate root cause). `resolveDispute`
(`src/state/GocContext.jsx`, `apps/ios/BanbeApp/State/AppState+Payments.swift`)
used to `await` the `api/dispute-resolved-email.js` fetch *before* clearing
`disputeBusy`/refreshing the list — a slow/untested Vercel function call
(puppeteer-core + chromium, see `05-notify-retention.md`) silently blocked
every visible sign that `resolve_dispute()` had already succeeded. Fixed in
`supabase/migrations/20260914000043_043_resolve_dispute_self_heal_and_email_decouple.sql`
+ client changes: the email send is now fire-and-forget, after the UI
refresh, on both platforms. **Last fix (042, dispute chat) caused a related
regression on this same screen — double-check `03-dispute-chat.md` before
touching `resolve_dispute()`/`escalate_payment_dispute()`/`reject_payment()`
again.**

## 2026-09-14 — live repro exposed the REAL bug behind "does nothing": P0001 status-transition errors

With the 043 email-decoupling fix in place, the actual server error surfaced
for the first time on ART10025: **"Invalid booking status transition from
cancelled to confirmed"** (uphold) / **"...to expired"** (release seat).

Root cause: `validate_booking_status_transition()` (`supabase/migrations/
20260913000028_028_forfeit_expired_hold.sql:29-44`, the current authoritative
version — trigger on `bookings`, fires on any `status` UPDATE) has NO
allowed transition starting from `'cancelled'` at all — by design, a
cancelled booking is meant to be terminal. `bookings.status` on ART10025 is
`'cancelled'` because `cancel_booking()` (`supabase/migrations/20260911000022_
022_undo_checkin_and_cancel_notifications.sql:103-`, callable by guest,
organizer, OR admin) has no awareness of `payment_state` — it only refuses
when `status` is already `cancelled`/`expired`/`attended`, so nothing
stopped someone from cancelling a booking that was mid-dispute (`payment_
state='disputed'`). `resolve_dispute()`'s two outcomes then tried
`status: cancelled -> confirmed` (via `verify_payment`) and `status:
cancelled -> expired` — both rejected by the trigger, both silently
swallowed by `resolveDispute`'s `console.warn`/`print`-only catch (same
class of gap as the email-blocking bug, just a different call throwing).

`booking_status` has no `'disputed'` value of its own (`pending`/
`confirmed`/`cancelled`/`expired`/`no_show`/`attended` —
`supabase/migrations/20260906000002_002_booking_lifecycle.sql:6`; only
`payment_state` has `'disputed'`) — adding one would be a real
state-machine change. Minimal fix instead, matching what was actually
asked: `supabase/migrations/20260914000044_dispute_resolution_transitions_and_admin_chat.sql`
adds `(OLD.status = 'cancelled' AND NEW.status IN ('confirmed', 'expired'))`
to the trigger's allowed-transitions list — unblocks exactly
`resolve_dispute()`'s two outcomes, nothing broader. `cancel_booking()`
itself was left untouched (not asked, and blocking it from ever touching a
disputed booking is a real policy decision, not a one-line fix).

Applied to production via `supabase db push`. Web build + iOS `xcodebuild`
both green; 75/75 Playwright tests pass. Not verified against the live
ART10025 row itself (no production DB read/write access in this session).

## 2026-09-14 — "Đã xử lý" (resolved) list rows were not clickable; admin could not reopen a closed case

**Root cause**: `src/screens/Disputes.jsx:134-144` (pre-fix) rendered each
`closed` row as a plain static `<div>` — no `onClick`, no expansion state,
no reuse of the `loadAuditTrail`/`openChat`+`DisputeChatPanel` machinery the
`open` rows already had (`Disputes.jsx:75-89`). Purely a UI-wiring gap:
`closed` and `open` both come from the same `s.disputes` array/`v_disputes`
view shape, so no new data-fetching was needed.

**Fix**: `Disputes.jsx` — closed rows now toggle an `expandedClosed` state
per booking; expanded, they show the (permanent, never-purged)
`dispute_reason`/`dispute_resolution` plus the same audit-trail and
`DisputeChatPanel` toggles the open rows use.

**Two access-control gaps found and fixed while verifying "admin only,
blocked after 72h purge" (migration
`20260914000046_046_dispute_reopen_admin_only_and_purge_guard.sql`)**:

1. `dispute_threads_select`/`dispute_messages_select` RLS (migration 033)
   let the guest/organizer read a dispute thread regardless of
   `resolved_at` — within the 72h grace window (before the purge cron
   deletes the row), a guest/organizer could already read their own
   resolved dispute's chat transcript directly, same as an open one.
   Tightened: once `resolved_at` is set, only `public.is_platform_admin()`
   may read the thread/messages; guest/organizer keep read access only
   while it's still open.
2. `resync_dispute_thread()` (migration 043,
   `supabase/migrations/20260914000043_...sql:162-167`) did
   `INSERT ... ON CONFLICT (booking_id) DO UPDATE ... WHERE resolved_at IS
   NULL` — that `WHERE` only guards the `UPDATE` branch of the upsert. Once
   a booking's `dispute_threads` row is hard-deleted by
   `purge_resolved_dispute_threads()` past the 72h window, there's no
   conflicting row, so the bare `INSERT` fired unconditionally and
   silently resurrected a fresh, empty, unresolved-looking thread —
   defeating the purge. Reachable from the client: `loadDisputeChat()`
   (`src/state/GocContext.jsx:1084-1086`) calls `resync_dispute_thread()`
   automatically whenever a thread read comes back empty, which looks
   identical to "purged" from the client's point of view. Fixed by
   refusing to resync once `bookings.dispute_resolved_at` (permanent,
   never purged) is set — the self-heal this RPC exists for only applies
   to a currently-open dispute.

Applied to production via `supabase db push`. `vite build` clean; 75/75
Playwright tests pass (none of the existing suite exercised the resolved
list's detail view, so nothing needed updating there — worth adding
coverage later, see TODO above).

## 2026-09-15 — "Mở lại chỗ" (return to pool) correctly re-opens the slot, but the guest still sees the event under "Going"

**Task 1 — status set + transaction, CONFIRMED not the bug**:
`resolve_dispute()` (currently `supabase/migrations/20260914000047_047_dispute_resolution_stats.sql:80-83`,
superseding the 033/043/045 versions this note already cites) sets, for
the release/"Mở lại chỗ" outcome, `bookings.payment_state = 'expired'`
AND `bookings.status = 'expired'` in the SAME `UPDATE` statement, inside
one PL/pgSQL function body — Postgres runs that as a single implicit
transaction, so there is no separate "slot count" write to get out of
sync with it at all. There is no stored seat-count column this function
touches (`events.seats_remaining` is never written here, or anywhere in
the RPC layer, and isn't queried by any client — see
`05-notify-retention.md`'s architecture note on the static demo catalogue);
"available slots" is a value computed at read time from
`booking_holds_seat(payment_state, hold_expires_at, status)`
(`supabase/migrations/20260913000026_026_payment_state_machine.sql:112-128`)
over live `bookings` rows. Once `status='expired'`, that predicate itself
returns false for this booking — the slot "frees up" as an automatic
consequence of the exact same row update, not a second write. Nothing to
fix here.

**Task 2 — the "Going" list's query, CONFIRMED not the bug either**:
`src/state/GocContext.jsx:472-506` (`loadMyEvents`, formerly an inline
effect) selects `bookings` `.in('status', ['pending', 'confirmed',
'attended'])` — `'expired'` was never in that list. The SQL-level filter
already excludes a released booking correctly, on every single fetch.

**Task 3 (cross-reference) — moot**, since task 2's filter already
excludes task 1's status.

**Task 4 — ACTUAL ROOT CAUSE, a client-side staleness bug**:
the effect that populated `s.attending`/`s.tickets`
(`src/state/GocContext.jsx`, previously inline at the old lines 472-503)
merged every fetch's result into whatever was already there —
`set(prev => ({ attending: [...new Set([...prev.attending, ...attending])],
... }))` — a pure union, never a removal. Once an event_id entered
`attending` it could never leave for the rest of that session: a booking
that stopped qualifying (dispute resolved against the guest, or any other
status change out of the three qualifying values) stayed visible under
"Going" indefinitely, no matter how many times a fresh, *correctly
filtered* query ran afterward — because the code never let a fresh result
replace stale membership, only add to it. `apps/ios/BanbeApp/State/
AppState+Data.swift:184-200`'s `loadMyEvents()` never had this bug — it
does a plain `attending = going` replacement (`:199`), which is what the
web side now matches.

Compounding it: nothing ever re-ran that fetch after the first one. The
effect is keyed only on `s.user?.id` (fires once per sign-in), and
`goGoingList()` (`GocContext.jsx`, formerly line 1433) just changed
`screen`/`eventListMode` — no refetch, no realtime subscription (this repo
has none anywhere, see `03-dispute-chat.md`), no polling. So even
opening the Going tab specifically, at any later point in the same
session, never gave the stale union a chance to be corrected. (A full
browser reload happened to self-correct it, since `attending` isn't
persisted to `localStorage` and the merge starts from `[]` again on a
fresh mount — but the bug reproduces for as long as the tab/app stays
open, which is exactly what the report described.)

**Fix**: `src/state/GocContext.jsx` — the fetch is now a named
`loadMyEvents(uid)` `useCallback` that does a plain replace
(`set({ attending, tickets })`, mirroring iOS), and `goGoingList()` now
calls `loadMyEvents(s.user.id)` every time the Going tab is opened, not
just relying on the once-per-session mount effect. Same fix applied to
`apps/ios/BanbeApp/State/AppState.swift`'s `goGoingList()` (iOS's merge
was already correct, but it had the identical "only fetched once, at
sign-in" gap — added the same refetch-on-open call there for parity).

**Test added** (`tests/dispute-flow-e2e.spec.js`, extending Run B —
"return to pool" — since Home/EventList only ever render the static demo
catalogue and a synthetic test event can never appear there regardless of
this bug, see that file's header): logs the participant in and lets the
mount-effect populate `attending` with the still-valid booking *before*
the dispute is resolved (reproducing "the guest already has the app open
when this stops being true" — a fresh post-resolution login would pass
even against the old buggy code, since a first-ever fetch has no stale
state to wrongly keep). After the admin resolves as "Mở lại chỗ" in a
separate browser context, the SAME already-open participant page opens
the Going tab again and two things are checked: the raw network response
(SQL-level exclusion, task 2) and — the part that actually catches this
bug — a new `data-attending-raw-count` attribute on Account.jsx's
`account-going-card` (`src/screens/Account.jsx`), added purely for this
kind of test observability since the rendered count/list are both
filtered through the static catalogue and can never reflect a synthetic
test event either way. Verified this specific assertion fails (received
`"1"`, expected `"0"`) against the pre-fix union-merge code, and passes
against the fix — confirms the test actually exercises the bug rather
than passing vacuously.

Migration: none needed (no schema/RPC change, client-only). `vite build`
clean; 269/270 pre-existing Playwright tests pass (the one failure is the
pre-existing flaky webkit onboarding-splash timeout, unrelated); both
dispute-flow-e2e runs pass on real Supabase, all 3 browsers.

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
- Only one designated admin email; no admin-management UI to promote/demote other accounts.

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

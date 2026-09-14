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

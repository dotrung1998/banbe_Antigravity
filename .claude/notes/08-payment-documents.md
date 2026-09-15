# Payment documents: auto-generated → organizer-uploaded (Task, 2026-09-16)

## Status (before this pass): WORKING as auto-generation — being replaced

## Confirmed facts (given, not re-derived)
- `public.payment_documents` RLS: `payment_documents_select_guest` (`auth.uid() = user_id`), `payment_documents_select_host` (via `organizers.owner_id`/`user_id`) — **no admin SELECT policy exists**.
- Columns (024): `id, booking_id, event_id, organizer_id, user_id, kind (invoice|receipt), number, issued_at, seller/buyer/event (jsonb), lines (jsonb), total_vnd, currency, pay_method, paid_at, note, created_at`.
- Auto-generation entry point: `api/payment-document.js` (this is actually the *render* endpoint for iOS's web-view print, not the generator — see Task 1 below for the real generator).

## Task 1 — audit: every call site of the auto-generation path, and every screen displaying it

Auto-generation is `public.ensure_payment_document(p_booking, p_kind)` (024:259-378) — a SECURITY DEFINER function that inserts a `payment_documents` row (or re-snapshots an unpaid invoice) the first time it's called for a `(booking, kind)` pair, and is a no-op afterwards (idempotent).

| # | Caller | file:line | Context |
|---|---|---|---|
| 1 | SQL trigger | `supabase/migrations/20260913000024_024_payments_and_documents.sql:495-496` | inside `confirm_payment()` — organizer's "mark as paid" |
| 2 | SQL trigger | `supabase/migrations/20260913000026_026_payment_state_machine.sql:374-375` | inside `reserve_free_event()`-equivalent free-RSVP auto-confirm path |
| 3 | SQL trigger | `supabase/migrations/20260913000026_026_payment_state_machine.sql:677-678` | inside `verify_payment()` (webhook/organizer/admin verification route) |
| 4 | SQL trigger | `supabase/migrations/20260913000025_025_reserve_payment_workflow.sql:117-118` | inside the original reserve-workflow free-event auto-confirm |
| 5 | SQL trigger | `supabase/migrations/20260914000031_031_fix_hold_and_sla_durations.sql:130-131` | same free-event auto-confirm, re-created after a hold/SLA duration fix |
| 6 | SQL trigger | `supabase/migrations/20260917000053_053_hold_seats_guest_notification.sql:110-111` | same again, re-created alongside a guest-notification fix |
| 7 | Web client | `src/state/GocContext.jsx:1440` | `loadDocuments()` — mints a missing **invoice** for every one of the guest's own bookings just from opening the Documents list (guest role, invoice kind only) |
| 8 | iOS client | `apps/ios/BanbeApp/State/AppState+Payments.swift:236` | same, `loadDocuments()` |

All 6 SQL call sites (#1-6) are `PERFORM`-only or assign to a `RECORD` variable inside a `BEGIN ... EXCEPTION WHEN OTHERS THEN NULL END` block (or the caller only reads `.number` off the result, which is NULL-safe in plpgsql) — confirmed by reading each in full. This means **neutering `ensure_payment_document()` itself into a no-op is safe for all 6 without touching any of those 5 large trigger functions' bodies** (see Task 2).

**Screens rendering the generated jsonb (need to switch to rendering `file_path` instead):**

| Screen | file:line | What it does today |
|---|---|---|
| `src/screens/DocumentView.jsx:23` | web | calls `renderPaymentDocument(doc, ...)` client-side, iframes the resulting HTML — the actual viewer |
| `src/state/GocContext.jsx:1477-1487` `downloadDocument()` | web | re-renders the same HTML into a new window and calls `.print()` — web's own "Download ▪︎ Print" |
| `api/payment-document.js` | API | renders the same HTML server-side for iOS's web view (`renderPaymentDocument`, same module) |
| `apps/ios/BanbeApp/State/AppState+Payments.swift:278-284` `documentURL(_:)` | iOS | points `DocumentWebView` at the above API route |
| `apps/ios/BanbeApp/Views/DocumentViews.swift:106-150` `DocumentViewerView` | iOS | hosts that web view + iOS's own print pipeline |

**False positives (checked, NOT part of the rendering pipeline — only import the unrelated `formatVnd` currency formatter from the same file):** `src/screens/Attendance.jsx:3`, `src/screens/Disputes.jsx:3`, `src/screens/PaymentDetails.jsx:4`, `src/screens/Verifications.jsx:3`.

**Entry points into the Documents list** (unaffected by the generation-vs-upload switch, kept as-is): `src/screens/Account.jsx:84,88,120,124`, `src/screens/PaymentDetails.jsx:196`, `apps/ios/BanbeApp/Views/AccountView.swift:66,71,130,135`, `apps/ios/BanbeApp/Views/PaymentViews.swift:454`.

**Organizer action that used to trigger auto-generation as a side effect:** `src/screens/Attendance.jsx:57` `markGuestPaid(g.id)` (→ `confirmPayment` → RPC `confirm_payment` → call site #1 above). Its own on-screen copy (`Attendance.jsx:42`) said "biên nhận sẽ tự phát hành cho khách" ("their receipt is issued automatically") — updated since that's no longer true.

## Task 2 — schema + storage (migration `20260919000056_056_payment_document_uploads.sql`)

- `payment_documents` gains: `file_path text`, `uploaded_by uuid REFERENCES profiles(id)`, `upload_reason text`, `superseded_at timestamptz`, `purge_after timestamptz`.
- **New fact found while implementing**: the existing unique index `payment_documents_booking_kind_idx (booking_id, kind)` enforces *one row ever* per booking+kind — incompatible with Task 5's "keep the superseded row queryable for 24h" requirement (a replacement needs a second row to coexist with the first for that window). Dropped and replaced with a **partial** unique index: `UNIQUE (booking_id, kind) WHERE superseded_at IS NULL` — still at most one *live* document per booking+kind, any number of superseded ones.
- `ensure_payment_document()` (024) redefined as a stub: returns `NULL::payment_documents` immediately, no INSERT. Confirmed safe against all 6 call sites in Task 1's table.
- New private bucket `payment-documents` (image/pdf, 10MB cap — organizer-sourced files are more likely to be a scanned PDF than a phone photo, hence larger than `pay-proof`'s 5MB), path `<booking_id>/<kind>-<timestamp>.<ext>`, same `split_part(name,'/',1) = booking_id` RLS shape as `pay-proof` (005/024). INSERT restricted to the booking's event's organizer; SELECT open to guest + organizer of that booking — **admin excluded on purpose, matching Task 1's confirmed fact; a comment on the policy says so explicitly so a future migration doesn't copy-paste `pay-proof`'s admin bypass onto this one.**
- New RPC `upload_payment_document(p_booking, p_kind, p_file_path, p_upload_reason default null)`: organizer-only (owner_id/user_id of the booking's event's organizer), validates the path's booking-id prefix matches, requires `p_upload_reason` non-empty **only** when a live (non-superseded) document of that kind already exists for the booking (Task 5's replacement gate), supersedes the old row (`superseded_at = now()`, `purge_after = now() + interval '24 hours'`) before inserting the new one, still assigns a real sequential number via the existing `payment_document_counters` series. Inserts the Task 3/6 notification row(s) in the same transaction.
- `profiles.auto_email_documents boolean NOT NULL DEFAULT false` (Task 4).

## Task 3/6 — notifications
New `notifications.kind` values: `payment_document_uploaded` (first upload) and `payment_document_replaced` (Task 6, carries `upload_reason` and the organizer's contact email in `data`). Both inserted directly inside `upload_payment_document()` — atomic with the document row, no client round-trip needed (unlike the email, which needs outbound SMTP and so is client-triggered, see below).

## Task 4/6 — email
No new outbox/cron for this (unlike Task 5's purge, which explicitly asked for one) — `sendWithGmail`/`api/notify.js`'s existing pattern is already client-triggered (the client calls `/api/notify` with its own access token right after an action succeeds, e.g. `claimPendingReferralAndWelcome`'s `welcome`/`referral_joined` calls). Two new `api/notify.js` cases added the same way: `document_uploaded` (attaches the file only if the recipient's `profiles.auto_email_documents` is true) and `document_replaced` (Task 6's distinct notice — always sent regardless of that flag, since its purpose is "act before the old file is gone," not "here's your routine copy").

## Task 5 — purge cron
`api/cron/purge-payment-documents.js`, registered in `vercel.json` alongside the existing `escalate-verifications` entry — hard-deletes (`DELETE`, not soft) `payment_documents` rows (and their storage object) past `purge_after`. Runs daily at `0 10 * * *` (an hour after the existing sweep) — **not** hourly: this project runs on Vercel's Hobby plan (`api/notify.js`'s own comment confirms it, re: the 12-function cap), which only permits daily cron schedules and caps the project at 2 cron jobs total, both already accounted for by this pair. A daily sweep still respects the 24h retention window (a superseded row purges some time within roughly 24-48h of that window closing, never before it).

## Task 7 — admin exclusion, confirmed
Grepped `payment_documents`/`pay-proof`/`payment-documents` across every admin-adjacent file (`Disputes.jsx`, `AdminDashboardView.swift`, `040_admin_rbac.sql`). The only admin bypass that migration 040 ever added is on **`pay-proof`** (guest's payment-proof screenshot, needed for dispute review — legitimate, unrelated to this feature). No admin code path references `payment_documents` or reads from it. Nothing to remove; the new `payment-documents` bucket's RLS was written to keep it that way (see Task 2).

## UI placement (not ambiguous — user specified it)
Task 4 said "same screen/pattern as locale/theme in `public.profiles`" — that's `src/screens/Preferences.jsx` (web) / iOS's equivalent preferences view, both already writing straight to `profiles` via the existing `persistAccountPreference()` pattern (web) — reused as-is, no new RPC needed since `profiles_update_own` RLS already covers this column.

Upload/replace entry points (not specified by the user, my call): `Attendance.jsx`'s guest row (where `markGuestPaid` already lives — the natural place an organizer is looking at a specific booking right after payment) for first uploads, and the Documents list's host-role row / `DocumentView`'s organizer-only "Replace" action for replacements.

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

## 2026-09-20 follow-up — long-term retention, advance-warning reminders, storage guard, pre-migration cleanup

**Context**: this Supabase project is on the Free plan (500MB DB / 1GB storage, confirmed via dashboard) and 056's `purge_after` was only ever set on a *superseded* row — a live, never-replaced document had no expiry at all. Fixed with a long (12-month, event-anchored), warned-in-advance window instead of anything aggressive, per Vietnamese accounting-record prudence.

### Task 1 — 12-month retention on first upload (migration `20260920000057_057_payment_document_retention.sql`)
`upload_payment_document()` (056) re-created to also set `purge_after` on the newly-INSERTed row — but only in the non-replacement path. A replacement's *old* row is untouched (still 056's 24h logic via `v_existing`'s `UPDATE`); its *new* row gets the same 12-month clock as any first upload. Anchor is `COALESCE(events.starts_at, event_date+event_time, now()) + interval '12 months'` — `events.starts_at timestamptz` is the primary anchor (001_core_schema.sql:74), `event_date date`/`event_time time` (001:75-76) the fallback for a row where `starts_at` was never backfilled.

### Task 2 — advance-warning reminders (same migration + `api/cron/purge-payment-documents.js` extended, not a new cron — Hobby plan caps this project at 2 total, both already spoken for)
- New columns `reminder_7d_sent_at`/`reminder_1d_sent_at` (057).
- Cron now runs reminders *before* the purge sweep each day: a 1-day query (`purge_after <= now()+1d AND reminder_1d_sent_at IS NULL`) and a 7-day query (`purge_after <= now()+7d AND purge_after > now()+1d AND reminder_7d_sent_at IS NULL`) — the `> now()+1d` guard on the 7-day query is deliberate: a *superseded* row's 24h `purge_after` is never more than a day out, so it only ever qualifies for the urgent 1-day reminder, never a misleading "7 days left" one on something that's actually about to go in hours.
- Each reminder emails (with a signed-URL "Download" link, 10-day expiry for the 7-day notice/2-day expiry for the 1-day notice — both comfortably past the threshold they warn about) **and** in-app-notifies (new `notifications.kind` values `payment_document_expiring_7d`/`payment_document_expiring_1d`) every real recipient: the participant (`booking.user_id`) **and** the organizer (`organizers.owner_id`/`user_id`) — per the ticket's "to the participant (and organizer)".
- New fact: PostgREST embedding a related table through a text FK (`payment_documents.organizer_id → organizers.id`) uses the bare table name (`organizers ( owner_id, user_id )`), not `alias:column(...)` — confirmed by a live query against the linked project before trusting it in the cron.

### Task 3 — storage-usage guard, concrete numbers (queried live via `supabase db query --linked`, not estimated)
- Whole-project DB size: **19,500,179 bytes (~19 MB)** of the 500MB cap.
- `payment_documents` table (incl. indexes): **172,032 bytes (168 kB)**, 26 rows before cleanup.
- Whole-project Storage usage (all buckets): **17,075,630 bytes (~16.3 MB)** of the 1GB cap — `pay-proof`: 92 objects / 16,967,907 bytes; `payment-documents`: 1 object / 107,723 bytes (one real test upload from building this feature, a PDF — not one of the auto-generated rows Task 4 removed, and deliberately left alone). `event-photos`/`pay-qr` currently empty.
- **Runway estimate**: remaining storage ≈ 1,056,666,194 bytes (~1,008 MB). At the one real sample's size (107,723 bytes/file, a PDF) that's **~9,800 uploads** before the 1GB cap — but a single sample isn't a real average; a typical organizer photo (this app's own `normalizeProofFile` caps images around a few hundred KB) or a multi-page scanned PDF (uncompressed, passed through as-is) could run anywhere from ~200KB to a few MB, giving a realistic range of roughly **500–5,000 uploads** before hitting 1GB. The 500MB DB cap is not the binding constraint either way — `payment_documents` rows are small (168kB for 26 rows including index overhead); thousands of uploads would add only single-digit MB to the DB.

## 2026-09-17 follow-up — real-iPhone "receipt won't load" report: strong lead REFUTED by live production data

**Context**: a follow-up prompt suspected `payment_documents_bucket_read`'s
`split_part(objects.name, '/', 1) = booking_id` RLS assumption was violated
by a path-construction mismatch between image and PDF uploads (8616a8e's
timeout/retry fix never actually restoring load-ability). Checked directly
against production via the service-role key already in `.env.local`
(`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`) — **every part of this
hypothesis is false**, confirmed with real objects, not assumptions:

- Queried `payment_documents` for the two real just-uploaded receipts: one
  `.pdf` (`209f356f-c6d1-4bd1-bfe2-423e30db390f/receipt-1789650394640.pdf`),
  one `.webp` (`9baf4be7-fe03-4dd4-80d0-bfc16a48bec7/receipt-1789650129477.webp`).
  Both `file_path`s have the booking id as their exact first path segment,
  character for character — the web upload path
  (`GocContext.jsx:1742`, `` `${bookingId}/${kind}-${Date.now()}.${ext}` ``)
  is what wrote both; there is no image-vs-PDF branch divergence in it.
- Storage `object/list` confirms both objects actually exist at those exact
  paths with correct `mimetype` (`application/pdf` / `image/webp`).
- `bookings.event_id` → `events.organizer_id` chain resolves for the PDF's
  booking (event `sonmai` → organizer `org_sonmai`), so the RLS join itself
  has real rows to match against — not an orphaned booking/event.
- Signed both objects via the real `/storage/v1/object/sign/payment-documents`
  endpoint (both the single-path and the bulk `paths:[...]` shape the iOS
  SDK's `createSignedURLs` actually calls) — both return a normal
  `{path, signedURL}` matching the requested path exactly, no error.
- Fetched the signed URL's actual bytes: `HTTP/2 200`, correct
  `content-type` (`application/pdf` / would be `image/webp` for the other),
  **no `Content-Disposition: attachment`** (so a WKWebView load wouldn't
  silently turn into an undisplayable download), tested with both a plain
  curl UA and a real iPhone Safari UA string — no Cloudflare challenge
  either way.
- Re-read `signedDocumentFileURL()` (`AppState+Payments.swift:381-409`) and
  its `makeSignedURL()` counterpart in the vendored supabase-swift package
  (`StorageFileApi.swift:552-582`) end to end — the relative `signedURL`
  string the server returns is correctly resolved against
  `configuration.url` into an absolute URL; nothing is dropped or
  mismatched. `PaymentDocument.filePath`'s `CodingKeys` (`file_path`) also
  decode correctly, so `isUploaded`/`doc.filePath` won't spuriously fall
  back to the dead legacy `ensure_payment_document()` HTML path.

**Conclusion**: the data layer, RLS, signing, and HTTP delivery are all
verified correct in production for the exact two files the user uploaded.
The "both image and PDF fail to load" symptom is real (per the user) but is
not explained by anything server/RLS/path-construction-side — it has to be
something in the live client runtime on that specific real device (session/
auth state, WKWebView rendering behavior, or something else not visible
from static code + REST/curl checks). Reproducing it needs an actual
interactive trace on that device (exact error/behavior: a `documentFileURLFailed`
retry banner appearing, vs. a blank/white viewer with no error, vs. a crash)
— none of which this pass could safely fake without guessing.

### Task 4 — pre-migration cleanup (migration `20260920000058_058_cleanup_auto_generated_documents.sql`)
Deleted **25 of 26** `payment_documents` rows (every one with `file_path IS NULL` — the old `ensure_payment_document()`-minted rows). The 1 surviving row is the real test upload mentioned in Task 3 above (has a real `file_path`, correctly not matched by the `WHERE file_path IS NULL` cleanup condition — this predates migration 057, so it has no `purge_after` either; left as-is, not backfilled, since it wasn't part of what was asked). `payment_document_counters` reset from 20 rows (several already past `next_number = 1`, e.g. `org_vuonsau`/invoice at 3) to **0 rows** — deleted outright rather than zeroed, since `upload_payment_document()`'s own `ON CONFLICT ... DO UPDATE` recreates a row at `next_number = 1` the moment each organizer/kind/year is next actually used. Confirmed post-migration: 1 remaining `payment_documents` row, 0 with `file_path IS NULL`, 0 counter rows.

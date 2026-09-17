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

**Fix applied (63bc160)**: `DocumentWebView.Coordinator` (`DocumentViews.swift`)
only treated an outright network failure (`didFailProvisionalNavigation`) as
an error — a non-2xx HTTP response (expired/invalid signed URL, a storage
error body) still counted as a normal `didFinish`, so it silently rendered
the error body in place of the document with no retry banner. Added
`webView(_:decidePolicyFor:decisionHandler:)` to treat any non-2xx response
as a failure. **This is a detection fix, not a root-cause fix** — see the
next entry, which re-investigates why the request is non-2xx in the first
place after this didn't resolve the user's real-device report.

## 2026-09-17 follow-up #2 — re-tested after 63bc160, still fails: signing/RLS/expiry ruled out live, root cause still real-device-only

**Context**: user re-tested on the real iPhone after both 24129a2 (path
mismatch ruled out) and 63bc160 (non-2xx detection) — still gets a
load/print failure. Since 63bc160 only makes a failure *visible*, this means
the signed-URL request itself is genuinely still failing. The previous
pass's checks all used the **service-role key**, which bypasses storage RLS
entirely — it never actually exercised the real authenticated-user code
path (`createSignedURLs` under RLS, the exact call `signedDocumentFileURL()`
makes). That gap is closed here.

**What was tested this time — a real anon-key session under real RLS, not
service role**: built an isolated repro using `tests/e2e/setup.mjs`'s
existing fixtures (`createTestUser`/`createOrganizer`/`createEvent`/`signIn`)
— created a fresh organizer + participant + event + booking, had the
*organizer's own authenticated anon-key session* upload a real object and
call `upload_payment_document()` (exercising the INSERT/RPC RLS too, not
just SELECT), then had the *participant's own authenticated anon-key
session* (the actual guest, i.e. the same actor/call shape as the iOS/web
app) call `storage.from('payment-documents').createSignedUrls([path], 600)`
— both immediately and again after a 65s wait:

- Both attempts returned a real `signedUrl` with no error, immediately and
  after the delay — RLS authorizes the real guest correctly, and a signed
  URL freshly generated 65s apart both fetch `200` with the correct
  `content-type`.
- This rules out: RLS denying the real (non-service-role) authenticated
  user, and the 600s signed-URL expiry being stale by the time the user
  gets around to viewing/printing (print itself doesn't even re-request —
  it calls `webView.viewPrintFormatter()` on the already-loaded content,
  confirmed at `DocumentViewerView.swift`'s print button — `printing = true`
  → `DocumentWebView.updateUIView` → `present(printFor:)`, no network call).
- Script used: ad hoc, not checked into the repo (used real test accounts
  under the `doqanh0906+banbe-e2e-*` Gmail alias convention already
  established by `tests/e2e/setup.mjs`, cleaned up after itself via the
  existing `cleanup()` helper).

**Conclusion**: signing, RLS-under-a-real-user-session, and expiry are now
*all* verified live and clean — this closes out essentially every
server/RLS/timing hypothesis raised by either investigation pass so far. Combined with
the prior pass's clean HTTP/content-type checks, the remaining explanation
has to be specific to the actual real device's own session state (e.g. a
stale/invalid persisted refresh token failing silently) — something no
clean-room script reproduces, because a fresh script always starts from a
just-issued, valid session, unlike a real device that's been signed in for
a while across app restarts/backgrounding.

**Fix applied (this pass)**: since the actual trigger still can't be
reproduced without a live device trace, and guessing at a fix here would
repeat 8616a8e's mistake (masking a symptom instead of fixing a cause), the
change made is diagnostic rather than corrective: `signedDocumentFileURL()`
(`AppState+Payments.swift`) now distinguishes and surfaces *why* it returned
nil — a thrown error (e.g. an auth/session failure), a per-path
`.failure(path:error:)` from the sign API itself, or the 12s timeout —
via a new `documentFileURLErrorDetail` published property, shown in small
print under the existing "couldn't load" retry banner
(`DocumentViewerView.swift`). `DocumentWebView`'s non-2xx handling (63bc160)
similarly now captures the actual HTTP status code into a `failedDetail`
binding shown next to its own retry text. **Next time this reproduces on a
real device, the on-screen error detail itself should say which of the
three remaining live hypotheses (auth/session failure, a genuine per-path
storage-side failure, or a slow/hung request) it actually is — no further
data-layer investigation should be needed before that detail is read.**

## 2026-09-17 follow-up #3 — separate bug found: print itself silently drops via UIPrintInteractionController re-entrancy

**Symptom**: not a load failure this time — tapping "Tải về ▪︎ In" on a real
iPhone produced repeated `"cannot add handler to 0 from 0 - dropping"` in
the Xcode console and no job ever reached Print Center. Reported as
starting only after 8616a8e/63bc160.

**Root cause, confirmed**: `present(printFor:)`
(`DocumentViews.swift`, `DocumentWebView.Coordinator`) uses
`UIPrintInteractionController.shared` — the only way to get an instance at
all (`UIPrintInteractionController.h:41`: the class has **no public
`init`**, only the `sharedPrintController`/`.shared` class property — so
"create a fresh instance per attempt" isn't actually available via the
public API, contrary to what a first read of this bug class suggests).
`updateUIView` (`DocumentWebView`) guarded against calling `present()`
twice for one tap by resetting the `printRequested` binding — but that
reset is itself deferred (`DispatchQueue.main.async`, required because
SwiftUI forbids synchronous state mutation from inside a view update),
while the `present(printFor:)` call right after it runs immediately. If
`updateUIView` fires again before that deferred reset executes — e.g.
because some unrelated `@Published` field on the shared `AppState` changes
(unrelated to this diagnosis, but 8616a8e and this pass's earlier work both
*added* published fields this screen observes — `documentFileURLFailed`,
`documentFileURLErrorDetail`, `loadFailedDetail` — meaning there are more
things now that can trigger a stray re-render mid-tap than before those
commits, which fits "only started after 8616a8e") — `printRequested` is
still `true`, and `present()` gets called a second time on the same shared
controller before the first call has resolved. That double-call is what
iOS's print stack logs as "cannot add handler to 0 from 0 - dropping": the
second `present()` tries to register a completion handler on a
connection/job the first call already owns (and is possibly already
tearing down), and it's silently discarded rather than erroring.

**Fix applied**: added a synchronous, `Coordinator`-owned guard
(`isPresentingPrint`) that is not tied to SwiftUI's render timing —
`present(printFor:)` now no-ops if a previous call hasn't resolved yet, and
only clears the guard from `UIPrintInteractionController`'s own completion
handler (or immediately if `presentAnimated:completionHandler:`'s `Bool`
return says it never started at all — e.g. printing unavailable — since the
completion handler then never fires). The `printRequested` binding's
existing async reset is kept (still needed so a later, separate tap can
re-trigger the flow) but is no longer what prevents re-entrancy.

**Not yet verified on a real device** (no physical iPhone or interactive
simulator session available from this pass) — confirmed only via a clean
`xcodebuild` build. Next real-device retest should tap print multiple times
in a row, including once after a retry, and confirm: no "cannot add
handler" log, and a job actually reaches Print Center/AirPrint each time.

## 2026-09-17 follow-up #4 — Documents list showed fake "0đ" for uploaded receipts, replaced with event + date

**Context**: `payment_documents.total_vnd defaults to 0` and is never
populated by `upload_payment_document()` (056, confirmed re-reading its
`INSERT` — only `booking_id, event_id, organizer_id, user_id, kind, number,
file_path, uploaded_by, upload_reason` are set) — it's only meaningful for
the legacy structured-invoice path (024's `ensure_payment_document()`,
which does populate `seller`/`buyer`/`event`/`lines`/`total_vnd` from a real
snapshot). The Documents list (`src/screens/Documents.jsx:59` web,
`apps/ios/BanbeApp/Views/DocumentViews.swift:85` `DocumentsView.row(_:)`
iOS) rendered `formatVnd(total_vnd)` unconditionally, showing a fake "0đ"
next to every raw-uploaded receipt/invoice.

**New fact confirmed live** (not assumed): built an isolated repro
(same `tests/e2e/setup.mjs` fixtures as the 2026-09-17 #2 entry) — a real
`upload_payment_document()`-created row has `event: {}` (the jsonb
default) and `event_id` populated, confirmed both on the RPC's own return
value and on a plain `select('*')` read back as the real guest. **The `event`
jsonb snapshot is never populated on an uploaded document** — only a legacy
structured invoice (024's generator) sets it, with shape `{id, key, name,
date, time, area, booking_code}` (`024:359-363`). Also confirmed live: a
`select('*, events(name, starts_at, event_date, event_time)')` embed via the
`event_id` FK works correctly under the real guest's RLS session (not just
service-role) and returns a normal nested object keyed `events` (plural —
no collision with the existing singular `event` jsonb column).

**Fix applied**:
- `src/lib/paymentDocument.js` — added `formatShortDate(value, lang)`
  ("12 Thg 9" / "Sep 12") and `eventDateAnchor(event)` (starts_at falling
  back to event_date+event_time — same precedence as 057's retention clock).
- `src/state/GocContext.jsx` `loadDocuments()` — select now embeds
  `events(name, starts_at, event_date, event_time)`.
- `src/screens/Documents.jsx` — the amount line only renders when
  `total_vnd > 0`; otherwise renders `"<event name> · <date>"`, sourced from
  the jsonb `event` snapshot when populated (legacy invoices), else the
  `events` join (uploads).
- iOS: `PaymentDocument.swift` — added `PaymentDocumentEventJoin` (decodes
  the `events(...)` embed), `events` field on `PaymentDocument`, `date`/
  `time` added to `DocumentEvent` (was silently dropping those jsonb keys
  before), `formatShortDate(_:lang:)`, and `displayEventCaption` (mirrors
  the web's source-picking logic). `AppState+Payments.swift`
  `loadDocuments()` select updated to match. `DocumentViews.swift`
  `DocumentsView.row(_:)` updated the same way as the web row.

**Verified end-to-end against a real uploaded receipt under real RLS** (not
service-role, not a static read) — the exact query+logic now in
`Documents.jsx` returns, for a freshly uploaded receipt with `total_vnd: 0`:
rendered row's third line = `"E2E dispute-flow test event (cap) · 12 Thg 9"`
(vi) / `"... · Sep 12"` (en) — no "0đ" anywhere. `xcodebuild` and `vite
build` both succeed for the iOS/web changes respectively.

## 2026-09-17 follow-up #5 — Check-in "Upload Receipt" always failed on replace (REASON_REQUIRED), plus 1a2767c's caption alignment/size

**Context**: commit 1a2767c added the event/date caption; this pass covers
two separate follow-ups against it and against a pre-existing bug in the
Check-in screen's upload flow.

**BUG 1 — replacing a receipt via Check-in's "Upload Receipt" always failed.**
Root cause, confirmed by re-reading `upload_payment_document()` (056):
it raises `REASON_REQUIRED` whenever a live document already exists for
the booking+kind — but `src/screens/Attendance.jsx:61` (web) and
`apps/ios/BanbeApp/Views/AttendanceView.swift:166` (iOS, pre-fix) both
called it with no reason at all, every time. The client's generic
catch-all then surfaced "Couldn't upload. Please try again." for what was
actually always the same, entirely expected exception — not a real failure.

Confirmed live with an isolated repro (same `tests/e2e/setup.mjs` fixtures
as prior follow-ups): a first upload with no existing document succeeds
with no reason; a second upload on the same booking+kind with **no**
reason is rejected with exactly `REASON_REQUIRED`; the same second upload
**with** a reason succeeds, supersedes the first row (`superseded_at` set,
`purge_after` = +24h) and inserts a live replacement (`purge_after` =
+12 months, migration 057's anchor). This is the exact mechanic the fix
below now drives correctly.

**Fix applied**:
- `src/state/GocContext.jsx` `uploadPaymentDocument()` — now returns the
  RPC's actual exception code (`REASON_REQUIRED`, `FILE_REQUIRED`,
  `AUTH_REQUIRED`, `NOT_AUTHORIZED`, `INVALID_PATH`, `BOOKING_NOT_FOUND`)
  instead of collapsing every failure into `UPLOAD_FAILED`.
- `src/screens/Attendance.jsx` — `onReceiptFileChosen` now checks the
  freshly-loaded guest's `hasReceipt` (see below) and, only when true,
  shows an inline reason textarea (`pickReceiptFile` no longer uploads
  immediately in that case) before calling `uploadPaymentDocument()` with
  the reason; a first upload skips this and uploads immediately, matching
  the RPC's own condition exactly. The error line now renders
  `uploadErrorMessage(code)` instead of one hardcoded string.
- `src/state/GocContext.jsx` `loadAttendanceGuests()` — now also queries
  `payment_documents` (`kind=receipt`, `booking_id IN (...)`,
  `superseded_at IS NULL OR purge_after > now()`) and attaches
  `hasReceipt`/`receiptVersionCount`/`receiptPendingDelete` per guest. The
  version indicator (`"Phiên bản hiện tại (N) · M bản cũ sẽ xoá trong
  24h"`) only renders when `receiptPendingDelete > 0`, to avoid cluttering
  the far more common single-upload case with a redundant "(1)".
- iOS: `AppState+Payments.swift` `uploadPaymentDocument()` already accepted
  a `reason` param and already special-cased `REASON_REQUIRED` in its
  catch block (pre-existing) — extended the same catch to cover
  `FILE_REQUIRED`/`NOT_AUTHORIZED`/`BOOKING_NOT_FOUND` too, matching the
  web's mapping. `AppState.swift` `AttendanceGuest` gained
  `hasReceipt`/`receiptVersionCount`/`receiptPendingDelete`;
  `AppState+Data.swift` `loadAttendanceGuests()` runs the equivalent
  `payment_documents` query. `AttendanceView.swift` — picking a file now
  reads it into memory immediately (`handlePickedReceipt`, not deferred,
  since a `fileImporter` URL's security-scoped access isn't guaranteed to
  survive across view updates) and, when `hasReceipt`, holds it in
  `pendingReplace` behind an inline reason `TextField` before calling
  `uploadPaymentDocument()`; the version indicator and real error message
  are shown the same way as web.

**Verified end-to-end** (not just read): the isolated repro's actual
numbers after a real replace — one superseded row (`pendingDelete: 1`),
one live row (`live: 1`) — are exactly `receiptVersionCount: 2`,
`receiptPendingDelete: 1`, i.e. the rendered label reads **"Phiên bản hiện
tại (2) · 1 bản cũ sẽ xoá trong 24h"**, matching the ticket's own example
verbatim. `xcodebuild` and `vite build` both succeed.

**BUG 2 — 1a2767c's caption line was too small/faint and sat low.**
Reported as "lệch xuống" (sitting low) and hard to read. Root cause on web:
the caption span had no explicit `lineHeight` (unlike a plain default), and
was sized/weighted the same as the plain secondary "number ▪︎ party" line
above it (11.5px, regular, opacity 0.7) rather than the amount line it was
actually replacing (12.5px, semibold) — under-weighted for what is, in the
uploaded-receipt case, the most useful line in the row. On iOS, the
equivalent `Text(caption)` had the same mismatch (11.5pt regular vs. the
amount branch's 12.5pt semibold).

**Fix applied**: matched the caption's styling to the amount line it
replaces on both platforms — 12.5px/pt, semibold, and gave all three lines
in the web row (`Documents.jsx`) an explicit `lineHeight: 1.3` so they sit
on a consistent rhythm rather than depending on the browser's/font's
default leading for one line and not the others. `xcodebuild`/`vite build`
both succeed; **actual rendered-pixel alignment not verified in a running
browser or simulator from this pass** (no visual session available) — if
it still reads off after this, the next thing to check is `DISPLAY_FACE`'s
(web) or `BanbeTheme.display`'s (iOS) own font metrics against the plain
system font used by the sibling lines, since a custom display face's
line-height/baseline can differ from a system font at the same declared
size even with `lineHeight` set explicitly.

## 2026-09-17 follow-up #7 — BUG 1: both receipt versions now individually viewable; BUG 2: found and fixed the actual root cause (a genuinely blank headline line)

**Context**: follow-up #5's version-count indicator ("Phiên bản hiện tại (2)
· 1 bản cũ sẽ xoá trong 24h") only ever showed a count on Attendance — no
screen let anyone actually open the still-live superseded copy during its
24h grace window. Separately, the user re-tested #4's caption fix and it
still looked wrong on the real guest Receipts screen.

**BUG 1 — both versions now listed and individually tappable**:
- `src/state/GocContext.jsx` `loadDocuments()` (Documents.jsx's query, both
  host and guest roles) — filter changed from `superseded_at IS NULL` to
  `superseded_at IS NULL OR purge_after > now()`. RLS
  (`payment_documents_select_guest`/`_host`, 024) doesn't gate on
  `superseded_at` at all, confirmed by re-reading it, so this is purely a
  query-filter change, not an access-control one. A superseded row simply
  stops matching once `purge_after` passes (hard-deleted by the purge
  cron) — no separate hide-it step needed.
- `src/screens/Documents.jsx` — each row now shows "Bản cũ · xoá sau 24h"
  (superseded) or "Bản hiện tại" (only shown when a superseded twin for the
  same `booking_id` is *also* in the list — otherwise it's noise on the far
  more common single-version case).
- `src/screens/Attendance.jsx`/`GocContext.jsx` `loadAttendanceGuests()` —
  previously only aggregated counts; now also carries each receipt's `id`
  so both the live and any still-live superseded copy render as their own
  tappable row ("Bản hiện tại ›" / "Bản cũ · xoá sau 24h ›"). Reused
  `openDocumentFromNotification()` (originally bell-notification-only) by
  adding a `role` param (default `'guest'`, Attendance passes `'host'`) —
  it already does exactly what's needed here: fetch one row by id and open
  the viewer, without requiring the full Documents list to be loaded first.
- iOS mirrors: `AppState+Payments.swift` `loadDocuments()`'s filter,
  `DocumentsView.row(_:)`'s labels (`DocumentViews.swift`),
  `AppState+Data.swift` `loadAttendanceGuests()`/`openDocumentFromNotification()`
  (added `role` param), `AttendanceGuest.receipts: [AttendanceReceipt]`
  (`AppState.swift`), and `AttendanceView.swift`'s per-receipt tappable rows.

**BUG 2 — actual root cause found, not just another styling tweak**: built
a real end-to-end repro (fresh organizer + guest + event + booking via
`tests/e2e/setup.mjs`, a real uploaded receipt, real sign-in, real
Playwright/Chromium session, injected the real Supabase session the same
way `tests/global-setup.js` does) and took an **actual screenshot** of the
guest's own Receipts screen — not a code read. It confirmed the real cause:
line 1 (`Documents.jsx:72` before this fix) read `doc.event?.name ||
party` directly — for *every* uploaded document, the jsonb `event`
snapshot is always `{}` (follow-up #4's finding) **and**, from the guest's
own view, `party` (`doc.seller?.name`) is *also* always empty (uploads
never populate seller/buyer either, only `booking_id`/`event_id`/etc. —
re-confirmed by re-reading `upload_payment_document()`'s `INSERT`). So line
1 rendered as a genuinely empty `<span>` — which still reserves its own
line-height in the flex column. That invisible blank line sitting above
the real two-line content block was the actual cause of "the caption still
looks off/sits low" through two prior attempts at just tweaking the
caption's own font-size/line-height/opacity — the caption itself was never
actually the problem.

**Fix**: line 1 (the row's headline) now uses the same join-aware
`eventName` the caption already computed (`doc.event?.name ||
doc.events?.name`, falling back to `party` only if that's *also* empty) —
never blank for any document whose event resolves, which is effectively
always. The caption line no longer repeats the event name (redundant now
that the headline reliably carries it) — it shows just the date. Same fix
applied on iOS (`DocumentViews.swift`'s `row(_:)`: `headline` replaces the
old `doc.event.name ?? party`).

**Verified with a real rendered screenshot** (saved during this session,
not committed) of the guest's real Receipts screen showing both an
uploaded receipt's live and superseded copy after a real replace: each row
now reads

```
Đối Thoại Sơn Mài
PT-E2E-ORG-<id>-2026-0002 ▪
Bản hiện tại
10 Thg 7
                                              [Tải về]
```
and, directly below it,
```
Đối Thoại Sơn Mài
PT-E2E-ORG-<id>-2026-0001 ▪
Bản cũ · xoá sau 24h
10 Thg 7
                                              [Tải về]
```
— headline populated, both versions present and independently downloadable,
version label present on both rows. **Could not get an equivalent
Attendance/Check-in screenshot** — see `01-hold-payment.md`'s 2026-09-17
follow-up #6 for why (`Dashboard.jsx`'s event list is a static demo
catalog, so an ad hoc test event never appears there to click into) — the
Attendance-side code change is the same shape as Documents.jsx's, reusing
the same `openDocumentFromNotification()`, and was verified via `xcodebuild`
build success only, not a rendered screenshot.

Both `vite build` and `xcodebuild` succeed.

### Task 4 — pre-migration cleanup (migration `20260920000058_058_cleanup_auto_generated_documents.sql`)
Deleted **25 of 26** `payment_documents` rows (every one with `file_path IS NULL` — the old `ensure_payment_document()`-minted rows). The 1 surviving row is the real test upload mentioned in Task 3 above (has a real `file_path`, correctly not matched by the `WHERE file_path IS NULL` cleanup condition — this predates migration 057, so it has no `purge_after` either; left as-is, not backfilled, since it wasn't part of what was asked). `payment_document_counters` reset from 20 rows (several already past `next_number = 1`, e.g. `org_vuonsau`/invoice at 3) to **0 rows** — deleted outright rather than zeroed, since `upload_payment_document()`'s own `ON CONFLICT ... DO UPDATE` recreates a row at `next_number = 1` the moment each organizer/kind/year is next actually used. Confirmed post-migration: 1 remaining `payment_documents` row, 0 with `file_path IS NULL`, 0 counter rows.

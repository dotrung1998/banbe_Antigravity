# Stage 9-10: Email+PDF notification + soft-delete retention (72h)

## Files / functions
- `api/dispute-resolved-email.js:56` `handler()` — POST endpoint, admin-only (bearer token → `profiles.role='admin'` check)
- `api/dispute-resolved-email.js` `htmlToPdf()` — `puppeteer-core` + `@sparticuz/chromium`, renders transcript HTML to PDF
- `src/lib/disputeTranscript.js:38` `renderDisputeTranscript()` — HTML template (event/guest/organizer/resolution + message rows)
- `api/_lib/email.js` `sendWithGmail()` — nodemailer, `attachments` array passed through unchanged
- `api/_lib/emailTemplate.js` `renderEmail()`, `renderEmailText()` — shared email shell, reused as-is
- `src/state/GocContext.jsx:1004` `resolveDispute()` — fires `fetch('/api/dispute-resolved-email')` after RPC success, best-effort
- `apps/ios/BanbeApp/State/AppState+Payments.swift:707` `resolveDispute()` — same, via `URLSession`
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:304` `purge_resolved_dispute_threads()` — hard DELETE, cron
- `supabase/migrations/20260914000033_033_dispute_thread_and_resolution.sql:324` `cron.schedule('banbe_purge_resolved_dispute_threads', '30 3 * * *', ...)`

## DB tables/columns
- `public.dispute_threads.resolved_at` (soft-delete marker, set by `resolve_dispute`), `.purge_after` (= resolved_at + 72h), `.email_sent_at`
- `public.dispute_threads`/`dispute_messages` — hard-deleted by cron once `purge_after < now()` (72h grace, not immediate)
- `public.threads`/`public.messages` — final one-line system note posted here by `resolve_dispute` ("Dispute resolved. Confirmation email sent to both parties.")

## Status: PARTIALLY WORKING — UNVERIFIED IN PRODUCTION
Code is written, builds, and DB side (soft-delete + 72h purge cron) is applied and mechanically correct. Email+PDF send path (`puppeteer-core`/`@sparticuz/chromium` inside a Vercel function) has **never been executed against a live Vercel deployment** in this session — no serverless runtime available to test. Requires `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `SUPABASE_SERVICE_ROLE_KEY` env vars set on Vercel.

## TODO / open questions
- Confirm `puppeteer-core`+`@sparticuz/chromium` actually launches within Vercel's function size/memory limits — first real dispute resolution should be watched closely.
- ~~`resolveDispute()` posts the "Dispute resolved" note into the ORDINARY thread synchronously (DB RPC), before the email is confirmed sent~~ — FIXED, see 2026-09-14 entry below.
- No retry/alerting if `dispute-resolved-email` fails; `disputeEmailError` only surfaces in the admin's own UI at the moment of resolution, nowhere persisted for later follow-up. Still true after today's fix.
- Cannot verify from this session whether `GMAIL_USER`/`GMAIL_APP_PASSWORD`/`SUPABASE_SERVICE_ROLE_KEY` are actually set in the LIVE Vercel deployment's env — `.env.example`/`.env.local` in this repo only affect local dev, Vercel env vars are configured separately in their dashboard and out of this session's reach.

## 2026-09-14 diagnosis — reported bug: "Confirmation email sent" message appears, but no email ever arrives (real inboxes tested)

Confirmed **(c) hardcoded success message, never tied to a real send** —
plus two additional silent-failure paths in the email endpoint itself that
would have hidden the problem even after fixing (c) alone.

**(c) CONFIRMED**: the exact string was inserted unconditionally by
`resolve_dispute()` (`supabase/migrations/20260914000043_...sql:110-114`,
the version active before today) — a synchronous Postgres RPC, run as part
of the SAME transaction that resolves the dispute, **entirely before** the
actual email HTTP call (a separate, client-triggered `fetch` to
`api/dispute-resolved-email.js`, deliberately decoupled since migration 043)
even begins. The DB function has no mechanism to await or know the outcome
of that later call — the message was a promise made at resolution time,
not a report made after delivery.

**Two silent-failure paths found in `api/dispute-resolved-email.js`
(pre-fix)**:
1. `admin.auth.admin.getUserById(...)` (guest at the old line ~97,
   organizer at ~99-100) only ever destructured `data`, discarding `error`
   — a failed lookup (deleted account, bad service-role key, transient
   auth-admin API error) silently resolved to an undefined email with
   nothing logged.
2. The send loop (old lines ~151-176) returned `res.status(200).json({
   sent })` **even when `sent === 0`** — if both recipient emails ended up
   unresolvable (via gap 1, or an organizer row with both `owner_id` and
   `user_id` null), the endpoint reported HTTP 200, which the client's
   `if (!res.ok)` check (`GocContext.jsx`'s `sendDisputeResolvedEmail`,
   `AppState+Payments.swift`'s counterpart) reads as success — zero emails
   sent, zero errors surfaced anywhere.
3. (Related, not separately fatal) all sends shared one try/catch — a
   throw on the guest's send aborted the organizer's attempt entirely,
   silently costing both parties their email over one recipient's failure.

**Fixed**:
- `supabase/migrations/20260914000045_045_dispute_email_message_not_hardcoded.sql`
  — `resolve_dispute()`'s system message no longer claims the email was
  sent (now just "Dispute resolved.").
- `api/dispute-resolved-email.js` — `getUserById` errors are now logged;
  each recipient's send has its own try/catch (one failure no longer costs
  the other); `sent === 0` now returns `502 {error: 'NO_EMAIL_DELIVERED',
  failures}` instead of `200 {sent: 0}`; the **real** "email sent" (or
  partial-failure, naming which recipient) confirmation is now posted into
  the guest's ordinary thread by this endpoint itself, only after send(s)
  actually succeed — moved here from `resolve_dispute()`.

Applied to production via `supabase db push`. Web build clean; 75/75
Playwright tests pass (iOS untouched by this fix, no client changes were
needed — the message move is entirely server-side). **Still not verified
against a live send** — this session cannot confirm whether Vercel's
deployed environment actually has working `GMAIL_USER`/`GMAIL_APP_PASSWORD`
values, or whether ART10025's guest/organizer accounts' emails resolve
correctly now that lookup failures are logged — the next real resolution
attempt's Vercel function logs are the way to find out.

## 2026-09-14 diagnosis, continued — recipient-ID trace + PDF-generation isolation (task: pin down (1) vs (2) vs (3))

**Could not execute the live-test task**: no `vercel` CLI, no deployment
token, and no browser session to trigger a real admin resolution in this
sandbox — `which vercel` fails, `~/.vercel` doesn't exist. **This needs the
user (or a session with Vercel access) to trigger one real resolution on
ART10025 (or a fresh test dispute) and pull that invocation's function logs
for `api/dispute-resolved-email.js`** — the fix below adds enough logging
to make that trace conclusive once it's run.

**(1) Recipient ID resolution — traced, CODE IS CORRECT, cannot rule out
bad underlying data:**
- Guest: `booking.user_id` (`api/dispute-resolved-email.js:80-81` select,
  `:102` `getUserById(booking.user_id)`) — `bookings.user_id` is the
  booking's own guest column; this is the right id for whoever actually
  reserved and disputed the seat.
- Organizer: `organizer.owner_id || organizer.user_id` (`:93-94` select via
  `thread.organizer_id`, `:104-109` `getUserById(organizerUserId)`) —
  `dispute_threads.organizer_id` is populated/self-healed from
  `events.organizer_id` by `resolve_dispute()`/`reject_payment()`/
  `escalate_payment_dispute()` (migrations 033/041/042/043/044); `organizers.
  owner_id`/`.user_id` are the account(s) that actually operate that
  organizer page.
- No ID-swap or wrong-column bug found by inspection. Whether ART10025's
  actual `bookings.user_id` is `dotrung1998@gmail.com`'s auth uid and its
  event's `organizer_id` row's `owner_id`/`user_id` is `banbetestadmin@gmail.com`'s
  (or whichever two accounts are the real guest/organizer here) is a data
  question this session cannot check — no production DB read access. The
  new logging (`guest auth lookup failed`/`organizer auth lookup failed`/
  `organizer has no owner_id/user_id`, all already added in the previous
  fix) will show definitively in the Vercel logs if either id fails to
  resolve to a real account.

**(2) PDF generation — CONFIRMED a real, previously unisolated failure
mode, most likely candidate given "neither party received anything":**
`htmlToPdf(transcriptHtml)` (old `:130`) sat directly in the handler's one
shared `try` block, with no isolation from the per-recipient send logic. A
throw there (any `puppeteer-core`/`@sparticuz/chromium` launch/render
failure — a genuinely common serverless failure mode: chromium binary size,
memory allocation, cold-start timeout; this path has never run against a
live Vercel deployment) jumps straight to the handler's outer `catch`,
returning generic `502 SEND_FAILED` **before the send loop runs at all** —
zero attempts for either recipient, indistinguishable from a Gmail-side
failure. This explains "no email to either party" more parsimoniously than
(1), since it fails uniformly for both recipients from one shared cause,
where two independent `getUserById` failures would be a coincidence.

**Fixed**: `api/dispute-resolved-email.js` — `htmlToPdf()` now has its own
try/catch; a failure there is logged distinctly
(`PDF generation failed, sending without the transcript attachment`) and no
longer blocks the email — it sends without the transcript PDF (the receipt
image, if any, and the summary text still go out) instead of silently
sending nothing to anyone. The receipt-image download's `error` is now also
checked and logged (previously discarded like the `getUserById` gaps from
the prior fix).

Not verified against a live send (same limitation as above) — Gmail
transporter/credentials were deliberately NOT touched, since nothing in
this session's log access points there; the next real Vercel invocation's
logs are what would confirm or rule out (1)/(2) conclusively.

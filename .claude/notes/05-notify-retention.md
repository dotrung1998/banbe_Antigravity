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

## 2026-09-14 — real end-to-end run: email delivery CONFIRMED working; root cause of earlier "no email arrives" report was already fixed

Built a real-backend Playwright E2E test, `tests/dispute-flow-e2e.spec.js`
(+ fixtures in `tests/e2e/setup.mjs`/`loadEnv.mjs`) — creates real Supabase
Auth users via the admin API, runs the actual flow through real RPCs and
(for the organizer/admin roles) the real browser UI, and invokes the real
`api/dispute-resolved-email.js` handler directly in Node (not through
Vercel — see the test file's own header for why: the local `vite` dev
server used by `playwright.config.js` doesn't serve `/api/*`, so the
browser's own fire-and-forget call 404s locally regardless of backend
correctness; importing and calling the handler function directly runs the
identical code path, real Gmail send included).

**Result, both outcomes ("ticket approved" and "return to pool"), all 3
browsers: PASS.** `dispute-resolved-email` returned `200 {"sent":2,
"failures":[]}` both times — a real Gmail send to both the guest and
organizer test accounts, `dispute_threads.email_sent_at` stamped
afterward. `getUserById` resolved both test accounts to their real,
correct emails (the specific failure mode this ticket named as a
suspect) — not reproduced. **Conclusion: the email pipeline itself is not
currently broken** — the hardcoded-message and silent-failure bugs fixed
earlier this same day (see the two entries above) were the actual root
cause of the original "no email arrives" report, and this run is the
first time that fix has been verified against a real send rather than by
code inspection alone. If a user reports missing email again, look
elsewhere first: Gmail account state (dotrung1998@gmail.com — the sender
in `.env.local`'s `GMAIL_USER`), spam-folder placement, or a difference
between this sandbox's local run and the live Vercel deployment's actual
environment/runtime (see next paragraph) — not this delivery path itself,
which is now demonstrated working end-to-end.

**One real gap this run surfaced, not previously visible from code
reading alone**: `htmlToPdf()` (`api/dispute-resolved-email.js:35-50`)
failed locally every time — `spawn ENOEXEC`, because `@sparticuz/chromium`
ships a Linux binary and this sandbox is macOS. Already isolated in its
own try/catch (see the PDF-generation-isolation fix above), so it did NOT
block the email — both sends still succeeded, just without the transcript
PDF attached. **This means the transcript-PDF attachment itself is still
unverified against a real send** — Vercel's runtime is Linux, so it
should work there, but this local run cannot confirm it; the receipt
image attachment path (a real download from `pay-proof`, not a
Chromium-rendered file) WAS exercised for real in this run, since the test
uploads a real file to that bucket first.

**Architecture fact found while building this test, appended here since
it constrains what any future E2E test can click through**: `Home.jsx`/
`EventDetail.jsx` only ever render the static demo catalogue in
`src/data/events.js` — there is no live query against the `events` table
and no `?event=` URL param (confirmed by grep: zero references to
`v_event_availability`/`seats_remaining` anywhere in `src/`). A freshly
created test event is therefore never click-reachable via Reserve/
PaymentDetails/Confirmed. `tests/dispute-flow-e2e.spec.js` works around
this by driving the participant's three actions (hold, mark paid, send a
chat message) through an authenticated `supabase-js` client signed in via
`auth.signInWithPassword()` — the same call the real password-login tab
makes — rather than through clicks; the organizer and admin queues
(`Verifications.jsx`, `Disputes.jsx`) have no such dependency (they query
live views by real ownership/RLS) and so those two roles ARE driven
through the real browser UI in that test. Worth fixing properly (a
`?event=` deep link, or a dev-seeded live-queryable demo event) if this
suite's coverage needs to grow to include the participant-side screens.

**Also found and fixed in passing**: `.env.example` (committed to git) had
real production secrets (`SUPABASE_SERVICE_ROLE_KEY`, `GMAIL_USER`,
`GMAIL_APP_PASSWORD`) checked in across several past commits instead of
placeholders — scrubbed back to placeholders this same pass, with the real
values moved to `.env.local` (gitignored, already had `GMAIL_*`). **The
user still needs to rotate the Supabase service_role key and Gmail app
password** — scrubbing the file doesn't invalidate a key that was already
exposed in git history; this session did not rewrite git history (a
separate, bigger decision).

Test is not part of the default fast suite (writes real rows, sends real
mail) — run explicitly: `npx playwright test tests/dispute-flow-e2e.spec.js`.
Requires `SUPABASE_SERVICE_ROLE_KEY` resolvable (via `.env.local` or
`.env`); skips itself with a clear reason otherwise.

## Status: MOSTLY WORKING — email delivery verified locally (real send), PDF attachment still unverified on Vercel
DB side (soft-delete + 72h purge cron) applied and mechanically correct. The email send itself is now confirmed working end-to-end by `tests/dispute-flow-e2e.spec.js` (2026-09-14 entry below) — real Gmail delivery, `sent:2` both outcomes — run directly in Node against the real handler, not through an actual Vercel invocation. **Still unverified specifically on Vercel's own runtime**: whether `puppeteer-core`/`@sparticuz/chromium` actually launches there (this session's local run couldn't test it — Linux-only binary, macOS sandbox), and whether Vercel's deployed env actually has `GMAIL_USER`/`GMAIL_APP_PASSWORD`/`SUPABASE_SERVICE_ROLE_KEY` set to the same values this session used locally.

## TODO / open questions
- Confirm `puppeteer-core`+`@sparticuz/chromium` actually launches within Vercel's function size/memory limits on a live deployment — this session's local Node run hit `spawn ENOEXEC` (Linux binary on macOS), isolated correctly (email still sent, just without the PDF) but not evidence either way for the real Vercel runtime. Watch the next real dispute resolution's Vercel function logs.
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

## 2026-09-14 — reopening a resolved case within the 72h window; anonymized quality-review view (feasibility only)

Investigated whether the 72h purge is actually leak-proof once the admin
"Đã xử lý" list becomes clickable (see 04-admin-escalation.md for the fix).
Found and fixed a real gap: `resync_dispute_thread()`'s upsert could
resurrect a purged `dispute_threads` row (see 04's entry) — fixed in
migration `20260914000046_...sql` by gating it on
`bookings.dispute_resolved_at IS NULL`, and tightened
`dispute_threads_select`/`dispute_messages_select` RLS so a resolved
thread is admin-only even before purge.

**Requirement-2 check (anonymized quality-review view) — does NOT exist.**
No aggregate/summary table or view is defined anywhere in
`supabase/migrations/`: grepped for `dispute_resolution_stats` and any
`CREATE VIEW`/table with "stat"/"summary"/"aggregate" in the dispute
context — nothing. The only resolution-outcome data that exists today:
- `dispute_threads.resolution_kind` (`'ticket_issued'` | `'cancelled'`,
  set in `resolve_dispute()`, e.g.
  `supabase/migrations/20260914000045_045_dispute_email_message_not_hardcoded.sql:63`)
  — lives on the **ephemeral, purged** table. Not safe to build an
  aggregate view on top of this after 72h, exactly the risk flagged in the
  ticket: this column is gone once `purge_resolved_dispute_threads()` runs.
- `bookings.dispute_resolution` (free-text admin note) and
  `bookings.dispute_reason` (free-text organizer "not found" reason,
  `supabase/migrations/20260913000026_026_payment_state_machine.sql:92`)
  — both permanent (never purged), but **free text, not a category enum**
  — "count by dispute reason category" isn't directly derivable from
  either without new structured classification.
- `bookings.disputed_at`/`dispute_resolved_at` — both permanent; the pair
  gives time-to-resolution for free already, no new column needed for
  that one metric.

**Proposed minimal approach (not implemented — feasibility only, per
request)**: a `dispute_resolution_stats` table, one row written by
`resolve_dispute()` itself at the same point it sets `dispute_resolved_at`
(so it survives the 72h purge — it's a new permanent table, not derived
from `dispute_threads`):
```
booking_id uuid (FK, for idempotency/audit only — never joined back to in
                  the aggregate view; not guest/organizer/PII)
resolved_at timestamptz
resolution_kind text            -- 'ticket_issued' | 'cancelled'
reason_category text            -- NEW: requires resolve_dispute() (or the
                                    admin UI) to also capture a fixed-enum
                                    category alongside the free-text
                                    dispute_reason/dispute_resolution —
                                    e.g. 'proof_not_found' | 'wrong_amount' |
                                    'duplicate_claim' | 'other' — since
                                    today's free text can't be grouped
time_to_resolution_seconds int  -- resolved_at - disputed_at, computed once
```
No guest name, ticket/booking id exposed in any SELECT surface, no chat
text, no transaction reference — an admin-facing "quality insights" screen
would query only aggregates (`count(*) group by reason_category`,
`avg(time_to_resolution_seconds)`, `count(*) filter (where resolution_kind
= 'ticket_issued') / count(*)`) over this table, never the raw row, so it
stays safe to use past any individual case's 72h purge. Biggest open
design question before building this: `reason_category` needs a real
fixed-enum input somewhere in the admin resolve flow (a dropdown next to
today's free-text resolution note) — there's currently no such categorized
input anywhere in `Disputes.jsx`/`resolve_dispute()` to source it from.

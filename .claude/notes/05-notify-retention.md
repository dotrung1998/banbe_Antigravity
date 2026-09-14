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
- `resolveDispute()` posts the "Dispute resolved" note into the ORDINARY thread synchronously (DB RPC), before the email is confirmed sent (separate HTTP call) — note can appear before/without email actually landing if the fetch fails.
- No retry/alerting if `dispute-resolved-email` fails; `disputeEmailError` only surfaces in the admin's own UI at the moment of resolution, nowhere persisted for later follow-up.

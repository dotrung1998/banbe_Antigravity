# 41 — Custom domain (www.banbe.app) + Resend email

Status: IMPLEMENTED. Domain change committed+pushed (21ce29e); Resend code committed as f8e1b9d and pushed. Not tested with a real send, and `RESEND_API_KEY` is not yet set in Vercel (as of 2026-10-10).

## 1. Domain switch: banbe-two.vercel.app -> www.banbe.app

Replaced every hard-coded `banbe-two.vercel.app` (12 files, 15 lines):
- Share links: event `/api/photo-share?eid=`, photo `?pid=`, referral `/?ref=` in `src/state/BanBeContext.jsx`; iOS `PhotoViewerView.swift`, `PulseViewerView.swift`.
- iOS API base: `SupabaseService.swift` `apiBaseURL`.
- Emails/docs: wordmark image in `api/_lib/emailTemplate.js` and `supabase/email-templates/password-changed.html`; default origin in `api/payment-document.js`, `src/lib/paymentDocument.js`, `api/_lib/handlers/walletPassIssue.js`, `walletWebService.js`.
- Skipped on purpose: `.kilo/worktrees/*` (separate worktree copies; one has `AUTH_REDIRECT_URL=https://banbe-two.vercel.app/` in `.env.example`).

Outside the code, still required (not done by code):
- Supabase Auth -> URL Configuration: Site URL + Redirect URLs must include `https://www.banbe.app`, else OAuth / password reset / magic link break.
- Google/Facebook OAuth console: add the new origin + redirect URIs.
- Vercel env `AUTH_REDIRECT_URL` (and similar) -> new domain.
- Apple Wallet pass web-service URL and iOS Associated Domains (universal links) if used; rebuild iOS so it picks up the new `apiBaseURL`.
- Redirect apex `banbe.app` -> `www.banbe.app` in Vercel.

## 2. Email provider: Gmail -> Resend

How email works: every email built in code goes through ONE function, `sendEmail()` in `api/_lib/email.js` (nodemailer). `sendWithGmail` is kept as an alias so call sites (`notify.js`, `dispute-resolved-email.js`, `auth/index.js`, `cronPurgePaymentDocuments.js`) did not change. Templates are inline in those files / `api/_lib/emailTemplate.js`; they did NOT need to move to Resend.

Behaviour now:
- `RESEND_API_KEY` set -> SMTP `smtp.resend.com:465`, user `resend`, pass = key. Sender = `EMAIL_FROM`, default `banbe <no-reply@banbe.app>`.
- `RESEND_API_KEY` unset -> falls back to Gmail (`GMAIL_USER`/`GMAIL_APP_PASSWORD`) exactly as before, so a deploy without the key does not break.
- `api/send-email.js` used to have its own Gmail transport; it now uses the shared sender.
- `getMissingEmailVariables()` returns `[]` when Resend is configured.

### Setup checklist (how to teach someone)
1. Resend -> Domains -> add `banbe.app`; add the DNS records (we added via Vercel DNS; Resend verified in ~1 min). Status must be **Verified**. The From address must be on this domain.
2. Resend -> API Keys -> Create. Permission = **Sending access** (not Full access: the app only sends; Full access can manage domains/keys/etc. and is only for admin scripts). Restrict to `banbe.app` if offered. The key (`re_...`) is shown once.
3. Vercel -> Project -> Settings -> Environment Variables:
   - `RESEND_API_KEY` = key, type **Secret**, env **Production** (Preview only if you want previews to send real mail).
   - `EMAIL_FROM` optional, type **Config** (not sensitive).
4. Redeploy (env vars do not apply to existing deployments).
5. Test: trigger a password reset or notification; check Resend -> Emails log for the send/delivery.
6. Supabase Auth emails (confirm signup, reset password, magic link, password-changed) are sent BY SUPABASE, not this code: Dashboard -> Authentication -> SMTP Settings -> same Resend SMTP details (host `smtp.resend.com`, port 465, user `resend`, pass = API key, sender `no-reply@banbe.app`); paste HTML under Authentication -> Email Templates (repo copy: `supabase/email-templates/password-changed.html`).
7. Optional in Resend domain config: click/open tracking (needs a tracking subdomain) and TLS (Opportunistic is fine).

### Monitoring limits
- Resend dashboard: Emails (per-send log + status), Metrics (deliverability), Settings -> Usage/Billing (quota).
- Free plan, from memory (verify on Resend pricing): ~3,000 emails/month, ~100/day, 1 domain. A burst (e.g. host cancels an event with many guests) can hit the daily cap; failures are logged but not retried.
- Watch bounce and spam-complaint rates; high rates can get sending suspended.

### Docs/config touched
`.env.example` (RESEND_API_KEY, EMAIL_FROM, Gmail marked fallback), `README.md` env section.

### Known gaps
- Tests/e2e setup (`tests/e2e/loadEnv.mjs`, `tests/dispute-flow-e2e.spec.js`) still mention Gmail vars; they work via the fallback but have not been run against Resend.
- Older notes (05, 08) still describe `sendWithGmail`/Gmail; accurate only for the fallback path.
- PDF attachments over Resend SMTP unverified (same open question as note 05 for Vercel).

# Phase 0 + push preparation — implementation plan (2026-10-23)

Source: `docs/retention-delight-plan.md` (F1–F4) and the owner's run brief of 2026-10-23 (APPLE / PUSH section).
Status lines live in the plan; this file is the how.

## 0. Ship what is built (F2 + push pre-setup)
- Branch `feat/us-tz-currency-push-presetup`, merge to `main` when green.
- Migration 194 is NOT applied yet, so it is extended in place (no corrective migration needed):
  - `app_feature_flag_defs`: the list of known switches becomes a table (FK from `app_feature_flags`), so new switches
    stop needing a redefinition of the CHECK + `admin_set_feature_flag`. Seeds `push_enabled = false`.
  - `push_enabled` OFF → nothing is queued. ON without APNs credentials → the drain runs dry: it logs counts only
    (kind + environment, never title/body/ids) and marks rows `skipped_no_credentials`.
  - Quiet hours 22:00–07:00 in the device's own zone (tokens now store `timezone`): a push queued at night gets
    `not_before` = 07:00 local; the per-minute tick wakes the drain then. Expiry counts from `not_before`.
  - Promotional kinds (`notification_kind_policy.promotional`) are queued only with `notification_preferences.promo_push`
    = true (default false, owner-only RPCs). Transactional kinds stay opt-out via the existing per-kind mute.
  - Sender env names: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY`, `APNS_ENV` (optional
    override; otherwise each token's own environment). `APNS_TOPIC` kept as an alias.
- iOS: Debug carries the push entitlement (aps-environment) like Release; PersonalTeamDebug stays capability-free for
  free-team devices. Registration runs only while `push_enabled` is on. Q6 contextual ask: after the first confirmed
  booking, a pre-permission sheet, and the system prompt only when the person taps Continue and the switch is on.
- Production: backup → dry-run on a fresh container + on a copy of the production schema → apply 185, 194, 195 one at a
  time (one-file workdir, as in note 58) → grant/RLS audit + old-RPC snapshot after each → F2 check with a rolled-back
  test US event → deploy web.

## F1 — first-party measurement
- `app_events` (id, user_id NULL-able, event name from a fixed list, small props jsonb of ids/buckets only, platform,
  market, created_at), insert only through `log_app_events(jsonb)` (batch, rate-limited, name whitelist, props
  whitelist per name), no client SELECT. Retention 13 months (daily purge in an existing cron).
- Switch `app_events` (OFF): clients only send while it is on. Policy text gated by the same switch.
- `profiles.market` ('VN' | 'US' | NULL), set from the first booked/created event's `country_code`, overridable later.
- `admin_retention_report(p_from, p_to)`: admin only, aggregate only, test accounts excluded, any group < 20 → hidden.
- Web `src/lib/analytics.js` and iOS `Lib/Analytics.swift` get a batching sink to `log_app_events`.

## F3 — trust prerequisites
- 185 applied (above). Age: `set_date_of_birth` refuses under 16 (`AGE_TOO_YOUNG`), web + iOS show why. Existing
  accounts are not re-checked (no lock-outs of test accounts). Policy placeholders: only facts the repo proves are
  filled; the rest are BLOCKED on the owner (registered address, contact email, SMS provider).

## F4 — interviews
- `docs/interview-guide.md` (vi + en): consent script, recruiting message, 5 guest + 5 host questions per market.
  Status "needs owner".

## Apple
- `docs/apple-setup-checklist.md`; Live Activity extension (event day, local-only) — built in L7.

# 60 — US readiness (per-event time zone + currency) and push pre-setup (2026-10-22)

Status: IMPLEMENTED LOCALLY (web + iOS + migrations 194/195 + Vercel handler), NOT committed, NOT applied to
production, NOT deployed. Owner decisions (2026-10-22): the US market is not live yet but must be ready; US events
may be free or priced in USD, but **paid USD booking stays off** (clear disabled state) until a later pass; the paid
Apple Developer account will be bought, so push must work the moment its key exists. Context: plan
`docs/retention-delight-plan.md` items F2 and the APNs blocker.

## 195 — events.tz + events.currency (migration 20261229000195)
- Bug fixed: `create_event_draft`/`resubmit_event_for_review` used `AT TIME ZONE 'Asia/Ho_Chi_Minh'` for every event,
  so a US host's 19:00 was stored as 05:00 Pacific. Now `starts_at = (event_date + event_time) AT TIME ZONE events.tz`.
- `tz` is derived on the server from country/state (`event_tz_for`), or a client zone for US when it is a real US zone
  (`resolve_event_tz`: MapKit knows multi-zone states). VN is always Asia/Ho_Chi_Minh. Unknown US state → TIMEZONE_UNKNOWN;
  other countries → UNSUPPORTED_COUNTRY. Old clients (no `p_tz`) get correct zones too: they send the wall clock.
- `currency` VND|USD from the country. **`price_vnd` keeps its name but means minor units of `currency`** (dong, or
  CENTS for USD); `price_cents` = cents for USD, legacy ×100 for VND. Existing rows stay VND (they were priced in dong);
  a US event becomes USD on its next resubmit. US rows' `starts_at` recomputed in their zone.
- Paid USD booking: `bookings_currency_guard` BEFORE INSERT trigger raises PAID_BOOKING_NOT_AVAILABLE; clients show
  reserve-bar state `currencyUnavailable` ("Paid booking for US events opens soon").
- `get_host_benchmarks(p_cat_key, p_city, p_currency DEFAULT 'VND')`: one currency per pool, day/slot in each event's zone.
- **Also restores what 112 silently dropped from 107** (112 was written from 106; live in production since 112):
  2-per-24h resubmission limit + bookkeeping, DUPLICATE_PENDING_EVENT guard, event_status_history submit/resubmit rows,
  withdrawal reset, anon REVOKE. 107's "coordinates inside Vietnam" check stays removed.
- Shared rules: `src/lib/eventMarket.js` ⇄ `apps/ios/BanbeApp/Lib/EventMarket.swift` ⇄ SQL helpers, vectors in
  `tests/fixtures/event-market.json` (web `tests/unit/eventMarket.test.mjs`, iOS `EventMarketTests`, SQL suite 24).
- Clients select `tz,currency` with a one-time fallback when the DB lacks them (42703), and send `p_tz` ONLY for US,
  so web/iOS keep working against production before 195 is applied. `api/photo-share.js` and Wallet passes format
  times in the venue zone (Wallet derives it from country/state).
- Left VND-only on purpose: booking/refund/dispute amounts (`total_vnd`, `amount_vnd`, SQL '₫' strings), payment
  webhook, Telegram alerts, Reports, surveys, Rewards zones, Home "this weekend" windows (VN offset).

## 194 — push delivery (migration 20261229000194)
- `notifications` AFTER INSERT → `push_enqueue()` → `push_outbox` (only if the recipient has a device token and has not
  muted the kind; mute is now enforced server-side) → `push_kick()` = pg_net POST to `/api/cron?job=push-drain` with URL
  + bearer from Supabase Vault (`push_drain_url`, `push_drain_secret` = CRON_SECRET). Inert without the Vault secrets.
- Drain (`api/_lib/handlers/cronPushDrain.js`, inside the existing cron function — Hobby has 12 functions, all used):
  `push_claim` (SKIP LOCKED, 15-minute freshness, 3 attempts, skips read/muted) → `api/_lib/apnsAlerts.js` (token .p8
  ES256 JWT, sandbox/production per token, BadDeviceToken retried on the other gateway and corrected, 410 tokens
  deleted) → `push_complete`. `bb_push_drain_tick` (pg_cron, every minute) retries/expires/cleans (7 days).
- `device_push_tokens` gains `environment` + `app_id`; `register_push_token(p_token, p_platform, p_environment, p_app_id)`
  (old 2-arg calls still work); `unregister_push_token(p_token)` for sign-out.
- iOS: `Config/Team.xcconfig` (DEVELOPMENT_TEAM, BANBE_PAID_ACCOUNT) drives Debug's push entitlement + ENABLE_PUSH by
  xcconfig indirection; Release unchanged (always push); PersonalTeamDebug untouched (verified with showBuildSettings).
  `PushEnvironment` reads aps-environment from embedded.mobileprovision; AppDelegate is the UNUserNotificationCenter
  delegate (foreground: no banner, refresh; tap → `PushRouting` → `openNotification`, held until sign-in on cold
  launch); badge = unread count; sign-out unregisters the token first. `applinks:www.banbe.app` added.
- Owner runbook: `docs/push-setup.md`; one command for the Team ID: `node scripts/apple-team-setup.mjs --team <ID>`.
- No web push (unchanged); web keeps the in-app toast.

## Verification (2026-10-22)
- SQL: fresh container, all 188 migrations apply; `supabase/_localtest/24_event_tz_currency_run.sh` → push suite 28 checks
  + US suite (fixture vectors + 25 checks) ALL PASS; existing suites run.sh (6 results), 13, 20, 21 ALL PASS; both
  rollbacks apply cleanly inside a rolled-back transaction.
- Web: `npm run test:unit` 394/394; `vite build` ok.
- iOS: unit tests 356 run, 3 failures, none new: GiftTicketPDFTests.testPDFLinksPointAtRealDestinations (2 assertions,
  pre-existing, notes 44/48) and PublicEntryTests.testNotificationsReturnsToWhereItWasOpened (stale test: Home's
  goNotifications opens an overlay; code untouched here). Debug, Release (push compiled in) and PersonalTeamDebug build.
- NOT verified: anything on a device, any real APNs send, screens visually (VI/EN, light/dark), production data.

## Deploy order (when the owner asks)
1. Apply 194 and 195 to production one at a time from a one-file workdir (production lacks 182-185 on purpose; see
   note 58's production log), staging/dry-run first. 2. Deploy web. 3. After buying Apple: `docs/push-setup.md`.

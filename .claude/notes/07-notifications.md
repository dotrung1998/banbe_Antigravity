# Notifications: in-app toast + real push

## Files / functions
- `src/screens/Notifications.jsx:1-76` — full-screen inbox list, pull-only (no toast anywhere in `src/`)
- `src/state/GocContext.jsx:1521-1535` `loadNotifications()`/`goNotifications()` — fetches once at sign-in + once per screen-open, no poll, no realtime
- `apps/ios/BanbeApp/State/AppState+Data.swift:356` `loadNotifications()`, `:351` `goNotifications()` — identical pattern, no local notifications (`UNUserNotificationCenter` grep: zero hits repo-wide)
- `apps/ios/BanbeApp/Views/HomeView.swift:104-135` `PhaseBanner` / `src/screens/Home.jsx:167-198` — persistent status banners, NOT ephemeral toasts (different concept, pre-existing)
- `api/telegram-webhook.js`, `api/cron/escalate-verifications.js`, `public.alert_outbox`/`v_alert_queue` (026:925-982) — organizer-only Telegram alert channel, confirmed intentional stopgap (note 02) for organizers without the app open; never used for the guest

## DB: server-side `notifications` INSERTs that already exist (kind values)
`booking_requested` (026:416), `payment_confirmed`/QR issued (026:707), `payment_disputed` (033:197), `payment_needs_info` (041:87), `dispute_resolved` (047:86), `hold_expired` (028:77), `verification_reminder`/`verification_escalation` (026:958,981), `booking_cancelled` (022:173), `referral_joined` (023:111)

## Gap found: dispute chat message has no notification row at all
`send_dispute_message()` (044:67-105) inserts into `dispute_messages` only — no `notifications` row for the other party. Every other event type above already has a row written server-side.

## Real push infra: NONE
Zero references anywhere (`push_token`/`device_token`/`apns`/`firebase`/`onesignal`/`UNUserNotificationCenter` all grepped, zero hits) — no device-token table/column, no APNs key reference, no push-sending service.

## Status: BROKEN (client never surfaces any notification proactively)
Every event type that already writes a `notifications` row is invisible to a user unless they manually open the bell/Notifications screen — no toast, no badge refresh, no poll. Same root pattern as the "Going" list bug fixed in 04-admin-escalation.md (fetch-once, no invalidation), but here there was never even a UI surface for it beyond the pull screen.

## TODO / open questions
- Toast fix below uses polling (this repo has no realtime channels anywhere, by established convention — see 03-dispute-chat.md) — 5s interval chosen to match existing poll conventions (4s dispute chat, 6s payment status).
- Push (Step 3): token capture + storage wired; APNs send itself blocked on a real `.p8` key — see report for exact credential needed.

## 2026-09-15 — fixed: toast system (web+iOS) + dispute-message notification + push scaffold

**Fixes**: `src/state/GocContext.jsx` (toasts state + `pushToast`, poll rewritten around a `sessionStart` timestamp rather than "seen last poll" — the latter has a real race: a row inserted while the first poll's request is still in flight was already present in that first response and so got marked "already seen," never toasting), `src/screens/ToastStack.jsx` (new), `src/App.jsx`, `src/index.css:gocToastIn/gocToastOut`. iOS mirrors: `AppState.swift` (`toasts`, `pushToast` with `.light` haptic), `AppState+Data.swift` (`startNotificationPolling`/`stopNotificationPolling`, same `sessionStart` fix), `apps/ios/BanbeApp/Views/ToastOverlay.swift` (new), `RootView.swift`.

**Migration** `20260915000048_048_dispute_message_notification.sql`: `send_dispute_message()` now inserts a `notifications` row for whoever didn't send it (guest + both organizer accounts, minus sender/NULLs) — closes the one gap found in Step 1.

**Push (Step 3)**: `20260915000049_049_device_push_tokens.sql` (table + `register_push_token()` RPC, upsert-by-token). iOS: `AppDelegate.swift` (new, wired via `@UIApplicationDelegateAdaptor` in `BanbeApp.swift`) captures the real device token; `AppState+Push.swift` (new) requests permission + calls the RPC. `BanbeApp.entitlements` (new) + `project.yml`'s `CODE_SIGN_ENTITLEMENTS` declare `aps-environment` — compiles and runs (`xcodegen generate` + `xcodebuild`, BUILD SUCCEEDED) but cannot receive a real push without a Development Team + real APNs Auth Key, neither of which exist in this project yet. Nothing server-side sends anything yet — no credential to send with.

**Tests**: `tests/notifications-toast.spec.js` (new) — inserts a `notifications` row via service role for a signed-in real test user, confirms a toast appears within one poll cycle and disappears on its own. Passes reliably in isolation on all 3 browsers; flaky when run in the same parallel batch as `dispute-flow-e2e.spec.js` (both hit the same live backend from real browsers, competing for CPU/network under this sandbox's default parallelism) — reliable with `--workers=1`, not a product bug (confirmed by isolated reruns).

vite build clean; iOS `xcodebuild` BUILD SUCCEEDED; 270/270 non-real-backend Playwright tests pass; both real-backend suites pass with `--workers=1`.

## 2026-09-15 — real-device install broken by aps-environment; gated behind ENABLE_PUSH

**Root cause (user-confirmed)**: `CODE_SIGN_ENTITLEMENTS`/`BanbeApp.entitlements` from the entry above declared `aps-environment` unconditionally. Push Notifications requires a *paid* Apple Developer Program membership to provision — a free/personal team (this user's) can't sign a real-device build once any entitlements file names that key, regardless of its value ("development" vs "production" doesn't matter, only whether the key exists at all). Simulator installs were unaffected (SweetPad doesn't enforce provisioning), which is why this wasn't caught until a real-device install.

**Fix — gated behind a build config, not deleted**:
- `apps/ios/BanbeApp/BanbeApp.entitlements:1-13` — now an empty `<dict/>`, no `aps-environment` key at all. This is the Debug (default) entitlements file.
- `apps/ios/BanbeApp/BanbeAppPush.entitlements` (new) — has the `aps-environment` key (what the old always-on file used to be). Only referenced by the Release config.
- `apps/ios/Config/Debug.xcconfig` (new): `ENABLE_PUSH = NO`, `CODE_SIGN_ENTITLEMENTS = BanbeApp/BanbeApp.entitlements`.
- `apps/ios/Config/Release.xcconfig` (new): `ENABLE_PUSH = YES`, `CODE_SIGN_ENTITLEMENTS = BanbeApp/BanbeAppPush.entitlements`, `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) ENABLE_PUSH`.
- `apps/ios/project.yml:8-15` — new top-level `configFiles: {Debug: Config/Debug.xcconfig, Release: Config/Release.xcconfig}`; the target's `settings.base` no longer sets `CODE_SIGN_ENTITLEMENTS` (removed, was line 62) so it can differ per config instead of applying to both.
- `apps/ios/BanbeApp/State/AppState+Push.swift:24-27,52-55` — `requestPushAuthorizationIfNeeded()` and `registerPushToken()` both open with `#if !ENABLE_PUSH \n return \n #else` — silently no-op (no permission prompt, no token upload) when the flag isn't compiled in, rather than attempting anything and relying on it merely failing safely.
- `apps/ios/BanbeApp/App/AppDelegate.swift:19-25` — comment only (the callback is simply never invoked in an ENABLE_PUSH=NO build, since nothing ever calls `registerForRemoteNotifications()`; `registerPushToken()`'s own guard above is the actual backstop).

**Verified**: `xcodegen generate` clean. `-showBuildSettings` confirms Debug resolves `CODE_SIGN_ENTITLEMENTS=BanbeApp/BanbeApp.entitlements`, `ENABLE_PUSH=NO`; Release resolves `BanbeAppPush.entitlements`, `ENABLE_PUSH=YES` + the compilation condition. Both configs `xcodebuild ... -destination 'generic/platform=iOS Simulator'` → BUILD SUCCEEDED. A real-device destination build (`generic/platform=iOS`, Debug) now fails ONLY on `"Signing for BanbeApp requires a development team"` — the ordinary, expected message for no Apple ID signed into Xcode in this sandbox — with no mention of Push Notifications/entitlements/provisioning-profile at all, confirming the capability itself is no longer what blocks signing. (This sandbox has no Apple ID session to prove an actual install succeeds — that last step is yours to confirm locally, but the specific error you reported cannot recur with no `aps-environment` key present.)

**To re-enable push later (once you have a paid Apple Developer account) — exactly two edits, then rebuild**:
1. `apps/ios/project.yml` — set `DEVELOPMENT_TEAM` (currently `""`, in `targets.BanbeApp.settings.base`) to your real Team ID.
2. Build the `Release` configuration (or change `schemes.BanbeApp.run.config` from `Debug` to `Release` in `project.yml` if you want Xcode's Run button itself to use it) — `Config/Release.xcconfig` is what actually flips `ENABLE_PUSH=YES` and switches to `BanbeAppPush.entitlements`; nothing else needs editing.
3. Run `xcodegen generate` from `apps/ios/` and rebuild.

No other file needs touching — the Swift permission-request/token-registration code activates automatically once `ENABLE_PUSH` is defined by the config in use.

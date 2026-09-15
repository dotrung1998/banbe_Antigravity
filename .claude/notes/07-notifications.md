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

## 2026-09-16 — message_id on dispute_message notifications; tap-to-highlight; notification delete; admin test-data purge

**Task 1**: `send_dispute_message()` (migration 050, superseding 048) now captures the new `dispute_messages` row's own id (`INSERT ... RETURNING id INTO v_msg_id`) and includes it as `message_id` in the notification's `data` — additive only, same role checks/error returns/recipient logic as before. Verified against production: `send_dispute_message()` returned `message_id`, and the matching `notifications` row's `data.message_id` matched it exactly. No other notification `kind` gets the same treatment — see the comment in migration 050 for why (none of them exist to point at a specific chat message the way `dispute_message` does, even though a few also drop an unrelated system note into the permanent `messages` table as a side effect — wiring a message_id onto those would be dead data with no consuming UI).

**Task 2**: `src/state/GocContext.jsx`'s `openNotification()` — new `dispute_message` branch sets `chatHighlight: {bookingId, messageId}` and routes by `accountType` (organizer → `openVerifications()`, else → `openPaymentDetails()`; admin is never a recipient of this kind, so no branch needed there). `src/screens/DisputeChatPanel.jsx` reads `chatHighlight` itself (not threaded through as a prop by every parent screen) — scrolls to and applies a temporary `alert`-colored outline to the matching message (`ref` map + `scrollIntoView`), or scrolls the list to the bottom if `messageId` is null (a pre-migration-050 row), then calls `clearChatHighlight()` so the 4s poll's re-renders don't re-trigger it. `src/screens/Verifications.jsx` gets a small `useEffect` to auto-open its local chat toggle when `chatHighlight` targets one of its rows (its panel isn't always mounted, unlike PaymentDetails.jsx's). iOS mirrors: `AppState.swift` (`chatHighlight`, `clearChatHighlight`), `AppState+Data.swift`'s `openNotification()`, `DisputeChatPanel.swift` (`ScrollViewReader` + `applyChatHighlight`), `VerificationsView.swift` (`.onChange`/`.onAppear` on `openChatBookingID`).

**Task 3**: 1px border added to the toast card using the existing `rule` token (an `ink`-derived divider token, not a new color) — `src/screens/ToastStack.jsx` and `apps/ios/BanbeApp/Views/ToastOverlay.swift` (`app.palette.rule`).

**Task 4**: `notifications` had SELECT/UPDATE RLS scoped to `recipient_id = auth.uid()` (migration 019) but **no DELETE policy at all** — meaning a user could not delete their own notifications before this pass (RLS defaults to deny). Migration 050 adds `notifications_delete_own` (`FOR DELETE ... USING (auth.uid() = recipient_id)`). A real, permanent delete — not audit-sensitive the way `dispute_messages` is, so no soft-delete/confirm dialog. Client: `deleteNotification()` (`GocContext.jsx`) + a small "×" per row (`src/screens/Notifications.jsx`); iOS `AppState+Data.swift`'s `deleteNotification()` + an "×" button per row (`MessagingViews.swift`'s `NotificationsView`).

**Task 5**: `admin_purge_test_dispute_thread(p_booking uuid)` (migration 050, corrected in 051 and 052 — see below) hard-deletes `dispute_messages` for one specific booking's dispute thread (keeps the `dispute_threads` row itself, so a fresh `send_dispute_message()` works immediately without re-escalating), refusing anything already resolved (`resolved_at IS NOT NULL` → `ALREADY_RESOLVED_REFUSING_TO_PURGE`, never touches a real retained case). **Two real bugs found by actually testing it, not just reading the SQL**, both fixed in migration 052:
1. `REVOKE EXECUTE ... FROM authenticated` alone did NOT block a signed-in admin's own browser session — Postgres grants EXECUTE to PUBLIC by default on function creation, and `authenticated` is implicitly part of PUBLIC, so the narrower revoke had no effect underneath that broader grant. Confirmed by literally calling it via an admin JWT session: it succeeded when it should have been refused outright. Fixed by also revoking from PUBLIC — confirmed the same call now fails with a real "permission denied" error, not just an application-level check.
2. `is_platform_admin()` checks `auth.uid() = ... AND role = 'admin'` — called via the service-role key (the only way this function is reachable at all once #1 is fixed), there is no JWT and so no `auth.uid()`, meaning the admin check always failed and refused every legitimate service-role call too. Fixed: only require `is_platform_admin()` when `auth.uid() IS NOT NULL` (a null auth.uid() only happens via service-role/direct psql, both already gated by the REVOKEs above).

Verified end-to-end against production (throwaway script, cleaned up after): admin's own JWT session → real permission-denied error; service-role purge of an open thread → succeeds, messages gone, thread row kept; fresh `send_dispute_message()` on the same booking → succeeds with a new `message_id`; purge attempt on a resolved thread → refused with `ALREADY_RESOLVED_REFUSING_TO_PURGE`.

All four migrations (050, 051, 052) applied via `supabase db push`. `vite build` clean; iOS `xcodebuild` clean on both Debug and Release configs; 270/270 non-real-backend Playwright tests pass.

## 2026-09-17 — notification coverage audit (Task A); real delete for public.messages (Task B); dispute-thread retention label (Task C)

**Task A — every booking/event lifecycle transition checked against its RPC's `notifications` INSERT**:

| Transition | RPC | Notification already existed? |
|---|---|---|
| slot held (paid) | `hold_seats()` (031:38) | **NO — confirmed gap** |
| slot held (free, instant-confirm) | `hold_seats()` (031:38, same function) | **NO — separate gap found while checking this one**: a free RSVP is confirmed inline in this same function and never calls `verify_payment()`, so it never got the guest-facing `payment_confirmed` notification either — silently unnotified for ANY event, not just paid ones |
| payment marked sent | `submit_payment_proof()` (031:195) | yes — `payment_awaiting_verification` to the organizer (:575-586), missed on first grep (function is 130+ lines) |
| organizer confirmed / QR issued | `verify_payment()` (026:608) | yes — `payment_confirmed` (026:707) |
| auto-confirmed | n/a | **N/A — not implemented at all** (02-confirm-qr.md: `sweep_verification_slas()` only sends Telegram reminders, never auto-confirms) |
| organizer marked "not found" | `reject_payment()` (042:28, current version) | yes — `payment_needs_info` (042:89) |
| dispute resolved — uphold | `resolve_dispute()` → `verify_payment()` | yes, via the same `payment_confirmed` kind as an ordinary confirm (no distinct "your dispute was upheld" wording, but a real notification does fire) |
| dispute resolved — release/"return to pool" | `resolve_dispute()` (047:48) | yes — `dispute_resolved` (047:86) |
| dispute chat message | `send_dispute_message()` | fixed already, migration 050 |

**Fix**: `supabase/migrations/20260917000053_053_hold_seats_guest_notification.sql` — `hold_seats()` now writes, for every booking: a `hold_created` notification to the guest for the paid path (names the hold deadline — the guest-facing mirror of the organizer's existing `booking_requested`), or reuses the existing `payment_confirmed` kind for the free/instant path (so `openNotification()`'s already-wired branch on both platforms works with no client change). Both moved outside the `v_ev.organizer_id IS NOT NULL` guard the thread-message/organizer-notification block already had — a guest's own confirmation has nothing to do with whether the event's organizer_id happens to be resolved. Verified against production (throwaway script): both a paid hold and a free RSVP now produce the correct notification row.

**Task B**: `public.messages` (the ordinary Chat.jsx/threads screen, confirmed distinct from `dispute_messages` and with no retention requirement documented anywhere in 05-notify-retention.md) had SELECT/INSERT RLS (migration `20260906000003_003_social_chat.sql:70-96`) but no UPDATE/DELETE at all. `supabase/migrations/20260917000054_054_messages_delete_own.sql` adds `messages_delete_own` (`auth.uid() = sender_id`) — a system note (`sender_id IS NULL`) can never match, so those are never deletable by a user either way. Client: `deleteMessage()` (`GocContext.jsx`) + a small "×" on own bubbles only (`src/screens/Chat.jsx`); iOS `AppState+Data.swift`'s `deleteMessage()` + an "×" button (`MessagingViews.swift`'s `ChatView.bubble`). Verified directly: a thread participant who isn't the sender gets 0 rows affected; the sender's own delete works.

**Task C**: `purge_after` gets set in `resolve_dispute()` (currently `20260914000047_047_dispute_resolution_stats.sql:100`, `purge_after = v_resolved_at + interval '72 hours'`, unconditional on both outcomes) — checked production directly: **zero** existing resolved `dispute_threads` rows have a null `purge_after` (every version since it was introduced in migration 033 has set it unconditionally), so no backfill was needed. Client: `loadDisputeChat()` now also selects `purge_after` (previously only `id, resolved_at`) and stores it in new `disputeChatThread` state (`GocContext.jsx`) / `AppState.disputeChatThread` (iOS). Label rendered in `DisputeChatPanel.jsx`'s `retentionLabel()` / `DisputeChatPanel.swift`'s `retentionLabel` computed property — static per render, "Sẽ tự xoá trong ~N giờ" (≥1h, rounded) or "~N phút" (<1h, rounded), nothing for an open thread or one whose `purge_after` has already passed. No delete button added anywhere near dispute chat, by design. Verified against a real fresh resolution: label reads "~72h" immediately after resolving, null before resolution.

All migrations (053, 054) applied via `supabase db push`. `vite build` clean; iOS `xcodebuild` clean (Debug + Release); 270/270 non-real-backend Playwright tests pass.

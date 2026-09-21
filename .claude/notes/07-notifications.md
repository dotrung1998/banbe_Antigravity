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

## 2026-09-17 — openNotification() had no per-event ownership check; two new kinds (see 15-organizer-checkin.md)

**Real bug, not just a hypothesis**: `openNotification()`'s `booking_requested`/`payment_awaiting_verification` branches routed to `openAttendance()`/`openVerifications()` using only an ACCOUNT-level gate (`organizerMode || accountType === 'admin' || hasHosted`, or nothing at all for `openAttendance`) — never checking whether the current account is the organizer of the SPECIFIC event the notification names. Any dual-role account (this app's own explicit design; the shared fast-suite test account is exactly this) could land on another organizer's screen for an event it only booked as a guest, RLS silently returning zero rows as the only backstop. Fixed by checking `n.data.event_id` against `myOrgEventKeys` (the real per-event list from `loadMyEvents()`, already existed) before either call — full detail and the guest-facing screen this replaced in `.claude/notes/15-organizer-checkin.md`.

**Two new kinds**: `payment_verification_nudge` (guest → organizer, `nudge_organizer()` RPC, migration 059, rate-limited to 2/hold) and `booking_declined` (organizer → guest, `reject_pending_guest()` RPC, same migration) — neither is deep-linked from `openNotification()` (a bell tap on either just marks it read, same as several other kinds e.g. `referral_joined`), by the same reasoning as every other non-deep-linked kind: nothing on the other end needs a dedicated screen beyond what's already reachable normally.

`vite build` clean; iOS `xcodebuild` clean (Debug + Release); full fast Playwright suite 125/125 clean.

## 2026-09-18 — Instagram/Facebook-style redesign: avatars, sections, collapse, back-target wiring

**New facts found, not assumed**:
- `profiles.avatar_url` is stored as a full external URL already (seed
  data, `010_seed_data.sql:16-19`, uses real `images.unsplash.com` URLs
  directly) — no signing or path-joining needed, unlike every other
  storage-backed field in this codebase.
- `public.event_photos` (`001_core_schema.sql:93-98`: `event_id`,
  `storage_path`, `sort_order`) and the public `event-photos` bucket
  (`005_storage_buckets.sql`) exist in the schema but had **zero
  consumers anywhere in the app** before this pass (confirmed by
  repo-wide grep) — every event image shown today comes from the static
  demo catalogue (`src/data/events.js`'s `LOCAL_PHOTOS`), not this table.
  This means a real event's own uploaded cover photo will show correctly
  for a real DB event, but every demo-catalogue event (nearly everything
  currently visible in the app) has no `event_photos` rows and falls
  through to the fallback glyph — expected, not a bug.
- **A real, pre-existing bug found and fixed as a side effect of wiring
  `confirmedBack`**: `openBookingConfirmed` (web, `GocContext.jsx`) was
  never included in `GocProvider`'s exported `value` object at all —
  `PaymentDetails.jsx` destructures and calls it (`:25`, `:100`, `:319`)
  regardless, meaning every call was silently `undefined()`, throwing a
  runtime `TypeError`. Fixed by adding it (and the new `backFromConfirmed`)
  to both the value object and its `useMemo` deps array
  (`GocContext.jsx:3311`/`:3340`).
- A new file under `apps/ios/BanbeApp/` requires `xcodegen generate`
  before `xcodebuild` will see it at all (`project.yml`'s `sources`
  globs `BanbeApp/` at generation time, not build time) — the committed
  `.xcodeproj` doesn't auto-discover new files. Ran once this pass for
  the two new Swift files below.

**1. Avatar helper** — `src/lib/notifications.js` (`avatarSourceFor`) /
`apps/ios/BanbeApp/Lib/NotificationPresentation.swift` (`avatarSource(for:maps:accountType:)`):
one small per-kind classifier each, not inline branching in the row
renderer. `booking_requested`/`payment_awaiting_verification`/
`receipt_requested`/`payment_verification_nudge`/`guest_renamed` (+
`dispute_message` only when the viewer is the organizer) prefer the
guest's `profiles.avatar_url` (joined via `data.booking_id` →
`bookings.user_id`); everything else with a resolvable `event_id`
(direct, or via the booking) prefers the event's `event_photos` cover
(`sort_order` ascending, first row); no resolution → a plain fallback
circle with the app's own 🔔 glyph, never a broken image.

Batch-fetch (avoids a join per row): `loadNotifications()` —
`GocContext.jsx:2095-2149`, `AppState+Data.swift:497-554` (new
`loadNotificationAvatarMaps`, private row structs at `:103-129`) — after
fetching notifications, collects `booking_id`s → one `bookings` query →
collects `event_id`s (direct + via booking) → one `event_photos` query
(`getPublicUrl`/`getPublicURL`, a local URL-builder, not a network call)
→ collects guest `user_id`s → one `profiles` query for `avatar_url`.
Stored in new state: `notificationBookingById`/`notificationEventPhotoByEventId`/
`notificationAvatarByUserId` (web, `GocContext.jsx:225-231`) /
`notificationAvatarMaps: NotificationAvatarMaps` (iOS, `AppState.swift:263-266`).
**Known, accepted limitation**: the 5s toast-poll's own `notifications`
refresh (`startNotificationPolling()`) does not re-run this batch-fetch —
only opening the Notifications screen (`loadNotifications()`) does. A
brand-new notification about a never-before-seen event/booking briefly
shows the fallback glyph in a toast until the bell screen is actually
opened. Not fixed — toasts are ephemeral and already disappear before
this would be visually confusing in practice; re-running the joins on
every 5s poll tick for a value nobody's looking at yet wasn't worth it.

**2. Title/preview** — `src/screens/Notifications.jsx`'s `Row`
(`fontWeight: 700` unconditionally, `body` now single-line
`whiteSpace:'nowrap'/textOverflow:'ellipsis'` instead of the old
multi-line wrap) / `MessagingViews.swift`'s `NotificationsView.row(_:)`
(`.fontWeight(.bold)` unconditionally, `item.body` now `.lineLimit(1)`).

**3. Time-based sections** — "Mới"/"New" (all unread, regardless of age)
always first, then "Hôm nay"/"Today", "7 ngày qua"/"Last 7 days", "Cũ
hơn"/"Older" bucket the REMAINING (read) notifications by `created_at`.
New `notificationAgeBucket(createdAt, now)` (`src/lib/notifications.js`) /
`notificationAgeBucket(_:now:)` (`NotificationPresentation.swift`) —
extends `agoLabel()`/`EventLabels.ago()`'s "hours ago" display concept
with the coarser buckets a long list needs; empty sections are hidden
entirely (a single-notification account never shows 3 empty headers).

**4. Collapse at N=20** — `src/screens/Notifications.jsx` (local
`expandedSections` Set state, applied per-section — not just "Cũ hơn" —
since any section can in principle exceed 20) / `MessagingViews.swift`
(`@State private var expandedSections: Set<String>`). A "Xem thêm
(N)"/"View more (N)" row appears only when a section actually has more
than 20 items; tapping it reveals the rest in place. Pure render-time
slice of already-loaded data — `loadNotifications()`'s existing 50-row
cap was untouched, no new query.

**5. Back-target wiring** — extended the same `documentBack`/
`paymentDetailsBackTarget` field-per-screen pattern to three destinations
that didn't have one before: `attendanceBack`/`verificationsBack`/
`confirmedBack` (web: `GocContext.jsx:152-159`; iOS:
`AppState.swift:375-383`), each defaulting to that screen's own previous
fixed target (`.dashboard`/`.profile`/`.home`) so every existing
non-notification entry point (`Dashboard.jsx`'s "Điểm danh", Attendance's
"Check payment", `PaymentDetails.jsx`'s auto-redirect-on-confirm) is
unchanged. `openAttendance`/`openVerifications`/`openVerificationDetail`/
`openBookingConfirmed` (both platforms) all gained an optional `back`
param that sets the field; `openNotification()` passes `'notifications'`/
`.notifications` at every one of its 8 routing branches (web:
`GocContext.jsx:3104-3151`; iOS: `AppState+Data.swift:610-699`),
including `openThread`'s existing `back` param (was hardcoded
`'inbox'`/`.inbox`) and `dispute_message`'s two-way branch. Each
destination's own back link/button (`Attendance.jsx`/`AttendanceView.swift`,
`Verifications.jsx`/`VerificationsView.swift`, `Confirmed.jsx`/
`ConfirmedView.swift`) now reads its field instead of a hardcoded target,
**and its own label text follows suit** (e.g. "‹ Your dashboard" doesn't
show when the tap actually goes to Notifications).

**The second exit path, checked and fixed too**: per
`15-organizer-checkin.md`'s own prior lesson (a swipe-back gesture is a
SECOND navigation path on iOS, independent of any screen's own back
button, and got missed once before for `paymentDetailsBackTarget`) —
`AppState.goBack()`/`backTargetScreen` (`AppState.swift:1094-1149`) were
updated in the same pass: `.attendance`/`.verifications`/`.confirmed`
cases now read the new fields instead of `goDashboard()`/`.dashboard`/
`.home` literals. `chatBackAction()`/`chatBackFn` (both platforms) also
gained a `.notifications`/`'notifications'` case — previously any
non-`'inbox'` value collapsed to `'organizer'`, which would have silently
misrouted a `new_message` notification's back button. Web has no
equivalent second exit path (confirmed in the prior session's own audit —
no `popstate`/history-stack wiring anywhere), so only the in-view back
links needed changing there.

**Verified by build only, not live screenshots** (per this ticket's own
instruction — reasoned through the logic instead): `vite build` clean;
iOS `xcodebuild` (Debug, `-destination 'generic/platform=iOS Simulator'`)
BUILD SUCCEEDED after `xcodegen generate` picked up the two new Swift
files (`Lib/NotificationPresentation.swift`, and `Views/MessagingViews.swift`'s
rewritten `NotificationsView`).

## 2026-09-18 follow-up — real-device regressions from the redesign above: avatars, duplicate "New", reorder-on-read, and a new "•••" menu

Live testing surfaced four problems in 937074d. All four investigated end
to end against real data (not fabricated accounts) using the service-role
key already in `.env.local` plus `tests/e2e/setup.mjs`'s fixtures for the
cases that needed a controlled repro.

### BUG 1 — avatar always fell back to the bell: root cause is a real data gap, not a code bug, plus one genuine bug found and fixed along the way

**Confirmed live, not assumed**: built an isolated repro (fresh organizer +
guest + event + booking) and ran the *exact* batch queries
`loadNotifications()`/`loadNotificationAvatarMaps()` run, under the real
guest's and real organizer's own authenticated sessions (not service
role) — RLS, key matching (`booking_id`/`event_id`/`user_id` are all text/uuid
strings on both sides, no type mismatch), and the join logic in
`avatarSourceFor()`/`avatarSource(for:maps:accountType:)` all resolved
correctly on the first try. **No timing/race, no RLS block, no key
mismatch** — the mechanism itself was never broken.

**The real cause, confirmed against the actual signed-in dev account's own
notifications** (`recipient_id 63cdbe55-6ea1-476a-8bf7-0633be842fd3`,
queried live): every one of its real notifications references a real
catalogue event (`phong302`, `vuonsau`, `noigiay`, `aeie`) and a real guest
booking. Checked both source tables directly:
- `event_photos` has rows **only** for the 4 seed demo events
  (`evt_001`-`evt_004`, migration `010_seed_data.sql`) — confirmed by
  repo-wide grep, **there is no upload path anywhere in this app** that
  ever writes to it. `tapPhotoSlot()` (`GocContext.jsx:2874`, "Create
  Event"'s photo picker) only increments a cosmetic slot COUNT — it never
  picks, uploads, or persists an actual file, and `create_event_draft`
  takes no photo parameter at all.
- `profiles.avatar_url` is non-null **only** for the same 4 seed profiles
  (`010_seed_data.sql:16-19`) — confirmed live: the actual guest behind the
  dev account's real `booking_requested` notifications has
  `avatar_url: null`. There is no avatar-upload feature anywhere in this
  app either.

So for any real account's real activity, both source tables the avatar
logic depends on are — and always were — empty. The bell fallback was
correct, just useless, because the two DB tables this feature was built
against have no real writer.

**Fix — a THIRD, actually-populated fallback**: every real event a real
account interacts with is a catalogue event (`findEvent()`/`EVENTS`,
`src/data/events.js`; `EventCatalog`, `apps/ios/BanbeApp/Models/CatalogEvent.swift`)
— the same photo already shown on Home/EventDetail/Dashboard everywhere
else in the app. `avatarSourceFor()` (`src/lib/notifications.js:38-49`) and
`avatarSource(for:maps:accountType:)` (`NotificationPresentation.swift:50-59`)
now fall back to the catalogue photo when `event_photos` has nothing.
**Caught and avoided a second bug while adding this**: `findEvent()`/
`EventCatalog.find()` themselves fall back to `EVENTS[0]`/`.all.first` for
an unrecognized key (deliberate elsewhere, "a screen always has something
to render") — blindly reusing that here would show a random WRONG event's
photo for a genuinely non-catalogue `event_id`, worse than the honest bell
glyph. Matched directly against `EVENTS`/`EventCatalog.all` instead, which
correctly returns nothing for a real miss (confirmed live:
`EVENTS.find(e => e.key === 'doesnotexist')` → `undefined`, correctly
falls through to the bell). iOS renders the catalogue photo via
`CatalogPhoto` (its own WebP/downsampling/disk-cache loader, not a raw
`AsyncImage` URL) — new `NotificationAvatarSource.catalogPhoto(String)`
case, `MessagingViews.swift`'s `avatar(for:)`.

**A second, real, independently-confirmed bug**: `event_photos.storage_path`
seed rows are stored WITH the bucket name baked in
(`'event-photos/evt_001/cover.jpg'`) — unlike every other
`storage_path`/`proof_path`/`file_path` column in this schema
(`pay-proof`, `payment-documents`), which are bucket-RELATIVE. Passed
as-is to `getPublicUrl()`/`getPublicURL()`, this doubles the bucket
segment (confirmed live: produced
`.../object/public/event-photos/event-photos/evt_.../cover.jpg`, a 404).
Fixed by stripping a redundant leading `event-photos/` before calling
`getPublicUrl` (`GocContext.jsx:2144-2148`) / `getPublicURL`
(`AppState+Data.swift:565-576`) — defensive enough to handle either
convention. This only affects the 4 seed rows today, but is a real,
verified bug independent of the catalogue-fallback fix above.

**Verified against real production data, both parts**: `findEvent('phong302').img`
→ `/photos/DSCF5542.jpg` (a real file), same for `vuonsau`/`noigiay`/`aeie`
— i.e. avatars now resolve for literally the real notifications the dev
account already has. The double-prefix fix was verified via the isolated
repro's own signed URL (previously doubled, now correct after the strip).

### BUG 2 — "New" rendered twice: could not reproduce the literal mechanism, but the redesign structurally guaranteed against the ticket's own hypothesis and against BUG 3's actual cause

Re-read `sections`/`NotificationSection` in both `Notifications.jsx` and
`MessagingViews.swift` as they stood at 937074d line by line: `unread` was
already computed as ONE filter over the full list (not a sequential
scan-and-transition that inserts a divider every time it crosses from read
to unread while walking a chronologically-sorted list) — the specific
mechanism the ticket's own hint described ("two non-contiguous unread
items each start their own section") does not match this codebase's
actual algorithm, and a single `{key:'new', items: unread}` object cannot
literally produce two DOM headers within one render.

The most likely real explanation, given what BUG 3 (below) turned out to
be: section membership was recomputed from **live** `read_at` on every
render, and the exact same `notifications` array is overwritten wholesale
every 5s by the app-wide toast poll while a screen may be mid-transition
from marking something read — a plausible source of a transient
double-render a screenshot could catch, though not reproduced directly.

**Fix, which also structurally rules this class of bug out**: section
membership is now decided ONCE per notification (frozen in
`sectionMembership`/`sectionMembership` state, keyed by id — see BUG 3
below, same mechanism), so building `sections` is a single grouping pass
over a **stable** per-item key, never a live re-filter that could disagree
with itself mid-render. Verified against the real dev account's own 25
real notifications (7 unread interleaved with 18 read ones, not
contiguous): grouping by the frozen key produces exactly 3 non-empty
sections, `new` appearing exactly once with all 7 unread items together,
regardless of interleaving — script output: `{new: 7, today: 0, week: 16,
older: 2}`, one bucket per key by construction.

### BUG 3 — reading a notification moved it: real bug, root cause confirmed, fixed on both platforms

**Confirmed real**: section membership was derived from **live** `read_at`
on every render (`unread = notifications.filter(n => !n.read_at)`, buckets
built the same way) — the instant `markNotificationRead()` flipped
`read_at`, the very next render recomputed which bucket the item belonged
to and it visibly jumped from "Mới" into "Hôm nay"/"Cũ hơn". Made worse by
the app-wide 5s toast poll, which overwrites the same `notifications`
array wholesale independent of this screen even being interacted with.

**Fix**: `src/screens/Notifications.jsx:30-57` (`sectionMembership` state
+ `classifyAtLoad()`) / `MessagingViews.swift:215-243`
(`sectionMembership`/`syncSectionMembership()`/`classifyAtLoad(_:now:)`) —
a notification's section is assigned exactly once, the first time this
screen observes it (on mount, and for any new id the toast poll delivers
later while the screen is open), and never reassigned afterward regardless
of subsequent `read_at` changes. The row's bold/dim weight still reads
**live** `read_at` (`Row`'s `unread` prop is now `!n.read_at`, not the
section's fixed flag; `MessagingViews.swift`'s `row(_:unread:)` call site
now passes `item.readAt == nil`) — so reading a notification unbolds it in
place immediately, exactly as asked, without moving it. Verified by
inspection against the same real 25-notification dataset above (the logic
change is pure and was exercised by the same script).

### BUG 4 — "×" delete replaced with a "•••" action menu (Xoá / Đánh dấu đã đọc·chưa đọc / Tắt loại thông báo này)

Implemented exactly the three actions this app can back for real, per this
ticket's own bar — explicitly did NOT add "Show more"/"Show less" (this
app has no ranking/personalization system for notifications to expose) or
"Report issue" (grepped for any existing generic issue-report mechanism
anywhere else in the app — none exists to call into).

- **"Xoá thông báo này"** — unchanged `deleteNotification(id)`, now
  reached via the menu instead of a direct "×" tap.
- **"Đánh dấu đã đọc"/"Đánh dấu chưa đọc"** (toggles, label follows current
  state) — mark-unread did not exist before this pass. New
  `markNotificationUnread(id)` (`GocContext.jsx`, right after
  `markNotificationRead`) / `markNotificationUnread(_:)`
  (`AppState+Data.swift`, right after `markNotificationRead`) — the exact
  reverse write (`read_at: null`). No new schema — `notifications`' existing
  UPDATE RLS (recipient-scoped, migration 019) already allows it. **Real
  Swift gotcha hit and fixed**: a synthesized `Encodable` for a struct with
  an `Optional<String>` field SKIPS the key entirely when nil
  (`encodeIfPresent` semantics) rather than sending `null` — silently
  never clearing `read_at` at all. Fixed with an explicit
  `NotificationUnreadUpdate: Encodable` that calls
  `container.encodeNil(forKey:)` (`AppState+Data.swift`, right after
  `NotificationReadUpdate`).
- **"Tắt loại thông báo này"** (mute) — built as instructed, cheaply: new
  migration `20260921000062_062_notification_mute_kinds.sql` adds
  `profiles.muted_notification_kinds text[] DEFAULT '{}'`. No new RLS
  needed — `profiles_update_own` (001) is already a blanket own-row policy
  covering any column, the same reasoning `auto_email_documents` (056)
  already established. Filtering happens **entirely client-side** — inside
  `loadNotifications()` (`GocContext.jsx:2126-2129`,
  `AppState+Data.swift:551-552`) and the 5s toast poll
  (`GocContext.jsx:790-793`, `AppState+Data.swift:664-669`) — not a single
  one of the ~15 RPCs that INSERT a `notifications` row needed touching.
  New `muteNotificationKind(kind)` (both platforms) writes the array back
  and immediately drops any already-loaded notifications of that kind from
  local state.
- **Migration applied to production**: `npx supabase db push` (this
  sandbox does have working, already-linked `supabase` CLI access via
  `npx --yes supabase`, despite a global `supabase` binary not being
  installed — worth remembering for next time rather than assuming no CLI
  access exists) — confirmed via `migration list` (062 went from
  `"remote":""` to applied) and a live `profiles` read
  (`muted_notification_kinds: []` present on real rows). This was done
  *before* shipping the client code that unconditionally selects this
  column in the sign-in-path profile fetch (`syncUser()`/`applySession()`)
  — selecting a genuinely nonexistent column would have failed that entire
  query (PostgREST 400s the whole request, not just the missing field),
  breaking sign-in for every account until deployed.

**Verified end to end against real accounts, not fabricated flows**: a
real anon-key session (not service role) successfully wrote `read_at` to a
timestamp, then back to `null` (both confirmed by an independent read
after each write); the same real session wrote
`muted_notification_kinds: ['referral_joined']` to its own profile and the
client-side filter simulation correctly dropped that account's one
existing notification of that kind from the list (1 → 0).

UI: web's menu (`Notifications.jsx`'s `NotificationActionSheet`) reuses
the exact bottom-sheet visual convention `ReasonSheet.jsx` already
established (dim overlay + a paper panel sliding up), not a new
dropdown/floating-menu pattern; iOS's (`MessagingViews.swift`) reuses the
existing generic `BottomSheet<Content>` component (`Sheets.swift`) the
same way `ReasonSheetView` does. Row's trailing control changed from a
delete "×"/`xmark` glyph to "•••" (`notification-menu`/`notification.menu`
test/accessibility identifiers, replacing `notification-delete`).

Both `vite build` and `xcodebuild` succeed.

## 2026-09-19 follow-up — stale-target detection/auto-delete, per-calendar-day grouping

**Confirmed real trigger, not fabricated**: this session's own bulk
`payment_documents` cleanup (direct SQL, clearing test data) deleted all
but 2 of that table's rows. Queried production directly: every
`payment_document_uploaded`/`_replaced`/`receipt_requested` notification
older than the 2 survivors now points at a `document_id` with no matching
row — e.g. notification `277ef2fc-dc9d-4fbb-acad-8a61c4c06193`
(`document_id: 5bd5a2d3-22d3-4d0b-84cd-928c31aadb32`, recipient
`8a4eb34e-...`) — confirmed the id genuinely doesn't exist in
`payment_documents`.

### BUG — tapping a notification whose target was deleted did nothing

**Root cause, confirmed by reading the actual code**: `openDocumentFromNotification()`
(web `GocContext.jsx`, iOS `AppState+Data.swift`) and `openBookingConfirmed()`
(same files) both fetched their target and, on zero rows, did a bare
`return`/`return` with no signal to the caller — `openNotification()` had
no way to know the fetch failed, so it just... stopped, silently. **New
fact**: iOS's versions used `.single()`, not `.maybeSingle()` — `.single()`
throws the SAME `PGRST116` error for "zero rows" as for a genuine decode/
network failure, so on iOS the two cases weren't even distinguishable
before this pass; switched to `.maybeSingle()` (decodes into `T?`, `nil`
on zero rows without throwing, still throws for a real error/multi-row
match) specifically so this fix can tell "confirmed gone" apart from "the
fetch itself broke."

**Fix — generalized, not documents-only, per this ticket's own ask**:
1. **On tap** (`openNotification()`, both platforms): the two kinds with an
   existing single-entity fetch (`payment_document_uploaded`/`_replaced` via
   `openDocumentFromNotification()`; `payment_confirmed` via
   `openBookingConfirmed()`) now check the result. A confirmed not-found
   calls the new `reportStaleNotification()` (web: `GocContext.jsx`, right
   after `deleteNotification`; iOS: `AppState+Data.swift`, right after
   `deleteNotification`) — deletes the dead notification and pushes a toast
   ("Nội dung này không còn tồn tại"/"This content no longer exists") with
   `notification: nil`-equivalent (web: literally `{title, body}`, no
   `id`/`kind`; iOS: a synthetic `AppNotification` with an unmatched `kind`
   and `readAt` pre-set) so tapping the TOAST itself can't re-attempt the
   same dead lookup or fire a pointless mark-read call.
2. **On list load** (`loadNotifications()`, both platforms): the exact same
   two-kind check now also runs proactively, reusing data the avatar batch
   already fetches for free (`bookingById` for `payment_confirmed`) plus
   ONE small new query (`payment_documents` ids only, for the document
   kinds — **new fact**: contrary to this ticket's own premise, the avatar
   batch added in 8256685 never actually fetched `payment_documents` at
   all, only `bookings`/`event_photos`/`profiles` — this pass is what adds
   it). Stale rows are pruned from `notifications`/`liveRows` before
   `set()`/before assigning `notifications`, and best-effort deleted
   server-side (fire-and-forget, doesn't block the render). No toast on
   this path — proactively vanishing from a list you're actively scrolling
   needs no extra "click here" feedback the way an unresponsive tap does.
3. **RLS-safety reasoning, why these two kinds are trustworthy to
   auto-delete on**: both `payment_documents` and `bookings` scope their
   guest-facing SELECT policy to `auth.uid() = user_id`, and the
   notification's recipient IS that same `user_id` by construction (the
   RPC that inserts the notification is the same one that set `user_id` on
   the target row) — ownership never changes afterward, so RLS can never
   spuriously deny an existing row to its own notification's recipient. An
   empty result is unambiguous.

**Kinds deliberately SKIPPED for auto-delete, and why** (per this ticket's
own instruction to log and skip rather than risk a false positive):
- `booking_requested`, `payment_awaiting_verification`, `receipt_requested`
  — these route to a LIST screen (`openAttendance()`/`openVerifications()`),
  not a single-entity fetch. If the specific booking is gone, the list
  simply doesn't show it — a much softer, already-correct degradation than
  "tap does nothing," and there's no single id to check existence against
  without inventing one.
- `hold_created`, `dispute_message`'s guest branch — both call
  `openPaymentDetails(bookingId, ...)`, which does **no fetch of its own**
  at all (pure navigation; the destination screen reads from
  `paymentBookings`, already loaded at sign-in). Adding an existence check
  here means a brand-new round trip with no reuse of anything already
  fetched. Skipped because: (a) no confirmed real trigger exists for a
  `bookings` row going missing — repo-wide grep of every migration found
  **zero** application RPCs that hard-delete a `bookings` row (only the
  one-time `010_seed_data.sql` reset does), unlike `payment_documents`,
  which has both a real purge cron (057) AND this session's own confirmed
  manual cleanup; (b) `dispute_message`'s organizer branch and `new_message`
  both route to list/thread screens, same reasoning as above.
- `new_message` — `openThread()`; no delete path exists anywhere in this
  codebase for a `threads` row itself (only individual `messages`/
  `dispute_messages` rows are ever deletable), so the destination can never
  actually go missing.

**Verified against the real confirmed repro, not a fabricated one**: ran
the exact `.maybeSingle()`-equivalent check against real notification
`277ef2fc-dc9d-4fbb-acad-8a61c4c06193` (`payment_document_uploaded`,
`document_id: 5bd5a2d3-...`) — confirmed `payment_documents` genuinely has
no matching row (`error: null, data: null`), applied the fix's own delete,
and confirmed the notification is now gone (`exists after: false`). This
is the exact code path `openNotification()` runs on a real tap — the only
difference from a live tap is this was driven by a script instead of a
finger, since this session has no way to sign in as the real account's
actual password.

### FEATURE — per-calendar-day headers within "7 ngày qua"/"Cũ hơn"

New `notificationDayLabel()`/`groupNotificationsByDay()`/`collapseDayGroups()`
(`src/lib/notifications.js`) and their Swift mirrors
(`NotificationPresentation.swift`) — "Mới"/"Hôm nay" stay exactly as
8256685 stabilized them (flat, frozen `sectionMembership`, unchanged); only
"7 ngày qua"/"Cũ hơn" now render one header per calendar day
("Thứ Năm, 18 Thg 9"/"Thursday, Sep 18", local calendar day via
`Calendar.current`, not UTC) instead of one flat block for the whole range.
`Notifications.jsx`'s row-rendering loop / `MessagingViews.swift`'s
`section(_:)` both branch on a new `dayGrouped` flag per section.

**Collapse, "whole days at a time, not mid-day"**: `collapseDayGroups(dayGroups, limit)`
accumulates full days until the NEXT day would push the running total past
the existing `COLLAPSE_AT`/`notificationCollapseAt` (still 20, unchanged) —
cuts there, keeping every included day intact. A single day with more than
20 items on its own is still shown in full rather than split (the
alternative — truncating mid-day — is exactly what this ticket asked to
avoid). The existing per-section `expandedSections` "Xem thêm" toggle is
reused unchanged; expanding a day-grouped section just shows every day in
full instead of applying the day-level cut.

Both `vite build` and `xcodebuild` succeed.

## 2026-09-19 follow-up — toast "Xem thêm"/"Tắt tất cả" + individual X; Inbox unread badge built from scratch; demo event dates de-frozen

**New fact confirmed**: `messages.read_at` already existed per-message (nullable timestamp, `003_social_chat.sql`) but had **zero** unread-count logic anywhere in the codebase before this pass (confirmed by grep) — `BottomTabBar.jsx`'s own prior comment said as much explicitly. Built from scratch, see Task 3 below.

**Task 1 — toast controls** (`src/screens/ToastStack.jsx`, `apps/ios/BanbeApp/Views/ToastOverlay.swift`):
- **1a (individual dismiss)**: `dismissToast`/`dismissToast(_:)` already worked correctly (local-only, never touches `notifications`/`read_at`) — kept as-is. Added an explicit small "✕"/`xmark` control per toast card (`data-testid="toast-dismiss"` / `accessibilityIdentifier("toast.dismiss")`) calling the same function, since the reference screenshot's per-banner X wasn't actually present as a visible affordance before (the whole card doubled as both "open" and "dismiss," which is a worse UX than a dedicated X once "see more"/"dismiss all" exist alongside it).
- **1b ("Xem thêm")**: only the first 3 toasts (`VISIBLE_COUNT`/`visibleCount`) render by default; a "Xem thêm (N)" pill appears below the stack when more are queued and reveals the rest in place (`expanded` local state, no new fetch — same local `state.toasts`/`app.toasts` array).
- **1c ("Tắt tất cả")**: new `dismissAllToasts()` (`GocContext.jsx`, right after `dismissToast`) / `dismissAllToasts()` (`AppState.swift`, right after `dismissToast(_:)`) — clears the whole local toast queue in one call, added to the value object + `useMemo` deps on web.
- **CRITICAL CONSTRAINT verified**: all three dismiss paths (individual, see-more's own reveal — which dismisses nothing itself — and dismiss-all) only ever mutate the local `toasts`/`app.toasts` array. Neither `dismissToast` nor the new `dismissAllToasts` calls `markNotificationRead()` or writes to `notifications` at all — read by inspection of both implementations, and structurally impossible for `dismissAllToasts` to affect the bell inbox since it takes no notification id/row as input, only clears local state.

**Task 3 — Inbox unread badge** (`src/screens/BottomTabBar.jsx`, `apps/ios/BanbeApp/Views/BottomTabBar.swift`): new `s.unreadMessages`/`app.unreadMessages`, computed by a new poll effect (`GocContext.jsx`, right after `loadInboxThreads`) / folded into `startNotificationPolling()`'s existing 5s loop via new `refreshUnreadMessageCount()` (`AppState+Data.swift`, right after `stopNotificationPolling()`) — reuses `loadInboxThreads()`'s own exact thread-scoping (`threads.guest_id = me`, OR `threads.organizer_id` in organizers owned by me via `owner_id`/`user_id`), then counts (not fetches full rows) `messages` where `read_at IS NULL AND sender_id != me` across those thread ids. Capped at "9+" above 9, matching the existing Notifications badge convention exactly (`item.badge > 9 ? '9+' : item.badge`). No new poll timer on web (reuses the same 5s cadence as the notifications poll, in a sibling effect); iOS reuses `startNotificationPolling()`'s literal loop rather than a second `Task`.

**Task 2 — demo event dates de-frozen** (`supabase/migrations/20260921000063_063_demo_events_realtime_dates.sql`, new): root cause confirmed — the `020` seed only ever wrote `event_date`/`event_time`, never `starts_at`, and `starts_at` is this schema's real anchor column (`057`'s own comment) that both `goc_mark_past_events` (`008_pg_cron_jobs.sql`, the only place `status` ever auto-flips to `'ended'`) and most of the app's own date-reading code (`countdown.js`, `MapExplore.jsx`, `paymentDocument.js`) actually key off — `event_date`/`event_time` is explicitly documented as the fallback for a row that never got a real `starts_at`. Since these 21 rows never had one, the daily sweep never touched them regardless of how stale their date got.

New migration reassigns each of the 21 demo event ids (same fixed id list as `020`) a fresh `starts_at` (`event_date`/`event_time` updated to match) with a realistic spread — 35% clearly past (1-45 days ago), 30% very soon/this week (0-6 days out), 35% further out (1-9 weeks out) — and sets `status` from it (`'ended'` if past, `'live'` if not), leaving any `'cancelled'`/`'draft'` row (e.g. `bandai`) untouched per its own intentional status. Idempotent/safe to re-run (fixed id list, no seed/insert side effects) but does re-randomize on every apply, which is fine — nothing downstream is keyed to a specific prior random date.

**Applied to production** in the follow-up below (2026-09-21), once authorized — confirmed via `migration list` (`20260921000063` now shows matching local/remote).

`vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED.

## 2026-09-21 follow-up — real message read-tracking, thread-count Inbox badge, unread divider, Inbox/Chat redesign

**Root cause confirmed** (matches the user's own report of a badge stuck at "9+"): grep for any code path writing `messages.read_at` returned zero hits before this pass — the badge added in the prior entry above counted rows that could never leave the unread state, so it only ever grew.

**Task 1a — real read-tracking**: new `markThreadMessagesRead(threadId)` (`GocContext.jsx`, right before `loadChatMessages`) / `markThreadMessagesRead(_:)` (`AppState+Data.swift`, right after `loadChatMessages`) — updates `read_at` to now on rows in that thread where `read_at IS NULL AND sender_id != me`. **Required a new migration**: `messages` had SELECT/INSERT RLS (003) and a sender-scoped DELETE policy (054) but **no UPDATE policy at all** (same class of gap as 054 found for DELETE) — an update would have silently affected zero rows under RLS's default-deny. New migration `20260921000064_064_messages_update_read_by_participant.sql` adds `messages_update_participant`, scoped to the same thread-participant check `messages_select_thread_participant` already uses. Applied via `supabase db push`, confirmed via `migration list`.

**Task 1b/c — thread-count badge, no cap**: the Inbox badge's poll now fetches `{thread_id}` rows (not a head/count query) and counts distinct thread ids — a 5-message thread counts once. `BottomTabBar.jsx`/`BottomTabBar.swift`'s badge render gained a per-item `badgeCapped` flag (true only for Notifications) so the Inbox badge shows the real number uncapped, while the bell's own "9+" convention is untouched.

**Task 2 — unread divider**: `loadChatMessages` gained a `computeDivider` flag (only true on `openThread`/`openChatFor`'s initial load, never the 4s poll) — captures the id of the first unread message at that exact moment, then immediately marks it/those rows read. The Chat screen inserts a "— Chưa đọc —" row above the matching message. Since the poll never recomputes it and the rows are marked read at open time, a second visit has nothing left to mark the boundary at, so it doesn't reappear.

**Task 3a — merged Inbox avatar**: `loadInboxThreads()` now also fetches each thread's organizer owner/user profile and batches one more profiles query for avatar_url, storing the OTHER participant's avatar per row (host's when I'm the guest, guest's when I'm the organizer — organizers itself has no avatar column). Rendered as a small badge circle overlapping the event photo's corner, falling back to an initial-letter circle rather than a broken image.

**Task 3b — Chat header**: new per-open "other participant name" state, set from the already-correct Inbox row name or from the event's organizer name for a guest-initiated chat; falls back to the old hostShort-only behavior for the one caller that doesn't know it (a new_message notification tap). Header now shows that name as the title, the event's date + name as a subtitle, and a "Chi tiết"/"Details" link to Event Detail.

**Task 3c — per-message sender/timestamp**: each bubble now renders a small "{sender} · {HH:mm}" line above it.

**Task 3d — payment-status system-message cards**: `messages.kind` only has 'text'/'system' with no per-lifecycle-event kind, so per this ticket's own instruction this classifies by the exact body prefix each RPC already writes today (confirm_payment, reject_pending_guest, cancel_booking) in the UI layer only, no schema change — rendered as a bordered card with a status label and a "Xem chi tiết" link instead of a plain bubble.

`vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. Migration 064 applied to production, confirmed via `migration list`.

## 2026-09-21 second follow-up — Inbox search/settings/archive/feedback, star/archive swipe, unread row styling, chat attachments, dock labels

**New schema, one migration** (`supabase/migrations/20260921000065_065_inbox_star_archive_feedback_attachments.sql`, applied via `supabase db push`, confirmed via `migration list`):
- `thread_preferences (thread_id, user_id, starred, archived)`, PK on both columns, RLS `USING/WITH CHECK (auth.uid() = user_id)` for `FOR ALL`. Deliberately NOT stored on `threads` itself — a guest and the organizer on the same thread need independent star/archive state (one side archiving shouldn't hide it from the other). **RLS correctness, by construction, not a live A/B test**: the policy's only condition is `auth.uid() = user_id`, and the primary key forces one row per (thread, user) pair, so two participants on the same thread structurally cannot read or write each other's row — no session exists that satisfies both `auth.uid() = A` and `auth.uid() = B`.
- `app_feedback (id, user_id, body, is_bug_report, created_at)` — confirmed via grep before adding that no generic feedback table existed. INSERT/SELECT RLS scoped to `auth.uid() = user_id`; no UPDATE/DELETE (feedback is write-once).
- `messages.attachment_path`/`attachment_type` (nullable) + new private `chat-attachments` bucket (20MB cap, same image/PDF allowlist as `pay-proof`), RLS scoped by the same thread-participant check `messages_select_thread_participant`/`messages_update_participant` already use, via `split_part(name,'/',1)::uuid = threads.id` (object path convention: `<thread_id>/<file>`).

**Task 1 — Inbox header, search, settings, archive, feedback** (`src/screens/Inbox.jsx`; `apps/ios/BanbeApp/Views/MessagingViews.swift`'s `InboxView`/`FeedbackFlowView`): "Xong"/"Done" moved to a small top-right link; replaced in its old top-right slot with search (client-side substring filter over name/snippet — no existing text-search backend to call into, only `MapExplore`'s different "Search here" location re-query) and settings (gear) icons. Settings opens a bottom sheet with "Đã lưu trữ"/"Archived" (switches `s.inboxView`/`app.inboxView` to show only `thread_preferences.archived = true` threads, with its own back-to-Messages link) and "Gửi phản hồi"/"Give feedback" (two-step flow — single-choice screen with one pre-selected option, then a text box + "I'm reporting a bug" toggle; Send disabled until text is non-empty — writes to `app_feedback` via new `submitFeedback()`).

**Task 2 — swipe-left Star/Archive**: web (`Inbox.jsx`'s new `InboxRow`) hand-rolls a per-row pointer-drag reveal (same imperative-transform technique `BottomTabBar.jsx`'s own scrub gesture already established) since this app has no other swipe-list precedent to reuse; iOS (`MessagingViews.swift`) switched `InboxView` from a plain ScrollView/VStack to a `List` specifically to get SwiftUI's native `.swipeActions` — the idiomatic, lower-risk choice over a hand-rolled gesture, accepted trade-off: Inbox loses `ScreenScaffold`'s scroll-collapse-the-dock nicety other screens have, since that probe doesn't apply the same way inside a `List`. New `toggleThreadStar`/`archiveThread`/`unarchiveThread` (`GocContext.jsx`, right after `loadInboxThreads`; `AppState+Data.swift`, same placement) upsert into `thread_preferences`. **Design-token note**: the reference screenshot's green "Star" action isn't reused literally — 06-design-tokens.md documents this app as deliberately one-accent-color (`alert`, #9A3E2D; "one paper, one ink"), so Star uses `alert` and Archive uses `ink` instead of introducing a new green.

**Task 3 — unread row styling**: `loadInboxThreads()` on both platforms now also fetches `read_at` on the same `messages` query it already runs for last-message snippets, computes the same "does this thread have an unread message" signal the Task 3 dock badge (prior entry) already uses, and stores it per-row (`unread`/`InboxThread.unread`). Web bolds the name/snippet and shows a small `alert`-colored dot; iOS bolds via `.fontWeight(.bold)`/`.semibold` and the same dot. No second computation — reuses the exact same `read_at IS NULL AND sender_id != me` condition.

**Task 4 — composer attachments**: new `sendChatAttachment()` (`GocContext.jsx`, `AppState+Data.swift`) uploads to `chat-attachments` then inserts a `messages` row with `attachment_path`/`attachment_type` set and a short placeholder `body` (NOT NULL column) — reused `normalizeProofFile()`/`ProofImage.jpegDataUnderLimit` (this app's existing HEIC/oversized-photo re-encoders built for the payment-proof path) rather than writing a second resize pipeline. Web: "+" opens a small menu (`fieldGlass` popover) with "Thêm ảnh hoặc tài liệu" (plain `<input type=file>`) and "Máy ảnh" (`capture="environment"` input) — camera capture gets its own Retake/Use Photo review step before sending, built by hand since the web `<input capture>` API hands back the file directly with no native review UI. iOS: **found that `UIImagePickerController(sourceType: .camera)`'s own native flow ALREADY shows "Retake"/"Use Photo" before calling back** (`CameraPicker.swift`, new) — no custom preview UI needed there to satisfy the same requirement; "Add photo or document" uses `.fileImporter` (`[.image, .pdf]`) instead of `PhotosPicker` since the latter can't reach documents/PDFs. Rendering: an inline image for an `image/*` attachment (signed via new `signChatAttachmentUrls()`, same batched pattern `proofUrls`/`signProofUrls` already use for the private `pay-proof` bucket) or a small document chip otherwise, on both platforms.

**Task 5 — dock/icon labels**: `BottomTabBar.jsx`/`BottomTabBar.swift` bumped `BAR_HEIGHT`/`barHeight` 54→64 and trimmed `ICON_SIZE`/`iconSize` 24→20 to fit a small label under each icon without changing the bar's own width/pill shape; added a short one-word `dockLabel` per item distinct from the existing full `label` (used for `aria-label`/`accessibilityLabel`), since "Trang chính"/"Thông báo" are fine as accessibility strings but too long to sit under a 20px icon without wrapping. `BottomTabBarOverlay.swift` (iOS) reads `BottomTabBar.barHeight` directly for its hosting window's hit-testable band, so it stayed in lockstep automatically — no separate edit needed. Inbox's own new search/settings icons (Task 1) get the same small label-under-icon treatment. `NSCameraUsageDescription` (`project.yml`) broadened from "...scan a guest's ticket QR code..." to also mention chat photo attachment, since the same OS permission prompt now fires for both purposes.

**Not independently verified against a live account this pass** (no real signed-in session in this sandbox): the swipe gesture, camera flow, and feedback submission were verified by code inspection + both platforms' clean builds only, not an actual device/browser run-through — flagging per this ticket's own "confirm" ask, since inspection isn't the same as a live confirmation.

`vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. Migration 065 applied to production, confirmed via `migration list`.

## 2026-09-21 third follow-up — real-device Inbox bugs: star label, settings-sheet whitespace/timing, search autofocus

Three real-device bugs against 7210059/44387fe, fixed on both platforms.

**Bug 1a — star swipe action label didn't relabel**: the Archive action already correctly flipped its label (`c.archived ? 'Unarchive' : 'Archive'`) but Star was hardcoded `'Star'` regardless of state — only its icon (★/☆) followed the toggle. Fixed: `src/screens/Inbox.jsx`'s `InboxRow` now takes a `T` prop and reads `c.starred ? T('Bỏ đánh dấu','Unstar') : T('Đánh dấu','Star')`; `apps/ios/BanbeApp/Views/MessagingViews.swift`'s `.swipeActions` Star button, same fix.

**Bug 1b — settings sheet whitespace + slow animation**: 44387fe's own fix for the exposed-corner bug (extending the sheet's PAPER BACKGROUND through the bottom safe area via `.ignoresSafeArea(edges: .bottom)`) had a side effect it didn't account for — the background now reaches the true screen bottom, but the row CONTENT was never resized to match, leaving a large dead gap of solid paper between the last row and the real bottom edge. Confirmed by re-reading 44387fe's own `settingsSheet` structure (iOS-only — web's sheet has never had a fixed/extended background, it's always been content-sized). Fixed: row `.padding(.vertical, 13)` → `22` (both rows), so the two options' own tap targets fill the space instead of leaving it empty. Animation: `.spring(response: 0.3, dampingFraction: 0.8)` (matched to the tab bar's own quick scroll-collapse effect, appropriate for a small collapse but too fast for a full sheet slide) replaced with a shared, explicitly slower `Self.sheetAnimation = .spring(response: 0.6, dampingFraction: 0.85)`. Web's own sheet entrance (`gocSheetIn 0.32s`) also bumped, to a shared `SHEET_ANIM_MS = 600` constant.

**Bug 1c — search reveal shares the same timing + autofocuses**: web's search `<input>` already had `autoFocus` (should already reliably raise the keyboard, since it's set on mount inside a user-gesture-triggered render) — given the SAME shared `SHEET_ANIM_MS` entrance animation for consistency with the settings sheet, previously unanimated. iOS's `TextField` had no `@FocusState` at all — new `@FocusState private var searchFieldFocused: Bool`, `.focused($searchFieldFocused)` on the field, and `searchFieldFocused = searchOpen` set in the same tap handler that flips `searchOpen` (inside `withAnimation(Self.sheetAnimation)` — the toggle itself and the state read happen synchronously, only the visual transition is animated, so the keyboard now comes up the instant the field appears rather than needing a second tap).

`vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. No schema changes this pass.

## 2026-09-21 fourth follow-up — chat attachment signed-URL churn (real bug), Archived back-target

**Bug 4 — chat photo attachment stuck in an infinite loading loop**: real, confirmed root cause — `loadChatMessages` (`GocContext.jsx`) called `signChatAttachmentUrls(rows.map(m => m.attachment_path))` on EVERY invocation, including the 4s poll that runs the whole time a thread stays open. `createSignedUrls`/`createSignedURLs` issues a BRAND-NEW URL string (same file, different token/expiry) every time it's called, and `chatAttachmentUrls[path]` was being unconditionally overwritten with that fresh value each poll tick — since `<img src={chatAttachmentUrls[path]}>` (web) / `AsyncImage(url: app.chatAttachmentUrls[path])` (iOS) read straight off that map, a changing src/url value made the browser/SwiftUI tear down and re-fetch the image from scratch roughly every 4 seconds, reading exactly as "thumbnail appears/disappears repeatedly, never tappable/savable." Same root-cause SHAPE as the signed-URL churn already diagnosed for payment receipts (08-payment-documents.md) — not a loading-state wiring bug, a genuinely unstable URL. Fixed on both platforms, two levels: (1) `signChatAttachmentUrls` itself never overwrites a path it's already signed (`!acc[row.path]` / `chatAttachmentUrls[path] == nil` guards); (2) `loadChatMessages` now pre-filters to only request URLs for paths NOT already in `chatAttachmentUrls`, avoiding the redundant network round trip too, not just the redundant state write. Web's pre-filter reads `s.chatAttachmentUrls` via closure rather than adding it to `loadChatMessages`'s own `useCallback` deps, so the 4s poll's `setInterval` (which holds a reference to this function) doesn't get torn down and rebuilt every time a new attachment gets signed.

**Bug 5 — Archived thread list swipes back to Home instead of Inbox**: Archived (`s.inboxView === 'archived'` / `app.inboxView == .archived`) isn't a separate `Screen`, just a sub-state of `.inbox` opened from Inbox's own settings menu (6fa094f/1c62d4c). iOS's edge-swipe-back routing (`AppState.goBack()`/`backTargetScreen`, the same centralized mechanism this app already uses for every other screen's back gesture, matching the `documentBack`/`verificationsBack`-style per-screen back-target convention) ran `backFromInbox()` unconditionally for `.inbox`, ignoring `inboxView` entirely — so swiping back while Archived was showing jumped straight past the regular Inbox list to wherever Inbox itself was opened from (Home/Profile), skipping the "return to the active list first" step the existing on-screen "‹ Quay lại Tin nhắn" link already gets right. Fixed: `goBack()`'s `.inbox` case now checks `inboxView == .archived` first (drops back to `.active` instead of calling `backFromInbox()`); `backTargetScreen`'s `.inbox` case does the matching computed-only check (`inboxView == .archived ? .inbox : inboxBack`) for the edge-swipe peek preview. Web has no equivalent bug — it has no second, gesture-driven exit path at all (confirmed in prior sessions' own audits, no `popstate`/history-stack wiring anywhere), so the existing on-screen link was always the only way back and already worked correctly.

`vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. No schema changes this pass.

## 2026-09-21 fifth follow-up — chat-image aspect ratio + fullscreen viewer (save/share/forward), real Stories system

**Root cause of the white side-rails (Task 1), confirmed by reading, not guessed**: neither platform had ever persisted the source image's own intrinsic width/height — `messages` had no such columns. Web's bubble was already `maxWidth/maxHeight` only (no forced square), so it wasn't actually broken; iOS's WAS: `AsyncImage(url:) { $0.resizable().scaledToFit() }.frame(maxWidth: 220, maxHeight: 220)` — `.scaledToFit()` inside a box whose aspect ratio doesn't match the source leaves empty space on two sides, which is exactly the reported bug. Fixed by adding `messages.attachment_width/height` (migration 066) and computing an aspect-ratio-correct BOX (not just a `.fit`/`.fill` mode swap) from those on both platforms — `attachmentBoxSize()` (`Chat.jsx`) / `ChatView.attachmentBoxSize(width:height:)` (`MessagingViews.swift`), same formula on both: box's own ratio = source ratio, clamped to a 120–240×320 range, then `objectFit:'cover'`/`.scaledToFill()` inside that correctly-shaped frame never has anything to crop. `normalizeProofFile()` (`src/lib/proofUpload.js`) now also returns `width`/`height` (probed via `decodeToPaintable()`, even on the already-allowed pass-through path) — additive, existing payment-proof callers unaffected; updated `tests/proof-upload.spec.js`'s exact-object-equality assertions to include the new `width: null, height: null` fields for that suite's plain-mock-object tests (a real image can't be decoded from a `{type, name}` mock, so those two always come back null there — only exercised against a real image in the browser, see the new Playwright suite below). iOS: `UIImage(data: data)?.size` read AFTER `ProofImage.jpegDataUnderLimit()`'s own re-encode (not `image.size` before it) — the dimensions must match what was actually uploaded, not the original picked photo's pre-downscale size.

**Task 2 — a chat photo's own fullscreen viewer, deliberately NOT a retrofit of `PhotoViewer.jsx`/`PhotoViewerView.swift`**: that component's dismiss/gesture machinery and action set (Like/Save-event/Share, gallery prev-next) is built around an event's static-catalogue gallery, not a single chat attachment with different actions (Save/Share/Forward) and different back semantics (must return to the exact chat, never Event Detail/Home). New, separate state+component on both platforms: web `chatPhotoViewer` (`GocContext.jsx`) + `ChatPhotoViewer.jsx` (new); iOS `AppState.chatPhotoViewer: ChatPhotoViewerItem?` + `ChatPhotoViewerView.swift` (new). Reused 14-photo-viewer.md's CONVENTIONS (blurred/dimmed backdrop, tap-to-dismiss, a shrink/fade dismiss) rather than its code — deliberately simplified to a single eased transform computed once at dismiss time, not a full per-frame drag-follow, since a single non-browsable image doesn't need prev/next swipe machinery.
- **Save/Download**: web fetches the real signed-URL bytes and triggers a real `<a download>` (never a screenshot/blank response); iOS fetches the bytes and writes them via `PHPhotoLibrary.performChanges`/`PHAssetChangeRequest.creationRequestForAsset(from:)`, gated on `.requestAuthorization(for: .addOnly)` — new `NSPhotoLibraryAddUsageDescription` added to BOTH `project.yml`'s `info.properties` (what XcodeGen actually bakes into the built Info.plist) and the static `Info.plist` template, per this codebase's own established convention (06-design-tokens.md's portrait-lock entry already documents why both need it).
- **Share**: Web Share API with the real file where `navigator.canShare({files})` supports it, falling back to the same download path; iOS presents a real `UIActivityViewController` with the decoded `UIImage`, same pattern `PhotoViewerView.swift` already established for its own share action.
- **Forward — a real bug caught and fixed while implementing, not shipped**: a forwarded message can't simply reference the SOURCE thread's own `attachment_path` — `chat_attachments_participant_read` (migration 065) grants read access keyed on the object's OWN path prefix (the thread id it lives under), not on the message row that references it, so the target thread's other participant (who isn't necessarily in the source thread) would get a permission-denied signing that URL. Fixed by re-fetching the real bytes from the already-authorized signed URL and re-uploading them under the TARGET thread's own path before inserting the new message — `forwardChatPhoto()` (both platforms). Only threads the sender is an actual participant of are ever offered (`s.inboxThreads` / `app.inboxThreads`).
- **Security**: no public/permanent URL introduced anywhere in this pass — save/share/forward all read the same private, signed `chat-attachments` URL the inline bubble already uses. The signed-URL-churn bug (bc4724d) could NOT recur here since this pass didn't touch `signChatAttachmentUrls`'s own already-signed-path guard.

**Task 3 — Stories, a genuinely new but deliberately small system**: checked first, per this ticket's own instruction, whether a follow relationship or a media/story table already existed.
- **`follows(user_id, organizer_id)` already existed** (003_social_chat.sql) but had **zero writers anywhere in the app** — confirmed by grep. `toggleFollow()` (both platforms) was 100% local React/`@Published` state, keyed by EVENT key, never touching this table at all. A real bug, fixed alongside this pass since stories needed a real audience: `toggleFollow()` now also resolves the event's real `organizer_id` (same `events`-table lookup `openChatFor()`/`openChat(for:)` already do) and upserts/deletes the matching `follows` row — best-effort, a demo-catalogue event with no real DB row only updates local state, same as before. This is exactly why `stories.organizer_id` exists (the ticket's own suggested schema only had `author_id`) — a "host" in this app IS an `organizers` row, and `follows` is keyed on that, not on a profile-to-profile edge; inventing a second, parallel person-to-person follow model would have duplicated a graph that already exists for exactly this purpose.
- **Schema** (migration 066): `stories`/`story_views` + RLS (active-only + author/co-owner/follower-scoped SELECT; author/co-owner-scoped INSERT/DELETE; viewer-own-row-only story_views INSERT) + a private `stories` storage bucket (path convention `<organizer_id>/<file>`, same `split_part((objects).name,'/',1)` pattern `chat-attachments`/`pay-qr` already use, keyed on organizer id since visibility here is follows-based not thread-membership-based) + `cleanup_expired_stories()` (SECURITY DEFINER, hard-deletes only rows where `expires_at <= now()`, returns freed `media_path`s for a caller to also clear from Storage — mirrors 08-payment-documents.md's own division of responsibility between a DB sweep and an out-of-band storage-object cleanup, not built as a single all-in-one job this pass).
- **Verified directly against production, not just read**: inserted a real story via service role, confirmed `expires_at - created_at` is exactly 24h; confirmed `cleanup_expired_stories()` is a no-op against an active story and correctly removes (only) one forced into the past, returning its `media_path`; confirmed an anon (unauthenticated) client reads 0 rows for a real story id and is refused an INSERT with a genuine RLS-violation error, not just an application-level check.
- **Creation**: reuses the chat attachment flow's own Retake/Use Photo preview convention (`Account.jsx`'s new story section / `AccountView.swift`'s `storyCreatePreview`), hosts only (`canHost`), publishing to the signed-in account's first owned organizer.
- **Visibility**: `loadHomeStories()`/`AppState.loadHomeStories()` — one unfiltered `stories` SELECT (RLS does 100% of the audience filtering), grouped by organizer, joined against `story_views` for per-story viewed state and `organizers.name` for display; the signed-in account's own active story sorts first. Story ring: bright while any active-not-yet-viewed story exists, subdued (rule-colored) once every active story from that author has been viewed, absent otherwise — both on Account/Profile's own avatar and each host's avatar in Home's new story row (placed between "Your events" and the category filter row, per this ticket's own instruction).
- **Viewer**: `StoryViewer.jsx`/`StoryViewerView.swift` — fullscreen, progress bars per story in that author's active set, auto-advance (5s/story) plus manual left/right tap zones, records a real `story_views` row (idempotent upsert) on every story shown including the first. A third, separate viewer/state from `photoViewer` and `chatPhotoViewer` per 14-photo-viewer.md's own established principle of not conflating origin/back semantics across viewer kinds.
- **Not done this pass, flagged rather than silently skipped**: the actual Storage BYTES of an expired story are never deleted automatically — only `cleanup_expired_stories()`'s DB-row sweep runs (called opportunistically from `loadHomeStories()`); wiring an actual periodic caller (cron/admin script) that also calls `storage.remove()` on the returned paths is the next step if orphaned storage objects become a real concern, same unfinished half `08-payment-documents.md`'s own retention sweep already documents for a different bucket.

**Real, executed Playwright verification (`tests/chat-photo.spec.js`, new), not just reasoning** — against the real seeded `phong302`/`org_phong302` event+organizer (010_seed_data.sql, has genuine `events`/`organizers` rows, unlike most of the static demo catalogue), using the shared persistent fast-suite test account:
- A portrait (301×602), a landscape (603×301), and a square (401×401) real PNG (hand-built in Node, not a mock, with a correct CRC so the browser's own PNG decoder accepts it) each upload and render at a box whose shape matches their own ratio (portrait taller-than-wide and narrower than the old fixed 220px box; landscape wider-than-tall; square within 3px of equal) — genuine `boundingClientRect()` measurements, not inspecting the JSX.
- The portrait image is tappable, opens `ChatPhotoViewer`, and dismissing it returns to the exact same Chat screen (`data-screen-label="Chat"` reappears, not Event Detail/Home).
- A fresh upload's signed URL is byte-identical before and 5.5s after (past one 4s poll cycle) — confirms the bc4724d churn bug class has not recurred.
- **New fact found while writing this suite**: this thread is a real, ever-growing DB row shared across every run — neither `.last()` nor a before/after attachment-COUNT diff is a reliable way to target "the message THIS test just uploaded," both directly observed racing the async `loadChatMessages()`/sign fetch (reading a stale, too-low count before that fetch had even started). Fixed by matching on the uploaded image's own exact `naturalWidth`/`naturalHeight` instead (`findAttachmentIndex()`) — sidesteps the ordering/timing race entirely since there's exactly one message with a given test's odd, randomly-chosen size at any moment. Worth remembering for any future test against this same persistent thread.

`npx vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED; `tests/chat-photo.spec.js` 3/3 pass (chromium); `tests/proof-upload.spec.js` 15/15 pass after updating for the new width/height fields; confirmed `tests/navigation-and-events.spec.js`'s one pre-existing failure (a gallery-photo swipe-index assertion, unrelated to any file this pass touched) fails identically on the pre-this-pass commit too, via `git stash` — not a regression introduced here.

## 2026-09-22 sixth follow-up (real-device report on f253886) — Post Story menu/picker/dock, revised chat-image interaction, reply composer

Four real, confirmed root causes, all fixed on both platforms unless noted.

**Task 1.2 — "Photo library" did nothing on a real iPhone**: confirmed root cause by reading, not guessed — `PhotosPicker(selection:matching:)` was used DIRECTLY as a `Menu` row's content (`AccountView.swift`). `Menu` wraps each row as its own tap target and can swallow the touch before `PhotosPicker`'s own internal presentation trigger ever fires — a known SwiftUI/real-device gap that looks fine in Simulator and silently no-ops on-device. Fixed by moving the PRESENTATION out of the Menu (still real `PhotosPicker`/`.photosPicker`, not a different API, per this ticket's own instruction not to just swap in another button): a plain `Button` inside the Menu now only flips `storyLibraryPickerOpen`, and `.photosPicker(isPresented: $storyLibraryPickerOpen, ...)` is attached to the screen itself — `AccountView.swift`.

**Task 1.1 — no icons on "Photo library"/"Camera"**: web's Account "Đăng story" wasn't even a menu before this pass — a single link that only ever opened the library input, no Camera option at all. Rebuilt as a real two-row popup menu matching `Chat.jsx`'s own attach-menu shape exactly (`Account.jsx`), and added a shared `AttachMenuIcon` component (stroke-only, 24x24 viewBox, matching `BottomTabBar.jsx`'s own icon vocabulary — not borrowed IG/Messenger artwork) used by BOTH the chat attach menu and the story menu, so they read as one family as this ticket asked. iOS: added matching `Label(..., systemImage:)` icons (`photo.on.rectangle`/`camera`) to `AccountView.swift`'s Post Story menu — the chat composer's own "+" menu (`MessagingViews.swift`) already had these SF Symbols from f253886, unchanged.

**Task 1.3 — Retake/Use Photo untappable behind the dock**: confirmed the SAME class of bug `BottomTabBarOverlay.swift`'s own doc comment already documents at length (a5fd823/4d549f9) — a real, always-on-top second `UIWindow` sits above ANY main-window presentation, including a `.photosPicker`/`.fullScreenCover`, and `.profile` staying in `BottomTabBar.visibleScreens` the whole time meant `updateVisibility(for:)` never hid it for these. `.chat` is NOT in `visibleScreens` (the dock is already hidden there), so this was Account/Profile-only for the story flow, but the SAME fix was applied to `ChatView`'s own camera/file-importer flow too per this ticket's explicit "same rule should apply" instruction, even though it's currently a no-op there (dock already hidden) — cheap insurance against a future screen where the dock does show. Both reuse the EXACT `setForcedHidden(_:)` mechanism InboxView already established (no second mechanism invented): `AccountView.swift` ORs together `storyLibraryPickerOpen || storyCameraOpen || (app.storyCreatePreviewImage != nil)`; `MessagingViews.swift`'s `ChatView` ORs `cameraOpen || fileImporterOpen`. Both reset via `.onDisappear`.

**Task 2 — revised chat-image interaction, confirmed both platforms**: backdrop/photo tap now toggles chrome (top bar + bottom composer fade out/in) instead of dismissing; only a downward drag past threshold dismisses, reusing 14-photo-viewer.md's live-drag-follow convention (photo tracks the finger, chrome/backdrop fade with drag progress, release short of threshold springs back via `.spring`/CSS transition). Web: `ChatPhotoViewer.jsx` rewritten around a single `onPointerDown/Move/Up` "stage" gesture (ref-driven live transform during drag, same non-state-churn reasoning 14-photo-viewer.md's own drag code already documents) that disambiguates a plain tap (toggle chrome) from a real downward drag (dismiss) by distance, exactly like `PhotoViewer.jsx`'s own tap/swipe axis-priority check. iOS: `ChatPhotoViewerView.swift` rewritten around one `DragGesture(minimumDistance: 0)` doing the same disambiguation. Top bar: close (identical to a completed swipe-dismiss), then Post to Story (hosts only)/Save/More — in that order, per this ticket's own spec. More menu: Share, Forward (only when eligible threads exist, unchanged from f253886), Copy.
- **Copy**: web feature-detects `navigator.clipboard`/`window.ClipboardItem` and only shows the row when both exist (per this ticket's own "never make a dead action" instruction) — writes the real image bytes via `ClipboardItem`. iOS: `UIPasteboard.general.image = image` — genuinely works unconditionally, no feature-detection needed, so no hiding logic there.
- **Edit (image markup) and Live Text — deliberately NOT shipped this pass, not silently dropped.** This ticket's own bar for Edit was explicit: "only if it can genuinely work... do not show Edit if it is a no-op." A real draw+text-annotation-then-export-a-derived-image flow (retaining the original) is a substantial, independent feature — PencilKit/canvas drawing surface, a text-placement tool, and a compositing export step, each with its own real failure modes (canvas-to-blob support, PencilKit tool state, coordinate-space math between the displayed image and the full-resolution original). Shipping a rushed version risks the exact "dead/broken action" outcome this ticket explicitly forbids more than omitting it does. Live Text (`ImageAnalysisInteraction`/VisionKit) is a bounded, well-documented API and a better candidate for a focused follow-up, but wasn't reachable in this pass's budget either — this ticket's own instruction allows omitting it on web ("unless a genuine equivalent already exists" — none does) and by extension the same discipline was applied to iOS rather than shipping an untested VisionKit integration. Both are explicitly flagged here as the next real follow-up, not abandoned silently.

**Task 3 — reply/reaction composer, real schema addition**: `messages.reply_to_message_id` (migration 067, nullable self-reference, no new RLS needed — existing `messages_select_thread_participant`/`_insert_participant` policies are thread-scoped and untouched by this column). Checked first, per this ticket's own instruction, whether the existing attachment schema could represent this — it couldn't (no message-to-message reference existed at all) — and added the SMALLEST explicit column rather than encoding "replying to X" in body text, which the ticket itself warned against. New `sendChatViewerReply()`/`AppState.sendChatViewerReply(text:replyToMessageId:)` — a SEPARATE function from `chatSend()`, since this viewer has its own local composer draft state, not `s.chatDraft`/`AppState.chatDraft` (which belongs to the main Chat screen and shouldn't be touched by something typed from inside a fullscreen photo viewer). `sendChatAttachment()` on both platforms gained an optional `replyToMessageId` param, reused by the viewer's own attach button. A small reply-to-media reference (a 22x22 thumbnail + "Replying to a photo" label) renders above the resulting bubble in the main Chat thread — `Chat.jsx`/`MessagingViews.swift`'s `bubble()` — resolved against the already-loaded `chatMessages`/`app.chatMessages` (a reply's target is always a message in the same thread already in memory, no second query). Bottom composer: a fixed 6-emoji quick-reaction row (not a full emoji-picker library — this app has none, and pulling one in for six buttons wasn't worth it), an attach button (reuses the same picker/upload path), a text field, and Send.

**Task 4 — Story regression checks**: `postChatPhotoToStory()`/`AppState.postChatPhotoToStory()` write into the EXACT SAME `stories` table via the EXACT SAME insert shape `publishStory()` already uses (same columns, same bucket) — structurally guaranteed to be the identical Story type, not a parallel one; both call `loadHomeStories()` on success so the ring/Home row reflect it immediately. A real review step (`postToStoryConfirm`) gates the actual publish per this ticket's "do not immediately publish by accidental tap" instruction. Double-tap guard: `storyCreateBusy` is checked and set BEFORE the first `await` on both platforms (an atomic guard on iOS's single-threaded MainActor; on web, `set({storyCreateBusy:true})` happens synchronously in the same call before any `await`, and the confirm button's own `onClick` is already gated on `s.storyCreateBusy` from the PREVIOUS render — covers a real double-tap, which has a human-scale gap between the two taps for React to re-render in between; a synthetic same-tick double-fire was not specifically hardened against, flagged rather than silently assumed safe). RLS/audience/expiration were unchanged by this pass — verified in the previous entry above, not re-verified here since nothing about the `stories` table itself changed.
- **Known environment gap, not fabricated around**: the shared fast-suite Playwright test account (`cf54316e-...`) owns NO organizer (confirmed live) — only `org_phong302`'s real owner does, a different account — so `canHost` is false for it and "Post to Story" never renders for that account in this session's automated tests. The button's own behavior was verified by code review + the identical-schema argument above, not by a live Playwright click-through; a real host account (or a temporary service-role-granted organizer for the test account) is what a future pass should use to close this gap with an executed test.

File:line — web: `src/screens/Chat.jsx` (`AttachMenuIcon`, `messageById`/reply-reference block), `src/screens/Account.jsx` (story menu rewrite), `src/screens/sheets/ChatPhotoViewer.jsx` (full rewrite — stage gesture, top bar, more menu, post-to-story confirm, bottom composer), `src/state/GocContext.jsx` (`sendChatViewerReply`, `openPostToStoryConfirm`/`closePostToStoryConfirm`/`postChatPhotoToStory`, `sendChatAttachment`'s new `replyToMessageId` param). iOS: `apps/ios/BanbeApp/Views/AccountView.swift` (menu icons, `storyLibraryPickerOpen`, dock-hiding `onChange`s), `apps/ios/BanbeApp/Views/MessagingViews.swift` (dock-hiding `onChange`s, `bubble()`'s reply-reference block), `apps/ios/BanbeApp/Views/ChatPhotoViewerView.swift` (full rewrite), `apps/ios/BanbeApp/State/AppState.swift`/`AppState+Data.swift` (`sendChatViewerReply`, `postChatPhotoToStory`, `openPostToStoryConfirm`/`closePostToStoryConfirm`, `sendChatAttachment`'s new param), `apps/ios/BanbeApp/Models/Thread.swift` (`ChatMessage.replyToMessageId`), `apps/ios/project.yml` (no new Info.plist keys this pass — PhotosPicker/UIPasteboard need none).

Migration: `supabase/migrations/20260922000067_067_message_reply_to.sql`, applied via `supabase db push`.

Verified live: `tests/chat-photo.spec.js` now 5/5 (added two new tests — backdrop-tap-toggles-chrome-never-dismisses, and a quick reaction sent from the viewer produces a real reply-reference chip in the thread — both against real uploads/real DB writes, not mocked). `npx vite build` clean; iOS `xcodegen generate` + `xcodebuild -destination 'generic/platform=iOS Simulator'` BUILD SUCCEEDED. `tests/account-and-preferences.spec.js` (5/5) and `tests/proof-upload.spec.js` (15/15) re-run clean, confirming no regression from the Account.jsx/Chat.jsx changes.

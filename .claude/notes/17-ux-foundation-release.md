# UX foundation release — Action Center, held-booking gating, create-event FAB, shareable profile, Banbe Pulse (2026-10-01)

## Status: WORKING (web + iOS) — five features in one pass, after commit 108546d. Read this before touching any of them again.

## Migration chain
- `20260930000079_079_public_profile_card_and_avatars.sql` — `profiles.handle` (unique, backfilled for every existing row from its own id — never from display_name), `bio`/`city`/`interests`/`profile_theme`; `avatars` Storage bucket (public read, owner-only write, path `<user_id>/<filename>`); `save_profile()` (owner-only edit, validates handle format, returns `HANDLE_TAKEN`/`INVALID_HANDLE`/`INVALID_NAME`); `get_public_profile(p_handle)` — the ONE read path for someone else's profile (granted to `anon` too — a shared `/u/<handle>` link must resolve for a signed-out visitor), returns only public-safe fields (never phone/role/organizer bank details).
- `20260930000080_080_banbe_pulse_ranking.sql` — `goc_pulse_ranked(p_period)` ('daily'/'weekly'), granted to `anon` too. **No `stories` table change at all** — see Bug/Decision section below for why.

**If touching these again: read both migrations in full before writing a new one.**

## A. Action Center
- Shared pure builder: `src/lib/actionCenter.js` (`buildActionCenterItems`/`sortActionCenterItems`) / `apps/ios/BanbeApp/Lib/ActionCenter.swift` — takes already-loaded canonical arrays (`paymentBookings`, `myRefunds`, `verifications`, `refundQueue`, `organizerHoldingSummary`) and returns a priority-sorted list (overdue → deadline-soon → money → normal). Presentational piece: `src/screens/ActionCenter.jsx` / `ActionCenterView.swift` — caps to 3 + "Xem tất cả", renders nothing at all when empty.
- **This REPLACED Home's old fixed four-`PhaseBanner` block** (myHolding/myPendingVerification/orgPendingCount/orgHolding) rather than living alongside it — those four signals are folded into the same unified, capped list (see the builder's own comments for why `pendingVerification`/`orgHolding` aren't part of this ticket's own 4+4 source list but were kept from being lost).
- Mounted on Home, Account, Dashboard (never Map). Each screen loads its own copies of the canonical sources on mount (`loadPaymentBookings`/`loadMyRefunds`/`loadVerifications`/`loadRefundQueue`/`loadOrganizerHoldingSummary`) — no new polling was added; a screen open long enough to want a live update already has 16-refund-lifecycle.md's own polling on the underlying sources it reuses.
- "Xem tất cả" routes to Notifications (Home) or the canonical Verifications/refund-queue screen (Account/Dashboard) — there is no single unified "all actions" screen; picked whichever existing surface most literally IS "everything" from that vantage point.

## B. Held booking vs ticket
- ONE shared rule, both platforms: `isBookingTicket(booking)` (`src/lib/bookingTicket.js`) / `Booking.isTicket` (`Booking.swift` extension) — `status == "confirmed" AND payment_state == "confirmed"`, never either alone.
- **Real bug found and fixed**: `EventDetail.jsx`'s/`EventDetailView.swift`'s "reserve bar" already had a `myBooking` gate checking `status IN ('pending','confirmed','attended')` — but its LABEL unconditionally read "Xem vé của bạn ▪︎ mã {code}" ("View your ticket ▪︎ code X") for ANY of those three statuses, including a still-holding/still-pending-verification booking. That's a real ticket-code leak before confirmation. Fixed: label now checks `isBookingTicket`/`.isTicket` separately from the tap-target gate, falls back to "Xem trạng thái thanh toán"/"View payment status" otherwise. The tap target itself was already safe (routes to Confirmed/ConfirmedView, which self-gates the actual QR correctly).
- `Confirmed.jsx`/`ConfirmedView.swift` now both route their own `isPaid` through the same shared helper (added the missing `status == 'confirmed'` check alongside the pre-existing `payment_state` check).

## C. Fast create-event entry point
**SUPERSEDED 2026-10-03** — the floating pill described below was replaced by a compact dock-adjacent "+" button. See the dated fix-pass section further down; `CreateEventFab.jsx`/`CreateEventFabView.swift` no longer exist.
- ~~Web: `src/screens/CreateEventFab.jsx`, mounted once in `App.jsx`'s `Shell`. Allowlist (`home`/`dashboard`/`profile`), not a denylist — a new screen added later defaults to NOT showing the FAB. Matches `inkButton` visual language (dark glass pill, drop shadow). Positioned above the bottom tab bar when one shows, safe-area aware by construction (`position: absolute` inside the same fixed-viewport container everything else uses).~~
- ~~iOS: `CreateEventFabView.swift`, a plain ZStack sibling in `RootView.swift` (NOT the separate always-on-top UIWindow `BottomTabBar` uses — this FAB only ever needs to sit above ordinary screen content, never above a native `.sheet()`, so it doesn't need that mechanism). Sits below `StoryViewerView`'s zIndex 27 by construction, which is what makes "hidden during full-screen story viewer" true for free rather than needing an explicit check.~~

## D. Shareable profile card
- Web: `src/screens/EditProfile.jsx` (owner's own edit — avatar/handle/name/bio/city/interests/palette), `src/screens/PublicProfile.jsx` (anyone's read view — organizer mode shows event/follower stats + Follow CTA, "Hiển thị mã QR", native share/clipboard fallback). iOS: `EditProfileView.swift`/`PublicProfileView.swift`, `AppState+Profile.swift`.
- Account header (`Account.jsx`/`AccountView.swift`) is now a rounded card with a palette-tinted gradient wash and the REAL `avatar_url` image (previously a hardcoded "G" letter placeholder — confirmed by reading the code, not assumed) — a separate trailing chevron opens Edit, so it doesn't conflict with the story-ring/post-story-menu's own existing nested tap targets.
- Universal link: `https://banbe.app/u/<handle>`. Web: parsed at module load in `GocContext.jsx` (same "read once before React mounts" pattern as the existing `?ref=`/`?org=` handling), works signed-out (`get_public_profile` granted to `anon`). iOS: `com.apple.developer.associated-domains` (`applinks:banbe.app`) added to BOTH entitlements files (Associated Domains, unlike Push, works on a free/personal team) + `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` in `BanbeApp.swift` → `AppState.handleUniversalLink(_:)`.
- **What's still a placeholder, not fully live**: `public/.well-known/apple-app-site-association`'s `appID` uses a literal `"TEAMID"` string — must be replaced with the real Apple Developer Team ID before universal links actually resolve (until then iOS silently falls through to opening the plain web URL — the documented degraded state, not a crash). `src/lib/appStore.js`'s `APP_STORE_URL` is an obvious placeholder App Store id. Neither blocks the feature from working end-to-end today (the web `/u/<handle>` page itself is fully real) — they're what to swap in once this app has a real Team ID/App Store listing. **2026-10-02**: for local real-device testing on a free Apple ID in the meantime, see `.claude/notes/18-ios-personal-team-signing.md` — the `PersonalTeamDebug` config/entitlements this Associated Domains entitlement made necessary.
- Avatar upload has no in-app crop UI — simple pick + upload, auto-fit via `object-fit: cover`/`.scaledToFill()`. A deliberate scope cut, not an oversight — see "OUTPUT" of the original ticket if a real cropper is wanted later.
- Follow/unfollow reuses the existing organizer-scoped `follows` table directly (its own RLS already permits `auth.uid() = user_id` insert/delete) — no new RPC needed for that part.

## E. Banbe Pulse
- **Key decision: "Banbe Pulse" is NOT a real row in `stories`.** That table hard-expires everything in 24h by both column default (`expires_at DEFAULT now()+24h`) and its own RLS SELECT predicate (`expires_at > now()`) — see 16-refund-lifecycle.md-adjacent stories notes. Rather than adding a `kind`/`pinned` column + an RLS exemption to a table whose entire design is "this expires," Pulse is a purely CLIENT-side synthetic first ring entry (index 0, permanent, always rendered) that opens a dedicated viewer backed by its own ranking RPC — matches this ticket's own explicit "not authored as a normal 24h user story" rule exactly, and is structurally simpler/lower-risk than special-casing the stories schema.
- Ranking: `goc_pulse_ranked(p_period)` — bounded, transparent score: confirmed bookings in the period (capped 20, weight 3, max 60) + check-ins (capped 15, weight 2, max 30) + organizer follower count as a bounded proxy for "new follows" (capped 10, weight 1.5, max 15 — see the migration's own comment: `follows` has no `created_at` column yet, so a true "new in this period" count isn't derivable without its own migration; this is the honest current substitute, not a silent shortcut) + event saves/favorites (capped 10, weight 1, max 10). Max score 115. Computed ON READ (a plain SQL query with lateral joins), not a materialized view or cron job — correct and transparent today; if this app's event volume grows enough that the query cost becomes real, the next step is a materialized view refreshed on a schedule, same shape as the query itself, not a rewrite.
- Only `status = 'live' AND visibility = 'public'` events with at least one `event_photos` row are eligible (join, not a filter — an event with zero approved photos structurally cannot appear). Capped to the single highest-scoring event per organizer (`DISTINCT ON (organizer_id)`), then top 20 organizers overall. No moderation-hidden flag exists anywhere in the current schema to exclude by — nothing to filter on yet.
- Web: `src/screens/sheets/PulseViewer.jsx` (two tabs, tapping organizer identity opens a compact follow sheet, tapping the card/event navigates via `goEvent`). iOS: `PulseViewerView.swift` + `AppState+Pulse.swift`, presented via `.fullScreenCover` — needed its own `BottomTabBarOverlay.setPulseViewerOpen(_:)` (mirrors `setStoryViewerOpen`) since the tab bar's separate always-on-top UIWindow would otherwise paint above a `.fullScreenCover` regardless of normal z-ordering, exactly the same reason `StoryViewerView` needed one.
- Ring entry always visible on Home (both platforms) — the story row itself is no longer conditional on real stories existing (`if !homeStories.isEmpty` removed); Pulse is always there even with zero real stories.

## Fix pass (2026-10-03) — Pulse ranking honesty, organizer-mode toggle, dock create button

### Bug — organizer mode "appears on by default and cannot be turned off"
**Confirmed root cause, TWO compounding bugs, both mirrored on iOS**:
1. **The toggle computed its target from the wrong variable.** `toggleOrganizerMode()` called `applyOrganizerMode(!canHost)` — `canHost` is ELIGIBILITY (`organizerMode || accountType === 'admin' || hasHosted`), not current preference. For any account that has ever really hosted (`hasHosted === true`, re-derived from a genuine `organizers` ownership query on every session sync, independent of the toggle), `canHost` is permanently `true` regardless of `organizerMode`'s own value — so `!canHost` was always `false`, and every tap just re-applied "off" to a preference that might already be off, with **no way to ever toggle it back to `true`**.
2. **`applyOrganizerMode(false)` also cleared `hasHosted: false`** — an attempt to make bug 1 "work" by collapsing eligibility down to match the toggle, which only worked by accident for the very first tap and actively fought the truthful, independently-re-derived value of `hasHosted` on the very next session resync (which always sets it back to `true` for a real host, since that lookup has nothing to do with the toggle).
3. **The switch's visual state, the Account "Hosting" section, and the "Đăng story" menu were all bound to `canHost`/`isOrganizer = canHost`, not `organizerMode`** — so even on builds where the underlying state genuinely did flip correctly, the UI never visually reflected it for any real host, reading as permanently "on."
**Fix**: `applyOrganizerMode` no longer touches `hasHosted` at all (it's a fact, not a preference); `toggleOrganizerMode` now targets `!organizerMode`; `isOrganizer`/all switch-visual and host-management-section gating now reads `organizerMode` directly. `canHost` is kept, unchanged, for genuinely eligibility-scoped decisions: the Account "Hosting" card's own branch (existing host → "your host page" card; never-hosted → "Host your first event" onboarding pitch) and the Action Center's host-source loading — both intentionally still fire regardless of whether `organizerMode` is currently on, per this ticket's own "don't silently hide money owed" rule.
**Files**: `src/state/GocContext.jsx` (`applyOrganizerMode`, `toggleOrganizerMode`), `src/screens/Account.jsx` (`isOrganizer`, the eligibility-vs-mode split at the "Hosting" card); iOS: `AppState+Data.swift` (`toggleOrganizerMode`, `applyOrganizerMode`), `AccountView.swift` (switch ZStack, subtitle, story-post menu, host management list — `switchToHost` card correctly already used `canHost`, unchanged).
**Lesson**: `profiles.role` has zero bearing on real authorization anywhere in this schema (confirmed by grep — every real host RLS/RPC check is `organizers.owner_id`/`user_id`, never `profiles.role`) — it is purely a self-reported UI preference. Any code that reads it (directly, or via `canHost`) to decide "should I re-apply eligibility as if it were the user's current choice" will eventually reintroduce this exact bug class.

### Pulse — ranking formula unchanged; what "like" actually does today
**Traced, not assumed**: the heart-icon "like" in `PhotoViewer.jsx` (`togglePhotoLike`/`isPhotoLiked`/`s.photoLikes`) is a **plain `localStorage` array, keyed by raw photo URL, never sent to Supabase at all** — confirmed by reading the whole implementation, zero `supabase.*` calls anywhere in it. It also only ever operates on the **static demo catalogue's bundled photo arrays** (`EventDetail.jsx`/`Organizer.jsx` pass `ev.gallery`/`ev.orgGallery` from `src/data/events.js`, never a real `event_photos` row) — structurally disconnected from anything Pulse could ever rank (`goc_pulse_ranked()` only ever considers real `events`/`event_photos` rows). Building a durable per-user like table for this would be infrastructure for content that can never overlap with a ranked event — explicitly why this pass did **not** add one. The ranking formula is therefore unchanged from migration 080 and this is the honest reason, not an oversight: it correctly excludes "photo likes" because there is no real per-event-photo user signal for it to bind to.
**Related, found in the same investigation but NOT fixed this pass (flagged, out of scope)**: `toggleFav`/`s.favorites` (the bookmark "save" button) is **also** local-only — zero `supabase.from('favorites')` calls anywhere in the app — meaning the ranking formula's own "event saves" signal is currently dead too (the `favorites` table it counts is never written by any client code path). This is a real, separate gap worth a future pass; not touched here to keep this fix scoped to what was actually asked.
**What WAS a real bug, fixed**: `loadPulse()`'s request-sequencing guard used a single counter shared between `daily` and `weekly` — since `openPulseViewer()` fires both calls back-to-back, the `daily` response almost always arrived after the `weekly` call had already bumped the shared counter past it, so its "stale response" check silently discarded a legitimate, correctly-ordered response for a completely different tab. Fixed: one counter per period, both platforms. Also added genuine per-tab loading state (`pulseDailyLoading`/`pulseWeeklyLoading`) so a still-fetching tab reads as "Đang tải…"/"Loading…" instead of flashing "Chưa có dữ liệu xếp hạng."/"Nothing ranked yet." before its real response lands — that flash was a direct, visible symptom of the sequencing bug above.
**A7 — dismiss gestures**: iOS `PulseViewerView` gained an interactive drag-to-dismiss, attached ONLY to the header row (title/tabs/close button), never the `ScrollView` — so vertical card scrolling, tab switching, and the organizer sheet's own presentation are completely unaffected; dragging down from the header past a 120pt threshold closes it, matching `.sheet()`'s native feel even though `.fullScreenCover` has no built-in equivalent. Web: Pulse now participates in `window.history` the same way `refundAccounts`/`myRefunds` already do (`pushState` on open, a `popstate` listener closes it) — the browser back button closes Pulse instead of navigating the screen underneath it away.
**Files**: `src/state/GocContext.jsx` (`loadPulse`, `openPulseViewer`, `closePulseViewer`, the shared `popstate` listener), `src/screens/sheets/PulseViewer.jsx`; iOS: `AppState.swift` (loading/seq state), `AppState+Pulse.swift` (`loadPulse`, `openPulseViewer`), `PulseViewerView.swift` (drag gesture, loading state).

### C — floating pill replaced with a dock-adjacent "+" 
`src/screens/CreateEventFab.jsx`/`apps/ios/BanbeApp/Views/CreateEventFabView.swift` are **deleted**. Replacement:
- Web: `src/screens/DockCreateButton.jsx` — a 46px circular "+" positioned at the dock's own vertical band (reuses `BAR_HEIGHT`/`BAR_BOTTOM_OFFSET`, now exported from `BottomTabBar.jsx`), only rendered where `showsBottomBar(screen)` is true AND `organizerMode` is on. Tapping it opens a small anchored menu (one item: "Tạo sự kiện") with an invisible full-screen backdrop for outside-tap-to-close; `Escape`/back-navigation isn't separately wired since this is a plain absolutely-positioned overlay, not a screen.
- iOS: `apps/ios/BanbeApp/Views/DockCreateButtonView.swift` — deliberately a child of `BottomTabBarOverlayRoot` (the SAME separate always-on-top `UIWindow` `BottomTabBar` itself lives in), not a new competing window, per this ticket's own explicit instruction. This means it inherits `BottomTabBarOverlay`'s entire existing show/hide lifecycle (`forcedHidden`/`storyViewerOpen`/`pulseViewerOpen`/`modalActionSheetPresented`, `BottomTabBar.visibleScreens`) for free — it structurally cannot render above a full-screen sheet/story/Pulse, because the whole window it lives in already hides itself for exactly those cases. Confirmed (by reading `BottomTabBarOverlay.attach()`, not assumed) that the window's band width (444pt) already exceeds every current iPhone's screen width, so it's already clamped to full-device-width — there was room for this button beside the dock without widening that carefully-tuned hit-test band at all.
**Files**: `src/screens/DockCreateButton.jsx` (new), `src/screens/BottomTabBar.jsx` (exports `BAR_HEIGHT`/`BAR_BOTTOM_OFFSET`), `App.jsx`; iOS: `Views/DockCreateButtonView.swift` (new), `Views/BottomTabBarOverlay.swift` (`BottomTabBarOverlayRoot` now wraps `BottomTabBar()` + `DockCreateButtonView()` in a `ZStack`), `Views/RootView.swift` (old FAB call site removed).

## Files touched (by feature)
- **A**: `src/lib/actionCenter.js` (new), `src/screens/ActionCenter.jsx` (new), `Home.jsx`/`Account.jsx`/`Dashboard.jsx`; iOS: `Lib/ActionCenter.swift` (new), `Views/ActionCenterView.swift` (new), `HomeView.swift`/`AccountView.swift`/`DashboardView.swift`.
- **B**: `src/lib/bookingTicket.js` (new), `Confirmed.jsx`/`EventDetail.jsx`; iOS: `Models/Booking.swift` (`isTicket`), `ConfirmedView.swift`/`EventDetailView.swift`.
- **C**: SUPERSEDED 2026-10-03 — see the dated fix-pass section above for the current files (`DockCreateButton.jsx`/`DockCreateButtonView.swift`, not the ones originally listed here).
- **D**: migration 079; `src/screens/EditProfile.jsx`/`PublicProfile.jsx` (new), `src/lib/profileTheme.js`/`appStore.js` (new), `Account.jsx`, `GocContext.jsx`, `App.jsx`, `public/.well-known/apple-app-site-association` (new), `vercel.json`; iOS: `Models/Profile.swift`, `State/AppState+Profile.swift` (new), `Views/EditProfileView.swift`/`PublicProfileView.swift` (new), `AccountView.swift`, `RootView.swift`, `App/BanbeApp.swift`, both `.entitlements` files.
- **E**: migration 080; `src/screens/sheets/PulseViewer.jsx` (new), `Home.jsx`, `GocContext.jsx`, `App.jsx`; iOS: `State/AppState+Pulse.swift` (new), `Views/PulseViewerView.swift` (new), `HomeView.swift`, `RootView.swift`, `Views/BottomTabBarOverlay.swift`.
- **Screenshot catalog**: `apps/ios/BanbeAppUITests/ScreenshotCatalogTests.swift`'s new `testGroupI_UXFoundation()` (group `09-ux-foundation`) — captures all 5 features' key screens, opportunistic/`skip()`s wherever the shared test account's real data doesn't currently satisfy a precondition, exactly like every other group in this file. Compiled via `xcodebuild build-for-testing` (not run — this session never runs simulator/device tests).

## Copy conventions added here
"Việc cần xử lý" (Action Center title) / "Xem tất cả" / "Đang giữ chỗ" + "Xem trạng thái thanh toán" (held-booking, not-yet-a-ticket) / "Tạo sự kiện" (FAB) / "Hồ sơ của bạn" (not literally used as a screen title — EditProfile uses "Chỉnh sửa hồ sơ", the public one has no title at all, just the card) / "Chia sẻ" / "Hiển thị mã QR" / "Banbe Pulse" / "Hôm nay" / "Tuần này".

## Fix pass (2026-10-05) — real-iPhone dock overlap, organizer-mode robustness, Pulse edge-swipe + ring shimmer

Base commit: `72b3a85`. Three real-device regressions reported against the previous fix pass's own changes.

### 1 — dock "+" overlapped the dock, menu was an oversized banner
Root cause: the dock (`BottomTabBar`, max width 380/400) and the create "+" button each self-positioned independently (`BottomTabBar` centered via its own `left:50%`/width math, the button pinned at a fixed trailing offset) — on a ~390pt iPhone that left well under the button's own diameter of real clearance between them. Fixed by making them ONE laid-out row instead of two independently-positioned floating shapes:
- **iOS**: new `DockRow` (`BottomTabBar.swift`) — an `HStack` of `BottomTabBar()` + `DockCreateButtonView()` sharing one `dockMargin`/`dockGap`, replacing the old `ZStack` composition in `BottomTabBarOverlayRoot`. `BottomTabBar.barWidth` reduced 380→300 (an upper bound now, not a fixed width — its own items were already `.frame(maxWidth: .infinity)`, so the whole bar shrinks fluidly under `DockRow`'s own available-width math instead of clipping). The create button's own size (`createButtonSize`) now equals `barHeight` exactly, so "shared vertical center" is structural (same height, `HStack`'s own `alignment: .center`), not two independently-tuned paddings.
- **Web**: new `DockRow` component (`App.jsx`) doing the equivalent `flex` row; `BottomTabBar.jsx`'s outer div stopped self-positioning (`position: relative`, `flex: 1 1 auto`, `minWidth: 0`, `maxWidth: DOCK_MAX_WIDTH` — reduced from 400→300) and its per-tab items changed from a fixed `width: 60` to `flex: 1 1 0` so they compress instead of overflowing on a narrow row. `DockCreateButton.jsx`'s button itself is now a plain flex child (`flex: 0 0 auto`, size `CREATE_SIZE === BAR_HEIGHT`), no longer `right: 16`-positioned.
- **The old anchored popover menu is gone**, replaced by a real bottom tray that rises just above the dock (not the anchored, content-hugging popover that used to render as a giant single-row banner because its own `minWidth: 176` fought a design meant for a small icon+label row). iOS: `DockCreateTrayView.swift` (new), presented from `RootView`'s own main-window ZStack (not the dock's band-sized overlay window — a tray needs to dim the real screen and rise well above that small band, which the overlay window structurally cannot do), driven by a shared `AppState.dockCreateTrayOpen` bool the button (in the OTHER window) also reads/writes. Web: `DockCreateButton.jsx`'s own tray + scrim, `position: fixed`, `Escape` key + outside-tap + downward-pointer-drag to dismiss.
- Tray auto-closes whenever the dock itself would hide (`BottomTabBarOverlay.applyVisibility()`'s hide branch now also clears `dockCreateTrayOpen` — covers every "hide/reconcile on other sheets, Pulse, story viewer, QR, auth screens" case in ONE place instead of duplicating the check at each call site).

### 2 — organizer-mode-off still failing with "Vui lòng thử lại" on a real device
Traced `set_organizer_mode()` (migration 017, unchanged) end-to-end: the RPC's own logic is symmetric between enable/disable (same `UPDATE profiles SET role = …` path, same `guard_profile_role` trigger, same `app.role_change_allowed` transaction-local `set_config`) — nothing in the function itself favors one direction. **Could not reproduce the failure in this environment** (no device access), so the exact server-side error code/message from the report is unverified — reporting that honestly rather than guessing a specific cause.
What WAS proven by reading the client code, and fixed:
- **iOS never logged anything on failure** — the `catch` block in `applyOrganizerMode` (`AppState+Data.swift`) had no diagnostic output at all, unlike web's `console.warn`. On a real device there was no way to ever see WHICH failure a real occurrence was. Now logs the `PostgrestError`'s own `code`/`message` (dev builds only, same fields `AppState+Payments.swift`'s `describeProofUploadError` already treats as safe to print — never the session token itself). Web's own `console.warn` similarly upgraded from the error object's default string form to its structured `code`/`message`/`details`/`hint`.
- **Neither platform guarded against a double-tap/double-click firing two overlapping RPC calls** — both would read the same stale `organizerMode` before the first call's optimistic flip had re-rendered, sending the identical `p_enabled` twice; whichever response landed second could stomp the first's already-successful result with its own rollback. Added `organizerModeBusy` (web: `GocContext.jsx` state; iOS: `AppState.organizerModeBusy`), checked in both `toggleOrganizerMode` and `applyOrganizerMode`, and mirrored onto the switch's own `.disabled`/`opacity` so a second tap while one is in flight visibly does nothing.
- **A stale/expired access token** (PostgREST's `PGRST301`, or a plain `401`) is the one server-adjacent cause a symmetric RPC + a real device plausibly explains — background the app for a while, come back, the JWT's expired, the RPC 401s. Both platforms now branch on that specific code to show an actionable "your session expired, sign in again" message instead of the generic one; every other code still gets the generic string, since this RPC has never been observed to raise anything else — a more specific claim there would be a guess, not a proven cause.
- Explicitly did NOT touch `set_organizer_mode()`, `guard_profile_role`, or any RLS/grant — nothing in this investigation implicated the server function itself, and the ticket's own instruction is not to loosen RLS to make the switch "work."
**Files**: `src/state/GocContext.jsx` (`applyOrganizerMode`, `toggleOrganizerMode`, `organizerModeBusy` state), `src/screens/Account.jsx` (disabled/opacity while busy); iOS: `State/AppState.swift` (`organizerModeBusy`), `State/AppState+Data.swift` (busy guard, dev logging, session-expired branch), `Views/AccountView.swift` (disabled/opacity while busy).

### 3 — Pulse: real edge swipe-back + shimmering ring
- **iOS**: added a genuine leading-edge swipe-to-dismiss to `PulseViewerView` — same affordance as `RootView`'s own `edgeSwipe` (which a `.fullScreenCover` doesn't inherit, since it's a separate presentation outside `RootView`'s ZStack), confined to a thin 20pt leading strip via `.highPriorityGesture` so it never arbitrates against the `ScrollView`'s own vertical pan, tab switches, photo taps, or the organizer sheet. Live-follows the finger (`@GestureState edgeDragOffset`), commits past 30% of screen width or a fast flick, otherwise springs back. The existing header-only downward drag (previous fix pass) is untouched — both gestures compose (`.offset(x:,y:)`), X close button stays as the explicit fallback either way.
- **Web**: no edge-swipe added — Pulse already closes via the browser back button (previous fix pass's `popstate` wiring), which IS the web equivalent of an edge-swipe-back; adding a synthetic touch-edge gesture on top would duplicate that affordance for no real benefit and risks fighting native browser back-swipe on mobile Safari.
- **Ring shimmer**: replaced the static two-tone gradient + plain "✦" with a slow `hue-rotate` cycle (iOS: SwiftUI `.hueRotation` on an `AngularGradient`; web: a CSS `@keyframes` hue-rotate filter) over the SAME dusty-rose/sage palette the old gradient used, plus one warm-sand stop in the same muted family — never a saturated rainbow. One continuous animation, not a per-frame redraw loop. Both honor reduced motion (iOS: `accessibilityReduceMotion` environment value gates whether the animation ever starts; web: `@media (prefers-reduced-motion: reduce)` disables the CSS animation) — the resting gradient frame, un-animated, is the "beautiful static state" either way. iOS additionally pauses via `scenePhase` while backgrounded; both platforms stop entirely the instant Home isn't the visible screen, since the ring only exists inside `HomeView`/`Home.jsx`, which unmount on navigation.
**Files**: iOS: `Views/PulseViewerView.swift` (edge-swipe gesture), `Views/HomeView.swift` (`PulseRingGlyph`, new); web: `src/screens/Home.jsx` (shimmer gradient + `<style>` keyframes).

### Not done / explicitly out of scope this pass
- No new automated test was added for the organizer-toggle busy-guard, dock geometry, or Pulse gesture — this repo still has no unit-test harness for this client-side logic (same gap the previous fix pass documented), and an E2E run against the shared live test account risked mutating shared account state (organizer mode is a real per-account toggle), which the ticket's own "do not alter test/production user data" constraint rules out. Verified instead via `xcodebuild` (Debug + PersonalTeamDebug + UI-test-target compile) and `vite build`, all green — no simulator/device interaction.
- The real server-side cause of the original "Vui lòng thử lại" report on organizer-off is still unconfirmed — see section 2 above. If it recurs, the new dev-console logging (both platforms) is what will finally surface the actual `PostgrestError` code/message next time.

## Fix pass (2026-10-06) — dock "+" visual/scale mismatch, organizer-mode profile-reload race

Base commit: `e21f6bf`. Two more real-iPhone reports against the 2026-10-05 pass above.

### 1 — dock "+" was a solid black circle that didn't scale with the dock
Both were genuine style/animation divergences, not a geometry bug this time:
- **Material**: `DockCreateButtonView`/`DockCreateButton.jsx` painted the button as a SOLID `ink`-filled circle with its own independently-chosen shadow — a different recipe from the dock's own translucent `.thinMaterial`/`barGlass()` capsule, not the same material reused. Now both reuse the dock's own background/stroke/shadow verbatim (iOS: `.thinMaterial` in a `Circle`, same stroke opacity, same shadow constants; web: `barGlass({})` on the button's own div), with the "+" glyph switched from white-on-ink to plain ink (a translucent material needs an ink glyph for contrast, same as every dock tab icon).
- **Scale sync**: the shrink-on-scroll `.scaleEffect`/`transform: scale()` lived on `BottomTabBar`'s own body/div alone — since `DockRow` lays the dock and the "+" out as HStack/flex SIBLINGS, scaling only one child meant the dock visibly resized on scroll while the "+" stayed full size beside it. Moved to `DockRow` itself (both platforms), so one transform scales the whole row as a unit.
**Files**: iOS `Views/BottomTabBar.swift` (`DockRow`'s own `.scaleEffect`, moved from `BottomTabBar`'s body), `Views/DockCreateButtonView.swift` (material/shadow); web `src/App.jsx` (`DockRow`'s own `transform`, moved from `BottomTabBar.jsx`), `src/screens/BottomTabBar.jsx`, `src/screens/DockCreateButton.jsx` (material/shadow via `barGlass()`).

### 2 — organizer-mode-off: proven defect fixed, exact server-side cause still unconfirmed
`set_organizer_mode()` itself was re-verified unchanged and symmetric (see the 2026-10-05 section above) — not touched again.
**What WAS found and fixed, by reading the full pipeline**: `syncUser()` (web) and `applySession()` (iOS) both unconditionally overwrite `organizerMode`/`accountType`/`mode` from a fresh `profiles.role` read, with no coordination against an in-flight `applyOrganizerMode()` call. On web this is concretely reachable: `supabase.auth.onAuthStateChange` reliably refires on a background token refresh and — far more readily on mobile Safari/WKWebView than desktop dev, which is consistent with this only reproducing on a real iPhone — on tab/app visibility regain, re-running `syncUser()`. If that refetch's `SELECT` starts before the toggle's own RPC `UPDATE` has committed, it legitimately reads the pre-toggle role, and its own `set()` — landing after the toggle's optimistic update — silently reverts the switch with no error of its own (matching "switch stays on", with the toggle's own error text showing alongside it if the RPC itself also failed for an unrelated reason). Fixed on both platforms: `syncUser`/`applySession` now skip the three role-derived fields entirely while `organizerModeBusy` is true (web via a ref, since `syncUser` closes over stale state otherwise — same pattern `storyViewedIdsRef` already established in this file for an identical out-of-order-refetch bug class).
**What is still unconfirmed**: whether `set_organizer_mode(false)` itself ever actually errors on a real device (vs. this profile-reload race alone explaining the report). I do not have real-device console access, so I could not capture the actual PostgREST code/message this ticket asks for. Added instead: full dev-only request/response logging on both platforms (auth-session presence + expiry, RPC name/params, the RPC's own returned business string, and a log line whenever `syncUser`/`applySession` skip the role fields because of the guard above) — **the missing diagnostic is the real device's own console output the next time this reproduces**; nothing here should be read as a confirmed server-side fix.
**Files**: web `src/state/GocContext.jsx` (`organizerModeBusyRef`, `syncUser`'s guarded `roleFields`, request/response `console.info`); iOS `State/AppState+Data.swift` (`applySession`'s guarded role assignment, request/response `print`, `#if DEBUG`-gated).

## Fix pass (2026-10-07) — "Publishing changes from within view updates" warning storm, dock width

Base commit: `f8ff907`. Two more real-iPhone reports.

### 1 — one tap on the organizer switch produced many SwiftUI publishing warnings (iOS only)
Traced the exact call chain: `AccountView`'s switch `Button` calls `app.toggleOrganizerMode()` synchronously, which spawns `Task { await applyOrganizerMode(target) }`. An unstructured `Task` created from inside a SwiftUI action closure is not guaranteed to start on a fresh run-loop turn — its body can begin running before the CURRENT view-update transaction (the one the button tap itself is part of) has finished committing. `applyOrganizerMode`'s first several lines mutated FIVE `@Published` properties (`organizerModeBusy`, `organizerMode`, `accountType`, `mode`, `organizerModeError`) with no `await` before any of them — five writes landing inside that still-open transaction, five copies of the warning from one tap. Root cause confirmed by reading the call chain, not reproduced (this session has no simulator/device run).
Fix: split the re-entrancy guard from the UI-facing flag. A new plain (non-`@Published`) `organizerModeInFlight` on `AppState` is checked-and-set synchronously, before any `await`, preserving the exact same one-call-at-a-time guarantee `organizerModeBusy` used to provide alone — but since it isn't `@Published`, setting it publishes nothing. Only AFTER an explicit `await Task.yield()` (a genuine cooperative-scheduling suspension point, not an arbitrary delay/sleep) does the function touch any `@Published` property — guaranteeing every one of those five writes lands on its own, later run-loop turn, unambiguously outside whatever transaction the triggering tap was part of. One tap is still exactly one RPC call and one state transition; nothing about the actual toggle behavior changed, only when its state writes are allowed to happen.
Web has no equivalent of this specific warning (Combine/SwiftUI-only diagnostic), so no change was needed there.
**Files**: `State/AppState.swift` (`organizerModeInFlight`), `State/AppState+Data.swift` (`applyOrganizerMode`'s guard/yield ordering, `toggleOrganizerMode`'s pre-check).

### 2 — dock felt cramped once the material/scale fix (2026-10-06) made it read as one group
Bumped `barWidth`/`DOCK_MAX_WIDTH` from 300 → 340 on both platforms — still well short of the original 380/400 that caused the overlap two passes ago, and still a genuine upper bound the row's own flexbox shrinks below on a narrow screen, not a fixed width. No other geometry/window changes: the dock and "+" still share one `UIWindow`/DOM row, one material, one scale transform (2026-10-06 fix, untouched here); no new floating FAB, no second window. Each tab item already uses an equal flexible width (`.frame(maxWidth: .infinity)` / `flex: '1 1 0'`), so the extra 40pt spreads evenly across all five without any new distribution logic, and stays comfortably above a 44pt touch target at every screen size this shrinks to.
**Files**: `Views/BottomTabBar.swift` (`barWidth`), `src/screens/BottomTabBar.jsx` (`DOCK_MAX_WIDTH`).

## Fix pass (2026-10-08) — organizer toggle-off flip-back, Account scroll jerk

Base commit: `3c3726a`. Confirmed root cause of the flip-back — a real regression the 2026-10-07 warning fix introduced.

### Flip-back — confirmed cause
`applySession()` (iOS) / `syncUser()` (web) both guard against overwriting `organizerMode` mid-toggle by checking a "busy" flag — but that flag was the `@Published organizerModeBusy` (iOS) / its ref mirror (web), and the 2026-10-07 pass deliberately delayed SETTING that flag until after `await Task.yield()`/a render+effect cycle, to stop a SwiftUI publishing warning. That opened a real window — between a tap being accepted and the flag actually flipping true — where a session/profile refetch already in flight (a token refresh, `onAuthStateChange` refiring — far more frequent on mobile) could read `profiles.role` from before the toggle's own RPC had committed, then write it back, undoing the toggle a moment later with no error of its own. **Confirmed by reading the guard's exact timing, not reproduced on-device.**
Fix: the atomic guard is now a separate value, set SYNCHRONOUSLY at the instant a toggle is accepted, before any suspension — `organizerModeInFlight` (iOS, already existed for the warning fix, now ALSO checked by `applySession`) and `organizerModeBusyRef` (web, now set directly inside `applyOrganizerMode` itself, not solely via the `useEffect` mirroring `state.organizerModeBusy` a render late). This covers the ENTIRE call, start to finish — not just the RPC await — closing the window regardless of what races it.
Added a distinct `[organizerMode] WRITE source=... old=... new=...` log at every site that can assign `organizerMode` (optimistic set, RPC success, RPC rollback, `applySession`/`syncUser`'s own resync) on both platforms, plus the RPC's own returned role logged separately from any later state — so the next occurrence (if the true cause turns out to be something else entirely) is fully traceable instead of inferred.
Duplicate-submission guard (item 4): the same synchronous lock (`organizerModeInFlight` / `organizerModeBusyRef`) already makes a second overlapping call from one tap a no-op, checked before any state mutation on both platforms.

### Scroll jerk — cause
A direct consequence of the flip-back: `organizerMode` changing TWICE in quick succession (false, then back to true) meant `AccountView`'s `organizerMode`-gated `LazyVStack` sections (post-story menu, host-management list) inserted/removed TWICE with no animation of their own, snapping the layout each time. Fixing the flip-back removes the second reflow entirely. Additionally wrapped every `organizerMode`/`accountType`/`mode` write in `applyOrganizerMode` (iOS) in `withAnimation` — the same "animate at the mutation site" convention `BottomTabBarOverlay`'s `dockVisible`/`bottomBarCollapsed` already use, not a new mechanism — so `ScreenScaffold`'s existing `scrollPositionID` anchor (`$app.accountScrollAnchorID`, already wired on `AccountView`) tracks even a single, correct transition smoothly instead of snapping. No web change for this specifically — Account.jsx has no equivalent scroll-anchor mechanism to begin with, and the report was iPhone-specific.
**Files**: iOS `State/AppState.swift` (no new fields — `organizerModeInFlight` reused), `State/AppState+Data.swift` (`applySession`'s guard now checks `organizerModeInFlight`, `applyOrganizerMode`'s writes wrapped in `withAnimation` + logged, `import SwiftUI` added for `withAnimation`); web `src/state/GocContext.jsx` (`organizerModeBusyRef` set synchronously inside `applyOrganizerMode`/`toggleOrganizerMode`, write-site logging in `syncUser`/`applyOrganizerMode`).

## Fix pass (2026-09-25) — organizer toggle-off error re-investigated (unreproducible), dock indicator misalignment fixed

Base commit: `8c0ca0e`. Two more reports against the previous pass.

### 1 — "Không thể đổi chế độ tổ chức lúc này" — CONFIRMED root cause, migration written, not yet pushed
**Resolved, via the real browser console log the user captured** (this session still has no simulator/device access, and creating a throwaway test account to repro live is blocked by the exact bug below). The actual PostgREST error, never guessed:
```
code: '23502', message: 'null value in column "handle" of relation "profiles" violates not-null constraint'
```
Root cause: migration `079_public_profile_card_and_avatars.sql` added `profiles.handle` as `NOT NULL` and backfilled every row that existed AT THAT TIME, but never updated `handle_new_user()` (last redefined by migration `040_admin_rbac.sql`) to actually set `handle` on INSERT. Two confirmed symptoms of the same one bug:
- Brand-new signups fail outright (the INSERT itself violates the constraint, the trigger raises, the whole `auth.users` insert rolls back — this is the "Database error creating new user" this session hit trying to create a throwaway test account, originally logged as a seemingly-unrelated aside).
- At least one already-existing account (`8a4eb34e-aeb8-48cb-a7ea-a9e3239491a8`) has a `profiles` row with `handle IS NULL` anyway — created through some path that produced a row without going through 079's one-time backfill. **Postgres re-validates NOT NULL against the entire row on ANY `UPDATE`, not just columns actually being written** — so every subsequent update to that one row started failing, including `set_organizer_mode()`'s own `UPDATE profiles SET role = ...`. That's the exact, full mechanism of this report: nothing wrong with `set_organizer_mode()`, `guard_profile_role`, RLS, or either platform's client code (all re-verified symmetric and correct, again, this pass) — this one account's row was simply unwritable at all, for any reason, the whole time.
**Fix, part 1 (applied)**: `supabase/migrations/20260930000081_081_fix_handle_new_user_missing_handle.sql` — re-ran 079's own backfill formula (`'u' || replace(id::text,'-','')`, trimmed to 13 chars) for any row still `handle IS NULL`, and redefined `handle_new_user()` to set `handle` with that same formula on INSERT. Confirmed via direct service-role read after push: the affected account's row now has `handle: 'u8a4eb34eaeb8'`, and a direct `role` UPDATE on it (service role) succeeds cleanly, where it used to throw the exact `23502` error.
**Reported as still broken after part 1 — because it was.** A fresh console capture from the user, post-081, showed the identical `23502 null value in column "handle"` error, on the SAME account, even though that account's row was now provably fine. That ruled out "081 didn't take effect" and pointed at a SECOND, independent place doing the same kind of insert.
**Fix, part 2 (applied)**: found it — `set_organizer_mode()` itself (migration `017_auth_lookup_and_organizer_mode_repair.sql`) has its own defensive `INSERT INTO profiles (...) ON CONFLICT (id) DO NOTHING` (a belt-and-suspenders guard for "this account's row doesn't exist yet"), added back when `PROFILE_NOT_FOUND` used to be a real failure mode — and it ALSO never listed `handle`. **Postgres validates NOT NULL while building the INSERT's proposed tuple, which happens BEFORE the `ON CONFLICT` clause is evaluated** — so this one redundant, defensive INSERT threw the exact same `23502` on *every single call* to `set_organizer_mode()`, for *every* account, completely independent of whatever `handle` value was already sitting in the table. That's the full, now-confirmed mechanism of the whole report. `supabase/migrations/20260930000082_082_fix_set_organizer_mode_missing_handle.sql` redefines the function with `handle` added to that INSERT, same formula as part 1. Applied via `supabase db push`, confirmed in `supabase migration list` as both local and remote.
**No client-code changes needed on either platform, still** — the toggle logic itself was correct the entire time; this was purely two independent instances of the same DB-side oversight (079 adding a NOT NULL column without auditing every existing `INSERT INTO profiles` for it).
**Lesson for next time a NOT NULL column is added to a hot table**: grep the ENTIRE migrations directory for every `INSERT INTO <table>` (not just the obvious signup trigger) before assuming one fix covers it — a defensive `ON CONFLICT DO NOTHING` insert deep inside an unrelated RPC is exactly the kind of second site that's easy to miss and, as here, fails with an identical-looking error that makes the first fix look like it silently didn't work.

<details><summary>Original (incomplete) investigation from this same pass, superseded by the above — kept for the trail</summary>

**Could not reproduce.** No simulator/device access this session (per this repo's own convention). Attempted a live repro instead: called `set_organizer_mode` directly against the real deployed Supabase project (service-role key from `.env.local`, anon-key client mirroring the app's own auth path — same pattern `tests/e2e/setup.mjs` already uses), turning a throwaway account's organizer mode on then off. Blocked before it could run: `admin.auth.admin.createUser()` itself now fails with a real, reproducible `"Database error creating new user"` (HTTP 500) — **unrelated root cause found while investigating**: migration `079_public_profile_card_and_avatars.sql` added `profiles.handle` as `NOT NULL` with no default, but `handle_new_user()` (last redefined by migration `040_admin_rbac.sql`, the version that actually wins) never sets `handle` on INSERT — every brand-new signup on this project is currently failing at the trigger. This is real and worth its own fix, but it cannot explain the toggle-OFF report (it only affects account *creation*, and the report is about an existing, presumably already-organizer account), so left untouched per this ticket's own file scope — flagging here instead of fixing blind.
Re-read the full pipeline end to end anyway (`toggleOrganizerMode` → `applyOrganizerMode` → `set_organizer_mode()` RPC → `guard_profile_role` trigger, both platforms): confirmed only ONE call site can ever fire a toggle-OFF (`AccountView.swift`'s switch `Button`/`Account.jsx`'s equivalent — the OTHER `toggleOrganizerMode()` call site, the "Bắt đầu tổ chức" onboarding CTA, is inside the `!canHost` branch and can only ever fire an ON), the synchronous `organizerModeInFlight`/`organizerModeBusyRef` guards from the 2026-10-08 pass still hold (no double-fire), and the RPC itself is unchanged and symmetric between enable/disable — nothing found that would make OFF fail while ON succeeds. **This is genuinely still an open question** — the dev-console `[organizerMode]` log trail (request/response/WRITE lines, added across the 2026-10-06/07/08 passes) is what will finally show the real code/message the next time this reproduces on a device; nothing in this pass should be read as a fix for it.

</details>

### 2 — dock active-tab indicator misaligned after the 340pt width bump
**Real client bug, found and fixed — web only** (iOS was already correct, see below).
`src/screens/BottomTabBar.jsx`'s scrub-highlight had two independent defects, both pre-existing (not introduced by the 340pt bump itself — that change just made the resulting pixel error bigger and therefore visible):
1. `measure()` (the `rectsRef` pixel-rect cache the highlight used to be drawn from) only ever re-ran on mount and on a `window` `resize` event. It never re-ran when the BAR's own width changed for any other reason — concretely, `DockRow` (`App.jsx`) toggling its create-"+" button on/off `state.organizerMode`, which changes this bar's own flex width with no `resize` event at all. Any such reflow left the highlight drawn from stale, wrong rects.
2. Even with fresh rects, `getBoundingClientRect()` returns POST-transform (screen) coordinates. `DockRow`'s collapse/expand `scale()` sits on an ANCESTOR of the bar — so the measured `rect.left`/`rect.width` already had that scale baked in, and reapplying them as the highlight's OWN `transform`/`width` double-applied it (`scale(0.86)` on the ancestor became an effective 0.86² on the highlight alone), drifting the indicator specifically while the dock was collapsed/expanding.
**Fix**: dropped pixel measurement for the highlight's placement entirely. Every tab is an equal `flex: '1 1 0'` slice of the bar with zero gap, so item `i`'s box is exactly its `i`-th `1/items.length` share — now expressed as CSS percentages (`width: ${100/count}%`, `translateX(${index*100}%)`), which resolve against the element's own local, pre-transform layout box. That's immune to both problems: no measured rect involved at all (immune to staleness), and resolved before any ancestor `scale()` is applied (immune to double-scaling). `measure()`/`rectsRef` are kept only for `hitTest` (the scrub-drag's touch→tab mapping, which genuinely needs live screen-space rects) — and upgraded from a `window`-resize-only listener to a `ResizeObserver` on the bar element itself, so that cache also stays fresh across the same `organizerMode`-driven reflow instead of only the visible highlight being fixed.
**iOS needed no change**: `BottomTabBar.swift`'s highlight already uses SwiftUI's `Anchor<CGRect>`/`GeometryProxy` system, which resolves against the pre-transform layout tree and updates via `.onChange(of: proxy.size)` whenever the bar's actual laid-out size changes (including `DockRow`'s `if app.organizerMode { DockCreateButtonView() }` reflow) — structurally immune to both bugs above; verified by reading, not assumed.
**Files**: `src/screens/BottomTabBar.jsx` (`measure()`'s `ResizeObserver`, `placeHighlight`'s percentage-based rewrite). No iOS changes.
**Validated**: `vite build` (web) and `xcodebuild … -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator build` (iOS, unchanged — build-only sanity check since no Swift file was touched), both green. No simulator/device interaction this session.

## Fix pass (2026-09-25, second) — iOS dock indicator (real fix this time), Pulse photo-ranking tab

## Fix pass (2026-10-02, second) — compact iOS Pulse expanded panels

iOS only: `PulseViewerView.swift` now uses one compact centered panel for all
three Pulse tabs. Width is 80% of the actual container with a 520pt cap; the
photo height is derived from the oriented cached image aspect ratio and capped
by available geometry, so landscape panels are shorter and portrait/square
photos remain aspect-fit without filler bands. The panel reuses one
`PhotoLoader` request for both the sharp inset image and the soft panel tint.

Each event/photo row publishes its stable-ID frame in the same named Pulse
overlay coordinate space. Opening records that frame, applies a brief press
compression, emits one light haptic, and springs only the panel/photo from the
source while the scrim fades separately. Close uses the same source when the
frame is valid and falls back to a fade under Reduce Motion or missing bounds.
iOS 26+ uses the existing `glassEffect`/`GlassEffectContainer` pattern; older
systems and Reduce Transparency use the existing material fallback. Existing
close, outside-dismiss, engagement, follow, and navigation actions are kept.

Validated with `xcodebuild -scheme PersonalTeamDebug -configuration
PersonalTeamDebug -sdk iphonesimulator ... build CODE_SIGNING_ALLOWED=NO`.
No simulator or physical-device UI verification was performed.

Follow-up: the first compact renderer let its `ScrollView` accept the full
overlay height, producing an oversized empty lower glass area on portrait
photos. The panel now hugs intrinsic content height and only caps for genuine
Dynamic Type/content overflow.

Second follow-up: the scroll container could still receive a tall viewport
proposal and center short content inside it. It now measures the rendered
image/text/actions content and uses that height directly, with the viewport
cap applied only when the measured content actually overflows.

Third follow-up: the expanded image now applies its rounded mask after the
source-transition scale, with a subtle edge stroke, so portrait photos keep
rounded corners throughout the opening animation as well as at rest.

Fourth follow-up: the photo frame now uses a stronger 28pt clip and matching
stroke on the actual image bounds, making its own rounded edge visibly distinct
from the larger glass-panel radius.

Fifth follow-up: the shared blurred backdrop was visually filling the clipped
photo corners with the same image colors. Its opacity is now muted and a light
panel separation layer is added, preserving reuse without hiding the real
photo-edge radius.

Sixth follow-up: the aspect-fit image previously clipped a wider layout frame
when its height was capped. The frame now uses the exact displayed width and
height derived from the oriented image aspect ratio, so the rounded clip and
stroke sit directly on the real photo pixels.

### iOS dock indicator — actually fixed
The 2026-09-25 pass above only fixed WEB; iOS was assumed fine (Anchor/GeometryReader-based) but the user confirmed the same misalignment on-device. Root cause: `itemFrames` (used for the highlight's `.position`/`.frame(width:)`) is refreshed by a SEPARATE `backgroundPreferenceValue` GeometryReader's own `.onAppear`/`.onChange(of: proxy.size)` — a real caching layer, one layout pass removed from this view's own render, that can lag a genuine reflow (organizerMode's "+" button, DockRow's collapse `scaleEffect`). Fixed: `BottomTabBar.swift`'s highlight is now computed directly from a `GeometryReader` wrapping the whole body, as `geo.size.width * (index/count)` — a live fraction of the actual current render size, same "equal-flex slice of the live container" idea as the web CSS-percentage fix, ported to SwiftUI instead of reusing `itemFrames`. `itemFrames`/`resolveFrames` kept only for the scrub-drag `hitTest` (needs real touch-space rects; `DragGesture(.local)` was never affected by the ancestor-scale bug class).
**Files**: `apps/ios/BanbeApp/Views/BottomTabBar.swift` (`activeIndex`, `GeometryReader`-wrapped body, highlight geometry).

### Banbe Pulse — third tab: ranked event photos (likes + shares)
New migration `083_pulse_photo_ranking.sql`: `photo_likes`/`photo_shares` tables (RLS: own-row only for likes, zero direct grants for shares — writes only via `log_photo_share()`), `toggle_photo_like(p_event_photo_id)` (server-checked, one-per-user via UNIQUE), `log_photo_share(p_event_photo_id, p_channel)` (called only on real share completion, never on opening a share sheet), `get_pulse_photo_ranked(p_period)` (likes capped 20×3 + shares capped 10×4, same live/public eligibility as `goc_pulse_ranked`, own separate ranking — no shared signals with the event-level one). `/api/photo-share.js` extended (not duplicated) to also resolve a real `event_photos` row via `?pid=<uuid>`, alongside its existing static-demo-gallery `?photo=&org=&by=` path.
Web: `PulseViewer.jsx` (third "Ảnh nổi bật" tab, photo cards with like/share counts, popup sheet with real like toggle + share + "view event"), `GocContext.jsx` (`loadPulsePhotos`, `openPulsePhotoSheet`/`closePulsePhotoSheet`, `togglePulsePhotoLike` optimistic w/ rollback, `sharePulsePhoto` logging only on `navigator.share()`/clipboard success).
iOS: `AppState+Pulse.swift` (`PulsePhotoItem`, `PulseTab.photos`, `loadPulsePhotos`, `togglePulsePhotoLike`, `logPulsePhotoShare`), `AppState.swift` (new `@Published` fields), `PulseViewerView.swift` (third tab button, `pulsePhotoCard`, `photoSheet`, `sharePulsePhoto` — a NEW `UIActivityViewController` helper with a real `completionWithItemsHandler`, deliberately not reusing `PhotoViewerView`'s existing share helper, which logs at presentation time not completion).
Local-only `s.photoLikes`/`togglePhotoLike` (localStorage, static demo gallery) left untouched — zero overlap with real `event_photos`, per the 2026-10-03 trace already on file.
**Files**: `supabase/migrations/20260930000083_083_pulse_photo_ranking.sql` (new), `api/photo-share.js`, `src/screens/sheets/PulseViewer.jsx`, `src/state/GocContext.jsx`; iOS `State/AppState+Pulse.swift`, `State/AppState.swift`, `Views/PulseViewerView.swift`.
**Validated**: `vite build` and `xcodebuild … PersonalTeamDebug … build`, both green. Migration applied via `supabase db push`, confirmed in `migration list` and a live anon-key RPC call (`get_pulse_photo_ranked` → `{success:true, items:[]}`, empty since no real engagement rows exist yet). No simulator/device interaction.

## Fix pass (2026-09-30) — dock "+" tray under Map's native sheet, numeric badge propagation, heading Title Case, em/en-dash sweep

Four unrelated tickets bundled into one pass. iOS build verified via `xcodegen generate` + `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**; web via `npx vite build` → clean. No simulator/device UI run this pass (per its own instruction) — anything below marked "unverified on-device" genuinely wasn't.

### 1 — dock "+" tray rendered UNDER MapExplore's native filter/list sheet
Root cause, confirmed by reading, not guessed: `DockCreateTrayView` lived in `RootView.swift`'s own main-window ZStack (old line ~764, `zIndex(28)`) — but `DockCreateButtonView`/the dock itself live in `BottomTabBarOverlay`'s SEPARATE always-on-top `UIWindow` (the one thing in this app already proven, across the whole tab-bar saga documented above, to draw above a native `.sheet()` at any detent). A plain ZStack zIndex can never out-layer a `.sheet()` presented in a different window — exactly the same bug class 80c1ac3 fixed for the dock itself, just never applied to the tray it opens.
**Fix**: moved `DockCreateTrayView` into `BottomTabBarOverlayRoot` (same window as the dock/button), gated on `app.dockCreateMenuOpen` exactly as before. That window is normally sized to a small dock-band (`bandWidth`/`bandHeight`) — too small for a full-bleed scrim/rise-above-the-dock tray — so `BottomTabBarOverlay.setDockCreateTrayOpen(_:)` (new) temporarily grows the window's own `frame` to the full screen bounds (captured once at `attach()`) while the tray is open, and shrinks it back to the band **after** `DockCreateTrayView.closeAnimationDuration` (0.15s, a new `static let` the close animation itself now reads too, so window-resize timing and the SwiftUI exit transition can never drift apart) — mirrors the existing `visibilityToken`/`asyncAfter` pattern `applyVisibility()` already uses for its own show/hide animation. Wired from `RootView`'s `.onChange(of: app.dockCreateMenuOpen)`, the same pattern as `storyViewer`/`pulseOpen`/`modalActionSheetPresented`.
Deliberately did NOT touch `MapExploreView`'s own sheet/camera/filter/search/selected-event/detent state — the fix is entirely a `BottomTabBarOverlay` window-frame resize; nothing in `MapExploreView.swift` was read from or written to.
**Files**: `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift` (`dockCreateTrayOpen`/`trayResizeToken`/`sceneBounds` fields, `bandFrame(in:)`, `setDockCreateTrayOpen(_:)`, `BottomTabBarOverlayRoot.body` now a `ZStack` with the tray as a second child), `apps/ios/BanbeApp/Views/DockCreateTrayView.swift` (`closeAnimationDuration` constant), `apps/ios/BanbeApp/Views/RootView.swift` (tray call site removed from the main ZStack, new `.onChange(of: app.dockCreateMenuOpen)`).
**Unverified on-device**: actual layering above the real Map sheet on a physical iPhone — this environment has no simulator/device access. The fix reuses, unmodified, the exact window-level mechanism already confirmed (by a real XCUITest run, `BottomTabBarUITests.testTabBarButtonWorksWhileMapSheetIsOpen`, see Follow-up 5 above) to draw above that same sheet, so confidence is high, but this specific tray-open-while-sheet-open case was not re-tested with a device/simulator tap.
**Web**: audited `MapExplore.jsx`'s sheet (a plain in-DOM `<div>`, not a native modal, per Follow-up 4's own finding above) against `DockCreateButton.jsx`'s tray/scrim — both are ordinary DOM siblings with explicit z-indices (tray/scrim at a higher `zIndex` than the map sheet's own). No stacking-context bug exists on web; nothing changed there.

### 2 — numeric badges did not propagate through every navigation level
Inventoried existing badge/count sources first (grep, not invented): `pendingEventsCount` (admin moderation queue), `verifications`/`refundQueue` (host duties, both already summed at the `hostOps` group-card level pre-existing this pass), `myOrganizerInvites`/`myEventCredits` (team/activity group cards, pre-existing). 25bd5f5 had already given the "Pending events" ROW parity with its own group card; nothing above the group-card level (tab, dock icon) had a badge at all, and the parallel `hostOps`/"Awaiting verification" row had no parity either.
**New centralized modules** (one per platform, not scattered per-view math): `src/lib/badges.js` (`computeAdminModerationCount`, `computeHostActionCount`, `computeAccountDockBadge`, `formatBadgeCount`) and `apps/ios/BanbeApp/Lib/Badges.swift` (`AccountBadges` enum, same four operations). Both read ONLY already-loaded canonical arrays/counts (`pendingEventsCount`, `verifications.length`/`.count`, `refundQueue.length`/`.count`) — no new "unread" concept, no new polling, no fabricated badge for Home/Map/static settings/the dock "+" itself.
**Dedup rule**: every number is either the length of one distinct array, or the sum of two arrays guaranteed to never share an item (`verifications` and `refundQueue` are different Postgres tables/PKs, and both already legitimately route to the SAME Verifications screen — `onOpenRefundCenter` already pointed there before this pass) — never a sum of two already-aggregated badges.
**Chain implemented** (child row → group card → tab → dock icon), both platforms:
- Admin: "Pending events" row (unchanged) → "Review & Moderation" group card (unchanged) → **Admin tab** (new badge) → **Account dock icon** (new badge).
- Host: **"Awaiting verification" row** (new badge, parity with its own group card) → "Event Operations & Payments" group card (unchanged) → **Host tab** (new badge) → **Account dock icon** (new badge, summed with admin's).
**Permissions/zero/cap**: `computeAdminModerationCount` returns 0 unless `accountType === 'admin'`; `computeHostActionCount` returns 0 unless `organizerMode` is on — both naturally 0 (hidden) post-logout/account-switch since `GocContext`'s/`AppState`'s own sign-out already clears `verifications`/`refundQueue`/`pendingEventsCount`. Account dock badge caps at "99+" (new — was hardcoded `badge: 0` before); Notifications keeps its existing "9+" cap unchanged (`badgeCap` field added to both platforms' tab-item model so the two caps coexist explicitly instead of one hardcoded `9`). Exact count always exposed via `accessibilityLabel`/`aria-label`/`title`, capped digits only in the visible glyph. New `data-testid`/`accessibilityIdentifier`s on every new badge span.
**Read/ack semantics preserved**: nothing here introduces a "clear on view" — every count still only changes when its underlying canonical array changes (verified/rejected, refund destination chosen, etc.), exactly as it already worked for the pre-existing badges this pass extended.
**Geometry**: dock/tab badges are `position: absolute`/`ZStack(alignment: .topTrailing)` overlays on the icon's own fixed-size box — same technique the pre-existing Notifications/Inbox badges already used — so none of this touches the dock's flex/HStack layout, hit-testing band, or the percentage-based scrub-highlight geometry documented in the 2026-09-25 passes above.
**Files**: `src/lib/badges.js` (new), `src/screens/BottomTabBar.jsx`, `src/screens/Account.jsx`, `src/screens/AccountGroup.jsx`; iOS `Lib/Badges.swift` (new), `Views/BottomTabBar.swift`, `Views/AccountView.swift`, `Views/AccountGroupView.swift`.
**Verified**: logic-only checks (Node, ad hoc) confirmed non-admin/non-host → 0, admin-only/host-only/both combinations sum correctly with no double count, and `formatBadgeCount(150) → "99+"`. No device/simulator run to see the actual badge shapes.

### 3 — Title Case pass on app-authored headings (representative, not exhaustive)
Fixed the literal owned strings (not a runtime text-transform, per the ticket's own preference) for: every Account IA screen title/section heading (Billing, Disputes, Payout, RefundAccounts, EditName, Preferences, Security, EditProfile, MyRefunds, AdminEvents, Inbox's title/feedback sheet/settings sheet, Notifications' title/selection header), the six `GROUP_META`/`accountGroupTitle` group labels (including the exact "Sự Kiện Chờ Duyệt"/"Pending Events" and "Duyệt & Kiểm Duyệt"/"Review & Moderation" pair), the three Account top-level tab labels (Cá Nhân/Tổ Chức/Quản Trị), and the dock-tray create menu ("Tạo Sự Kiện"/"Create Event", "Đăng Story"/"Post A Story", "Thư Viện Ảnh"/"Photo Library") on both platforms. Branding/acronym exceptions preserved (banbe, iOS, QR, .ics). User-supplied data (event names, guest names, addresses) and paragraph copy were explicitly left alone.
**Not exhaustive**: this app has hundreds of screens/labels; this pass covers the navigation-heading surface the ticket's own examples pointed at (Account/Admin IA, dock menu) plus a handful of directly-adjacent screen titles, not every string in the codebase. A future pass should grep `display(`/`<h1>`/`<h2>` call sites screen-by-screen for anything missed.
**Files**: too many individual screens to list every line here — see the actual diff; both platforms touched symmetrically for every string changed.

### 4 — em/en dash (—/–) sweep of app-owned copy
Grep-based scan (Python, filtering out source comments) over `src/`, `apps/ios/BanbeApp/`, and `api/`. Found ~50 real hits in owned UI copy/email/Telegram templates (comments — the overwhelming majority of raw hits — were correctly left alone, per the ticket's own instruction).
**Fixed**: rewrote each naturally (colon for "here's what/why", period for a new sentence, comma for a soft continuation, parentheses for an aside) rather than a mechanical "-" swap — e.g. "This booking can't be cancelled — it's already cancelled…" → "…cancelled: it's already cancelled…"; "Ghi đúng mã này — hệ thống…" → "Ghi đúng mã này: hệ thống…". Covered: `GocContext.jsx`/`AppState+Data.swift`/`AppState+Payments.swift` toast/error strings, `Verifications.jsx`/`VerificationsView.swift`, `DisputeChatPanel.jsx`/`.swift`, `Confirmed.jsx`/`ConfirmedView.swift`, `Login.jsx`/`LoginView.swift`, `CreateEvent.jsx`/`OnboardingViews.swift`, `PaymentDetails.jsx`/`PaymentViews.swift`, `Account.jsx`/`AccountView.swift`/`AccountGroup.jsx`/`AccountGroupView.swift`, `Reports.jsx`/`ReportsView.swift`/`AppState+Reports.swift`, `Attendance.jsx`/`AttendanceView.swift`, `Chat.jsx`/`MessagingViews.swift` (decorative "— Unread —" → "(Unread)"), and email/alert templates `api/notify.js`, `api/auth/index.js`, `api/telegram-webhook.js`, `api/_lib/alerts.js`, `api/cron/purge-payment-documents.js`.
**Standalone dash placeholders** (`|| '—'` for a missing transaction ID/category/capacity/address/etc. in Disputes/Verifications/AdminEvents, both platforms) replaced with a real localized value: `T('Không Có Thông Tin', 'Not Provided')` / `app.T("Không Có Thông Tin", "Not Provided")`. Two unknown-status-label fallbacks (`MyRefunds.jsx`/`Attendance.jsx`, `['—','—']`) used "Không Xác Định"/"Unknown" instead — a status-unknown case, not a missing-field case, so the more semantically accurate fallback was used rather than the literal example string.
**Genuine numeric/date ranges kept as a plain hyphen**, not rewritten as prose: "3–5 ngày làm việc"/"3-5 business days" (Refunded.jsx/RefundedView.swift) and a reports date range (`GocContext.jsx`/`AppState+Reports.swift`) both now use `-`.
**Not touched, deliberately**: source comments (thousands of hits, this codebase's dominant use of "—" as a comment-prose connector — explicitly out of scope), URLs, hyphenated identifiers, CLI args, and user-authored/persisted content (none found containing a dash needing a fix in the scanned owned-string sources).
**Files**: too many to enumerate every line; see the diff. `src/lib/badges.js`'s and `Lib/Badges.swift`'s own new doc comments are unaffected (comments, not UI copy).

### Verification summary (this pass)
`npx vite build` → clean. `xcodegen generate` + `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**. Badge logic spot-checked via a standalone Node ESM script (permission gating, zero-count hiding, dedup-safe summation, 99+ cap — all correct). No simulator/device UI interaction this pass — the Map-sheet layering fix in particular could not be visually confirmed on-device/simulator, flagged explicitly above rather than claimed.

## Fix pass (2026-09-30, second) — dock jump when "+" tray opens

Bug report: opening the dock "+" tray visibly shifted the dock/icons upward for a moment.

**Root cause, confirmed by reading (no device access this session)**: `DockRow`'s own final layout modifier (`BottomTabBar.swift`) used to be `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)`, sitting inside `BottomTabBarOverlayRoot`'s plain `ZStack` (default `.center` alignment, `BottomTabBarOverlay.swift`). `setDockCreateTrayOpen(true)` (same file) grows the hosting window's own frame from a small dock band to full-screen for exactly as long as the tray needs the room — a real, sudden change in the HEIGHT this ZStack proposes to `DockRow`. `.frame(maxHeight: .infinity, alignment: .bottom)` doesn't anchor to a fixed coordinate — it fills whatever height it's GIVEN and then self-aligns `.bottom` within that filled rectangle, so a change in the proposed height is exactly the kind of input that recomputes where "bottom" lands, independent of whether the window's own bottom edge itself moved.

**Fix — DockRow's screen position no longer depends on the window's own frame size, structurally, not via a compensating offset**:
- `BottomTabBar.swift`'s `DockRow.body` — dropped `maxHeight: .infinity, alignment: .bottom`, kept only `.frame(maxWidth: .infinity)`. DockRow now reports its own fixed intrinsic height (from its content + padding), never a "fill and self-align" computation.
- `BottomTabBarOverlay.swift`'s `BottomTabBarOverlayRoot.body` — the ZStack is now `ZStack(alignment: .bottom)` (was the implicit `.center` default). DockRow is placed flush against the ZStack's own bottom edge using its own fixed height — and the ZStack's bottom edge IS the window's bottom edge, which `bandFrame(in:)`/`setDockCreateTrayOpen` always keep pinned to the physical screen's bottom edge (`y + height == bounds.height`) in BOTH the small band frame and the full-screen tray frame (confirmed by reading both call sites). DockRow's on-screen position is therefore anchored to a coordinate invariant to the window's height, not re-derived when the window resizes.
- `DockCreateTrayView` is unaffected — it's a separate view with its own internal `ZStack(alignment: .bottom)` and `.ignoresSafeArea()` scrim; it doesn't rely on the outer ZStack's alignment for its own full-bleed layout.

**Preserved, unchanged**: tray still renders above Map's native sheet at every detent (same window, same `windowLevel`); pass-through hit-testing when the tray is closed (band frame/`isHidden` sync untouched); scrim/hit-testing teardown timing (`setDockCreateTrayOpen`'s `closeAnimationDuration`-delayed shrink, untouched); Create Event/library/camera flows (untouched, `DockCreateTrayView` itself not modified); Map camera/filters/search/selection/detent state (never touched by this window at all).

**Verification**: `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**. This is a code-level trace, not a visual confirmation — no simulator/device UI interaction this session; the actual on-screen jump could not be re-observed before/after.
**Files**: `apps/ios/BanbeApp/Views/BottomTabBar.swift` (`DockRow.body`'s trailing `.frame`), `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift` (`BottomTabBarOverlayRoot.body`'s `ZStack` alignment).

**Correction (2026-10-08, real-device report) — the above was NOT fixed; it only removed one contributor.** On a real iPhone: opening "+" still nudged the dock upward, and closing it ("x") made the whole dock fly up toward the upper third of the screen before snapping back — the close case, not even present in the report the pass above addressed, was worse. The `ZStack(alignment: .bottom)` + fixed-intrinsic-height change above was real and is kept, but it was insufficient because it assumed the window's bottom edge staying at the same COORDINATE (`y + height == bounds.height` in both frames) was enough to guarantee an invariant on-screen result. It is not, in practice, once `setDockCreateTrayOpen`'s window resize happens inside the same SwiftUI transaction as the "+"→"x" `withAnimation` (open: `DockCreateButtonView.swift`'s own `withAnimation(.easeInOut(duration: 0.15))`; close: `DockCreateTrayView.close()`'s own `withAnimation`) — a raw `UIWindow.frame` assignment executed during an active SwiftUI animation transaction is not guaranteed to apply as a single, instantaneous, un-animated step the way the previous fix's reasoning assumed; the close path additionally raced its OWN `DispatchQueue.main.asyncAfter`-delayed shrink against that same transaction, which is consistent with why close visibly overshot worse than open.

**Real fix, this pass — stop resizing the window at all.** `DockOverlayWindow` (new `UIWindow` subclass, `BottomTabBarOverlay.swift`) is created once in `attach()` at the full screen size and never resized again, for either open or close — there is no more frame change for any transaction, animation, or delayed callback to race, so the class of bug is structurally gone rather than newly-avoided. Pass-through hit-testing (needed so this window doesn't swallow every touch on every screen just because it now always covers the whole screen — the original reason a small band existed at all, see `a5fd823`'s doc comment earlier in this file) is done geometrically instead of by resizing: `DockOverlayWindow.hitTest` forwards a touch only when it falls inside `passthroughRect` (the same small dock-band rectangle the window used to BE) or anywhere at all while `trayOpen` is true. `setDockCreateTrayOpen` now just flips that one boolean — no frame math, no `trayResizeToken`, no `asyncAfter`, so rapid "+"/"x" taps can't leave a stale delayed shrink behind either (there's nothing delayed left to go stale). `BottomTabBarOverlayRoot`'s `ZStack(alignment: .bottom)` from the first pass is kept and is now trivially correct, since its container's size literally never changes.
**Files**: `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift` (new `DockOverlayWindow`, `attach()`, `setDockCreateTrayOpen`).
**Verification**: `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**. Code-level trace only, same as above — no simulator/device UI run this session; the on-device jump/fly-up itself has not been re-observed, only reasoned about structurally (the window genuinely never resizes anymore, which removes the specific mechanism blamed above, but "no resize" is a stronger, more verifiable claim than "the previous resize was safe" was).

## Fix pass (2026-09-30, third) — Account information architecture reorg, real "My Tickets"

Reorganized Account by user intent rather than by implementation grouping, and made "My Tickets" show genuinely real data instead of stopping at a "Going" list that was demo-catalogue-first and routed to Event Detail rather than the ticket/QR screen. Kept the existing 3-tab structure (Personal/Host/Admin) and every existing `groupKey`/route/testid unchanged — only visible labels, content, and where a couple of rows live moved.

**Old → new mapping (Personal tab)**:
- `activity` group: relabeled "Vé & Hoạt Động"/"Tickets & Activity" → "Vé & Đặt Chỗ"/"Tickets & Bookings". Its content is now this account's REAL bookings (see "My Tickets" below) plus the pre-existing "Sự kiện đã hoàn thành" row, relabeled "Sự Kiện Quá Khứ"/"Past Events" (same destination, `goCompletedList`/`EventListView` mode `'completed'`, unchanged).
- Event-credit invites (organizer-collaboration credits — pending/confirmed contributions to someone else's event) RELOCATED out of `activity` into `team` ("Hồ Sơ & Team"/"Profile & Team") — a deliberate reclassification (both are organizer-collaboration concerns, a better fit than sitting next to real attendee bookings), not a silent drop. `team`'s badge is now `myOrganizerInvites.count + myEventCredits.count` (two distinct real arrays/tables, safe to sum).
- `preferences` group: relabeled "Tùy Chỉnh"/"Preferences" → "Cài Đặt"/"Settings" (reads more accurately for its actual contents — app preferences + security). No content change.
- `payments` group: unchanged (already matched "Payments & Documents" well).
- New "Trợ Giúp & Pháp Lý"/"Help & Legal" row added to the Personal tab, pointing at the existing bilingual Policy screen (`openPolicy()`/`PolicyView.swift`/`Policy.jsx` — the same screen used for signup consent, reachable read-only here, its own back-target set to wherever it was opened from). **Real gap, not fabricated**: no dedicated in-app Help/Support screen exists anywhere in this codebase — this row currently covers the Legal half only; there is nothing to route a "Help" tap to yet.
- Host tab / Admin tab structure: unchanged, already matched the target organization (org profile card → dashboard = "My Events"; `hostOps` = "Event Operations & Payments"; `team` = "Organizer Profile & Team"). **Parity fix**: iOS's `adminReview` was missing the "Tranh chấp thanh toán"/"Payment Disputes" row web already had (a known, previously-documented divergence — see this file's Fix pass (2026-09-30)'s adminReview note). Added it to iOS, routed to the same `openAdminDashboard()` destination iOS's disputes desk already lives inside (`AdminDashboardView`'s own `adminDisputes`/`loadAdminDisputes()`) — two doors into one real screen, not a new dispute-viewing mechanism.

**"My Tickets" — real DB-backed data end-to-end, reusing what already worked rather than rebuilding**:
- Data source: `paymentBookings` (web: `s.paymentBookings` via `loadPaymentBookings()`, `GocContext.jsx`; iOS: `app.paymentBookings` via `AppState+Payments.swift`) — the SAME real `bookings` query (`user_id`-scoped, joined to `events`/`organizers` for real name/date) Account's own Action Center was already loading. No new query, no demo-catalogue fallback as the primary path.
- Routing: an active booking (`status` in pending/confirmed/attended) opens `openBookingConfirmed(bookingId, eventKey, back: 'accountGroup'/.accountGroup)` — the exact existing helper Confirmed's notification-reopen path already uses, which self-gates the real QR via `isBookingTicket`/`PayableBooking.isTicket` (new computed property added to `PayableBooking`, mirroring `Booking.isTicket`'s canonical `status == "confirmed" && paymentState == .confirmed` — NOT the same as the pre-existing, looser `isPaid`, which also counts a manually-marked-paid state) vs. showing the current "awaiting payment"/"holding" state truthfully.
- Cancelled/expired/no_show bookings (real `bookings.status` values) get their own clearly labeled, non-interactive section — no fabricated "refunded" bucket, since `bookings.status` has no such value.
- Loading/empty states handled (`paymentsLoading`/empty-array checks on both platforms).
- Back-navigation polish: `Confirmed.jsx`/`ConfirmedView.swift`'s footer back-button label previously only special-cased a `'notifications'` back-target (everything else, including the new `'accountGroup'` target, showed the generic "Back to home" even though it correctly navigates back to the Account group). Added an `'accountGroup'`/`.accountGroup` case ("‹ Tài khoản"/"‹ Account") so the label matches where the button actually goes.
- **Known gap, not silently fixed**: iOS's `paymentBookings` query does not currently select `event_date`/`event_time` (only the event name via its existing join), so iOS's My Tickets rows show name + status but no date, unlike web's. Extending that shared struct's decode/`CodingKeys` was judged out of scope for this pass (several other payment screens already depend on its current shape) — flagged for a future pass.
- Badges: new `computeMyTicketsActionCount`/`AccountBadges.myTicketsActionCount` (personal-tab-only leaf badge on the `activity`/"Tickets & Bookings" group card — count of this account's own active-but-not-yet-a-real-ticket bookings), reading the SAME already-loaded `paymentBookings` array, deliberately NOT summed into the admin/host `computeAccountDockBadge` chain (that chain is scoped to admin/host duties by design — this is a personal-tab-only signal).

**Verification**: `npx vite build` → clean, 460 modules. `xcodegen generate` + `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED** (one real compile error found and fixed along the way: `PayableBooking` needed the new `isTicket` computed property, it didn't exist before this pass). Confirmed by reading, not device-tested: every relocated/renamed row still resolves to its original route/action (no `groupKey`/testid/route changed, only labels/content); `accountGroupKey`-based deep-link/back-navigation is unaffected since group keys are untouched; badge chain still sums only distinct real arrays.
**Files**: web `src/screens/Account.jsx`, `src/screens/AccountGroup.jsx`, `src/screens/Confirmed.jsx`, `src/lib/badges.js`; iOS `apps/ios/BanbeApp/Views/AccountView.swift`, `apps/ios/BanbeApp/Views/AccountGroupView.swift`, `apps/ios/BanbeApp/Views/ConfirmedView.swift`, `apps/ios/BanbeApp/State/AppState.swift` (`accountGroupTitle`), `apps/ios/BanbeApp/Models/PaymentDocument.swift` (`PayableBooking.isTicket`), `apps/ios/BanbeApp/Lib/Badges.swift`.

## Fix pass (2026-09-30, fourth) — Account section headers, invite-stranding fix, account deletion, notification banner overhaul

Three tickets in one pass: (1) real section headers + reordering across Personal/Host/Admin, (2) self-service account deletion, (3) the in-app toast banner duration/pause/dedupe/layering fix. Read `.claude/notes/07-notifications.md`'s own entry for (3)'s full detail — only a summary + file list is duplicated here.

### 1 — Section headers and reordering
Stated product hypothesis (NOT measured usage — no banbe usage data exists to cite): common task frequency is ticket/booking access → payments → settings → hosting → admin, so "Your Activity" (actionable/money content) now leads Personal, ahead of "Account & Settings".

**Personal tab, old → new order**:
- Identity card — unchanged, still first, no header.
- NEW header "Hoạt Động Của Bạn"/"Your Activity": ActionCenter → `activity` GroupCard ("Tickets & Bookings") → Going/Saved stat cards (Saved relabeled "Sự Kiện Đã Lưu"/"Saved Events") → `payments` GroupCard → Reports row (relabeled Title Case "Số Liệu & Báo Cáo"/"Metrics & Reports") → (web-only) Invite-friends card. Previously: identity card → Going/Saved → ActionCenter → Reports → invite card → `team`/`activity`/`payments`/`preferences` GroupCards in a flat list with no headers.
- NEW header "Tài Khoản & Cài Đặt"/"Account & Settings": NEW "Hồ Sơ Cá Nhân"/"Personal Profile" row (same destination as the identity card's own chevron — `openPublicProfile`/`.openPublicProfile`, not new functionality) → `preferences` GroupCard ("Settings") → "Help & Legal" row.
- `team` GroupCard ("Profile & Team") — REMOVED from its old always-shown spot here. **Reasoning**: a user can receive a co-organizer invite before ever turning Hosting Mode on; hiding the only entry point to that invite behind the Hosting toggle would strand them with an invisible, unactionable invite. Fix: (a) a NEW Host-tab entry point into the SAME `team` screen (`hostManagementRows`/host pane, gated `canHost`, same "two doors, one destination" pattern the Payment Disputes row already established for `adminReview`), and (b) a lightweight conditional row on Personal (`account-team-invite-banner`/`account.teamInviteBanner`), shown ONLY when `myOrganizerInvites.length > 0 && !organizerMode`. The two are mutually exclusive by construction (the Host tab is unreachable whenever `organizerMode` is off — see the existing `accountTab` role-sync effect), so neither ever double-counts; both read the SAME badge source (`myOrganizerInvites.length [+ myEventCredits.length]`).
- "Tổ Chức"/"Hosting" header + toggle + pitch card — position/content unchanged.
- Sign out — unchanged, still last.

**Host tab, old → new order**: org profile card → `hostOps` GroupCard → NEW `team` GroupCard entry ("Hồ Sơ & Team Tổ Chức"/"Organizer Profile & Team", gated `canHost`) → Reports row (moved AFTER the group cards; was BEFORE them). No header added (tab itself is already scoped).

**Admin tab, old → new order**: NEW header "Quản Trị"/"Administration" (this tab previously had none) → `adminReview` GroupCard FIRST → Reports row AFTER (a real order swap — was Reports first, then the group card).

Every `groupKey`/testid/accessibility-identifier/route/deep-link/badge-source is unchanged — only labels, headers, and on-screen position moved. New shared header component: web `SectionHeader` (`Account.jsx`, same 11.5px/weight-600/`ink` style the pre-existing "Tổ Chức" header already used); iOS `sectionHeader(_:topPadding:)` (`AccountView.swift`).

**Verified by reading, not device-tested**: every relocated row's `onClick`/action target diffed against its pre-pass value — unchanged in all cases. Badge sources re-traced: `activity`→`computeMyTicketsActionCount`, `payments`→none, `preferences`→none, `team`→`myOrganizerInvites.length + myEventCredits.length` (same on both its entry points), `hostOps`→`verifications.length + refundQueue.length`, `adminReview`→`pendingEventsCount` — all unchanged in value.
**Files**: web `src/screens/Account.jsx` (`SectionHeader`, full personal/host/admin pane reorder); iOS `apps/ios/BanbeApp/Views/AccountView.swift` (`sectionHeader(_:)`, same reorder, `hostManagementRows`'s new `team` groupCard).

### 2 — Self-service account deletion
**Data handling** (see the migration's own doc comment for the full per-table trace): hard-deleted via `profiles.id → auth.users(id) ON DELETE CASCADE` (bookings.user_id, threads/messages the user sent into a cascaded thread, favorites, follows, organizer_members, event_organizer_credits, thread_participant_state/message_reactions, device_push_tokens); anonymized/orphaned via `ON DELETE SET NULL` (organizers.owner_id/user_id, bookings.paid_marked_by/cancelled_by, messages.sender_id, payment_documents.uploaded_by, dispute_events.actor_id, refund_batches.created_by, payment_verifications.verified_by) — matches Policy's "booking record stays, identity detached" claim; blocked entirely (409, no deletion attempted) while any organizer this user owns (`owner_id`/`user_id`) has an event `status IN ('live','review')`.

**Deployment status, stated precisely**: migration `20261023000111_111_account_deletion_requests.sql` — **applied** to the live project (`npx supabase db push --linked`, confirmed via `supabase migration list`). Endpoint (`api/auth/index.js`, `type: 'delete_account'`, folded into the existing dispatcher) and pure eligibility helper (`api/_lib/accountDeletion.js`, unit-tested) — **written, `node --check`-clean, NOT exercised end-to-end** (no isolated test account was created/destroyed this session, per this ticket's own explicit "no destructive integration test" instruction). Client flow (web `src/screens/sheets/DeleteAccountSheet.jsx`; iOS `apps/ios/BanbeApp/Views/DeleteAccountView.swift`) — **written, builds clean on both platforms, not run in a simulator/device**.

**Policy copy correction, made this pass**: `Policy.jsx`/`PolicyView.swift` previously promised automatic deletion of accounts inactive 6 months (14 for organizers), with 11-month/7-day/1-day reminder emails — **none of that exists** (no cron job, no reminder emails; confirmed by grep, matches this ticket's own "no existing auto-delete" premise). Corrected FOUR passages (both platforms, both languages) to explicitly say this is "planned, not yet built" rather than leaving a live, false claim in shipped legal copy. The "self-service in Preferences, no request needed" and "refused while you own an open event" claims were left as real claims (now backed by real code), with "one tap" softened to "self-service ... a few in-app confirmation steps" since the real flow is a multi-step wizard, not literally one tap.

**Flow** (Settings → `preferences` AccountGroup screen → new "Account Management" subsection, `alert`-tinted, distinct from Sign Out): intro (shows signed-in identity) → optional reason picker (fixed list + "Other" free text + "Prefer not to say", never blocks) → confirm screen with (a) reauthentication reusing the EXISTING emailed 8-digit login-code flow (`verifyEmailCode`/`AuthViewModel.verifyEmailCode` — no parallel auth mechanism built; an OAuth-only account is told a fresh sign-in is needed instead, since this app has no Apple Sign-In at all — confirmed by grep — and no OAuth re-consent path beyond a plain `signInWithOAuth` to reuse) and (b) an exact-phrase gate ("DELETE banbe", case-sensitive, never pre-filled) → final button disabled until both gates pass, disabled again synchronously on tap, truthful "Deleting…"/"Account deleted" copy (never claims completion before the server call actually returns 200). On confirmed completion: signs out, clears `localStorage`/`sessionStorage` (web) — no push-token local cache exists to clear on either platform (confirmed by reading `AppState+Push.swift`/the web push code path; `forgetPushTokenLocally()` documents this rather than silently no-opping unexplained).
**Files**: migration `20261023000111_111_account_deletion_requests.sql`; `api/auth/index.js` (`handleDeleteAccount`, dispatcher wiring), `api/_lib/accountDeletion.js` (new), `tests/unit/account-deletion-open-event.test.mjs` (new, 5 cases, all passing); web `src/screens/sheets/DeleteAccountSheet.jsx` (new), `src/screens/AccountGroup.jsx` (Account Management row), `src/state/GocContext.jsx` (delete-account state + actions), `src/App.jsx` (sheet mount), `src/screens/Policy.jsx` (copy correction); iOS `apps/ios/BanbeApp/Views/DeleteAccountView.swift` (new), `apps/ios/BanbeApp/Views/AccountGroupView.swift` (Account Management row), `apps/ios/BanbeApp/Views/RootView.swift` (`.fullScreenCover`), `apps/ios/BanbeApp/State/AppState.swift` (`deleteAccountOpen`), `apps/ios/BanbeApp/State/AppState+Push.swift` (`forgetPushTokenLocally`), `apps/ios/BanbeApp/Services/AuthAPIService.swift` (`deleteAccount`, `AccountDeletionError`), `apps/ios/BanbeApp/Views/PolicyView.swift` (copy correction).

### 3 — Notification banner fix
Summary only — full detail in `.claude/notes/07-notifications.md`'s matching dated entry. Duration is now a named 8s constant on both platforms, starting when the banner is ACTUALLY painted (a per-toast mount effect calls `markToastVisible`/`markVisible`, not enqueue time). Pause-on-interaction is a REAL timer pause (pointerenter/touch on web, a press gesture on iOS) with a cancel+remaining-budget-record, not a visual-only state. Dedup by stable notification id — a new arrival for an already-visible notification is a no-op, never resets the visible banner. Tap cancels the auto-dismiss timer synchronously before `openNotification`'s async work runs. **iOS layering root cause**: `ToastOverlay` lived in the MAIN window's ZStack, rendering beneath Map's native `.sheet()` — the same bug class already fixed for the dock tray. Moved into `BottomTabBarOverlay`'s existing always-on-top `DockOverlayWindow` (the SAME window, not a third one), with an ADDITIVE `toastRect` hit-test region alongside the pre-existing `passthroughRect`/`trayOpen` (never touching their own meaning) — `ToastFramePreferenceKey` reports the banner's real on-screen frame up to `BottomTabBarOverlay.setToastRect`. `BottomTabBarOverlay.swift`'s just-fixed dock-centering logic (`DockRow`, `BottomTabBarOverlayRoot`'s `.frame(..., alignment: .bottom)`) was re-read, not re-derived, and is untouched (`git diff --stat` confirms additive-only: 44 insertions, 1 changed line — the `hitTest` guard's OR-condition).
**Files**: web `src/state/GocContext.jsx` (toast timer rewrite), `src/screens/ToastStack.jsx` (`ToastCard`, pause/resume/mark-visible wiring); iOS `apps/ios/BanbeApp/State/AppState.swift` (timer rewrite), `apps/ios/BanbeApp/Views/ToastOverlay.swift` (press gesture, `onAppear`, `ToastFramePreferenceKey`), `apps/ios/BanbeApp/Views/RootView.swift` (mount site removed), `apps/ios/BanbeApp/Views/BottomTabBarOverlay.swift` (`toastRect`, `setToastRect`, `ToastOverlay()` mount — additive only).

**Build verification (this pass)**: `vite build` clean (461/462 modules, no errors, only the pre-existing >500kB chunk-size warning). `xcodegen generate` clean; `xcodebuild -scheme PersonalTeamDebug -configuration PersonalTeamDebug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED** (re-run after every batch of changes in this pass, all green). `npm run test:unit` → 16/16 passing (5 new account-deletion-eligibility cases + 11 pre-existing). No simulator/device UI interaction this session — every UI/behavior claim above is verified by reading the code, not by observing it run.

## Fast cleanup pass — Inbox loading-icon position, remaining Title Case gaps, Metrics & Reports localization leak

The stale refund badge from this same pass is documented in
`.claude/notes/16-refund-lifecycle.md` instead (refund-specific root cause),
not duplicated here.

**1 — Inbox loading icon too close to header (iOS only; web's pull-to-
refresh indicator is one shared implementation in `App.jsx`, not duplicated
per screen, so it never had this inconsistency)**: real root cause —
`InboxView`'s `RootRefreshIndicator` was a sibling of the WHOLE top-level
`VStack` (header included), top-aligned against the FULL screen with a flat
`.padding(.top, 54)` — measured from the screen's own top edge, not from
the bottom of `header`. Home/NotificationsView place the exact same
indicator via `ScreenScaffold`'s `refreshIndicatorTopPadding: 16`, but
THAT padding is measured from the top of their scroll content, which is
already below their own header (a sibling ABOVE `ScreenScaffold`, same
shape as `InboxView`'s own `header`) — so "54" and "16" were never
comparable numbers to begin with, and 54-from-the-screen-top landed the
spinner far closer to (this header being taller, almost touching) the
header's own bottom edge than intended. Fixed by scoping a new
`ZStack(alignment: .top)` to the content BELOW `header` only (mirroring
`ScreenScaffold`'s own reference frame exactly) and reusing the SAME
established `16` value Home/Notifications already use — `header` itself,
the `ScaffoldScrollProbe`/pull-gesture wiring, and the List/empty-state
branches are all untouched. `apps/ios/BanbeApp/Views/MessagingViews.swift`
(`InboxView.body`).

**2 — remaining Title Case gaps**: `src/screens/Reports.jsx`'s own screen
title was still `'Metrics & reports'` (lowercase "reports") despite every
OTHER call site of the same string (`Account.jsx` x3, iOS `AccountView.
swift`/`ReportsView.swift`) already being correct — the one place that
actually renders as this screen's own `<h1>`-equivalent was the one place
missed. Also fixed, both platforms: "Awaiting verification" → "Awaiting
Verification" (`AccountGroup.jsx`/`AccountGroupView.swift`'s host-ops row +
booking-status label, `Verifications.jsx`/`VerificationsView.swift`'s own
screen title), "Payment detail" → "Payment Detail" (same screen title,
focused-booking variant), "Underlying data" → "Underlying Data"
(`Reports.jsx`/`ReportsView.swift`'s expanded-card subsection header), and
a cluster of `AccountGroup.jsx`/`AccountGroupView.swift` row labels that
were never Title Cased in the first place: "Team invites", "My teams", "My
tickets", "App preferences", "Getting paid", "Invoices issued", "Receipts
issued" (web only — iOS's own copies of all of these were already
correct), and web-only "Payment disputes" (iOS's own row already said
"Payment Disputes"). One VI-side inconsistency also fixed for consistency
with every other call site of the same string: `SurveysHosting.jsx`'s own
`<h1>` had `'Khảo sát & Ý tưởng sự kiện'` (lowercase) while every other
occurrence of this exact string elsewhere in the app is fully capitalized.
Left untouched, deliberately: action/button-style labels ("Save image",
"Download CSV", "Expand all", "Retry", "Invite friends", etc.) — sentence-
case CTAs are this app's own established convention (matches "Preview"/
"Retry" everywhere else), not a missed heading.

**3 — Metrics & Reports English localization leak (real, confirmed)**:
`get_account_kpis()` (migration 097) hardcodes every metric's `label` as a
single Vietnamese string server-side, with NO English counterpart in the
payload at all — switching the app to English never translated a single
KPI card title, chart title, or PDF line, because nothing client-side was
even trying to. No migration/schema change this pass (out of scope) —
translated client-side instead, keyed by the metric's own stable `key`
(16 known keys from migration 097, read directly from that file, not
guessed): new `src/lib/reportMetricLabels.js` (`metricLabel(metric, T)`)
and iOS `apps/ios/BanbeApp/Lib/ReportMetricLabels.swift`
(`ReportMetricLabels.label(metric, T)`) — ONE shared module per platform,
reused by both the on-screen cards/chart (`Reports.jsx`'s `MetricCard`/
`MiniChart`, iOS `ReportsView.swift`'s `ReportChartView`/the collapsed-card
row) and the PDF export (`GocContext.jsx`'s `exportReportsPdf`, iOS
`AppState+Reports.swift`'s PDF draw loop) so the two can never show
different English wording for the same metric. Falls back to the raw
server (Vietnamese) label if a metric key is ever missing from the map (a
future new KPI), so this can never render blank. Left untouched,
deliberately: the JSON export (`exportReportsJson`) keeps the raw server
label — a downloaded data file, not on-screen UI copy, same reasoning as
"don't translate database content." Table column headers in the expanded-
card detail rows (`Object.keys(rows[0])`) are raw database column names,
also left untouched for the same reason.

**Verified**: `npx vite build` clean. `xcodegen generate` (new Swift file
picked up) + `xcodebuild -scheme PersonalTeamDebug -configuration Debug
-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
→ **BUILD SUCCEEDED**. No simulator/device UI run — the Inbox spinner
reposition, Title Case corrections and KPI label translations were all
verified by reading the code and tracing the exact reference frames/data
sources, not by observing them render.

## Fix pass (2026-10-02) — Pulse expanded panel redesign, fixed Account header+tabs

Two unrelated tickets, bundled. `npx vite build` clean;
`xcodebuild -scheme PersonalTeamDebug -sdk iphonesimulator build` → BUILD
SUCCEEDED; `npm run test:unit` 24/24 (pre-existing suite, unaffected). No
simulator/device UI run this pass — both are visual/interaction changes
the user's own iPhone is the real check for.

### Pulse — expanded panel: centered floating glass card, image-aware sizing

**Real bug, both platforms**: the ranked-photo popup (`photoSheet`/
`PulseViewer.jsx`'s `pulse-photo-sheet`) was a native/CSS bottom sheet
fixed at 66% of screen height with a hardcoded 2:1 media/footer split —
"wide filler panels around the featured photo" whenever a photo's real
aspect ratio didn't match that fixed box (the fix already in place,
2026-10-25, only blurred/dimmed the gap, never removed it). The ranked-
EVENT popup (`organizerSheet`/`pulseOrganizerSheet`) had no photo at all.

**Fix**: one shared, reusable presentation on each platform —
`pulseExpandedPanel` (iOS, `PulseViewerView.swift`) / `ExpandedPanel` (web,
`PulseViewer.jsx`) — a centered, rounded glass card (`.ultraThinMaterial`/
CSS `backdrop-filter: blur()`) over a dimmed/blurred scrim, bounded to the
real viewport with margins (`maxWidth`/`maxHeight`, never a fixed
fraction). The photo sizes itself to its OWN aspect ratio
(`.aspectRatio(contentMode: .fit)` with only max-constraints / CSS
`maxHeight` + `object-fit: contain`) instead of a fixed media box — no
more gap to fill. The one blurred backdrop that remains is the SAME
loaded image behind the WHOLE card (one surface), not a second,
visibly-separate rectangle behind just the photo. `.ultraThinMaterial`
auto-respects Reduce Transparency; the panel's own appear/disappear
transition is skipped (not the content) under Reduce Motion (iOS:
`.animation(reduceMotion ? nil : ..., value:)`).

Both `photoSheet` (Featured Photos) and `organizerSheet` (Top Events →
Today/This Week — previously photo-less) now render through this one
component. The event panel gained an honest meta line (category + real
`booking_count`/`checkin_count`, the same breakdown the ranked-list row
already shows — never a fabricated engagement count or a changed ranking)
and a new "Xem trang tổ chức"/"View host page" action
(`openOrganizerProfile`) alongside the existing Follow/"Xem sự kiện". No
real date/price field exists in `goc_pulse_ranked()`'s own payload (traced,
not assumed — confirmed by reading migration 086's `SELECT` list) — not
fabricated, left out rather than guessed; a future pass wanting it needs
its own migration.

Like/Share permissions, counts, selected item, dismissal, return state and
dock-hiding are completely unchanged — only the surrounding chrome moved.
Close "×"/X is a 44×44pt tappable target on both platforms.

**Files**: iOS `Views/PulseViewerView.swift` (`pulseExpandedPanel`,
`organizerSheet`/`photoSheet` rewritten to use it, `reduceMotion`
environment value); web `src/screens/sheets/PulseViewer.jsx`
(`ExpandedPanel`, both sheet blocks rewritten, `openOrganizerProfile` added
to the `useGoc()` destructure).

### Fixed Account header + tabs

**Web**: title row + Personal/Host/Admin tab pills wrapped in one
`position: sticky; top: 0` container (`data-testid="account-fixed-header"`)
— stays stationary while the shared scroll container (App.jsx's Shell)
scrolls the tab panels below it. Each tab panel keeps its existing
`display: none/block` toggle (never unmounted) — unchanged.

**iOS**: `accountHeader` was already a fixed sibling above `ScreenScaffold`
(2026-09-29 follow-up); the Personal/Host/Admin tab pills (`HStack`) used
to be the FIRST row INSIDE `accountContent`'s own scrollable `LazyVStack`
— pulled out into a new `accountTabsBar`, a second fixed sibling between
`accountHeader` and `ScreenScaffold`, so switching tabs while scrolled no
longer requires scrolling back to the top first.

**Independent per-tab scroll position (new on iOS — was a documented
"not built this pass" simplification, Stage D's own comment)**:
`AppState.accountScrollAnchorID` (single, shared anchor across all three
tabs) replaced with `accountScrollAnchorIDByTab: [String: String]`, keyed
by `accountTab`, read/written through a computed `accountScrollAnchorBinding`
in `AccountView.swift`. `accountContent`'s `LazyVStack` also gained
`.id(app.accountTab)` — switching tabs now tears down and recreates that
subtree (standard SwiftUI "new identity resets scroll offset"), and
`ScreenScaffold`'s existing `scrollPosition(id:)` restore mechanism
(`retryScrollRestoreIfNeeded`, already used for a full screen return)
naturally re-applies per-tab on that same recreation. Web's existing
per-tab scroll behavior (all three panels stay mounted, `display:none`
toggle, raw `scrollTop` carries over) is unchanged by this pass — not a
true per-tab independent position the way the web panels' own "both panes
keep their scrollTop" comment implies, since the shared scroll container
is keyed by SCREEN (`App.jsx`'s `scrollPositions`), not by tab; flagged,
not silently fixed, since refactoring web's scroll-ownership model here
risked the gesture/swipe system this pass didn't otherwise touch.

Back/swipe-return, badges, role gates (organizer-mode/admin tab
visibility), the Hosting toggle, and pull-to-refresh are all unchanged —
this pass only moved WHERE the tab row renders and added the per-tab
anchor map, never the tab-switch/role-gate logic itself. Root/dock swipe
behavior is untouched (no changes outside `AccountView.swift`/
`Account.jsx`).

**Files**: iOS `Views/AccountView.swift` (`accountTabsBar`, `accountContent`'s
`.id`, `accountScrollAnchorBinding`, `retryScrollRestoreIfNeeded`),
`State/AppState.swift` (`accountScrollAnchorIDByTab`); web
`src/screens/Account.jsx` (sticky header wrapper).

import SwiftUI
import UIKit

private struct HomeControlPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(
                .spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.14),
                value: configuration.isPressed
            )
    }
}

/// Home's area control is a native `Menu` mounted inline on this header
/// (see `header` below), so nothing needs to know where it sits on screen any
/// more: the former HomeAreaFramePreferenceKey existed only to feed the
/// removed AreaSheetView's anchored placement math, and is gone with it.

/// The feed — a port of src/screens/Home.jsx: header (wordmark, language
/// toggle, area picker, notification bell, messages, account), the held-spot
/// banner, the "Your events" strip, category filters, and the photo cards.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()
    /// Bumped each time Home becomes the visible screen; replays the reminder halo.
    @State private var reminderHaloTrigger = 0
    // TASK 4 (2026-09-22 nineteenth follow-up) — one-shot guard so the
    // retry below (see its own comment) only ever fires once per Home
    // mount, never repeatedly fighting the user's own subsequent scrolling
    // (which keeps updating `app.homeScrollAnchorID` live via
    // `.scrollPosition(id:)`'s own two-way binding — see requirement 4).
    @State private var didAttemptScrollRestore = false
    /// The area menu's own "Search locations…" row opens the searchable
    /// location list — a native `Menu` can't host a text field, so this is
    /// where typing a place name still works. See `LocationPickerSheet`.
    @State private var areaSearchOpen = false
    @StateObject private var forYouAlert = ForYouAlertModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let filters: [(key: String, vi: String, en: String)] = [
        ("all", "Tất cả", "All"),
        ("supper", "Supper club", "Supper club"),
        ("fashion", "Thời trang", "Fashion"),
        ("gallery", "Phòng tranh", "Gallery"),
        ("music", "Nhạc", "Music"),
    ]

    /// Any of these showing is reason enough to tick every second; none of
    /// them showing means no clock runs at all.
    private var anyCountdownVisible: Bool {
        app.heldEvent != nil || app.myHolding != nil || app.myPendingVerification != nil
            || app.organizerPendingCount > 0 || app.organizerHoldingSummary != nil
    }

    /// TASK A (2026-10-01 UX foundation pass) — goer items always
    /// considered, host items only while `app.canHost`, merged and
    /// re-sorted together (mirrors src/screens/Home.jsx's own actionItems).
    private var actionItems: [ActionCenterItem] {
        var goer = buildActionCenterItems(ActionCenterInputs(
            role: .goer, now: tick,
            myHolding: app.myHolding, myPendingVerification: app.myPendingVerification, myRefunds: app.myRefunds,
            refundDestinations: app.refundDestinationsLoaded ? app.refundDestinations : nil,
            onOpenPayment: { app.openPaymentDetails($0, back: .home) },
            onOpenMyRefunds: { app.openMyRefunds(back: .home) },
            onOpenRefundAccounts: { app.openRefundAccounts(back: .home) },
            // "Refund dispute open › View" goes to the booking conversation
            // that dispute actually belongs to, with its card expanded.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        ))
        if app.canHost {
            goer += buildActionCenterItems(ActionCenterInputs(
                role: .host, now: tick,
                verifications: app.verifications, refundQueue: app.refundQueue, orgHolding: app.organizerHoldingSummary,
                onOpenVerifications: { app.openVerifications() },
                onOpenRefundCenter: { app.openVerifications() },
                onOpenDashboard: { app.goDashboard() },
                onOpenAttendance: { key in app.openAttendance(key, back: .home) },
                // Same single-dispute shortcut as the goer half.
                onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
                T: app.T
            ))
        }
        return sortActionCenterItems(goer)
    }

    var body: some View {
        // Task 3 (2026-09-21 follow-up) — `scrollPositionID` restores the
        // feed to roughly where the user left it on returning from Event
        // Detail (see `ScreenScaffold`'s own doc comment for why this is
        // id-based, not a raw pixel offset). Only the event cards below
        // get a stable `.id(...)` — the header/banners/chips are always a
        // small, fixed offset near the top and aren't meaningful restore
        // targets the way "which event card was on screen" is.
        // Pull-to-refresh header fix (2026-09-29 follow-up) — matches
        // Messages: `header` is now a sibling ABOVE `ScreenScaffold`, not the
        // first item inside the content it offsets during a pull, so it
        // never moves/shifts — only the feed below it does.
        // Opaque-header fix (2026-09-29 follow-up, real-device report:
        // overlapping headers during a swipe-back transition) — `header`
        // used to inherit `ScreenScaffold`'s own opaque `app.palette.paper`
        // background for free, since it was rendered INSIDE that scroll
        // content. Pulled out as a sibling above it, `header` itself paints
        // nothing behind its text — transparent — so mid-transition, the
        // OTHER screen sitting behind this one in RootView's swipe ZStack
        // showed straight through it. Matches InboxView's own
        // `ZStack { app.palette.paper.ignoresSafeArea(); VStack { header; ... } }`
        // shape exactly, which never had this bug.
        ZStack {
            app.palette.paper.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
            header
            ScreenScaffold(tracksBottomBarScroll: true, scrollPositionID: $app.homeScrollAnchorID, refreshIndicatorTopPadding: 16, onRefresh: {
                await app.loadHomeLiveEvents()
                await app.loadWeekendEvents()
                await app.loadDiscoveryEvents()
                if app.userID != nil {
                    await app.loadHomeStories()
                    await app.loadHomeSurveyDiscovery()
                }
            }) {
                // Lazy, so only the cards actually on screen fetch their photo —
                // the eager VStack kicked off all ~21 hero downloads at launch
                // and they all fought for the same bandwidth.
                LazyVStack(alignment: .leading, spacing: 0) {
                    // TASK A (2026-10-01 UX foundation pass) — replaces the old
                    // fixed four-banner `paymentBanners` block: one unified,
                    // priority-sorted, 3-card-capped Action Center covering both
                    // roles this account can hold. heldEvent itself stays in use
                    // for tagging the "Your events" strip further down.
                    ActionCenterView(items: actionItems, onSeeAll: { app.goNotifications() })
                    if !app.savedStrip.isEmpty { savedStrip }
                    storyRow
                    surveyDiscoveryRow
                    filterSection
                    if app.feed.isEmpty {
                        emptyState
                    } else {
                        ForEach(app.feed) { event in
                            EventCard(event: event)
                                .id(event.key)
                        }
                        footer
                    }
                    weekendSection
                    hostLink
                }
                .padding(.bottom, 100)
            }
        }
        }
        // 2026-10-02 fix — "refresh correctly on foreground": these loads
        // only ever ran once, on this view's own mount (`.task` below) —
        // a booking cancelled/refunded on another device, or by the host,
        // while this device sat backgrounded never updated the "Going"
        // chip until Home happened to remount. Re-runs the same loads
        // (idempotent re-fetch, same as every other "also loaded here"
        // source in this codebase) on returning to the foreground.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, app.userID != nil else { return }
            Task {
                await app.loadPaymentBookings()
                await app.loadMyRefunds()
                await app.loadRefundDestinations()
                await app.loadMyEvents()
            }
        }
        .task {
            guard app.userID != nil else { return }
            await app.loadPaymentBookings()
            await app.loadMyRefunds()
            await app.loadRefundDestinations()
            if app.canHost {
                await app.loadVerifications()
                await app.loadOrganizerHoldingSummary()
                await app.loadRefundQueue()
            }
            // The data this decides on arrives asynchronously, after
            // .onAppear's own call below has almost certainly already run
            // and found nothing to show yet — without this, a countdown
            // could sit there never ticking at all, having missed its one
            // chance to start.
            startTickingIfNeeded()
        }
        // 2026-09-21 follow-up — real ended/cancelled status for every
        // catalogue event this screen might show, public info so this runs
        // for every visitor (no `userID` gate), same as `loadLiveEventStatus`
        // does for a single open event.
        .task { await app.loadHomeLiveEvents() }
        // Task 3.3 (07-notifications.md) — active-story row.
        .task { if app.userID != nil { await app.loadHomeStories() } }
        // Source-of-discovery pass — independent of the story ring above;
        // own initial load, own refresh, own pagination state.
        .task { if app.userID != nil { await app.loadHomeSurveyDiscovery() } }
        // Retention roadmap P1 ("Cuối tuần này") — public info, same as
        // loadHomeLiveEvents above (runs for every visitor).
        .task { await app.loadWeekendEvents() }
        // Home-visibility fix (2026-09-29) — public info, same as
        // loadWeekendEvents above (runs for every visitor); this is what
        // actually populates `app.feed` with real events at all (see
        // `discoveryEvents`'s own doc comment on AppState.swift).
        .task { await app.loadDiscoveryEvents() }
        // Blocker fix (retention roadmap follow-up) — a saved/attending
        // real (non-catalogue) event needs its own fetch for savedStrip to
        // resolve it instead of quietly skipping it.
        .task { await app.loadMissingRealEvents(for: app.favorites + app.attending) }
        .onChange(of: app.screen) { _, new in if new == .home { reminderHaloTrigger += 1 } }
        .onAppear {
            reminderHaloTrigger += 1
            startTickingIfNeeded()
            retryScrollRestoreIfNeeded()
        }
        .onDisappear { tickTask?.cancel() }
        // Task 1 (2026-09-22 twelfth follow-up) — collects every visible
        // story ring's own global frame for StoryViewerView's expand/
        // shrink-toward-ring transition (see AppState.swift's own comment
        // on storyRingFrames).
        .onPreferenceChange(StoryRingFramePreferenceKey.self) { app.storyRingFrames = $0 }
        .onPreferenceChange(RootGestureExclusionZonePreferenceKey.self) { app.rootGestureExclusionZones = $0 }
        // Reset-on-account-change — `visibleSurveyDiscoveryCount` is plain
        // local `@State` (HomeView can stay mounted across a sign-out/
        // sign-in within the same session), so a new account must not
        // inherit a previous account's "already revealed 23 rows" state.
        .onChange(of: app.userID) { _, _ in visibleSurveyDiscoveryCount = 3 }
        // For You: recomputes (computed property) on any of these; reset if stale.
        .onChange(of: app.eventPrefsVersion) { _, _ in resetForYouIfStale() }
        .onChange(of: app.area) { _, _ in resetForYouIfStale() }
        .onChange(of: app.hasForYouMatches) { _, _ in resetForYouIfStale() }
        .onChange(of: app.discoveryEventsLoading) { _, _ in resetForYouIfStale() }
        // New-match attention (Lib/ForYouAlert.swift): observe on any input change.
        .onChange(of: app.forYouMatches) { _, _ in observeForYouAlert() }
        .onChange(of: app.discoveryEventsLoading) { _, _ in observeForYouAlert() }
        .onChange(of: app.eventPrefsVersion) { _, _ in observeForYouAlert() }
        .onChange(of: app.userID) { _, _ in observeForYouAlert() }
        .onAppear { observeForYouAlert() }
        .task { await app.loadRewardsSummary() }
        // The area menu's searchable fallback (see `header`): a native Menu
        // can't hold a text field, so "Search locations…" opens this sheet
        // instead. Same picker Map Explore uses, same `app.area` selection.
        .sheet(isPresented: $areaSearchOpen) {
            LocationPickerSheet(isPresented: $areaSearchOpen)
        }
        // The Pulse RING's frame is no longer tracked anywhere at all — no
        // PreferenceKey, no probe, no `AppState` property. The teaser bubble
        // is drawn inside `storyRow`'s own content these days, so there is
        // nothing to keep in sync. See `PulseTeaserBubbleContent`
        // (PulseTeaserBubbleView.swift) and `storyRow` below.
        // Home search relocation (2026-09-28 follow-up — real-device report:
        // the top-header search icon was still showing on a real iPhone).
        // Root cause: the 2026-09-28 dock/search pass that relocated web's
        // Home search to a floating button above the dock (src/screens/
        // Home.jsx, HomeSearchFab) never touched this iOS file at all — its
        // own commit only mentions the web dock/search fix; the header
        // button below (`home.searchButton`, 2026-09-27) was never removed
        // and no iOS equivalent of the floating button was ever added. Fixed
        // here: header button removed (see `header` below) and replaced with
        // this `.overlay`, attached to the WHOLE `ScreenScaffold` (this
        // modifier chain's own receiver), not to anything inside its
        // `ScrollView` content closure above — so it's a true sibling of the
        // scrolling feed, at the same view-hierarchy level web's fix put it
        // at (a sibling of the animated root div, never a descendant of it).
        // It therefore can never scroll away or get clipped by the feed's
        // own content, matching this ticket's "outside any scrolling/
        // animated containing block" requirement.
    }

    /// TASK 4 (2026-09-22 nineteenth follow-up) — real root cause,
    /// confirmed by reading `ScreenScaffold` (Components.swift): its
    /// `.scrollPosition(id:)` restoration only works for an `.id(...)`
    /// that's already materialized in the `LazyVStack`'s own view
    /// hierarchy — a well-known SwiftUI limitation (this exact class of
    /// bug is already documented once in this file's own `ScaffoldScrollProbe`
    /// comment, for a different symptom). Returning to Home after scrolling
    /// PAST the first screenful means the target event card's row was
    /// never instantiated in this fresh `HomeView` instance's `LazyVStack`
    /// at the moment `.scrollPosition(id:)` first tries to restore it, so
    /// the restore silently no-ops. Switching away from `LazyVStack` (would
    /// reintroduce the ~21-simultaneous-photo-download regression this file
    /// already fixed once) or restructuring `ScreenScaffold` into a `List`
    /// (touches Inbox/Notifications/Account too) are both too large for
    /// this pass. Instead: re-drive the SAME binding a moment after this
    /// view actually appears — by then `app.feed`'s async dependencies
    /// (`loadHomeLiveEvents`, etc.) have generally settled and SwiftUI's
    /// own layout pass has had a real chance to instantiate more of the
    /// LazyVStack, giving the retry a real shot at finding the target id
    /// that the very first, too-early attempt didn't. Toggled through nil
    /// first since re-assigning a Binding<String?> to its OWN current value
    /// wouldn't produce a change for `.scrollPosition(id:)` to react to.
    /// TASK 3 (2026-09-22 twentieth follow-up) — real root cause of the
    /// late/janky restore during an interactive edge-swipe back: RootView's
    /// peek (`screenView(for: app.backTargetScreen, isPreview: true)`, see
    /// RootView.swift) constructs a brand-new `HomeView` the instant the
    /// user's finger moves — its `.home` case ignores `isPreview` entirely,
    /// so this is the SAME view/onAppear path as any other Home mount. The
    /// flat 400ms delay below was tuned for the genuine FIRST-load case,
    /// where `app.feed` is still empty and the async loaders in `.task`
    /// above haven't populated it yet. But on a return-from-Event-Detail
    /// peek, `app.feed` is already populated (it's never cleared on screen
    /// navigation — only this View struct is torn down and recreated), so
    /// waiting 400ms here is exactly what let Home reveal at the top first
    /// and only jump into place afterward, instead of already being correct
    /// before the peek reveals anything. Skipping the wait whenever the
    /// data needed to restore is already in hand fixes that without
    /// stacking another retry on top of this one.
    private func retryScrollRestoreIfNeeded() {
        guard !didAttemptScrollRestore, let target = app.homeScrollAnchorID else { return }
        didAttemptScrollRestore = true
        if !app.feed.isEmpty {
            app.homeScrollAnchorID = nil
            DispatchQueue.main.async {
                app.homeScrollAnchorID = target
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                app.homeScrollAnchorID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    app.homeScrollAnchorID = target
                }
            }
        }
    }

    private func startTickingIfNeeded() {
        tickTask?.cancel()
        // Screenshot Catalog (docs/demo-screenshots) — a live-ticking
        // countdown is exactly the kind of non-deterministic, mid-capture
        // change `scripts/capture_ios_catalog.sh` must avoid; this is the
        // only source of one on Home.
        guard !AppState.isUITesting, anyCountdownVisible else { return }
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                tick = Date()
                forfeitAnyJustLapsedHold()
                // Stop ticking once nothing is left to show — matches
                // useTicking()'s behaviour on the web side, and means a
                // countdown that just got forfeited above doesn't leave a
                // pointless per-second timer running forever afterward.
                if !anyCountdownVisible { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    /// Home is often the screen a buyer is sitting on when a hold's
    /// countdown reaches zero — not just the ticket screen. `app.myHolding`
    /// already excludes a lapsed row (that's what makes its banner
    /// disappear on time), which means it can't be used to notice the
    /// transition; this checks the raw list directly so Home can forfeit it
    /// the same instant the banner for it vanishes, rather than leaving
    /// that to whichever other screen the buyer happens to open next.
    private func forfeitAnyJustLapsedHold() {
        guard let justLapsed = app.paymentBookings.first(where: {
            $0.paymentState == .holding && $0.holdExpiresAt != nil
                && Countdown.secondsUntil($0.holdExpiresAt, now: tick) == 0
        }) else { return }
        app.forfeitExpiredHold(justLapsed)
    }


    // MARK: Header

    @ViewBuilder
    private func homeGlassCapsule(active: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                Capsule()
                    .fill(active
                          ? app.palette.ink.opacity(0.92)
                          : app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                    .glassEffect(.regular.interactive(), in: Capsule())
                      .opacity(active ? 1 : app.glassOpacity)
            }
        } else {
            if active {
                Capsule().fill(app.palette.ink)
            } else {
                Capsule()
                    .fill(app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                    .background(.thinMaterial, in: Capsule())
                    .opacity(app.glassOpacity)
            }
        }
    }

    // Task 2c (2026-09-21 follow-up) — a quick Appearance (light/dark)
    // toggle next to the existing language/area switchers, separated by
    // this app's own "▪" glyph (already used throughout its copy, e.g.
    // event captions like "Th 5, 09.07 ▪ 21:00") rather than a new divider
    // style. Wired to the SAME `toggleTheme` Preferences already uses — no
    // parallel theme state.
    // MARK: header top row (wordmark + title, streak/coin shortcuts, search)

    /// Shown only once the server has answered (migration 165 applied); never a placeholder number.
    private var rewardShortcutsVisible: Bool { app.rewardsSummaryStatus == .loaded && app.rewardsSummary != nil }

    /// With the shortcuts the row can get tight on narrow iPhones, so it degrades in a fixed order
    /// (ViewThatFits): full -> drop the "Home" title -> smaller wordmark. Every control keeps a 44pt
    /// touch target and the search button never moves.
    @ViewBuilder
    private var headerTopRow: some View {
        if rewardShortcutsVisible {
            ViewThatFits(in: .horizontal) {
                headerTopRow(wordmark: 96, showTitle: true)
                headerTopRow(wordmark: 96, showTitle: false)
                headerTopRow(wordmark: 80, showTitle: false)
            }
        } else {
            headerTopRow(wordmark: BanbeLogo.headerWordmarkWidth, showTitle: true)
        }
    }

    private func headerTopRow(wordmark: CGFloat, showTitle: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 10) {
                BanbeLogo(kind: .wordmark, width: wordmark)
                if showTitle {
                    // Home-specific label, same font/color as the other sections' titles.
                    Text(app.T("Nhà", "Home"))
                        .font(BanbeTheme.display(27))
                        .foregroundStyle(app.palette.ink)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
            }
            Spacer(minLength: 0)
            if rewardShortcutsVisible { rewardShortcuts }
            // Search lives in the header's top-right corner, part of the fixed header.
            HomeSearchButton()
        }
    }

    /// One glass capsule, two separate buttons (streak, coins), both opening Account > Rewards & badges.
    private var rewardShortcuts: some View {
        let sum = app.rewardsSummary ?? RewardSummary(balance: 0, streak: 0, activeToday: false)
        return HStack(spacing: 0) {
            Button {
                Haptics.light()
                app.screen = .rewards
            } label: {
                HStack(spacing: 4) {
                    Text("🔥").font(.system(size: 16)).opacity(sum.streak > 0 ? 1 : 0.45).accessibilityHidden(true)
                    Text("\(sum.streak)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Chuỗi \(sum.streak) ngày. Mở phần thưởng", "\(sum.streak)-day streak. Open rewards"))
            .accessibilityIdentifier("home.streak")
            Rectangle().fill(app.palette.ink.opacity(0.18)).frame(width: 1, height: 22).accessibilityHidden(true)
            Button {
                Haptics.light()
                app.screen = .rewards
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "circle.hexagongrid.circle").font(.system(size: 15, weight: .medium)).accessibilityHidden(true)
                    Text(RewardsLogic.compactCoins(sum.balance)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("\(sum.balance) xu. Mở phần thưởng và huy hiệu", "\(sum.balance) coins. Open rewards and badges"))
            .accessibilityIdentifier("home.coins")
        }
        .foregroundStyle(app.palette.ink)
        .background { homeGlassCapsule() }
        .overlay(Capsule().stroke(app.palette.rule.opacity(0.7 * app.glassOpacity), lineWidth: 1))
        .fixedSize()
    }

    private var header: some View {
        // Alignment changed from `.firstTextBaseline` to `.center` (2026-09-29
        // follow-up, wordmark doubled in size) — baseline alignment anchors a
        // non-text view's BOTTOM to the text baseline, so as the wordmark
        // image grows taller it pushes upward past the row's top and can
        // clip the quick-switch row on the trailing side along with it.
        // Centering keeps every sibling vertically centered in the row
        // regardless of the wordmark's height, so the lang/area/theme
        // buttons stay fully visible at any wordmark size.
        VStack(alignment: .leading, spacing: 8) {
            headerTopRow
            HStack {
                Spacer(minLength: 0)
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Bolder/larger + bigger hit-area (2026-09-29 follow-up)
                    // — bumped 13pt/semibold -> 15pt/bold and 4pt -> 7pt
                    // vertical padding on all three quick-switch buttons for
                    // easier tapping.
                    Button(app.T("EN", "VN")) {
                        Haptics.light()
                        app.toggleLang()
                    }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background { homeGlassCapsule() }
                        .overlay(Capsule().stroke(app.palette.rule.opacity(0.7 * app.glassOpacity), lineWidth: 1))
                        .buttonStyle(HomeControlPressStyle())
                        .accessibilityIdentifier("header.lang")
                    // "banbe ▪︎" prefix dropped (2026-09-29 follow-up) — was
                    // crowding out the actual region name; the control's own
                    // accessibility identifier and action already make it
                    // unambiguous which control this is without a label
                    // prefix repeating the app's own name.
                    //
                    // Area menu parity pass — this is a native `Menu` now, the
                    // same mechanism the chat composer's "+" attach button and
                    // Inbox's own row menus use, replacing the hand-rolled
                    // anchored glass panel (the former AreaSheetView) and all
                    // of its own scale/opacity reveal. Everything about how it
                    // presents — animation, Liquid Glass look, anchoring,
                    // outside-tap dismissal, edge/safe-area handling,
                    // light/dark, Reduce Motion — is therefore the system's and
                    // cannot drift from the chat "+" menu.
                    Menu {
                        AreaMenuOptions { areaSearchOpen = true }
                    } label: {
                        // The glass surface, stroke and padding live INSIDE the
                        // label, exactly like the chat "+" (ChatAttachButton puts
                        // its circle background inside its Menu label). Applied
                        // outside the Menu, the surface stayed behind as a
                        // separate layer while only the text morphed.
                        Text("\(app.currentAreaLabel) ▾")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background { homeGlassCapsule() }
                            .overlay(Capsule().stroke(app.palette.rule.opacity(0.7 * app.glassOpacity), lineWidth: 1))
                            .foregroundStyle(app.palette.ink)
                    }
                    .accessibilityIdentifier("header.area")
                    // No `toggleTheme()` exists on iOS — Preferences.swift's
                    // own theme picker already uses `pickTheme(_:)` directly
                    // (the exact write path, incl. persistence); this just
                    // calls the same function with the flipped value rather
                    // than adding a parallel toggle.
                    Button(app.theme == "dark" ? app.T("Sáng", "Light") : app.T("Tối", "Dark")) {
                        Haptics.light()
                        app.pickTheme(app.theme == "dark" ? "light" : "dark")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background { homeGlassCapsule() }
                    .overlay(Capsule().stroke(app.palette.rule.opacity(0.7 * app.glassOpacity), lineWidth: 1))
                    .buttonStyle(HomeControlPressStyle())
                    .accessibilityIdentifier("header.theme")
                }
                .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        // The web header fits in a narrower face; scale rather than clip if
        // a longer area name (or English) pushes the row past the edge.
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Your events

    private var savedStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.T("Sự kiện của bạn", "Your events")).font(BanbeTheme.display(15))
                Spacer()
                Text(app.T("Sự kiện đã qua sẽ ẩn sau 48h", "Past events clear after 48h")).font(.system(size: 11.5))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(app.savedStrip) { event in
                        SwipeSafeButton { app.goEvent(event.key) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ZStack(alignment: .topLeading) {
                                    CatalogPhoto(path: event.img, height: 96, width: 152, cornerRadius: 12)
                                    if reminderPhase(event) != nil {
                                        EventReminderHalo(trigger: reminderHaloTrigger, cornerRadius: 12)
                                            .frame(width: 152, height: 96)
                                    }
                                    HStack(spacing: 4) {
                                        if reminderPhase(event) != nil {
                                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color(hex: 0xFFD76A))
                                        }
                                        PhotoChip(text: app.trStatus(savedTag(event).0), background: savedTag(event).1)
                                    }
                                    .padding(6)
                                }
                                .accessibilityIdentifier(reminderPhase(event) != nil ? "home.eventReminder" : "home.savedEvent")
                                Text(event.name)
                                    .font(BanbeTheme.display(15))
                                    .lineLimit(1)
                                Text(app.trStatus(savedStatus(event)))
                                    .font(.system(size: 11))
                            }
                            .frame(width: 152, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Room for the reminder halo (a ScrollView clips), cancelled out below.
                .padding(.vertical, 12).padding(.horizontal, 12)
            }
            .padding(.vertical, -12).padding(.horizontal, -12)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        // The events strip owns horizontal scrolling. Register its real
        // bounds in the same root coordinate space used by tabSwipeGesture,
        // so a swipe that starts on an event stays with this ScrollView
        // instead of committing Home -> Map.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: RootGestureExclusionZonePreferenceKey.self,
                    value: ["savedEvents": geo.frame(in: .named("rootGesture"))]
                )
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    // MARK: Story row (Task 3.3, 07-notifications.md) — between "Your
    // events" and the main event list, per this ticket's own placement.
    // TASK E (2026-10-01 UX foundation pass) — "Banbe Pulse" is now a
    // PERMANENT first entry (index 0), so this row is no longer
    // conditional on real stories existing (was `if !app.homeStories.
    // isEmpty`) — always shows at least Pulse. Never rendered on Map (this
    // row only exists on Home).
    private var storyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                SwipeSafeButton { app.openPulseViewer() } label: {
                    VStack(spacing: 5) {
                        PulseRingGlyph()
                            // Same-space pass (2026-09-28, this pass): the
                            // `RingFrameProbe` that used to sit here as this
                            // glyph's `.background()` — reporting the ring's
                            // own on-screen frame up to the teaser bubble
                            // through a callback — is GONE, along with
                            // `AppState.pulseRingFrame`/`pulseBubbleFrameSink`
                            // and the whole callback pipeline behind them
                            // (PreferenceKey -> KVO probe -> imperative
                            // `UIHostingController` frame writes). Each of
                            // those still left the bubble frozen at a fixed
                            // screen position during a real finger-drag. The
                            // bubble is now drawn INSIDE `storyRow`'s own
                            // content, in this ring's exact scrolling
                            // coordinate space — see `PulseTeaserBubbleContent`
                            // (PulseTeaserBubbleView.swift) and the
                            // `.overlay` on this row's HStack below.
                        Text(app.T("Banbe Pulse", "Banbe Pulse"))
                            .font(.system(size: 9.5)).foregroundStyle(app.palette.ink).lineLimit(1).frame(width: 60)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.pulseAvatar")
                ForEach(app.homeStories) { group in
                    SwipeSafeButton { app.openStoryViewer(group.organizerId, originRect: app.storyRingFrames[group.organizerId]) } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(group.allViewed ? Color.clear : BanbeTheme.alert, lineWidth: 2.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(group.allViewed ? app.palette.rule : .clear, lineWidth: 2.5)
                                    )
                                    .frame(width: 56, height: 56)
                                Text(String(group.orgName.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(app.palette.ink)
                                    .frame(width: 48, height: 48)
                                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            Text(group.orgName)
                                .font(.system(size: 9.5))
                                .foregroundStyle(app.palette.ink)
                                .lineLimit(1)
                                .frame(width: 60)
                        }
                        // Task 1 — reports this ring's own global frame
                        // (the 56x56 ZStack above, not the label/text) via
                        // StoryRingFramePreferenceKey.
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: StoryRingFramePreferenceKey.self,
                                    value: [group.organizerId: geo.frame(in: .global)]
                                )
                            }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.storyAvatar")
                }
            }
            .padding(.horizontal, 20)
            // Same-space pass (2026-09-28, this pass) — THE teaser bubble.
            // It is part of this row's own content, i.e. inside the exact
            // same scrolling coordinate space as the Pulse ring it points at
            // (the ring is in the HStack above), so the feed's vertical
            // scroll AND this row's own horizontal scroll move ring and
            // bubble together as one piece of content — by construction,
            // with no callback, KVO, `convert(_:to:)` or SwiftUI render
            // commit anywhere in between. That is the whole fix for the
            // real-device report of the bubble sitting fixed on screen while
            // the ring scrolled: nothing positions it separately from the
            // ring any more.
            //
            // The anchor is this row's own layout constant, never a guess
            // about the screen: `padding(.horizontal, 20)` above plus half of
            // the ring's 56x56 glyph (centred in the 60pt-wide `VStack` that
            // also holds its label — verified at runtime as mid-x 50) is 50,
            // and the glyph starts at this content's own top, so its mid-y
            // is 28.
            //
            // Two SwiftUI specifics this deliberately works around, both
            // confirmed on a real accessibility dump of this row rather than
            // assumed:
            //  * the bubble gets a DEFINITE 230pt-wide layout box
            //    (`.frame(width:)`, content leading-aligned inside it) —
            //    this row's content is only as wide as the rings it holds
            //    (100pt with Pulse alone), and letting the proposal decide
            //    squeezed the copy to ~50pt and wrapped it two characters per
            //    line. The bubble itself still hugs its own copy up to that
            //    cap: 230 + 50 stays inside even a 375pt-wide iPhone.
            //  * the bottom edge is put on the anchor with a zero-height
            //    box (`.frame(height: 0, alignment: .bottom)`, with
            //    `.fixedSize(vertical:)` so the copy keeps its real height)
            //    rather than an `.alignmentGuide(.top)` — a guide is ignored
            //    by `.overlay(alignment:)` here, which is what left the
            //    bubble's TOP sitting on the ring's centre line instead of
            //    its bottom. A zero-height box also means the row's own
            //    height never depends on the bubble's copy, so no step
            //    advance can nudge the feed below it.
            // Repositioned (2026-09-29 follow-up, reverted second pass) —
            // growing fully leftward from the ring's centre (previous pass)
            // ran the box off the LEFT edge of the screen entirely (the
            // ring sits only ~70pt from the screen's own left edge, nowhere
            // near enough room for a 230pt-wide box to grow into), clipping
            // the longest copy. Back to growing UP-RIGHT (box's leading
            // edge anchored near the ring, content left-aligned — plenty of
            // screen width in that direction) but shifted 20pt further
            // LEFT than the ring's exact centre so the box overlaps the
            // ring slightly, per this pass's own explicit request. Tail
            // unchanged, at the bubble's own bottom-leading corner
            // (`Triangle`'s own `.overlay(alignment: .bottomLeading)` in
            // PulseTeaserBubbleContent).
            .overlay(alignment: .topLeading) {
                if app.pulseTeaserStep >= 0 {
                    PulseTeaserBubbleContent(
                        step: app.pulseTeaserStep,
                        onTap: { app.pulseTeaserAdvance?() },
                        onOpenFeaturedPhotos: { app.pulseTeaserOpenPhotos?() }
                    )
                    .frame(width: Self.pulseBubbleMaxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 0, alignment: .bottom)
                    .padding(.leading, Self.pulseRingMidXInRow - 20)
                    .padding(.top, Self.pulseRingMidYInRow)
                }
            }
        }
        // The bubble is anchored at the ring's centre and grows UPWARD, so
        // the tallest copy this sequence shows (the 3-line ranked list)
        // reaches above the row's own top edge. Without this, the horizontal
        // scroller would clip it to its own bounds; disabling that clip is
        // the "not clipped by the horizontal story row" requirement, and it
        // can only ever affect the bubble itself — nothing else in this row
        // draws outside it. Still clipped by the feed's own vertical
        // ScrollView as it scrolls away, exactly like the ring.
        .scrollClipDisabled()
        // The story row owns horizontal scrolling. Register its real bounds
        // (the scroller itself — before the top clearance padding below) in
        // the same root coordinate space tabSwipeGesture uses, exactly like
        // "Your events" does, so a swipe that starts on a story ring scrolls
        // the row and never commits Home -> Map.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: RootGestureExclusionZonePreferenceKey.self,
                    value: ["homeStories": geo.frame(in: .named("rootGesture"))]
                )
            }
        }
        // Extra top clearance (2026-09-29 follow-up, real-device report) —
        // the teaser bubble grows upward from the ring's centre (see the
        // comment above) and, when little/nothing renders above this row
        // (e.g. an empty Action Center), had no room to grow into: it
        // reached above this screen's own header and rendered over the
        // "home" title. This row (Pulse ring + its bubble) is shifted down
        // by that much extra so the bubble's tallest content (the 3-line
        // ranked list) is always fully clear of the header above, without
        // changing the bubble's own top-left/pointer-at-bottom-left design.
        .padding(.top, 65)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    /// Section 5 — public survey discovery. Source-of-discovery pass —
    /// `app.homeSurveyDiscovery` is now loaded directly from
    /// `get_public_survey_discovery()` (`loadHomeSurveyDiscovery()`,
    /// AppState+Surveys.swift) — every PUBLISHED, currently-open public
    /// survey, whether or not it was ever shared to a story, one row per
    /// DISTINCT survey id (never collapsed by organizer — the same host can
    /// have several rows). Tapping a row opens the same in-app response
    /// modal a story's own "Answer Survey" CTA does.
    /// Visibility-investigation fix — ALWAYS rendered (header + one of
    /// loading/error/empty/rows), not only when rows already exist, so a
    /// real load failure is never indistinguishable from the section
    /// simply not existing.
    ///
    /// Collapse/expand pass — collapsed by default (`app.homeSurveyDiscoveryExpanded`,
    /// lives on AppState, not local `@State`, so it isn't lost across a trip
    /// into the survey modal and back — see that field's own doc comment).
    ///
    /// Compact-vertical-list pass — replaces the previous horizontal
    /// carousel entirely. A `LazyVStack` inside HOME'S OWN existing vertical
    /// scroll (no nested scroll view of any kind), initially showing only
    /// the first 3 loaded rows with a "Show More" control below (distinct
    /// from `homeSurveyDiscoveryHasMore`, the REAL signal for "more exist on
    /// the server" — see `visibleSurveyDiscoveryCount`'s own doc comment for
    /// why these two are never conflated).
    private var surveyDiscoveryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { app.homeSurveyDiscoveryExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(app.T("Góp ý cho sự kiện sắp tới", "Help Shape Upcoming Events"))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                    if !app.homeSurveyDiscoveryLoading && app.homeSurveyDiscoveryError.isEmpty && !app.homeSurveyDiscovery.isEmpty {
                        // Honest LOADED count, never a fabricated total —
                        // "+" only when the server told us more exist
                        // (`hasMore`), never guessed from a page-size cap.
                        Text(app.homeSurveyDiscoveryHasMore ? "\(app.homeSurveyDiscovery.count)+" : "\(app.homeSurveyDiscovery.count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(app.palette.ink.opacity(0.1), in: Capsule())
                            .foregroundStyle(app.palette.ink.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.5))
                        .rotationEffect(.degrees(app.homeSurveyDiscoveryExpanded ? 180 : 0))
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.surveyDiscoveryToggle")

            if app.homeSurveyDiscoveryExpanded {
                if app.homeSurveyDiscoveryLoading && app.homeSurveyDiscovery.isEmpty {
                    Text(app.T("Đang tải…", "Loading…")).font(.system(size: 12)).opacity(0.6).padding(.horizontal, 20)
                } else if !app.homeSurveyDiscoveryError.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.homeSurveyDiscoveryError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                        Button(app.T("Thử lại", "Retry")) { Task { await app.loadHomeSurveyDiscovery() } }
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                } else if app.homeSurveyDiscovery.isEmpty {
                    Text(app.T("Chưa có khảo sát công khai nào.", "No public surveys right now."))
                        .font(.system(size: 12)).opacity(0.6).padding(.horizontal, 20)
                } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(app.homeSurveyDiscovery.prefix(visibleSurveyDiscoveryCount)) { card in
                        surveyDiscoveryCardRow(card)
                    }
                    if visibleSurveyDiscoveryCount < app.homeSurveyDiscovery.count || app.homeSurveyDiscoveryHasMore {
                        Button {
                            Task { await revealMoreSurveyDiscovery() }
                        } label: {
                            HStack(spacing: 6) {
                                if app.homeSurveyDiscoveryLoadingMore { ProgressView().controlSize(.small) }
                                Text(app.T("Xem thêm", "Show More"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        .disabled(app.homeSurveyDiscoveryLoadingMore)
                        .accessibilityIdentifier("home.surveyDiscoveryShowMore")
                    }
                }
                .padding(.horizontal, 20)
                // Gesture fix — the WHOLE expanded list's real screen-space
                // bounds, published only while actually in the tree
                // (expanded, this branch), measured in the SAME named
                // coordinate space `tabSwipeGesture` itself now uses
                // (RootView.swift's `.coordinateSpace(name: "rootGesture")`)
                // instead of `.global` — see that modifier's own doc
                // comment for why a plain `.global`/`.local` pairing was the
                // real cause of the earlier real-device failure. A vertical
                // OR diagonal drag starting anywhere in this list now hands
                // off to Home's own scroll entirely, for the gesture's whole
                // duration — it can never commit a tab change.
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RootGestureExclusionZonePreferenceKey.self,
                            value: ["surveyDiscovery": geo.frame(in: .named("rootGesture"))]
                        )
                    }
                )
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// How many of the already-loaded `app.homeSurveyDiscovery` rows are
    /// currently rendered — deliberately a SEPARATE number from both the
    /// array's own `.count` and `app.homeSurveyDiscoveryHasMore` (the real
    /// "more exist on the server" signal), so a preview-row cap is never
    /// confused with the true total. "Show More" first reveals rows already
    /// in memory (no network call) and only fetches a real next page once
    /// every loaded row is already visible — see `revealMoreSurveyDiscovery()`.
    @State private var visibleSurveyDiscoveryCount = 3

    private func revealMoreSurveyDiscovery() async {
        if visibleSurveyDiscoveryCount < app.homeSurveyDiscovery.count {
            visibleSurveyDiscoveryCount += 10
            return
        }
        await app.loadMoreHomeSurveyDiscovery()
        visibleSurveyDiscoveryCount = app.homeSurveyDiscovery.count
    }

    /// One compact row: small avatar, one-line title, a single metadata
    /// line (host · deadline) using the app's solid-square separator glyph,
    /// never a bullet/dash/large clock — content-driven height (no fixed
    /// frame), ~60–76pt at standard text size. The ENTIRE row is one big
    /// tap target (no repeated "Answer Survey" button inside it); the
    /// accessibility label states the action explicitly for VoiceOver.
    @ViewBuilder
    private func surveyDiscoveryCardRow(_ card: SurveyDiscoveryCard) -> some View {
        Button {
            Task { await app.openSurveyStoryModal(publicID: card.publicId) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                surveyDiscoveryAvatar(card)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        Text(card.hostName)
                        if let closesAt = card.closesAt {
                            // Solid small square separator — decorative,
                            // hidden from accessibility (never a bullet/
                            // dash, per this ticket's own convention).
                            Rectangle()
                                .fill(app.palette.ink.opacity(0.35))
                                .frame(width: 3, height: 3)
                                .accessibilityHidden(true)
                            Text("\(app.T("Hạn", "Deadline")): \(closesAt.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    // No `.lineLimit` here — lets this line wrap onto a
                    // second line at larger Dynamic Type sizes instead of
                    // truncating/clipping.
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.35))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.surveyDiscoveryCard")
        .accessibilityLabel(
            card.closesAt != nil
                ? app.T(
                    "Trả lời khảo sát: \(card.title), tổ chức bởi \(card.hostName), hạn \(card.closesAt!.formatted(date: .abbreviated, time: .omitted))",
                    "Answer survey: \(card.title), hosted by \(card.hostName), deadline \(card.closesAt!.formatted(date: .abbreviated, time: .omitted))"
                )
                : app.T("Trả lời khảo sát: \(card.title), tổ chức bởi \(card.hostName)", "Answer survey: \(card.title), hosted by \(card.hostName)")
        )
    }

    /// 28×28 — a real avatar when resolved, the host's own initial as a
    /// deliberate fallback otherwise (never a blank circle), through the
    /// SAME cache/loader (`RemoteImage`/`PhotoLoader`) every other photo in
    /// this app already uses — no URL churn, no duplicate downloads.
    @ViewBuilder
    private func surveyDiscoveryAvatar(_ card: SurveyDiscoveryCard) -> some View {
        ZStack {
            Circle().fill(app.palette.ink.opacity(0.1))
            Text(String((card.hostName.isEmpty ? "?" : card.hostName).prefix(1)).uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(app.palette.ink)
            if let url = card.hostAvatarURL {
                RemoteImage(path: url.absoluteString, maxPixel: 56)
                    .clipShape(Circle())
            }
        }
        .frame(width: 28, height: 28)
    }

    /// The Pulse ring's centre point inside `storyRow`'s own content space —
    /// see that row's own comment for how these two numbers are derived from
    /// its layout constants (`padding(.horizontal, 20)`, the 60pt-wide ring
    /// column, and the 56x56 glyph at the top of that column). Named rather
    /// than inlined so the bubble's anchor and the row that has to satisfy it
    /// stay visibly in sync.
    /// The widest any step's copy is allowed to be, i.e. the width of the
    /// bubble's own layout box in `storyRow` (which is why the copy wraps
    /// here rather than running off the trailing edge of the screen): the
    /// bubble's leading edge sits 50pt into the row, so 230 + 50 stays
    /// inside even a 375pt-wide iPhone.
    private static let pulseBubbleMaxWidth: CGFloat = 230
    private static let pulseRingMidXInRow: CGFloat = 50
    // Shifted down from the ring's own vertical centre (28) so the
    // bubble's bottom (it grows UPWARD from this anchor) now dips down
    // just enough to barely overlap the "Banbe Pulse" label under the
    // ring, per this pass's explicit request.
    private static let pulseRingMidYInRow: CGFloat = 10

    /// Matches the web strip's tag rules: cancelled / past / on hold /
    /// paid / saved, each with its own chip colour.
    private func savedTag(_ event: CatalogEvent) -> (String, Color) {
        if event.cancelled { return ("Đã hủy", BanbeTheme.Chip.cancelled) }
        if event.endedHoursAgo != nil { return ("Đã diễn ra", BanbeTheme.Chip.past) }
        if event.key == app.heldEvent?.key { return ("Đang giữ", BanbeTheme.Chip.hold) }
        if let phase = reminderPhase(event) {
            return (phase == .live ? "Đang diễn ra" : "Sắp diễn ra", BanbeTheme.Chip.reminder)
        }
        if app.isGoing(event.key) { return ("Đã thanh toán", BanbeTheme.Chip.going) }
        return ("Đã lưu", BanbeTheme.Chip.saved)
    }

    /// Reminder only for a ticket-holder's own event (not a hold, not merely saved).
    private func reminderPhase(_ event: CatalogEvent) -> EventReminder.Phase? {
        guard app.isGoing(event.key), event.key != app.heldEvent?.key,
              !event.cancelled, event.endedHoursAgo == nil else { return nil }
        return EventReminder.phase(startsAt: event.startDate)
    }

    private func savedStatus(_ event: CatalogEvent) -> String {
        let tix = app.tickets[event.key] ?? 1
        let suffix = tix > 1 ? " ▪︎ \(tix) vé" : ""
        if event.cancelled { return "Đã hoàn tiền" }
        if let ended = event.endedHoursAgo { return EventLabels.ago(ended) }
        if event.key == app.heldEvent?.key { return "Trả để xác nhận" + suffix }
        if app.isGoing(event.key) { return event.untilLabel + suffix }
        return event.untilLabel
    }

    // MARK: Filters

    /// Two filter rows (categories on top, status chips below), each its OWN
    /// horizontal ScrollView so they swipe independently. Like the "Your
    /// events" strip, each row registers its real bounds as a root-gesture
    /// exclusion zone, so a swipe starting on either row scrolls the chips
    /// and never commits Home -> Map.
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterRow(zone: "homeFilterCategories") { filterTabs }
            statusFilterRow
            if app.filterForYou && app.hasForYouMatches { forYouEditRow }
        }
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    /// Second row: For You pinned at the leading edge (never scrolls, never shrinks);
    /// the remaining chips scroll on their own to its right, registered as the same
    /// root-gesture exclusion zone as before. The ScrollView keeps one stable position
    /// whether or not For You is shown (no remount, offset preserved). HStack's leading
    /// edge follows the layout direction (RTL-safe).
    private var statusFilterRow: some View {
        let hasForYou = app.hasForYouMatches
        return HStack(spacing: 8) {
            if hasForYou {
                forYouChip
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.leading, 20)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                homeExtraFilterChips
                    .padding(.leading, hasForYou ? 0 : 20)
                    .padding(.trailing, 20)
            }
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: RootGestureExclusionZonePreferenceKey.self,
                        value: ["homeFilterStatus": geo.frame(in: .named("rootGesture"))]
                    )
                }
            }
        }
    }

    private func observeForYouAlert() {
        let matches = app.forYouMatches.map { m in
            ForYouAlertMatch(id: m.key, version: app.discoveryAlertVersions[m.key] ?? "")
        }
        forYouAlert.observe(userID: app.userID?.uuidString, matches: matches,
                            prefsVersion: app.eventPrefsVersion,
                            loading: app.discoveryEventsLoading || app.eventPrefs == nil)
    }

    private func filterRow<Content: View>(zone: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content().padding(.horizontal, 20)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: RootGestureExclusionZonePreferenceKey.self,
                    value: [zone: geo.frame(in: .named("rootGesture"))]
                )
            }
        }
    }

    private var filterTabs: some View {
        HStack(spacing: 8) {
                ForEach(filters, id: \.key) { filter in
                    let active = app.filter == filter.key
                    SwipeSafeButton {
                        if app.filter != filter.key { Haptics.selection() }
                        app.pickFilter(filter.key)
                    } label: {
                        Text(app.T(filter.vi, filter.en))
                            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                            .background { homeGlassCapsule(active: active) }
                            .overlay(Capsule().stroke(active ? .clear : app.palette.rule.opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter.\(filter.key)")
                }
        }
        .foregroundStyle(app.palette.ink)
    }

    // Second, independent chip row (12-home-filters.md) — multi-select,
    // AND-combined with filterTabs' category row and the area picker, not a
    // third incompatible filter system: each reuses an existing definition
    // (isGoing's status set from note 04, isSaved's favorites, .soldOut's
    // static catalogue flag) rather than recomputing any of them.
    //
    // 2026-09-21 follow-up — extended with notConfirmed/upcoming/ended
    // (mirrors src/screens/Home.jsx's HOME_EXTRA_FILTERS exactly).
    //
    // Second follow-up (same day): notAttending/notSaved removed entirely
    // per this ticket's own instruction; Upcoming/Saved/Attending reordered
    // to lead, Ended kept last. Also switched from a horizontally-scrolling
    // `ScrollView` to `FlowLayout` (MapExploreView.swift's own reusable
    // wrapping layout, already used for Map Explore's category row) — every
    // chip is now always visible, wrapping to a second line instead of
    // requiring a swipe to see the rest.
    private var homeExtraFilterChips: some View {
        let chips: [(key: String, vi: String, en: String, active: Bool)] = [
            ("upcoming", "Sắp diễn ra", "Upcoming", app.filterUpcoming),
            ("saved", "Đã lưu", "Saved", app.filterSaved),
            ("attending", "Đang tham gia", "Attending", app.filterAttending),
            ("notConfirmed", "Chưa xác nhận", "Not confirmed", app.filterNotConfirmed),
            ("soldOut", "Hết chỗ", "Sold out", app.filterSoldOut),
            ("ended", "Đã kết thúc", "Ended", app.filterEnded),
        ]
        return HStack(spacing: 8) {
            ForEach(chips, id: \.key) { chip in
                SwipeSafeButton {
                    Haptics.selection()
                    app.toggleHomeFilter(chip.key)
                } label: {
                    Text(app.T(chip.vi, chip.en))
                        .font(.system(size: 12, weight: chip.active ? .bold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(chip.active ? app.palette.paper : app.palette.ink)
                        .background { homeGlassCapsule(active: chip.active) }
                        .overlay(Capsule().stroke(chip.active ? app.palette.ink : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filter.\(chip.key.lowercased())")
            }
        }
        .foregroundStyle(app.palette.ink)
    }

    /// Quick shortcut while For You is active: edit the answers, and Back /
    /// swipe-back returns here with For You still on (`eventPrefsReturnScreen`).
    private var forYouEditRow: some View {
        Button {
            Haptics.selection()
            app.openEventPreferences(returnTo: .home)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                Text(app.T("Chỉnh câu trả lời của bạn", "Edit my answers"))
                    .font(.system(size: 12.5, weight: .semibold)).underline()
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("foryou.editAnswers")
    }

    /// Gold-star "For You" chip — only rendered when `hasForYouMatches`.
    private var forYouChip: some View {
        let gold = Color(red: 0.80, green: 0.62, blue: 0.16)
        let active = app.filterForYou
        return SwipeSafeButton {
            Haptics.selection()
            if !app.filterForYou { forYouAlert.acknowledge(loadedIDs: app.forYouMatches.map(\.key)) }
            app.toggleHomeFilter("forYou")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? app.palette.paper : gold)
                Text(app.T("Dành cho bạn", "For You"))
                    .font(.system(size: 12, weight: active ? .bold : .regular))
                    .lineLimit(1)
                if forYouAlert.hasPending {
                    // White on #7A5200 = ~6.9:1 (AA); static, retained until acknowledged.
                    Text(app.T("Mới", "New"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 0.478, green: 0.322, blue: 0)))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
            .background { homeGlassCapsule(active: active) }
            .overlay(Capsule().stroke(active ? app.palette.ink : gold.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(ForYouAttentionEffect(animating: forYouAlert.animating && forYouAlert.hasPending, reduceMotion: reduceMotion))
        .accessibilityIdentifier("filter.foryou")
        .accessibilityLabel(forYouAlert.hasPending && !active
            ? app.T("Dành cho bạn, có gợi ý mới", "For You, new recommendations")
            : app.T("Dành cho bạn", "For You"))
    }

    /// Never leave a stale empty "For You" list: once data has settled, a
    /// vanished match set (prefs edited, area changed) clears the filter.
    private func resetForYouIfStale() {
        guard app.filterForYou, !app.discoveryEventsLoading, !app.hasForYouMatches else { return }
        app.filterForYou = false
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(app.T(
                "Chưa có buổi nào ở \(app.area == LocationHierarchy.allID ? "mục này" : app.currentAreaLabel) tuần này, thử mục khác xem sao!",
                "Nothing in \(app.area == LocationHierarchy.allID ? "this category" : app.currentAreaLabel) this week, try another one!"
            ))
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            Button(app.T("Xem tất cả", "See all")) { app.clearFilters() }
                .font(.system(size: 12.5))
                .buttonStyle(.plain)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(app.palette.rule).frame(height: 1)
            Text(app.T("Hết rồi, ra ngoài chơi thôi!", "That's it, go have fun!"))
                .font(BanbeTheme.display(11.5))
                .padding(.top, 34)
            Text(app.T(
                "Vài buổi vui dành cho riêng bạn tuần này. Không xếp hạng, không quảng cáo, không lướt vô tận.",
                "A few fun gatherings made just for you this week. No ratings, no ads, no endless scrolling."
            ))
            .font(.system(size: 11))
            .padding(.top, 12)
            .padding(.horizontal, 20)
        }
        .foregroundStyle(app.palette.ink)
        .multilineTextAlignment(.center)
    }

    /// Retention roadmap P1 ("Cuối tuần này") — real live+public events for
    /// the applicable weekend (app.weekendEvents), never demo cards. Placed
    /// after the main feed (not the "Sự kiện của bạn" strip near the top)
    /// on purpose: it's a discovery section, not a personal one. Reuses
    /// `EventCard` — the exact same view every catalogue card in the main
    /// feed already uses — since `CatalogEvent.fromReal` shapes a real row
    /// into the same type; no separate rendering path to keep in sync.
    private var weekendSection: some View {
        Group {
            if !app.weekendEvents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.T("Cuối tuần này", "This weekend"))
                        .font(BanbeTheme.display(15))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                    ForEach(app.weekendEvents) { event in
                        EventCard(event: event)
                            .id("weekend-\(event.key)")
                    }
                }
            } else if !app.weekendEventsLoading {
                // Quiet empty state — no demo cards, never invented.
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.T("Cuối tuần này", "This weekend"))
                        .font(BanbeTheme.display(15))
                    Text(app.T("Chưa có sự kiện phù hợp cuối tuần này.", "No matching events this weekend yet."))
                        .font(.system(size: 12.5))
                        .opacity(0.7)
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    private var hostLink: some View {
        SwipeSafeButton {
            if app.hasHosted { app.switchToHost() } else { app.goHostIntro() }
        } label: {
            Text((app.hasHosted
                  ? app.T("Trang tổ chức của bạn", "Your host page")
                  : app.T("Dành cho người tổ chức ▪︎ hoàn toàn miễn phí", "For organizers ▪︎ completely free")) + " ›")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(app.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }
}

/// One feed card — hero photo with the Save/Going chips over it, then the
/// name, meta line and price/seats, as on the web feed.
struct EventCard: View {
    let event: CatalogEvent
    @EnvironmentObject private var app: AppState

    var body: some View {
        SwipeSafeButton { app.goEvent(event.key) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    CatalogPhoto(path: event.img, height: 272, cornerRadius: 14)
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [app.palette.paper.opacity(0), app.palette.paper],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 58)
                        }
                    SwipeSafeButton { app.toggleFavorite(event.key) } label: {
                        PhotoChip(
                            text: app.isSaved(event.key) ? app.T("Đã lưu", "Saved") : app.T("Lưu", "Save"),
                            background: app.isSaved(event.key) ? BanbeTheme.Chip.going : app.palette.paper.opacity(0.62),
                            foreground: app.isSaved(event.key) ? .white : app.palette.ink
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(12)

                    if app.isGoing(event.key) && event.isOpen {
                        PhotoChip(text: app.trStatus("Đang tham gia"), background: BanbeTheme.Chip.going)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.name).font(BanbeTheme.display(22))
                        Text(app.metaLine(for: event)).font(.system(size: 12.5))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(app.trStatus(event.price)).font(.system(size: 13))
                        Text(app.seatsLabel(for: event))
                            .font(.system(size: 11.5))
                            .multilineTextAlignment(.trailing)
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.\(event.key)")
    }
}

// Task 1 (2026-09-22 twelfth follow-up) — see AppState.swift's own comment
// on storyRingFrames for why this exists (StoryViewerView's expand/shrink-
// toward-ring transition). Internal (not `private`) — StoryViewerView.swift
// only reads `app.storyRingFrames` itself, never this key directly, but the
// `.onPreferenceChange` call above needs it visible from HomeView's body.
struct StoryRingFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Survey-strip gesture fix — see `AppState.rootGestureExclusionZones`'s own
/// doc comment. Same shape/merge rule as `StoryRingFramePreferenceKey`
/// above, kept as a separate key (not a reuse of that one) since the two
/// track unrelated things — ring-frame lookups by organizer id vs.
/// gesture-exclusion zones by row id — and conflating them would make
/// either one's future changes risk the other's behavior.
struct RootGestureExclusionZonePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// TASK 3 (2026-10-05 fix pass) — replaces the Pulse ring's static two-tone
/// gradient + plain "✦" with a refined multicolor shimmer, still built
/// entirely from Banbe's own existing dusty-rose/sage palette (the same two
/// colors the old `LinearGradient` used, plus one warm sand tone already in
/// that same muted family — never a saturated rainbow). `hueRotation`
/// slowly cycling an `AngularGradient` is one continuous system-driven
/// animation, not a per-frame `Timer`/`TimelineView` redraw loop — cheap
/// for a 56×56 view and, since `HomeView` (the only place this is used) is
/// swapped out of the screen-switch entirely on navigation, it stops
/// running the instant Home isn't the visible screen, with no extra
/// visibility plumbing needed. `scenePhase` still pauses it explicitly
/// while backgrounded, and Reduce Motion skips starting it at all, leaving
/// the gradient's own resting frame — still colorful, just not moving — as
/// the "beautiful static state" this ticket asks for.
private struct PulseRingGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rotate = false

    private static let colors: [Color] = [
        Color(red: 0.91, green: 0.79, blue: 0.76), // dusty rose — the old gradient's own first stop
        Color(red: 0.87, green: 0.75, blue: 0.62), // warm sand — a third stop in the same muted family
        Color(red: 0.78, green: 0.80, blue: 0.70), // sage — the old gradient's own second stop
    ]

    var body: some View {
        ZStack {
            AngularGradient(colors: Self.colors + [Self.colors[0]], center: .center)
                .hueRotation(.degrees(rotate ? 360 : 0))
            Text("✦")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .white.opacity(0.5), radius: 3)
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onAppear { startIfEligible() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startIfEligible() } else { rotate = false }
        }
        .onChange(of: reduceMotion) { _, _ in startIfEligible() }
    }

    private func startIfEligible() {
        guard !reduceMotion, scenePhase == .active else { rotate = false; return }
        withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { rotate = true }
    }
}

/// Home's search button — top-right of the fixed header, always visible
/// (it no longer floats above the dock or hides when the feed scrolls), in a
/// larger Liquid Glass circle so it reads clearly against the paper.
struct HomeSearchButton: View {
    @EnvironmentObject private var app: AppState

    private static let size: CGFloat = 52

    var body: some View {
        SwipeSafeButton {
            Haptics.light()
            app.openEventSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(app.palette.ink)
                .frame(width: Self.size, height: Self.size)
                .background { glass }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.searchFab")
        .accessibilityLabel(app.T("Tìm sự kiện", "Search events"))
    }

    @ViewBuilder
    private var glass: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        } else {
            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().strokeBorder(app.palette.ink.opacity(0.10)))
                .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 4)
        }
    }
}

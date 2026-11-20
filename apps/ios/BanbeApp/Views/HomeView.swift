import SwiftUI
import UIKit

/// Home's area control is a native `Menu` mounted inline on this header
/// (see `header` below), so nothing needs to know where it sits on screen any
/// more: the former HomeAreaFramePreferenceKey existed only to feed the
/// removed AreaSheetView's anchored placement math, and is gone with it.

/// The feed — a port of src/screens/Home.jsx (note 50 discovery layout): header (wordmark + title, rewards
/// capsule, bell), location pill, full-width search bar, Next-up reminder, Action Center, stories, category
/// tiles, quick row (Filters / Sort / For You / one-tap chips), "Upcoming · N" with a cards/list switch, the
/// feed, relax hints, the "This weekend" rail, surveys and the host link.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    /// Simple Shell's goer hero needs the checklist's own visibility rule (it reads the Face ID setting).
    @EnvironmentObject private var auth: AuthViewModel
    /// Chip text: 13pt at the default size, growing with Dynamic Type (it used to stay 13pt at every size).
    @ScaledMetric(relativeTo: .footnote) private var chipFont: CGFloat = 13
    /// The "Show all" category sheet (every category A–Z with its count).
    @State private var categorySheetOpen = false
    @State private var quickSheetOpen = false
    @State private var pinnedHeaderHeight: CGFloat = HomeHeroPinnedHeader.fallbackHeight
    @Environment(\.scenePhase) private var scenePhase
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()
    /// Bumped each time Home becomes the visible screen; replays the reminder halo.
    @State private var reminderHaloTrigger = 0
    /// The area menu's own "Search locations…" row opens the searchable
    /// location list — a native `Menu` can't host a text field, so this is
    /// where typing a place name still works. See `LocationPickerSheet`.
    @State private var areaSearchOpen = false
    /// Note 80: the photo hero's tab (Going out, Simple Shell). Hosting is the other Home view, not a value here.
    @State private var heroTab: HomeHeroTab = .foryou
    /// v2.3 (note 81): the live line's shown update (Reduced form) and the Live now sheet.
    @State private var liveIndex = 0
    @State private var liveNowOpen = false
    /// Note 99: the "All types" sheet of the unified type tiles.
    @State private var udTypeSheetOpen = false
    /// Prototype v2 (note 99): "See all" on the rail scrolls Home to the "Near you" list.
    @State private var nearYouScrollToken = 0
    @StateObject private var forYouAlert = ForYouAlertModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Note 50 — cards (default) or a compact list; a per-device convenience, like web's localStorage.
    @AppStorage("banbe.homeLayout.v1") private var layoutMode = "cards"

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
        sortActionCenterItems(goerActionItems + (app.canHost ? hostActionItems : []))
    }

    /// The goer half of Things to do (Simple Shell's goer hero shows only these: mode decides content).
    private var goerActionItems: [ActionCenterItem] {
        buildActionCenterItems(ActionCenterInputs(
            role: .goer, now: tick,
            myHolding: app.myHolding, myPendingVerification: app.myPendingVerification, myAdminInvite: app.myAdminInvite, myRefunds: app.myRefunds,
            refundDestinations: app.refundDestinationsLoaded ? app.refundDestinations : nil,
            onOpenPayment: { app.openPaymentDetails($0, back: .home) },
            onOpenMyRefunds: { app.openMyRefunds(back: .home) },
            onOpenAdminInvite: { app.accountGroupKey = "adminTeam"; app.screen = .accountGroup },
            onOpenRefundAccounts: { app.openRefundAccounts(back: .home) },
            // "Refund dispute open › View" goes to the booking conversation
            // that dispute actually belongs to, with its card expanded.
            onOpenRefundDispute: { claimID, back in app.openRefundDisputeFromActionCenter(claimID: claimID, back: back) },
            T: app.T
        ))
    }

    /// The host half (Simple Shell's host Home shows these).
    private var hostActionItems: [ActionCenterItem] {
            buildActionCenterItems(ActionCenterInputs(
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

    var body: some View {
        // Scroll-restore fix (2026-11-16, owner report: "while scrolling up
        // or down and stopping, the screen refreshes by itself and shifts to
        // another Home section with a laggy animation") — Home used to hand
        // `ScreenScaffold` a `scrollPositionID` as well as `restoreOffsetY`,
        // so TWO mechanisms drove this feed's offset. `.scrollPosition(id:)`
        // is bidirectional: it records the id SwiftUI finds at its `.center`
        // anchor on every pass AND scrolls back to that id whenever the bound
        // value is (re)applied — which happened on any later body pass or
        // content reflow (photos finishing, a load landing, the id flipping
        // nil↔card near the top). The result was the feed animating itself
        // to centre some other card right as the swipe settled, and then the
        // exact-offset restore below yanking it back: the "refresh + shift"
        // with a laggy animation. Home now restores by exact offset only
        // (`restoreOffsetY`, the same mechanism note 69 chose for Account's
        // rows because an id anchor restores CENTRED, never exactly), so
        // nothing re-drives this scroll view after the user's own scroll.
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
        #if DEBUG
        let _ = { if UITestFixture.isActive { UITestFixture.homeBodies += 1 } }()
        #endif
        let snap = makeSnapshot()
        ZStack {
            app.palette.paper.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
            activeHeader.revealRegion(0)
            // L5 weekly digest: its notification asks for the "This weekend" rail (AppState.goHomeThisWeekend).
            ScrollViewReader { weekendProxy in
            ScreenScaffold(tracksBottomBarScroll: true, restoreOffsetY: app.homeScrollOffsetY, onScrollOffset: { app.homeScrollOffsetY = $0; HomeHeaderCompact.shared.update(offsetY: $0) }, scrollToTopToken: app.homeScrollToTopToken, scrollRequest: app.homeTourScrollRequest, pullAnchorTop: app.simpleShellEnabled ? heroBandRoom : 0, onRefresh: {
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
                // Pinned section headers (unified discovery): "Browse by type" and "Near you" stick under the folded band.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Simple Shell (note 66, switch simple_shell): one hero per mode. OFF renders the feed below unchanged.
                    if app.simpleShellEnabled {
                        if hostHome {
                            // Hosting is a 4th tab of the same hero (no card rail); the host sections swap in under it.
                            HomeHeroSection(tab: $heroTab, lists: snap.heroLists, onSeeAll: { heroSeeAll($0) },
                                            onSearchLocations: { areaSearchOpen = true },
                                            onAvatar: { quickSheetOpen = true },
                                            headerHeight: heroBandRoom)
                                .id(true)   // distinct from the Going out hero: a lazy stack reuses a node by its outer id
                                .id("home.tour.hero")
                                .revealRegion(0)
                            HostHomeSections(actionItems: sortActionCenterItems(hostActionItems)).revealRegion(1)
                        } else {
                            simpleGoerFeed(snap, proxy: weekendProxy)
                        }
                    } else {
                    // Note 50/51 order: Pulse ticker → Next-up (note-37 reminder only) → Action Center / guest banner → stories (only if any) →
                    // categories → quick row → "Upcoming · N" → feed → hints → empty/footer → weekend → surveys.
                    // The old "Your events" strip and status chips are gone (Schedule + Account own your events).
                    // Banbe Pulse: one slim ticker line (note 51), replacing the big tile in the story row.
                    // Note 64: `.revealRegion(n)` = the sign-in reveal order (header 0, summary 1, feed 2, dock 3).
                    PulseTickerView().padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6).revealRegion(1)
                    if let next = nextUp {
                        NextUpBanner(event: next.event, phase: next.phase, haloTrigger: reminderHaloTrigger).revealRegion(1)
                    }
                    if app.isSignedIn, !savedUpcoming.isEmpty { savedUpcomingSection.revealRegion(1) }
                    if app.isSignedIn {
                        ActionCenterView(items: actionItems, onSeeAll: { app.goNotifications() }).revealRegion(1)
                        ActivationChecklistCard().revealRegion(1)
                    } else {
                        GuestBrowseBanner()
                    }
                    if !app.homeStories.isEmpty { storyRow.revealRegion(1) }
                    HomeCategoryRow(keys: snap.categoryRow, counts: snap.categoryCounts, onShowAll: { categorySheetOpen = true })
                        .revealRegion(2)
                    quickRow(snap)
                        // One scrolling row of capsules: let it grow, but not past the size where a chip still fits.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                        .revealRegion(2)
                    if !snap.typeChips.isEmpty {
                        typeChipRow(snap)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                            .revealRegion(2)
                    }
                    if app.filterForYou && app.hasForYouMatches { forYouEditRow.padding(.bottom, 4).revealRegion(2) }
                    sectionHeader(snap).revealRegion(2)
                    ForEach(snap.cards) { card in
                        Group {
                            if layoutMode == "list" { DiscoveryRow(model: card) } else { DiscoveryCard(model: card) }
                        }
                        .revealRegion(2)
                        .modifier(FirstCardTourTarget(isFirst: card.key == snap.cards.first?.key))
                        .id(card.key)
                    }
                    // Requirements are soft: when filters leave almost nothing, offer the one change that adds the most.
                    if !snap.relaxHints.isEmpty && !snap.items.isEmpty { relaxHintsRow(snap.relaxHints) }
                    if snap.cards.isEmpty { emptyState } else { footer }
                    if app.homeFilters.date != "weekend" { weekendSection.id("home.weekend") }
                    // Survey discovery is authenticated-only server-side
                    // (get_public_survey_discovery); hide it for guests.
                    if app.isSignedIn { surveyDiscoveryRow }
                    }
                }
                .padding(.bottom, BottomTabBar.contentClearance)
            }
            // The scroll view's top edge (its own origin for the pinned-header hairline check)…
            .coordinateSpace(name: HomePinnedSectionHeader.space)
            // …starts under the folded band (Simple Shell), so pinned section headers stick right below it, never under it.
            // The hero keeps the rest of the band's room (`heroBandRoom`) and draws its backdrop past this edge (the
            // scroll view does not clip), so the screen at rest is unchanged and scroll offsets mean what they did.
            .padding(.top, scrollTopShift)
            .task(id: app.homeWeekendScrollRequest) { await scrollToWeekendIfAsked(weekendProxy) }
            // Prototype v2's rail end card: "See all" scrolls Home down to the "Near you" list, not into Browse. Observed
            // here (the reader's level), never inside the lazy feed, whose later rows may not be built yet.
            // The anchor lands on the scroll view's top edge, which is the folded band's bottom edge: with unified
            // discovery that is where the "Near you" header pins; otherwise the heading lands 12 pt below the band.
            .onChange(of: nearYouScrollToken) { _, _ in
                let wasCompact = HomeHeaderCompact.shared.isCompact
                let anchor = UnitPoint.top
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    weekendProxy.scrollTo("home.nearYou", anchor: anchor)
                }
                // Scrolling from the top folds the band on the way, and the hero gives back the tabs' 44 pt mid-flight,
                // so the target moved under the scroll. One plain re-align once the fold has settled (only then).
                guard !wasCompact else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    weekendProxy.scrollTo("home.nearYou", anchor: anchor)
                }
            }
            .environment(\.scaffoldClipsContent, homeClipsContent)
            // Note 64: the v3 tour's event-card step brings the first card into view (a scroll, nothing else).
            .onReceive(OnboardingTourController.shared.$scrollRequest.dropFirst()) { _ in
                let target = OnboardingTourController.shared.scrollTarget
                let id: String? = target == "event" ? snap.cards.first?.key : target
                guard let id else { return }
                let anchor: UnitPoint = target == "home.tour.hero" ? .top : .center
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { weekendProxy.scrollTo(id, anchor: anchor) }
            }
            // The tour asks for a hero tab (For You on step 1, Tonight on its "do it" tap).
            .onReceive(OnboardingTourController.shared.$heroTabRequest.compactMap { $0 }) { heroTabBinding.wrappedValue = $0 }
            // A time chosen elsewhere (Filters, the Map hand-off) leaves All events: its pick must not come back when the date
            // clears (web twin: the effect after `curTab` in Home.jsx).
            .onChange(of: app.homeFilters.date) { _, d in
                if app.unifiedDiscoveryEnabled, heroTab == .all, d != "any" { heroTab = .foryou }
            }
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
        // The header from the wordmark to the search bar stays pinned while the feed scrolls under it.
        .overlay(alignment: .top) {
            if app.simpleShellEnabled {
                HomeHeroPinnedHeader(tab: heroTabBinding,
                                     onSearchLocations: { areaSearchOpen = true },
                                     onAvatar: { quickSheetOpen = true },
                                     height: $pinnedHeaderHeight)
                    .revealRegion(0)
            }
        }
        .task(id: app.justSignedIn) { await app.finishSignInReveal(reduceMotion: reduceMotion) }
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
        // The admin invite is a Things-to-do item, so Home loads it itself.
        .task(id: app.userID) { if app.userID != nil { await app.loadMyAdminInvite() } }
        // Source-of-discovery pass — independent of the story ring above;
        // own initial load, own refresh, own pagination state.
        .task { if app.userID != nil { await app.loadHomeSurveyDiscovery() } }
        // Retention roadmap P1 ("Cuối tuần này") — public info, same as
        // loadHomeLiveEvents above (runs for every visitor).
        .task { await app.loadWeekendEvents() }
        // Banbe Pulse ticker + the Popular sort both read the daily ranking (public, so guests too).
        .task { await app.loadPulse(period: .daily) }
        // Home-visibility fix (2026-09-29) — public info, same as
        // loadWeekendEvents above (runs for every visitor); this is what
        // actually populates `app.feed` with real events at all (see
        // `discoveryEvents`'s own doc comment on AppState.swift).
        .task { await app.loadDiscoveryEvents() }
        // Blocker fix (retention roadmap follow-up) — a saved/attending
        // real (non-catalogue) event needs its own fetch for the Next-up
        // reminder to resolve it instead of quietly skipping it.
        .task { await app.loadMissingRealEvents(for: app.favorites + app.attending) }
        .onChange(of: app.screen) { _, new in if new == .home { reminderHaloTrigger += 1 } }
        .onAppear {
            reminderHaloTrigger += 1
            startTickingIfNeeded()
        }
        .onDisappear { tickTask?.cancel() }
        #if DEBUG
        // Shell fixture tests assert Home is never rebuilt by opening/closing an event (note 47).
        .onAppear { if UITestFixture.isActive { UITestFixture.homeMounts += 1 } }
        #endif
        // Task 1 (2026-09-22 twelfth follow-up) — collects every visible
        // story ring's own global frame for StoryViewerView's expand/
        // shrink-toward-ring transition (see AppState.swift's own comment
        // on storyRingFrames).
        .onPreferenceChange(StoryRingFramePreferenceKey.self) { app.storyRingFrames = $0 }
        .onPreferenceChange(RootGestureExclusionZonePreferenceKey.self) { zones in
            // Only Home's preference-reported zones are replaced; `rootSwipeExclusion` zones (category row, chips) stay.
            var z = app.rootGestureExclusionZones
            z["homeStories"] = nil; z["surveyDiscovery"] = nil
            app.rootGestureExclusionZones = z.merging(zones) { _, new in new }
        }
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
        .onAppear { observeForYouAlert(); forYouAlert.replay() }
        .task { await app.loadRewardsSummary() }
        // The area menu's searchable fallback (see `header`): a native Menu
        // can't hold a text field, so "Search locations…" opens this sheet
        // instead. Same picker Map Explore uses, same `app.area` selection.
        .sheet(isPresented: $areaSearchOpen) {
            LocationPickerSheet(isPresented: $areaSearchOpen)
        }
        // Note 50 — every filter in one sheet over the results; edits a draft until "Show N events".
        .sheet(isPresented: $app.homeFilterSheetOpen) {
            HomeFilterSheet(items: makeSnapshot().items, now: Date(), onClose: { app.homeFilterSheetOpen = false },
                            forYou: (app.eventPrefs?.isEmpty ?? true) ? nil : Binding(get: { app.filterForYou }, set: { app.filterForYou = $0 }))
            .environmentObject(app)
        }
        .sheet(isPresented: $quickSheetOpen) { QuickSheetView(onClose: { quickSheetOpen = false }).environmentObject(app) }
        .sheet(isPresented: $categorySheetOpen) {
            HomeCategorySheet(counts: makeSnapshot().categoryCounts)
                .environmentObject(app)
        }
        // The All types sheet lives on the screen, not on the type grid: the grid sits in a LazyVStack, so once it
        // scrolls far off screen it is unloaded and a sheet hung on it never shows (the list end card's
        // "Browse every type" did nothing on page 2, owner 2026-11-20).
        .sheet(isPresented: $udTypeSheetOpen) {
            UnifiedTypeSheet(counts: makeSnapshot().udCounts, selected: app.homeFilters.cats.first) { key in
                udTypeSheetOpen = false
                app.pickFilter(key)
                alignNearYouAfterPick()
            }
            .environmentObject(app)
        }
    }

    /// Once per request: waits for the rail (hidden while the first load is still empty) and for the scaffold's own
    /// restore window, then brings "This weekend" to the top.
    private func scrollToWeekendIfAsked(_ proxy: ScrollViewProxy) async {
        guard app.homeWeekendScrollRequest != nil else { return }
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            if !app.weekendEventsLoading || !app.weekendEvents.isEmpty { break }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, app.homeWeekendScrollRequest != nil else { return }
        app.homeWeekendScrollRequest = nil
        guard app.homeFilters.date != "weekend" else { return } // the whole feed is already this weekend
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { proxy.scrollTo("home.weekend", anchor: .top) }
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

    /// Native system glass (note 45). A selected chip/capsule is the same
    /// glass tinted with the ink colour, so selection reads without any
    /// hand-tuned opacity. Follows iOS Settings (Liquid Glass / Reduce Transparency).
    @ViewBuilder
    private func homeGlassCapsule(active: Bool = false) -> some View {
        Color.clear.nativeGlassCapsule(interactive: true, tint: active ? app.palette.ink : nil)
    }

    // MARK: header top row (wordmark + title, streak/coin shortcuts, search)

    /// Shown only once the server has answered (migration 165 applied); never a placeholder number.
    private var rewardShortcutsVisible: Bool { app.rewardsEnabled && app.rewardsSummaryStatus == .loaded && app.rewardsSummary != nil }

    /// With the shortcuts the row can get tight on narrow iPhones, so it degrades in a fixed order
    /// (ViewThatFits): full -> drop the "Home" title -> smaller wordmark. Every control keeps a 44pt
    /// touch target and the search button never moves.
    /// The "Home" title never drops (note 45): with the streak/coins capsule, the bell and the
    /// search button the row gets tight on narrower phones, so it shrinks in a fixed order
    /// (ViewThatFits) — controls to 46/44pt, then the wordmark and title step down, and only as a
    /// last resort the wordmark goes (the title stays). Every control keeps a 44pt touch target.
    @ViewBuilder
    private var headerTopRow: some View {
        ViewThatFits(in: .horizontal) {
            // The logo stays at the shared header size (112pt, as Account/Messages/Schedule) as long
            // as possible — the controls on the right shrink first.
            headerTopRow(wordmark: BanbeLogo.headerWordmarkWidth, titleSize: 27, control: 52)
            headerTopRow(wordmark: BanbeLogo.headerWordmarkWidth, titleSize: 27, control: 42, compact: true)
            headerTopRow(wordmark: BanbeLogo.headerWordmarkWidth, titleSize: 27, control: 36, compact: true, spacing: 3)
            headerTopRow(wordmark: BanbeLogo.headerWordmarkWidth, titleSize: 24, control: 34, compact: true, spacing: 2)
            headerTopRow(wordmark: 96, titleSize: 27, control: 46)
            headerTopRow(wordmark: 80, titleSize: 24, control: 46)
            headerTopRow(wordmark: 70, titleSize: 22, control: 44, spacing: 4)
            headerTopRow(wordmark: 58, titleSize: 21, control: 44, spacing: 3)
            headerTopRow(wordmark: nil, titleSize: 24, control: 44)
        }
    }

    private func headerTopRow(wordmark: CGFloat?, titleSize: CGFloat, control: CGFloat, compact: Bool = false, spacing: CGFloat = 6) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            if let wordmark, wordmark >= BanbeLogo.headerWordmarkWidth {
                // Note 53: the shared dock header (same logo, gap and title as Schedule/Messages/Account).
                DockHeaderTitle(title: app.T("Nhà", "Home"), identifier: "home.title", titleSize: titleSize)
            } else {
                // Last-resort variants for very narrow phones only.
                HStack(spacing: wordmark.map { $0 > 90 ? 10 : (spacing < 5 ? 4 : 6) } ?? 0) {
                    if let wordmark { BanbeLogo(kind: .wordmark, width: wordmark) }
                    Text(app.T("Nhà", "Home"))
                        .font(BanbeTheme.display(titleSize))
                        .foregroundStyle(app.palette.ink)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home.title")
                }
            }
            Spacer(minLength: 0)
            if rewardShortcutsVisible { rewardShortcuts(compact: compact, height: control) }
            // Note 44 — Notifications left the dock for Schedule; its bell (and
            // unread badge) lives here, always visible on Home.
            // Below 44pt the visible circle shrinks but the touch target stays 44pt (the
            // neighbouring targets overlap only their empty margins).
            HomeNotificationsButton(size: control)
                .frame(width: max(control, 44), height: max(control, 44))
                .padding(.horizontal, -(max(44 - control, 0) / 2))
        }
    }

    /// One glass capsule, two separate buttons (streak, coins), both opening Account > Rewards & badges.
    private func rewardShortcuts(compact: Bool, height: CGFloat) -> some View {
        let sum = app.rewardsSummary ?? RewardSummary(balance: 0, streak: 0, activeToday: false)
        let streak = RewardsLogic.capsuleStreak(sum, weekly: app.rewardsV2Enabled) // weeks under Rewards v2 (migration 192)
        return HStack(spacing: 0) {
            Button {
                Haptics.light()
                app.openRewards(from: .home)
            } label: {
                HStack(spacing: 4) {
                    Text("🔥").font(.app(size: compact ? 14 : 16)).opacity(streak.value > 0 ? 1 : 0.45).accessibilityHidden(true)
                    Text("\(streak.value)").font(.app(size: compact ? 12 : 13, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, compact ? 5 : 8).frame(minWidth: compact ? 36 : 44, minHeight: compact ? max(height, 34) : 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(streak.weekly
                                ? app.T("Chuỗi \(streak.value) tuần. Mở phần thưởng", "\(streak.value)-week streak. Open rewards")
                                : app.T("Chuỗi \(streak.value) ngày. Mở phần thưởng", "\(streak.value)-day streak. Open rewards"))
            .accessibilityIdentifier("home.streak")
            Rectangle().fill(app.palette.ink.opacity(0.18)).frame(width: 1, height: 22).accessibilityHidden(true)
            Button {
                Haptics.light()
                app.openRewards(from: .home)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "circle.hexagongrid.circle").font(.app(size: compact ? 13 : 15, weight: .medium)).accessibilityHidden(true)
                    Text(RewardsLogic.compactCoins(sum.balance)).font(.app(size: compact ? 12 : 13, weight: .semibold)).monospacedDigit()
                }
                .padding(.horizontal, compact ? 5 : 8).frame(minWidth: compact ? 36 : 44, minHeight: compact ? max(height, 34) : 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("\(sum.balance) xu. Mở phần thưởng và huy hiệu", "\(sum.balance) coins. Open rewards and badges"))
            .accessibilityIdentifier("home.coins")
        }
        .foregroundStyle(app.palette.ink)
        .background { homeGlassCapsule() }
        .fixedSize()
    }

    /// Note 50: a location pill ("Near Everywhere ▾") with the quick language and light/dark switches right
    /// beside it (plain text, same style), then the full-width search bar that opens the Search screen.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note 53: a fixed row height, so the logo + title sit at the same height whichever variant fits.
            headerTopRow.frame(height: DockHeaderTitle.rowHeight)
            // Area menu parity pass — a native `Menu`, the same mechanism the chat composer's "+" uses, so
            // presentation, glass, anchoring and dismissal are the system's. The label holds everything.
            // The quick language + light/dark switches sit right beside it in the SAME plain style (icon + text,
            // no capsule); each shows what a tap switches TO, as the old capsules did.
            HStack(spacing: 16) {
                Menu {
                    AreaMenuOptions { areaSearchOpen = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin").font(.app(size: 13, weight: .semibold))
                        Text(app.T("Gần", "Near")).fontWeight(.medium).opacity(0.6).fixedSize()
                        Text(app.area == LocationHierarchy.allID ? app.T("Mọi nơi", "Everywhere") : app.currentAreaLabel)
                            .lineLimit(1)
                        Text("▾").font(.app(size: 9))
                    }
                    .font(.app(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("header.area")
                Button {
                    Haptics.light()
                    app.toggleLang()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe").font(.app(size: 13, weight: .semibold))
                        Text(app.T("EN", "VN"))
                    }
                    .font(.app(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .fixedSize()
                .accessibilityLabel(app.T("Chuyển sang English", "Switch to Vietnamese"))
                .accessibilityIdentifier("header.lang")
                Button {
                    Haptics.light()
                    app.pickTheme(app.isDark ? "light" : "dark")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: app.isDark ? "sun.max" : "moon").font(.app(size: 13, weight: .semibold))
                        Text(app.isDark ? app.T("Sáng", "Light") : app.T("Tối", "Dark"))
                    }
                    .font(.app(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .fixedSize()
                .accessibilityLabel(app.isDark ? app.T("Chuyển sang giao diện sáng", "Switch to light mode")
                                                        : app.T("Chuyển sang giao diện tối", "Switch to dark mode"))
                .accessibilityIdentifier("header.theme")
            }
            // Same breathing room under the search bar as Map's own search field, so the feed never butts against it.
            HomeSearchBar()
                .padding(.bottom, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    // MARK: Simple Shell (note 66, switch simple_shell)

    /// Home shows the host sections only when the effective view is Hosting (Lib/HomeMode.swift): organizer mode on
    /// AND this session chose Hosting. Organizer mode off is always Going out, whatever was chosen before.
    /// Simple Shell: the hero backdrop paints above the scroll bounds, so the scroll view must not clip it (pull / bounce).
    private var homeClipsContent: Bool { !app.simpleShellEnabled }

    /// Simple Shell: the feed's scroll view starts under the FOLDED band (58 pt), so pinned section headers stick right
    /// below it. 0 without Simple Shell (no overlaid band).
    private var scrollTopShift: CGFloat { app.simpleShellEnabled ? HomeHeroPinnedHeader.barHeight : 0 }
    /// What of the band's height still lies over the scroll view (44 pt of tabs at rest, 0 folded): the hero's top room
    /// and the pull chip's anchor, both measured from the scroll view's own top.
    private var heroBandRoom: CGFloat { max(0, pinnedHeaderHeight - scrollTopShift) }

    private var hostHome: Bool { app.simpleShellEnabled && app.effectiveHomeView == .host }

    @ViewBuilder
    private var activeHeader: some View {
        // Note 80: with Simple Shell the header lives inside the photo hero on BOTH Going out and Hosting (it scrolls with the feed).
        if !app.simpleShellEnabled { header }
    }

    /// Logo, the Going out | Hosting switch and the bell. Streak/coins and the area/language/theme chips are gone from
    /// here (Account tiles, Settings, and the area button inside the search bar). Degrades by shrinking the logo, then
    /// putting the switch on its own row (large text).
    private var simpleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                simpleTopRow(logo: BanbeLogo.headerWordmarkWidth)
                simpleTopRow(logo: 84)
                simpleTopRow(logo: 64)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        BanbeLogo(kind: .wordmark, width: 84)
                        Spacer(minLength: 0)
                        HomeNotificationsButton(size: 44)
                    }
                    HomeModeSwitch()
                }
            }
            .frame(minHeight: DockHeaderTitle.rowHeight)
            if !hostHome {
                // Note 69: the streak/coins capsule (Rewards on) was only in the old Home header, so with Simple
                // Shell Rewards had no way in from Home. It sits beside the search bar on Going out.
                HStack(spacing: 8) {
                    simpleSearchBar
                    if rewardShortcutsVisible { rewardShortcuts(compact: true, height: 44) }
                }
                .padding(.bottom, 12)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, hostHome ? 12 : 0)
    }

    private func simpleTopRow(logo: CGFloat) -> some View {
        HStack(spacing: 10) {
            BanbeLogo(kind: .wordmark, width: logo)
            Spacer(minLength: 0)
            HomeModeSwitch()
            HomeNotificationsButton(size: 44)
        }
    }

    /// The search bar with the location folded in: "Find events near D1", and a trailing area button inside it.
    private var simpleSearchBar: some View {
        let place = app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel
        let placeholder = place.map { app.T("Tìm sự kiện gần \($0)", "Find events near \($0)") }
            ?? app.T("Tìm sự kiện ở mọi nơi", "Find events anywhere")
        return HomeSearchBar(placeholder: placeholder, trailingInset: 52)
            .overlay(alignment: .trailing) {
                Menu {
                    AreaMenuOptions { areaSearchOpen = true }
                } label: {
                    HStack(spacing: 8) {
                        Rectangle().fill(app.palette.divider).frame(width: 1, height: 22)
                        Image(systemName: "mappin.and.ellipse").font(.app(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(app.palette.ink)
                    .frame(width: 52, height: 46)
                    .contentShape(Rectangle())
                }
                .opacity(app.searchOverlayOpen ? 0 : 1)
                .accessibilityLabel(app.T("Khu vực: \(place ?? "Mọi nơi"). Đổi khu vực", "Area: \(place ?? "Everywhere"). Change area"))
                .accessibilityIdentifier("header.area")
            }
    }

    /// The new-user checklist's own visibility rule (ActivationChecklistCard), so the hero picker can rank it.
    private var checklistVisible: Bool {
        guard app.activation.enabled && !app.activation.dismissed else { return false }
        let items = ActivationChecklist.items(biometricsAvailable: BiometricAuthService.cachedAvailability.available)
        return ActivationChecklist.isVisible(state: app.activation, items: items,
                                             hasSavedEvent: !app.favorites.isEmpty, faceIDEnabled: auth.faceIDEnabled)
    }

    /// Exactly one hero (Lib/HomeHero.swift): Next up > the goer Things to do > the checklist > nothing; guests get
    /// the guest banner.
    @ViewBuilder
    private func goerHero(_ kind: HomeHero.Goer, items: [ActionCenterItem]) -> some View {
        switch kind {
        case .guest: GuestBrowseBanner()
        case .nextUp:
            if let next = nextUp { NextUpBanner(event: next.event, phase: next.phase, haloTrigger: reminderHaloTrigger) }
        case .action: ActionCenterView(items: items, onSeeAll: { app.goNotifications() })
        case .checklist: ActivationChecklistCard()
        case .none: EmptyView()
        }
    }

    private var pulseHasItems: Bool { !PulseTicker.items(from: app.pulseDaily).isEmpty }

    /// Hero → (saved, only without a hero) → one chip row → "N events · cards | list | map" → cards, with the stories
    /// row after the 3rd card and the Pulse ticker after the 6th → the rest of today's feed footer.
    @ViewBuilder
    private func simpleGoerFeed(_ snap: Snapshot, proxy: ScrollViewProxy) -> some View {
        if app.homeV23Enabled { v23GoerFeed(snap, proxy: proxy) } else { classicGoerFeed(snap) }
    }

    /// v2.3 (note 81): hero (rail of 4 + See all fan card) → Next up tickets (else the one hero block) → live line +
    /// Shortlist → Browse by type (closes Home).
    @ViewBuilder
    private func v23GoerFeed(_ snap: Snapshot, proxy: ScrollViewProxy) -> some View {
        let items = app.isSignedIn ? sortActionCenterItems(goerActionItems) : []
        HomeHeroSection(tab: heroTabBinding, lists: snap.heroLists, onSeeAll: { heroSeeAll($0) },
                        onSearchLocations: { areaSearchOpen = true },
                        onAvatar: { quickSheetOpen = true },
                        headerHeight: heroBandRoom,
                        v23Counts: snap.tabCounts,
                        suggestTotals: snap.heroTotals,
                        onBrowseAll: { nearYouScrollToken += 1 })
            .id(false)
            .id("home.tour.hero")
            .revealRegion(0)
        let tickets = app.nextUpItems()
        if !tickets.isEmpty {
            NextUpV23View(items: tickets).revealRegion(1)
        } else {
            let kind = HomeHero.goer(signedIn: app.isSignedIn, hasNextUp: nextUp != nil, actionCount: items.count,
                                     checklistVisible: app.isSignedIn && checklistVisible)
            goerHero(kind, items: items).revealRegion(1)
            if kind == .none, !savedUpcoming.isEmpty { savedUpcomingSection.revealRegion(1) }
        }
        if app.unifiedDiscoveryEnabled {
            LiveLineView(updates: snap.live, index: $liveIndex, onOpen: { liveNowOpen = true })
                .revealRegion(2)
                .sheet(isPresented: $liveNowOpen) { liveNowSheet(snap) }
            // Pinned section headers, like a grouped list: "Browse by type" sticks under the folded band while the grid
            // scrolls beneath it, then "Near you" pushes it off and stays for the rest of the list. 18 pt here + 10 pt
            // inside each header = the 28 pt the blocks had above their heading.
            Color.clear.frame(height: 18)
            Section {
                v23Browse(snap, part: .grid)
            } header: {
                v23Browse(snap, part: .header).modifier(HomePinnedSectionHeader()).revealRegion(2)
            }
            Color.clear.frame(height: 18)
            // Direct child of the LazyVStack (an id nested inside another container is unknown until that container is
            // built, so scrollTo would no-op while "Near you" is still off screen). Zero height, right on the header's top.
            Color.clear.frame(height: 0).id("home.nearYou")
            Section {
                VStack(spacing: 0) {
                    shortlist(snap, part: .list)
                    shortlistFooter(snap)
                }
                .id("home.tour.filters")
                .revealRegion(2)
            } header: {
                shortlist(snap, part: .header).modifier(HomePinnedSectionHeader()).revealRegion(2)
            }
        } else {
            VStack(spacing: 0) {
                LiveLineView(updates: snap.live, index: $liveIndex, onOpen: { liveNowOpen = true })
                // Prototype v2 order (note 99): Browse by type sits above the "Near you" list.
                v23Browse(snap)
            }
            .revealRegion(2)
            // 16 pt above the anchor + 12 pt in the list = the 28 pt above the heading; the anchor's 16 pt puts the
            // heading 12 pt under the folded band (the scroll view's top edge) when "See all" scrolls here.
            Color.clear.frame(height: 16)
            // Direct child of the LazyVStack (an id nested inside another container is unknown until that container is
            // built, so scrollTo would no-op while "Near you" is still off screen). Zero height, just above the heading.
            Color.clear.frame(height: 0).id("home.nearYou")
            VStack(spacing: 0) {
                shortlist(snap, part: .whole)
                shortlistFooter(snap)
            }
            .id("home.tour.filters")
            .revealRegion(2)
            .sheet(isPresented: $liveNowOpen) { liveNowSheet(snap) }
        }
        if !app.homeStories.isEmpty { storyRow.padding(.top, 20) }
        if app.isSignedIn { surveyDiscoveryRow.padding(.top, 28) }
    }

    /// "Near you" (note 99): `.whole` is the one block; unified discovery renders its header and list as a pinned Section.
    private func shortlist(_ snap: Snapshot, part: ShortlistV23View.Part) -> some View {
        // Note 99: time has the tabs, so the Filters badge counts only what Filters owns.
        // The tab shows beside the title only when the list follows it (unified discovery); otherwise the list is every
        // open event whatever the tab, so the end card words itself for All events. Web twin: ShortlistV23 `tab` / `endTab`.
        ShortlistV23View(tab: app.unifiedDiscoveryEnabled ? shownHeroTab : nil,
                         endTab: app.unifiedDiscoveryEnabled ? shownHeroTab : .all, rows: snap.shortRows, total: snap.shortTotal,
                         filterBadge: app.unifiedDiscoveryEnabled ? UnifiedDiscovery.ownedFilterCount(app.homeFilters, sort: app.homeSort) : snap.filterBadge,
                         onFilters: { app.homeFilterSheetOpen = true }, onAction: { shortlistAction($0) },
                         activeParts: unifiedActiveParts, onClearActive: { clearUnified() },
                         part: part, topPadding: 12)
    }

    /// Under the list: the map banner (unified discovery) and the closing line.
    @ViewBuilder
    private func shortlistFooter(_ snap: Snapshot) -> some View {
        if app.unifiedDiscoveryEnabled && snap.udTotal > 0 {
            UnifiedMapBanner(count: snap.udTotal, onOpen: { app.goMapExploreFromHome() })
        }
        Text("banbe · " + app.T("chọn một buổi, gặp vài người", "pick an evening, meet a few people"))
            .font(.app(size: 12)).foregroundStyle(app.palette.ink3)
            .frame(maxWidth: .infinity).padding(.top, 28)
    }

    private func liveNowSheet(_ snap: Snapshot) -> some View {
        LiveNowSheet(updates: snap.live, shownIndex: reduceMotionOn ? liveIndex : nil,
                     onOpen: { id, i in liveNowOpen = false; liveIndex = i; app.goEvent(id) },
                     onClose: { liveNowOpen = false })
            .environmentObject(app)
    }

    /// The in-place Browse by type (note 99), rendered above the "Near you" list: one block, or (unified discovery) the
    /// pinned header and the grid of a Section. The type sheet hangs off the grid (`.whole` / `.grid`).
    @ViewBuilder
    private func v23Browse(_ snap: Snapshot, part: UnifiedBrowseSection.Part = .whole) -> some View {
        if app.unifiedDiscoveryEnabled {
            let section = UnifiedBrowseSection(counts: snap.udCounts, onToggle: { toggleUnifiedType($0) },
                                               onClear: { app.pickFilter("all"); alignNearYouAfterPick() }, onOpenSheet: { udTypeSheetOpen = true },
                                               part: part)
            if part == .header {
                section
            } else {
                section
                    .id("home.tour.browse")
                    .revealRegion(2)
            }
        } else {
            HomeBrowseSection(counts: snap.categoryCounts, onPick: { app.openBrowse(type: $0, scope: "all") },
                              onFind: { app.openBrowse(type: "all", scope: "all") }, seeAllTotal: snap.browseTotal)
                .id("home.tour.browse")
                .revealRegion(2)
        }
    }

    private var reduceMotionOn: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Note 99 (unified_discovery): the tabs ARE the shared time. The selected tab is derived from
    /// `homeFilters.date` and picking one sets the date; with the switch off this is the local tab as before.
    /// For You and All events share the date "any", so the pick (`heroTab`) breaks the tie (UnifiedDiscovery.resolveTab).
    private var shownHeroTab: HomeHeroTab {
        app.unifiedDiscoveryEnabled
            ? UnifiedDiscovery.resolveTab(date: app.homeFilters.date, allPicked: heroTab == .all, hasPrefs: app.hasForYouPrefs)
            : UnifiedDiscovery.effectiveTab(heroTab, hasPrefs: app.hasForYouPrefs)
    }
    private var heroTabBinding: Binding<HomeHeroTab> {
        guard app.unifiedDiscoveryEnabled else {
            return Binding(get: { UnifiedDiscovery.effectiveTab(heroTab, hasPrefs: app.hasForYouPrefs) }, set: { heroTab = $0 })
        }
        return Binding(get: { UnifiedDiscovery.resolveTab(date: app.homeFilters.date, allPicked: heroTab == .all, hasPrefs: app.hasForYouPrefs) },
                       set: { t in
                           heroTab = t
                           let d = UnifiedDiscovery.dateForTab(t)
                           if app.homeFilters.date != d { app.homeFilters.date = d }
                       })
    }

    /// Note 99: × on the state bar clears the query and the Filters-owned filters, keeping the time.
    private func clearUnified() {
        app.searchQuery = ""
        var f = HomeDiscovery.Filters.default
        f.date = app.homeFilters.date
        app.homeFilters = f
        app.homeSort = "soonest"
    }

    private func toggleUnifiedType(_ key: String) {
        Haptics.selection()
        app.pickFilter(app.homeFilters.cats.first == key ? "all" : key)
        alignNearYouAfterPick()
    }

    /// Type tile tapped (select, switch or deselect): the "Near you" header goes to just under the folded band, always
    /// (same anchor as the rail's See all; web twin: `pickTypeAndAlign`). Waits a beat so the filtered list has laid
    /// out; Reduce Motion jumps (the `.onChange(of: nearYouScrollToken)` handler animates only when it is off).
    /// What narrows "Near you" (search, type, time…), shown as one chip under its header (owner 2026-11-19: replaced the
    /// state bar above Browse by type). Empty when nothing is on. Web twin: `udParts` → ShortlistV23 `active`.
    private var unifiedActiveParts: [String] {
        guard app.unifiedDiscoveryEnabled else { return [] }
        let q = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || UnifiedDiscovery.ownedFilterCount(app.homeFilters, sort: app.homeSort) > 0 else { return [] }
        let f = app.homeFilters
        return (q.isEmpty ? [] : ["“\(q)”"]) + UnifiedText.filterParts(app, f, sort: app.homeSort)
            + [UnifiedText.time(app, f.date)].compactMap { $0 }
    }

    private func alignNearYouAfterPick() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            nearYouScrollToken += 1
        }
    }

    /// End-card and empty-state actions of the Shortlist (web twin: `onShortlistAction`).
    private func shortlistAction(_ act: String) {
        switch act {
        case "clear-filters": app.clearFilters(); app.homeSort = "soonest"
        case "map": app.goMapExploreFromHome()
        // End card "See all events": the All events tab, in place (the same switch the tab row makes).
        case "tab:all": heroTabBinding.wrappedValue = .all
        // End card on All events: nothing to widen but the area.
        case "area": areaSearchOpen = true
        // Prototype v2: Browse is unreachable from Home in this mode; the end card opens the in-place type sheet.
        default:
            if app.unifiedDiscoveryEnabled { udTypeSheetOpen = true }
            else { app.openBrowse(type: "all", scope: "all") }
        }
    }

    @ViewBuilder
    private func classicGoerFeed(_ snap: Snapshot) -> some View {
        let items = app.isSignedIn ? sortActionCenterItems(goerActionItems) : []
        // Note 80: the full-bleed photo hero (header, search, tabs, card rail), then the same one-hero block as before.
        HomeHeroSection(tab: $heroTab, lists: snap.heroLists, onSeeAll: { heroSeeAll($0) },
                        onSearchLocations: { areaSearchOpen = true },
                        onAvatar: { quickSheetOpen = true },
                        headerHeight: heroBandRoom,
                        suggestTotals: snap.heroTotals)
            .id(false)
            .id("home.tour.hero")
            .revealRegion(0)
        let kind = HomeHero.goer(signedIn: app.isSignedIn, hasNextUp: nextUp != nil, actionCount: items.count,
                                 checklistVisible: app.isSignedIn && checklistVisible)
        goerHero(kind, items: items).revealRegion(1)
        if kind == .none, !savedUpcoming.isEmpty { savedUpcomingSection.revealRegion(1) }
        // Note 80: Browse (types with counts + Find a type), then By type (one photo row per type). The old category row,
        // chip row, "N events" header and card list are replaced by these; Filters still opens the same sheet.
        HomeBrowseSection(counts: snap.categoryCounts, onPick: { shellPickType($0) }, onFind: { categorySheetOpen = true })
            .id("home.tour.browse")
            .revealRegion(2)
        if !snap.typeChips.isEmpty {
            typeChipRow(snap)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .revealRegion(2)
        }
        HomeByTypeSections(sections: HomeByTypeSections.sections(shown: snap.shown, cards: snap.cards),
                           summary: shellFilterSummary, onFilters: { app.homeFilterSheetOpen = true },
                           onPick: { shellPickType($0) })
            .id("home.tour.filters")
            .revealRegion(2)
            .modifier(FirstCardTourTarget(isFirst: true))
        if !app.homeStories.isEmpty { storyRow.padding(.top, 20) }
        if pulseHasItems { PulseTickerView().padding(.horizontal, 20).padding(.vertical, 10) }
        if !snap.relaxHints.isEmpty && !snap.items.isEmpty { relaxHintsRow(snap.relaxHints) }
        if app.isSignedIn { surveyDiscoveryRow }
    }

    /// "Area · date · price", the one-line summary under By type (web twin: `shellFilterSummary`).
    private var shellFilterSummary: String {
        let f = app.homeFilters
        let area = app.area == LocationHierarchy.allID ? app.T("Mọi nơi", "Everywhere") : app.currentAreaLabel
        let date = HomeDiscovery.dateLabels[f.date].map { app.T($0.vi, $0.en) } ?? app.T("Mọi lúc", "Any time")
        let price = f.free ? app.T("Miễn phí", "Free") : app.T("Mọi mức giá", "Any price")
        return [area, date, price].joined(separator: " · ")
    }

    /// A type tile or row filters Home to that type (web twin: `shellPickType`); an already picked type stays picked.
    private func shellPickType(_ key: String) {
        Haptics.selection()
        if !app.homeFilters.cats.contains(key) { app.pickFilter(key) }
    }

    /// "See all" on a hero rail: For You turns the For You filter on, Tonight / Weekend set the date, then the feed shows.
    private func heroSeeAll(_ tab: HomeHeroTab) {
        // v2.3: See all opens Browse for THAT tab. Prototype v2 (unified discovery): it scrolls Home down to the
        // "Near you" list instead — Browse is unreachable from Home in that mode.
        if app.homeV23Enabled {
            if app.unifiedDiscoveryEnabled { nearYouScrollToken += 1; return }
            app.openBrowse(type: "all", scope: tab.rawValue); return
        }
        switch tab {
        case .foryou:
            if !app.filterForYou && app.hasForYouMatches { app.filterForYou = true }
        case .tonight, .weekend:
            var f = app.homeFilters
            f.date = tab == .tonight ? "today" : "weekend"
            app.setHomeFilters(f)
        case .all:
            break   // the feed already lists every event (web: heroSeeAll skips the date pick for All events)
        }
    }

    /// For You first, then Today / This weekend / Free / Almost full (scrolling), then Filters with its count, pinned.
    /// Sort lives in the Filters sheet; categories and event-type chips are the rows above this one.
    private func simpleChipRow(_ snap: Snapshot) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if app.hasForYouMatches { forYouChip.fixedSize(horizontal: true, vertical: false) }
                    ForEach(Self.quickChips, id: \.key) { chip in quickChip(chip, snap) }
                }
                .padding(.leading, 20).padding(.trailing, 4)
                .padding(.vertical, 4)
            }
            .rootSwipeExclusion("homeQuickChips")
            filtersButton(snap).padding(.trailing, 20)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 6).padding(.bottom, 6)
    }

    // MARK: Story row (Task 3.3, 07-notifications.md)
    // Host stories only. Banbe Pulse moved to the ticker at the top of the feed (note 51, PulseTickerView), so this
    // row is shown ONLY when there are stories: no stories, no row, no empty band. Compact 52pt rings.
    private var storyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(app.homeStories) { group in
                    SwipeSafeButton { app.openStoryViewer(group.organizerId, originRect: app.storyRingFrames[group.organizerId]) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(group.allViewed ? Color.clear : BanbeTheme.alert, lineWidth: 2.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(group.allViewed ? app.palette.rule : .clear, lineWidth: 2.5)
                                    )
                                    .frame(width: 52, height: 52)
                                Text(String(group.orgName.prefix(1)).uppercased())
                                    .font(.app(size: 15, weight: .bold))
                                    .foregroundStyle(app.palette.ink)
                                    .frame(width: 44, height: 44)
                                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            Text(group.orgName)
                                .font(.app(size: 9.5))
                                .foregroundStyle(app.palette.ink)
                                .lineLimit(1)
                                .frame(width: 56)
                        }
                        // Reports this ring's own global frame (the 52x52 ZStack above, not the label/text) via
                        // StoryRingFramePreferenceKey, so the viewer can zoom out of it.
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
        }
        // The story row owns horizontal scrolling. Register its real bounds in the same root coordinate space
        // tabSwipeGesture uses, so a swipe that starts on a story ring scrolls the row and never commits Home -> Map.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: RootGestureExclusionZonePreferenceKey.self,
                    value: ["homeStories": geo.frame(in: .named("rootGesture"))]
                )
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
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
                        .font(BanbeTheme.display(20)).foregroundStyle(app.palette.ink)
                    if !app.homeSurveyDiscoveryLoading && app.homeSurveyDiscoveryError.isEmpty && !app.homeSurveyDiscovery.isEmpty {
                        // Honest LOADED count, never a fabricated total —
                        // "+" only when the server told us more exist
                        // (`hasMore`), never guessed from a page-size cap.
                        Text(app.homeSurveyDiscoveryHasMore ? "\(app.homeSurveyDiscovery.count)+" : "\(app.homeSurveyDiscovery.count)")
                            .font(.app(size: 13, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(app.palette.ink.opacity(0.1), in: Capsule())
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.app(size: 14, weight: .bold))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
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
                    Text(app.T("Đang tải…", "Loading…")).font(.app(size: 12)).opacity(0.6).padding(.horizontal, 20)
                } else if !app.homeSurveyDiscoveryError.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.homeSurveyDiscoveryError).font(.app(size: 12)).foregroundStyle(BanbeTheme.alert)
                        Button(app.T("Thử lại", "Retry")) { Task { await app.loadHomeSurveyDiscovery() } }
                            .font(.app(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                } else if app.homeSurveyDiscovery.isEmpty {
                    Text(app.T("Chưa có khảo sát công khai nào.", "No public surveys right now."))
                        .font(.app(size: 12)).opacity(0.6).padding(.horizontal, 20)
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
                                    .font(.app(size: 12, weight: .semibold))
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
                        .font(.app(size: 13, weight: .semibold))
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
                    .font(.app(size: 11))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    // No `.lineLimit` here — lets this line wrap onto a
                    // second line at larger Dynamic Type sizes instead of
                    // truncating/clipping.
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.app(size: 10, weight: .semibold))
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
                .font(.app(size: 12, weight: .bold))
                .foregroundStyle(app.palette.ink)
            if let url = card.hostAvatarURL {
                RemoteImage(path: url.absoluteString, maxPixel: 56)
                    .clipShape(Circle())
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: Phase 1 Q8 — "Saved, coming up" (same rule as web Home.jsx)

    /// Saved events that are live and start within 30 days, soonest first, at most 5 (Lib/QuickWins.swift).
    private var savedUpcoming: [CatalogEvent] {
        let resolved = app.favorites.compactMap(app.resolvedEvent(for:))
        let picked = QuickWins.savedComingUp(resolved.map { e in
            QuickWins.Candidate(key: e.key, status: e.cancelled ? "cancelled" : (e.endedHoursAgo != nil ? "ended" : "live"), startsAt: e.startDate)
        }, now: Date())
        return picked.compactMap { c in resolved.first { $0.key == c.key } }
    }

    /// Each with its real date and, when known, its real fill ("12 of 20 taken"). No timers, no urgency words.
    private var savedUpcomingSection: some View {
        let rows = savedUpcoming
        return VStack(alignment: .leading, spacing: 0) {
            Text(app.T("Đã lưu, sắp diễn ra", "Saved, coming up"))
                .font(BanbeTheme.display(17))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.element.key) { index, e in
                Button { app.goEvent(e.key) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.app(size: 14.5, weight: .semibold)).lineLimit(1)
                            Text(savedRowDetail(e)).font(.app(size: 12.5)).opacity(0.65)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).opacity(0.4)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(app.palette.rule).frame(height: 1) } }
                .accessibilityIdentifier("home.savedUpcoming.\(e.key)")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
        .accessibilityIdentifier("home.savedUpcoming")
        .task(id: rows.map(\.key).joined(separator: ",")) {
            let missing = rows.map(\.key).filter { app.eventFill[$0] == nil }
            await app.loadPublicEventFill(ids: missing)
        }
    }

    private func savedRowDetail(_ e: CatalogEvent) -> String {
        let when = app.discoveryWhenLabel(e.startDate, timeZone: EventMarket.timeZone(e.timeZoneID))
        guard let fill = app.eventFill[e.key], let t = QuickWins.fillText(capacity: fill.capacity, booked: fill.booked) else { return when }
        return when + " · " + app.T(t.vi, t.en)
    }

    /// Reminder only for a ticket-holder's own event (not a hold, not merely saved).
    private func reminderPhase(_ event: CatalogEvent) -> EventReminder.Phase? {
        guard app.isGoing(event.key), event.key != app.heldEvent?.key,
              !event.cancelled, event.endedHoursAgo == nil else { return nil }
        return EventReminder.phase(startsAt: event.startDate)
    }

    /// The note-37 reminder, surfaced only as the Next-up banner: the most urgent confirmed ticket (live before
    /// soon) among saved/attending/held events. Same rule as before (Lib/EventReminder.swift).
    private var nextUp: (event: CatalogEvent, phase: EventReminder.Phase)? {
        let candidates = app.savedStrip.compactMap { e in reminderPhase(e).map { (event: e, phase: $0) } }
        return candidates.first { $0.phase == .live } ?? candidates.first
    }

    // MARK: Discovery snapshot (note 50)

    /// `app.feed` (category + area + For You) normalized ONCE into the Lib/HomeDiscovery.swift item shape, so
    /// quick chips, the filter sheet, its per-pill counts and the feed all run the same pure logic.
    private struct Snapshot {
        let items: [HomeDiscovery.Item]
        let shown: [HomeDiscovery.Item]
        let cards: [DiscoveryCardModel]
        let quickCounts: [String: Int]
        let relaxHints: [HomeDiscovery.RelaxHint]
        let filterBadge: Int
        var typeChips: [EventTypeProfile.HomeFilter] = []
        var typeCounts: [String: Int] = [:]
        var categoryCounts: [String: Int] = [:]
        var categoryRow: [String] = ["all"]
        /// Note 80: the hero's rails (max 5 each), same filters as the feed except the date. Empty unless Simple Shell.
        var heroLists: [HomeHeroTab: [DiscoveryCardModel]] = [:]
        /// Weekend and All events sizes under Home's area and filters (the hero's suggestion cards; web `heroLists.totals`).
        var heroTotals: [HomeHeroTab: Int] = [:]
        /// v2.3 (note 81): the Shortlist rows (the open tab narrowed by Home's filters), the tab's size before the
        /// filters, every tab's size (See all card), the live line, and the whole catalogue's size (Browse "See all").
        var shortRows: [V23Row] = []
        var shortTotal = 0
        var tabCounts: [HomeHeroTab: Int] = [:]
        var live: [LiveLine.Update] = []
        var browseTotal = 0
        /// Note 99 (unified_discovery): events per type for the shared search + time + price (type tiles, type sheet),
        /// and the "Near you" list's own count (state bar, map banner: "same results" means exactly the list).
        var udCounts: [String: Int] = [:]
        var udTotal = 0
    }

    private static let quickChips: [(key: String, vi: String, en: String)] = [
        ("today", "Hôm nay", "Today"), ("weekend", "Cuối tuần này", "This weekend"),
        ("free", "Miễn phí", "Free"), ("seatsLeft", "Còn chỗ", "Seats left"), ("almostFull", "Sắp hết chỗ", "Almost full"),
    ]

    private func quickActive(_ key: String, _ f: HomeDiscovery.Filters) -> Bool {
        switch key {
        case "today": return f.date == "today"
        case "weekend": return f.date == "weekend"
        case "free": return f.free
        case "seatsLeft": return f.seatsLeft
        default: return f.almostFull
        }
    }

    private func toggleQuick(_ key: String) {
        var f = app.homeFilters
        switch key {
        case "today": f.date = f.date == "today" ? "any" : "today"
        case "weekend": f.date = f.date == "weekend" ? "any" : "weekend"
        case "free": f.free.toggle(); f.priceMin = nil; f.priceMax = nil
        case "seatsLeft": f.seatsLeft.toggle()
        default: f.almostFull.toggle()
        }
        app.setHomeFilters(f)
    }

    /// The whole discovery pass for one render (Home re-renders on many AppState changes; this keeps it to
    /// one pass over the feed).
    private func makeSnapshot(now: Date = Date()) -> Snapshot {
        let feed = app.feed
        let scores = app.pulseScores
        let items = feed.map { app.discoveryItem(for: $0, now: now, scores: scores) }
        let byKey = Dictionary(feed.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let f = app.homeFilters
        let filtered = HomeDiscovery.apply(items, f, now: now)
        // For You keeps its own ranking; any explicit sort overrides it, Soonest keeps the feed's order.
        let shown = app.homeSort != "soonest" ? HomeDiscovery.sort(filtered, mode: app.homeSort) : filtered
        var quick = HomeDiscovery.optionCounts(items, f, .date, options: ["today", "weekend"], now: now)
        quick["free"] = HomeDiscovery.optionCounts(items, f, .free, now: now)["true"]
        quick["seatsLeft"] = HomeDiscovery.optionCounts(items, f, .seatsLeft, now: now)["true"]
        quick["almostFull"] = HomeDiscovery.optionCounts(items, f, .almostFull, now: now)["true"]
        let hints = shown.count < 3 ? HomeDiscovery.relaxationHints(items, f, now: now) : []
        // Best-match label: the top For You match, only when the user has answers. Without answers the first
        // card is "Popular this week" when it's the area's top Pulse event — never called a "match".
        let forYou = app.forYouMatches   // computed (ForYou.rank): read once per pass
        let topForYou = forYou.first?.key
        let forYouActive = app.filterForYou && !forYou.isEmpty
        let topPulse = items.filter { $0.popularity != nil }.max { ($0.popularity ?? 0) < ($1.popularity ?? 0) }?.key
        let cards: [DiscoveryCardModel] = shown.enumerated().compactMap { i, it in
            guard let e = byKey[it.key] else { return nil }
            var label: String?
            if i == 0 && topForYou == e.key { label = "best" }
            else if i == 0 && !forYouActive && topPulse == e.key { label = "popular" }
            return app.discoveryCardModel(e, item: it, now: now, label: label)
        }
        let badge = HomeDiscovery.activeFilterCount(f)
        // Event type profiles: with exactly one category picked, that type's own chips (counts like the quick chips).
        let typeChips = app.eventTypesEnabled && f.cats.count == 1 ? EventTypes.homeFilters(EventTypes.profile(f.cats[0])) : []
        let typeCounts = typeChips.isEmpty ? [:]
            : HomeDiscovery.optionCounts(items, f, .typeFilters, options: typeChips.map(\.id), now: now)
        // Category row (web twin): what tapping each category shows, with the very same filter the feed renders with.
        let catCounts = HomeDiscovery.categoryCounts(items, f, keys: EventTypes.keys, now: now)
        let catRow = HomeDiscovery.categoryRowKeys(catCounts, keys: EventTypes.keys, selected: f.cats)
        var snap = Snapshot(items: items, shown: shown, cards: cards, quickCounts: quick, relaxHints: hints, filterBadge: badge,
                            typeChips: typeChips, typeCounts: typeCounts, categoryCounts: catCounts, categoryRow: catRow)
        if app.simpleShellEnabled && app.effectiveHomeView != .host {
            var totals: [HomeHeroTab: Int] = [:]
            snap.heroLists = makeHeroLists(items: items, byKey: byKey, forYou: forYou, filters: f, now: now, totals: &totals)
            snap.heroTotals = totals
            if app.homeV23Enabled { fillV23(&snap, items: items, byKey: byKey, forYou: forYou, filters: f, now: now) }
        }
        return snap
    }

    /// Note 80 (web twin: `heroLists` in Home.jsx): For You (ranked matches, else the soonest), Tonight and Weekend, each
    /// at most 5 open events (not sold out, not cancelled, not past its end), every filter kept
    /// except the date.
    private func makeHeroLists(items: [HomeDiscovery.Item], byKey: [String: CatalogEvent], forYou: [ForYouMatch],
                               filters: HomeDiscovery.Filters, now: Date,
                               totals: inout [HomeHeroTab: Int]) -> [HomeHeroTab: [DiscoveryCardModel]] {
        // One "still on" rule with web (UnifiedDiscovery.isOpenItem: not cancelled, a start, not past its end). It
        // used to drop anything that had merely started over an hour ago, which web stopped doing (audit row 6).
        func open(_ it: HomeDiscovery.Item) -> Bool { !it.soldOut && UnifiedDiscovery.isOpenItem(it, now: now) }
        // Web builds the rails from `qItems`: the shared query narrows them too (unified discovery).
        let items = queryNarrowed(items, byKey: byKey)
        func shape(_ its: [HomeDiscovery.Item]) -> [DiscoveryCardModel] {
            its.prefix(app.homeV23Enabled ? 4 : 5).compactMap { it in byKey[it.key].map { app.discoveryCardModel($0, item: it, now: now) } }
        }
        var base = filters
        base.date = "any"
        func byDate(_ date: String) -> [DiscoveryCardModel] {
            var g = base
            g.date = date
            return shape(HomeDiscovery.apply(items, g, now: now).filter(open))
        }
        let byItemKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let ranked = forYou.compactMap { byItemKey[$0.key] }.filter(open)
        let soonest = HomeDiscovery.apply(items, base, now: now).filter(open)
        // All events: every open event, any type and date, soonest first (web: `heroLists.all`).
        let allSoonest = HomeDiscovery.sort(soonest, mode: "soonest")
        let weekendAll = HomeDiscovery.apply(items, { var g = base; g.date = "weekend"; return g }(), now: now).filter(open)
        totals = [.foryou: ranked.count, .weekend: weekendAll.count, .all: allSoonest.count]
        // For You = only the matcher's picks (an empty set shows For You's own empty card); All events is every open event.
        return [.foryou: shape(ranked), .tonight: byDate("today"), .weekend: byDate("weekend"),
                .all: shape(allSoonest)]
    }

    /// Unified discovery: the shared query narrows Home's lists with Search's own matcher (web: `qItems`).
    private func queryNarrowed(_ items: [HomeDiscovery.Item], byKey: [String: CatalogEvent]) -> [HomeDiscovery.Item] {
        let q = app.unifiedDiscoveryEnabled ? app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !q.isEmpty else { return items }
        return items.filter { it in byKey[it.key].map { SearchMatch.matches(doc: SearchMatch.buildDoc(for: $0), query: q) } ?? false }
    }

    private func fillV23(_ snap: inout Snapshot, items: [HomeDiscovery.Item], byKey: [String: CatalogEvent], forYou: [ForYouMatch],
                         filters f: HomeDiscovery.Filters, now: Date) {
        var counts: [HomeHeroTab: Int] = [:]
        for t in HomeHeroTab.allCases {
            counts[t] = app.v23TabItems(t, items: items, byKey: byKey, forYou: forYou, now: now).count
        }
        snap.tabCounts = counts
        // "Near you" (bug 2026-11-19): ONE rule with web, UnifiedDiscovery.nearYou + its shared fixture. Every open event
        // Home lists (never the For You ranking of the open tab, which made it 7 here and 15 on web), Home's filters,
        // soonest first; total = before the Filters-owned filters (the tab's time stays applied with unified discovery).
        // The shared query narrows the list with Search's own matcher; the shared date is already in `f`.
        let pool = queryNarrowed(items, byKey: byKey)
        if app.unifiedDiscoveryEnabled {
            // Type tiles count the same open events the list shows (web: categoryCountMap over the open items).
            snap.udCounts = HomeDiscovery.categoryCounts(pool.filter { UnifiedDiscovery.isOpenItem($0, now: now) }, f,
                                                         keys: EventTypes.keys, now: now)
        }
        let ud = app.unifiedDiscoveryEnabled
        let near = UnifiedDiscovery.nearYou(pool, filters: f, sort: app.homeSort, now: now, tabOwnsTime: ud,
                                            tab: shownHeroTab, forYouKeys: ud && app.hasForYouPrefs ? Set(forYou.map(\.key)) : nil)
        snap.shortTotal = near.total
        snap.shortRows = near.rows.compactMap { it in byKey[it.key].map { app.v23Row($0, item: it, now: now) } }
        // The map banner and the state bar promise "same results": exactly the list's count (web: shortlist.rows.length).
        snap.udTotal = snap.shortRows.count
        snap.browseTotal = HomeDiscovery.apply(items, .default, now: now).filter { byKey[$0.key]?.cancelled == false }.count
        let byItem = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        snap.live = LiveLine.updates(
            pulse: app.pulseDaily.map { LiveLine.PulseItem(eventId: $0.eventId, eventName: $0.eventName, organizerName: $0.organizerName, bookingCount: $0.bookingCount) },
            lookup: { id in
                guard let it = byItem[id], let e = byKey[id], !e.cancelled else { return nil }
                return LiveLine.Facts(seatsLeft: HomeDiscovery.fillBadge(booked: it.booked, capacity: it.capacity).left,
                                      when: app.discoveryDateBadge(it.startsAt, now: now, timeZone: e.eventTimeZone))
            },
            tonight: counts[.tonight] ?? 0, weekend: counts[.weekend] ?? 0)
    }

    /// Event type profiles (switch event_type_profiles): the selected category's own chips (a supper club:
    /// Vegetarian-friendly, Vegan, BYO). AND-combined; a chip with 0 events hides unless on.
    private func typeChipRow(_ snap: Snapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snap.typeChips) { chip in
                    let active = app.homeFilters.typeFilters.contains(chip.id)
                    let n = snap.typeCounts[chip.id] ?? 0
                    if active || n > 0 {
                        SwipeSafeButton {
                            Haptics.selection()
                            var f = app.homeFilters
                            if let i = f.typeFilters.firstIndex(of: chip.id) { f.typeFilters.remove(at: i) } else { f.typeFilters.append(chip.id) }
                            app.setHomeFilters(f)
                        } label: {
                            HStack(spacing: 6) {
                                Text(app.T(chip.vi, chip.en))
                                if !active { Text("\(n)").font(.app(size: 12)).monospacedDigit().opacity(0.6) }
                            }
                            .font(.app(size: chipFont, weight: active ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 14).frame(minHeight: 36)
                            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                            .background { homeGlassCapsule(active: active) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                        .accessibilityIdentifier("home.type.\(chip.id)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 2)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Lọc theo loại sự kiện", "Filter by event type"))
        .rootSwipeExclusion("homeTypeChips")
    }

    /// Filters + Sort open the sheet; For You stays pinned at the leading edge (notes 34/36); the one-tap chips
    /// scroll on their own (registered as a root-gesture exclusion zone). A chip with 0 events hides unless on.
    private func quickRow(_ snap: Snapshot) -> some View {
        HStack(spacing: 8) {
            filtersButton(snap)
            // Sort is its own native pop-up (same mechanism as the area menu) with ONLY the sort options.
            // The capsule turns "on" while a non-default sort is chosen.
            let sortActive = app.homeSort != "soonest"
            Menu {
                ForEach(HomeDiscovery.sortModes, id: \.self) { mode in
                    let l = HomeDiscovery.sortLabels[mode] ?? (mode, mode)
                    let needsLocation = mode == "nearest" && !(app.located == true && app.userCoords != nil)
                    Button {
                        Haptics.selection()
                        if needsLocation { app.allowLocation() } else { app.homeSort = mode }
                    } label: {
                        if app.homeSort == mode {
                            Label(app.T(l.vi, l.en), systemImage: "checkmark")
                        } else if needsLocation {
                            Label(app.T("\(l.vi) ▪︎ bật vị trí", "\(l.en) ▪︎ turn on location"), systemImage: "location")
                        } else {
                            Text(app.T(l.vi, l.en))
                        }
                    }
                    .accessibilityIdentifier("home.sort.\(mode)")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.app(size: 14, weight: .semibold))
                    .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 36)
                    .foregroundStyle(sortActive ? app.palette.paper : app.palette.ink)
                    .background { homeGlassCapsule(active: sortActive) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Sắp xếp: \(HomeDiscovery.sortLabels[app.homeSort]?.vi ?? "")",
                                      "Sort: \(HomeDiscovery.sortLabels[app.homeSort]?.en ?? "")"))
            .accessibilityIdentifier("home.sortButton")
            if app.hasForYouMatches {
                forYouChip
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .zIndex(1)  // halo ring may overlap the scroller beside it
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.quickChips, id: \.key) { chip in quickChip(chip, snap) }
                }
                .padding(.trailing, 20)
                .padding(.vertical, 2)
            }
            .rootSwipeExclusion("homeQuickChips")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.leading, 20)
        .padding(.top, 10).padding(.bottom, 6)
    }

    /// Filters opens the sheet; the number is how many filters are on (shared by today's row and Simple Shell's).
    private func filtersButton(_ snap: Snapshot) -> some View {
        SwipeSafeButton {
            Haptics.light()
            app.homeFilterSheetOpen = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.app(size: 14, weight: .semibold))
                if snap.filterBadge > 0 {
                    Text("\(snap.filterBadge)").font(.app(size: 12, weight: .bold)).monospacedDigit()
                }
            }
            .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 36)
            .foregroundStyle(snap.filterBadge > 0 ? app.palette.paper : app.palette.ink)
            .background { homeGlassCapsule(active: snap.filterBadge > 0) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(snap.filterBadge > 0 ? app.T("Bộ lọc, \(snap.filterBadge) đang bật", "Filters, \(snap.filterBadge) on")
                                                 : app.T("Bộ lọc", "Filters"))
        .accessibilityIdentifier("home.filtersButton")
    }

    /// One one-tap chip (Today / This weekend / Free / Almost full); hidden at 0 unless it is on.
    @ViewBuilder
    private func quickChip(_ chip: (key: String, vi: String, en: String), _ snap: Snapshot) -> some View {
        let active = quickActive(chip.key, app.homeFilters)
        let n = snap.quickCounts[chip.key] ?? 0
        if active || n > 0 {
            SwipeSafeButton {
                Haptics.selection()
                toggleQuick(chip.key)
            } label: {
                HStack(spacing: 6) {
                    Text(app.T(chip.vi, chip.en))
                    if !active { Text("\(n)").font(.app(size: 12)).monospacedDigit().opacity(0.6) }
                }
                .font(.app(size: chipFont, weight: active ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                .background { homeGlassCapsule(active: active) }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityIdentifier("home.quick.\(chip.key)")
        }
    }

    /// What you're looking through, and a cards/list switch (no single default suits everyone).
    /// Simple Shell adds a third option, map, which opens the Map screen (Map is a Home view there, not a dock tab).
    private func sectionHeader(_ snap: Snapshot, includeMap: Bool = false) -> some View {
        let date = app.homeFilters.date
        let title: String = {
            if date != "any", let l = HomeDiscovery.dateLabels[date] { return app.T(l.vi, l.en) }
            if app.filterForYou && app.hasForYouMatches {
                if let t = forYouIntent, t.goal != nil { return app.T(t.vi, t.en) }
                return app.T("Dành cho bạn", "For you")
            }
            return app.T("Sắp diễn ra", "Upcoming")
        }()
        let n = snap.shown.count
        return HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(BanbeTheme.display(20)).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text(app.T("\(n) sự kiện", "\(n) event\(n == 1 ? "" : "s")"))
                    .font(.app(size: 13)).opacity(0.6).lineLimit(1)
                    .accessibilityIdentifier("home.resultCount")
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach([("cards", app.T("Thẻ", "Cards"), "rectangle.grid.1x2"), ("list", app.T("Danh sách", "List"), "list.bullet")], id: \.0) { mode, label, icon in
                    let on = layoutMode == mode
                    Button {
                        Haptics.selection()
                        layoutMode = mode
                    } label: {
                        Image(systemName: icon).font(.app(size: 13, weight: .semibold))
                            .frame(width: 36, height: 30)
                            .background(on ? app.palette.paper : Color.clear, in: Capsule())
                            .overlay(Capsule().strokeBorder(app.palette.rule.opacity(on ? 1 : 0), lineWidth: 1))
                            .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 1.5, y: 1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("home.layout.\(mode)")
                }
                if includeMap {
                    Button {
                        Haptics.selection()
                        app.goMapExploreFromHome()
                    } label: {
                        Image(systemName: "map").font(.app(size: 13, weight: .semibold))
                            .frame(width: 36, height: 30)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Bản đồ", "Map"))
                    .accessibilityIdentifier("home.layout.map")
                    .tourTarget("tour.home.mapView")
                }
            }
            .padding(.horizontal, 2)
            .background(app.palette.ink.opacity(0.06), in: Capsule().inset(by: 7))
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 6).padding(.bottom, 4)
    }

    private func relaxHintsRow(_ hints: [HomeDiscovery.RelaxHint]) -> some View {
        FlowRow(spacing: 8) {
            ForEach(hints, id: \.id) { h in
                let l = HomeDiscovery.relaxLabels[h.id] ?? (h.id, h.id)
                SwipeSafeButton {
                    Haptics.selection()
                    app.setHomeFilters(h.filters)
                } label: {
                    Text(app.T("+\(h.gain) sự kiện nếu \(l.vi)", "+\(h.gain) event\(h.gain == 1 ? "" : "s") with \(l.en)"))
                        .font(.app(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background { homeGlassCapsule() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.relax.\(h.id)")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 18)
    }

    private func observeForYouAlert() {
        // Note 64: while the v3 tour shows Home, nothing is observed or saved on the person's behalf.
        guard !app.tourActive else { return }
        let matches = app.forYouMatches.map { m in
            ForYouAlertMatch(id: m.key, version: app.discoveryAlertVersions[m.key] ?? "")
        }
        forYouAlert.observe(userID: app.userID?.uuidString, matches: matches,
                            prefsVersion: app.eventPrefsVersion,
                            loading: app.discoveryEventsLoading || app.eventPrefs == nil)
    }
    /// L6 intent For You (switch intent_foryou): title + one "because you said…" line from the FIRST goal the person
    /// stated in onboarding (CoreLoops.intentTitle). Stated answers only; ranking unchanged. nil while the switch is off.
    private var forYouIntent: CoreLoops.IntentTitle? {
        guard FeatureFlags.isOn(app.featureFlags, "intent_foryou") else { return nil }
        return CoreLoops.intentTitle(goals: app.eventPrefs?.declaredGoals ?? [])
    }

    /// Quick shortcut while For You is active: edit the answers, and Back /
    /// swipe-back returns here with For You still on (`eventPrefsReturnScreen`).
    private var forYouEditRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = forYouIntent, let whyVi = t.whyVi, let whyEn = t.whyEn {
                Text(app.T(whyVi, whyEn))
                    .font(.app(size: 13))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("foryou.why")
            }
            Button {
                Haptics.selection()
                app.openEventPreferences(returnTo: .home)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.app(size: 12, weight: .semibold))
                    Text(app.T("Chỉnh câu trả lời của bạn", "Edit my answers"))
                        .font(.app(size: 12.5, weight: .semibold)).underline()
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("foryou.editAnswers")
        }
    }

    /// Gold-star "For You" chip — only rendered when `hasForYouMatches`.
    private var forYouChip: some View {
        let gold = Color(red: 0.80, green: 0.62, blue: 0.16)
        let active = app.filterForYou
        let chipTitle: String = {
            if let t = forYouIntent, t.goal != nil { return app.T(t.vi, t.en) }
            return app.T("Dành cho bạn", "For You")
        }()
        return SwipeSafeButton {
            Haptics.selection()
            if !app.filterForYou { forYouAlert.acknowledge(loadedIDs: app.forYouMatches.map(\.key)) }
            app.toggleHomeFilter("forYou")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.app(size: 11, weight: .bold))
                    .foregroundStyle(active ? app.palette.paper : gold)
                Text(chipTitle)
                    .font(.app(size: chipFont, weight: active ? .bold : .regular))
                    .lineLimit(1)
                if forYouAlert.hasPending {
                    // White on #7A5200 = ~6.9:1 (AA); static, retained until acknowledged.
                    Text(app.T("Mới", "New"))
                        .font(.app(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 0.478, green: 0.322, blue: 0)))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 36)  // same height as Filters / Sort / the quick chips
            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
            .background { homeGlassCapsule(active: active) }
            .overlay(Capsule().stroke(active ? app.palette.ink : gold.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(ForYouAttentionEffect(animating: forYouAlert.animating, reduceMotion: reduceMotion, token: reminderHaloTrigger &+ forYouAlert.replayToken))
        .accessibilityIdentifier("filter.foryou")
        .tourTarget("tour.home.forYou")
        .accessibilityLabel(forYouAlert.hasPending && !active
            ? chipTitle + app.T(", có gợi ý mới", ", new recommendations")
            : chipTitle)
    }

    /// Never leave a stale empty "For You" list: once data has settled, a
    /// vanished match set (prefs edited, area changed) clears the filter.
    private func resetForYouIfStale() {
        guard app.filterForYou, !app.discoveryEventsLoading, !app.hasForYouMatches else { return }
        app.filterForYou = false
    }

    // MARK: Empty / footer

    /// Note 48: a cute scene + one clear next step instead of a bare line. Calm Pass phase 2: when For You is on and
    /// other filters leave nothing, say it is the combination (web twin: Home.jsx `home-empty-foryou`).
    @ViewBuilder
    private var emptyState: some View {
        if app.filterForYou && app.hasForYouMatches {
            MotivatingEmptyState(
                scene: .findPlans,
                title: app.T("Chưa có sự kiện khớp lựa chọn của bạn", "No events match your picks yet"),
                message: app.T("Các bộ lọc khác đang thu hẹp kết quả Dành cho bạn. Xem tất cả, hoặc chỉnh sở thích của bạn.",
                               "Your other filters narrow For You down to nothing. See everything, or change what you like."),
                actionTitle: app.T("Xem tất cả sự kiện", "See all events"),
                actionIcon: "sparkles",
                actionID: "home.empty.forYou.seeAll",
                action: { app.clearFilters(); app.filterForYou = false; app.homeSort = "soonest" },
                secondaryTitle: app.T("Chỉnh sở thích", "Edit my picks"),
                secondaryID: "home.empty.forYou.prefs",
                secondaryAction: { app.openEventPreferences(returnTo: .home) },
                identifier: "home.empty.forYou"
            )
            .padding(.vertical, 20)
        } else {
            plainEmptyState
        }
    }

    private var plainEmptyState: some View {
        let place = app.area == LocationHierarchy.allID ? nil : app.currentAreaLabel
        return MotivatingEmptyState(
            scene: .findPlans,
            title: app.T("Tuần này hơi yên ắng…", "A quiet week here…"),
            message: place.map {
                app.T("Chưa có buổi nào ở \($0) khớp bộ lọc. Xem tất cả hoặc mở bản đồ để tìm quanh bạn nhé!",
                      "Nothing in \($0) matches these filters yet. See everything, or open the map to look around you!")
            } ?? app.T("Chưa có buổi nào khớp bộ lọc này. Bỏ lọc để xem mọi buổi vui tuần này nhé!",
                       "Nothing matches these filters yet. Clear them to see every fun gathering this week!"),
            actionTitle: app.T("Xem tất cả sự kiện", "See all events"),
            actionIcon: "sparkles",
            actionID: "home.empty.seeAll",
            action: { app.clearFilters(); app.homeSort = "soonest" },
            secondaryTitle: app.T("Tìm trên bản đồ", "Look on the map"),
            secondaryID: "home.empty.map",
            secondaryAction: { app.goMapExploreFromHome() },
            identifier: "home.empty"
        )
        .padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(app.palette.rule).frame(height: 1)
            Text(app.T("Hết rồi, ra ngoài chơi thôi!", "That's it, go have fun!"))
                .font(BanbeTheme.display(11.5))
                .padding(.top, 34)
                .padding(.bottom, 6)
        }
        .foregroundStyle(app.palette.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Retention roadmap P1 ("Cuối tuần này") — real live+public events for the applicable weekend
    /// (app.weekendEvents), never demo cards. After the main feed on purpose: it's a discovery section, not a
    /// personal one. Note 50: a compact rail (web parity), hidden while the weekend date filter is on, and it
    /// now follows the SAME area + category picks as the feed (it used to ignore both on iOS).
    private var weekendList: [CatalogEvent] {
        Array(app.weekendEvents.map(app.withLive)
            .filter { app.matchesArea($0) }
            .filter { e in app.homeFilters.cats.isEmpty || app.homeFilters.cats.contains(e.catKey) || e.cat2Key.map(app.homeFilters.cats.contains) == true }
            .prefix(12))
    }

    @ViewBuilder
    private var weekendSection: some View {
        let list = weekendList
        // Suppressed during the very first load so it never flashes the empty state.
        if !(app.weekendEventsLoading && list.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Cuối tuần này", "This weekend"))
                    .font(BanbeTheme.display(20))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                if list.isEmpty {
                    Text(app.T("Chưa có sự kiện phù hợp cuối tuần này.", "No matching events this weekend yet."))
                        .font(.app(size: 12.5)).opacity(0.7)
                        .padding(.horizontal, 20).padding(.bottom, 12)
                        .accessibilityIdentifier("weekend.empty")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(list) { event in WeekendRailCard(event: event).id("weekend-\(event.key)") }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 10)
                    }
                    .rootSwipeExclusion("homeWeekend")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.weekendSection")
        }
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

/// Home header bell → Notifications (back returns Home). Unread count is
/// text in a badge AND in the spoken label, never colour alone.
struct HomeNotificationsButton: View {
    @EnvironmentObject private var app: AppState
    var size: CGFloat = 52

    var body: some View {
        SwipeSafeButton {
            Haptics.light()
            app.goNotifications(back: .home)
        } label: {
            NotificationsGlyph(color: app.palette.ink, filled: false)
                .frame(width: 24, height: 24)
                .frame(width: size, height: size)
                .background { Color.clear.nativeGlass(Circle(), interactive: true) }
                .overlay(alignment: .topTrailing) {
                    if app.unreadNotifications > 0 {
                        Text(app.unreadNotifications > 99 ? "99+" : "\(app.unreadNotifications)")
                            .font(.app(size: 11, weight: .bold)).monospacedDigit()
                            .foregroundStyle(BanbeTheme.onAlert)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(BanbeTheme.alert, in: Capsule())
                            .offset(x: 2, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Where the bell is, so Notifications can burst out of it (and shrink back into it).
        .background(GeometryReader { g in
            Color.clear
                .onAppear { app.homeBellFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in app.homeBellFrame = f }
        })
        .accessibilityIdentifier("home.notifications")
        .accessibilityLabel(app.unreadNotifications > 0
            ? app.T("Thông báo, \(app.unreadNotifications) chưa đọc", "Notifications, \(app.unreadNotifications) unread")
            : app.T("Thông báo", "Notifications"))
    }
}

/// Note 64: only the first card of the feed is the v3 tour's "an event" target.
private struct FirstCardTourTarget: ViewModifier {
    let isFirst: Bool
    func body(content: Content) -> some View {
        if isFirst { content.tourTarget("tour.home.eventCard") } else { content }
    }
}

/// A Home section header that pins under the folded band (unified discovery): opaque page paper, so the content scrolls
/// beneath it unseen, and a hairline under it only while it is pinned or being pushed off. Pinned = its top has reached
/// the scroll view's top edge (`space`, set on Home's scroll view). The check reads geometry in a background only — no
/// state is written per frame.
struct HomePinnedSectionHeader: ViewModifier {
    static let space = "home.feed.scroll"
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opaque paper only: no hairline under a pinned header (owner 2026-11-20, same as web).
            .background {
                app.palette.paper
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
    }
}

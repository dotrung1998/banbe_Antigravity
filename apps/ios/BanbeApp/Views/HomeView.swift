import SwiftUI

/// The feed — a port of src/screens/Home.jsx: header (wordmark, language
/// toggle, area picker, notification bell, messages, account), the held-spot
/// banner, the "Your events" strip, category filters, and the photo cards.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()
    // TASK 4 (2026-09-22 nineteenth follow-up) — one-shot guard so the
    // retry below (see its own comment) only ever fires once per Home
    // mount, never repeatedly fighting the user's own subsequent scrolling
    // (which keeps updating `app.homeScrollAnchorID` live via
    // `.scrollPosition(id:)`'s own two-way binding — see requirement 4).
    @State private var didAttemptScrollRestore = false

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
            onOpenPayment: { app.openPaymentDetails($0, back: .home) },
            onOpenMyRefunds: { app.openMyRefunds(back: .home) },
            T: app.T
        ))
        if app.canHost {
            goer += buildActionCenterItems(ActionCenterInputs(
                role: .host, now: tick,
                verifications: app.verifications, refundQueue: app.refundQueue, orgHolding: app.organizerHoldingSummary,
                onOpenVerifications: { app.openVerifications() },
                onOpenRefundCenter: { app.openVerifications() },
                onOpenDashboard: { app.goDashboard() },
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
        ScreenScaffold(tracksBottomBarScroll: true, scrollPositionID: $app.homeScrollAnchorID) {
            // Lazy, so only the cards actually on screen fetch their photo —
            // the eager VStack kicked off all ~21 hero downloads at launch
            // and they all fought for the same bandwidth.
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                // TASK A (2026-10-01 UX foundation pass) — replaces the old
                // fixed four-banner `paymentBanners` block: one unified,
                // priority-sorted, 3-card-capped Action Center covering both
                // roles this account can hold. heldEvent itself stays in use
                // for tagging the "Your events" strip further down.
                ActionCenterView(items: actionItems, onSeeAll: { app.goNotifications() })
                if !app.savedStrip.isEmpty { savedStrip }
                storyRow
                filterTabs
                homeExtraFilterChips
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
        .task {
            guard app.userID != nil else { return }
            await app.loadPaymentBookings()
            await app.loadMyRefunds()
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
        // Retention roadmap P1 ("Cuối tuần này") — public info, same as
        // loadHomeLiveEvents above (runs for every visitor).
        .task { await app.loadWeekendEvents() }
        // Blocker fix (retention roadmap follow-up) — a saved/attending
        // real (non-catalogue) event needs its own fetch for savedStrip to
        // resolve it instead of quietly skipping it.
        .task { await app.loadMissingRealEvents(for: app.favorites + app.attending) }
        .onAppear {
            startTickingIfNeeded()
            retryScrollRestoreIfNeeded()
        }
        .onDisappear { tickTask?.cancel() }
        // Task 1 (2026-09-22 twelfth follow-up) — collects every visible
        // story ring's own global frame for StoryViewerView's expand/
        // shrink-toward-ring transition (see AppState.swift's own comment
        // on storyRingFrames).
        .onPreferenceChange(StoryRingFramePreferenceKey.self) { app.storyRingFrames = $0 }
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

    // Task 2c (2026-09-21 follow-up) — a quick Appearance (light/dark)
    // toggle next to the existing language/area switchers, separated by
    // this app's own "▪" glyph (already used throughout its copy, e.g.
    // event captions like "Th 5, 09.07 ▪ 21:00") rather than a new divider
    // style. Wired to the SAME `toggleTheme` Preferences already uses — no
    // parallel theme state.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            BanbeLogo(kind: .wordmark, width: 126)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    // Task 1 (2026-09-21 follow-up) — bumped 11pt -> 13pt,
                    // just enough to read/tap more easily without
                    // unbalancing the rest of the header row.
                    // Task 3 (2026-09-22 twelfth follow-up) — area/appearance
                    // brought up to the SAME 13pt/semibold + padded hit-area
                    // as language, matching web's Home.jsx parity fix.
                    Button(app.T("English", "Tiếng Việt")) { app.toggleLang() }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("header.lang")
                    Text("▪").font(.system(size: 9)).opacity(0.4)
                    Button("banbe ▪︎ \(app.currentArea.key == "all" ? "Sài Gòn" : app.currentArea.label) ▾") {
                        app.openArea()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("header.area")
                    Text("▪").font(.system(size: 9)).opacity(0.4)
                    // No `toggleTheme()` exists on iOS — Preferences.swift's
                    // own theme picker already uses `pickTheme(_:)` directly
                    // (the exact write path, incl. persistence); this just
                    // calls the same function with the flipped value rather
                    // than adding a parallel toggle.
                    Button(app.theme == "dark" ? app.T("Sáng", "Light") : app.T("Tối", "Dark")) {
                        app.pickTheme(app.theme == "dark" ? "light" : "dark")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("header.theme")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        // The web header fits in a narrower face; scale rather than clip if
        // a longer area name (or English) pushes the row past the edge.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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
                        Button { app.goEvent(event.key) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ZStack(alignment: .topLeading) {
                                    CatalogPhoto(path: event.img, height: 96, width: 152, cornerRadius: 12)
                                    PhotoChip(text: app.trStatus(savedTag(event).0), background: savedTag(event).1)
                                        .padding(6)
                                }
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
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
                Button { app.openPulseViewer() } label: {
                    VStack(spacing: 5) {
                        PulseRingGlyph()
                        Text(app.T("Banbe Pulse", "Banbe Pulse"))
                            .font(.system(size: 9.5)).foregroundStyle(app.palette.ink).lineLimit(1).frame(width: 60)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.pulseAvatar")
                ForEach(app.homeStories) { group in
                    Button { app.openStoryViewer(group.organizerId, originRect: app.storyRingFrames[group.organizerId]) } label: {
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
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
    }

    /// Matches the web strip's tag rules: cancelled / past / on hold /
    /// paid / saved, each with its own chip colour.
    private func savedTag(_ event: CatalogEvent) -> (String, Color) {
        if event.cancelled { return ("Đã hủy", BanbeTheme.Chip.cancelled) }
        if event.endedHoursAgo != nil { return ("Đã diễn ra", BanbeTheme.Chip.past) }
        if event.key == app.heldEvent?.key { return ("Đang giữ", BanbeTheme.Chip.hold) }
        if app.isGoing(event.key) { return ("Đã thanh toán", BanbeTheme.Chip.going) }
        return ("Đã lưu", BanbeTheme.Chip.saved)
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

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(filters, id: \.key) { filter in
                    let active = app.filter == filter.key
                    Button { app.pickFilter(filter.key) } label: {
                        VStack(spacing: 6) {
                            Text(app.T(filter.vi, filter.en))
                                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                            Rectangle()
                                .fill(active ? app.palette.ink : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filter.\(filter.key)")
                }
            }
            .padding(.horizontal, 20)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 16)
        .padding(.bottom, 14)
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
        return FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(chips, id: \.key) { chip in
                Button { app.toggleHomeFilter(chip.key) } label: {
                    Text(app.T(chip.vi, chip.en))
                        .font(.system(size: 12, weight: chip.active ? .bold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(chip.active ? app.palette.ink : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filter.\(chip.key.lowercased())")
            }
        }
        .padding(.horizontal, 20)
        .foregroundStyle(app.palette.ink)
        .padding(.bottom, 14)
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(app.T(
                "Chưa có buổi nào ở \(app.currentArea.key == "all" ? "mục này" : app.currentArea.label) tuần này, thử mục khác xem sao!",
                "Nothing in \(app.currentArea.key == "all" ? "this category" : app.currentArea.label) this week, try another one!"
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
        Button {
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
        Button { app.goEvent(event.key) } label: {
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
                    Button { app.toggleFavorite(event.key) } label: {
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

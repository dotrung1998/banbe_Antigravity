import SwiftUI

/// The feed — a port of src/screens/Home.jsx: header (wordmark, language
/// toggle, area picker, notification bell, messages, account), the held-spot
/// banner, the "Your events" strip, category filters, and the photo cards.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()

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
                // Supersedes the old single-booking heldBanner below: this
                // covers both payment phases, both roles, and every booking
                // this account has — not just the one most recently reserved
                // in the current session. heldEvent itself stays in use for
                // tagging the "Your events" strip further down.
                paymentBanners
                if !app.savedStrip.isEmpty { savedStrip }
                if !app.homeStories.isEmpty { storyRow }
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
                hostLink
            }
            .padding(.bottom, 100)
        }
        .task {
            guard app.userID != nil else { return }
            await app.loadPaymentBookings()
            if app.canHost {
                await app.loadVerifications()
                await app.loadOrganizerHoldingSummary()
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
        .onAppear { startTickingIfNeeded() }
        .onDisappear { tickTask?.cancel() }
        // Task 1 (2026-09-22 twelfth follow-up) — collects every visible
        // story ring's own global frame for StoryViewerView's expand/
        // shrink-toward-ring transition (see AppState.swift's own comment
        // on storyRingFrames).
        .onPreferenceChange(StoryRingFramePreferenceKey.self) { app.storyRingFrames = $0 }
    }

    private func startTickingIfNeeded() {
        tickTask?.cancel()
        guard anyCountdownVisible else { return }
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

    @ViewBuilder
    private var paymentBanners: some View {
        // Both phases of the payment state machine, both roles this account
        // can hold: what I (as a buyer) am waiting on, and — separately —
        // what my own events' buyers are waiting on me for.
        if let holding = app.myHolding {
            PhaseBanner(
                label: app.T("Đang giữ chỗ", "Holding a seat"),
                detail: holding.eventName + (holding.qty > 1 ? " ▪︎ \(holding.qty)" + app.T(" vé", " tix") : "")
                    + app.T(" ▪︎ trả để xác nhận", " ▪︎ pay to confirm"),
                countdown: Countdown.format(Countdown.secondsUntil(holding.holdExpiresAt, now: tick))
            ) { app.openPaymentDetails(holding.id, back: .home) }
        }
        if let pending = app.myPendingVerification {
            PhaseBanner(
                label: app.T("Đang chờ xác nhận", "Awaiting confirmation"),
                detail: pending.eventName + app.T(" ▪︎ đồng hồ đã dừng, chỗ được khoá", " ▪︎ clock stopped, seat locked"),
                countdown: nil
            ) { app.openPaymentDetails(pending.id, back: .home) }
        }
        if app.organizerPendingCount > 0 {
            let soonest = app.organizerSoonestVerifyDue
            let secondsLeft = Countdown.secondsUntil(soonest, now: tick)
            PhaseBanner(
                label: app.T("Chờ bạn xác nhận thanh toán", "Payments awaiting your OK"),
                detail: "\(app.organizerPendingCount)" + app.T(" khoản", app.organizerPendingCount == 1 ? " payment" : " payments")
                    + (soonest != nil ? app.T(" ▪︎ sớm nhất còn", " ▪︎ soonest in") : ""),
                countdown: soonest != nil ? Countdown.format(secondsLeft) : nil,
                urgent: soonest != nil && secondsLeft == 0
            ) { app.openVerifications() }
        }
        if let orgHolding = app.organizerHoldingSummary {
            PhaseBanner(
                label: app.T("Khách đang giữ chỗ", "Guests holding seats"),
                detail: "\(orgHolding.count)" + app.T(" chỗ", orgHolding.count == 1 ? " seat" : " seats")
                    + app.T(" ▪︎ sớm nhất hết hạn trong", " ▪︎ soonest expires in"),
                countdown: orgHolding.soonestHoldExpiresAt.map { Countdown.format(Countdown.secondsUntil($0, now: tick)) }
            ) { app.goDashboard() }
        }
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
    private var storyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
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

/// One row shape for every payment-phase banner Home shows, on either side
/// of the transaction. `countdown` is optional — PHASE 2 for a buyer has
/// nothing productive to count down (their clock already stopped), so that
/// row renders with no timer rather than a fake or misleading one.
private struct PhaseBanner: View {
    @EnvironmentObject private var app: AppState
    let label: String
    let detail: String
    let countdown: String?
    var urgent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 11.5, weight: .semibold))
                    Text(detail).font(.system(size: 12.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let countdown {
                    Text(countdown)
                        .font(BanbeTheme.display(18))
                        .monospacedDigit()
                        .foregroundStyle(urgent ? BanbeTheme.alert : app.palette.ink)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
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

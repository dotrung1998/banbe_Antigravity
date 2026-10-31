import SwiftUI

// Simple Shell (note 66, admin switch `simple_shell`): the pieces of the new Home that are not part of HomeView's
// own discovery feed: the Going out | Hosting mode switch, the host Home sections and the dock "+" event-story
// picker. Nothing here renders while the switch is off (HomeView / RootView gate every use).

/// The Home header's segmented mode switch (plan item 1, owner decision 2026-10-31). It changes only the Home VIEW
/// (`app.homeView`, session-only); organizer mode stays as it is. Hosting is locked while organizer mode is off: a
/// lock glyph, muted, still focusable, and a tap opens the Start hosting invitation (a guest is asked to sign in
/// first) through `app.startHosting(land: .home)`, never flipping the mode directly.
struct HomeModeSwitch: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var font: CGFloat = 14

    private var hosting: Bool { app.effectiveHomeView == .host }
    private var hostLocked: Bool { HomeMode.hostSegmentLocked(organizerMode: app.isSignedIn && app.organizerMode) }

    var body: some View {
        HStack(spacing: 0) {
            segment(host: false, title: app.T("Đi chơi", "Going out"), position: 1, id: "home.mode.goer")
            segment(host: true, title: app.T("Tổ chức", "Hosting"), position: 2, id: "home.mode.host")
        }
        .padding(2)
        .background(app.palette.surface2, in: Capsule())
        .fixedSize()
        .disabled(app.organizerModeBusy)
        .animation(Motion.animation(.spring(response: 0.3, dampingFraction: 0.85), reduce: reduceMotion), value: hosting)
        .animation(Motion.fade(.easeOut(duration: 0.2), reduce: reduceMotion), value: hostLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Chế độ", "Mode"))
        .accessibilityIdentifier("home.modeSwitch")
        .tourTarget("tour.home.modeSwitch")
    }

    private func segment(host: Bool, title: String, position: Int, id: String) -> some View {
        let selected = host == hosting
        let locked = host && hostLocked
        return Button { select(host: host) } label: {
            HStack(spacing: 5) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: font - 3, weight: .semibold))
                        .accessibilityHidden(true)
                        // The lock fades and shrinks away when hosting unlocks (a plain fade under Reduce Motion).
                        .transition(Motion.transition(.scale(scale: 0.4).combined(with: .opacity), reduce: reduceMotion))
                }
                Text(title)
                    .font(.system(size: font, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(selected ? app.palette.paper : (locked ? app.palette.ink3 : app.palette.ink))
            .background { if selected { Capsule().fill(app.palette.ink) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? HomeMode.lockedLabel(app.T) : title)
        .accessibilityValue(locked ? app.T("đã khoá", "locked") : app.T("\(position) trên 2", "\(position) of 2"))
        .accessibilityHint(locked ? HomeMode.lockedHint(app.T) : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    private func select(host: Bool) {
        if host && hostLocked {
            Haptics.light()
            // Never flips organizer mode here: sign-in prompt (guest) or the Start hosting invitation.
            app.startHosting(land: .home)
            return
        }
        guard host != hosting else { return }
        Haptics.selection()
        // Only the Home view changes; organizer mode stays on (owner decision 2026-10-31).
        app.homeView = host ? .host : .goer
        app.resetHomeScrollToTop()
    }
}

/// Home while Hosting (switch on): ONE hero (the next event you host, or "Plan your next event"), then the host
/// Things-to-do, the submitted-events summary and up to three KPI tiles. Reads only what the Dashboard and Reports
/// already load; the loaders it calls are the Dashboard's own (no new fetching).
struct HostHomeSections: View {
    @EnvironmentObject private var app: AppState
    let actionItems: [ActionCenterItem]

    private var nextHosted: CatalogEvent? {
        let events = app.myOrgEvents
        let hosted: [HomeHero.HostedEvent] = events.compactMap { e in
            guard let start = e.startDate else { return nil }
            let status = e.cancelled ? "cancelled" : (e.endedHoursAgo != nil ? "ended" : "live")
            return HomeHero.HostedEvent(key: e.key, startsAt: start, endsAt: nil, status: status)
        }
        guard let pick = HomeHero.host(hosted, now: Date()) else { return nil }
        return events.first { $0.key == pick.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let e = nextHosted { hero(e) } else { planCard }
            quickActions.padding(.top, 16)
            ActionCenterView(items: actionItems, onSeeAll: { app.goNotifications() })
                .padding(.top, 16)
            upcomingList.padding(.top, 16)
            submittedSummary.padding(.top, 16)
            kpiTiles.padding(.top, 16)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 4)
        .task {
            await app.loadMyEvents()
            await app.loadMyOrgEventSummaries()
        }
        // Note 69: "This month" used to appear only after Reports had been opened this session. Load the host numbers
        // here when nothing host-scoped is in hand (same RPC and range as Reports).
        .task(id: app.myOrganizerID) {
            guard let org = app.myOrganizerID, !app.reportsLoading else { return }
            if let r = app.reportsData, r.success, ReportRole(scope: r.scope) == .host { return }
            await app.fetchAccountKpis(scope: "host", organizerID: org, rangeDays: app.reportsRangeDays,
                                       customStart: app.reportsCustomStart, customEnd: app.reportsCustomEnd)
        }
    }

    /// The most recent event you hosted that has already started (what "start from your last event" copies).
    private var lastHosted: CatalogEvent? {
        let now = Date()
        return app.myOrgEvents.filter { !$0.cancelled && ($0.startDate.map { $0 < now } ?? false) }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Up to three upcoming hosted events after the hero's.
    private var upcoming: [CatalogEvent] {
        let now = Date()
        return Array(app.myOrgEvents
            .filter { !$0.cancelled && $0.endedHoursAgo == nil && ($0.startDate.map { $0 > now } ?? false) && $0.key != nextHosted?.key }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .prefix(3))
    }

    // MARK: Quick actions (note 69)

    private struct QuickAction: Identifiable { let id: String, short: String, title: String, icon: String, run: () -> Void }

    private var quickActionItems: [QuickAction] {
        var out: [QuickAction] = []
        // The plan card already has "Create event"; with a hero event, Create joins the shortcuts instead. The hero
        // has its own Check-in and Message buttons, so they are not repeated here.
        if nextHosted != nil {
            out.append(QuickAction(id: "create", short: app.T("Tạo", "Create"), title: app.T("Tạo sự kiện", "Create event"), icon: "plus") { app.goCreate() })
        }
        out += [
            QuickAction(id: "guests", short: app.T("Khách", "Guests"), title: app.T("Khách & thanh toán", "Guests & payments"), icon: "person.2.fill") { app.openVerifications(back: .home) },
            QuickAction(id: "refunds", short: app.T("Hoàn tiền", "Refunds"), title: app.T("Hoàn tiền", "Refunds"), icon: "arrow.uturn.backward") { app.openVerificationsRefunds(back: .home) },
            QuickAction(id: "story", short: app.T("Story", "Story"), title: app.T("Đăng story", "Post a story"), icon: "camera.fill") { app.storyLibraryPickerOpen = true },
            QuickAction(id: "surveys", short: app.T("Khảo sát", "Surveys"), title: app.T("Khảo sát & ý tưởng", "Surveys & ideas"), icon: "lightbulb.fill") { app.screen = .surveysHosting },
        ]
        if let org = app.myOrganizerID {
            out += [
                QuickAction(id: "profile", short: app.T("Hồ sơ", "Profile"), title: app.T("Hồ sơ tổ chức", "Host profile"), icon: "storefront.fill") { app.openOrganizerProfile(organizerID: org, back: .home) },
                QuickAction(id: "reports", short: app.T("Báo cáo", "Reports"), title: app.T("Báo cáo", "Reports"), icon: "chart.bar.fill") { app.openReports(scope: "host", organizerID: org, back: .home) },
            ]
        }
        return out
    }

    /// Icon tiles with a one-word label (the full name is what VoiceOver reads). The row scrolls on its own: like
    /// Going out's chip row, it is excluded from the dock's root swipe, so a drag here never switches screens.
    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(quickActionItems) { a in
                    Button { Haptics.light(); a.run() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: a.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 56, height: 56)
                                .background(app.palette.block, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            Text(a.short)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(app.palette.ink2)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(width: 64)
                        .foregroundStyle(app.palette.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.title)
                    .accessibilityIdentifier("home.host.quick.\(a.id)")
                }
            }
            .padding(.horizontal, 20)
        }
        .rootSwipeExclusion("homeHostQuickActions")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Lối tắt tổ chức", "Hosting shortcuts"))
        .accessibilityIdentifier("home.host.quick")
    }

    // MARK: Upcoming (note 69)

    @ViewBuilder
    private var upcomingList: some View {
        let list = upcoming
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Sắp tới", "Coming up")).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.key) { i, e in
                        if i > 0 { Divider().overlay(app.palette.divider).padding(.leading, 64) }
                        Button { app.goEvent(e.key) } label: {
                            HStack(spacing: 12) {
                                CatalogPhoto(path: e.img, height: 40, width: 40, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(app.discoveryWhenLabel(e.startDate, timeZone: EventMarket.timeZone(e.timeZoneID)))
                                        .font(.footnote).foregroundStyle(app.palette.ink2)
                                }
                                Spacer(minLength: 8)
                                if let fill = app.eventFill[e.key], fill.capacity > 0 {
                                    Text("\(fill.booked)/\(fill.capacity)")
                                        .font(.footnote.weight(.semibold)).monospacedDigit()
                                        .accessibilityLabel(app.T("\(fill.booked) trên \(fill.capacity) chỗ đã bán", "\(fill.booked) of \(fill.capacity) seats sold"))
                                }
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                    .foregroundStyle(app.palette.ink3).accessibilityHidden(true)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.host.upcoming.\(e.key)")
                    }
                }
                .background(app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)
            .accessibilityIdentifier("home.host.upcoming")
            .task(id: list.map(\.key)) {
                let missing = list.map(\.key).filter { app.eventFill[$0] == nil }
                if !missing.isEmpty { await app.loadPublicEventFill(ids: missing) }
            }
        }
    }

    // MARK: Hero

    private func hero(_ e: CatalogEvent) -> some View {
        let fill = app.eventFill[e.key]
        let when = app.discoveryWhenLabel(e.startDate, timeZone: EventMarket.timeZone(e.timeZoneID))
        return VStack(alignment: .leading, spacing: 12) {
            Button { app.goEvent(e.key) } label: {
                HStack(alignment: .top, spacing: 12) {
                    CatalogPhoto(path: e.img, height: 64, width: 64, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.T("Sự kiện tiếp theo của bạn", "Your next event"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(app.palette.ink2)
                        Text(e.name).font(BanbeTheme.display(20)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(when).font(.subheadline).foregroundStyle(app.palette.ink2)
                        if let fill, fill.capacity > 0 {
                            Text(app.T("\(fill.booked)/\(fill.capacity) chỗ đã bán", "\(fill.booked)/\(fill.capacity) seats sold"))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .accessibilityIdentifier("home.host.hero.seats")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 10) {
                heroButton(app.T("Điểm danh", "Check-in"), icon: "qrcode.viewfinder", primary: true, id: "home.host.checkin") {
                    app.openAttendance(e.key, back: .home)
                }
                heroButton(app.T("Nhắn khách", "Message guests"), icon: "bubble.left.and.bubble.right", primary: false,
                           id: "home.host.message") { app.goInbox() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.host.hero")
        .task(id: e.key) {
            if app.eventFill[e.key] == nil { await app.loadPublicEventFill(ids: [e.key]) }
        }
    }

    private func heroButton(_ title: String, icon: String, primary: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(primary ? app.palette.paper : app.palette.ink)
                // Nested inside the hero block: the inset fill, never block-on-block.
                .background(primary ? app.palette.ink : app.palette.blockInset, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Lên kế hoạch cho sự kiện tiếp theo", "Plan your next event"))
                .font(BanbeTheme.display(20))
                .accessibilityAddTraits(.isHeader)
            // Note 69: one short line. Names the event that will be copied when there is one.
            Group {
                if let last = lastHosted {
                    Text(app.T("Sao chép \"\(last.name)\" · khoảng 5 phút", "Copy \"\(last.name)\" · about 5 min"))
                        .accessibilityIdentifier("home.host.plan.last")
                } else {
                    Text(app.T("Khoảng 5 phút", "About 5 minutes"))
                }
            }
            .font(.subheadline)
            .foregroundStyle(app.palette.ink2)
            .lineLimit(1)
            InkButton(title: app.T("Tạo sự kiện", "Create event"), cornerRadius: 999) { app.goCreate() }
                .padding(.top, 4)
                .accessibilityIdentifier("home.host.plan.create")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.host.plan")
    }

    // MARK: Submitted events

    /// Plan item 5: no wrapping card any more. A header row (opens the host dashboard) and three block tiles directly
    /// on paper, the same tiles as the KPIs below, so there is no beige-on-beige nesting.
    private var submittedSummary: some View {
        let live = app.myOrgEvents.filter(\.isOpen).count
        let chips: [(String, Int, String)] = [
            (app.T("Chờ duyệt", "Pending"), app.myPendingEvents.count, "pending"),
            (app.T("Cần sửa", "Needs fixing"), app.myNeedsFixEvents.count, "needsFix"),
            (app.T("Đang mở", "Live"), live, "live"),
        ]
        // Note 69: each tile is its own button. Pending / Needs fixing open the dashboard with Submitted events
        // expanded; Live opens it where the live events are.
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.light()
                app.goDashboard(back: .home)
            } label: {
                HStack {
                    Text(app.T("Sự kiện đã gửi", "Submitted events")).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(app.T("Mở trang tổ chức", "Opens your host dashboard"))
            .accessibilityIdentifier("home.host.submitted")
            HostTileGrid(tiles: chips.map { title, n, key in
                HostTileGrid.Tile(id: key, value: "\(n)", label: title,
                                  highlight: key == "needsFix" && n > 0,
                                  identifier: "home.host.submitted.\(key)") {
                    app.dashboardOpenSubmitted = key != "live"
                    app.goDashboard(back: .home)
                }
            })
        }
        .padding(.horizontal, 20)
    }

    // MARK: KPIs (only when Reports already loaded host numbers)

    @ViewBuilder
    private var kpiTiles: some View {
        if let report = app.reportsData, report.success, ReportRole(scope: report.scope) == .host {
            let d = ReportsPresentation.dashboard(report, fallbackScope: "host", T: app.T)
            let tiles = Array(([d.primary].compactMap { $0 } + d.overview).prefix(3))
            if !tiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(app.T("Tháng này", "This month")).font(.headline)
                        Spacer()
                        Button {
                            app.openReports(scope: "host", organizerID: app.myOrganizerID, back: .home)
                        } label: {
                            Text(app.T("Báo cáo ›", "Reports ›")).font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.host.reports")
                    }
                    // Short tile labels (Lib/ReportMetricLabels.swift `short`); the full ones stay in Reports.
                    HostTileGrid(tiles: tiles.map { m in
                        HostTileGrid.Tile(id: m.key, value: m.valueText,
                                          label: ReportMetricLabels.shortLabel(m.key, app.T) ?? m.title,
                                          accessibilityValue: m.accessibilityValue,
                                          identifier: "home.host.kpi.\(m.key)")
                    })
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.host.kpis")
            }
        }
    }
}

/// Plan item 5: equal block tiles in a 3-column grid (Submitted events and the KPIs). Every tile is the same width
/// (`maxWidth: .infinity` in equal grid columns) and at least 88pt tall; padding 16, gap 8; value 20 semibold, label
/// 13 regular wrapping to at most 2 lines (no ellipsis). At accessibility text sizes the tiles stack in one column.
/// Web twin: HostHome.jsx `.host-tiles` (grid-template-columns: repeat(3, 1fr)).
struct HostTileGrid: View {
    struct Tile: Identifiable {
        let id: String
        let value: String
        let label: String
        var highlight = false
        var accessibilityValue: String? = nil
        var identifier: String? = nil
        /// Note 69: a tile can be its own button (Submitted events: each status opens its own place).
        var onTap: (() -> Void)? = nil
    }

    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tiles: [Tile]

    static let spacing: CGFloat = 8
    static let minHeight: CGFloat = 88

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<(start + columns), id: \.self) { i in
                        if i < tiles.count {
                            tile(tiles[i])
                        } else {
                            Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ t: Tile) -> some View {
        let base = VStack(alignment: .leading, spacing: 4) {
            Text(t.value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(t.label)
                .font(.system(size: 13))
                .foregroundStyle(app.palette.ink2)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: Self.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(t.highlight ? app.palette.honeyBg : app.palette.block,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        if let onTap = t.onTap {
            Button { Haptics.light(); onTap() } label: { base.contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t.label)
                .accessibilityValue(t.accessibilityValue ?? t.value)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(t.identifier ?? "tile.\(t.id)")
        } else if let id = t.identifier {
            base
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t.label)
                .accessibilityValue(t.accessibilityValue ?? t.value)
                .accessibilityIdentifier(id)
        } else {
            base
        }
    }
}

/// The dock "+" (host) → "Share one of my events": the same picker as Account's Post a story menu, posting through
/// the same `beginEventStory` (nothing is published until the host taps "Post story").
struct DockEventStoryPickerSheet: View {
    @EnvironmentObject private var app: AppState
    @State private var busyKey: String?
    @State private var loaded = false

    var body: some View {
        let events = app.myOrgEvents.filter { $0.isOpen }
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if !loaded {
                        ProgressView().padding(.top, 40)
                    } else if events.isEmpty {
                        Text(app.T("Bạn chưa có sự kiện nào đang mở để đăng.", "You have no live events to post yet."))
                            .font(.subheadline).foregroundStyle(app.palette.ink2).padding(.top, 40)
                    }
                    ForEach(events, id: \.key) { ev in
                        Button {
                            guard busyKey == nil else { return }
                            busyKey = ev.key
                            Task {
                                app.dockEventStoryPickerOpen = false
                                try? await Task.sleep(nanoseconds: 450_000_000)   // let the sheet finish closing
                                await app.beginEventStory(ev)
                                busyKey = nil
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CatalogPhoto(path: ev.img, height: 52, width: 52, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.name).font(BanbeTheme.display(15)).lineLimit(1)
                                    Text(ev.when).font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if busyKey == ev.key { ProgressView() }
                                else { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(app.palette.ink3) }
                            }
                            .padding(12)
                            .frame(minHeight: 44)
                            .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dock.eventStory.\(ev.key)")
                    }
                    Text(app.T("Bạn có thể thêm chữ và liên kết trước khi đăng. Story hiển thị trong 24 giờ.",
                               "You can add text and a link before posting. The story stays up for 24 hours."))
                        .font(.caption).foregroundStyle(app.palette.ink2).padding(.top, 6)
                }
                .padding(20)
            }
            .foregroundStyle(app.palette.ink)
            .background(app.palette.paper.ignoresSafeArea())
            .task {
                loaded = false
                await app.loadMyOrgEventSummaries()
                loaded = true
            }
            .navigationTitle(app.T("Đăng sự kiện lên story", "Post an event to your story"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Đóng", "Close")) { app.dockEventStoryPickerOpen = false }
                        .accessibilityIdentifier("dock.eventStory.close")
                }
            }
        }
        .hidesDock("dockEventStoryPicker")
    }
}

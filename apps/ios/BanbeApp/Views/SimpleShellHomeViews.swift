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
            ActionCenterView(items: actionItems, onSeeAll: { app.goNotifications() })
                .padding(.top, 16)
            submittedSummary.padding(.top, 16)
            kpiTiles.padding(.top, 16)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 4)
        .task {
            await app.loadMyEvents()
            await app.loadMyOrgEventSummaries()
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
            Text(app.T("Bắt đầu từ sự kiện gần nhất của bạn. Mất khoảng 5 phút.",
                       "Start from your last event. It takes about 5 minutes."))
                .font(.subheadline)
                .foregroundStyle(app.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
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
        return Button {
            Haptics.light()
            app.goDashboard(back: .home)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(app.T("Sự kiện đã gửi", "Submitted events")).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                HostTileGrid(tiles: chips.map { title, n, key in
                    HostTileGrid.Tile(id: key, value: "\(n)", label: title,
                                      highlight: key == "needsFix" && n > 0)
                })
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.T("Sự kiện đã gửi: \(chips[0].1) chờ duyệt, \(chips[1].1) cần sửa, \(live) đang mở",
                                  "Submitted events: \(chips[0].1) pending, \(chips[1].1) needs fixing, \(live) live"))
        .accessibilityHint(app.T("Mở trang tổ chức", "Opens your host dashboard"))
        .accessibilityIdentifier("home.host.submitted")
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
        if let id = t.identifier {
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

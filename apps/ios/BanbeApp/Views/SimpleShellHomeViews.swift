import SwiftUI

// Simple Shell (note 66, admin switch `simple_shell`): the pieces of the new Home that are not part of HomeView's
// own discovery feed: the Going out | Hosting mode switch, the host Home sections and the dock "+" event-story
// picker. Nothing here renders while the switch is off (HomeView / RootView gate every use).

/// The Home header's segmented mode switch. Mode = `app.organizerMode` (the same preference Account's toggle and the
/// `set_organizer_mode` RPC own). Going out turns organizer mode off; Hosting asks a guest to sign in, and otherwise
/// runs Account's "Start hosting" (toggleOrganizerMode turns it on; for someone who never hosted that IS the start).
struct HomeModeSwitch: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var font: CGFloat = 14

    private var hosting: Bool { app.isSignedIn && app.organizerMode }

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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Chế độ", "Mode"))
        .accessibilityIdentifier("home.modeSwitch")
        .tourTarget("tour.home.modeSwitch")
    }

    private func segment(host: Bool, title: String, position: Int, id: String) -> some View {
        let selected = host == hosting
        return Button { select(host: host) } label: {
            Text(title)
                .font(.system(size: font, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .background { if selected { Capsule().fill(app.palette.ink) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(app.T("\(position) trên 2", "\(position) of 2"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    private func select(host: Bool) {
        guard host != hosting else { return }
        Haptics.selection()
        if !host {
            // Going out: organizer mode off (only reachable while it is on, so always signed in).
            app.toggleOrganizerMode()
            return
        }
        guard app.isSignedIn else { return app.promptSignIn(.host) }
        app.toggleOrganizerMode()
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
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .background(primary ? app.palette.ink : app.palette.surface2, in: Capsule())
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
        .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.host.plan")
    }

    // MARK: Submitted events

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
                HStack(spacing: 8) {
                    ForEach(chips, id: \.2) { title, n, key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(n)").font(.title3.weight(.semibold)).monospacedDigit()
                            Text(title).font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(key == "needsFix" && n > 0 ? app.palette.honeyBg : app.palette.surface2,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(16)
            .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    HStack(spacing: 8) {
                        ForEach(tiles) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.valueText).font(.title3.weight(.semibold)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Text(m.title).font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(app.palette.surface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(m.title)
                            .accessibilityValue(m.accessibilityValue)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.host.kpis")
            }
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

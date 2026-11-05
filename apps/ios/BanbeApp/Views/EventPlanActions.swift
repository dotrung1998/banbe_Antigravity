import SwiftUI

/// "I put this event on my Apple Calendar" marks, device-local like `InAppCalendarStore`. The
/// system editor runs out of process and no calendar permission is requested, so the app can only
/// know the person pressed Save — it cannot see a later deletion in Calendar (the menu offers
/// "Clear mark" for that). Stores event keys only.
struct AppleCalendarMarkStore {
    var defaults: UserDefaults = .standard
    static func key(_ uid: UUID) -> String { "banbe.schedule.appleCal.v1.\(uid.uuidString)" }
    func contains(_ eventKey: String, uid: UUID) -> Bool { keys(uid).contains(eventKey) }
    func add(_ eventKey: String, uid: UUID) {
        var k = keys(uid)
        if !k.contains(eventKey) { k.append(eventKey); defaults.set(k, forKey: Self.key(uid)) }
    }
    func remove(_ eventKey: String, uid: UUID) {
        defaults.set(keys(uid).filter { $0 != eventKey }, forKey: Self.key(uid))
    }
    private func keys(_ uid: UUID) -> [String] { defaults.stringArray(forKey: Self.key(uid)) ?? [] }
}

/// Event Detail's title (note 46, note 77): the event name alone. The calendar choices moved into the ticket stub
/// (`EventPlanButtons`) so the title has room and the stub's right side is used.
struct EventPlanTitleRow: View {
    @EnvironmentObject private var app: AppState
    let event: CatalogEvent
    /// Note 70 (story-first): the title sits on the event photo over a dark scrim, so it is white.
    var onPhoto = false

    var body: some View {
        Text(event.name)
            .font(BanbeTheme.display(28))
            .foregroundStyle(onPhoto ? Color.white : app.palette.ink)
            .shadow(color: onPhoto ? .black.opacity(0.35) : .clear, radius: 4, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Note 77: a tiny tear-off calendar page (red band with the month, the day number below): the "phone calendar"
/// icon on Event Detail and Confirmed, so it never looks like the banbe Schedule button.
struct MiniCalendarPage: View {
    var day: String
    /// The short weekday (or month) shown above the day, like the Calendar app icon.
    var month: String
    var size: CGFloat = 44

    var body: some View {
        // Monochrome Calendar icon (iOS 27 dark/tinted style): black tile, grey weekday, white day.
        VStack(spacing: size * 0.02) {
            Text(month.isEmpty ? " " : month.uppercased())
                .font(.system(size: size * 0.17, weight: .semibold)).tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.62))
            Text(day.isEmpty ? "+" : day)
                .font(.system(size: size * 0.46, weight: .regular))
                .foregroundStyle(.white)
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .frame(width: size, height: size)
        .background(Color(red: 0.07, green: 0.07, blue: 0.075), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// Note 77: two calendar tiles inside the ticket stub, each with its own look so they are never confused:
/// - banbe Schedule: a clay square with a calendar glyph and a sparkle (the in-app agenda, not a reservation).
///   One tap adds; once added a tap opens Remove.
/// - Phone calendar: a mini tear-off calendar page (red band, the event's day number). A tap opens the system
///   editor with no permission; once marked, a tap offers Add again / Clear mark.
/// Status text goes to `onMessage` (the stub shows it full width); without it the tiles show it themselves.
struct EventPlanButtons: View {
    @EnvironmentObject private var app: AppState
    let event: CatalogEvent
    /// The day number and month on the calendar page (the stub's date block).
    var day: String = ""
    var month: String = ""
    var axis: Axis = .vertical
    var onMessage: ((String?) -> Void)?
    @State private var exportRequest: CalendarExportRequest?
    @State private var message: String?
    @State private var appleMarked = false
    @State private var messageTask: Task<Void, Never>?
    @State private var scheduleOpen = false
    @State private var appleOpen = false

    private var info: ScheduleEventInfo { app.scheduleInfo(for: app.withLive(event)) }
    private var source: ScheduleSource? { app.scheduleSource(for: event.key) }
    private var canAdd: Bool { SchedulePresentation.canAdd(info, now: Date()) }
    private var available: Bool { info.start != nil && !info.cancelled }

    var body: some View {
        if available {
            VStack(alignment: .trailing, spacing: 6) {
                let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    tile(caption: "banbe") { scheduleButton }
                    tile(caption: app.T("Lịch", "Calendar")) { appleButton }
                }
                if onMessage == nil, let message {
                    Text(message).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.8))
                        .accessibilityIdentifier("event.plan.message")
                }
            }
            .onAppear { refreshMark() }
            .sheet(item: $exportRequest) { req in
                SystemEventEditor(draft: req.draft) { result in
                    exportRequest = nil
                    Analytics.track(.systemCalendarEditorResult(result: result.rawValue))
                    if result == .saved, let uid = app.userID {
                        AppleCalendarMarkStore().add(event.key, uid: uid)
                        refreshMark()
                    }
                    show(result == .saved ? app.T("Đã thêm vào Lịch Apple.", "Added to Apple Calendar.")
                                          : app.T("Chưa thêm vào Lịch Apple.", "Not added to Apple Calendar."))
                }
                .ignoresSafeArea()
            }
        }
    }

    private func tile<C: View>(caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 3) {
            content()
            Text(caption).font(.system(size: 10, weight: .semibold)).foregroundStyle(app.palette.ink2)
                .lineLimit(1).fixedSize()
                .accessibilityHidden(true)
        }
    }

    // MARK: banbe Schedule tile

    private var scheduleButton: some View {
        Button {
            if source != nil { scheduleOpen = true } else { addToSchedule() }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: source != nil ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(colors: [app.palette.clay, app.palette.clay.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.45))
                    .offset(x: 4, y: -4)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .popover(isPresented: $scheduleOpen, arrowEdge: .top) {
            PopoverMenuList(items: scheduleItems) { scheduleOpen = false }
                .environmentObject(app)
        }
        .accessibilityIdentifier("event.plan.schedule")
        .accessibilityLabel(source.map { app.T("Trong lịch banbe (\($0.label(app.T)))", "In banbe Schedule (\($0.label(app.T)))") }
                            ?? app.T("Thêm vào lịch banbe", "Add to banbe Schedule"))
    }

    private var scheduleItems: [PopoverMenuItem] {
        guard let source else { return [] }
        var items = [PopoverMenuItem(id: "event.schedule.inMine",
                                     title: app.T("Đã có trong lịch của tôi · \(source.label(app.T))", "In My schedule · \(source.label(app.T))"),
                                     systemImage: "checkmark.circle.fill", disabled: true) {}]
        if source == .added {
            items.append(PopoverMenuItem(id: "event.schedule.remove", title: app.T("Bỏ khỏi lịch banbe", "Remove from banbe Schedule"),
                                         systemImage: "calendar.badge.minus", destructive: true) {
                app.removeFromBanbeSchedule(event.key)
                show(nil)
            })
        }
        return items
    }

    private func addToSchedule() {
        guard canAdd else { show(app.T("Sự kiện này không thể thêm vào lịch.", "This event can't be added to your schedule.")); return }
        switch app.addToBanbeSchedule(event) {
        case .added: show(app.T("Đã thêm vào lịch banbe. Đây chưa phải đặt chỗ.", "Added to your banbe Schedule. This isn't a reservation."))
        case .ineligible: show(app.T("Sự kiện này không thể thêm vào lịch.", "This event can't be added to your schedule."))
        case .alreadyThere, .needsSignIn: show(nil)
        }
    }

    // MARK: phone calendar tile

    private var appleButton: some View {
        Button {
            if appleMarked { appleOpen = true } else { open() }
        } label: {
            MiniCalendarPage(day: day, month: month)
            .overlay(alignment: .bottomTrailing) {
                if appleMarked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white, Color(red: 0.2, green: 0.62, blue: 0.36))
                        .offset(x: 5, y: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .popover(isPresented: $appleOpen, arrowEdge: .top) {
            PopoverMenuList(items: appleItems) { appleOpen = false }
                .environmentObject(app)
        }
        .accessibilityIdentifier("event.plan.calendar")
        .accessibilityLabel(appleMarked ? app.T("Đã lưu vào Lịch Apple", "Saved to Apple Calendar")
                                        : app.T("Thêm vào Lịch Apple", "Add to Apple Calendar"))
    }

    private var appleItems: [PopoverMenuItem] {
        [PopoverMenuItem(id: "event.appleCalendar", title: app.T("Thêm lại vào Lịch Apple", "Add to Apple Calendar again"),
                         systemImage: "calendar") { open() },
         PopoverMenuItem(id: "event.appleCalendar.clear", title: app.T("Bỏ dấu Lịch Apple", "Clear Apple Calendar mark"),
                         systemImage: "xmark.circle", destructive: true) {
             if let uid = app.userID { AppleCalendarMarkStore().remove(event.key, uid: uid) }
             refreshMark()
         }]
    }

    // MARK: helpers

    private func refreshMark() {
        appleMarked = app.userID.map { AppleCalendarMarkStore().contains(event.key, uid: $0) } ?? false
    }

    /// Short status line; fades after a few seconds.
    private func show(_ text: String?) {
        message = text
        onMessage?(text)
        messageTask?.cancel()
        guard text != nil else { return }
        messageTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            message = nil
            onMessage?(nil)
        }
    }

    private func open() {
        Analytics.track(.systemCalendarEditorOpened)
        if let draft = app.calendarDraft(for: event) {
            exportRequest = CalendarExportRequest(draft: draft)
        } else {
            Analytics.track(.systemCalendarEditorResult(result: CalendarExport.Result.unavailable.rawValue))
            show(app.T("Sự kiện này chưa có giờ bắt đầu.", "This event has no start time yet."))
        }
    }
}

extension AppState {
    /// The pre-filled system-editor draft for one event (nil = no start time).
    func calendarDraft(for e: CatalogEvent) -> CalendarEventDraft? {
        CalendarExport.draft(title: e.name, start: e.startDate, end: nil, location: e.locationLabel ?? "",
                             eventKey: e.key, origin: AppConfig.publicWebOrigin, T: T)
    }
}

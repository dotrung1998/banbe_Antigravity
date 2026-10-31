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

/// Event Detail's title row (note 46): the event name with ONE small glass button at its trailing
/// edge that carries the planning state and opens a menu (like the dock's "+"):
/// - nothing yet  -> one glass circle, calendar-plus icon, label "Discover"
/// - in banbe Schedule -> circle with a check, label "Added"
/// - also saved to Apple Calendar -> two connected glass segments (banbe + Apple), label "Added"
/// The menu offers only what makes sense in that state. "Add to banbe Schedule" is the in-app
/// agenda (not a reservation); "Add to Apple Calendar" opens the system editor with no permission.
struct EventPlanTitleRow: View {
    @EnvironmentObject private var app: AppState
    let event: CatalogEvent
    /// Note 70 (story-first): the title sits on the event photo over a dark scrim, so it is white and the calendar
    /// circle is a clay disc with a white glyph.
    var onPhoto = false
    @State private var exportRequest: CalendarExportRequest?
    @State private var message: String?
    @State private var appleMarked = false
    @State private var messageTask: Task<Void, Never>?
    @State private var planOpen = false

    private var info: ScheduleEventInfo { app.scheduleInfo(for: app.withLive(event)) }
    private var source: ScheduleSource? { app.scheduleSource(for: event.key) }
    private var canAdd: Bool { SchedulePresentation.canAdd(info, now: Date()) }
    private var available: Bool { info.start != nil && !info.cancelled }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.name)
                    .font(BanbeTheme.display(28))
                    .foregroundStyle(onPhoto ? Color.white : app.palette.ink)
                    .shadow(color: onPhoto ? .black.opacity(0.35) : .clear, radius: 4, y: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if available {
                    planMenu
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(onPhoto ? Color.white.opacity(0.9) : app.palette.ink.opacity(0.8))
                    .accessibilityIdentifier("event.plan.message")
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .foregroundStyle(app.palette.ink)
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

    // MARK: the button

    private var added: Bool { source != nil || appleMarked }

    private var planMenu: some View {
        // Note 53 (owner report): a compact 40pt clay circle instead of the long "Add to calendar" pill. The icon says
        // it (calendar +); once added it fills clay with a check. It opens a popover (not a `Menu`): on iOS 26 a
        // Menu lifted this button's bounding box as a white platter that lingered after the menu closed.
        Button { planOpen = true } label: {
            Image(systemName: added ? "calendar.badge.checkmark" : "calendar.badge.plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(onPhoto ? Color.white : (added ? app.palette.paper : app.palette.clay))
                .frame(width: 40, height: 40)
                .background(onPhoto ? app.palette.clay.opacity(added ? 1 : 0.85) : (added ? app.palette.clay : app.palette.paper), in: Circle())
                .overlay(Circle().stroke(onPhoto ? Color.white.opacity(0.32) : app.palette.clay, lineWidth: 1))
                .frame(width: 44, height: 44)          // 44pt tap target around the 40pt circle
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .popover(isPresented: $planOpen, arrowEdge: .top) {
            PopoverMenuList(items: planItems) { planOpen = false }
                .environmentObject(app)
        }
        .accessibilityIdentifier("event.plan.button")
        .accessibilityLabel(planSpokenLabel)
        .accessibilityHint(app.T("Mở menu thêm vào lịch", "Opens the add-to-calendar menu"))
    }

    private var planSpokenLabel: String {
        var parts: [String] = []
        if let source { parts.append(app.T("Trong lịch banbe (\(source.label(app.T)))", "In banbe Schedule (\(source.label(app.T)))")) }
        if appleMarked { parts.append(app.T("Đã lưu vào Lịch Apple", "Saved to Apple Calendar")) }
        return parts.isEmpty ? app.T("Thêm lịch", "Add to calendar") : parts.joined(separator: ", ")
    }

    /// What makes sense in this state (same actions and identifiers as the old menu).
    private var planItems: [PopoverMenuItem] {
        var items: [PopoverMenuItem] = []
        if let source {
            items.append(PopoverMenuItem(id: "event.schedule.inMine",
                                         title: app.T("Đã có trong lịch của tôi · \(source.label(app.T))", "In My schedule · \(source.label(app.T))"),
                                         systemImage: "checkmark.circle.fill", disabled: true) {})
            if source == .added {
                items.append(PopoverMenuItem(id: "event.schedule.remove", title: app.T("Bỏ khỏi lịch banbe", "Remove from banbe Schedule"),
                                             systemImage: "calendar.badge.minus", destructive: true) {
                    app.removeFromBanbeSchedule(event.key)
                    message = nil
                })
            }
        } else if canAdd {
            items.append(PopoverMenuItem(id: "event.schedule.add", title: app.T("Thêm vào lịch banbe", "Add to banbe Schedule"),
                                         systemImage: "calendar.badge.plus") {
                switch app.addToBanbeSchedule(event) {
                case .added: show(app.T("Đã thêm vào lịch banbe. Đây chưa phải đặt chỗ.", "Added to your banbe Schedule. This isn't a reservation."))
                case .ineligible: show(app.T("Sự kiện này không thể thêm vào lịch.", "This event can't be added to your schedule."))
                case .alreadyThere, .needsSignIn: message = nil
                }
            })
        }
        items.append(PopoverMenuItem(id: "event.appleCalendar",
                                     title: appleMarked ? app.T("Thêm lại vào Lịch Apple", "Add to Apple Calendar again")
                                                        : app.T("Thêm vào Lịch Apple", "Add to Apple Calendar"),
                                     systemImage: "calendar") { open() })
        if appleMarked {
            items.append(PopoverMenuItem(id: "event.appleCalendar.clear", title: app.T("Bỏ dấu Lịch Apple", "Clear Apple Calendar mark"),
                                         systemImage: "xmark.circle", destructive: true) {
                if let uid = app.userID { AppleCalendarMarkStore().remove(event.key, uid: uid) }
                refreshMark()
            })
        }
        return items
    }

    // MARK: helpers

    private func refreshMark() {
        appleMarked = app.userID.map { AppleCalendarMarkStore().contains(event.key, uid: $0) } ?? false
    }

    /// Short status line under the title; fades after a few seconds.
    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            message = nil
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

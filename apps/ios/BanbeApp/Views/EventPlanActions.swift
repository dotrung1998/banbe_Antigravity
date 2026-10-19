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
    @State private var exportRequest: CalendarExportRequest?
    @State private var message: String?
    @State private var appleMarked = false
    @State private var messageTask: Task<Void, Never>?

    private var info: ScheduleEventInfo { app.scheduleInfo(for: app.withLive(event)) }
    private var source: ScheduleSource? { app.scheduleSource(for: event.key) }
    private var canAdd: Bool { SchedulePresentation.canAdd(info, now: Date()) }
    private var available: Bool { info.start != nil && !info.cancelled }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(event.name)
                    .font(BanbeTheme.display(28))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if available {
                    planMenu
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.8))
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

    private var statusLabel: String { added ? app.T("Đã thêm", "Added") : app.T("Thêm lịch", "Add to calendar") }

    private var planMenu: some View {
        // Compact (2026-10-18): one 36pt glass pill — calendar icon(s) + status — so the title row is only as
        // tall as the title itself (the old icon-over-caption column left a big gap above the location line).
        Menu { menuItems } label: {
            HStack(spacing: 6) {
                Image(systemName: source != nil ? "calendar.badge.checkmark" : "calendar.badge.plus")
                if appleMarked {
                    Rectangle().fill(app.palette.clay.opacity(0.35)).frame(width: 1, height: 16)
                    Image(systemName: "calendar")
                }
                Text(statusLabel)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .font(.system(size: 15, weight: .semibold))
            // Outlined clay pill (note 52 mockup): a secondary action beside the title, never a second CTA.
            .foregroundStyle(app.palette.clay)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(Capsule().stroke(app.palette.clay, lineWidth: 1))
            .fixedSize()
            .frame(minHeight: 44)          // keeps a 44pt tap target without adding visual height
            .contentShape(Rectangle())
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

    @ViewBuilder
    private var menuItems: some View {
        if let source {
            Button {} label: {
                Label(app.T("Đã có trong lịch của tôi · \(source.label(app.T))", "In My schedule · \(source.label(app.T))"),
                      systemImage: "checkmark.circle.fill")
            }
            .disabled(true)
            .accessibilityIdentifier("event.schedule.inMine")
            if source == .added {
                Button(role: .destructive) {
                    app.removeFromBanbeSchedule(event.key)
                    message = nil
                } label: {
                    Label(app.T("Bỏ khỏi lịch banbe", "Remove from banbe Schedule"), systemImage: "calendar.badge.minus")
                }
                .accessibilityIdentifier("event.schedule.remove")
            }
        } else if canAdd {
            Button {
                switch app.addToBanbeSchedule(event) {
                case .added: show(app.T("Đã thêm vào lịch banbe. Đây chưa phải đặt chỗ.", "Added to your banbe Schedule. This isn't a reservation."))
                case .ineligible: show(app.T("Sự kiện này không thể thêm vào lịch.", "This event can't be added to your schedule."))
                case .alreadyThere, .needsSignIn: message = nil
                }
            } label: {
                Label(app.T("Thêm vào lịch banbe", "Add to banbe Schedule"), systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("event.schedule.add")
        }
        Button { open() } label: {
            Label(appleMarked ? app.T("Thêm lại vào Lịch Apple", "Add to Apple Calendar again")
                              : app.T("Thêm vào Lịch Apple", "Add to Apple Calendar"),
                  systemImage: "calendar")
        }
        .accessibilityIdentifier("event.appleCalendar")
        if appleMarked {
            Button(role: .destructive) {
                if let uid = app.userID { AppleCalendarMarkStore().remove(event.key, uid: uid) }
                refreshMark()
            } label: {
                Label(app.T("Bỏ dấu Lịch Apple", "Clear Apple Calendar mark"), systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("event.appleCalendar.clear")
        }
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

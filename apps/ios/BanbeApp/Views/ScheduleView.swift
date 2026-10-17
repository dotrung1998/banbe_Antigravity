import SwiftUI

/// The Schedule dock tab (note 44): "My schedule" (default — booked, awaiting,
/// on-hold, hosting and manually added banbe events) and "Discover" (upcoming
/// public events by day). Purely banbe data: it never reads Apple/Google
/// calendars and never claims to know when the person is free.
struct ScheduleView: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        // ONE derivation per body pass (memoized in AppState); everything below reads it.
        ScheduleScreen(snap: app.scheduleSnapshot)
    }
}

private struct ScheduleScreen: View {
    @EnvironmentObject private var app: AppState
    let snap: ScheduleSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var loading = false
    @State private var monthPickerOpen: Bool = {
        #if DEBUG
        return UITestFixture.opensMonth
        #else
        return false
        #endif
    }()
    @State private var exportRequest: CalendarExportRequest?
    @State private var exportMessage: String?
    @State private var trackedConflicts: Set<String> = []
    @State private var modeBarFrame: CGRect = .zero

    private var calendar: Calendar { Calendar.current }
    private var agendaZone: TimeZone { calendar.timeZone }
    private var vi: Bool { !app.isEN }
    private var selected: Date { app.scheduleSelectedDate }

    private var mine: SchedulePresentation.MyScheduleResult { snap.mine }
    private var discover: [ScheduleEventInfo] { snap.discover }
    private var week: [Date] { SchedulePresentation.week(containing: selected, calendar: calendar) }

    private var largeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // Fixed above the scroll (like Home/Account) so the week strip never moves
                // under the finger and its swipe zone stays put. At accessibility text
                // sizes it scrolls with the content instead, so it can grow.
                if !largeText {
                    headerBlock
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                        .background(app.palette.paper)
                }
                ScreenScaffold(tracksBottomBarScroll: true, refreshIndicatorTopPadding: 16, onRefresh: { await reload(force: true) }) {
                    VStack(alignment: .leading, spacing: 14) {
                        if largeText { headerBlock.padding(.top, 12) }
                        Text(SchedulePresentation.dayTitle(selected, calendar: calendar, vi: vi))
                            .font(.system(.headline, design: .rounded))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("schedule.dayTitle")
                        content
                            .id("\(app.scheduleMode.rawValue).\(calendar.startOfDay(for: selected).timeIntervalSince1970)")
                            .transition(.opacity)
                        if let exportMessage {
                            Text(exportMessage).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.75))
                                .accessibilityIdentifier("schedule.exportMessage")
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: app.scheduleMode)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: calendar.startOfDay(for: selected))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        // Swipe left/right anywhere switches My schedule <-> Discover, exactly like Account's tabs:
        // same gesture thresholds, no wrap-around, and it never hops to another dock section.
        .contentShape(Rectangle())
        .simultaneousGesture(modeSwipe)
        .rootSwipeExclusion("schedule.tabs")
        // Deferred: this screen is mounted as a neighbor the moment a dock-tab swipe starts, and
        // a load republishes app-wide state — loading mid-drag is what made the swipe stutter.
        // A cancelled swipe removes the view, which cancels this task before it loads anything.
        .task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await reload(force: false)
        }
        .sheet(isPresented: $monthPickerOpen) {
            ScheduleMonthSheet(snap: snap, onClose: { monthPickerOpen = false })
                .environmentObject(app)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportRequest) { req in
            SystemEventEditor(draft: req.draft) { result in
                exportRequest = nil
                Analytics.track(.systemCalendarEditorResult(result: result.rawValue))
                exportMessage = calendarResultText(result)
            }
            .ignoresSafeArea()
        }
    }

    /// Logo + title + Today + month button, then the mode picker and week strip (the swipe zone).
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(alignment: .leading, spacing: 12) {
                modePicker
                // Seven columns can't grow without splitting numbers; the full-size
                // day title right below restates the selection.
                weekStrip.dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
        }
    }

    private func reload(force: Bool) async {
        loading = true
        await app.loadScheduleData(force: force)
        loading = false
    }

    // MARK: header

    /// Same logo + title as Account's header (112pt wordmark, display 27); Today and the month button sit on the row below.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleRow
            if largeText {
                VStack(alignment: .leading, spacing: 8) { todayButton; monthButton }
            } else {
                HStack(alignment: .center, spacing: 8) { monthButton; Spacer(minLength: 8); todayButton.fixedSize() }
            }
        }
    }

    /// banbe wordmark + "Schedule", identical to Account/Messages (width, font, spacing).
    private var titleRow: some View {
        HStack(alignment: .center) {
            BanbeLogo(kind: .wordmark, width: BanbeLogo.headerWordmarkWidth)
            Text(app.T("Lịch", "Schedule"))
                .font(BanbeTheme.display(27))
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("schedule.title")
            Spacer(minLength: 0)
        }
    }

    private var monthButton: some View {
        Button { monthPickerOpen = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                Text(SchedulePresentation.monthTitle(selected, calendar: calendar, vi: vi))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(app.palette.ink.opacity(0.8))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(app.T("Mở lịch cả tháng", "Opens the whole month"))
        .accessibilityIdentifier("schedule.month")
    }

    private var todayButton: some View {
        Button {
            select(Date())
        } label: {
            Text(app.T("Hôm nay", "Today"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(minHeight: 44)
                .nativeGlassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(calendar.isDateInToday(selected))
        .accessibilityIdentifier("schedule.today")
    }

    private var modePicker: some View {
        GlassSegmentedControl(
            segments: [GlassSegment(id: ScheduleMode.mine.rawValue, label: app.T("Lịch của tôi", "My schedule"), identifier: "schedule.mode.mine"),
                       GlassSegment(id: ScheduleMode.discover.rawValue, label: app.T("Khám phá", "Discover"), identifier: "schedule.mode.discover")],
            selection: app.scheduleMode.rawValue, height: 46, showsIcons: false, frame: $modeBarFrame,
            onSelect: { id in
                guard let m = ScheduleMode(rawValue: id) else { return }
                app.scheduleMode = m
                Haptics.selection()
                Analytics.track(.scheduleModeSelected(mode: m.rawValue))
            })
        .accessibilityIdentifier("schedule.mode")
    }

    // MARK: week strip

    private var weekStrip: some View {
        let busy: Set<Date> = app.scheduleMode == .mine
            ? SchedulePresentation.busyDays(week, items: mine.items, calendar: calendar)
            : Set(week.filter { !SchedulePresentation.events(discover, on: $0, calendar: calendar).isEmpty })
        return HStack(spacing: 0) {
            stepButton(-7, symbol: "chevron.left", label: app.T("Tuần trước", "Previous week"), id: "schedule.prevWeek")
            ForEach(week, id: \.self) { day in dayPill(day, busy: busy.contains(day)) }
            stepButton(7, symbol: "chevron.right", label: app.T("Tuần sau", "Next week"), id: "schedule.nextWeek")
        }
    }

    private func stepButton(_ days: Int, symbol: String, label: String, id: String) -> some View {
        Button {
            if let d = calendar.date(byAdding: .day, value: days, to: selected) { select(d) }
        } label: {
            Image(systemName: symbol).font(.footnote.weight(.semibold))
                .frame(width: 44, height: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func dayPill(_ day: Date, busy: Bool) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let f = DateFormatter()
        f.locale = Locale(identifier: vi ? "vi_VN" : "en_US")
        f.timeZone = agendaZone
        f.dateFormat = "EEEEE"
        let weekday = f.string(from: day)
        let number = calendar.component(.day, from: day)
        return Button { select(day) } label: {
            VStack(spacing: 4) {
                Text(weekday).font(.caption.weight(.bold))
                Text("\(number)").font(.system(.callout, design: .rounded).weight(isSelected || isToday ? .bold : .regular))
                Circle().fill(busy ? (isSelected ? app.palette.paper : app.palette.ink) : .clear)
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle(isSelected ? app.palette.paper : app.palette.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(isSelected ? app.palette.ink : .clear, in: Capsule())
            .overlay(Capsule().stroke(isToday && !isSelected ? app.palette.ink : .clear, lineWidth: 1.2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SchedulePresentation.dayTitle(day, calendar: calendar, vi: vi))
        .accessibilityValue([isToday ? app.T("Hôm nay", "Today") : nil,
                             busy ? app.T("Có sự kiện", "Has events") : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("schedule.day.\(calendar.component(.weekday, from: day))")
    }

    private var modeSwipe: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .named("rootGesture"))
            .onEnded { v in
                guard !modeBarFrame.contains(v.startLocation) else { return }   // the bubble's own drag
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) >= 60, abs(dx) > abs(dy) * 1.8 else { return }
                let target: ScheduleMode = dx < 0 ? .discover : .mine
                guard target != app.scheduleMode else { return }
                Haptics.selection()
                app.scheduleMode = target
                Analytics.track(.scheduleModeSelected(mode: target.rawValue))
            }
    }

    private func select(_ d: Date) {
        guard !calendar.isDate(d, inSameDayAs: selected) else { return }
        Haptics.selection()
        app.scheduleSelectedDate = d
        Analytics.track(.scheduleDaySelected(bucket: SchedulePresentation.dayBucket(d, today: Date(), calendar: calendar)))
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch app.scheduleMode {
        case .mine: mineContent
        case .discover: discoverContent
        }
    }

    @ViewBuilder
    private var mineContent: some View {
        let items = SchedulePresentation.items(mine.items, on: selected, calendar: calendar)
        if app.paymentBookingsLoadFailed && items.isEmpty {
            errorCard(app.T("Chưa tải được đặt chỗ của bạn. Lịch có thể chưa đầy đủ.", "Couldn't load your bookings, so this schedule may be incomplete."))
        } else if loading && mine.items.isEmpty {
            loadingRows
        } else if items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Chưa có kế hoạch nào trong ngày này.", "Nothing planned for this day."))
                    .font(.subheadline)
                    .accessibilityIdentifier("schedule.empty.mine")
                Button {
                    app.scheduleMode = .discover
                    Analytics.track(.scheduleModeSelected(mode: "discover"))
                } label: {
                    Label(app.T("Khám phá sự kiện ngày này", "Discover events on this day"), systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("schedule.empty.toDiscover")
            }
        } else {
            VStack(spacing: 10) {
                ForEach(items) { item in mineCard(item) }
            }
        }
        if mine.undatedCount > 0 {
            Label(app.T("\(mine.undatedCount) kế hoạch chưa có ngày giờ nên chưa hiện trên lịch.",
                        "\(mine.undatedCount) plan\(mine.undatedCount == 1 ? " has" : "s have") no date yet, so not shown on the calendar."),
                  systemImage: "calendar.badge.exclamationmark")
                .font(.footnote).foregroundStyle(app.palette.ink.opacity(0.7))
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        let events = SchedulePresentation.events(discover, on: selected, calendar: calendar)
        if app.discoveryEventsLoadFailed && discover.isEmpty {
            errorCard(app.T("Chưa tải được sự kiện. Kéo xuống để thử lại.", "Couldn't load events. Pull down to try again."))
        } else if (loading || app.discoveryEventsLoading) && discover.isEmpty {
            loadingRows
        } else if events.isEmpty {
            Text(discover.isEmpty
                 ? app.T("Hiện chưa có sự kiện công khai sắp tới nào để đặt chỗ.", "There are no upcoming public events open for booking right now.")
                 : app.T("Không có sự kiện công khai nào ngày này. Ngày có chấm là ngày có sự kiện.", "No public events on this day. Days with a dot have events."))
                .font(.subheadline)
                .accessibilityIdentifier("schedule.empty.discover")
        } else {
            VStack(spacing: 10) {
                ForEach(events, id: \.key) { e in discoverCard(e) }
            }
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(app.palette.field).frame(height: 84)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Đang tải lịch", "Loading schedule"))
        .accessibilityIdentifier("schedule.loading")
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "wifi.exclamationmark").font(.subheadline)
                .accessibilityIdentifier("schedule.error")
            Button(app.T("Thử lại", "Try again")) { Task { await reload(force: true) } }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .accessibilityIdentifier("schedule.retry")
        }
    }

    // MARK: cards

    private func timeColumn(_ e: ScheduleEventInfo) -> some View {
        Text(e.start.map { SchedulePresentation.time($0, timeZone: agendaZone, vi: vi) } ?? "—")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
    }

    private func cardChrome<Content: View>(_ e: ScheduleEventInfo, @ViewBuilder _ inner: () -> Content) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) { timeColumn(e); inner() }
            } else {
                HStack(alignment: .top, spacing: 12) { timeColumn(e).frame(width: 64, alignment: .leading); inner() }
            }
        }
    }

    private func mineCard(_ item: ScheduleItem) -> some View {
        let e = item.event
        return cardChrome(e) {
            VStack(alignment: .leading, spacing: 6) {
                SwipeSafeButton { app.goEvent(e.key) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        Label(item.source.label(app.T), systemImage: item.source.symbol)
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if e.ended { Text(app.T("Đã kết thúc", "Ended")).font(.caption).opacity(0.7) }
                        if !e.location.isEmpty { Text(e.location).font(.caption).opacity(0.7).lineLimit(2) }
                        if let note = SchedulePresentation.venueTimeNote(e, agendaZone: agendaZone, vi: vi) {
                            Text(note).font(.caption).opacity(0.7)
                        }
                        if e.end == nil, !e.ended {
                            Text(app.T("Chưa có giờ kết thúc", "No end time listed")).font(.caption).opacity(0.75)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    // ONE element for VoiceOver: title, source, time and location read together.
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityHint(app.T("Mở sự kiện", "Opens the event"))
                .accessibilityIdentifier("schedule.item.\(e.key)")
                cardActions(e, removable: item.source == .added)
            }
            .padding(14)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(app.palette.ink.opacity(item.source == .added ? 0.35 : 0.9))
                    .frame(width: 3).padding(.vertical, 12)
            }
        }
    }

    private func discoverCard(_ e: ScheduleEventInfo) -> some View {
        let proximity = SchedulePresentation.proximity(of: e, to: mine.items)
        return cardChrome(e) {
            VStack(alignment: .leading, spacing: 6) {
                SwipeSafeButton { app.goEvent(e.key) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(app.T("Gợi ý khám phá", "Discover"), systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).opacity(0.75)
                        Text(e.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        if !e.location.isEmpty { Text(e.location).font(.caption).opacity(0.7).lineLimit(2) }
                        if let note = SchedulePresentation.venueTimeNote(e, agendaZone: agendaZone, vi: vi) {
                            Text(note).font(.caption).opacity(0.7)
                        }
                        if let text = SchedulePresentation.proximityText(proximity, T: app.T) {
                            Label(text, systemImage: "exclamationmark.circle")
                                .font(.caption.weight(.semibold))
                                .accessibilityIdentifier("schedule.conflict.\(e.key)")
                                .onAppear { trackConflict(e.key, proximity) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityHint(app.T("Mở sự kiện", "Opens the event"))
                .accessibilityIdentifier("schedule.discover.\(e.key)")
                // One line each when they fit, stacked when they don't (narrow
                // phones, large text) — never a three-line pill.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { discoverActions(e, oneLine: true) }
                    VStack(alignment: .leading, spacing: 8) { discoverActions(e, oneLine: false) }
                }
            }
            .padding(14)
            // Dashed outline: a suggestion, never mistakable for a confirmed plan.
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(app.palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        }
    }

    @ViewBuilder
    private func discoverActions(_ e: ScheduleEventInfo, oneLine: Bool) -> some View {
                    SwipeSafeButton {
                        if let event = app.resolvedEvent(for: e.key) { app.addToBanbeSchedule(event) }
                    } label: {
                        Label(app.T("Thêm vào lịch banbe", "Add to banbe Schedule"), systemImage: "plus")
                            .font(.footnote.weight(.semibold))
                            .lineLimit(oneLine ? 1 : nil)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(app.palette.paper)
                            .background(app.palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(app.T("Lưu vào lịch trong app. Không phải đặt chỗ.", "Saves to your in-app schedule. Not a reservation."))
                    .accessibilityIdentifier("schedule.add.\(e.key)")
                    appleCalendarButton(e, oneLine: oneLine)
    }

    private func cardActions(_ e: ScheduleEventInfo, removable: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { mineActions(e, removable: removable, oneLine: true) }
            VStack(alignment: .leading, spacing: 4) { mineActions(e, removable: removable, oneLine: false) }
        }
    }

    @ViewBuilder
    private func mineActions(_ e: ScheduleEventInfo, removable: Bool, oneLine: Bool) -> some View {
            appleCalendarButton(e, oneLine: oneLine)
            if removable {
                SwipeSafeButton {
                    app.removeFromBanbeSchedule(e.key)
                } label: {
                    Label(app.T("Bỏ khỏi lịch", "Remove"), systemImage: "minus.circle")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(app.T("Chỉ bỏ khỏi lịch banbe trên máy này", "Removes it from your banbe Schedule on this device only"))
                .accessibilityIdentifier("schedule.remove.\(e.key)")
            }
    }

    private func appleCalendarButton(_ e: ScheduleEventInfo, oneLine: Bool) -> some View {
        SwipeSafeButton {
            openAppleCalendar(e)
        } label: {
            Label(app.T("Thêm vào Lịch Apple", "Add to Apple Calendar"), systemImage: "calendar.badge.plus")
                .font(.footnote.weight(.semibold))
                .lineLimit(oneLine ? 1 : nil)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(Capsule().stroke(app.palette.rule))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("schedule.appleCalendar.\(e.key)")
    }

    private func openAppleCalendar(_ e: ScheduleEventInfo) {
        Analytics.track(.systemCalendarEditorOpened)
        exportMessage = nil
        guard let draft = CalendarExport.draft(title: e.title, start: e.start, end: e.end, location: e.location,
                                               eventKey: e.key, origin: AppConfig.publicWebOrigin, T: app.T) else {
            Analytics.track(.systemCalendarEditorResult(result: CalendarExport.Result.unavailable.rawValue))
            exportMessage = calendarResultText(.unavailable)
            return
        }
        exportRequest = CalendarExportRequest(draft: draft)
    }

    private func calendarResultText(_ r: CalendarExport.Result) -> String {
        switch r {
        case .saved: return app.T("Đã thêm vào Lịch Apple.", "Added to Apple Calendar.")
        case .cancelled, .deleted: return app.T("Chưa thêm vào Lịch Apple.", "Not added to Apple Calendar.")
        case .unavailable: return app.T("Sự kiện này chưa có giờ bắt đầu nên chưa thêm vào lịch được.", "This event has no start time yet, so it can't be added to a calendar.")
        }
    }

    private func trackConflict(_ key: String, _ p: ScheduleProximity) {
        guard !trackedConflicts.contains(key) else { return }
        trackedConflicts.insert(key)
        Analytics.track(.scheduleConflictShown(countBucket: AnalyticsEvent.bucket(p.count)))
    }
}

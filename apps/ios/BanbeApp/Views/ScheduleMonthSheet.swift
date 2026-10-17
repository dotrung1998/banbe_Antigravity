import SwiftUI

/// The whole-month view (note 45): a month grid with an event indicator on each
/// day plus the month's agenda underneath. Tapping a day, a week row or an
/// agenda item selects it and returns to the week view on that week.
/// Shows the same mode as the Schedule tab (My schedule / Discover). Hides the
/// always-on-top dock while it is up (it would sit over the sheet).
struct ScheduleMonthSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snap: ScheduleSnapshot
    let onClose: () -> Void
    @State private var month: Date = Date()
    @State private var seeded = false

    private var calendar: Calendar { Calendar.current }
    private var vi: Bool { !app.isEN }

    private var events: [ScheduleEventInfo] {
        app.scheduleMode == .mine ? snap.mine.items.map(\.event) : snap.discover
    }

    var body: some View {
        let grid = SchedulePresentation.monthGrid(containing: month, calendar: calendar)
        let counts = SchedulePresentation.dayCounts(events, grid: grid, calendar: calendar)
        let agenda = SchedulePresentation.monthAgenda(events, month: month, calendar: calendar)
        CardSheet(title: app.T("Xem theo tháng", "Month view"), closeID: "schedule.month.close", onClose: onClose) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    monthNav
                    modePicker
                    weekdayHeader(grid)
                    VStack(spacing: 4) {
                        ForEach(Array(grid.enumerated()), id: \.offset) { _, row in weekRow(row, counts: counts) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("schedule.month.grid")
                    agendaSection(agenda)
                }
                .padding(.bottom, 24)
            }
        }
        .hidesDock("schedule.month")
        .onAppear {
            guard !seeded else { return }
            seeded = true
            month = SchedulePresentation.monthStart(app.scheduleSelectedDate, calendar: calendar)
        }
        .accessibilityIdentifier("schedule.month.sheet")
    }

    // MARK: header

    private var monthNav: some View {
        HStack(spacing: 4) {
            navButton(-1, symbol: "chevron.left", label: app.T("Tháng trước", "Previous month"), id: "schedule.month.prev")
            Text(SchedulePresentation.monthTitle(month, calendar: calendar, vi: vi))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("schedule.month.title")
            navButton(1, symbol: "chevron.right", label: app.T("Tháng sau", "Next month"), id: "schedule.month.next")
        }
    }

    private func navButton(_ delta: Int, symbol: String, label: String, id: String) -> some View {
        Button {
            Haptics.selection()
            month = SchedulePresentation.addMonths(delta, to: month, calendar: calendar)
        } label: {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var modePicker: some View {
        GlassSegmentedControl(
            segments: [GlassSegment(id: ScheduleMode.mine.rawValue, label: app.T("Lịch của tôi", "My schedule"), identifier: "schedule.month.mode.mine"),
                       GlassSegment(id: ScheduleMode.discover.rawValue, label: app.T("Khám phá", "Discover"), identifier: "schedule.month.mode.discover")],
            selection: app.scheduleMode.rawValue, height: 46, showsIcons: false,
            onSelect: { id in
                guard let m = ScheduleMode(rawValue: id) else { return }
                app.scheduleMode = m
                Haptics.selection()
                Analytics.track(.scheduleModeSelected(mode: m.rawValue))
            })
        .accessibilityIdentifier("schedule.month.mode")
    }

    // MARK: grid

    private func weekdayHeader(_ grid: [[SchedulePresentation.MonthGridDay]]) -> some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: vi ? "vi_VN" : "en_US")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEEEE"
        return HStack(spacing: 0) {
            ForEach(grid.first ?? [], id: \.date) { d in
                Text(f.string(from: d.date))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(app.palette.ink.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }

    private func weekRow(_ row: [SchedulePresentation.MonthGridDay], counts: [Date: Int]) -> some View {
        let isSelectedWeek = row.contains { calendar.isDate($0.date, inSameDayAs: app.scheduleSelectedDate) }
        return HStack(spacing: 0) {
            ForEach(row) { day in dayCell(day, count: counts[day.date] ?? 0) }
        }
        .padding(.vertical, 2)
        // The selected week is the row the week view will show.
        .background {
            if isSelectedWeek { RoundedRectangle(cornerRadius: 16, style: .continuous).fill(app.palette.field) }
        }
    }

    private func dayCell(_ day: SchedulePresentation.MonthGridDay, count: Int) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: app.scheduleSelectedDate)
        let isToday = calendar.isDateInToday(day.date)
        let number = calendar.component(.day, from: day.date)
        return Button { pick(day.date) } label: {
            VStack(spacing: 3) {
                Text("\(number)")
                    .font(.system(.callout, design: .rounded).weight(isSelected || isToday ? .bold : .regular))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isSelected ? app.palette.paper : app.palette.ink)
                    .background(isSelected ? app.palette.ink : .clear, in: Circle())
                    .overlay(Circle().stroke(isToday && !isSelected ? app.palette.ink : .clear, lineWidth: 1.2))
                // Up to three dots; the exact number is in the spoken value.
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().fill(app.palette.ink).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .opacity(day.inMonth ? 1 : 0.4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SchedulePresentation.dayTitle(day.date, calendar: calendar, vi: vi))
        .accessibilityValue(count == 0 ? app.T("Không có sự kiện", "No events")
                                       : app.T("\(count) sự kiện", "\(count) event\(count == 1 ? "" : "s")"))
        .accessibilityHint(app.T("Mở tuần này", "Shows this week"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("schedule.month.day.\(number)\(day.inMonth ? "" : ".out")")
    }

    private func pick(_ date: Date) {
        Haptics.selection()
        app.scheduleSelectedDate = date
        Analytics.track(.scheduleDaySelected(bucket: SchedulePresentation.dayBucket(date, today: Date(), calendar: calendar)))
        onClose()
    }

    // MARK: month agenda

    @ViewBuilder
    private func agendaSection(_ agenda: [(day: Date, events: [ScheduleEventInfo])]) -> some View {
        Text(app.scheduleMode == .mine ? app.T("Kế hoạch trong tháng", "Your plans this month")
                                       : app.T("Sự kiện trong tháng", "Events this month"))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 6)
        if agenda.isEmpty {
            Text(app.scheduleMode == .mine ? app.T("Chưa có kế hoạch nào trong tháng này.", "Nothing planned this month.")
                                           : app.T("Chưa có sự kiện công khai nào trong tháng này.", "No public events this month."))
                .font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.75))
                .accessibilityIdentifier("schedule.month.empty")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(agenda, id: \.day) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(SchedulePresentation.dayTitle(entry.day, calendar: calendar, vi: vi))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.8))
                        ForEach(entry.events, id: \.key) { e in agendaRow(e, day: entry.day) }
                    }
                }
            }
        }
    }

    private func agendaRow(_ e: ScheduleEventInfo, day: Date) -> some View {
        Button { pick(day) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(e.start.map { SchedulePresentation.time($0, timeZone: calendar.timeZone, vi: vi) } ?? "—")
                    .font(.system(.footnote, design: .rounded).weight(.semibold)).monospacedDigit()
                    .frame(minWidth: 62, alignment: .leading)
                Text(e.title).font(.subheadline).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(app.T("Mở ngày này", "Shows this day"))
        .accessibilityIdentifier("schedule.month.event.\(e.key)")
    }
}

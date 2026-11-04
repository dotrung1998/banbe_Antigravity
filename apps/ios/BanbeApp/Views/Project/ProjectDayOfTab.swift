import SwiftUI

/// Day-of (v6 prototype): the event week with tasks due per day, the event-day mode card (live sync only on the event day,
/// plus the team's call), then the run-of-show as a List or a time-grid Calendar. Times are in the event's zone.
/// The Host and Managers add, edit and delete items; everyone ticks.
struct ProjectDayOfTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    let snap: ProjectSnapshot
    let live: Bool
    @State private var selectedDay: String?

    private var tz: TimeZone { snap.event?.timeZone ?? .current }
    private var editor: Bool { app.projectCan("ros.edit") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekStrip
            if let day = selectedDay { dueList(day) }
            infoCard.padding(.top, 14)
            HStack(spacing: 10) {
                GlassSegmentedControl(segments: [
                    GlassSegment(id: "list", label: app.T("Danh sách", "List"), icon: "list.bullet", identifier: "project.dayof.view.list"),
                    GlassSegment(id: "cal", label: app.T("Lịch", "Calendar"), icon: "calendar.day.timeline.left", identifier: "project.dayof.view.cal"),
                ], selection: app.projectDayView, height: 44, showsIcons: false) { app.projectDayView = $0 }
                if editor {
                    Button { openSheet(.rosItem(nil)) } label: {
                        Label(app.T("Thêm mốc", "Add item"), systemImage: "plus").font(.subheadline.weight(.bold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(app.palette.clay).background(app.palette.clayBg, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .fixedSize()
                    .accessibilityIdentifier("project.dayof.add")
                }
            }
            .padding(.top, 16).padding(.bottom, 10)
            if app.projectDayView == "cal" {
                ProjectRosGrid(snap: snap)
            } else {
                list
            }
            Text(editor ? app.T("Bạn thêm, sửa hoặc xoá được các mốc. Mọi người khác chỉ tick xong.",
                                "You can add, edit or delete items. Everyone else just ticks them off.")
                        : app.T("Chỉ Chủ sự kiện và Quản lý sửa được mốc. Bạn tick khi xong.",
                                "Only the Host and Managers can edit items. Tick yours when it's done."))
                .font(.footnote).foregroundStyle(app.palette.ink3).padding(.top, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.dayofTab")
    }

    // MARK: week

    /// The seven days ending on the event day, in the event's zone.
    private var days: [String] {
        guard let eventDay = snap.event?.eventDate, let end = ProjectPresentation.localDay(eventDay, tz: tz) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: end) }.map { ProjectPresentation.ymd($0, tz: tz) }
    }

    private var weekStrip: some View {
        let open = ProjectPresentation.open(snap.tasks ?? [])
        let toGo = ProjectPresentation.daysToGo(snap.event, now: app.projectNow) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.T("Tuần diễn ra", "Event week")).font(.body.weight(.bold))
                Spacer()
                Text(toGo > 0 ? app.T("Còn \(toGo) ngày", toGo == 1 ? "In 1 day" : "In \(toGo) days")
                              : toGo == 0 ? app.T("Hôm nay", "Today") : app.T("Đã qua", "Over"))
                    .font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(app.palette.clay).background(app.palette.clayBg, in: Capsule())
            }
            .padding(.horizontal, 4)
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { d in
                    dayPill(d, due: open.filter { $0.dueDate == d }.count)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.dayof.week")
    }

    private func dayPill(_ d: String, due: Int) -> some View {
        let isEvent = d == snap.event?.eventDate
        let on = selectedDay == d
        let date = ProjectPresentation.localDay(d, tz: tz) ?? Date()
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: app.T("vi_VN", "en_US"))
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        let weekday = f.string(from: date)
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        let spoken = f.string(from: date)
        let dayNum = d.split(separator: "-").last.map { String(Int($0) ?? 0) } ?? ""
        return Button {
            Haptics.selection()
            selectedDay = on ? nil : d
        } label: {
            VStack(spacing: 3) {
                Text(weekday).font(.caption2.weight(.bold)).opacity(0.8)
                Text(dayNum).font(.system(size: 17, weight: .bold).monospacedDigit())
                Text(due > 0 ? app.T("\(due) việc", "\(due) due") : isEvent ? "★" : " ").font(.caption2.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(on ? app.palette.paper : isEvent ? app.palette.clay : app.palette.ink)
            .background(on ? app.palette.ink : isEvent ? app.palette.clayBg : app.palette.field,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(spoken + (isEvent ? app.T(", ngày diễn ra", ", event day") : "")
                            + (due > 0 ? app.T(", \(due) việc đến hạn", due == 1 ? ", 1 task due" : ", \(due) tasks due") : ""))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("project.dayof.day.\(d)")
    }

    @ViewBuilder
    private func dueList(_ day: String) -> some View {
        let tasks = (snap.tasks ?? []).filter { $0.dueDate == day }.sorted { $0.title < $1.title }
        HStack(alignment: .firstTextBaseline) {
            Text(app.T("Việc đến hạn ", "Tasks due ") + (app.projectDueText(day) ?? day)).font(BanbeTheme.display(18)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(app.T("Bỏ chọn", "Clear")) { selectedDay = nil }
                .font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.clay).frame(minHeight: 44)
                .accessibilityIdentifier("project.dayof.clearDay")
        }
        .padding(.top, 16).padding(.bottom, 6)
        if tasks.isEmpty {
            Text(app.T("Không có việc nào đến hạn ngày này.", "Nothing is due that day.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                .padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .projectCard()
                .accessibilityIdentifier("project.dayof.dueEmpty")
        } else {
            ProjectRowsCard(items: tasks) { t in ProjectTaskRow(task: t) { openSheet(.task(t.id)) } }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project.dayof.due")
        }
    }

    // MARK: info

    private var infoCard: some View {
        let channels = snap.project?.channels ?? []
        let call = channels.first { $0.primary } ?? channels.first
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: live ? "dot.radiowaves.left.and.right" : "clock").foregroundStyle(app.palette.honey).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live ? app.T("Đang đồng bộ trực tiếp", "Live now") : app.T("Chế độ ngày diễn ra", "Event-day mode"))
                        .font(.body.weight(.bold))
                    Text(live ? app.T("Cập nhật mỗi \(ProjectLimits.shared.pollSeconds) giây khi bạn mở thẻ này.",
                                      "Updates every \(ProjectLimits.shared.pollSeconds) seconds while this tab is open.")
                              : app.T("Chỉ ngày \(eventDayText) mới đồng bộ trực tiếp để cả đội tick cùng lúc. Các ngày khác đồng bộ khi mở hoặc kéo xuống.",
                                      "Only on \(eventDayText) does it sync live, so the team can tick together. Other days it syncs on open or when you pull down."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let call, let url = URL(string: call.url) {
                Link(destination: url) {
                    Label(app.T("Vào cuộc gọi · ", "Join call · ") + (call.label.isEmpty ? (ProjectChannels.names[call.platform] ?? call.platform) : call.label),
                          systemImage: "phone.arrow.up.right")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(app.palette.paper.opacity(0.6), in: Capsule())
                }
                .accessibilityIdentifier("project.dayof.call")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(live ? "project.dayof.live" : "project.dayof.info")
    }

    private var eventDayText: String {
        guard let d = snap.event?.eventDate, let date = ProjectPresentation.localDay(d, tz: tz) else { return "" }
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: app.T("vi_VN", "en_US"))
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    // MARK: list

    @ViewBuilder
    private var list: some View {
        let items = snap.ros ?? []
        let placed = ProjectRosGrid.placed(items, now: app.projectNow)
        if items.isEmpty {
            Text(app.T("Chưa có mốc nào.", "No items yet.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                .padding(.vertical, 18).frame(maxWidth: .infinity).projectCard()
                .accessibilityIdentifier("project.dayof.empty")
        } else {
            ProjectRowsCard(items: items) { r in row(r, placed: placed[r.id]) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project.dayof.list")
        }
    }

    private func row(_ r: ProjectRosItem, placed p: RosLayout.Placed?) -> some View {
        let start = ProjectDates.parse(r.startsAt) ?? Date()
        let end = ProjectDates.parse(r.endsAt) ?? Date()
        let done = r.doneAt != nil
        return HStack(spacing: 10) {
            Text(app.projectClock(start)).font(.body.weight(.bold).monospacedDigit()).frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.body.weight(.semibold))
                    .strikethrough(done, color: app.palette.ink3)
                    .foregroundStyle(done ? app.palette.ink2 : app.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("\(app.projectClock(start))–\(app.projectClock(end)) · \(app.projectPersonName(r.ownerId))")
                        .font(.footnote).foregroundStyle(app.palette.ink2)
                    if let p, p.overrun { ProjectRosBadge(text: "+\(p.overrunMin)′", tone: .alert) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if editor {
                Button { openSheet(.rosItem(r.id)) } label: {
                    Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44)
                        .background(app.palette.blockInset, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Sửa \(r.title)", "Edit \(r.title)"))
                .accessibilityIdentifier("project.ros.edit.\(r.id)")
            }
            ProjectRosTick(item: r)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.ros.row.\(r.id)")
    }
}

/// The 44 pt tick of a run-of-show item (list row and grid block).
struct ProjectRosTick: View {
    @EnvironmentObject private var app: AppState
    let item: ProjectRosItem

    var body: some View {
        let done = item.doneAt != nil
        Button {
            guard app.projectCan("ros.tick") else { return }
            Haptics.light()
            Task { await app.tickProjectRosItem(item.id, done: !done) }
        } label: {
            ProjectStatusCircle(status: done ? "done" : "todo").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!app.projectCan("ros.tick") || app.projectBusy)
        .accessibilityLabel(done ? app.T("Bỏ đánh dấu xong: \(item.title)", "Mark not done: \(item.title)")
                                 : app.T("Đánh dấu xong: \(item.title)", "Mark done: \(item.title)"))
        .accessibilityValue(done ? app.T("Xong", "Done") : app.T("Chưa xong", "Not done"))
        .accessibilityIdentifier("project.ros.tick.\(item.id)")
    }
}

struct ProjectRosBadge: View {
    @EnvironmentObject private var app: AppState
    enum Tone { case alert, honey }
    let text: String
    let tone: Tone
    /// A "Versus the plan" chip may wrap; a badge inside a row or block stays on one line.
    var wraps = false

    var body: some View {
        Text(text).font(.caption.weight(.bold)).lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: wraps)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tone == .alert ? BanbeTheme.alert : app.palette.honey)
            .background(tone == .alert ? BanbeTheme.alert.opacity(0.14) : app.palette.honeyBg, in: Capsule())
    }
}

/// Scroll the hub to an anchor (the time grid's "Jump to now"). Set by ProjectHubView around its ScrollView.
struct ProjectScrollTo {
    let scroll: (String) -> Void
    func callAsFunction(_ id: String) { scroll(id) }
}

private struct ProjectScrollToKey: EnvironmentKey { static let defaultValue = ProjectScrollTo { _ in } }

extension EnvironmentValues {
    var projectScrollTo: ProjectScrollTo {
        get { self[ProjectScrollToKey.self] }
        set { self[ProjectScrollToKey.self] = newValue }
    }
}

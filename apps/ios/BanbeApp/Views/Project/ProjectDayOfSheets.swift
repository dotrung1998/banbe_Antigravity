import SwiftUI

/// Add or edit a run-of-show item (Host and Managers): name, start and end in the EVENT's zone (the end at least
/// 10 minutes after the start; items may cross midnight), and who runs it. Delete needs a reason and goes to the trash.
struct ProjectRosSheet: View {
    @EnvironmentObject private var app: AppState
    let itemID: String?
    let close: () -> Void

    @State private var title = ""
    @State private var owner: String?
    @State private var start = Date()
    @State private var end = Date()
    @State private var deleting = false
    @State private var reason = ""
    @State private var loaded = false

    private var item: ProjectRosItem? { itemID.flatMap { id in app.projectSnapshot?.ros?.first { $0.id == id } } }
    private var tz: TimeZone { app.projectSnapshot?.event?.timeZone ?? .current }
    private var limits: ProjectLimits { .shared }

    /// The event's start, from which the allowed window is counted.
    private var eventStart: Date? {
        if let s = ProjectDates.parse(app.projectSnapshot?.event?.startsAt) { return s }
        guard let d = app.projectSnapshot?.event?.eventDate else { return nil }
        return ProjectPresentation.localDay(d, tz: tz)
    }
    private var window: ClosedRange<Date> {
        let base = eventStart ?? Date()
        return base.addingTimeInterval(-Double(limits.rosWindowBeforeStartHours) * 3600)...base.addingTimeInterval(Double(limits.rosWindowAfterStartHours) * 3600)
    }
    private var titleOK: Bool { (limits.rosTitleMin...limits.rosTitleMax).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private var timeOK: Bool { end.timeIntervalSince(start) >= Double(limits.rosMinMinutes) * 60 }

    var body: some View {
        CardSheet(title: itemID == nil ? app.T("Thêm mốc", "Add item") : app.T("Sửa mốc", "Edit item"), closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if deleting { deleteForm } else { form }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.rosSheet")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let item, let s = ProjectDates.parse(item.startsAt), let e = ProjectDates.parse(item.endsAt) {
            title = item.title; owner = item.ownerId; start = s; end = e
        } else {
            // A new item follows the last one (or starts with the event), 30 minutes long.
            let last = (app.projectSnapshot?.ros ?? []).compactMap { ProjectDates.parse($0.endsAt) }.max()
            start = last ?? eventStart ?? app.projectNow
            end = start.addingTimeInterval(30 * 60)
        }
    }

    @ViewBuilder
    private var form: some View {
        ProjectTextField(label: app.T("Việc", "What"), text: $title, limit: limits.rosTitleMax,
                         placeholder: app.T("Ví dụ: Mở cửa đón khách", "e.g. Doors open"), id: "project.ros.title")
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(app.T("Bắt đầu", "Start"), selection: $start, in: window, displayedComponents: [.date, .hourAndMinute])
                .font(.body.weight(.semibold))
                .onChange(of: start) { old, new in
                    // Moving the start keeps the length, so the end never ends up before it.
                    end = end.addingTimeInterval(new.timeIntervalSince(old))
                }
                .accessibilityIdentifier("project.ros.start")
            DatePicker(app.T("Kết thúc", "End"), selection: $end, in: window, displayedComponents: [.date, .hourAndMinute])
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("project.ros.end")
            Text(app.T("Giờ theo múi giờ sự kiện (\(tz.identifier)). Kết thúc sau bắt đầu ít nhất \(limits.rosMinMinutes) phút.",
                       "Times are in the event's zone (\(tz.identifier)). The end is at least \(limits.rosMinMinutes) minutes after the start."))
                .font(.footnote).foregroundStyle(timeOK ? app.palette.ink3 : BanbeTheme.alert)
                .accessibilityIdentifier("project.ros.timeHint")
        }
        .environment(\.timeZone, tz)
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Người phụ trách", "Who runs it"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(app.projectPeopleIDs, id: \.self) { uid in
                    ProjectChip(title: app.projectPersonName(uid), selected: owner?.lowercased() == uid.lowercased(), id: "project.ros.owner") {
                        owner = owner?.lowercased() == uid.lowercased() ? nil : uid
                    }
                }
            }
        }
        InkButton(title: app.T("Lưu", "Save"), enabled: titleOK && timeOK && !app.projectBusy, cornerRadius: 999,
                  disabledReason: !titleOK ? app.T("Tên mốc dài 2 đến 40 ký tự.", "An item name is 2 to 40 characters.")
                                           : !timeOK ? app.T("Kết thúc phải sau bắt đầu ít nhất 10 phút.", "The end must be at least 10 minutes after the start.") : nil) {
            Task {
                if await app.saveProjectRosItem(itemID: itemID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), ownerID: owner,
                                                startsAt: start, endsAt: end) {
                    close()
                }
            }
        }
        .accessibilityIdentifier("project.ros.save")
        if itemID != nil {
            Button(role: .destructive) { deleting = true } label: {
                Label(app.T("Xoá mốc", "Delete item"), systemImage: "trash").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("project.ros.delete")
        }
    }

    @ViewBuilder
    private var deleteForm: some View {
        Text(item?.title ?? "").font(BanbeTheme.display(18))
        ProjectReasonField(reason: $reason, picks: [app.T("Đổi lịch", "Schedule changed"), app.T("Không cần nữa", "No longer needed"),
                                                    app.T("Viết sai", "Written wrong")])
        Button(role: .destructive) {
            Task { if let itemID, await app.deleteProjectRosItem(itemID, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
        } label: {
            Text(app.T("Xoá mốc", "Delete item")).font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
        .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
        .accessibilityIdentifier("project.ros.confirmDelete")
        Text(app.T("Mốc bị xoá vào thùng rác 7 ngày.", "Deleted items stay in the trash for 7 days.")).font(.footnote).foregroundStyle(app.palette.ink3)
        Button(app.T("Không xoá", "Keep it")) { deleting = false }.frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Trash (v6): deleted tasks, posts and run-of-show items for 7 days (30 at most) and archived lanes, each with who
/// and why. The Host and Managers restore; only the Host deletes for good.
struct ProjectTrashSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void
    @State private var items: [ProjectTrashItem] = []
    @State private var loaded = false

    var body: some View {
        CardSheet(title: app.T("Thùng rác", "Trash"), closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(app.T("Mục bị xoá được giữ \(ProjectLimits.shared.trashDays) ngày (tối đa \(ProjectLimits.shared.trashMax) mục) rồi tự dọn. Mọi thao tác đều ghi người làm và lý do.",
                               "Deleted items are kept \(ProjectLimits.shared.trashDays) days (\(ProjectLimits.shared.trashMax) at most), then cleared. Every action records who and why."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                    if !loaded {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else if items.isEmpty {
                        Text(app.T("Thùng rác trống.", "The trash is empty.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                            .accessibilityIdentifier("project.trash.empty")
                    } else {
                        ProjectRowsCard(items: items) { row($0) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task {
            items = await app.loadProjectTrash()
            loaded = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.trash")
    }

    private func row(_ t: ProjectTrashItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text([app.projectTrashKindName(t.kind), app.projectPersonName(t.by), t.reason.map { "“\($0)”" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(app.T("Khôi phục", "Restore")) {
                Task { if await app.restoreProjectItem(t) { items.removeAll { $0.id == t.id } } }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).frame(minHeight: 44).background(app.palette.blockInset, in: Capsule())
            .accessibilityIdentifier("project.trash.restore.\(t.itemId)")
            if app.projectCan("trash.purge") {
                Button {
                    Task { if await app.purgeProjectItem(t) { items.removeAll { $0.id == t.id } } }
                } label: {
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Xoá vĩnh viễn \(t.title)", "Delete \(t.title) for good"))
                .accessibilityIdentifier("project.trash.purge.\(t.itemId)")
            }
        }
        .padding(.vertical, 8)
    }
}

import SwiftUI

/// Every sheet the Event Project Hub opens (note 76). One `.sheet(item:)` in ProjectHubView presents them; tabs open
/// one through the `openProjectSheet` environment value.
enum ProjectSheet: Identifiable, Equatable {
    case task(String)
    case newTask(laneID: String?)
    case channels
    case newLane
    case manageLane(String)
    case declineChange(String)
    case leave
    // Phase 4
    case post(String)
    case compose
    case member(String)
    case invite

    var id: String {
        switch self {
        case .task(let id): return "task.\(id)"
        case .newTask: return "newTask"
        case .channels: return "channels"
        case .newLane: return "newLane"
        case .manageLane(let id): return "lane.\(id)"
        case .declineChange(let id): return "decline.\(id)"
        case .leave: return "leave"
        case .post(let id): return "post.\(id)"
        case .compose: return "compose"
        case .member(let id): return "member.\(id)"
        case .invite: return "invite"
        }
    }
}

struct OpenProjectSheet {
    let open: (ProjectSheet) -> Void
    func callAsFunction(_ sheet: ProjectSheet) { open(sheet) }
}

private struct OpenProjectSheetKey: EnvironmentKey {
    static let defaultValue = OpenProjectSheet { _ in }
}

extension EnvironmentValues {
    var openProjectSheet: OpenProjectSheet {
        get { self[OpenProjectSheetKey.self] }
        set { self[OpenProjectSheetKey.self] = newValue }
    }
}

struct ProjectSheetHost: View {
    let sheet: ProjectSheet
    let close: () -> Void

    var body: some View {
        switch sheet {
        case .task(let id): ProjectTaskSheet(taskID: id, presetLane: nil, close: close)
        case .newTask(let lane): ProjectTaskSheet(taskID: nil, presetLane: lane, close: close)
        case .channels: ProjectChannelsSheet(close: close)
        case .newLane: ProjectNewLaneSheet(close: close)
        case .manageLane(let id): ProjectManageLaneSheet(laneID: id, close: close)
        case .declineChange(let id): ProjectDeclineSheet(requestID: id, close: close)
        case .leave: ProjectLeaveSheet(close: close)
        case .post(let id): ProjectPostSheet(postID: id, close: close)
        case .compose: ProjectComposeSheet(close: close)
        case .member(let id): ProjectMemberSheet(memberID: id, close: close)
        case .invite: ProjectInviteSheet(close: close)
        }
    }
}

// MARK: - shared form pieces

/// A labelled text field with a live counter and the app's field chrome.
struct ProjectTextField: View {
    @EnvironmentObject private var app: AppState
    let label: String
    @Binding var text: String
    let limit: Int
    var placeholder = ""
    var axis: Axis = .horizontal
    var id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.6)
                Spacer()
                Text("\(text.count)/\(limit)").font(.caption.monospacedDigit())
            }
            .foregroundStyle(app.palette.ink3)
            .accessibilityHidden(true)
            TextField(placeholder, text: $text, axis: axis)
                .font(.body)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: text) { _, v in if v.count > limit { text = String(v.prefix(limit)) } }
                .accessibilityLabel(label)
                .accessibilityValue(text)
                .accessibilityIdentifier(id)
        }
    }
}

struct ProjectFieldLabel: View {
    @EnvironmentObject private var app: AppState
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(app.palette.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A required reason (3–140 characters) with quick picks, used before anything goes to the trash or is declined.
struct ProjectReasonField: View {
    @EnvironmentObject private var app: AppState
    @Binding var reason: String
    let picks: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(picks, id: \.self) { p in ProjectChip(title: p, selected: reason == p, id: "project.reason.pick") { reason = p } }
            }
            ProjectTextField(label: app.T("Lý do", "Reason"), text: $reason, limit: 140, placeholder: app.T("Một dòng ngắn…", "One short line…"),
                             id: "project.reason")
        }
    }

    static func valid(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
}

// MARK: - task

struct ProjectTaskSheet: View {
    @EnvironmentObject private var app: AppState
    let taskID: String?
    let presetLane: String?
    let close: () -> Void

    @State private var title = ""
    @State private var laneID = ""
    @State private var assignee: String?
    @State private var hasDue = false
    @State private var due = Date()
    @State private var status = "todo"
    @State private var deleting = false
    @State private var reason = ""
    @State private var loaded = false

    private var task: ProjectTask? { taskID.flatMap { id in app.projectSnapshot?.tasks?.first { $0.id == id } } }
    private var tz: TimeZone { app.projectSnapshot?.event?.timeZone ?? .current }
    private var me: ProjectMe? { app.projectSnapshot?.me }
    /// A lane lead only ever works inside their own lane.
    private var allowedLanes: [ProjectLane] {
        let lanes = (app.projectSnapshot?.lanes ?? []).sorted { $0.position < $1.position }
        if me?.role == "lane_lead", app.projectSnapshot?.isHost != true { return lanes.filter { $0.id == me?.laneId } }
        return lanes
    }
    private var editable: Bool {
        guard let task else { return app.projectCan("task.manage", .init(laneId: laneID.isEmpty ? presetLane : laneID)) }
        return app.projectCan("task.manage", .init(laneId: task.laneId))
    }
    private var dueString: String? { hasDue ? ProjectPresentation.ymd(due, tz: tz) : nil }
    private var titleOK: Bool { (3...60).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private var dirty: Bool {
        guard let task else { return true }
        return title.trimmingCharacters(in: .whitespacesAndNewlines) != task.title || laneID != task.laneId
            || assignee?.lowercased() != task.assigneeId?.lowercased() || dueString != task.dueDate || status != task.status
    }

    var body: some View {
        CardSheet(title: taskID == nil ? app.T("Việc mới", "New task") : (editable ? app.T("Sửa việc", "Edit task") : app.T("Việc", "Task")),
                  closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if deleting { deleteForm } else if editable { form } else if let task { detail(task) }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let task {
            title = task.title; laneID = task.laneId; assignee = task.assigneeId; status = task.status
            if let d = task.dueDate, let date = ProjectPresentation.localDay(d, tz: tz) { hasDue = true; due = date }
        } else {
            laneID = presetLane ?? allowedLanes.first?.id ?? ""
            assignee = app.userID?.uuidString.lowercased()
        }
    }

    @ViewBuilder
    private var form: some View {
        ProjectTextField(label: app.T("Tên việc", "Title"), text: $title, limit: 60, placeholder: app.T("Làm gì?", "What needs doing?"),
                         id: "project.task.title")
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Hạng mục", "Lane"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(allowedLanes) { l in ProjectChip(title: l.name, selected: laneID == l.id, id: "project.task.lane.\(l.id)") { laneID = l.id } }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Người phụ trách", "Assignee"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(app.projectPeopleIDs, id: \.self) { uid in
                    ProjectChip(title: app.projectPersonName(uid), selected: assignee?.lowercased() == uid.lowercased(), id: "project.task.assignee") {
                        assignee = uid
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Toggle(app.T("Có hạn", "Due date"), isOn: $hasDue).font(.body.weight(.semibold)).accessibilityIdentifier("project.task.hasDue")
            if hasDue {
                DatePicker(app.T("Hạn", "Due"), selection: $due, displayedComponents: .date)
                    .environment(\.timeZone, tz)
                    .accessibilityIdentifier("project.task.due")
            }
        }
        if taskID != nil {
            VStack(alignment: .leading, spacing: 8) {
                ProjectFieldLabel(text: app.T("Trạng thái", "Status"))
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(["todo", "doing", "blocked", "done"], id: \.self) { s in
                        ProjectChip(title: app.projectStatusName(s), selected: status == s, id: "project.task.status.\(s)") { status = s }
                    }
                }
                if status == "blocked" {
                    Text(app.T("Việc bị chặn báo ngay cho Chủ sự kiện.", "A blocked task alerts the Host straight away."))
                        .font(.footnote).foregroundStyle(BanbeTheme.alert)
                }
            }
        }
        InkButton(title: taskID == nil ? app.T("Tạo việc", "Create task") : app.T("Lưu thay đổi", "Save changes"),
                  enabled: titleOK && !laneID.isEmpty && dirty && !app.projectBusy, cornerRadius: 999,
                  disabledReason: titleOK ? nil : app.T("Tên việc dài 3 đến 60 ký tự.", "A title is 3 to 60 characters.")) {
            Task {
                if await app.saveProjectTask(taskID: taskID, laneID: laneID, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                             assigneeID: assignee, dueDate: dueString, status: taskID == nil ? nil : status) {
                    close()
                }
            }
        }
        .accessibilityIdentifier("project.task.save")
        if taskID != nil {
            Button(role: .destructive) { deleting = true } label: {
                Label(app.T("Xoá việc", "Delete task"), systemImage: "trash").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(BanbeTheme.alert)
                    .background(BanbeTheme.alert.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("project.task.delete")
            Text(app.T("Việc bị xoá vào thùng rác 7 ngày. Chủ sự kiện và Quản lý khôi phục được.",
                       "Deleted tasks stay in the trash for 7 days. The Host and Managers can restore them."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
    }

    @ViewBuilder
    private var deleteForm: some View {
        Text(task?.title ?? "").font(BanbeTheme.display(18))
        ProjectReasonField(reason: $reason, picks: [app.T("Viết sai", "Written wrong"), app.T("Không cần nữa", "No longer needed"),
                                                    app.T("Trùng việc", "Duplicate")])
        Button(role: .destructive) {
            Task { if let taskID, await app.deleteProjectTask(taskID, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
        } label: {
            Text(app.T("Xoá việc", "Delete task")).font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
        .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
        .accessibilityIdentifier("project.task.confirmDelete")
        Button(app.T("Không xoá", "Keep it")) { deleting = false }.frame(maxWidth: .infinity, minHeight: 44)
    }

    @ViewBuilder
    private func detail(_ task: ProjectTask) -> some View {
        let lane = app.projectSnapshot?.lanes?.first { $0.id == task.laneId }?.name ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(BanbeTheme.display(20)).fixedSize(horizontal: false, vertical: true)
            Text([lane, app.projectPersonName(task.assigneeId), app.projectDueText(task.dueDate)].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(app.palette.ink2)
        }
        let canStatus = app.projectCan("task.status", .init(laneId: task.laneId, assigneeId: task.assigneeId))
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Trạng thái", "Status"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(["todo", "doing", "blocked", "done"], id: \.self) { s in
                    ProjectChip(title: app.projectStatusName(s), selected: task.status == s, enabled: canStatus && !app.projectBusy,
                                id: "project.task.status.\(s)") {
                        Task { await app.setProjectTaskStatus(task.id, s) }
                    }
                }
            }
        }
        Text(canStatus
             ? app.T("Bạn đổi được trạng thái. Sửa tên, hạn hoặc xoá việc do Chủ sự kiện, Quản lý hoặc Trưởng hạng mục làm.",
                     "You can change the status. Editing or deleting is for the Host, a Manager or the lane lead.")
             : app.T("Bạn không phụ trách việc này nên chỉ xem được.", "You're not on this task, so it's view only."))
            .font(.footnote).foregroundStyle(app.palette.ink3)
    }
}

extension AppState {
    /// Hosts, then active members: everyone a task can be given to.
    var projectPeopleIDs: [String] {
        guard let snap = projectSnapshot else { return [] }
        return (snap.hosts ?? []).map(\.userId) + (snap.members ?? []).map(\.userId)
    }
}

// MARK: - lanes

/// The Host adds a lane straight away; a Manager proposes one with a reason for the Host.
struct ProjectNewLaneSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void
    @State private var name = ""
    @State private var why = ""

    private var direct: Bool { app.projectCan("lane.manage") }
    private var count: Int { app.projectSnapshot?.lanes?.count ?? 0 }
    private var ok: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...24).contains(n.count) && count < 10 && (direct || ProjectReasonField.valid(why))
    }

    var body: some View {
        CardSheet(title: direct ? app.T("Thêm hạng mục", "Add a lane") : app.T("Đề xuất hạng mục", "Propose a lane"),
                  closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !direct {
                        Text(app.T("Chủ sự kiện sẽ duyệt và trả lời kèm lý do. Hạng mục chỉ hiện cho cả đội sau khi được duyệt.",
                                   "The Host reviews it and replies with a reason. The lane appears for the team once approved."))
                            .font(.subheadline).padding(14)
                            .background(app.palette.clayBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(app.palette.clay)
                    }
                    ProjectTextField(label: app.T("Tên hạng mục", "Lane name"), text: $name, limit: 24,
                                     placeholder: app.T("Ví dụ: Truyền thông", "e.g. Marketing"), id: "project.lane.name")
                    if !direct {
                        ProjectTextField(label: app.T("Vì sao cần?", "Why is it needed?"), text: $why, limit: 140,
                                         placeholder: app.T("Một hai câu cho Chủ sự kiện", "A line or two for the Host"), axis: .vertical,
                                         id: "project.lane.why")
                    }
                    Text(app.T("\(count)/10 hạng mục.", "\(count)/10 lanes.")).font(.footnote).foregroundStyle(app.palette.ink3)
                    InkButton(title: direct ? app.T("Thêm", "Add") : app.T("Gửi đề xuất", "Send proposal"), enabled: ok && !app.projectBusy,
                              cornerRadius: 999) {
                        Task {
                            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let done = direct ? await app.addProjectLane(n)
                                              : await app.proposeProjectChange(kind: "lane_add", name: n, why: why.trimmingCharacters(in: .whitespacesAndNewlines))
                            if done { close() }
                        }
                    }
                    .accessibilityIdentifier("project.lane.save")
                }
            }
        }
    }
}

/// Host: rename a lane, or archive it once no open task is left in it (it can be restored from the trash).
struct ProjectManageLaneSheet: View {
    @EnvironmentObject private var app: AppState
    let laneID: String
    let close: () -> Void
    @State private var name = ""
    @State private var reason = ""

    private var lane: ProjectLane? { app.projectSnapshot?.lanes?.first { $0.id == laneID } }
    private var openTasks: Int { (app.projectSnapshot?.tasks ?? []).filter { $0.laneId == laneID && $0.status != "done" }.count }

    var body: some View {
        CardSheet(title: app.T("Quản lý hạng mục", "Manage lane"), closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectTextField(label: app.T("Tên hạng mục", "Lane name"), text: $name, limit: 24, id: "project.lane.rename")
                    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    InkButton(title: app.T("Đổi tên", "Rename"), enabled: (1...24).contains(n.count) && n != lane?.name && !app.projectBusy,
                              cornerRadius: 999) {
                        Task { if await app.renameProjectLane(laneID, n) { close() } }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.T("Lưu trữ hạng mục", "Archive lane")).font(.body.weight(.bold))
                        Text(openTasks > 0
                             ? app.T("Còn \(openTasks) việc chưa xong. Hãy xong hoặc chuyển sang hạng mục khác trước.",
                                     "\(openTasks) open task(s) left. Finish them or move them to another lane first.")
                             : app.T("Lưu trữ sẽ ẩn hạng mục. Bạn khôi phục được từ thùng rác.", "Archiving hides the lane. You can restore it from the trash."))
                            .font(.subheadline).foregroundStyle(app.palette.ink2)
                        if openTasks == 0 {
                            ProjectReasonField(reason: $reason, picks: [app.T("Gộp vào hạng mục khác", "Merged into another lane"),
                                                                        app.T("Không cần nữa", "No longer needed")])
                            Button(role: .destructive) {
                                Task { if await app.archiveProjectLane(laneID, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
                            } label: {
                                Label(app.T("Lưu trữ", "Archive"), systemImage: "archivebox").font(.body.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
                            .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
                            .accessibilityIdentifier("project.lane.archive")
                        }
                    }
                    .projectCard()
                }
            }
        }
        .onAppear { if name.isEmpty { name = lane?.name ?? "" } }
    }
}

/// Host declines a Manager's proposal: the reason is required and shown to the proposer.
struct ProjectDeclineSheet: View {
    @EnvironmentObject private var app: AppState
    let requestID: String
    let close: () -> Void
    @State private var reason = ""

    var body: some View {
        CardSheet(title: app.T("Từ chối đề xuất", "Decline proposal"), closeID: "project.sheet.close", onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let r = app.projectSnapshot?.changeRequests?.first(where: { $0.id == requestID }) {
                        Text(app.projectChangeTitle(r)).font(BanbeTheme.display(18))
                    }
                    ProjectReasonField(reason: $reason, picks: [app.T("Đã nằm trong hạng mục khác", "Already covered by another lane"),
                                                                app.T("Chưa cần lúc này", "Not needed right now"),
                                                                app.T("Quá sát ngày diễn ra", "Too close to the event")])
                    Button(role: .destructive) {
                        Task {
                            if await app.reviewProjectChange(requestID, approve: false, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() }
                        }
                    } label: {
                        Text(app.T("Từ chối", "Decline")).font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
                    .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
                    .accessibilityIdentifier("project.decline.confirm")
                    Text(app.T("Người đề xuất sẽ thấy lý do.", "The proposer will see the reason.")).font(.footnote).foregroundStyle(app.palette.ink3)
                }
            }
        }
    }
}

struct ProjectLeaveSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void

    var body: some View {
        CardSheet(title: app.T("Rời dự án", "Leave project"), closeID: "project.sheet.close", onClose: close) {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.T("Việc đang giao cho bạn sẽ thành chưa giao. Bạn cần lời mời mới để vào lại.",
                           "Tasks given to you become unassigned. You'll need a new invite to come back."))
                    .font(.body)
                Button(role: .destructive) { Task { close(); await app.leaveProject() } } label: {
                    Text(app.T("Rời dự án", "Leave project")).font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("project.leave.confirm")
            }
        }
    }
}

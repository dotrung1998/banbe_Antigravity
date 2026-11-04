import Foundation

/// Event Project Hub (note 76): loading a project and its writes. Every write is one RPC (migration 210) followed by a
/// version-checked refresh; the server decides permissions, `ProjectPermissions` only decides what the UI offers.
/// In a DEBUG UI fixture nothing reaches Supabase: writes change the in-memory snapshot instead.
extension AppState {
    var projectHubEnabled: Bool { FeatureFlags.isOn(featureFlags, "event_project_hub") }

    /// "Now" for due days and countdowns (a UI fixture pins it, so screenshots and tests never go stale).
    var projectNow: Date {
        #if DEBUG
        if let now = UITestFixture.projectNow { return now }
        #endif
        return Date()
    }

    /// What the UI may offer for `action` (the server re-checks every call).
    func projectCan(_ action: String, _ target: ProjectPermissions.Target = .init()) -> Bool {
        guard let snap = projectSnapshot else { return false }
        let me = snap.me
        let uid = userID?.uuidString.lowercased()
        // The snapshot says whether I am the Host; the permission rules need an organizer to compare with.
        let organizer = ProjectPermissions.Organizer(ownerId: snap.isHost == true ? uid : nil, userId: nil)
        let member = me.map { ProjectPermissions.Member(role: $0.role, laneId: $0.laneId, capMoney: $0.capMoney, capCheckin: $0.capCheckin,
                                                       grantExpiresAt: ProjectDates.parse($0.grantExpiresAt)) }
        var t = target
        t.assigneeId = t.assigneeId?.lowercased(); t.authorId = t.authorId?.lowercased(); t.addresseeId = t.addresseeId?.lowercased()
        return ProjectPermissions.can(action, .init(
            userId: uid, member: member, organizer: organizer, flags: featureFlags, now: projectNow,
            readOnlyAt: ProjectDates.parse(snap.project?.readOnlyAt), refundApproval: snap.project?.refundApproval ?? "host", target: t))
    }

    // MARK: open / refresh

    func openProject(eventID: String, back: Screen, tab: String = "overview") async {
        projectBackScreen = back
        if projectEventID != eventID { projectSnapshot = nil; projectRosVersion = nil; projectDayView = "list"; projectMoney = nil; projectDoor = nil }
        projectEventID = eventID
        projectTab = tab
        projectError = ""
        projectNotice = ""
        screen = .eventProject
        await refreshProject(full: projectSnapshot == nil)
    }

    func backFromProject() { screen = projectBackScreen }

    /// `full: false` asks with the current version: one tiny answer when nothing moved.
    func refreshProject(full: Bool = false) async {
        #if DEBUG
        if UITestFixture.isActive { return }
        #endif
        guard !projectEventID.isEmpty else { return }
        struct Params: Encodable {
            let pEventId: String
            let pSinceVersion: Int?
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pSinceVersion = "p_since_version" }
        }
        let eventID = projectEventID
        if projectSnapshot == nil { projectLoading = true }
        do {
            let result: ProjectSnapshot = try await SupabaseService.client
                .rpc("get_event_project", params: Params(pEventId: eventID, pSinceVersion: full ? nil : projectSnapshot?.version))
                .execute().value
            guard eventID == projectEventID else { return }   // the user opened another project meanwhile
            projectLoading = false
            if !result.success {
                projectError = projectErrorText(result.error)
                return
            }
            if result.unchanged == true { return }
            var next = result
            mergeOlderPosts(into: &next)
            projectSnapshot = next
            projectRosVersion = nil
            projectError = ""
        } catch {
            print("refreshProject failed:", error)
            projectLoading = false
            if projectSnapshot == nil { projectError = projectErrorText(nil) }
        }
    }

    func loadMyProjects() async {
        #if DEBUG
        if UITestFixture.isActive { myProjectsLoaded = true; return }
        #endif
        guard projectHubEnabled, userID != nil else { myProjects = []; myProjectsLoaded = true; return }
        do {
            let result: MyProjectsResult = try await SupabaseService.client.rpc("get_my_event_projects").execute().value
            myProjects = result.projects ?? []
        } catch {
            print("loadMyProjects failed:", error)
        }
        myProjectsLoaded = true
    }

    func myProject(for eventID: String) -> MyProject? { myProjects.first { $0.eventId == eventID } }

    /// The Host's lanes a new project starts with, in the Host's language (the server only checks length and duplicates).
    var defaultProjectLanes: [String] {
        [T("Địa điểm", "Venue"), T("Thực đơn & đồ uống", "Menu & drinks"), T("Ngân sách", "Budget"),
         T("Khách & vé", "Guests & tickets"), T("Nhà cung cấp", "Vendors"), T("Ngày diễn ra", "Day-of")]
    }

    /// Opt-in: "Start a project" on the Hosting card. Opens the new project on success.
    func startProject(eventID: String, back: Screen) async {
        struct Params: Encodable {
            let pEventId: String
            let pLaneNames: [String]
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pLaneNames = "p_lane_names" }
        }
        let ok = await projectWrite("start_event_project", Params(pEventId: eventID, pLaneNames: defaultProjectLanes), refresh: false)
        if ok {
            await loadMyProjects()
            await openProject(eventID: eventID, back: back)
        }
    }

    // MARK: writes

    /// One write RPC. On success the project refreshes; on a refusal `projectNotice` says why in plain words.
    @discardableResult
    func projectWrite<P: Encodable>(_ function: String, _ params: P, refresh: Bool = true, post: Bool = false, ros: Bool = false) async -> Bool {
        projectBusy = true
        defer { projectBusy = false }
        projectNotice = ""
        do {
            let result: ProjectWriteResult = try await SupabaseService.client.rpc(function, params: params).execute().value
            guard result.success else {
                projectNotice = projectErrorText(result.error, post: post, ros: ros)
                return false
            }
            if refresh { await refreshProject() }
            return true
        } catch {
            print("\(function) failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }

    func setProjectTaskStatus(_ taskID: String, _ status: String) async {
        #if DEBUG
        if UITestFixture.isActive { fixtureEditTask(taskID) { $0.status = status }; return }
        #endif
        struct Params: Encodable {
            let pTaskId: String; let pStatus: String
            enum CodingKeys: String, CodingKey { case pTaskId = "p_task_id", pStatus = "p_status" }
        }
        await projectWrite("project_set_task_status", Params(pTaskId: taskID, pStatus: status))
    }

    /// Create (taskID nil) or edit a task.
    @discardableResult
    func saveProjectTask(taskID: String?, laneID: String, title: String, assigneeID: String?, dueDate: String?, status: String?) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            if let taskID {
                fixtureEditTask(taskID) { $0.title = title; $0.assigneeId = assigneeID; $0.dueDate = dueDate; if let status { $0.status = status } }
            } else {
                let t = ProjectTask(id: UUID().uuidString.lowercased(), laneId: laneID, title: title, assigneeId: assigneeID, dueDate: dueDate,
                                    status: status ?? "todo", createdAt: nil, updatedAt: nil)
                projectSnapshot?.tasks = (projectSnapshot?.tasks ?? []) + [t]
            }
            return true
        }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pTaskId: String?; let pLaneId: String; let pTitle: String
            let pAssigneeId: String?; let pDueDate: String?; let pStatus: String?
            enum CodingKeys: String, CodingKey {
                case pEventId = "p_event_id", pTaskId = "p_task_id", pLaneId = "p_lane_id", pTitle = "p_title"
                case pAssigneeId = "p_assignee_id", pDueDate = "p_due_date", pStatus = "p_status"
            }
            func encode(to encoder: Encoder) throws {
                // Always send every key (a nil must clear the assignee or due day, not be skipped).
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(pEventId, forKey: .pEventId); try c.encode(pTaskId, forKey: .pTaskId); try c.encode(pLaneId, forKey: .pLaneId)
                try c.encode(pTitle, forKey: .pTitle); try c.encode(pAssigneeId, forKey: .pAssigneeId)
                try c.encode(pDueDate, forKey: .pDueDate); try c.encode(pStatus, forKey: .pStatus)
            }
        }
        return await projectWrite("project_upsert_task", Params(pEventId: projectEventID, pTaskId: taskID, pLaneId: laneID, pTitle: title,
                                                                pAssigneeId: assigneeID, pDueDate: dueDate, pStatus: status))
    }

    @discardableResult
    func deleteProjectTask(_ taskID: String, reason: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive { projectSnapshot?.tasks?.removeAll { $0.id == taskID }; return true }
        #endif
        struct Params: Encodable {
            let pTaskId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pTaskId = "p_task_id", pReason = "p_reason" }
        }
        return await projectWrite("project_delete_task", Params(pTaskId: taskID, pReason: reason))
    }

    @discardableResult
    func saveProjectChannels(_ channels: [ProjectChannels.Channel]) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive { projectSnapshot?.project?.channels = channels; return true }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pChannels: [ProjectChannels.Channel]
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pChannels = "p_channels" }
        }
        return await projectWrite("project_set_channels", Params(pEventId: projectEventID, pChannels: channels))
    }

    @discardableResult
    func addProjectLane(_ name: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            let n = projectSnapshot?.lanes?.count ?? 0
            projectSnapshot?.lanes?.append(ProjectLane(id: UUID().uuidString.lowercased(), name: name, position: n))
            return true
        }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pName: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pName = "p_name" }
        }
        return await projectWrite("project_add_lane", Params(pEventId: projectEventID, pName: name))
    }

    @discardableResult
    func renameProjectLane(_ laneID: String, _ name: String) async -> Bool {
        struct Params: Encodable {
            let pLaneId: String; let pName: String
            enum CodingKeys: String, CodingKey { case pLaneId = "p_lane_id", pName = "p_name" }
        }
        return await projectWrite("project_rename_lane", Params(pLaneId: laneID, pName: name))
    }

    @discardableResult
    func archiveProjectLane(_ laneID: String, reason: String) async -> Bool {
        struct Params: Encodable {
            let pLaneId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pLaneId = "p_lane_id", pReason = "p_reason" }
        }
        return await projectWrite("project_archive_lane", Params(pLaneId: laneID, pReason: reason))
    }

    /// A Manager proposes a lane or channel change; the Host applies it by approving.
    @discardableResult
    func proposeProjectChange(kind: String, laneID: String? = nil, name: String? = nil, url: String? = nil,
                              channel: ProjectChannels.Channel? = nil, why: String) async -> Bool {
        struct Payload: Encodable {
            let name: String?; let url: String?; let channel: ProjectChannels.Channel?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(name, forKey: .name); try c.encodeIfPresent(url, forKey: .url); try c.encodeIfPresent(channel, forKey: .channel)
            }
            enum CodingKeys: String, CodingKey { case name, url, channel }
        }
        struct Params: Encodable {
            let pEventId: String; let pKind: String; let pLaneId: String?; let pPayload: Payload; let pWhy: String
            enum CodingKeys: String, CodingKey {
                case pEventId = "p_event_id", pKind = "p_kind", pLaneId = "p_lane_id", pPayload = "p_payload", pWhy = "p_why"
            }
        }
        return await projectWrite("project_propose_change", Params(pEventId: projectEventID, pKind: kind, pLaneId: laneID,
                                                                   pPayload: Payload(name: name, url: url, channel: channel), pWhy: why))
    }

    @discardableResult
    func reviewProjectChange(_ requestID: String, approve: Bool, reason: String?) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            if approve, let r = projectSnapshot?.changeRequests?.first(where: { $0.id == requestID }), r.kind == "lane_add", let name = r.payload.name {
                _ = await addProjectLane(name)
            }
            projectSnapshot?.changeRequests?.removeAll { $0.id == requestID }
            return true
        }
        #endif
        struct Params: Encodable {
            let pRequestId: String; let pApprove: Bool; let pReason: String?
            enum CodingKeys: String, CodingKey { case pRequestId = "p_request_id", pApprove = "p_approve", pReason = "p_reason" }
        }
        return await projectWrite("project_review_change", Params(pRequestId: requestID, pApprove: approve, pReason: reason))
    }

    func leaveProject() async {
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        if await projectWrite("project_leave", Params(pEventId: projectEventID), refresh: false) {
            projectSnapshot = nil
            await loadMyProjects()
            backFromProject()
        }
    }

    #if DEBUG
    private func fixtureEditTask(_ taskID: String, _ change: (inout ProjectTask) -> Void) {
        guard let i = projectSnapshot?.tasks?.firstIndex(where: { $0.id == taskID }) else { return }
        change(&projectSnapshot!.tasks![i])
    }
    #endif

    // MARK: words

    /// A refusal code from migration 210 in plain words.
    func projectErrorText(_ code: String?, post: Bool = false, ros: Bool = false) -> String {
        if post, code == "TITLE_INVALID" { return T("Tiêu đề dài 3 đến 80 ký tự.", "A title is 3 to 80 characters.") }
        if ros, code == "TITLE_INVALID" { return T("Tên mốc dài 2 đến 40 ký tự.", "An item name is 2 to 40 characters.") }
        switch code {
        case "FEATURE_OFF": return T("Dự án sự kiện đang tạm tắt.", "Event projects are switched off right now.")
        case "NOT_AUTHORIZED": return T("Bạn không có quyền làm việc này trong dự án.", "You can't do this in this project.")
        case "NOT_FOUND": return T("Không tìm thấy mục này. Có thể nó vừa bị xoá.", "This item wasn't found. It may have just been removed.")
        case "READ_ONLY": return T("Dự án đã chuyển sang chỉ xem (30 ngày sau sự kiện).", "This project is read-only now (30 days after the event).")
        case "ACCOUNT_GATE": return T("Hãy hoàn tất xác minh tài khoản trước.", "Finish verifying your account first.")
        case "ALREADY_STARTED": return T("Sự kiện này đã có dự án.", "This event already has a project.")
        case "EVENT_CLOSED": return T("Sự kiện đã huỷ hoặc bị gỡ.", "This event was cancelled or removed.")
        case "EVENT_NOT_SCHEDULED": return T("Hãy chọn ngày cho sự kiện trước.", "Pick a date for the event first.")
        case "LANES_FULL": return T("Đã đủ 10 hạng mục.", "This project already has 10 lanes.")
        case "LANE_NAME_TAKEN": return T("Đã có hạng mục tên này.", "A lane with this name already exists.")
        case "LANE_NAME_INVALID": return T("Tên hạng mục dài 1 đến 24 ký tự.", "A lane name is 1 to 24 characters.")
        case "LANE_HAS_OPEN_TASKS": return T("Hạng mục còn việc chưa xong. Hãy xong hoặc chuyển chúng trước.", "This lane still has open tasks. Finish or move them first.")
        case "LANE_REQUIRED": return T("Hãy chọn một hạng mục.", "Pick a lane.")
        case "REASON_REQUIRED": return T("Hãy ghi lý do (ít nhất 3 ký tự).", "Add a reason (at least 3 characters).")
        case "TITLE_INVALID": return T("Tên việc dài 3 đến 60 ký tự.", "A title is 3 to 60 characters.")
        case "ASSIGNEE_NOT_IN_PROJECT": return T("Người này không còn trong dự án.", "This person is no longer in the project.")
        case "CHANNELS_INVALID": return T("Có liên kết không hợp lệ. Chỉ dùng liên kết https.", "A link isn't valid. Use https links only.")
        case "NOT_PENDING": return T("Đề xuất này đã được xử lý.", "This proposal was already handled.")
        case "RESTORE_LANE_FIRST": return T("Hãy khôi phục hạng mục của mục này trước.", "Restore this item's lane first.")
        case "NOT_A_MEMBER": return T("Bạn không còn trong dự án này.", "You're no longer in this project.")
        case "AUTH_REQUIRED": return T("Hãy đăng nhập trước.", "Log in first.")
        case "ADDRESSEE_INVALID": return T("Hãy chọn một người trong dự án để hỏi.", "Pick someone in the project to ask.")
        case "OPTIONS_INVALID": return T("Đề xuất cần 2 đến 4 lựa chọn, mỗi lựa chọn tối đa 40 ký tự.", "A proposal needs 2 to 4 options of up to 40 characters.")
        case "BODY_TOO_LONG": return T("Chi tiết tối đa 280 ký tự.", "Details are up to 280 characters.")
        case "BODY_INVALID": return T("Phản hồi dài 1 đến 140 ký tự.", "A reply is 1 to 140 characters.")
        case "REPLIES_FULL": return T("Bài đã đủ 10 phản hồi. Hãy chốt hoặc đóng bài.", "This post has 10 replies. Settle or close it.")
        case "NOT_OPEN": return T("Bài này đã đóng.", "This post is closed.")
        case "ALREADY_ANSWERED": return T("Đã có người phản hồi nên không sửa được nữa.", "Someone has responded, so it can't be edited now.")
        case "INVITE_NOT_FOUND": return T("Không tìm thấy mã mời này. Hãy kiểm tra lại.", "This invite code wasn't found. Check it and try again.")
        case "INVITE_EXPIRED": return T("Lời mời đã hết hạn. Hãy xin một mã mới.", "This invite has expired. Ask for a new one.")
        case "INVITE_USED": return T("Lời mời đã được dùng hết.", "This invite has already been used.")
        case "INVITE_REVOKED": return T("Lời mời đã bị huỷ.", "This invite was cancelled.")
        case "IS_HOST": return T("Bạn là Chủ sự kiện này, không cần lời mời.", "You're the Host of this event, so you don't need an invite.")
        case "ALREADY_MEMBER": return T("Bạn đã ở trong dự án này.", "You're already in this project.")
        case "LANE_ARCHIVED": return T("Hạng mục của lời mời đã được lưu trữ. Hãy xin một mã mới.", "The invite's lane was archived. Ask for a new one.")
        case "RATE_LIMITED": return T("Nhập sai quá nhiều lần. Hãy thử lại sau một giờ.", "Too many wrong codes. Try again in an hour.")
        case "INVALID_VALUE": return T("Giá trị không hợp lệ.", "That value isn't valid.")
        case "TIME_INVALID": return T("Kết thúc phải sau bắt đầu ít nhất 10 phút.", "The end must be at least 10 minutes after the start.")
        case "TIME_OUTSIDE_EVENT": return T("Mốc phải nằm trong khoảng 12 giờ trước đến 24 giờ sau giờ bắt đầu sự kiện.",
                                            "Items must sit between 12 hours before and 24 hours after the event starts.")
        case "OWNER_NOT_IN_PROJECT": return T("Người phụ trách không còn trong dự án.", "That person is no longer in the project.")
        default: return T("Chưa lưu được. Hãy thử lại.", "Couldn't save. Try again.")
        }
    }

    func projectRoleName(_ role: String?) -> String {
        switch role {
        case "host": return T("Chủ sự kiện", "Host")
        case "manager": return T("Quản lý", "Manager")
        case "finance": return T("Tài chính & cổng", "Finance & door")
        case "lane_lead": return T("Trưởng hạng mục", "Lane lead")
        case "helper": return T("Hỗ trợ", "Helper")
        default: return ""
        }
    }

    /// A participant's display name ("You" for me; falls back to the handle).
    func projectPersonName(_ userID: String?) -> String {
        guard let userID, let snap = projectSnapshot else { return T("Chưa giao", "Unassigned") }
        if userID.lowercased() == self.userID?.uuidString.lowercased() { return T("Bạn", "You") }
        let people = (snap.hosts ?? []).map { ($0.userId, $0.displayName, $0.handle) } + (snap.members ?? []).map { ($0.userId, $0.displayName, $0.handle) }
        guard let p = people.first(where: { $0.0.lowercased() == userID.lowercased() }) else { return T("Người đã rời dự án", "Former member") }
        if let name = p.1, !name.isEmpty { return name }
        return p.2 ?? "—"
    }

    func projectDueText(_ day: String?) -> String? {
        guard let tz = projectSnapshot?.event?.timeZone, let label = ProjectPresentation.dueLabel(day, now: projectNow, tz: tz) else { return nil }
        switch label {
        case .today: return T("Hôm nay", "Today")
        case .tomorrow: return T("Ngày mai", "Tomorrow")
        case .late(let n): return T("Trễ \(n) ngày", n == 1 ? "1 day late" : "\(n) days late")
        case .date(let d):
            guard let date = ProjectPresentation.localDay(d, tz: tz) else { return d }
            let f = DateFormatter()
            f.timeZone = tz
            f.locale = Locale(identifier: T("vi_VN", "en_US"))
            f.setLocalizedDateFormatFromTemplate("EEE d/M")
            return f.string(from: date)
        }
    }
}

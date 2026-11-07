import Foundation

/// Event Project Hub phase 4 (note 76): Team. Invites (the Host presets any role, a Manager presets Lane lead or
/// Helper; 48 hours, single use until the QR phase), member roles and access (Host only), and the "Join a team" screen
/// for a link (`banbe://join/<v>`, `https://www.banbe.app/join/<v>`) or a typed `BB-XXXX` code. The link only carries
/// an opaque value: the role and lane come from the server, never from the link.
extension AppState {
    /// A join link or code opened while signed out waits here until the person has signed in.
    static let pendingProjectInviteKey = "banbe.pendingProjectInvite"

    // MARK: invites

    /// Mint an invite for `role` (and the lane, for a lane lead). More than one use needs switch `project_qr_invite`
    /// (the server refuses it otherwise).
    func createProjectInvite(role: String, laneID: String?, maxUses: Int = 1) async -> ProjectInvite? {
        if projectOffline {
            ProjectDemo.inviteCount += 1
            let n = ProjectDemo.inviteCount
            let inv = ProjectInvite(inviteId: UUID().uuidString.lowercased(), token: "Fx7kQ2mN9pR4sT6vW8yZ1" + (n == 1 ? "a" : "b"),
                                    shortCode: n == 1 ? "BB-7K2Q" : "BB-M4\(["A", "C", "D", "E", "F", "G", "H", "J"][n % 8])P",
                                    role: role, laneId: role == "lane_lead" ? laneID : nil,
                                    expiresAt: ISO8601DateFormatter().string(from: projectNow.addingTimeInterval(48 * 3600)),
                                    maxUses: maxUses, uses: 0, createdBy: userID?.uuidString.lowercased())
            projectInvites.insert(inv, at: 0)
            return inv
        }
        struct Params: Encodable {
            let pEventId: String; let pRole: String; let pLaneId: String?; let pMaxUses: Int
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pRole = "p_role", pLaneId = "p_lane_id", pMaxUses = "p_max_uses" }
        }
        projectBusy = true
        defer { projectBusy = false }
        projectNotice = ""
        do {
            let result: ProjectInviteResult = try await SupabaseService.client
                .rpc("project_create_invite", params: Params(pEventId: projectEventID, pRole: role,
                                                             pLaneId: role == "lane_lead" ? laneID : nil, pMaxUses: maxUses))
                .execute().value
            guard let inv = result.invite else {
                projectNotice = projectErrorText(result.error)
                return nil
            }
            projectInvites.insert(inv, at: 0)
            return inv
        } catch {
            print("createProjectInvite failed:", error)
            projectNotice = projectErrorText(nil)
            return nil
        }
    }

    func loadProjectInvites() async {
        if projectOffline { return }
        guard projectCan("invite.create", .init(role: "helper")) else { projectInvites = []; return }
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        do {
            let result: ProjectInviteList = try await SupabaseService.client
                .rpc("project_list_invites", params: Params(pEventId: projectEventID)).execute().value
            if result.success { projectInvites = result.invites ?? [] }
        } catch {
            print("loadProjectInvites failed:", error)
        }
    }

    @discardableResult
    func revokeProjectInvite(_ inviteID: String) async -> Bool {
        if projectOffline { projectInvites.removeAll { $0.id == inviteID }; return true }
        struct Params: Encodable {
            let pInviteId: String
            enum CodingKeys: String, CodingKey { case pInviteId = "p_invite_id" }
        }
        let ok = await projectWrite("project_revoke_invite", Params(pInviteId: inviteID), refresh: false)
        if ok { projectInvites.removeAll { $0.id == inviteID } }
        return ok
    }

    /// The text a Share sheet sends: the link and the typed code, in the inviter's language.
    func projectInviteShareText(_ inv: ProjectInvite) -> String {
        let link = ProjectInviteLink.joinURL(token: inv.token) ?? ""
        let name = projectSnapshot?.event?.name ?? ""
        return T("Mời bạn vào đội của \(name) trên banbe (\(projectRoleName(inv.role))). Mở liên kết: \(link) hoặc nhập mã \(inv.shortCode). Hết hạn sau 48 giờ.",
                 "Join the \(name) team on banbe as \(projectRoleName(inv.role)). Open \(link) or enter the code \(inv.shortCode). Expires in 48 hours.")
    }

    // MARK: members (Host)

    @discardableResult
    func setProjectMember(_ memberID: String, role: String, laneID: String?, capMoney: Bool, capCheckin: Bool) async -> Bool {
        if projectOffline {
            guard let i = projectSnapshot?.members?.firstIndex(where: { $0.memberId == memberID }), let m = projectSnapshot?.members?[i] else { return false }
            let finance = role == "finance"
            projectSnapshot?.members?[i] = ProjectMember(memberId: m.memberId, userId: m.userId, role: role, laneId: role == "lane_lead" ? laneID : nil,
                                                         capMoney: finance || capMoney, capCheckin: finance || capCheckin,
                                                         displayName: m.displayName, handle: m.handle, avatarUrl: m.avatarUrl)
            return true
        }
        struct Params: Encodable {
            let pMemberId: String; let pRole: String; let pLaneId: String?; let pCapMoney: Bool; let pCapCheckin: Bool
            enum CodingKeys: String, CodingKey {
                case pMemberId = "p_member_id", pRole = "p_role", pLaneId = "p_lane_id", pCapMoney = "p_cap_money", pCapCheckin = "p_cap_checkin"
            }
        }
        return await projectWrite("project_set_member", Params(pMemberId: memberID, pRole: role, pLaneId: role == "lane_lead" ? laneID : nil,
                                                               pCapMoney: capMoney, pCapCheckin: capCheckin))
    }

    @discardableResult
    func removeProjectMember(_ memberID: String, reason: String) async -> Bool {
        if projectOffline {
            if let uid = projectSnapshot?.members?.first(where: { $0.memberId == memberID })?.userId, let tasks = projectSnapshot?.tasks {
                projectSnapshot?.tasks = tasks.map { t in
                    var t = t
                    if t.assigneeId == uid && t.status != "done" { t.assigneeId = nil }
                    return t
                }
            }
            projectSnapshot?.members?.removeAll { $0.memberId == memberID }
            return true
        }
        struct Params: Encodable {
            let pMemberId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pMemberId = "p_member_id", pReason = "p_reason" }
        }
        return await projectWrite("project_remove_member", Params(pMemberId: memberID, pReason: reason))
    }

    func projectRoleNote(_ role: String) -> String {
        switch role {
        case "host": return T("Toàn quyền, duyệt hạng mục và kênh, đổi tài khoản nhận tiền.", "Full control. Approves lanes and channels, changes the payout account.")
        case "manager": return T("Điều phối việc và chủ đề, mời Trưởng hạng mục và Hỗ trợ, đề xuất hạng mục mới.",
                                 "Coordinates tasks and topics, invites Lane leads and Helpers, proposes new lanes.")
        case "finance": return T("Xác nhận thanh toán, xử lý hoàn tiền, check-in khách, khi banbe bật các quyền này.",
                                 "Confirms payments, handles refunds and checks guests in, once banbe turns these on.")
        case "lane_lead": return T("Phụ trách một hạng mục: tạo, giao và chốt việc trong hạng mục đó.", "Owns one lane: creates, assigns and settles its work.")
        default: return T("Làm việc được giao, hỏi và bỏ phiếu.", "Does assigned work, asks and votes.")
        }
    }

    // MARK: join

    /// A join link or a typed code. Signed out, the code is parked and the screen asks to log in first.
    /// A link, token or typed code -> what the server's peek/redeem accept (a token or a normalised BB- code).
    static func projectInviteValue(_ input: String) -> String? {
        ProjectInviteLink.parse(input).map { inv -> String in
            switch inv { case .token(let t): return t; case .code(let c): return c }
        }
    }

    func openProjectJoin(_ input: String, back: Screen? = nil) {
        let code = Self.projectInviteValue(input) ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        projectJoinBack = back ?? (screen == .projectJoin ? projectJoinBack : (screen == .login || screen == .welcome ? .home : screen))
        projectJoinCode = code
        projectJoinPeek = nil
        projectJoinError = ""
        screen = .projectJoin
        if userID == nil {
            if !code.isEmpty { UserDefaults.standard.set(code, forKey: Self.pendingProjectInviteKey) }
            return
        }
        if !code.isEmpty { Task { await peekProjectInvite() } }
    }

    /// The join screen with nothing typed yet ("Enter an invite code").
    func openProjectJoinEntry(back: Screen) {
        projectJoinBack = back
        projectJoinCode = UserDefaults.standard.string(forKey: Self.pendingProjectInviteKey) ?? ""
        projectJoinPeek = nil
        projectJoinError = ""
        screen = .projectJoin
        if userID != nil, !projectJoinCode.isEmpty { Task { await peekProjectInvite() } }
    }

    /// After a sign-in started from the join screen: look at the parked code again.
    func resumeProjectJoin() {
        let code = UserDefaults.standard.string(forKey: Self.pendingProjectInviteKey) ?? projectJoinCode
        openProjectJoin(code, back: .home)
    }

    func peekProjectInvite() async {
        guard !projectJoinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A pasted or scanned link becomes the bare value the server understands (and the field shows it).
        guard let code = Self.projectInviteValue(projectJoinCode) else {
            projectJoinPeek = nil
            projectJoinError = T("Mã có dạng BB-XXXX (4 ký tự).", "A code looks like BB-XXXX (4 characters).")
            return
        }
        if projectJoinCode != code { projectJoinCode = code }
        if projectOffline {
            projectJoinPeek = ProjectDemo.joinPeek(code)
            projectJoinError = projectJoinPeek == nil ? projectErrorText("INVITE_NOT_FOUND") : ""
            return
        }
        struct Params: Encodable {
            let pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        projectJoinLoading = true
        defer { projectJoinLoading = false }
        do {
            let result: ProjectInvitePeek = try await SupabaseService.client.rpc("peek_project_invite", params: Params(pCode: code)).execute().value
            guard code == Self.projectInviteValue(projectJoinCode) else { return }
            if result.success {
                projectJoinPeek = result
                projectJoinError = ""
            } else {
                projectJoinPeek = nil
                projectJoinError = projectErrorText(result.error)
            }
        } catch {
            print("peekProjectInvite failed:", error)
            projectJoinError = T("Chưa kiểm tra được mã. Hãy thử lại.", "Couldn't check the code. Try again.")
        }
    }

    /// Join with the code on screen; on success the new project opens on Overview.
    func joinProject() async {
        guard let code = Self.projectInviteValue(projectJoinCode) else { return }
        if projectOffline {
            UserDefaults.standard.removeObject(forKey: Self.pendingProjectInviteKey)
            fixtureJoined()
            return
        }
        struct Params: Encodable {
            let pCode: String
            enum CodingKeys: String, CodingKey { case pCode = "p_code" }
        }
        projectJoinLoading = true
        defer { projectJoinLoading = false }
        do {
            let result: ProjectRedeemResult = try await SupabaseService.client.rpc("project_redeem_invite", params: Params(pCode: code)).execute().value
            guard result.success, let eventID = result.eventId else {
                projectJoinError = projectErrorText(result.error)
                return
            }
            UserDefaults.standard.removeObject(forKey: Self.pendingProjectInviteKey)
            Haptics.success()
            await loadMyProjects()
            await openProject(eventID: eventID, back: projectJoinBack == .projectJoin ? .home : projectJoinBack)
        } catch {
            print("joinProject failed:", error)
            projectJoinError = T("Chưa vào được dự án. Hãy thử lại.", "Couldn't join. Try again.")
        }
    }

    /// Fixture or demo: joining lands on the sample project.
    private func fixtureJoined() {
        projectSnapshot = projectSampleSnapshot()
        projectEventID = projectSnapshot?.event?.id ?? "fx_project"
        projectTab = "overview"
        projectBackScreen = .home
        screen = .eventProject
    }

    // MARK: notifications

    /// `project_joined`, `project_blocked` (and the 18:00 digest later) carry {screen: event_project, event_id}. Only a
    /// project I'm in (as Host or member) opens; anything else stays on the bell.
    func openProjectFromNotification(_ notification: AppNotification) {
        guard notification.data["screen"]?.stringValue == "event_project",
              let eventID = notification.data["event_id"]?.stringValue, !eventID.isEmpty else { return }
        Task {
            await loadMyProjects()
            guard myProject(for: eventID) != nil else { return }
            await openProject(eventID: eventID, back: .notifications)
        }
    }
}

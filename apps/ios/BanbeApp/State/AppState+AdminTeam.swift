import Foundation

// Admin Team pass (2026-10-02, migration 121) — "Admin Team"/"Invite Admin"
// in Account → Admin, reusing the proven organizer/event-invite MECHANICS
// (AppState+Team.swift's own pattern, mirrored field-for-field) but NOT
// their permissions. `role == "admin"` and `canManageAdmins` are two
// different things, enforced server-side in every RPC below — this file
// never assumes/derives either, only ever reflects what the server
// already decided. See migration 121's own doc comment for the full RBAC
// model (why a newly-accepted admin invite does NOT inherit
// canManageAdmins, last-admin/self-lockout protection, etc).

private struct AdminRPCResult: Decodable {
    let success: Bool?
    let error: String?
}

struct AdminInvite: Decodable, Identifiable, Hashable {
    let id: UUID
    var invitedEmail: String
    var status: String
    var createdAt: Date?
    var expiresAt: Date?
    enum CodingKeys: String, CodingKey {
        case id
        case invitedEmail = "invited_email"
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

private struct AdminVoteRPCResult: Decodable { let success: Bool?; let error: String? }
private struct AdminVoteRoleRow: Decodable {
    let role: String
    let canManageAdmins: Bool
    enum CodingKeys: String, CodingKey { case role; case canManageAdmins = "can_manage_admins" }
}

/// One open removal vote (migration 172).
struct AdminRemovalVote: Decodable, Identifiable, Hashable {
    let id: UUID
    let kind: String            // "revoke_admin" | "revoke_management"
    let targetUserId: UUID
    let targetName: String
    let openedByName: String
    let isOpener: Bool
    let expiresAt: Date?
    let yes: Int
    let no: Int
    let electorate: Int
    let needed: Int
    let myVote: String?         // "yes" | "no" | nil
    let canVote: Bool
    enum CodingKeys: String, CodingKey {
        case id, kind, yes, no, electorate, needed
        case targetUserId = "target_user_id", targetName = "target_name", openedByName = "opened_by_name"
        case isOpener = "is_opener", expiresAt = "expires_at", myVote = "my_vote", canVote = "can_vote"
    }
}

/// `admin_removal_overview()` — who is protected, the admin floor and the open votes.
struct AdminRemovalOverview: Decodable, Hashable {
    let protectedUserId: UUID?
    let adminCount: Int
    let minAdmins: Int
    let electorate: Int
    let canOpen: Bool
    let votes: [AdminRemovalVote]
    enum CodingKeys: String, CodingKey {
        case protectedUserId = "protected_user_id", adminCount = "admin_count", minAdmins = "min_admins"
        case electorate, votes, canOpen = "can_open"
    }
}

struct AdminRosterRow: Decodable, Identifiable, Hashable {
    let id: UUID
    var displayName: String?
    var avatarUrl: String?
    var canManageAdmins: Bool
    var isSelf: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case canManageAdmins = "can_manage_admins"
        case isSelf = "is_self"
    }
}

extension AppState {
    /// This account's OWN pending admin invite, if any — a plain RLS-
    /// backed select (admin_invites_select_own), reachable regardless of
    /// current role (the whole point: the invitee isn't an admin yet).
    func loadMyAdminInvite() async {
        guard let uid = userID else { print("loadMyAdminInvite: no signed-in user, skipped"); return }
        // Preferred: RPC (migration 169) — resolves the invite by this
        // account's verified email and binds invited_user_id, so an invite
        // whose user id was never stored still reaches its recipient.
        do {
            let rows: [AdminInvite] = try await SupabaseService.client
                .rpc("get_my_admin_invite")
                .execute().value
            myAdminInvite = rows.first
            print("loadMyAdminInvite: RPC ok, pending invites =", rows.count)
            return
        } catch {
            print("get_my_admin_invite failed (migration 169 not applied?), falling back:", error)
        }
        // Fallback: plain RLS select (admin_invites_select_own) — only sees
        // invites already bound to this user id.
        do {
            let rows: [AdminInvite] = try await SupabaseService.client
                .from("admin_invites")
                .select("id, invited_email, status, created_at, expires_at")
                .eq("invited_user_id", value: uid.uuidString)
                .eq("status", value: "pending")
                .limit(1)
                .execute().value
            myAdminInvite = rows.first
            print("loadMyAdminInvite: fallback select ok, pending invites =", rows.count)
        } catch {
            print("loadMyAdminInvite failed:", error)
        }
    }

    func respondToAdminInvite(inviteID: UUID, accept: Bool) async {
        struct Params: Encodable {
            let pInviteId: String
            let pAccept: Bool
            enum CodingKeys: String, CodingKey { case pInviteId = "p_invite_id", pAccept = "p_accept" }
        }
        do {
            let result: AdminRPCResult = try await SupabaseService.client
                .rpc("respond_to_admin_invite", params: Params(pInviteId: inviteID.uuidString, pAccept: accept))
                .execute().value
            guard result.success == true else { print("respondToAdminInvite failed:", result.error ?? "unknown"); return }
            myAdminInvite = nil
            // Accepting changes this account's own role server-side —
            // patch the cached copy immediately rather than waiting for
            // the next sign-in/token-refresh cycle (same "don't just hide
            // a tab until next login" requirement revoke_admin()'s own
            // admin_access_revoked path also honors, see AppState+Data.swift).
            if accept, let uid = userID {
                struct RoleRow: Decodable { let role: String; let canManageAdmins: Bool
                    enum CodingKeys: String, CodingKey { case role; case canManageAdmins = "can_manage_admins" }
                }
                if let row: RoleRow = try? await SupabaseService.client.from("profiles")
                    .select("role, can_manage_admins").eq("id", value: uid.uuidString).single().execute().value {
                    accountType = row.role
                    canManageAdmins = row.canManageAdmins
                }
            }
        } catch {
            print("respondToAdminInvite failed:", error)
        }
    }

    /// Manage-admins-capable admin only — both lists come back empty/
    /// denied under RLS for anyone else; this is a convenience fetch, not
    /// the real security boundary.
    func loadAdminTeam() async {
        adminTeamLoading = true
        defer { adminTeamLoading = false }
        async let rosterTask: [AdminRosterRow] = SupabaseService.client.rpc("list_admin_roster").execute().value
        async let invitesTask: [AdminInvite] = SupabaseService.client.from("admin_invites")
            .select("id, invited_email, status, created_at, expires_at")
            .order("created_at", ascending: false)
            .execute().value
        do {
            adminRoster = try await rosterTask
        } catch {
            print("list_admin_roster failed:", error)
        }
        do {
            let overview: AdminRemovalOverview = try await SupabaseService.client.rpc("admin_removal_overview").execute().value
            adminRemoval = overview
        } catch {
            // Also lands here for {"error":"NOT_AUTHORIZED"} (non-manager) and when migration 172 isn't applied.
            adminRemoval = nil
        }
        do {
            adminInvites = try await invitesTask
        } catch {
            print("loadAdminTeam invites failed:", error)
        }
    }

    private static let adminInviteErrorMessages: [String: (String, String)] = [
        "NOT_AUTHORIZED": ("Bạn không có quyền mời quản trị viên.", "You don't have permission to invite admins."),
        "INVALID_EMAIL": ("Email không hợp lệ.", "Invalid email address."),
        "ALREADY_ADMIN": ("Tài khoản này đã là quản trị viên.", "That account is already an admin."),
        "ALREADY_INVITED_PENDING": ("Đã có lời mời đang chờ cho email này.", "There is already a pending invite for this email."),
    ]
    private static let revokeAdminErrorMessages: [String: (String, String)] = [
        "NOT_AUTHORIZED": ("Bạn không có quyền này.", "You don't have this permission."),
        "CANNOT_REVOKE_SELF": ("Bạn không thể tự thu hồi quyền của chính mình.", "You cannot revoke your own admin access."),
        "LAST_ADMIN_CANNOT_BE_REVOKED": ("Không thể thu hồi quản trị viên cuối cùng.", "The last remaining admin cannot be revoked."),
        "TARGET_NOT_ADMIN": ("Tài khoản này không phải quản trị viên.", "That account is not an admin."),
        "PROTECTED_ADMIN_MIN_ADMINS": ("Tài khoản được bảo vệ này chỉ có thể bị gỡ khi có ít nhất 3 quản trị viên, và phải qua bỏ phiếu.", "This protected admin can only be changed when there are at least 3 admins, and only by a vote."),
        "PROTECTED_ADMIN_VOTE_REQUIRED": ("Tài khoản được bảo vệ này chỉ có thể bị gỡ qua một cuộc bỏ phiếu.", "This protected admin can only be changed through a vote."),
        "NOT_ENOUGH_VOTERS": ("Cần ít nhất 2 quản trị viên có quyền quản lý đội ngũ (không tính tài khoản bị gỡ) để bỏ phiếu.", "At least 2 admins with team-management access (not counting the account in question) are needed to vote."),
        "VOTE_ALREADY_OPEN": ("Đã có một cuộc bỏ phiếu đang mở cho việc này.", "A vote for this is already open."),
        "ALREADY_VOTED": ("Bạn đã bỏ phiếu rồi.", "You have already voted."),
        "VOTE_NOT_OPEN": ("Cuộc bỏ phiếu này đã kết thúc.", "This vote has ended."),
        "TARGET_HAS_NO_MANAGEMENT_ACCESS": ("Tài khoản này không còn quyền quản lý đội ngũ.", "This account no longer has team-management access."),
    ]

    /// Explicit confirmation of the intended recipient before anything is
    /// sent — opens a plain inline confirm, never sends on one tap.
    func requestAdminInviteConfirm() {
        let email = adminInviteEmailDraft.trimmingCharacters(in: .whitespaces)
        guard email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            adminInviteError = T("Email không hợp lệ.", "Invalid email address.")
            return
        }
        adminInviteConfirmEmail = email
    }
    func cancelAdminInviteConfirm() { adminInviteConfirmEmail = nil }

    func confirmAdminInvite() async {
        guard let email = adminInviteConfirmEmail else { return }
        adminInviteBusy = true
        adminInviteError = ""
        struct Params: Encodable { let pEmail: String; enum CodingKeys: String, CodingKey { case pEmail = "p_email" } }
        struct Result: Decodable { let success: Bool?; let error: String? }
        do {
            let result: Result = try await SupabaseService.client
                .rpc("create_admin_invite", params: Params(pEmail: email))
                .execute().value
            adminInviteBusy = false
            adminInviteConfirmEmail = nil
            guard result.success == true else {
                let msg = Self.adminInviteErrorMessages[result.error ?? ""] ?? ("Không gửi được lời mời.", "Could not send the invite.")
                adminInviteError = T(msg.0, msg.1)
                return
            }
            adminInviteEmailDraft = ""
            await loadAdminTeam()
        } catch {
            adminInviteBusy = false
            adminInviteConfirmEmail = nil
            adminInviteError = T("Không gửi được lời mời.", "Could not send the invite.")
            print("confirmAdminInvite failed:", error)
        }
    }

    func requestRevokeAdminInviteConfirm(_ id: UUID) { revokeAdminInviteConfirmID = id }
    func cancelRevokeAdminInviteConfirm() { revokeAdminInviteConfirmID = nil }
    func confirmRevokeAdminInvite() async {
        guard let id = revokeAdminInviteConfirmID else { return }
        revokeAdminInviteConfirmID = nil
        struct Params: Encodable { let pInviteId: String; enum CodingKeys: String, CodingKey { case pInviteId = "p_invite_id" } }
        do {
            let result: AdminRPCResult = try await SupabaseService.client
                .rpc("revoke_admin_invite", params: Params(pInviteId: id.uuidString))
                .execute().value
            guard result.success == true else { print("revoke_admin_invite failed:", result.error ?? "unknown"); return }
            await loadAdminTeam()
        } catch {
            print("revoke_admin_invite failed:", error)
        }
    }

    /// Grants/removes `can_manage_admins` for another admin (server: `set_admin_management_permission`,
    /// caller must already have it; target must be an admin).
    func setAdminManagementPermission(_ id: UUID, enabled: Bool) async {
        struct Params: Encodable {
            let pUserId: String; let pEnabled: Bool
            enum CodingKeys: String, CodingKey { case pUserId = "p_user_id"; case pEnabled = "p_enabled" }
        }
        struct Result: Decodable { let success: Bool?; let error: String? }
        do {
            let result: Result = try await SupabaseService.client
                .rpc("set_admin_management_permission", params: Params(pUserId: id.uuidString, pEnabled: enabled))
                .execute().value
            guard result.success == true else {
                let msg = Self.revokeAdminErrorMessages[result.error ?? ""] ?? ("Không thực hiện được thao tác.", "Could not complete that action.")
                adminInviteError = T(msg.0, msg.1)
                return
            }
            await loadAdminTeam()
        } catch {
            print("set_admin_management_permission failed:", error)
        }
    }

    func requestRevokeAdminConfirm(_ id: UUID) { revokeAdminConfirmID = id }
    func cancelRevokeAdminConfirm() { revokeAdminConfirmID = nil }
    func confirmRevokeAdmin() async {
        guard let id = revokeAdminConfirmID else { return }
        revokeAdminConfirmID = nil
        struct Params: Encodable { let pUserId: String; enum CodingKeys: String, CodingKey { case pUserId = "p_user_id" } }
        struct Result: Decodable { let success: Bool?; let error: String? }
        do {
            let result: Result = try await SupabaseService.client
                .rpc("revoke_admin", params: Params(pUserId: id.uuidString))
                .execute().value
            guard result.success == true else {
                let msg = Self.revokeAdminErrorMessages[result.error ?? ""] ?? ("Không thực hiện được thao tác.", "Could not complete that action.")
                adminInviteError = T(msg.0, msg.1)
                return
            }
            await loadAdminTeam()
        } catch {
            print("revoke_admin failed:", error)
        }
    }

    // migration 172 — voting round for the protected admin (banbetestadmin@gmail.com).
    private func adminRemovalCall<P: Encodable>(_ fn: String, _ params: P) async {
        adminRemovalBusy = true
        adminInviteError = ""
        defer { adminRemovalBusy = false }
        do {
            let result: AdminVoteRPCResult = try await SupabaseService.client.rpc(fn, params: params).execute().value
            if result.success != true {
                let msg = Self.revokeAdminErrorMessages[result.error ?? ""] ?? ("Không thực hiện được thao tác.", "Could not complete that action.")
                adminInviteError = T(msg.0, msg.1)
            }
        } catch {
            print("\(fn) failed:", error)
            adminInviteError = T("Không thực hiện được thao tác.", "Could not complete that action.")
        }
        await loadAdminTeam()
        // A passed vote may have changed THIS account's own role / permission.
        if let uid = userID {
            if let row: AdminVoteRoleRow = try? await SupabaseService.client.from("profiles")
                .select("role, can_manage_admins").eq("id", value: uid.uuidString).single().execute().value {
                accountType = row.role
                canManageAdmins = row.canManageAdmins
            }
        }
    }
    func openAdminRemovalVote(targetID: UUID, kind: String) async {
        struct P: Encodable { let pTarget: String; let pKind: String
            enum CodingKeys: String, CodingKey { case pTarget = "p_target", pKind = "p_kind" } }
        await adminRemovalCall("open_admin_removal_vote", P(pTarget: targetID.uuidString, pKind: kind))
    }
    func castAdminRemovalVote(voteID: UUID, approve: Bool) async {
        struct P: Encodable { let pVoteId: String; let pApprove: Bool
            enum CodingKeys: String, CodingKey { case pVoteId = "p_vote_id", pApprove = "p_approve" } }
        await adminRemovalCall("cast_admin_removal_vote", P(pVoteId: voteID.uuidString, pApprove: approve))
    }
    func cancelAdminRemovalVote(voteID: UUID) async {
        struct P: Encodable { let pVoteId: String
            enum CodingKeys: String, CodingKey { case pVoteId = "p_vote_id" } }
        await adminRemovalCall("cancel_admin_removal_vote", P(pVoteId: voteID.uuidString))
    }
}

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
}

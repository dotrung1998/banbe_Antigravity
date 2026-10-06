import Foundation

// Organizer Team pass (2026-09-27, Stage 1) — real, opt-in organizer
// membership (organizer_members, migration 098). Mirrors BanBeContext.jsx's
// own Team actions field-for-field — see that file's doc comment for the
// full privacy model (public_visible defaults false, only the member's
// own switch can ever turn it on, the owner can remove but never publish).

private struct TeamRPCResult: Decodable {
    let success: Bool?
    let error: String?
    let publicVisible: Bool?
    enum CodingKeys: String, CodingKey {
        case success, error
        case publicVisible = "public_visible"
    }
}

struct OrganizerMembershipOrganizerJoin: Codable, Hashable {
    var name: String?
    var avatarPath: String?
    enum CodingKeys: String, CodingKey {
        case name
        case avatarPath = "avatar_path"
    }
}

struct OrganizerMembership: Codable, Identifiable, Hashable {
    let id: UUID
    var organizerId: String
    var status: String
    var publicRole: String
    var publicVisible: Bool
    var joinedAt: Date?
    var organizers: OrganizerMembershipOrganizerJoin?
    enum CodingKeys: String, CodingKey {
        case id
        case organizerId = "organizer_id"
        case status
        case publicRole = "public_role"
        case publicVisible = "public_visible"
        case joinedAt = "joined_at"
        case organizers
    }
}

struct OrganizerTeamRosterProfileJoin: Codable, Hashable {
    var handle: String?
    var displayName: String?
    var avatarUrl: String?
    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct OrganizerTeamRosterRow: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var status: String
    var publicRole: String
    var publicVisible: Bool
    var invitedAt: Date
    var joinedAt: Date?
    var profiles: OrganizerTeamRosterProfileJoin?
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case publicRole = "public_role"
        case publicVisible = "public_visible"
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case profiles
    }
}

// Organizer Team pass (2026-09-27, Stage 2) — public Team page + real
// event-organizing credits.

struct OrganizerTeamMember: Decodable, Identifiable, Hashable {
    var id: String { handle }
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let publicRole: String
    let joinedAt: Date?
    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case publicRole = "public_role"
        case joinedAt = "joined_at"
    }
}

struct OrganizerTeam: Decodable {
    let success: Bool
    let error: String?
    let organizerId: String?
    let organizerName: String?
    let members: [OrganizerTeamMember]?
    enum CodingKeys: String, CodingKey {
        case success, error, members
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
    }
}

struct EventCreditEventJoin: Decodable, Hashable { let name: String? }
struct EventCreditOrganizerJoin: Decodable, Hashable { let name: String? }

struct EventCreditInvite: Decodable, Identifiable, Hashable {
    let id: UUID
    let eventId: String
    let organizerId: String
    let status: String
    let events: EventCreditEventJoin?
    let organizers: EventCreditOrganizerJoin?
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case organizerId = "organizer_id"
        case status, events, organizers
    }
}

extension AppState {
    /// This account's OWN pending invites + accepted memberships — a
    /// plain RLS-backed select (organizer_members_select_own), not an
    /// RPC; the table's own RLS already restricts this to user_id = self.
    func loadMyOrganizerMemberships() async {
        guard let uid = userID else { return }
        do {
            let rows: [OrganizerMembership] = try await SupabaseService.client
                .from("organizer_members")
                .select("id, organizer_id, status, public_role, public_visible, joined_at, organizers(name, avatar_path)")
                .eq("user_id", value: uid.uuidString)
                .in("status", values: ["invited", "accepted"])
                .order("invited_at", ascending: false)
                .execute().value
            myOrganizerInvites = rows.filter { $0.status == "invited" }
            myTeamMemberships = rows.filter { $0.status == "accepted" }
        } catch {
            print("loadMyOrganizerMemberships failed:", error)
        }
    }

    func respondToOrganizerInvite(membershipID: UUID, accept: Bool) async {
        struct Params: Encodable {
            let pMembershipId: String
            let pAccept: Bool
            enum CodingKeys: String, CodingKey { case pMembershipId = "p_membership_id", pAccept = "p_accept" }
        }
        do {
            let _: TeamRPCResult = try await SupabaseService.client
                .rpc("respond_to_organizer_invite", params: Params(pMembershipId: membershipID.uuidString, pAccept: accept))
                .execute().value
            await loadMyOrganizerMemberships()
        } catch {
            print("respondToOrganizerInvite failed:", error)
        }
    }

    /// The member's OWN switch — optimistic, reconciled on failure; the
    /// ONLY path that can ever turn `public_visible` on.
    func setOrganizerMemberVisibility(membershipID: UUID, visible: Bool) async {
        struct Params: Encodable {
            let pMembershipId: String
            let pVisible: Bool
            enum CodingKeys: String, CodingKey { case pMembershipId = "p_membership_id", pVisible = "p_visible" }
        }
        if let idx = myTeamMemberships.firstIndex(where: { $0.id == membershipID }) {
            myTeamMemberships[idx].publicVisible = visible
        }
        do {
            let result: TeamRPCResult = try await SupabaseService.client
                .rpc("set_organizer_member_visibility", params: Params(pMembershipId: membershipID.uuidString, pVisible: visible))
                .execute().value
            if result.success != true, let idx = myTeamMemberships.firstIndex(where: { $0.id == membershipID }) {
                myTeamMemberships[idx].publicVisible = !visible
            }
        } catch {
            print("setOrganizerMemberVisibility failed:", error)
            if let idx = myTeamMemberships.firstIndex(where: { $0.id == membershipID }) {
                myTeamMemberships[idx].publicVisible = !visible
            }
        }
    }

    /// Owner/co-owner only — the FULL roster (every status), never shown
    /// to anyone else. `!organizer_members_user_id_fkey` disambiguates
    /// the embed: this table has two FKs into profiles (user_id AND
    /// invited_by), so PostgREST can't infer which one without a hint.
    func loadOrgTeamRoster(organizerID: String) async {
        orgTeamRosterLoading = true
        do {
            let rows: [OrganizerTeamRosterRow] = try await SupabaseService.client
                .from("organizer_members")
                .select("id, user_id, status, public_role, public_visible, invited_at, joined_at, profiles!organizer_members_user_id_fkey(handle, display_name, avatar_url)")
                .eq("organizer_id", value: organizerID)
                .order("invited_at", ascending: false)
                .execute().value
            orgTeamRoster = rows
            orgTeamRosterLoading = false
        } catch {
            print("loadOrgTeamRoster failed:", error)
            orgTeamRosterLoading = false
        }
    }

    func inviteOrganizerMember(organizerID: String) async {
        let handle = orgTeamInviteHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { return }
        struct Params: Encodable {
            let pOrganizerId: String
            let pHandle: String
            let pPublicRole: String
            enum CodingKeys: String, CodingKey { case pOrganizerId = "p_organizer_id", pHandle = "p_handle", pPublicRole = "p_public_role" }
        }
        orgTeamInviteBusy = true
        orgTeamInviteError = ""
        do {
            let role = orgTeamInviteRole.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: TeamRPCResult = try await SupabaseService.client
                .rpc("invite_organizer_member", params: Params(pOrganizerId: organizerID, pHandle: handle, pPublicRole: role.isEmpty ? "Thành viên" : role))
                .execute().value
            guard result.success == true else {
                orgTeamInviteBusy = false
                switch result.error {
                case "USER_NOT_FOUND": orgTeamInviteError = T("Không tìm thấy người dùng với tên này.", "No user found with that handle.")
                case "ALREADY_MEMBER": orgTeamInviteError = T("Người này đã ở trong đội ngũ hoặc đang chờ phản hồi.", "This person is already a member or has a pending invite.")
                case "CANNOT_INVITE_OWNER": orgTeamInviteError = T("Không thể mời chính chủ sở hữu.", "You can't invite the owner.")
                default: orgTeamInviteError = T("Không thể gửi lời mời lúc này. Vui lòng thử lại.", "Couldn't send the invite right now. Please try again.")
                }
                return
            }
            orgTeamInviteBusy = false
            orgTeamInviteHandle = ""
            orgTeamInviteRole = ""
            await loadOrgTeamRoster(organizerID: organizerID)
        } catch {
            print("inviteOrganizerMember failed:", error)
            orgTeamInviteBusy = false
            orgTeamInviteError = T("Không thể gửi lời mời lúc này. Vui lòng thử lại.", "Couldn't send the invite right now. Please try again.")
        }
    }

    func removeOrganizerMember(membershipID: UUID, organizerID: String) async {
        struct Params: Encodable {
            let pMembershipId: String
            enum CodingKeys: String, CodingKey { case pMembershipId = "p_membership_id" }
        }
        do {
            let _: TeamRPCResult = try await SupabaseService.client
                .rpc("remove_organizer_member", params: Params(pMembershipId: membershipID.uuidString))
                .execute().value
            await loadOrgTeamRoster(organizerID: organizerID)
        } catch {
            print("removeOrganizerMember failed:", error)
        }
    }

    /// get_organizer_team (098/101) — PUBLIC/anon-safe: accepted AND
    /// public_visible members only. Reused verbatim from the "Bởi <org>
    /// Team ›" row (OrganizerProfileView) and a standalone deep link alike.
    func openOrganizerTeam(organizerID: String, back: Screen = .organizerProfile) async {
        organizerTeamBackScreen = back
        organizerTeam = nil
        organizerTeamLoading = true
        organizerTeamError = ""
        organizerTeamOrganizerId = organizerID
        screen = .organizerTeam
        struct Params: Encodable {
            let pOrganizerId: String
            enum CodingKeys: String, CodingKey { case pOrganizerId = "p_organizer_id" }
        }
        do {
            let result: OrganizerTeam = try await SupabaseService.client
                .rpc("get_organizer_team", params: Params(pOrganizerId: organizerID))
                .execute().value
            guard result.success else {
                organizerTeamLoading = false
                organizerTeamError = T("Không tìm thấy đội ngũ này.", "This Team couldn't be found.")
                return
            }
            organizerTeam = result
            organizerTeamLoading = false
        } catch {
            print("openOrganizerTeam failed:", error)
            organizerTeamLoading = false
            organizerTeamError = T("Không tìm thấy đội ngũ này.", "This Team couldn't be found.")
        }
    }
    func backFromOrganizerTeam() { screen = organizerTeamBackScreen }

    /// This account's OWN pending event-credit invites — real, explicit,
    /// owner-assigned; never derived from bookings/check-ins.
    func loadMyEventCredits() async {
        guard let uid = userID else { return }
        do {
            let rows: [EventCreditInvite] = try await SupabaseService.client
                .from("event_credits")
                .select("id, event_id, organizer_id, status, events(name), organizers(name)")
                .eq("user_id", value: uid.uuidString)
                .eq("status", value: "invited")
                .order("created_at", ascending: false)
                .execute().value
            myEventCredits = rows
        } catch {
            print("loadMyEventCredits failed:", error)
        }
    }

    /// iPhone fix pass (2026-09-27), Issue 5 — the CONFIRMED half; same
    /// table/RLS as loadMyEventCredits() above (event_credits_select_own:
    /// `user_id = auth.uid()`), just `status = 'accepted'` instead of
    /// `'invited'`. Account's own "Đóng góp sự kiện" section renders these
    /// separately from the pending list — this account's own PRIVATE view,
    /// regardless of whether it opted into showing them publicly (that's a
    /// SEPARATE switch, `set_organizer_member_visibility`'s own
    /// `public_visible`, which only ever gates the PUBLIC profile's own
    /// `credited_events` — see get_public_profile, migration 100).
    func loadMyConfirmedEventCredits() async {
        guard let uid = userID else { return }
        do {
            let rows: [EventCreditInvite] = try await SupabaseService.client
                .from("event_credits")
                .select("id, event_id, organizer_id, status, events(name), organizers(name)")
                .eq("user_id", value: uid.uuidString)
                .eq("status", value: "accepted")
                .order("responded_at", ascending: false)
                .execute().value
            myConfirmedEventCredits = rows
        } catch {
            print("loadMyConfirmedEventCredits failed:", error)
        }
    }

    func respondToEventCredit(creditID: UUID, accept: Bool) async {
        struct Params: Encodable {
            let pCreditId: String
            let pAccept: Bool
            enum CodingKeys: String, CodingKey { case pCreditId = "p_credit_id", pAccept = "p_accept" }
        }
        do {
            let _: TeamRPCResult = try await SupabaseService.client
                .rpc("respond_to_event_credit", params: Params(pCreditId: creditID.uuidString, pAccept: accept))
                .execute().value
            // iPhone fix pass (2026-09-27), Issue 5 — "refresh all views
            // after the action": an accept moves the row from the pending
            // list to the confirmed one; reloading only the pending side
            // (as before) left an accepted credit invisible until the next
            // full relaunch.
            await loadMyEventCredits()
            await loadMyConfirmedEventCredits()
        } catch {
            print("respondToEventCredit failed:", error)
        }
    }

    /// Owner/co-owner only — credits a real ACCEPTED team member for a
    /// real event they own. Never the owner "crediting" themselves; never
    /// a stranger who hasn't accepted the Team invite (the RPC itself
    /// re-checks both server-side regardless).
    @discardableResult
    func assignEventCredit(eventID: String, userID: UUID) async -> Bool {
        struct Params: Encodable {
            let pEventId: String
            let pUserId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pUserId = "p_user_id" }
        }
        do {
            let result: TeamRPCResult = try await SupabaseService.client
                .rpc("assign_event_credit", params: Params(pEventId: eventID, pUserId: userID.uuidString))
                .execute().value
            return result.success == true
        } catch {
            print("assignEventCredit failed:", error)
            return false
        }
    }
}

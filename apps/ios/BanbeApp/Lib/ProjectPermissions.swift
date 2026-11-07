import Foundation

/// Event Project Hub permissions (note 76): who may do what in an event's private team project.
/// Web twin: src/lib/projectPermissions.js. Shared vectors: tests/fixtures/project-permissions.json, run under BOTH
/// Host definitions. The server enforces the same rules (migrations 210-214); this copy only decides what the UI offers.
///
/// Two different "host" checks, on purpose:
/// - `projectIsHost`: the Host of the PROJECT. v1 = either organizer account (owner_id or user_id), exactly like
///   is_event_host() today. Mirrors the server helper project_is_host(), the one place to change if the Host ever
///   becomes owner_id only (`.ownerOnly`).
/// - `organizerAccount`: the check the EXISTING money and door RPCs already make (confirm_payment, check_in_guest,
///   mark_refund_sent: owner_id or user_id). Delegation only ever ADDS people on top of it, so changing the project
///   Host can never take money or door rights away from anyone who has them today. Event cancellation and the payout
///   account are not project actions at all and are not modelled here.
///
/// Roles stored on a member: manager ("Quản lý"), finance, lane_lead, helper. The Host is never a stored role.
enum ProjectPermissions {
    enum HostDefinition: String { case either, ownerOnly = "owner_only" }

    static let roles = ["manager", "finance", "lane_lead", "helper"]
    /// Which roles each inviter may preset on an invite.
    static let invitableByHost = ["manager", "finance", "lane_lead", "helper"]
    static let invitableByManager = ["lane_lead", "helper"]

    /// Every action this module answers; anything else is refused.
    static let actions = [
        "project.read", "project.start", "channels.open",
        "task.status", "task.manage",
        "post.question", "post.update", "post.vote", "post.seen", "post.reply", "post.proposal", "post.decision",
        "post.resolve", "post.edit", "post.delete",
        "invite.create", "invite.revoke", "member.manage",
        "lane.manage", "channels.edit", "change.propose", "change.review",
        "ros.edit", "ros.tick", "trash.restore", "trash.purge",
        "refund.approval.set", "grants.extend",
        "checkin", "money.view", "money.confirm", "money.reject", "proof.open",
        "refund.request", "refund.markSent", "refund.approve",
    ]

    private static let hostOnlyWrites: Set<String> = ["member.manage", "lane.manage", "channels.edit", "change.review",
                                                      "refund.approval.set", "grants.extend", "trash.purge"]
    private static let anyMemberWrites: Set<String> = ["post.question", "post.update", "post.vote", "post.seen", "post.reply", "ros.tick"]

    struct Organizer: Equatable { let ownerId: String?; let userId: String? }

    struct Member: Equatable {
        var role: String
        var laneId: String? = nil
        var capMoney = false
        var capCheckin = false
        var status = "active"
        var grantExpiresAt: Date? = nil
    }

    struct Target: Equatable {
        var laneId: String? = nil
        var assigneeId: String? = nil
        var authorId: String? = nil
        var addresseeId: String? = nil
        var createdBy: String? = nil
        var type: String? = nil
        var state: String? = nil
        var quiet: Bool? = nil
        var role: String? = nil
        var awaitingVerification: Bool? = nil
        var refundClaimId: String? = nil
    }

    struct DisputeGrant: Equatable { let userId: String; let refundClaimId: String; let until: Date; let disputeOpen: Bool }

    struct Context {
        var userId: String?
        var member: Member?
        var organizer: Organizer?
        var hostDefinition: HostDefinition = .either
        var flags: [String: Bool] = [:]
        var now: Date = Date()
        var readOnlyAt: Date? = nil
        /// "host" (the default) or "finance_alone".
        var refundApproval = "host"
        var target = Target()
        var disputeGrants: [DisputeGrant] = []
    }

    /// The existing RPCs' own check: either organizer account.
    static func organizerAccount(_ userId: String?, _ org: Organizer?) -> Bool {
        guard let userId, let org else { return false }
        return userId == org.ownerId || userId == org.userId
    }

    /// project_is_host(): v1 `.either` (both organizer accounts); `.ownerOnly` is the one-line alternative.
    static func projectIsHost(_ userId: String?, _ org: Organizer?, _ def: HostDefinition = .either) -> Bool {
        guard let userId, let org else { return false }
        return def == .ownerOnly ? userId == org.ownerId : organizerAccount(userId, org)
    }

    /// Finance always holds both capabilities; anyone else holds what the Host granted.
    static func caps(_ m: Member?) -> (money: Bool, checkin: Bool) {
        guard let m else { return (false, false) }
        if m.role == "finance" { return (true, true) }
        return (m.capMoney, m.capCheckin)
    }

    static func can(_ action: String, _ c: Context) -> Bool {
        let uid = c.userId
        let host = projectIsHost(uid, c.organizer, c.hostDefinition)
        let org = organizerAccount(uid, c.organizer)
        let m = c.member?.status == "active" ? c.member : nil
        let role = m?.role
        let t = c.target
        let hub = FeatureFlags.isOn(c.flags, "event_project_hub")
        let readOnly = c.readOnlyAt.map { c.now >= $0 } ?? false
        let inProject = hub && (host || m != nil)
        let write = inProject && !readOnly
        let manager = role == "manager"
        let leadOk = role == "lane_lead" && (t.laneId == nil || m?.laneId == t.laneId)
        func mine(_ id: String?) -> Bool { uid != nil && id == uid }
        let cap = caps(m)
        let grantLive = m != nil && (m?.grantExpiresAt.map { c.now < $0 } ?? true) && !readOnly
        func delegate(_ flag: String, money: Bool) -> Bool {
            hub && FeatureFlags.isOn(c.flags, flag) && grantLive && (money ? cap.money : cap.checkin)
        }
        let disputeOk = hub && FeatureFlags.isOn(c.flags, "project_delegate_refunds") && t.refundClaimId != nil &&
            c.disputeGrants.contains { $0.userId == uid && $0.refundClaimId == t.refundClaimId && $0.disputeOpen && c.now < $0.until }

        if hostOnlyWrites.contains(action) { return write && host }
        if anyMemberWrites.contains(action) { return write }
        switch action {
        case "project.read", "channels.open":
            return inProject
        case "project.start":
            return hub && host && !readOnly
        case "task.status":
            return write && (host || manager || leadOk || mine(t.assigneeId))
        case "task.manage", "post.decision":
            return write && (host || manager || leadOk)
        case "post.proposal":
            return write && (host || manager || role == "finance" || role == "lane_lead")
        case "post.resolve":
            return write && t.state == "open" && t.type != "update" &&
                (host || manager || leadOk || mine(t.authorId) || mine(t.addresseeId))
        case "post.edit":
            return write && mine(t.authorId) && t.state == "open" && t.type != "decision" && t.quiet == true
        case "post.delete":
            return write && (host || manager || (mine(t.authorId) && t.state == "open" && t.quiet == true))
        case "invite.create":
            let r = t.role ?? ""
            return write && ((host && invitableByHost.contains(r)) || (manager && invitableByManager.contains(r)))
        case "invite.revoke":
            return write && (host || (manager && mine(t.createdBy)))
        case "change.propose":
            return write && manager
        case "ros.edit", "trash.restore":
            return write && (host || manager)
        // Money and door: the existing check, plus delegation behind its own switch (migrations 212-214).
        case "checkin":
            return org || delegate("project_delegate_checkin", money: false)
        case "money.view", "money.confirm":
            return org || delegate("project_delegate_payments", money: true)
        case "proof.open":
            return org || (delegate("project_delegate_payments", money: true) && t.awaitingVerification == true)
        case "money.reject":
            return org // reject_pending_guest cancels a seat: not delegated
        case "refund.request":
            return !org && (delegate("project_delegate_refunds", money: true) || disputeOk)
        case "refund.markSent":
            return org || (c.refundApproval == "finance_alone" && (delegate("project_delegate_refunds", money: true) || disputeOk))
        case "refund.approve":
            return org
        default:
            return false
        }
    }
}

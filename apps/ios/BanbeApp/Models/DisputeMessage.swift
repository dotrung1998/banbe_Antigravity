import Foundation

/// One line in the temporary dispute chat (`dispute_messages`) — the Swift
/// counterpart of GocContext.jsx's disputeChatMessages. Purged along with
/// its thread once resolve_dispute() closes it out and the grace window in
/// purge_resolved_dispute_threads() elapses.
struct DisputeMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var senderId: UUID?
    var senderRole: String  // "guest" | "organizer" | "system"
    var body: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case senderRole = "sender_role"
        case body
        case createdAt = "created_at"
    }
}

/// A row from `v_disputes` — RLS-scoped the same way bookings always are,
/// so the exact same query returns different things depending on who asks:
/// an organizer sees only their own events' disputes (used by
/// VerificationsView, so they can keep talking with a guest after
/// escalating — the booking leaves v_pending_verifications the moment it's
/// escalated, so without this there'd be nowhere left on that screen to
/// reach it), and a platform admin sees every dispute (used by
/// AdminDashboardView, the actual resolution desk).
struct DisputeRow: Codable, Identifiable, Hashable {
    let bookingId: UUID
    var eventName: String?
    var guestName: String?
    var organizerName: String?
    var totalVnd: Int
    var paymentRef: String?
    var transactionId: String?
    var proofPath: String?
    var disputeReason: String?
    var disputeResolvedAt: Date?
    var disputeResolution: String?
    var id: UUID { bookingId }

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case eventName = "event_name"
        case guestName = "guest_name"
        case organizerName = "organizer_name"
        case totalVnd = "total_vnd"
        case paymentRef = "payment_ref"
        case transactionId = "transaction_id"
        case proofPath = "proof_path"
        case disputeReason = "dispute_reason"
        case disputeResolvedAt = "dispute_resolved_at"
        case disputeResolution = "dispute_resolution"
    }
}

/// One line of `payment_audit_log` — the T1/T2/T3 trail a dispute is argued
/// on, same data AdminDashboardView shows Disputes.jsx showing on web.
struct PaymentAuditEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var action: String
    var at: Date
    var actorKind: String?
    var ip: String?

    enum CodingKeys: String, CodingKey {
        case id, action, at
        case actorKind = "actor_kind"
        case ip
    }
}

/// One row of get_my_dispute_chats() (migration 129) — the yellow "dispute"
/// section pinned at the top of Messages. One per live dispute chat this
/// account is a party to, whether it's a payment dispute (the host escalated
/// to banbe) or a refund dispute (the goer reported not receiving the money,
/// which had no chat at all before this).
///
/// `bookingId` is nil and `refundClaimId` set for a refund dispute, exactly as
/// the row is keyed server-side; `kind` says which, so a view never has to
/// infer it. `resolvedAt`/`purgeAfter` drive the "ends in N days" countdown —
/// both parties keep the row for a 7-day window after a REFUND dispute
/// settles, then the purge sweep removes it for good.
struct DisputeChatSummary: Codable, Identifiable, Hashable {
    let threadId: UUID
    /// "payment" | "refund"
    let kind: String
    let bookingId: UUID?
    let refundClaimId: UUID?
    let eventId: String?
    let eventKey: String?
    let eventName: String?
    /// Whoever this account is NOT — the organizer for a goer, the guest for
    /// a host.
    let otherName: String?
    let otherAvatarUrl: String?
    let amountVnd: Int?
    /// refund_claims.status while this is a refund dispute (nil otherwise).
    let claimStatus: String?
    let disputedAt: Date?
    let resolvedAt: Date?
    let purgeAfter: Date?
    let lastMessageAt: Date?
    let lastMessageBody: String?
    let messageCount: Int
    /// "guest" | "organizer" — which side of this dispute this account is on.
    let viewerRole: String
    var id: UUID { threadId }
    var isRefund: Bool { kind == "refund" }
    var isConcluded: Bool { resolvedAt != nil }

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case kind
        case bookingId = "booking_id"
        case refundClaimId = "refund_claim_id"
        case eventId = "event_id"
        case eventKey = "event_key"
        case eventName = "event_name"
        case otherName = "other_name"
        case otherAvatarUrl = "other_avatar_url"
        case amountVnd = "amount_vnd"
        case claimStatus = "claim_status"
        case disputedAt = "disputed_at"
        case resolvedAt = "resolved_at"
        case purgeAfter = "purge_after"
        case lastMessageAt = "last_message_at"
        case lastMessageBody = "last_message_body"
        case messageCount = "message_count"
        case viewerRole = "viewer_role"
    }
}

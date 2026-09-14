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

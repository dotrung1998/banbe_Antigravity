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

/// A row from `v_disputes` — reused by both the (web-only) admin desk and,
/// on iOS, by VerificationsView so an organizer can keep talking with the
/// guest after escalating (the booking leaves v_pending_verifications the
/// moment it's escalated, so without this there'd be nowhere left on this
/// screen to reach it).
struct OrganizerDispute: Codable, Identifiable, Hashable {
    let bookingId: UUID
    var eventName: String?
    var guestName: String?
    var totalVnd: Int
    var disputeResolvedAt: Date?
    var id: UUID { bookingId }

    enum CodingKeys: String, CodingKey {
        case bookingId = "booking_id"
        case eventName = "event_name"
        case guestName = "guest_name"
        case totalVnd = "total_vnd"
        case disputeResolvedAt = "dispute_resolved_at"
    }
}

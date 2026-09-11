import Foundation

/// Mirrors the `threads` table — one per (event, guest) pair.
struct ChatThread: Codable, Identifiable, Hashable {
    let id: UUID
    var eventId: String
    var guestId: UUID
    var organizerId: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case guestId = "guest_id"
        case organizerId = "organizer_id"
    }
}

/// Mirrors the `messages` table. `kind` follows the `message_kind` enum:
/// "text" (a real chat message) or "system" (e.g. a cancellation notice
/// inserted by the cancel_booking() RPC).
struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var threadId: UUID
    var senderId: UUID?
    var body: String
    var kind: String
    var createdAt: Date
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderId = "sender_id"
        case body
        case kind
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

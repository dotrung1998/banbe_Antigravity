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
    // Task 4 (07-notifications.md, 2026-09-21) — the composer's "+" attach
    // flow; nil for an ordinary text message.
    var attachmentPath: String?
    var attachmentType: String?
    // 2026-09-21 follow-up (07-notifications.md Task 1) — the source
    // image's own intrinsic size, so the bubble can render at its true
    // aspect ratio instead of a fixed square (the white-rail bug). Nil for
    // a pre-migration-066 row or a non-image attachment.
    var attachmentWidth: Int?
    var attachmentHeight: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderId = "sender_id"
        case body
        case kind
        case createdAt = "created_at"
        case readAt = "read_at"
        case attachmentPath = "attachment_path"
        case attachmentType = "attachment_type"
        case attachmentWidth = "attachment_width"
        case attachmentHeight = "attachment_height"
    }
}

/// Mirrors the `stories` table (migration 066, 07-notifications.md Task 3).
struct Story: Codable, Identifiable, Hashable {
    let id: UUID
    var organizerId: String
    var authorId: UUID
    var mediaPath: String
    var mediaType: String
    var width: Int?
    var height: Int?
    var createdAt: Date
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizerId = "organizer_id"
        case authorId = "author_id"
        case mediaPath = "media_path"
        case mediaType = "media_type"
        case width, height
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// A resolved, ready-to-render story with its signed URL and whether this
/// account has already viewed it — built client-side in
/// AppState+Data.swift's loadHomeStories(), not a DB row shape.
struct StoryItem: Identifiable, Hashable {
    let id: UUID
    let mediaPath: String
    var url: URL?
    let width: Int?
    let height: Int?
    let createdAt: Date
    var viewed: Bool
}

/// One host's set of active stories, grouped for the ring/row UI.
struct StoryGroup: Identifiable, Hashable {
    var id: String { organizerId }
    let organizerId: String
    let orgName: String
    var stories: [StoryItem]
    var allViewed: Bool { stories.allSatisfy(\.viewed) }
}

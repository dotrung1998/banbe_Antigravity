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
    // Task 3 (2026-09-22 follow-up, migration 067) — set only by a reply
    // sent from the chat-photo viewer's own composer; nil for every
    // ordinary message.
    var replyToMessageId: UUID?

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
        case replyToMessageId = "reply_to_message_id"
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
    // Task 4 (2026-09-22 follow-up, migration 068) — "media" (default) or
    // "event_share"; eventId is only ever set for the latter.
    var kind: String = "media"
    var eventId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case organizerId = "organizer_id"
        case authorId = "author_id"
        case mediaPath = "media_path"
        case mediaType = "media_type"
        case width, height
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case kind
        case eventId = "event_id"
    }
}

/// A denormalized snapshot of the shared event's own catalogue fields, so
/// an event-share story's card still renders correctly even if the event
/// later changes — built client-side from `EventCatalog.find(_:)`, the
/// same static-catalogue-vs-real-DB duality 11-realtime-map.md documents.
struct StoryEventSnapshot: Equatable, Hashable {
    let eventKey: String
    // BUG 2 fix (2026-09-22 follow-up) — kept as the catalogue's own
    // web-relative path string (NOT resolved to a URL here) specifically
    // so the viewer can render it via `CatalogPhoto` — the SAME robust
    // cover-photo resolver Event Detail/Home/Map already use (its own
    // WebP/downsampling/disk-cache loader), rather than a second, ad-hoc
    // `AsyncImage(url:)` path that has to get URL-resolution right on its
    // own. `img: String` was previously passed straight into
    // `URL(string:)`, which "successfully" parses a scheme-less relative
    // path into a URL with no host — `URLSession` then silently fails to
    // load it, which is what produced the reported blank/white card.
    let img: String
    let name: String
    let when: String
    let location: String
    // BUG 2 (2026-09-22 tenth follow-up) — the event's own coordinates, so
    // the story card can show a live distance via the SAME canonical
    // `haversineKm`/`stripKm` primitive MapExplore/Event Detail already
    // use, instead of showing no distance at all (its previous state).
    let lat: Double?
    let lng: Double?
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
    var kind: String = "media"
    var eventSnapshot: StoryEventSnapshot?
}

/// One host's set of active stories, grouped for the ring/row UI.
struct StoryGroup: Identifiable, Hashable {
    var id: String { organizerId }
    let organizerId: String
    let orgName: String
    var stories: [StoryItem]
    var allViewed: Bool { stories.allSatisfy(\.viewed) }
}

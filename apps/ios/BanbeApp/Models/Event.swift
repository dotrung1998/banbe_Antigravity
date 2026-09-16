import Foundation

/// Mirrors the `events` table. `id` is text (a slug), not a uuid.
/// `status` is only ever queried as 'live' from the client — draft/review/
/// cancelled/ended rows are filtered out by RLS for anyone but the host.
struct Event: Codable, Identifiable, Hashable {
    let id: String
    var organizerId: String?
    var slug: String?
    var name: String
    var category: String
    var description: String
    var area: String
    var lat: Double?
    var lng: Double?
    var startsAt: Date?
    var priceVnd: Int
    var capacity: Int
    var seatsRemaining: Int?
    var palette: String
    var visibility: String   // "public" | "invite"
    var status: String       // "draft" | "review" | "live" | "cancelled" | "ended"
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizerId = "organizer_id"
        case slug
        case name
        case category
        case description
        case area
        case lat
        case lng
        case startsAt = "starts_at"
        case priceVnd = "price_vnd"
        case capacity
        case seatsRemaining = "seats_remaining"
        case palette
        case visibility
        case status
        case createdAt = "created_at"
    }
}

/// A narrower projection of `events`, used only by the map explore screen
/// (11-realtime-map.md) — needs `cat_key` (for the pin glyph) which `Event`
/// above doesn't carry, and skips fields the map has no use for.
struct MapEventRow: Codable, Identifiable, Hashable {
    let id: String
    var catKey: String?
    var name: String
    var area: String
    var lat: Double?
    var lng: Double?
    var startsAt: Date?
    var priceVnd: Int
    var seatsRemaining: Int?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case catKey = "cat_key"
        case name
        case area
        case lat
        case lng
        case startsAt = "starts_at"
        case priceVnd = "price_vnd"
        case seatsRemaining = "seats_remaining"
        case status
    }
}

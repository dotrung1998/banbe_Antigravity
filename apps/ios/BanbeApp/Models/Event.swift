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

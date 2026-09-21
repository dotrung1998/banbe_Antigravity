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

/// MapExploreView's own local state, saved onto `AppState.mapExploreState`
/// right before navigating to Event Detail and restored on return — see
/// that property's own doc comment and `.claude/notes/11-realtime-map.md`
/// (bug 2). Plain data, not `Codable`/persisted anywhere beyond memory —
/// this only needs to survive one screen's round trip within a single app
/// session, not a relaunch.
struct MapExploreState {
    var cameraCenterLat: Double
    var cameraCenterLng: Double
    var cameraSpanLat: Double
    var cameraSpanLng: Double
    /// One of the three literal fractions `MapExploreView.sheetContent`'s
    /// `.presentationDetents` declares (0.12/0.45/0.72) — see that view's
    /// own `sheetFraction`/`detent(for:)` for why a plain Double is used
    /// instead of storing `PresentationDetent` directly (it isn't a type
    /// this struct can hold a stable literal of across platform versions).
    var sheetFraction: Double
    var catFilter: String
    var openNowOnly: Bool
    var sortByDistance: Bool
    var selectedId: String?
    /// Task 7 (2026-09-21 follow-up, 11-realtime-map.md) — true only for
    /// `AppState.openEventOnMap(_:)`'s own from-scratch snapshot, whose
    /// `cameraSpanLat`/`cameraSpanLng` (0.01°, a tight single-pin view) are
    /// meant ONLY for the visual camera, never for the data-loading query
    /// bounds — see `MapExploreView.init(restored:)`'s own use of this flag.
    var singleEventFocus: Bool = false
}

import Foundation
import MapKit

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

/// Address-autocomplete fix pass (2026-09-28) — one candidate from
/// `AppState.searchCreateAddress(_:)` (MKLocalSearch). Mirrors web's own
/// `shapeAddressSuggestion` (GocContext.jsx) field-for-field, so both
/// platforms validate/store the exact same shape server-side (migration
/// 105) despite using different underlying providers (MapKit here,
/// Nominatim there) — "compare iOS and web behavior without creating
/// incompatible provider-specific event records," per this ticket.
struct AddressSuggestion: Identifiable, Equatable {
    let id: String
    /// Street + house number ("12 Nguyễn Văn Đậu"), OR a verified named
    /// venue/POI's own name when no conventional house number exists —
    /// see `init(mapItem:)`'s own comment for exactly how that's decided.
    let addressLine: String
    let district: String
    let city: String
    let postalCode: String
    let isVenue: Bool
    let lat: Double
    let lng: Double
    /// Full human-readable label for the "confirmed" summary UI.
    let label: String

    /// `nil` when MapKit's own result can't resolve to a genuinely
    /// precise point by this app's rules — same heuristic web's
    /// `shapeAddressSuggestion` applies to Nominatim's results:
    /// house-number+street, OR a named place (a real MapKit
    /// `pointOfInterestCategory`, or any non-empty `MKMapItem.name` when
    /// there's no house number to use instead) with a resolvable
    /// district+city. A bare road with no name and no house number, or a
    /// result with no district/city at all, is rejected — never offered
    /// as a selectable suggestion.
    ///
    /// District/city extraction is a best-effort mapping of Apple's own
    /// placemark hierarchy (`locality`/`subLocality`/`administrativeArea`)
    /// onto this app's district/city model — Apple's own geocoding
    /// granularity for Vietnamese addresses was not verified on-device as
    /// part of this pass (no simulator/device run), so this is a
    /// reasonable mapping, not a confirmed-correct one.
    init?(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let houseNumber = (placemark.subThoroughfare ?? "").trimmingCharacters(in: .whitespaces)
        let street = (placemark.thoroughfare ?? "").trimmingCharacters(in: .whitespaces)
        let venueName = (mapItem.name ?? "").trimmingCharacters(in: .whitespaces)
        let district = (placemark.subLocality?.isEmpty == false ? placemark.subLocality : placemark.locality) ?? ""
        let city = (placemark.administrativeArea ?? "").trimmingCharacters(in: .whitespaces)
        let postalCode = (placemark.postalCode ?? "").trimmingCharacters(in: .whitespaces)

        var resolvedAddressLine = ""
        var resolvedIsVenue = false
        if !houseNumber.isEmpty, !street.isEmpty {
            resolvedAddressLine = "\(houseNumber) \(street)"
        } else if !venueName.isEmpty {
            resolvedAddressLine = venueName
            resolvedIsVenue = true
        } else {
            return nil
        }
        guard !district.trimmingCharacters(in: .whitespaces).isEmpty, !city.isEmpty else { return nil }
        guard let coordinate = placemark.location?.coordinate else { return nil }

        self.id = "\(coordinate.latitude),\(coordinate.longitude),\(resolvedAddressLine)"
        self.addressLine = resolvedAddressLine
        self.district = district.trimmingCharacters(in: .whitespaces)
        self.city = city
        self.postalCode = postalCode
        self.isVenue = resolvedIsVenue
        self.lat = coordinate.latitude
        self.lng = coordinate.longitude
        self.label = [resolvedAddressLine, district, city].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

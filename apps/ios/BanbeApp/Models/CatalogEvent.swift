import Foundation

/// One event from the shared catalogue — the same shape `EVENTS` has in
/// src/data/events.js. The `events` table in Postgres holds the rows that
/// bookings/threads/check-ins reference by id, but all the *presentation*
/// detail (copy, photos, galleries, organizer bio, greeting, price and
/// seat labels) lives in that catalogue on the web side, keyed by the same
/// id. Rather than keep a second hand-written copy here,
/// Tools/generate-catalog.mjs emits Resources/events.json straight from it.
struct CatalogEvent: Codable, Identifiable, Hashable {
    var id: String { key }

    let key: String
    let catKey: String
    let cat: String
    let cat2Key: String?
    let catDisplay: String
    let name: String
    let img: String
    let lat: Double
    let lng: Double
    let meta: String
    /// `where` is a Swift keyword, hence the backticks — the JSON key is plain "where".
    let `where`: String
    let when: String
    let price: String
    let seats: String
    let seatsLong: String
    let urgent: Bool
    let desc: String
    let included: String
    let host: String
    let hostShort: String
    let greeting: String
    let gallery: [String]
    let orgGallery: [String]
    let orgName: String
    let orgIg: String
    let orgDesc: String
    let orgSince: Int
    let orgCount: Int
    let orgTrusted: Bool
    let cancelled: Bool
    let cancelledHoursAgo: Int?
    let endedHoursAgo: Int?
    let soldOut: Bool
    let inviteOnly: Bool
    let until: Int?
    let untilLabel: String

    enum CodingKeys: String, CodingKey {
        case key, catKey, cat, cat2Key, catDisplay, name, img, lat, lng, meta
        case `where`
        case when, price, seats, seatsLong, urgent, desc, included, host, hostShort
        case greeting, gallery, orgGallery, orgName, orgIg, orgDesc, orgSince
        case orgCount, orgTrusted, cancelled, cancelledHoursAgo, endedHoursAgo
        case soldOut, inviteOnly, until, untilLabel
    }

    /// Absolute URLs for the photos, which the catalogue stores as the web
    /// app's own root-relative paths ("/photos/x.jpg").
    var imageURL: URL? { Self.photoURL(img) }
    var galleryURLs: [URL] { gallery.compactMap(Self.photoURL) }
    var orgGalleryURLs: [URL] { orgGallery.compactMap(Self.photoURL) }

    static func photoURL(_ path: String) -> URL? {
        URL(string: AppConfig.apiBaseURL + path)
    }

    /// Google Maps directions, same link the web event page opens.
    var mapsURL: URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lng)")
    }

    /// Whether this event is still live in the feed (not cancelled, not over).
    var isOpen: Bool { !cancelled && endedHoursAgo == nil }

    /// Numeric price in đồng, parsed from the display string ("900.000₫").
    var priceVnd: Int {
        let digits = price.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    var isFree: Bool { price.contains("Miễn phí") }
}

/// The catalogue itself, decoded once from the bundled resource.
enum EventCatalog {
    static let all: [CatalogEvent] = {
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([CatalogEvent].self, from: data)
        else {
            assertionFailure("events.json missing or unreadable — run Tools/generate-catalog.mjs")
            return []
        }
        return events
    }()

    /// Mirrors findEvent() on the web side, including its fall back to the
    /// first event so screens always have something to render.
    static func find(_ key: String?) -> CatalogEvent? {
        guard !all.isEmpty else { return nil }
        guard let key else { return all.first }
        return all.first { $0.key == key } ?? all.first
    }
}

// MARK: - Shared label helpers (ports of src/data/events.js)

enum EventLabels {
    /// "Còn 3 ngày" / "Hôm nay" / "Ngày mai"
    static func until(_ days: Int) -> String {
        switch days {
        case 0: return "Hôm nay"
        case 1: return "Ngày mai"
        default: return "Còn \(days) ngày"
        }
    }

    /// "5 giờ trước" / "2 ngày trước"
    static func ago(_ hours: Int) -> String {
        if hours < 24 {
            return hours <= 1 ? "1 giờ trước" : "\(hours) giờ trước"
        }
        let days = hours / 24
        return days == 1 ? "1 ngày trước" : "\(days) ngày trước"
    }

    /// Formats a đồng amount the way the catalogue writes prices.
    static func vnd(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return formatted + "₫"
    }
}

/// Distance in km between the user and an event — the same haversine the
/// web app uses to swap the catalogue's placeholder distance for a real one.
func haversineKm(from coords: Coordinates?, to event: CatalogEvent) -> Double? {
    guard let coords else { return nil }
    let radius = 6371.0
    let dLat = (event.lat - coords.lat) * .pi / 180
    let dLng = (event.lng - coords.lng) * .pi / 180
    let lat1 = coords.lat * .pi / 180
    let lat2 = event.lat * .pi / 180
    let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
    return radius * 2 * atan2(sqrt(h), sqrt(1 - h))
}

struct Coordinates: Equatable {
    let lat: Double
    let lng: Double
}

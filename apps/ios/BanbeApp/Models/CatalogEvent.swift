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
    // 2026-09-25 fix pass — mutable now (like cancelled/endedHoursAgo
    // below), so `applyingLiveStatus` can overlay the REAL starts_at date
    // on top of the catalogue's static one. See Countdown.liveDateOverrides.
    var meta: String
    /// `where` is a Swift keyword, hence the backticks — the JSON key is plain "where".
    var `where`: String
    var when: String
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
    // Mutable (unlike the rest of this struct) so `applyingLiveStatus` can
    // overlay a live read from the real `events` row on top of the static,
    // bundled-at-build-time catalogue — see that method below.
    var cancelled: Bool
    var cancelledHoursAgo: Int?
    var endedHoursAgo: Int?
    let soldOut: Bool
    let inviteOnly: Bool
    var until: Int?
    var untilLabel: String
    /// Bug 3 (15-organizer-checkin.md follow-up): "Add to Calendar" needs a
    /// real, structured start time — resolved once on the web side (the
    /// catalogue's own hardcoded-year date + time), emitted as ISO8601 so
    /// there's nothing left to re-parse here. Mutable since 2026-09-25 —
    /// see `meta`'s own comment just above.
    var startDate: Date?
    let locationLabel: String?

    enum CodingKeys: String, CodingKey {
        case key, catKey, cat, cat2Key, catDisplay, name, img, lat, lng, meta
        case `where`
        case when, price, seats, seatsLong, urgent, desc, included, host, hostShort
        case greeting, gallery, orgGallery, orgName, orgIg, orgDesc, orgSince
        case orgCount, orgTrusted, cancelled, cancelledHoursAgo, endedHoursAgo
        case soldOut, inviteOnly, until, untilLabel, startDate, locationLabel
    }

    /// Absolute URLs for the photos, which the catalogue stores as the web
    /// app's own root-relative paths ("/photos/x.jpg").
    var imageURL: URL? { img.isEmpty ? nil : Self.photoURL(img) }
    var galleryURLs: [URL] { gallery.compactMap(Self.photoURL) }
    var orgGalleryURLs: [URL] { orgGallery.compactMap(Self.photoURL) }

    static func photoURL(_ path: String) -> URL? {
        // Retention roadmap follow-up — a REAL event's photo (CatalogEvent.
        // fromReal) is already a full Supabase Storage public URL, not one
        // of the catalogue's own root-relative bundled paths ("/photos/x.jpg")
        // this prefix was written for. Passing it through unprefixed keeps
        // every existing catalogue caller (which never passes an absolute
        // URL) working exactly as before.
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return URL(string: path) }
        return URL(string: AppConfig.apiBaseURL + path)
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

    /// Overlays a live read of the real `events` row's status on top of this
    /// (static, bundled) event — see `Countdown.liveEventOverrides` for the
    /// full rationale. Returns `self` unchanged when there is no live row to
    /// read yet (or ever, for a client-side-only preview).
    func applyingLiveStatus(_ live: LiveEventStatus?, now: Date = Date()) -> CatalogEvent {
        guard let overrides = Countdown.liveEventOverrides(live, staticEvent: self, now: now) else { return self }
        var copy = self
        copy.cancelled = overrides.cancelled
        copy.cancelledHoursAgo = overrides.cancelledHoursAgo
        copy.endedHoursAgo = overrides.endedHoursAgo
        // 2026-09-25 fix pass — the live DATE, applied regardless of which
        // status branch matched above (a cancelled/ended event still has a
        // real starts_at worth showing correctly). `nil` fields mean
        // `live.startsAt` wasn't set (a row created before that column was
        // wired up) — the catalogue's own static date stays as a fallback.
        let d = overrides.date
        if let startDate = d.startDate { copy.startDate = startDate }
        if let when = d.when { copy.when = when }
        if let until = d.until { copy.until = until }
        if let untilLabel = d.untilLabel { copy.untilLabel = untilLabel }
        if let meta = d.meta { copy.meta = meta }
        if let where_ = d.where_ { copy.where = where_ }
        return copy
    }
}

/// A real, non-catalogue `events` row (retention roadmap follow-up — see
/// AppState.loadRealEventsByID/loadWeekendEvents). Deliberately data-only,
/// no baked-in Vietnamese/English text of its own — CatalogEvent.fromReal
/// below does all the presentation shaping, the same job src/data/events.js
/// does for a static catalogue row, just from real columns instead of
/// hand-written ones.
struct RealEventSummary: Decodable {
    let id: String
    let name: String
    let area: String?
    let catKey: String?
    let catLabel: String?
    let startsAt: Date?
    let priceVnd: Int?
    let capacity: Int?
    let seatsRemaining: Int?
    let status: String
    let cancelledAt: Date?
    let visibility: String
    let organizerId: String?
    // Event review queue (event submission -> review -> publish).
    let description: String?
    let eventDate: String?
    let eventTime: String?
    let submittedAt: Date?
    let reviewedAt: Date?
    let rejectionReason: String?
    var organizerName: String = ""
    var photoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, area
        case catKey = "cat_key"
        case catLabel = "cat_label"
        case startsAt = "starts_at"
        case priceVnd = "price_vnd"
        case capacity
        case seatsRemaining = "seats_remaining"
        case status
        case cancelledAt = "cancelled_at"
        case visibility
        case organizerId = "organizer_id"
        case description
        case eventDate = "event_date"
        case eventTime = "event_time"
        case submittedAt = "submitted_at"
        case reviewedAt = "reviewed_at"
        case rejectionReason = "rejection_reason"
    }

    var soldOut: Bool { (seatsRemaining ?? 1) <= 0 }
}

extension CatalogEvent {
    /// Blocker fix (retention roadmap follow-up) — a REAL, host-created
    /// event (not one of the 20 static demo ones) shaped into the SAME
    /// `CatalogEvent` every view already knows how to render, instead of
    /// `EventCatalog.find`'s own `?? EventCatalog.all[0]` fallback, which
    /// used to substitute a WRONG demo event's name/price/photo/description
    /// in its place. Every FACTUAL field below is real; every DECORATIVE
    /// one this app has no real-data source for yet (long description,
    /// included list, organizer bio/trust stats, extra gallery photos) is
    /// an honest empty/neutral default, never invented.
    static func fromReal(_ real: RealEventSummary, now: Date = Date()) -> CatalogEvent {
        let endedHoursAgo = real.status == "ended" ? Countdown.hoursAgo(real.startsAt, now: now) : nil
        let cancelledHoursAgo = real.status == "cancelled" ? (Countdown.hoursAgo(real.cancelledAt, now: now) ?? 0) : nil
        let priceLabel = (real.priceVnd ?? 0) > 0 ? EventLabels.vnd(real.priceVnd ?? 0) : "Miễn phí"
        return CatalogEvent(
            key: real.id, catKey: real.catKey ?? "all", cat: real.catLabel ?? "", cat2Key: nil, catDisplay: real.catLabel ?? "",
            name: real.name, img: real.photoURL?.absoluteString ?? "", lat: 0, lng: 0,
            meta: [real.catLabel, real.area].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ▪︎ "),
            where: real.area ?? "",
            when: real.startsAt.map(Countdown.whenLabel) ?? "",
            price: priceLabel,
            seats: real.seatsRemaining.map(String.init) ?? "",
            seatsLong: real.soldOut ? "Hết chỗ" : (real.seatsRemaining.map { "\($0) chỗ trống" } ?? ""),
            urgent: (real.seatsRemaining ?? 99) <= 5,
            desc: "", included: "",
            host: real.organizerName, hostShort: real.organizerName, greeting: "",
            gallery: [], orgGallery: [], orgName: real.organizerName, orgIg: "", orgDesc: "",
            orgSince: 0, orgCount: 0, orgTrusted: false,
            cancelled: real.status == "cancelled", cancelledHoursAgo: cancelledHoursAgo, endedHoursAgo: endedHoursAgo,
            soldOut: real.soldOut, inviteOnly: real.visibility == "invite",
            until: nil, untilLabel: "", startDate: real.startsAt,
            locationLabel: real.area
        )
    }

    /// An honest "unavailable" placeholder — the id/key is real (so
    /// isSaved/toggleFavorite still key off the right row) but the row
    /// itself is gone or RLS no longer lets this account see it. Never a
    /// wrong demo event's content standing in for it.
    static func unavailable(key: String, loading: Bool = false, T: (String, String) -> String) -> CatalogEvent {
        CatalogEvent(
            key: key, catKey: "all", cat: "", cat2Key: nil, catDisplay: "",
            // Still loading: an honest blank, same as web's curEvent while
            // its own realEventsById fetch is in flight — never "Event
            // unavailable" for what may well turn out to be a perfectly
            // real, just-not-yet-fetched event.
            name: loading ? "" : T("Sự kiện không khả dụng", "Event unavailable"), img: "", lat: 0, lng: 0,
            meta: "", where: "", when: "", price: "",
            seats: "", seatsLong: "", urgent: false, desc: "", included: "",
            host: "", hostShort: "", greeting: "", gallery: [], orgGallery: [],
            orgName: "", orgIg: "", orgDesc: "", orgSince: 0, orgCount: 0, orgTrusted: false,
            cancelled: false, cancelledHoursAgo: nil, endedHoursAgo: nil,
            soldOut: false, inviteOnly: false, until: nil, untilLabel: "", startDate: nil,
            locationLabel: nil
        )
    }
}

/// The catalogue itself, decoded once from the bundled resource.
enum EventCatalog {
    static let all: [CatalogEvent] = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let url = Bundle.main.url(forResource: "events", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([CatalogEvent].self, from: data)
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
    haversineKm(from: coords, toCoords: Coordinates(lat: event.lat, lng: event.lng))
}

/// BUG 2 (2026-09-22 tenth follow-up) — the actual coordinate-pair
/// primitive, factored out of `haversineKm(from:to:)` above so a caller
/// that only has a bare lat/lng (StoryViewerView's `StoryEventSnapshot`,
/// which isn't a full `CatalogEvent`) can compute the exact same live
/// distance instead of a second, hand-rolled copy of this formula.
func haversineKm(from coords: Coordinates?, toCoords other: Coordinates?) -> Double? {
    guard let coords, let other else { return nil }
    let radius = 6371.0
    let dLat = (other.lat - coords.lat) * .pi / 180
    let dLng = (other.lng - coords.lng) * .pi / 180
    let lat1 = coords.lat * .pi / 180
    let lat2 = other.lat * .pi / 180
    let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
    return radius * 2 * atan2(sqrt(h), sqrt(1 - h))
}

struct Coordinates: Equatable {
    let lat: Double
    let lng: Double
}

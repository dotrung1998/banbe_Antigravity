import Foundation
import CoreLocation

/// Map discovery core (Map redesign, phase 2): ONE committed geography + ONE predicate drive the pins, the list and
/// the count. Web twin: src/lib/mapDiscovery.js; shared cases: tests/fixtures/map-discovery.json. Pure.
///
/// Geography is the map's REFERENCE RECT: the whole map minus the top controls and minus the PEEK sheet. It is the
/// same at every detent, so moving the sheet never changes the results. Camera moves carry a reason; only geographic
/// navigation (user, initial, destination, recenter, nearest, cluster) commits a new area once the camera settles.
/// 'reveal' (selection / sheet follow) and 'restore' never do.
enum MapDiscovery {
    enum Reason: String {
        case user, initial, destination, recenter, nearest, cluster, reveal, restore
        var commits: Bool { self != .reveal && self != .restore }
    }

    struct Bounds: Equatable {
        var north: Double, south: Double, east: Double, west: Double
    }

    struct Rect: Equatable {
        var top: Double, bottom: Double, left: Double, right: Double
    }

    struct Point {
        var lat: Double, lng: Double
    }

    private static let maxLat = 85.05112878

    // MARK: Web Mercator (world fractions: x 0..1 west→east, y 0..1 north→south)
    static func mercX(_ lng: Double) -> Double { (lng + 180) / 360 }
    static func mercY(_ lat: Double) -> Double {
        let s = sin(min(maxLat, max(-maxLat, lat)) * .pi / 180)
        return 0.5 - log((1 + s) / (1 - s)) / (4 * .pi)
    }
    static func latFromMercY(_ y: Double) -> Double { atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi }
    static func lngFromMercX(_ x: Double) -> Double { x * 360 - 180 }

    /// Below the top controls, above the peek sheet.
    static func referenceRect(width: Double, height: Double, topInset: Double, bottomInset: Double) -> Rect {
        let top = min(height, max(0, topInset))
        let bottom = max(top + 1, height - max(0, bottomInset))
        return Rect(top: top, bottom: min(height, bottom), left: 0, right: width)
    }

    /// Bounds of a px rect inside a map whose FULL view shows `full` (longitude linear in x, latitude in Mercator y).
    static func boundsForRect(_ full: Bounds, width: Double, height: Double, rect: Rect) -> Bounds {
        let east = full.east < full.west ? full.east + 360 : full.east
        let x0 = mercX(full.west), x1 = mercX(east)
        let y0 = mercY(full.north), y1 = mercY(full.south)
        func fx(_ px: Double) -> Double { x0 + (x1 - x0) * (px / width) }
        func fy(_ py: Double) -> Double { y0 + (y1 - y0) * (py / height) }
        func wrap(_ lng: Double) -> Double { lng > 180 ? lng - 360 : lng }
        return Bounds(north: latFromMercY(fy(rect.top)), south: latFromMercY(fy(rect.bottom)),
                      east: wrap(lngFromMercX(fx(rect.right))), west: wrap(lngFromMercX(fx(rect.left))))
    }

    /// True when (lat, lng) is inside `b`, including a box across the antimeridian.
    static func inBounds(lat: Double?, lng: Double?, _ b: Bounds?) -> Bool {
        guard let b, let lat, let lng else { return false }
        if lat > b.north || lat < b.south { return false }
        return b.west <= b.east ? (lng >= b.west && lng <= b.east) : (lng >= b.west || lng <= b.east)
    }

    /// Selection survives only while the event is still a result; it is never moved to another event.
    static func selectionAfter(_ selected: String?, results: [String]) -> String? {
        guard let selected else { return nil }
        return results.contains(selected) ? selected : nil
    }

    // MARK: Framing
    static func distanceKm(_ a: Point, _ b: Point) -> Double {
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLng / 2), 2)
        return 2 * 6371 * asin(min(1, sqrt(h)))
    }

    static func boundsOfPoints(_ points: [Point]) -> Bounds? {
        guard !points.isEmpty else { return nil }
        return Bounds(north: points.map(\.lat).max()!, south: points.map(\.lat).min()!,
                      east: points.map(\.lng).max()!, west: points.map(\.lng).min()!)
    }

    /// Indices of points within `radiusKm` of `center` — one city's worth, never the whole inventory.
    static func pointsNear(_ points: [Point], center: Point?, radiusKm: Double = 25) -> [Int] {
        guard let center else { return [] }
        return points.indices.filter { distanceKm(center, points[$0]) <= radiusKm }
    }

    static func nearestPoint(_ points: [Point], from: Point) -> Int? {
        points.indices.min { distanceKm(from, points[$0]) < distanceKm(from, points[$1]) }
    }

    struct Padding { var top = 0.0, bottom = 0.0, left = 0.0, right = 0.0 }

    /// Camera (centre + zoom on a `tileSize` basis) that fits `bounds` into the part of a `width` × `height` map left
    /// free by `padding` (top controls, mid sheet). A single point gets `maxZoom`.
    static func fitCamera(_ bounds: Bounds, width: Double, height: Double, padding: Padding,
                          tileSize: Double = 512, maxZoom: Double = 15, minZoom: Double = 2) -> (center: Point, zoom: Double) {
        let w = max(40, width - padding.left - padding.right)
        let h = max(40, height - padding.top - padding.bottom)
        let x0 = mercX(bounds.west), x1 = mercX(bounds.east < bounds.west ? bounds.east + 360 : bounds.east)
        let y0 = mercY(bounds.north), y1 = mercY(bounds.south)
        let dx = abs(x1 - x0), dy = abs(y1 - y0)
        let zx = dx > 0 ? log2(w / (dx * tileSize)) : .infinity
        let zy = dy > 0 ? log2(h / (dy * tileSize)) : .infinity
        let zoom = min(maxZoom, max(minZoom, min(zx, zy, maxZoom)))
        let world = tileSize * pow(2, zoom)
        let cx = (x0 + x1) / 2 - (padding.left + w / 2 - width / 2) / world
        let cy = (y0 + y1) / 2 - (padding.top + h / 2 - height / 2) / world
        let lng = lngFromMercX(cx)
        return (Point(lat: latFromMercY(cy), lng: lng > 180 ? lng - 360 : lng), zoom)
    }

    /// The full view (`width` × `height`) around a camera from `fitCamera`, as bounds — what a MapKit region needs.
    static func viewBounds(center: Point, zoom: Double, width: Double, height: Double, tileSize: Double = 512) -> Bounds {
        let world = tileSize * pow(2, zoom)
        let cy = mercY(center.lat)
        let halfLng = width / 2 / world * 360
        return Bounds(north: latFromMercY(cy - height / 2 / world), south: latFromMercY(cy + height / 2 / world),
                      east: center.lng + halfLng, west: center.lng - halfLng)
    }
}

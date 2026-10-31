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

    // MARK: Clustering (phase 4; web twin clusterPins/sameSpot/padBounds in src/lib/mapDiscovery.js)
    // Display only: every result is in exactly one group, so markers always add up to the count. A screen-space grid
    // at the camera zoom, then any two groups whose centres are closer than one cell merge (a grid edge must never
    // leave two overlapping markers). At `clusterMaxZoom` and above only the SAME place (≈1 m) groups — a "stack".

    static let clusterCellPx = 64.0
    static let clusterMaxZoom = 16.0

    struct GroupPoint { var id: String; var lat: Double; var lng: Double }
    enum GroupKind: String { case pin, cluster, stack }
    struct Group: Identifiable {
        var kind: GroupKind
        var ids: [String]
        var lat: Double
        var lng: Double
        var bounds: Bounds?
        var id: String { "\(kind.rawValue):\(ids.joined(separator: ","))" }
    }

    private static func spotKey(_ lat: Double, _ lng: Double) -> String { String(format: "%.5f,%.5f", lat, lng) }

    static func clusterPins(_ points: [GroupPoint], zoom: Double, tileSize: Double = 512,
                            cellPx: Double = clusterCellPx, maxZoom: Double = clusterMaxZoom) -> [Group] {
        let world = tileSize * pow(2, zoom)
        var order: [String] = []
        var groups: [String: [GroupPoint]] = [:]
        for p in points {
            let key = zoom >= maxZoom
                ? "s:\(spotKey(p.lat, p.lng))"
                : "g:\(Int(floor(mercX(p.lng) * world / cellPx))):\(Int(floor(mercY(p.lat) * world / cellPx)))"
            if groups[key] == nil { order.append(key); groups[key] = [] }
            groups[key]!.append(p)
        }
        var list = order.map { groups[$0]! }
        if zoom < maxZoom {
            func px(_ pts: [GroupPoint]) -> (Double, Double) {
                (pts.map { mercX($0.lng) }.reduce(0, +) / Double(pts.count) * world,
                 pts.map { mercY($0.lat) }.reduce(0, +) / Double(pts.count) * world)
            }
            var merged = true
            while merged {
                merged = false
                outer: for i in list.indices {
                    for j in list.indices where j > i {
                        let a = px(list[i]), b = px(list[j])
                        if hypot(a.0 - b.0, a.1 - b.1) < cellPx {
                            list[i] += list[j]
                            list.remove(at: j)
                            merged = true
                            break outer
                        }
                    }
                }
            }
        }
        return list.map { pts in
            let sameSpot = Set(pts.map { spotKey($0.lat, $0.lng) }).count == 1
            return Group(kind: pts.count == 1 ? .pin : (sameSpot ? .stack : .cluster), ids: pts.map(\.id),
                         lat: pts.map(\.lat).reduce(0, +) / Double(pts.count),
                         lng: pts.map(\.lng).reduce(0, +) / Double(pts.count),
                         bounds: boundsOfPoints(pts.map { Point(lat: $0.lat, lng: $0.lng) }))
        }
    }

    /// Indices in `list` at the same place as (lat, lng) — the card's stack switcher.
    static func sameSpotIDs(_ list: [GroupPoint], lat: Double, lng: Double) -> [String] {
        let k = spotKey(lat, lng)
        return list.filter { spotKey($0.lat, $0.lng) == k }.map(\.id)
    }

    /// `b` grown by `factor` around its centre (bounded-fetch margin when the full set is too large to load).
    static func padBounds(_ b: Bounds, factor: Double = 1.5) -> Bounds {
        let dLat = (b.north - b.south) * (factor - 1) / 2, dLng = (b.east - b.west) * (factor - 1) / 2
        return Bounds(north: min(85, b.north + dLat), south: max(-85, b.south - dLat), east: b.east + dLng, west: b.west - dLng)
    }
}

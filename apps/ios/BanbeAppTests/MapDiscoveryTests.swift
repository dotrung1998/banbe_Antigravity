import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/mapDiscovery.test.mjs through the shared tests/fixtures/map-discovery.json (Map redesign
/// phase 2): one committed area drives pins, list and count.
final class MapDiscoveryTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/map-discovery.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func d(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
    private func bounds(_ any: Any?) throws -> MapDiscovery.Bounds {
        let b = try XCTUnwrap(any as? [String: Any])
        return MapDiscovery.Bounds(north: try XCTUnwrap(d(b["north"])), south: try XCTUnwrap(d(b["south"])),
                                   east: try XCTUnwrap(d(b["east"])), west: try XCTUnwrap(d(b["west"])))
    }

    func testOnlyGeographicNavigationCommits() throws {
        for c in try XCTUnwrap(fixture()["reasons"] as? [[String: Any]]) {
            let reason = try XCTUnwrap(MapDiscovery.Reason(rawValue: try XCTUnwrap(c["reason"] as? String)))
            XCTAssertEqual(reason.commits, c["commits"] as? Bool, reason.rawValue)
        }
    }

    func testReferenceRect() throws {
        for c in try XCTUnwrap(fixture()["referenceRect"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Any]), e = try XCTUnwrap(c["expect"] as? [String: Any])
            let got = MapDiscovery.referenceRect(width: d(i["width"])!, height: d(i["height"])!, topInset: d(i["topInset"])!, bottomInset: d(i["bottomInset"])!)
            XCTAssertEqual(got, MapDiscovery.Rect(top: d(e["top"])!, bottom: d(e["bottom"])!, left: d(e["left"])!, right: d(e["right"])!))
        }
    }

    func testBoundsForRectFollowsMercator() throws {
        for c in try XCTUnwrap(fixture()["boundsForRect"] as? [[String: Any]]) {
            let size = try XCTUnwrap(c["size"] as? [String: Any]), r = try XCTUnwrap(c["rect"] as? [String: Any])
            let got = MapDiscovery.boundsForRect(try bounds(c["full"]), width: d(size["width"])!, height: d(size["height"])!,
                                                 rect: .init(top: d(r["top"])!, bottom: d(r["bottom"])!, left: d(r["left"])!, right: d(r["right"])!))
            let e = try bounds(c["expect"])
            XCTAssertEqual(got.north, e.north, accuracy: 1e-6); XCTAssertEqual(got.south, e.south, accuracy: 1e-6)
            XCTAssertEqual(got.east, e.east, accuracy: 1e-6); XCTAssertEqual(got.west, e.west, accuracy: 1e-6)
        }
    }

    func testInBoundsIncludingTheAntimeridian() throws {
        for c in try XCTUnwrap(fixture()["inBounds"] as? [[String: Any]]) {
            let ev = try XCTUnwrap(c["ev"] as? [String: Any])
            XCTAssertEqual(MapDiscovery.inBounds(lat: d(ev["lat"]), lng: d(ev["lng"]), try bounds(c["b"])), c["expect"] as? Bool, "\(c["name"] ?? "")")
        }
    }

    func testResultsComeOnlyFromTheCommittedArea() throws {
        for c in try XCTUnwrap(fixture()["mapResults"] as? [[String: Any]]) {
            let evs = try XCTUnwrap(c["events"] as? [[String: Any]])
            let b = c["bounds"] is NSNull ? nil : try bounds(c["bounds"])
            let got = evs.filter { MapDiscovery.inBounds(lat: d($0["lat"]), lng: d($0["lng"]), b) }.compactMap { $0["id"] as? String }
            XCTAssertEqual(got, c["expect"] as? [String], "\(c["name"] ?? "")")
        }
    }

    func testSelectionIsKeptOnlyWhileAResult() throws {
        for c in try XCTUnwrap(fixture()["selectionAfter"] as? [[String: Any]]) {
            XCTAssertEqual(MapDiscovery.selectionAfter(c["selected"] as? String, results: c["results"] as? [String] ?? []),
                           c["expect"] as? String, "\(c["name"] ?? "")")
        }
    }

    func testFirstOpenClusterStaysInOneCity() throws {
        for c in try XCTUnwrap(fixture()["pointsNear"] as? [[String: Any]]) {
            let pts = try XCTUnwrap(c["points"] as? [[String: Any]])
            let center = try XCTUnwrap(c["center"] as? [String: Any])
            let idx = MapDiscovery.pointsNear(pts.map { .init(lat: d($0["lat"])!, lng: d($0["lng"])!) },
                                              center: .init(lat: d(center["lat"])!, lng: d(center["lng"])!), radiusKm: d(c["radiusKm"])!)
            XCTAssertEqual(idx.compactMap { pts[$0]["id"] as? String }, c["expect"] as? [String])
        }
    }

    func testFitCameraMatchesTheSharedNumbers() throws {
        for c in try XCTUnwrap(fixture()["fitCamera"] as? [[String: Any]]) {
            let size = try XCTUnwrap(c["size"] as? [String: Any]), p = try XCTUnwrap(c["padding"] as? [String: Any])
            let e = try XCTUnwrap(c["expect"] as? [String: Any])
            let got = MapDiscovery.fitCamera(try bounds(c["bounds"]), width: d(size["width"])!, height: d(size["height"])!,
                                             padding: .init(top: d(p["top"])!, bottom: d(p["bottom"])!, left: d(p["left"])!, right: d(p["right"])!),
                                             tileSize: d(c["tileSize"])!, maxZoom: d(c["maxZoom"])!)
            XCTAssertEqual(got.center.lat, d(e["lat"])!, accuracy: 1e-6, "\(c["name"] ?? "")")
            XCTAssertEqual(got.center.lng, d(e["lng"])!, accuracy: 1e-6)
            XCTAssertEqual(got.zoom, d(e["zoom"])!, accuracy: 1e-6)
        }
    }
}

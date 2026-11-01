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

    func testClustersReduceMarkersNeverResults() throws {
        for c in try XCTUnwrap(fixture()["clusterPins"] as? [[String: Any]]) {
            let pts = try XCTUnwrap(c["points"] as? [[String: Any]]).map {
                MapDiscovery.GroupPoint(id: $0["id"] as! String, lat: d($0["lat"])!, lng: d($0["lng"])!)
            }
            let got = MapDiscovery.clusterPins(pts, zoom: d(c["zoom"])!)
            let expect = try XCTUnwrap(c["expect"] as? [[Any]])
            XCTAssertEqual(got.map(\.kind.rawValue), expect.map { $0[0] as! String }, "\(c["name"] ?? "")")
            XCTAssertEqual(got.map(\.ids), expect.map { $0[1] as! [String] }, "\(c["name"] ?? "")")
            XCTAssertEqual(got.reduce(0) { $0 + $1.ids.count }, pts.count, "every result counted once")
        }
    }

    func testPadBounds() throws {
        for c in try XCTUnwrap(fixture()["padBounds"] as? [[String: Any]]) {
            XCTAssertEqual(MapDiscovery.padBounds(try bounds(c["b"]), factor: d(c["factor"])!), try bounds(c["expect"]))
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

    // MARK: Map v5 (note 73): cities + the active filter summary (shared with tests/unit/mapDiscovery.test.mjs)

    private func repoCities() throws -> [MapDiscovery.City] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return try MapDiscovery.decodeCities(Data(contentsOf: url.appendingPathComponent("src/data/cities.json")))
    }

    private func place(_ ev: [String: Any]) -> MapDiscovery.Place {
        MapDiscovery.Place(city: ev["city"] as? String, stateProvince: ev["stateProvince"] as? String,
                           countryCode: ev["countryCode"] as? String, lat: d(ev["lat"]), lng: d(ev["lng"]))
    }

    func testCitiesJSONIsSaneAndBundled() throws {
        let cities = try repoCities()
        XCTAssertFalse(cities.isEmpty)
        var ids = Set<String>()
        for c in cities {
            XCTAssertFalse(ids.contains(c.id), c.id); ids.insert(c.id)
            XCTAssertTrue(c.bounds.north > c.bounds.south && c.bounds.east > c.bounds.west, c.id)
            XCTAssertTrue(MapDiscovery.inBounds(lat: c.center.lat, lng: c.center.lng, c.bounds), "\(c.id) centre")
            XCTAssertTrue(["VN", "US"].contains(c.country), c.id)
        }
        XCTAssertEqual(MapDiscovery.cities.map(\.id), cities.map(\.id), "the app bundles the same file (run xcodegen generate)")
    }

    func testFoldText() {
        XCTAssertEqual(MapDiscovery.foldText("  Đà Lạt!! "), "da lat")
        XCTAssertEqual(MapDiscovery.foldText("TP. Hồ Chí Minh"), "tp ho chi minh")
        XCTAssertEqual(MapDiscovery.foldText(nil), "")
    }

    func testCityForColumnsFirstThenSmallestBox() throws {
        let cities = try repoCities()
        for c in try XCTUnwrap(fixture()["cityFor"] as? [[String: Any]]) {
            let ev = try XCTUnwrap(c["ev"] as? [String: Any])
            XCTAssertEqual(MapDiscovery.cityFor(place(ev), cities: cities), c["expect"] as? String, "\(c["name"] ?? "")")
        }
    }

    func testSearchCitiesAccentFreeWordPrefix() throws {
        let cities = try repoCities()
        for c in try XCTUnwrap(fixture()["searchCities"] as? [[String: Any]]) {
            let counts = (c["counts"] as? [String: Any] ?? [:]).mapValues { ($0 as? NSNumber)?.intValue ?? 0 }
            let got = MapDiscovery.searchCities(try XCTUnwrap(c["query"] as? String), cities: cities, counts: counts)
            let expect = try XCTUnwrap(c["expect"] as? [[String: Any]]).map {
                MapDiscovery.CityHit(id: $0["id"] as! String, count: ($0["count"] as! NSNumber).intValue)
            }
            XCTAssertEqual(got, expect, "\(c["name"] ?? "")")
        }
    }

    func testCityGroupsNeverLoseAResult() throws {
        let cities = try repoCities()
        for c in try XCTUnwrap(fixture()["cityGroups"] as? [[String: Any]]) {
            let pts = try XCTUnwrap(c["points"] as? [[String: Any]]).map {
                MapDiscovery.GroupPoint(id: $0["id"] as! String, lat: d($0["lat"])!, lng: d($0["lng"])!)
            }
            let zoom = try XCTUnwrap(d(c["zoom"]))
            let got = MapDiscovery.cityGroups(pts, zoom: zoom, cityOf: {
                MapDiscovery.cityFor(.init(lat: $0.lat, lng: $0.lng), cities: cities)
            }, cities: cities)
            let name = "\(c["name"] ?? "")"
            XCTAssertEqual(got.reduce(0) { $0 + $1.ids.count }, pts.count, "\(name): count")
            if c["expect"] as? String == "clusterPins" {
                let plain = MapDiscovery.clusterPins(pts, zoom: zoom)
                XCTAssertEqual(got.map(\.id), plain.map(\.id), name)
                XCTAssertEqual(got.map(\.lat), plain.map(\.lat), name)
                XCTAssertEqual(got.map(\.lng), plain.map(\.lng), name)
            } else {
                let expect = try XCTUnwrap(c["expect"] as? [[String: Any]])
                XCTAssertEqual(got.map(\.kind.rawValue), expect.map { $0["kind"] as! String }, name)
                XCTAssertEqual(got.map(\.cityId), expect.map { $0["cityId"] as? String }, name)
                XCTAssertEqual(got.map(\.ids), expect.map { $0["ids"] as! [String] }, name)
                for g in got where g.kind == .city {
                    let city = try XCTUnwrap(cities.first { $0.id == g.cityId })
                    XCTAssertEqual(g.lat, city.center.lat); XCTAssertEqual(g.lng, city.center.lng)
                    XCTAssertEqual(g.bounds, city.bounds)
                }
            }
        }
    }

    func testActiveFilterSummaryTokensAndCount() throws {
        for c in try XCTUnwrap(fixture()["activeFilterSummary"] as? [[String: Any]]) {
            let f = c["filters"] as? [String: Any] ?? [:], o = c["opts"] as? [String: Any] ?? [:]
            var filters = HomeDiscovery.Filters()
            if let v = f["date"] as? String { filters.date = v }
            if let v = f["cats"] as? [String] { filters.cats = v }
            if let v = f["typeFilters"] as? [String] { filters.typeFilters = v }
            if let v = f["seatsLeft"] as? Bool { filters.seatsLeft = v }
            if let v = f["almostFull"] as? Bool { filters.almostFull = v }
            if let v = f["free"] as? Bool { filters.free = v }
            filters.priceMin = (f["priceMin"] as? NSNumber)?.intValue
            filters.priceMax = (f["priceMax"] as? NSNumber)?.intValue
            if let v = f["priceCurrency"] as? String { filters.priceCurrency = v }
            let got = MapDiscovery.activeFilterSummary(filters, forYou: o["forYou"] as? Bool ?? false, query: o["query"] as? String ?? "")
            let e = try XCTUnwrap(c["expect"] as? [String: Any])
            let expect: [MapDiscovery.SummaryToken] = try XCTUnwrap(e["tokens"] as? [[String: Any]]).map { t in
                switch t["kind"] as! String {
                case "query": return .query(t["text"] as! String)
                case "cat": return .cat(t["key"] as! String)
                case "forYou": return .forYou
                case "date": return .date(t["key"] as! String)
                case "free": return .free
                case "price": return .price(min: (t["min"] as? NSNumber)?.intValue, max: (t["max"] as? NSNumber)?.intValue,
                                            currency: t["currency"] as! String)
                case "seatsLeft": return .seatsLeft
                case "almostFull": return .almostFull
                default: return .types((t["n"] as! NSNumber).intValue)
                }
            }
            XCTAssertEqual(got.tokens, expect, "\(c["name"] ?? "")")
            XCTAssertEqual(got.count, (e["count"] as? NSNumber)?.intValue, "\(c["name"] ?? "")")
        }
    }
}

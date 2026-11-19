import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/unifiedDiscovery.test.mjs (note 99). Shared cases come from tests/fixtures/unified-discovery.json
/// when it exists; the inline cases below pin the same rules either way.
final class UnifiedDiscoveryTests: XCTestCase {
    private func fixture(_ name: String) throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let file = url.appendingPathComponent("tests/fixtures/\(name)")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("\(name) not present yet") }
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let keys = ["food", "music", "art", "stage", "market", "workshop", "fashion"]

    func testTabDateMapping() {
        XCTAssertEqual(UnifiedDiscovery.DATE_FOR_TAB, ["foryou": "any", "tonight": "today", "weekend": "weekend"])
        XCTAssertEqual(UnifiedDiscovery.tabForDate("today"), "tonight")
        XCTAssertEqual(UnifiedDiscovery.tabForDate("weekend"), "weekend")
        for d in ["any", "tomorrow", "week", "on:2026-11-20", ""] { XCTAssertEqual(UnifiedDiscovery.tabForDate(d), "foryou", d) }
        for t in HomeHeroTab.allCases {
            XCTAssertEqual(UnifiedDiscovery.heroTab(forDate: UnifiedDiscovery.dateForTab(t)), t)
        }
    }

    func testTopTypesBusiestFirstTiesInCatalogueOrder() {
        let counts = ["food": 2, "music": 5, "art": 2, "market": 7, "fashion": 1]
        XCTAssertEqual(UnifiedDiscovery.topTypes(counts, keys: keys), ["market", "music", "food", "art", "fashion"])
        // Empty types still fill the tiles, in catalogue order.
        XCTAssertEqual(UnifiedDiscovery.topTypes(["workshop": 1], keys: keys), ["workshop", "food", "music", "art", "stage"])
        XCTAssertEqual(UnifiedDiscovery.topTypes([:], keys: keys, n: 2), ["food", "music"])
    }

    func testPickedTile() {
        let tiles = ["market", "music", "food", "art", "fashion"]
        XCTAssertNil(UnifiedDiscovery.pickedTileType(nil, tiles: tiles))
        XCTAssertNil(UnifiedDiscovery.pickedTileType("all", tiles: tiles))
        XCTAssertNil(UnifiedDiscovery.pickedTileType("music", tiles: tiles))
        XCTAssertEqual(UnifiedDiscovery.pickedTileType("workshop", tiles: tiles), "workshop")
    }

    func testTypeSheetOrder() {
        let counts = ["food": 2, "music": 5, "art": 2]
        XCTAssertEqual(UnifiedDiscovery.typeSheetOrder(counts, keys: keys),
                       ["music", "food", "art", "stage", "market", "workshop", "fashion"])
        let names = ["food": "Ăn tối", "music": "Âm nhạc", "art": "Nghệ thuật", "stage": "Sân khấu",
                     "market": "Chợ đêm", "workshop": "Workshop", "fashion": "Thời trang"]
        XCTAssertEqual(UnifiedDiscovery.typeSheetOrder(counts, keys: keys, nameOf: { names[$0] ?? $0 }, query: "am"),
                       ["music"])
        XCTAssertEqual(UnifiedDiscovery.typeSheetOrder(counts, keys: keys, nameOf: { names[$0] ?? $0 }, query: " CHO "),
                       ["market"])
    }

    func testAreaGlyphs() {
        let r = UnifiedDiscovery.areaGlyphs(["art": 1, "food": 3, "music": 1, "stage": 2, "fashion": 1, "market": 0], keys: keys)
        XCTAssertEqual(r.shown, ["food", "stage", "music", "art"])
        XCTAssertEqual(r.more, 1)
        let few = UnifiedDiscovery.areaGlyphs(["music": 1], keys: keys)
        XCTAssertEqual(few.shown, ["music"]); XCTAssertEqual(few.more, 0)
        // Unknown keys sort after the catalogue.
        XCTAssertEqual(UnifiedDiscovery.areaGlyphs(["zzz": 1, "food": 1], keys: keys).shown, ["food", "zzz"])
    }

    func testOwnedFilterCountIgnoresTimeAndArea() {
        var f = HomeDiscovery.Filters.default
        f.date = "today"
        XCTAssertEqual(UnifiedDiscovery.ownedFilterCount(f, sort: "soonest"), 0)
        f.cats = ["food"]; f.priceMax = 400_000; f.seatsLeft = true; f.almostFull = true; f.typeFilters = ["a", "b"]
        XCTAssertEqual(UnifiedDiscovery.ownedFilterCount(f, sort: "price"), 6)
        XCTAssertEqual(UnifiedDiscovery.ownedFilterCount(f, sort: nil), 5)
    }

    func testMapDayMapping() {
        XCTAssertEqual(UnifiedDiscovery.dateForMapDay("today"), "today")
        XCTAssertEqual(UnifiedDiscovery.dateForMapDay("tomorrow"), "tomorrow")
        XCTAssertEqual(UnifiedDiscovery.dateForMapDay("weekend"), "weekend")
        XCTAssertEqual(UnifiedDiscovery.dateForMapDay("nextWeek"), "week")
        XCTAssertEqual(UnifiedDiscovery.dateForMapDay("all"), "any")
        for d in ["today", "tomorrow", "weekend", "week", "any"] {
            XCTAssertEqual(UnifiedDiscovery.dateForMapDay(UnifiedDiscovery.mapDayForDate(d)), d)
        }
        XCTAssertEqual(UnifiedDiscovery.mapDayForDate("on:2026-11-20"), "all")
    }

    // MARK: Shared fixture (tests/fixtures/unified-discovery.json)

    func testSharedFixture() throws {
        let root = try fixture("unified-discovery.json")
        let fkeys = root["keys"] as? [String] ?? keys
        for c in root["tabForDate"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(UnifiedDiscovery.tabForDate(c["date"] as? String ?? ""), c["tab"] as? String)
        }
        if let d = root["dateForTab"] as? [String: String] {
            XCTAssertEqual(d, UnifiedDiscovery.DATE_FOR_TAB)
        }
        for c in root["topTypes"] as? [[String: Any]] ?? [] {
            let counts = c["counts"] as? [String: Int] ?? [:]
            let n = c["n"] as? Int ?? UnifiedDiscovery.TILE_TYPES
            XCTAssertEqual(UnifiedDiscovery.topTypes(counts, keys: c["keys"] as? [String] ?? fkeys, n: n), c["expect"] as? [String])
        }
        for c in root["pickedTileType"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(UnifiedDiscovery.pickedTileType(c["selected"] as? String, tiles: c["tiles"] as? [String] ?? []),
                           c["expect"] as? String)
        }
        for c in root["typeSheetOrder"] as? [[String: Any]] ?? [] {
            let names = c["names"] as? [String: String] ?? [:]
            XCTAssertEqual(UnifiedDiscovery.typeSheetOrder(c["counts"] as? [String: Int] ?? [:], keys: c["keys"] as? [String] ?? fkeys,
                                                           nameOf: { names[$0] ?? $0 }, query: c["query"] as? String ?? ""),
                           c["expect"] as? [String])
        }
        for c in root["areaGlyphs"] as? [[String: Any]] ?? [] {
            let r = UnifiedDiscovery.areaGlyphs(c["cats"] as? [String: Int] ?? [:], keys: c["keys"] as? [String] ?? fkeys,
                                                max: c["max"] as? Int ?? 4)
            XCTAssertEqual(r.shown, c["shown"] as? [String])
            XCTAssertEqual(r.more, c["more"] as? Int)
        }
        for c in root["ownedFilterCount"] as? [[String: Any]] ?? [] {
            let j = c["filters"] as? [String: Any] ?? [:]
            var f = HomeDiscovery.Filters.default
            f.date = j["date"] as? String ?? "any"
            f.cats = j["cats"] as? [String] ?? []
            f.free = j["free"] as? Bool ?? false
            f.priceMin = j["priceMin"] as? Int
            f.priceMax = j["priceMax"] as? Int
            f.seatsLeft = j["seatsLeft"] as? Bool ?? false
            f.almostFull = j["almostFull"] as? Bool ?? false
            f.typeFilters = j["typeFilters"] as? [String] ?? []
            XCTAssertEqual(UnifiedDiscovery.ownedFilterCount(f, sort: c["sort"] as? String), c["expect"] as? Int)
        }
    }

    // MARK: Near you (bug 2026-11-19: web and iOS Home listed different events), shared with tests/unit/unifiedDiscovery.test.mjs

    func testNearYouSharedFixture() throws {
        let root = try fixture("unified-discovery.json")
        let ny = try XCTUnwrap(root["nearYou"] as? [String: Any])
        let iso = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? { (v as? String).flatMap { iso.date(from: $0) } }
        let now = try XCTUnwrap(date(ny["now"]))
        let items: [HomeDiscovery.Item] = (ny["items"] as? [[String: Any]] ?? []).map { j in
            HomeDiscovery.Item(key: j["key"] as? String ?? "", startsAt: date(j["startsAt"]), priceVnd: nil,
                               catKeys: j["catKeys"] as? [String] ?? [], cancelled: j["cancelled"] as? Bool ?? false,
                               endsAt: date(j["endsAt"]))
        }
        XCTAssertEqual(items.count, 11)
        let byKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for (k, want) in ny["open"] as? [String: Bool] ?? [:] {
            XCTAssertEqual(UnifiedDiscovery.isOpenItem(try XCTUnwrap(byKey[k]), now: now), want, k)
        }
        let cases = ny["cases"] as? [[String: Any]] ?? []
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let j = c["filters"] as? [String: Any] ?? [:]
            var f = HomeDiscovery.Filters.default
            f.date = j["date"] as? String ?? "any"
            f.cats = j["cats"] as? [String] ?? []
            let r = UnifiedDiscovery.nearYou(items, filters: f, sort: c["sort"] as? String, now: now,
                                             tabOwnsTime: c["tabOwnsTime"] as? Bool ?? false)
            XCTAssertEqual(r.rows.map(\.key), c["rows"] as? [String], name)
            XCTAssertEqual(r.total, c["total"] as? Int, name)
        }
    }

    /// The "is it over" moment matches web's eventEndsAt: the host's end on the venue clock (past midnight = next day),
    /// else 12 h after the start.
    func testEventEndsAt() {
        let vn = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        let start = ISO8601DateFormatter().date(from: "2026-11-19T12:00:00Z")!   // 19:00 in Vietnam
        XCTAssertEqual(EventEnd.endsAt(start: start, timeZone: vn, endTime: "21:00", endOpen: false),
                       ISO8601DateFormatter().date(from: "2026-11-19T14:00:00Z"))
        XCTAssertEqual(EventEnd.endsAt(start: start, timeZone: vn, endTime: "01:00", endOpen: false),
                       ISO8601DateFormatter().date(from: "2026-11-19T18:00:00Z"))
        XCTAssertEqual(EventEnd.endsAt(start: start, timeZone: vn, endTime: nil, endOpen: true), start.addingTimeInterval(12 * 3600))
        XCTAssertNil(EventEnd.endsAt(start: nil, timeZone: vn, endTime: "21:00", endOpen: false))
        XCTAssertTrue(EventEnd.isOver(start: start, timeZone: vn, endTime: "21:00", endOpen: false,
                                      now: ISO8601DateFormatter().date(from: "2026-11-19T15:05:00Z")!))
    }
}

import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/eventTypes.test.mjs through the shared tests/fixtures/event-types.json.
final class EventTypesTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/event-types.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func group(_ name: String) throws -> [[String: Any]] {
        try XCTUnwrap(try fixture()[name] as? [[String: Any]])
    }
    private func details(_ any: Any?) -> EventDetails { EventTypes.details(fromJSON: any) }

    func testKeysAreTheServerIdsInOrder() throws {
        let keys = try XCTUnwrap(try fixture()["keys"] as? [String])
        XCTAssertEqual(EventTypes.keys, keys)
        XCTAssertEqual(EventPrefTaxonomy.interests.map(\.id), keys)
        for k in keys { XCTAssertNotNil(EventTypes.emoji[k], k) }
    }

    func testShaped() throws {
        let shaped = try XCTUnwrap(try fixture()["shaped"] as? [String: Bool])
        for (k, v) in shaped { XCTAssertEqual(EventTypes.isShaped(EventTypes.profile(k)), v, k) }
    }

    func testRequiredFieldsAreKnownCreateFields() {
        for k in EventTypes.keys {
            for f in EventTypes.requiredFields(EventTypes.profile(k)) {
                XCTAssertTrue(CreateProgress.fieldOrder.contains(f), "\(k): \(f)")
            }
        }
    }

    func testCleanDetails() throws {
        for c in try group("cleanDetails") {
            let name = c["case"] as? String ?? "?"
            let got = EventTypes.json(EventTypes.clean(EventTypes.profile(c["type"] as? String), details(c["raw"])))
            XCTAssertEqual(NSDictionary(dictionary: got), NSDictionary(dictionary: c["expect"] as? [String: Any] ?? [:]), name)
        }
    }

    func testDroppedDetailTypes() throws {
        for c in try group("droppedDetailTypes") {
            let raw = c["draft"] as? [String: Any] ?? [:]
            let draft = raw.mapValues { details($0) }
            XCTAssertEqual(EventTypes.droppedDetailTypes(primary: c["primary"] as? String ?? "", draft: draft),
                           c["expect"] as? [String], c["case"] as? String ?? "?")
        }
    }

    func testDetailFacts() throws {
        for c in try group("detailFacts") {
            let got = EventTypes.detailFacts(EventTypes.profile(c["type"] as? String), details(c["details"]), lang: c["lang"] as? String ?? "en")
            let want = (c["expect"] as? [[String: String]] ?? []).map { EventTypes.Fact(id: $0["id"]!, label: $0["label"]!, value: $0["value"]!) }
            XCTAssertEqual(got, want, c["case"] as? String ?? "?")
        }
    }

    func testCardLine() throws {
        for c in try group("cardLine") {
            let got = EventTypes.cardLine(EventTypes.profile(c["type"] as? String), capacity: c["capacity"] as? Int ?? 0,
                                          details: details(c["details"]), lang: c["lang"] as? String ?? "en")
            XCTAssertEqual(got, c["expect"] as? String, c["case"] as? String ?? "?")
        }
    }

    func testHomeFilters() throws {
        for c in try group("homeFilter") {
            let p = EventTypes.profile(c["type"] as? String)
            let f = try XCTUnwrap(EventTypes.homeFilters(p).first { $0.id == c["filter"] as? String })
            XCTAssertEqual(EventTypes.matches(f, details(c["details"])), c["expect"] as? Bool, c["case"] as? String ?? "?")
        }
    }

    func testKeywordSuggestions() throws {
        for c in try group("keywordSuggestions") {
            let got = EventTypes.keywordSuggestions(EventTypes.profile(c["type"] as? String), lang: c["lang"] as? String ?? "en",
                                                    area: c["area"] as? String ?? "", benchmark: c["benchmark"] as? [String] ?? [],
                                                    typed: c["typed"] as? [String] ?? [], dismissed: c["dismissed"] as? [String] ?? [])
            XCTAssertEqual(got, c["expect"] as? [String], c["case"] as? String ?? "?")
        }
    }

    func testSearchAliases() throws {
        for c in try group("search") {
            let aliases = SearchMatch.categoryAliases[c["catKey"] as? String ?? ""] ?? []
            let doc = SearchMatch.normalize((["Untitled", c["catKey"] as? String ?? ""] + aliases).joined(separator: " "))
            XCTAssertEqual(SearchMatch.matches(doc: doc, query: c["query"] as? String ?? ""), c["expect"] as? Bool, c["case"] as? String ?? "?")
        }
    }

    // MARK: Home with type chips (same vectors as tests/unit/eventTypes.test.mjs)

    private func discovery() throws -> (items: [HomeDiscovery.Item], root: [String: Any]) {
        let d = try XCTUnwrap(try fixture()["discovery"] as? [String: Any])
        let items = try XCTUnwrap(d["items"] as? [[String: Any]]).map {
            HomeDiscovery.Item(key: $0["key"] as? String ?? "", startsAt: nil, priceVnd: nil,
                               catKeys: $0["catKeys"] as? [String] ?? [], details: details($0["details"]))
        }
        return (items, d)
    }
    private func filters(_ any: Any?) -> HomeDiscovery.Filters {
        let o = any as? [String: Any] ?? [:]
        var f = HomeDiscovery.Filters()
        f.cats = o["cats"] as? [String] ?? []
        f.typeFilters = o["typeFilters"] as? [String] ?? []
        return f
    }

    func testDiscoveryTypeFilters() throws {
        let (items, d) = try discovery()
        let now = Date(timeIntervalSince1970: 0)
        for c in try XCTUnwrap(d["cases"] as? [[String: Any]]) {
            let f = filters(c["filters"])
            XCTAssertEqual(HomeDiscovery.apply(items, f, now: now).map(\.key), c["expect"] as? [String], c["case"] as? String ?? "?")
            XCTAssertEqual(HomeDiscovery.activeFilterCount(f), c["badge"] as? Int, c["case"] as? String ?? "?")
        }
        let counts = try XCTUnwrap(d["counts"] as? [String: Any])
        XCTAssertEqual(HomeDiscovery.optionCounts(items, filters(counts["filters"]), .typeFilters,
                                                  options: counts["options"] as? [String] ?? [], now: now),
                       counts["expect"] as? [String: Int])
        let relax = try XCTUnwrap(d["relax"] as? [String: Any])
        let hint = try XCTUnwrap(HomeDiscovery.relaxationHints(items, filters(relax["filters"]), now: now).first)
        let want = try XCTUnwrap(relax["expect"] as? [String: Any])
        XCTAssertEqual(hint.id, want["id"] as? String)
        XCTAssertEqual(hint.gain, want["gain"] as? Int)
    }
}

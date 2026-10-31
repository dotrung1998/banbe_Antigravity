import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/eventDetailPresentation.test.mjs through the shared tests/fixtures/event-detail-presentation.json
/// (notes 68, 70) — change both together.
final class EventDetailPresentationTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/event-detail-presentation.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSeatStatusMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["seatStatus"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let i = try XCTUnwrap(c["in"] as? [String: Any]), o = try XCTUnwrap(c["out"] as? [String: Any])
            let s = EventDetailPresentation.seatStatus(capacity: i["capacity"] as? Int, remaining: i["remaining"] as? Int,
                                                       soldOut: i["soldOut"] as? Bool ?? false, going: i["going"] as? Bool ?? false)
            XCTAssertEqual(s.kind.rawValue, o["kind"] as? String, name)
            XCTAssertEqual(s.left, o["left"] as? Int, name)
            if let r = o["ratio"] as? Double { XCTAssertEqual(try XCTUnwrap(s.ratio, name), r, accuracy: 0.0001, name) } else { XCTAssertNil(s.ratio, name) }
        }
    }

    func testZeroLeftIsSoldOutWithNoBar() {
        // Regression: 0 left on a row not yet marked sold out used to draw a full clay bar reading as progress.
        let s = EventDetailPresentation.seatStatus(capacity: 12, remaining: 0, soldOut: false, going: false)
        XCTAssertEqual(s.kind, .soldOut)
        XCTAssertNil(s.ratio)
    }

    func testSplitFactsMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["splitFacts"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let ids = try XCTUnwrap(c["in"] as? [String]), o = try XCTUnwrap(c["out"] as? [String: Any])
            let out = EventDetailPresentation.splitFacts(ids.map { EventTypes.Fact(id: $0, label: $0, value: "x") })
            XCTAssertEqual(out.minAge?.id, o["minAge"] as? String, name)
            XCTAssertEqual(out.chips.map(\.id), o["chips"] as? [String], name)
            XCTAssertEqual(out.rows.map(\.id), o["rows"] as? [String], name)
        }
    }

    func testSplitFactValuesMatchFixture() throws {
        for c in try XCTUnwrap(fixture()["splitFactsValues"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let facts = try XCTUnwrap(c["in"] as? [[String: Any]]).map { f -> EventTypes.Fact in
                let vs = f["values"] as? [String]
                return EventTypes.Fact(id: f["id"] as! String, label: f["id"] as! String, value: (vs ?? ["x"]).joined(separator: ", "), values: vs)
            }
            let want = try XCTUnwrap((c["out"] as? [String: Any])?["chips"] as? [[Any]]).map { "\($0[0] as! String)|\($0[1] as? String ?? "-")" }
            let got = EventDetailPresentation.splitFacts(facts).chips.map { "\($0.id)|\($0.values == nil ? "-" : $0.value)" }
            XCTAssertEqual(got, want, name)
        }
    }

    func testIncludedSectionMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["includedSection"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let o = try XCTUnwrap(c["out"] as? [String: Any])
            let out = EventDetailPresentation.includedSection(try XCTUnwrap(c["in"] as? [String]))
            XCTAssertEqual(out.visible, o["visible"] as? Bool, name)
            XCTAssertEqual(out.items, o["items"] as? [String], name)
        }
    }

    func testDistanceLabelMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["distanceLabel"] as? [[String: Any]]) {
            XCTAssertEqual(EventDetailPresentation.distanceLabel(km: c["km"] as? Double, en: c["en"] as? Bool ?? true),
                           c["out"] as? String, c["name"] as? String ?? "")
        }
    }

    func testDateTileLabelMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["dateTileLabel"] as? [[String: Any]]) {
            XCTAssertEqual(EventDetailPresentation.dateTileLabel(c["raw"] as? String ?? "", en: c["en"] as? Bool ?? true),
                           c["out"] as? String, c["name"] as? String ?? "")
        }
    }

    func testStripPhotosMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["stripPhotos"] as? [[String: Any]]) {
            let out = EventDetailPresentation.stripPhotos(try XCTUnwrap(c["in"] as? [String]), heroURL: c["hero"] as? String) { $0 }
            XCTAssertEqual(out, c["out"] as? [String], c["name"] as? String ?? "")
        }
    }

    func testSupperDietaryWithTwoChoicesIsTwoChips() {
        let facts = EventTypes.detailFacts(EventTypes.profile("supper"),
                                           ["alcohol": .text("included"), "min_age": .text("18"), "dietary": .list(["vegetarian", "can_accommodate"])], lang: "en")
        let dietary = EventDetailPresentation.splitFacts(facts).chips.filter { $0.id == "dietary" }
        XCTAssertEqual(dietary.count, 2)
        XCTAssertTrue(dietary.allSatisfy { !$0.value.contains(",") })
    }

    func testAboutSectionMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["aboutSection"] as? [[String: Any]]) {
            let name = c["name"] as? String ?? ""
            let i = try XCTUnwrap(c["in"] as? [String: Any]), o = try XCTUnwrap(c["out"] as? [String: Any])
            let a = EventDetailPresentation.aboutSection(desc: i["desc"] as? String, intro: i["intro"] as? String, includedCount: i["includedCount"] as? Int ?? 0)
            XCTAssertEqual(a.visible, o["visible"] as? Bool, name)
            XCTAssertEqual(a.body, o["body"] as? String, name)
            XCTAssertEqual(a.clampable, o["clampable"] as? Bool, name)
            XCTAssertEqual(a.hasSheet, o["hasSheet"] as? Bool, name)
        }
    }

    func testEveryTypeKeepsAlcoholAndMinimumAgeVisible() throws {
        for key in ["supper", "music", "gallery", "fashion", "popup"] {
            let profile = EventTypes.profile(key)
            let facts = EventTypes.detailFacts(profile, ["alcohol": .text("none"), "min_age": .text("18")], lang: "en")
            let split = EventDetailPresentation.splitFacts(facts)
            XCTAssertEqual(split.minAge?.value, "18+", key)
            XCTAssertTrue(split.chips.contains { $0.id == "alcohol" }, key)
        }
    }

    func testHeroScrimKeepsWhiteTextReadableOnAWhitePhoto() {
        XCTAssertGreaterThanOrEqual(EventDetailPresentation.scrimContrast(alpha: EventDetailPresentation.heroScrim.alpha), 4.5)
    }
}

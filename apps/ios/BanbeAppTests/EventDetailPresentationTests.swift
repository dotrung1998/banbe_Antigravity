import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/eventDetailPresentation.test.mjs through the shared tests/fixtures/event-detail-presentation.json
/// (note 68) — change both together.
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
}

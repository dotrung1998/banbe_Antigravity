import XCTest
@testable import BanbeApp

/// Note 69 (migration 207): two picked categories shape one form, and the intro style rides in details.
final class EventTypesCombinedTests: XCTestCase {
    func testOneKeyIsThatTypeUnchanged() {
        let p = EventTypes.combined(["supper"])
        XCTAssertEqual(p.wizard?.details, EventTypes.profile("supper").wizard?.details)
        XCTAssertEqual(EventTypes.requiredFields(p), EventTypes.requiredFields(EventTypes.profile("supper")))
    }

    func testTwoKeysMergeFieldsWithSharedOnesOnceAtTheEnd() {
        let p = EventTypes.combined(["supper", "music"])
        XCTAssertEqual(p.key, "supper", "the first pick keeps the identity")
        XCTAssertEqual(p.wizard?.details, ["dietary", "dress_code", "lineup", "genre", "format", "alcohol", "min_age"])
        let required = EventTypes.requiredFields(p)
        XCTAssertTrue(required.contains("included"), "supper still needs Included")
        XCTAssertTrue(required.contains("lineup"), "music adds its lineup")
        XCTAssertEqual(required.filter { $0 == "alcohol" }.count, 1)
        XCTAssertEqual(p.detail?.facts.filter { $0 == "min_age" }.count, 1)
        XCTAssertTrue(p.detail?.facts.contains("genre") == true)
    }

    func testSharedTypeFieldsBelongToTheFirstTypeThatHasThem() {
        XCTAssertEqual(EventTypes.owner(of: "brands", keys: ["fashion", "popup"]), "fashion")
        XCTAssertEqual(EventTypes.owner(of: "entry_mode", keys: ["fashion", "popup"]), "popup")
        XCTAssertEqual(EventTypes.owner(of: "alcohol", keys: ["music", "supper"]), "music")
        XCTAssertEqual(EventTypes.owner(of: "dietary", keys: ["music", "supper"]), "supper")
    }

    func testMergedDraftReadsEachFieldFromItsOwner() {
        let draft: [String: EventDetails] = [
            "supper": ["dietary": .list(["vegan"]), "alcohol": .text("byo"), "lineup": .list(["stale"])],
            "music": ["lineup": .list(["Trio Hà"]), "alcohol": .text("paid")],
            "_style": ["intro_font": .text("serif")],
        ]
        let merged = EventTypes.mergedDraft(["supper", "music"], draft)
        XCTAssertEqual(merged["dietary"], .list(["vegan"]))
        XCTAssertEqual(merged["lineup"], .list(["Trio Hà"]), "music owns lineup")
        XCTAssertEqual(merged["alcohol"], .text("byo"), "shared fields live under the first pick")
        XCTAssertNil(merged["intro_font"])
    }

    func testPublishAddsSecondCategoryAndNonDefaultStyleOnly() {
        let draft: [String: EventDetails] = ["supper": ["dietary": .list(["vegan"])], "music": ["lineup": .list(["A"])]]
        let out = EventTypes.publishDetails(keys: ["supper", "music"], draft: draft, introFont: "serif", introColor: "ink")
        XCTAssertEqual(out["cat2"], .text("music"))
        XCTAssertEqual(out["intro_font"], .text("serif"))
        XCTAssertNil(out["intro_color"], "the default colour is not stored")
        let plain = EventTypes.publishDetails(keys: ["supper"], draft: [:], introFont: "sans", introColor: "ink")
        XCTAssertTrue(plain.isEmpty, "an untouched form stores nothing")
        let bogus = EventTypes.publishDetails(keys: ["supper"], draft: [:], introFont: "comic", introColor: "#ff0000")
        XCTAssertTrue(bogus.isEmpty, "only known fonts and theme colours")
    }

    func testPublishedEventReadsBackItsSecondCategory() {
        let details: EventDetails = ["cat2": .text("music"), "lineup": .list(["A"]), "intro_color": .text("clay")]
        XCTAssertEqual(EventTypes.secondCategory(details, primary: "supper"), "music")
        XCTAssertNil(EventTypes.secondCategory(details, primary: "music"), "never the same as the first")
        XCTAssertNil(EventTypes.secondCategory(["cat2": .text("karaoke")], primary: "supper"))
        XCTAssertTrue(EventTypes.eventProfile(catKey: "supper", details: details).wizard?.details.contains("lineup") == true)
        XCTAssertEqual(EventTypes.introStyle(details).color, "clay")
        XCTAssertNil(EventTypes.introStyle(details).font)
    }
}

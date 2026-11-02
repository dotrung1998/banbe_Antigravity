import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/eventDetailTabs.test.mjs through tests/fixtures/event-detail-tabs.json (note 75).
final class EventDetailTabsTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/event-detail-tabs.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testVisibleTabsMatchFixture() throws {
        for c in try XCTUnwrap(fixture()["visibleTabs"] as? [[String: Any]]) {
            let i = try XCTUnwrap(c["in"] as? [String: Bool])
            let out = EventDetailTabs.visible(hasMenu: i["hasMenu"] ?? false, hasHost: i["hasHost"] ?? false,
                                              hasPhotos: i["hasPhotos"] ?? false, hasProtection: i["hasProtection"] ?? false)
            XCTAssertEqual(out, c["out"] as? [String], c["name"] as? String ?? "")
        }
    }

    func testActiveTabMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["activeTab"] as? [[String: Any]]) {
            let tops = try XCTUnwrap(c["tops"] as? [NSNumber]).map(\.doubleValue)
            let got = EventDetailTabs.active(tops: tops, scrollTop: (c["scrollTop"] as? NSNumber)?.doubleValue ?? 0,
                                             maxScroll: (c["maxScroll"] as? NSNumber)?.doubleValue ?? 0,
                                             lead: (c["lead"] as? NSNumber)?.doubleValue ?? 0)
            XCTAssertEqual(got, c["out"] as? Int, c["name"] as? String ?? "")
        }
    }
}

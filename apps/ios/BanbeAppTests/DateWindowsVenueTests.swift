import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/dateWindowsVenue.test.mjs through tests/fixtures/date-windows-venue.json (Map redesign
/// phase 3): Tonight / Weekend / Today are judged in each event's own venue zone, DST included.
final class DateWindowsVenueTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/date-windows-venue.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func date(_ s: Any?) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(s as? String))) }

    func testWindowsAreComputedInTheVenueZone() throws {
        for c in try XCTUnwrap(fixture()["windows"] as? [[String: Any]]) {
            let zone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(c["tz"] as? String)))
            let w = try XCTUnwrap(HomeDiscovery.dateWindowInZone(try XCTUnwrap(c["option"] as? String), now: try date(c["now"]), timeZone: zone))
            let e = try XCTUnwrap(c["expect"] as? [String])
            XCTAssertEqual(w.start, try date(e[0]), "\(c["name"] ?? "") start")
            XCTAssertEqual(w.end, try date(e[1]), "\(c["name"] ?? "") end")
        }
    }

    func testEachEventIsJudgedInItsOwnVenueZone() throws {
        let p = try XCTUnwrap(fixture()["perVenue"] as? [String: Any])
        let items = try XCTUnwrap(p["items"] as? [[String: Any]]).map { i in
            HomeDiscovery.Item(key: i["key"] as! String, startsAt: try? date(i["startsAt"]), priceVnd: 0, catKeys: [], tz: i["tz"] as? String)
        }
        var f = HomeDiscovery.Filters(); f.date = "tonight"
        XCTAssertEqual(HomeDiscovery.apply(items, f, now: try date(p["now"])).map(\.key), p["tonight"] as? [String])
    }
}

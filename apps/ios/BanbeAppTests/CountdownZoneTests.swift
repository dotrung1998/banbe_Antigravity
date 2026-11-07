import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/countdownZone.test.mjs through tests/fixtures/countdown-zone.json (note 75): the stub countdown
/// counts days in the VENUE's zone, never the device's.
final class CountdownZoneTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/countdown-zone.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func date(_ v: Any?) -> Date? { (v as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } }

    func testDaysUntilMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["daysUntil"] as? [[String: Any]]) {
            let got = Countdown.daysUntilInZone(c["raw"] as? String ?? "", start: date(c["startMs"]),
                                                timeZone: TimeZone(identifier: c["tz"] as? String ?? ""),
                                                now: try XCTUnwrap(date(c["nowMs"])))
            XCTAssertEqual(got, c["out"] as? Int, c["name"] as? String ?? "")
        }
    }

    func testChipTextMatchesFixture() throws {
        for c in try XCTUnwrap(fixture()["chipText"] as? [[String: Any]]) {
            XCTAssertEqual(Countdown.countdownChipText(c["days"] as? Int, en: c["en"] as? Bool ?? false), c["out"] as? String)
        }
    }
}

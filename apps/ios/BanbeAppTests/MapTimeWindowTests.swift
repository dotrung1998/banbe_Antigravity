import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/mapTimeWindow.test.mjs through the shared tests/fixtures/map-time-window.json (Map E+, note 79).
final class MapTimeWindowTests: XCTestCase {
    private typealias W = MapTimeWindow

    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/map-time-window.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func ms(_ iso: Any?) throws -> Double {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(iso as? String)), "bad date \(iso ?? "nil")")
        return date.timeIntervalSince1970 * 1000
    }
    private func zone(_ id: Any?) -> TimeZone { EventMarket.timeZone(id as? String) }
    private func int(_ any: Any?) -> Int { (any as? NSNumber)?.intValue ?? -1 }

    private func window(_ any: Any?) throws -> W.Window {
        let w = try XCTUnwrap(any as? [String: Any])
        return W.Window(on: w["on"] as! Bool, key: w["key"] as! String, days: w["days"] as! [String],
                        from: int(w["from"]), to: int(w["to"]), todayKey: w["todayKey"] as! String)
    }

    func testRangeConstants() {
        XCTAssertEqual([W.rangeMin, W.rangeMax, W.rangeStep], [10, 26, 1])
    }

    func testEventSlotUsesTheVenueZoneAndFoldsTheSmallHours() throws {
        for c in try XCTUnwrap(fixture()["eventSlot"] as? [[String: Any]]) {
            let e = try XCTUnwrap(c["expect"] as? [String: Any])
            let s = W.eventSlot(ms: try ms(c["startsAt"]), timeZone: zone(c["tz"]))
            let name = "\(c["name"] ?? "")"
            XCTAssertEqual(s.dayKey, e["dayKey"] as? String, name)
            XCTAssertEqual(s.min, int(e["min"]), name)
        }
    }

    func testDayOptionsInBothLanguages() throws {
        for c in try XCTUnwrap(fixture()["dayOptions"] as? [[String: Any]]) {
            let expect = try XCTUnwrap(c["expect"] as? [[String: Any]])
            for en in [false, true] {
                let got = W.dayOptions(nowMs: try ms(c["now"]), timeZone: zone(c["tz"]), en: en)
                XCTAssertEqual(got.map(\.key), expect.map { $0["key"] as! String }, "\(c["name"] ?? "")")
                XCTAssertEqual(got.map(\.days), expect.map { $0["days"] as! [String] }, "\(c["name"] ?? "") days")
                XCTAssertEqual(got.map { [$0.label, $0.sub] }, expect.map { $0[en ? "en" : "vi"] as! [String] }, "\(c["name"] ?? "") \(en ? "en" : "vi")")
            }
        }
    }

    func testDefaultWindow() throws {
        for c in try XCTUnwrap(fixture()["defaultWindow"] as? [[String: Any]]) {
            let got = W.defaultWindow(key: c["key"] as! String, nowMs: try ms(c["now"]), timeZone: zone(c["tz"]))
            XCTAssertEqual(got, try window(c["expect"]), "\(c["name"] ?? "")")
        }
    }

    func testMoveKnob() throws {
        for c in try XCTUnwrap(fixture()["moveKnob"] as? [[String: Any]]) {
            let which: W.Knob = (c["which"] as? String) == "from" ? .from : .to
            let got = W.moveKnob(try window(c["win"]), which, hour: try XCTUnwrap((c["hour"] as? NSNumber)?.doubleValue))
            XCTAssertEqual(got, try window(c["expect"]), "\(c["name"] ?? "")")
        }
    }

    func testInWindow() throws {
        let root = try XCTUnwrap(fixture()["inWindow"] as? [String: Any])
        let now = try ms(root["now"])
        for c in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let slot = W.eventSlot(ms: try ms(c["startsAt"]), timeZone: zone(c["tz"]))
            XCTAssertEqual(W.inWindow(slot, try window(c["win"]), nowMs: now), c["expect"] as? Bool, "\(c["name"] ?? "")")
        }
    }

    func testWindowFromHomeDate() throws {
        for c in try XCTUnwrap(fixture()["windowFromHomeDate"] as? [[String: Any]]) {
            let got = W.windowFromHomeDate(c["date"] as! String, nowMs: try ms(c["now"]), timeZone: zone(c["tz"]))
            XCTAssertEqual(got, try window(c["expect"]), "\(c["name"] ?? "")")
        }
    }

    func testWindowSummaryAndHourLabel() throws {
        let f = try fixture()
        for c in try XCTUnwrap(f["windowSummary"] as? [[String: Any]]) {
            XCTAssertEqual(W.windowSummary(try window(c["win"]), dayLabel: c["label"] as! String, en: c["en"] as! Bool), c["expect"] as? String, "\(c["name"] ?? "")")
        }
        for c in try XCTUnwrap(f["hourLabel"] as? [[String: Any]]) {
            XCTAssertEqual(W.hourLabel(int(c["hour"])), c["expect"] as? String)
        }
    }
}

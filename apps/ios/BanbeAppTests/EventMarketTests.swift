import XCTest
@testable import BanbeApp

/// Per-event time zone + currency (migration 195). Every vector in tests/fixtures/event-market.json is shared with
/// tests/unit/eventMarket.test.mjs (web) and the SQL helpers — change all three together.
final class EventMarketTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/event-market.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func vectors(_ key: String) throws -> [[String: Any]] {
        try XCTUnwrap(fixture()[key] as? [[String: Any]], key)
    }

    private func utc(_ s: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: s), s) }

    func testTimeZonesFromCountryAndState() throws {
        let vs = try vectors("timeZones")
        XCTAssertFalse(vs.isEmpty)
        for v in vs {
            XCTAssertEqual(EventMarket.eventTimeZone(countryCode: v["country"] as? String, stateProvince: v["state"] as? String),
                           v["tz"] as? String, "\(v)")
        }
    }

    func testResolvedZonesPreferARealUSClientZone() throws {
        for v in try vectors("resolvedZones") {
            XCTAssertEqual(EventMarket.resolveEventTimeZone(countryCode: v["country"] as? String, stateProvince: v["state"] as? String,
                                                            clientTz: v["clientTz"] as? String),
                           v["tz"] as? String, "\(v)")
        }
    }

    func testCurrencies() throws {
        for v in try vectors("currencies") {
            XCTAssertEqual(EventMarket.eventCurrency(countryCode: v["country"] as? String), v["currency"] as? String, "\(v)")
        }
    }

    func testWallClockToInstant() throws {
        for v in try vectors("wallClock") {
            let tz = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(v["tz"] as? String)))
            let got = EventMarket.wallClockDate(date: try XCTUnwrap(v["date"] as? String), time: try XCTUnwrap(v["time"] as? String), timeZone: tz)
            XCTAssertEqual(got, try utc(try XCTUnwrap(v["utc"] as? String)), "\(v)")
        }
    }

    func testZonedParts() throws {
        for v in try vectors("zonedParts") {
            let tz = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(v["tz"] as? String)))
            let p = EventMarket.zonedParts(try utc(try XCTUnwrap(v["utc"] as? String)), timeZone: tz)
            XCTAssertEqual(p, EventMarket.ZonedParts(year: v["year"] as! Int, month: v["month"] as! Int, day: v["day"] as! Int,
                                                     hour: v["hour"] as! Int, minute: v["minute"] as! Int, weekday: v["weekday"] as! Int), "\(v)")
        }
    }

    func testMoneyFormatting() throws {
        for v in try vectors("money") {
            let amount = v["amount"] as! Int, currency = v["currency"] as! String
            XCTAssertEqual(EventMarket.formatMoney(amount, currency: currency), v["text"] as? String, "\(v)")
            XCTAssertEqual(EventMarket.formatMoneyShort(amount, currency: currency), v["short"] as? String, "\(v)")
        }
        // VND text is the same string the existing iOS formatters print.
        XCTAssertEqual(EventMarket.formatMoney(150_000, currency: "VND"), EventLabels.vnd(150_000))
        XCTAssertEqual(EventMarket.formatMoney(1_250_000, currency: "VND"), formatVnd(1_250_000))
    }

    func testParsePriceInput() throws {
        for v in try vectors("parsePrice") {
            XCTAssertEqual(EventMarket.parsePriceInput(v["input"] as! String, currency: v["currency"] as! String),
                           v["amount"] as? Int, "\(v)")
        }
    }

    func testPriceInputText() throws {
        for v in try vectors("priceInput") {
            XCTAssertEqual(EventMarket.priceInputText(v["amount"] as! Int, currency: v["currency"] as! String), v["text"] as? String, "\(v)")
        }
    }

    func testQuickPicks() throws {
        let picks = try XCTUnwrap(fixture()["quickPicks"] as? [String: [Int]])
        XCTAssertEqual(EventMarket.priceQuickPicks(currency: "VND"), picks["VND"])
        XCTAssertEqual(EventMarket.priceQuickPicks(currency: "USD"), picks["USD"])
    }

    func testPaidBookingAvailability() throws {
        for v in try vectors("paidBooking") {
            XCTAssertEqual(EventMarket.paidBookingAvailable(currency: v["currency"] as! String, amount: v["amount"] as! Int),
                           v["available"] as? Bool, "\(v)")
        }
    }

    func testMajorAmountAndRowDefaults() {
        XCTAssertEqual(EventMarket.majorAmount(1250, currency: "USD"), 12.5)
        XCTAssertEqual(EventMarket.majorAmount(150_000, currency: "VND"), 150_000)
        XCTAssertEqual(EventMarket.rowCurrency(nil), "VND")
        XCTAssertEqual(EventMarket.rowCurrency("USD"), "USD")
        XCTAssertEqual(EventMarket.rowTimeZoneID(tz: nil, countryCode: "US", stateProvince: "CA"), "America/Los_Angeles")
        XCTAssertEqual(EventMarket.rowTimeZoneID(tz: "America/Boise", countryCode: "US", stateProvince: "Idaho"), "America/Boise")
        XCTAssertEqual(EventMarket.rowTimeZoneID(tz: nil, countryCode: "US", stateProvince: nil), "Asia/Ho_Chi_Minh")
    }
}

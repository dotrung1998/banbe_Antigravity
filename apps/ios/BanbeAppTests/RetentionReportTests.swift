import XCTest
@testable import BanbeApp

/// Admin › Retention report (migration 196). Same vectors as tests/unit/retentionReport.test.mjs (web).
final class RetentionReportTests: XCTestCase {
    private typealias R = RetentionReport

    func testCounts() {
        XCTAssertEqual(R.count(.number(0)), "0")
        XCTAssertEqual(R.count(.number(1234)), "1,234")
        XCTAssertEqual(R.count(.text("<20")), "<20")
        XCTAssertEqual(R.count(.none), "—")
    }

    func testRatesAndMedians() {
        XCTAssertEqual(R.rate(.number(0.4)), "40%")
        XCTAssertEqual(R.rate(.number(0.125)), "12.5%")
        XCTAssertEqual(R.rate(.number(0.3333)), "33.3%")
        XCTAssertEqual(R.rate(.none), "—")
        XCTAssertEqual(R.median(.number(4)), "4")
        XCTAssertEqual(R.median(.number(4.55)), "4.6")
        XCTAssertEqual(R.median(.none), "—")
        XCTAssertEqual(R.countRate(.number(25), .number(0.25)), "25 · 25%")
        XCTAssertEqual(R.countRate(.text("<20"), .none), "<20")
        XCTAssertEqual(R.countRate(.number(30), .none), "30")
    }

    func testRangeIsTheLastNDaysIncludingToday() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15)))
        XCTAssertTrue(R.range(days: 30, now: now, calendar: cal) == ("2026-09-24", "2026-10-23"))
        XCTAssertTrue(R.range(days: 90, now: now, calendar: cal) == ("2026-07-26", "2026-10-23"))
        XCTAssertTrue(R.range(days: 365, now: now, calendar: cal) == ("2025-10-24", "2026-10-23"))
        XCTAssertTrue(R.range(days: 7, now: now, calendar: cal) == R.range(days: 90, now: now, calendar: cal))
    }

    func testDecodesTheServerShapeAndOrdersMarkets() throws {
        let json = """
        {"success":true,"from":"2026-07-26","to":"2026-10-23","k_min":20,
         "markets":[
          {"market":"US","people":"<20","active_people":"<20","new_people":"<20","d7_returned":"<20","d30_returned":"<20",
           "d7_rate":null,"d30_rate":null,"first_attenders":"<20","second_within_60d":"<20","second_within_60d_rate":null,
           "days_to_second_median":null},
          {"market":"VN","people":120,"active_people":80,"new_people":60,"d7_returned":21,"d7_rate":0.35,
           "d30_returned":"<20","d30_rate":null,"first_attenders":40,"second_within_60d":22,"second_within_60d_rate":0.55,
           "days_to_second_median":12.5}],
         "notifications":[{"kind":"new_message","sent":140,"read":"<20","read_minutes_median":null}],
         "notification_kinds_hidden":3}
        """
        let r = try JSONDecoder().decode(R.Reply.self, from: Data(json.utf8))
        XCTAssertEqual(r.success, true)
        XCTAssertEqual(r.notificationKindsHidden, 3)
        let ms = R.orderedMarkets(r.markets)
        XCTAssertEqual(ms.map(\.market), ["VN", "US", "unknown"])
        XCTAssertEqual(R.rows(ms[0]).map(\.value), ["120", "80", "60", "21 · 35%", "<20", "40", "22 · 55%", "12.5"])
        XCTAssertEqual(R.rows(ms[1]).first?.value, "<20")
        XCTAssertEqual(R.rows(ms[2]).first?.value, "—")
        let n = try XCTUnwrap(r.notifications?.first)
        XCTAssertEqual([R.count(n.sent), R.count(n.read), R.median(n.readMinutesMedian)], ["140", "<20", "—"])
        XCTAssertEqual(R.orderedMarkets(nil).map(\.market), ["VN", "US", "unknown"])
    }

    func testNotAuthorizedDecodes() throws {
        let r = try JSONDecoder().decode(R.Reply.self, from: Data(#"{"success":false,"error":"NOT_AUTHORIZED"}"#.utf8))
        XCTAssertEqual(r.success, false)
        XCTAssertEqual(r.error, "NOT_AUTHORIZED")
        XCTAssertNil(r.markets)
    }
}

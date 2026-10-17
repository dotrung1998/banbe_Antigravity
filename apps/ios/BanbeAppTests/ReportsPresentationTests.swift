import XCTest
@testable import BanbeApp

final class ReportsPresentationTests: XCTestCase {
    private let vi: (String, String) -> String = { v, _ in v }
    private let en: (String, String) -> String = { _, e in e }

    private func dash(_ json: String, _ T: @escaping (String, String) -> String) -> ReportsDashboard {
        ReportsPresentation.dashboard(ReportsFixtures.decode(json), fallbackScope: "personal", T: T)
    }

    // MARK: role ordering

    func testHostOrderingAndAttention() {
        let d = dash(ReportsFixtures.hostJSON, en)
        XCTAssertEqual(d.role, .host)
        XCTAssertEqual(d.primary?.key, "confirmed_seats")
        XCTAssertFalse(d.attentionFirst)
        XCTAssertEqual(d.attention.map(\.key), ["refunds_overdue", "refunds_owed"])
        XCTAssertEqual(d.attention.first?.severity, .overdue)
        // Flagged refunds are not repeated in the overview.
        XCTAssertEqual(d.overview.map(\.key), ["confirmed_payment_amount", "upcoming_events", "published_events", "check_ins"])
        XCTAssertEqual(d.trends.map(\.key), ["confirmed_payment_amount", "check_ins"])
        XCTAssertEqual(d.all.count, 7)
    }

    func testPersonalZeroRefundsStayInOverviewNotAttention() {
        let d = dash(ReportsFixtures.personalJSON, en)
        XCTAssertEqual(d.role, .personal)
        XCTAssertEqual(d.primary?.key, "confirmed_bookings")
        XCTAssertTrue(d.attention.isEmpty, "a zero backlog is never 'needs attention'")
        XCTAssertEqual(d.overview.map(\.key), ["upcoming_events", "attended_events", "saved_events", "outstanding_refunds"])
        XCTAssertEqual(d.trends.map(\.key), ["attended_events"])
    }

    func testAdminLeadsWithBacklog() {
        let d = dash(ReportsFixtures.adminJSON, vi)
        XCTAssertEqual(d.role, .admin)
        XCTAssertTrue(d.attentionFirst)
        XCTAssertEqual(d.attention.map(\.key), ["pending_event_reviews"])
        XCTAssertEqual(d.attention.first?.message, "Sự kiện chờ lâu nhất: 2,5 ngày.")
        XCTAssertEqual(d.primary?.key, "platform_new_bookings")
        XCTAssertEqual(d.overview.map(\.key), ["unresolved_disputes", "backlog_avg_age_days", "platform_new_events"])
    }

    func testPersonalRefundMessageCountsHostMarkedSent() {
        let json = """
        {"success":true,"scope":"personal","metrics":[
         {"key":"outstanding_refunds","label":"Hoàn tiền đang chờ","unit":"vnd","value":500000,
          "rows":[{"id":"a","status":"owed","amount_vnd":200000},{"id":"b","status":"host_marked_sent","amount_vnd":300000}]}]}
        """
        let d = dash(json, en)
        XCTAssertEqual(d.attention.count, 1)
        XCTAssertEqual(d.attention[0].valueText, "500,000₫")
        XCTAssertEqual(d.attention[0].message, "1 marked as sent by the host. Confirm once you've received it.")
    }

    func testUnknownMetricIsKeptWithServerLabel() {
        let json = """
        {"success":true,"scope":"host","metrics":[
         {"key":"brand_new_metric","label":"Chỉ số mới","unit":"count","value":7}]}
        """
        let d = dash(json, en)
        XCTAssertEqual(d.overview.map(\.title), ["Chỉ số mới"])
        XCTAssertNil(d.primary)
    }

    func testFailedOrEmptyPayloadIsEmptyDashboard() {
        let d = dash(#"{"success":true,"scope":"admin","metrics":[]}"#, en)
        XCTAssertTrue(d.isEmpty)
        XCTAssertTrue(d.attention.isEmpty)
    }

    // MARK: series honesty

    func testSeriesSummaryFromRealPointsOnly() throws {
        let d = dash(ReportsFixtures.hostJSON, en)
        let s = try XCTUnwrap(d.primary?.summary)
        XCTAssertEqual(s.total, 5)
        XCTAssertEqual(s.activeDays, 2)
        XCTAssertEqual(s.dayCount, 3)
        XCTAssertEqual(s.peak?.dayKey, "2026-10-02")
        XCTAssertEqual(ReportsPresentation.seriesSentence(try XCTUnwrap(d.primary), T: en),
                       "Total 5 over 3 days, active on 2. Peak 3 on 02/10.")
    }

    func testAllZeroSeriesHasNoPeak() throws {
        let d = dash(ReportsFixtures.hostJSON, en)
        let checkIns = try XCTUnwrap(d.all.first { $0.key == "check_ins" })
        XCTAssertEqual(checkIns.summary?.hasActivity, false)
        XCTAssertNil(checkIns.summary?.peak)
        XCTAssertEqual(ReportsPresentation.seriesSentence(checkIns, T: en), "No activity across 3 days.")
    }

    func testPointInTimeMetricsAreNeverSeries() {
        let d = dash(ReportsFixtures.hostJSON, en)
        for key in ["published_events", "upcoming_events", "refunds_owed", "refunds_overdue"] {
            let m = d.all.first { $0.key == key }
            XCTAssertEqual(m?.isTimeSeries, false, key)
            XCTAssertNil(m?.summary, key)
        }
    }

    func testPeakTieGoesToEarliestDay() {
        let pts = ReportsPresentation.seriesPoints([
            .init(d: "2026-10-03", v: 2), .init(d: "2026-10-01", v: 2), .init(d: "2026-10-02", v: 0),
        ])
        XCTAssertEqual(pts.map(\.dayKey), ["2026-10-01", "2026-10-02", "2026-10-03"])
        XCTAssertEqual(ReportsPresentation.summarize(pts).peak?.dayKey, "2026-10-01")
    }

    // MARK: formatting

    func testValueFormattingPerLanguage() {
        XCTAssertEqual(ReportsPresentation.formatValue(1_250_000, kind: .money, metricKey: "x", T: vi), "1.250.000₫")
        XCTAssertEqual(ReportsPresentation.formatValue(1_250_000, kind: .money, metricKey: "x", T: en), "1,250,000₫")
        XCTAssertEqual(ReportsPresentation.formatValue(1_250_000, kind: .money, metricKey: "x", T: en, spoken: true), "1,250,000 dong")
        XCTAssertEqual(ReportsPresentation.formatValue(12_345, kind: .count, metricKey: "x", T: vi), "12.345")
        XCTAssertEqual(ReportsPresentation.formatValue(2.5, kind: .days, metricKey: "x", T: vi), "2,5 ngày")
        XCTAssertEqual(ReportsPresentation.formatValue(1, kind: .days, metricKey: "x", T: en), "1 day")
        XCTAssertEqual(ReportsPresentation.formatValue(0, kind: .days, metricKey: "backlog_avg_age_days", T: en), "No backlog")
    }

    func testCompactAxisLabels() {
        XCTAssertEqual(ReportsPresentation.compact(750_000, kind: .money, T: vi), "750k")
        XCTAssertEqual(ReportsPresentation.compact(1_200_000, kind: .money, T: vi), "1,2tr")
        XCTAssertEqual(ReportsPresentation.compact(1_200_000, kind: .money, T: en), "1.2M")
        XCTAssertEqual(ReportsPresentation.compact(42, kind: .count, T: en), "42")
    }

    func testRangeTextParsesFractionalAndPlainTimestamps() {
        // The old on-screen label used a formatter without fractional seconds
        // and came out blank for real server payloads.
        XCTAssertEqual(ReportsPresentation.rangeText(.init(start: "2026-10-01T02:15:30.25+00:00", end: "2026-10-03T16:59:59.999+00:00")),
                       "01/10/2026 – 03/10/2026")
        XCTAssertEqual(ReportsPresentation.rangeText(.init(start: "2026-10-01T00:00:00+00:00", end: "2026-10-02T00:00:00+00:00")),
                       "01/10/2026 – 02/10/2026")
        XCTAssertEqual(ReportsPresentation.rangeText(nil), "")
    }

    func testDayBucketsDoNotShiftWithDeviceTimeZone() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        for tz in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Ho_Chi_Minh"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: tz))
            let d = try XCTUnwrap(ReportsPresentation.parseDay("2026-10-02"))
            XCTAssertEqual(ReportsPresentation.formatDay(d, T: en), "02/10", tz)
        }
    }

    // MARK: rows

    func testRowsUseLocalizedLabelsAndHideIds() throws {
        let report = ReportsFixtures.decode(ReportsFixtures.hostJSON)
        let owed = try XCTUnwrap(report.metrics?.first { $0.key == "refunds_owed" })
        let rows = ReportsPresentation.rows(owed, T: en)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Gallery night")
        XCTAssertTrue(rows[0].flagged)
        XCTAssertEqual(rows[0].fields.map(\.label), ["Amount", "Refund due", "Overdue"])
        XCTAssertEqual(rows[0].fields.map(\.value), ["300,000₫", "30/09/2026 07:00", "Yes"])
        XCTAssertFalse(rows[0].fields.contains { $0.value == "r1" }, "internal ids stay export-only")
    }

    func testStatusLabelsAreLocalized() {
        XCTAssertEqual(ReportsPresentation.cell("status", .string("host_marked_sent"), T: vi), "Host báo đã gửi")
        XCTAssertEqual(ReportsPresentation.cell("status", .string("owed"), T: en), "Waiting for host refund")
        XCTAssertNil(ReportsPresentation.cell("due_at", .null, T: en))
    }
}

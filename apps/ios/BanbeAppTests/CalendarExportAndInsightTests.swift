import EventKitUI
import XCTest
@testable import BanbeApp

final class CalendarExportTests: XCTestCase {
    private let en: (String, String) -> String = { _, e in e }

    func testDraftMappingWithoutEndUsesHonestDefault() throws {
        let start = Date(timeIntervalSince1970: 1_793_491_200)
        let d = try XCTUnwrap(CalendarExport.draft(title: "Supper", start: start, end: nil, location: " 42 Lê Lợi ",
                                                   eventKey: "evt 1", origin: "https://www.banbe.app", T: en))
        XCTAssertEqual(d.title, "Supper")
        XCTAssertEqual(d.start, start)
        XCTAssertEqual(d.end, start.addingTimeInterval(2 * 3600))
        XCTAssertTrue(d.endIsEstimated)
        XCTAssertEqual(d.location, "42 Lê Lợi")
        XCTAssertEqual(d.url?.absoluteString, "https://www.banbe.app/api/photo-share?eid=evt%201")
        XCTAssertTrue(d.notes.contains("didn't list an end time"))
    }

    func testDraftUsesRealEndAndNoStartMeansUnavailable() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let d = try XCTUnwrap(CalendarExport.draft(title: "T", start: start, end: start.addingTimeInterval(600),
                                                   location: "", eventKey: "k", origin: "https://x", T: en))
        XCTAssertEqual(d.end, start.addingTimeInterval(600))
        XCTAssertFalse(d.endIsEstimated)
        XCTAssertNil(d.location)
        XCTAssertFalse(d.notes.contains("end time"))
        XCTAssertNil(CalendarExport.draft(title: "T", start: nil, end: nil, location: "", eventKey: "k", origin: "https://x", T: en))
    }

    func testEditorResultMapping() {
        XCTAssertEqual(CalendarExport.result(for: .saved), .saved)
        XCTAssertEqual(CalendarExport.result(for: .canceled), .cancelled)
        XCTAssertEqual(CalendarExport.result(for: .deleted), .deleted)
    }

    func testAnalyticsCarryOnlyEnumsAndBuckets() {
        let events: [AnalyticsEvent] = [
            .systemCalendarEditorResult(result: "saved"), .banbeScheduleResult(result: "added"),
            .scheduleModeSelected(mode: "discover"), .scheduleDaySelected(bucket: "today"),
            .scheduleConflictShown(countBucket: AnalyticsEvent.bucket(3)), .publicStorySkipped(step: 1),
            .publicEntryViewed, .publicEntryLogin, .publicEntryGetStarted,
        ]
        let allowed: Set<String> = ["result", "mode", "day_bucket", "count_bucket", "step"]
        for e in events {
            XCTAssertTrue(Set(e.properties.keys).isSubset(of: allowed), e.name)
        }
        XCTAssertEqual(AnalyticsEvent.systemCalendarEditorOpened.name, "system_calendar_editor_opened")
    }
}

final class ReportInsightTests: XCTestCase {
    private let en: (String, String) -> String = { _, e in e }

    private func insights(_ json: String) -> [ReportInsight] {
        ReportsPresentation.dashboard(ReportsFixtures.decode(json), fallbackScope: "personal", T: en).insights
    }

    func testHostOverdueShareUsesOneClaimPopulation() throws {
        let i = insights(ReportsFixtures.hostJSON)
        XCTAssertEqual(i.count, 1)
        guard case .share(let s) = try XCTUnwrap(i.first) else { return XCTFail("expected a share") }
        XCTAssertEqual(s.numerator, 1)
        XCTAssertEqual(s.denominator, 1, "denominator = owed claims in the same rows, not another metric")
        XCTAssertEqual(s.caption, "1 of 1 owed refund claim overdue")
        XCTAssertEqual(i.first?.metricKey, "refunds_owed")
    }

    func testPersonalWithoutOutstandingRowsHasNoInsight() {
        XCTAssertTrue(insights(ReportsFixtures.personalJSON).isEmpty, "never a chart without grouped data")
    }

    func testPersonalRefundStatusDistribution() throws {
        let json = """
        {"success":true,"scope":"personal","metrics":[
         {"key":"outstanding_refunds","label":"x","unit":"vnd","value":500000,
          "rows":[{"status":"owed"},{"status":"host_marked_sent"},{"status":"host_marked_sent"}]}]}
        """
        guard case .distribution(let d) = try XCTUnwrap(insights(json).first) else { return XCTFail() }
        XCTAssertEqual(d.segments.map(\.count), [1, 2])
        XCTAssertEqual(d.total, 3)
    }

    func testAdminBacklogCompositionAndAges() throws {
        let i = insights(ReportsFixtures.adminJSON)
        XCTAssertEqual(i.count, 2)
        guard case .distribution(let comp) = i[0], case .distribution(let ages) = i[1] else { return XCTFail() }
        XCTAssertEqual(comp.segments.map(\.id), ["reviews"], "a zero-count segment is not drawn")
        XCTAssertEqual(comp.total, 2)
        XCTAssertEqual(ages.segments.map(\.count), [0, 1, 0, 0], "age 2.5 days → 1–3 days bucket")
        XCTAssertEqual(ReportsPresentation.insightSentence(i[0], T: en), "Open backlog. Total 2. Event reviews: 2.")
    }

    func testEmptyPayloadHasNoInsights() {
        XCTAssertTrue(insights(#"{"success":true,"scope":"host","metrics":[]}"#).isEmpty)
    }
}

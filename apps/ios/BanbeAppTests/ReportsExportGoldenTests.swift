import PDFKit
import XCTest
@testable import BanbeApp

/// Golden output of the Reports exports, captured against the export code as
/// it was BEFORE the dashboard redesign. The redesign must not change a byte
/// of CSV, and JSON may only differ in `generated_at`.
@MainActor
final class ReportsExportGoldenTests: XCTestCase {

    private func app(_ json: String) -> AppState {
        let app = AppState()
        app.lang = "vi"
        app.reportsScope = "host"
        app.reportsData = ReportsFixtures.decode(json)
        return app
    }

    private func read(_ url: URL?) throws -> String {
        // Byte-exact: String(contentsOf:) would silently drop the UTF-8 BOM.
        let data = try Data(contentsOf: try XCTUnwrap(url))
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF], "CSV must start with a UTF-8 BOM")
        return String(decoding: data, as: UTF8.self)
    }

    func testMetricCsvGolden() throws {
        let app = app(ReportsFixtures.hostJSON)
        app.exportReportCardCsv("confirmed_seats")
        let csv = try read(app.reportsExportedFileURL)
        XCTAssertEqual(app.reportsExportedFileURL?.lastPathComponent, "banbe-confirmed_seats.csv")
        XCTAssertEqual(csv, "\u{FEFF}at,event_name,id,qty\r\n"
            + "2026-10-02T03:04:05.123+00:00,\"'=SUM(A1), Phở\",b1,3\r\n"
            + "2026-10-03T20:00:00+00:00,\"Supper \"\"club\"\"\",b2,2")
    }

    func testMetricCsvWithoutRowsFallsBackToValue() throws {
        let app = app(ReportsFixtures.hostJSON)
        app.exportReportCardCsv("refunds_overdue")
        XCTAssertEqual(try read(app.reportsExportedFileURL), "\u{FEFF}value\r\n1")
    }

    func testMetricCsvBooleanAndMoneyRows() throws {
        let app = app(ReportsFixtures.hostJSON)
        app.exportReportCardCsv("refunds_owed")
        XCTAssertEqual(try read(app.reportsExportedFileURL),
                       "\u{FEFF}amount_vnd,due_at,event_name,id,overdue\r\n300000,2026-09-30T00:00:00+00:00,Gallery night,r1,true")
    }

    func testJsonGoldenIgnoringGeneratedAt() throws {
        let app = app(ReportsFixtures.hostJSON)
        app.exportReportsJson()
        let url = try XCTUnwrap(app.reportsExportedFileURL)
        XCTAssertEqual(url.lastPathComponent, "banbe-report-host.json")
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNotNil(obj.removeValue(forKey: "generated_at"))
        XCTAssertEqual(obj["schema_version"] as? Int, 1)
        XCTAssertEqual(obj["role"] as? String, "host")
        XCTAssertEqual(obj["range"] as? [String: String],
                       ["start": "2026-10-01T02:15:30.25+00:00", "end": "2026-10-03T16:59:59.999+00:00"])
        let metrics = try XCTUnwrap(obj["metrics"] as? [[String: Any]])
        XCTAssertEqual(metrics.map { $0["key"] as? String }, [
            "published_events", "upcoming_events", "confirmed_seats", "check_ins",
            "confirmed_payment_amount", "refunds_owed", "refunds_overdue",
        ])
        // Server label is exported verbatim (not the localized client label).
        XCTAssertEqual(metrics[2]["label"] as? String, "Chỗ đã xác nhận")
        XCTAssertEqual((metrics[2]["series"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((metrics[2]["rows"] as? [[String: Any]])?.first?["event_name"] as? String, "=SUM(A1), Phở")
        XCTAssertNil(metrics[0]["series"])
        XCTAssertNil(metrics[0]["rows"])
        XCTAssertEqual(metrics[4]["value"] as? Double, 1_250_000)
    }

    func testPdfContainsEveryMetric() throws {
        let app = app(ReportsFixtures.hostJSON)
        app.exportReportsPdf()
        XCTAssertEqual(app.reportsExportBusy, "")
        let url = try XCTUnwrap(app.reportsExportedFileURL)
        XCTAssertEqual(url.lastPathComponent, "banbe-report-host.pdf")
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Báo cáo số liệu (Tổ chức)"))
        XCTAssertTrue(text.contains("01/10/2026 - 03/10/2026"))
        for label in ["Sự kiện đã công khai", "Chỗ đã xác nhận", "Hoàn tiền quá hạn"] {
            XCTAssertTrue(text.contains(label), "PDF missing \(label)")
        }
        XCTAssertTrue(text.contains("1.250.000 đ"))
    }
}

import XCTest
@testable import BanbeApp

/// Note 78. Every case in tests/fixtures/ticket-copy.json (generated from src/lib/ticketCopy.js, checked by
/// tests/unit/ticketCopy.test.mjs) is compared with the Swift port, so a copy change is made in both or neither.
final class TicketCopyTests: XCTestCase {
    private func fixture() throws -> [[String: Any]] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/ticket-copy.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["cases"] as? [[String: Any]])
    }

    private func context(_ d: [String: Any]) -> TicketCopy.Context {
        var c = TicketCopy.Context()
        c.en = d["en"] as? Bool ?? false
        c.eventCancelled = d["eventCancelled"] as? Bool ?? false
        c.dateText = d["dateText"] as? String ?? ""
        c.timeText = d["timeText"] as? String ?? ""
        c.areaText = d["areaText"] as? String ?? ""
        c.daysUntil = d["daysUntil"] as? Int
        if let w = d["typicalWait"] as? [String: String], let vi = w["vi"], let en = w["en"] { c.typicalWait = (vi, en) }
        c.verifyOverdue = d["verifyOverdue"] as? Bool ?? false
        c.hasReceipt = d["hasReceipt"] as? Bool ?? false
        c.hasRefund = d["hasRefund"] as? Bool ?? false
        c.hasDirections = d["hasDirections"] as? Bool ?? false
        return c
    }

    func testCopyMatchesTheSharedFixture() throws {
        let cases = try fixture()
        XCTAssertGreaterThan(cases.count, 40)
        for c in cases {
            let name = c["name"] as? String ?? ""
            let key = try XCTUnwrap(TicketStatus.Key(rawValue: try XCTUnwrap(c["key"] as? String)), name)
            let got = TicketCopy.copy(for: key, context(try XCTUnwrap(c["ctx"] as? [String: Any])))
            let want = try XCTUnwrap(c["expect"] as? [String: Any], name)
            XCTAssertEqual(got.label, want["label"] as? String, "\(name) label")
            XCTAssertEqual(got.heading, want["heading"] as? String, "\(name) heading")
            XCTAssertEqual(got.sub, want["sub"] as? String, "\(name) sub")
            XCTAssertEqual(got.detail, want["detail"] as? String, "\(name) detail")
            let link = want["link"] as? [String: String]
            XCTAssertEqual(got.link?.kind.rawValue, link?["kind"], "\(name) link kind")
            XCTAssertEqual(got.link?.label, link?["label"], "\(name) link label")
        }
    }

    func testEveryKeyHasCopyInBothLanguages() {
        for key in TicketStatus.Key.allCases {
            var vi = TicketCopy.Context(); vi.en = false
            var en = TicketCopy.Context(); en.en = true
            let a = TicketCopy.copy(for: key, vi), b = TicketCopy.copy(for: key, en)
            XCTAssertFalse(a.heading.isEmpty); XCTAssertFalse(b.heading.isEmpty)
            XCTAssertNotEqual(a.heading, b.heading, "\(key) vi != en")
        }
    }
}

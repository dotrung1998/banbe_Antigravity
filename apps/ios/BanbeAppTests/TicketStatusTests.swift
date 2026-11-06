import XCTest
@testable import BanbeApp

/// Note 78. Every vector in tests/fixtures/ticket-status.json is shared with tests/unit/ticketStatus.test.mjs (web),
/// change both together.
final class TicketStatusTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/ticket-status.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCasePrecedence() throws {
        let vs = try XCTUnwrap(fixture()["cases"] as? [[String: Any]])
        XCTAssertFalse(vs.isEmpty)
        for v in vs {
            let i = v["in"] as? [String: Any] ?? [:]
            let got = TicketStatus.resolve(
                paymentState: i["paymentState"] as? String, eventCancelled: i["eventCancelled"] as? Bool ?? false,
                endedHoursAgo: i["endedHoursAgo"] as? Int, isPaid: i["isPaid"] as? Bool ?? false,
                checkedIn: i["checkedIn"] as? Bool ?? false, daysUntil: i["daysUntil"] as? Int)
            let name = v["case"] as? String ?? ""
            if let e = v["expect"] as? [String: String] {
                XCTAssertEqual(got?.key.rawValue, e["key"], name)
                XCTAssertEqual(got?.tone, e["tone"], name)
                XCTAssertEqual(got?.qr.rawValue, e["qr"], name)
            } else {
                XCTAssertNil(got, name)
            }
        }
    }

    func testEveryKeyIsReachableAndMapped() throws {
        let vs = try XCTUnwrap(fixture()["cases"] as? [[String: Any]])
        let seen = Set(vs.compactMap { ($0["expect"] as? [String: String])?["key"] })
        XCTAssertEqual(seen, Set(TicketStatus.Key.allCases.map(\.rawValue)))
    }

    func testOnlyOkAndInDrawTheToken() throws {
        let m = try XCTUnwrap(fixture()["qrShowsToken"] as? [String: Bool])
        for (qr, want) in m { XCTAssertEqual(TicketStatus.qrShowsToken(TicketStatus.QR(rawValue: qr)), want, qr) }
    }

    func testEntryCodeGroupsThreeThree() throws {
        for v in try XCTUnwrap(fixture()["entryCode"] as? [[String: String]]) {
            XCTAssertEqual(TicketStatus.formatEntryCode(v["in"]), v["out"], v["in"] ?? "")
        }
    }

    func testDistanceOnlyWhenLocatedAndNear() throws {
        for v in try XCTUnwrap(fixture()["distance"] as? [[String: Any]]) {
            let got = TicketStatus.showDistance(km: v["km"] as? Double, located: v["located"] as? Bool, en: v["en"] as? Bool ?? false)
            XCTAssertEqual(got, v["out"] as? String, "\(v)")
        }
    }

    func testDoorWatchWindowAndNamedScans() throws {
        let vs = try XCTUnwrap(fixture()["doorWatch"] as? [[String: Any]])
        XCTAssertFalse(vs.isEmpty)
        for v in vs {
            let i = v["in"] as? [String: Any] ?? [:]
            // The vectors count milliseconds from an arbitrary zero; any fixed reference date works.
            let ref = Date(timeIntervalSince1970: 1_700_000_000)
            func at(_ ms: Any?) -> Date? { (ms as? NSNumber).map { ref.addingTimeInterval($0.doubleValue / 1000) } }
            let got = TicketStatus.doorWatchOpen(namedScans: i["namedScans"] as? [Bool], checkedIn: i["checkedIn"] as? Bool ?? false,
                                                 start: at(i["startMs"]), now: at(i["nowMs"]) ?? ref)
            XCTAssertEqual(got, v["expect"] as? Bool, v["case"] as? String ?? "")
        }
    }
}

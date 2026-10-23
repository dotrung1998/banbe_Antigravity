import XCTest
@testable import BanbeApp

/// Phase 1 quick wins. Every vector in tests/fixtures/quick-wins.json is shared with tests/unit/quickWins.test.mjs
/// (web) — change both together.
final class QuickWinsTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/quick-wins.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func utc(_ s: String) throws -> Date { try XCTUnwrap(ISO8601DateFormatter().date(from: s), s) }

    func testEndedWinsOverTheTicket() throws {
        let vs = try XCTUnwrap(fixture()["endedPrecedence"] as? [[String: Any]])
        XCTAssertFalse(vs.isEmpty)
        for v in vs {
            let got = ReserveBar.state(booking: v["booking"] as? Bool ?? false, ticket: v["ticket"] as? Bool ?? false,
                                       cancelled: v["cancelled"] as? Bool ?? false, ended: v["ended"] as? Bool ?? false,
                                       soldOut: v["soldOut"] as? Bool ?? false, blocked: false)
            XCTAssertEqual(got.rawValue, v["expect"] as? String, v["case"] as? String ?? "")
        }
    }

    func testOnceKeysMatchTheContract() throws {
        let keys = try XCTUnwrap(fixture()["onceKeys"] as? [String: String])
        XCTAssertEqual(keys.count, QuickWins.Moment.allCases.count)
        for m in QuickWins.Moment.allCases {
            XCTAssertEqual(QuickWins.onceKeyTemplates[m], keys[m.rawValue], m.rawValue)
        }
        XCTAssertEqual(QuickWins.onceKey(.ticketReveal, "B1"), keys["ticketReveal"]?.replacingOccurrences(of: "<bookingId>", with: "b1"))
        XCTAssertEqual(QuickWins.onceKey(.eventLive, "ev-9"), keys["eventLive"]?.replacingOccurrences(of: "<eventId>", with: "ev-9"))
        XCTAssertNil(QuickWins.onceKey(.checkIn, ""))
    }

    func testCelebrationFiresOncePerMilestonePerDevice() throws {
        let suite = "QuickWinsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(QuickWins.seenOnce(.ticketReveal, "b1", defaults: defaults))
        XCTAssertTrue(QuickWins.claimOnce(.ticketReveal, "b1", defaults: defaults))
        XCTAssertFalse(QuickWins.claimOnce(.ticketReveal, "b1", defaults: defaults))
        XCTAssertTrue(QuickWins.seenOnce(.ticketReveal, "b1", defaults: defaults))
        XCTAssertTrue(QuickWins.claimOnce(.ticketReveal, "b2", defaults: defaults))
        XCTAssertTrue(QuickWins.claimOnce(.checkIn, "b1", defaults: defaults))
    }

    func testTypicalWait() throws {
        let vs = try XCTUnwrap(fixture()["typicalWait"] as? [[String: Any]])
        for v in vs {
            let minutes = (v["minutes"] as? NSNumber)?.doubleValue
            let got = QuickWins.typicalWaitText(minutes: minutes)
            XCTAssertEqual(got?.vi, v["vi"] as? String, "\(v)")
            XCTAssertEqual(got?.en, v["en"] as? String, "\(v)")
        }
        XCTAssertNil(QuickWins.typicalWaitText(minutes: -3))
        XCTAssertEqual(QuickWins.typicalWaitText(minutes: 58)?.en, "This host usually confirms within about 1 hour.")
        XCTAssertEqual(QuickWins.typicalWaitText(minutes: 1430)?.en, "This host usually confirms within about 1 day.")
    }

    func testFillText() throws {
        let vs = try XCTUnwrap(fixture()["fillText"] as? [[String: Any]])
        for v in vs {
            let got = QuickWins.fillText(capacity: v["capacity"] as? Int, booked: v["booked"] as? Int)
            XCTAssertEqual(got?.vi, v["vi"] as? String, "\(v)")
            XCTAssertEqual(got?.en, v["en"] as? String, "\(v)")
        }
    }

    func testSavedRow() throws {
        let r = try XCTUnwrap(fixture()["savedRow"] as? [String: Any])
        let now = try utc(try XCTUnwrap(r["now"] as? String))
        let events = try XCTUnwrap(r["events"] as? [[String: Any]]).map { e in
            QuickWins.Candidate(key: e["key"] as? String ?? "", status: e["status"] as? String ?? "",
                                startsAt: (e["startsAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
        }
        XCTAssertEqual(r["maxItems"] as? Int, QuickWins.savedRowMax)
        XCTAssertEqual(r["withinDays"] as? Int, QuickWins.savedRowWithinDays)
        XCTAssertEqual(QuickWins.savedComingUp(events, now: now).map(\.key), r["expect"] as? [String])
        XCTAssertEqual(QuickWins.savedComingUp([], now: now), [])
    }

    func testNextFromHost() throws {
        let now = try utc("2027-03-01T03:00:00Z")
        func c(_ k: String, _ s: String, _ d: String) throws -> QuickWins.Candidate { .init(key: k, status: s, startsAt: try utc(d)) }
        let rows = [
            try c("this", "live", "2027-03-02T12:00:00Z"), try c("d", "live", "2027-04-02T12:00:00Z"),
            try c("a", "live", "2027-03-03T12:00:00Z"), try c("gone", "ended", "2027-03-03T12:00:00Z"),
            try c("past", "live", "2027-02-03T12:00:00Z"), try c("b", "live", "2027-03-04T12:00:00Z"),
            try c("c", "live", "2027-03-05T12:00:00Z"),
        ]
        XCTAssertEqual(QuickWins.nextFromHost(rows, now: now, excluding: "this").map(\.key), ["a", "b", "c"])
    }

    func testNewlyLive() throws {
        let now = try utc("2027-03-10T00:00:00Z")
        XCTAssertTrue(QuickWins.isNewlyLive(status: "live", reviewedAt: try utc("2027-03-09T00:00:00Z"), startsAt: try utc("2027-03-20T00:00:00Z"), now: now))
        XCTAssertFalse(QuickWins.isNewlyLive(status: "live", reviewedAt: try utc("2027-02-20T00:00:00Z"), startsAt: try utc("2027-03-20T00:00:00Z"), now: now))
        XCTAssertFalse(QuickWins.isNewlyLive(status: "live", reviewedAt: try utc("2027-03-09T00:00:00Z"), startsAt: try utc("2027-03-09T12:00:00Z"), now: now))
        XCTAssertFalse(QuickWins.isNewlyLive(status: "review", reviewedAt: nil, startsAt: try utc("2027-03-20T00:00:00Z"), now: now))
    }

    func testReferralOnlyForFreshAccounts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(QuickWins.isFreshAccount(createdAt: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(QuickWins.isFreshAccount(createdAt: now.addingTimeInterval(-25 * 3600), now: now))
    }
}

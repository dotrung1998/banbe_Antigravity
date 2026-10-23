import XCTest
@testable import BanbeApp

/// Phase 2-3 core loops. Every vector in tests/fixtures/core-loops.json is shared with tests/unit/coreLoops.test.mjs
/// (web) — change both together.
final class CoreLoopsTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/core-loops.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testNotificationRoutesMatchTheContract() throws {
        let vs = try XCTUnwrap(fixture()["notificationRoutes"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vs.count, 7)
        for v in vs {
            let kind = try XCTUnwrap(v["kind"] as? String)
            let raw = try XCTUnwrap(v["data"] as? [String: Any])
            // The same conversion a push payload goes through (PushRouting.value), so JSON numbers arrive as .int.
            let data = raw.mapValues { PushRouting.value($0) }
            let got = CoreLoops.route(kind: kind, data: data)
            XCTAssertEqual(got?.route.rawValue, v["route"] as? String, "\(v)")
            XCTAssertEqual(got?.id, v["id"] as? String, "\(v)")
        }
    }

    func testAPushTapRoutesLikeABellTap() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Your event is tomorrow", "body": "Jazz starts tomorrow at 19:00."]],
            "nid": UUID().uuidString, "kind": "event_reminder_day",
            "data": ["event_id": "e1", "booking_id": "b1"],
        ]
        let n = try XCTUnwrap(PushRouting.notification(from: userInfo, recipientID: nil))
        XCTAssertEqual(PushRouting.coreLoopDestination(n), .init(route: .ticket, id: "b1"))
        let digest: [AnyHashable: Any] = ["nid": UUID().uuidString, "kind": "weekly_digest", "data": ["screen": "this_weekend", "count": 4]]
        XCTAssertEqual(PushRouting.coreLoopDestination(try XCTUnwrap(PushRouting.notification(from: digest, recipientID: nil))),
                       .init(route: .thisWeekend, id: nil))
    }

    func testUnknownKindsAndMissingIdsRouteNowhere() {
        XCTAssertNil(CoreLoops.route(kind: "new_message", data: ["thread_id": .string("t")]))
        XCTAssertNil(CoreLoops.route(kind: "event_reminder_day", data: ["event_id": .string("e1")]))
        XCTAssertNil(CoreLoops.route(kind: "event_recap", data: [:]))
        XCTAssertEqual(CoreLoops.route(kind: "follow_alert", data: ["count": .int(2)]), .init(route: .following, id: nil))
        XCTAssertEqual(CoreLoops.route(kind: "follow_alert", data: ["event_id": .string("e9"), "count": .string("3")]), .init(route: .following, id: nil))
        XCTAssertEqual(CoreLoops.route(kind: "follow_alert", data: ["event_id": .string("e9")]), .init(route: .event, id: "e9"))
    }

    func testRunItAgainMatchesTheContract() throws {
        let vs = try XCTUnwrap(fixture()["runItAgain"] as? [[String: Any]])
        XCTAssertFalse(vs.isEmpty)
        for v in vs {
            let got = CoreLoops.runItAgainDate(eventDate: v["eventDate"] as? String, eventTime: v["eventTime"] as? String,
                                               today: try XCTUnwrap(v["today"] as? String))
            XCTAssertEqual(got.date, v["expectDate"] as? String, v["case"] as? String ?? "")
            XCTAssertEqual(got.time, v["expectTime"] as? String, v["case"] as? String ?? "")
        }
    }

    func testRunItAgainNeverInThePastNorTooSoon() {
        XCTAssertEqual(CoreLoops.runItAgainDate(eventDate: "2027-03-09", eventTime: "09:15:00", today: "2027-03-08").date, "2027-03-16")
        XCTAssertEqual(CoreLoops.runItAgainDate(eventDate: "2027-03-09", eventTime: "09:15:00", today: "2027-03-08").time, "09:15")
        XCTAssertEqual(CoreLoops.runItAgainDate(eventDate: "2027-03-02", eventTime: "19:00", today: "2027-03-08").date, "2027-03-16")
        XCTAssertEqual(CoreLoops.runItAgainDate(eventDate: nil, eventTime: nil, today: "2027-03-08").date, "2027-03-10")
        XCTAssertNil(CoreLoops.runItAgainDate(eventDate: nil, eventTime: nil, today: "2027-03-08").time)
    }

    func testFeedbackLimitsMatchTheContract() throws {
        let f = try XCTUnwrap(fixture()["feedback"] as? [String: Any])
        XCTAssertEqual(f["noteMax"] as? Int, CoreLoops.noteMax)
        XCTAssertEqual(f["ratings"] as? [Int], CoreLoops.ratings)
        XCTAssertEqual(f["openDays"] as? Int, CoreLoops.openDays)
        XCTAssertEqual(f["hostMinResponses"] as? Int, CoreLoops.hostMinResponses)
        XCTAssertTrue(CoreLoops.canSaveFeedback(rating: 1, note: ""))
        XCTAssertTrue(CoreLoops.canSaveFeedback(rating: -1, note: String(repeating: "x", count: CoreLoops.noteMax)))
        XCTAssertFalse(CoreLoops.canSaveFeedback(rating: -1, note: String(repeating: "x", count: CoreLoops.noteMax + 1)))
        XCTAssertFalse(CoreLoops.canSaveFeedback(rating: 0, note: ""))
        XCTAssertFalse(CoreLoops.canSaveFeedback(rating: nil, note: ""))
        // Counted like Postgres length() and web's [...note].length: one code point per emoji.
        XCTAssertEqual(CoreLoops.noteLength("👍🏽ok"), 4)
        XCTAssertEqual(CoreLoops.noteLength(String(repeating: "😀", count: 500)), 500)
        XCTAssertEqual(CoreLoops.noteLength(CoreLoops.clampNote(String(repeating: "😀", count: 501))), 500)
        XCTAssertEqual(CoreLoops.clampNote("short"), "short")
    }

    func testFeedbackWindow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(CoreLoops.feedbackWindowOpen(startsAt: start, now: start.addingTimeInterval(14 * 86_400)))
        XCTAssertFalse(CoreLoops.feedbackWindowOpen(startsAt: start, now: start.addingTimeInterval(14 * 86_400 + 1)))
        XCTAssertTrue(CoreLoops.feedbackWindowOpen(startsAt: nil, now: start))
        XCTAssertEqual(CoreLoops.feedbackErrorText("NOT_OPEN").en, "Feedback for this event is closed.")
    }

    func testHostFeedbackViewHidesBelowThree() {
        XCTAssertTrue(CoreLoops.hostFeedbackView(.init(responses: 2, hidden: true)).hidden)
        XCTAssertTrue(CoreLoops.hostFeedbackView(nil).hidden)
        XCTAssertTrue(CoreLoops.hostFeedbackView(.init(responses: 2, hidden: false, up: 2, down: 0, notes: ["x"])).hidden)
        let v = CoreLoops.hostFeedbackView(.init(responses: 3, hidden: false, up: 2, down: 1, notes: ["  Great ", ""]))
        XCTAssertEqual(v, .init(hidden: false, responses: 3, up: 2, down: 1, notes: ["Great"]))
    }

    func testHostRecapDecodes() throws {
        let json = #"{"success":true,"event_id":"e1","status":"ended","capacity":20,"confirmed_seats":12,"checked_in":9,"new_followers":3,"repeat_guests":2,"photos":5,"feedback":{"responses":1,"hidden":true}}"#
        let r = try JSONDecoder().decode(CoreLoops.HostRecap.self, from: Data(json.utf8))
        XCTAssertEqual(r.confirmedSeats, 12)
        XCTAssertEqual(r.capacity, 20)
        XCTAssertEqual(r.checkedIn, 9)
        XCTAssertEqual(r.newFollowers, 3)
        XCTAssertEqual(r.repeatGuests, 2)
        XCTAssertEqual(r.photos, 5)
        XCTAssertTrue(CoreLoops.hostFeedbackView(r.feedback).hidden)
    }
}

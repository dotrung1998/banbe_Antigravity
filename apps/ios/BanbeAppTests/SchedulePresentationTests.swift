import XCTest
@testable import BanbeApp

final class SchedulePresentationTests: XCTestCase {
    private let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!
    /// 2026-11-01 00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_491_200)

    private func cal(_ tz: TimeZone, firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.firstWeekday = firstWeekday
        return c
    }

    private func date(_ tz: TimeZone, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func ev(_ key: String, _ start: Date?, end: Date? = nil, cancelled: Bool = false, ended: Bool = false,
                    invite: Bool = false, soldOut: Bool = false) -> ScheduleEventInfo {
        ScheduleEventInfo(key: key, title: key.uppercased(), start: start, end: end, cancelled: cancelled,
                          ended: ended, inviteOnly: invite, soldOut: soldOut)
    }

    private func booking(_ key: String, status: String = "confirmed", pay: String = "confirmed",
                         hold: Date? = nil, gifted: Bool = false) -> ScheduleBookingInput {
        ScheduleBookingInput(eventKey: key, status: status, paymentState: pay, holdExpiresAt: hold, giftedAway: gifted)
    }

    // MARK: sources

    func testBookingSourceRules() {
        XCTAssertEqual(SchedulePresentation.source(for: booking("a"), now: now), .booked)
        XCTAssertEqual(SchedulePresentation.source(for: booking("a", status: "attended"), now: now), .booked)
        XCTAssertEqual(SchedulePresentation.source(for: booking("a", status: "pending", pay: "pending_verification"), now: now), .awaiting)
        XCTAssertEqual(SchedulePresentation.source(for: booking("a", status: "pending", pay: "holding", hold: now.addingTimeInterval(600)), now: now), .holding)
        XCTAssertNil(SchedulePresentation.source(for: booking("a", status: "pending", pay: "holding", hold: now.addingTimeInterval(-1)), now: now),
                     "an expired hold is not a plan")
        XCTAssertNil(SchedulePresentation.source(for: booking("a", status: "pending", pay: "holding", hold: nil), now: now))
        XCTAssertNil(SchedulePresentation.source(for: booking("a", status: "cancelled"), now: now))
        XCTAssertNil(SchedulePresentation.source(for: booking("a", pay: "expired"), now: now))
        XCTAssertNil(SchedulePresentation.source(for: booking("a", gifted: true), now: now), "a ticket gifted away is the recipient's plan")
    }

    func testDedupeKeepsStrongestSourceAndListsAll() {
        let t = date(hcm, 2026, 11, 3, 19)
        let r = SchedulePresentation.mySchedule(
            bookings: [booking("x"), booking("y", status: "pending", pay: "pending_verification")],
            hostedKeys: ["x", "h"], addedKeys: ["x", "y", "m"],
            events: ["x": ev("x", t), "y": ev("y", t.addingTimeInterval(60)), "h": ev("h", t.addingTimeInterval(120)), "m": ev("m", t.addingTimeInterval(180))],
            now: now)
        XCTAssertEqual(r.items.map(\.id), ["x", "y", "h", "m"])
        XCTAssertEqual(r.items.map(\.source), [.booked, .awaiting, .hosting, .added])
        XCTAssertEqual(r.items[0].sources, [.booked, .hosting, .added])
    }

    func testCancelledEventsLeaveAndUndatedAreCountedNotHidden() {
        let r = SchedulePresentation.mySchedule(
            bookings: [booking("c"), booking("u")], hostedKeys: [], addedKeys: ["missing"],
            events: ["c": ev("c", now.addingTimeInterval(3600), cancelled: true), "u": ev("u", nil)], now: now)
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertEqual(r.undatedCount, 1)
    }

    func testEndedBookedEventStaysAsHistory() {
        let past = now.addingTimeInterval(-2 * 86_400)
        let r = SchedulePresentation.mySchedule(bookings: [booking("p")], hostedKeys: [], addedKeys: [],
                                                events: ["p": ev("p", past, ended: true)], now: now)
        XCTAssertEqual(r.items.map(\.id), ["p"])
    }

    func testFavoritesAreNotASource() {
        // There is no favorites parameter at all: saved ≠ planning to go.
        let r = SchedulePresentation.mySchedule(bookings: [], hostedKeys: [], addedKeys: [],
                                                events: ["f": ev("f", now.addingTimeInterval(3600))], now: now)
        XCTAssertTrue(r.items.isEmpty)
    }

    // MARK: discover

    func testDiscoverOnlyUpcomingReservablePublicNotMine() {
        let soon = now.addingTimeInterval(3600)
        let list = SchedulePresentation.discover(events: [
            ev("ok", soon), ev("past", now.addingTimeInterval(-60)), ev("cx", soon, cancelled: true),
            ev("end", soon, ended: true), ev("inv", soon, invite: true), ev("full", soon, soldOut: true),
            ev("mine", soon), ev("nodate", nil),
        ], excluding: ["mine"], now: now)
        XCTAssertEqual(list.map(\.key), ["ok"])
    }

    func testCanAdd() {
        XCTAssertTrue(SchedulePresentation.canAdd(ev("a", now.addingTimeInterval(60)), now: now))
        XCTAssertFalse(SchedulePresentation.canAdd(ev("a", now.addingTimeInterval(-60)), now: now))
        XCTAssertFalse(SchedulePresentation.canAdd(ev("a", now.addingTimeInterval(60), cancelled: true), now: now))
        XCTAssertFalse(SchedulePresentation.canAdd(ev("a", nil), now: now))
    }

    // MARK: day grouping

    func testSameInstantLandsOnTheRightDayPerZone() {
        // 2026-11-03 02:00 in Ho Chi Minh = 2026-11-02 11:00 in Los Angeles.
        let e = ev("x", date(hcm, 2026, 11, 3, 2))
        XCTAssertTrue(SchedulePresentation.occurs(e, on: date(hcm, 2026, 11, 3, 12), calendar: cal(hcm)))
        XCTAssertFalse(SchedulePresentation.occurs(e, on: date(hcm, 2026, 11, 2, 12), calendar: cal(hcm)))
        XCTAssertTrue(SchedulePresentation.occurs(e, on: date(la, 2026, 11, 2, 12), calendar: cal(la)))
    }

    func testDaylightSavingFallBackDayIsHandled() {
        // US fall-back: 2026-11-01 is a 25-hour day in Los Angeles.
        let c = cal(la)
        let lateOnFallBackDay = date(la, 2026, 11, 1, 23, 30)
        let e = ev("dst", lateOnFallBackDay)
        XCTAssertTrue(SchedulePresentation.occurs(e, on: date(la, 2026, 11, 1, 9), calendar: c))
        XCTAssertFalse(SchedulePresentation.occurs(e, on: date(la, 2026, 11, 2, 9), calendar: c))
    }

    func testOvernightWithRealEndShowsOnBothDaysMissingEndOnlyOnStart() {
        let start = date(hcm, 2026, 11, 3, 22)
        let overnight = ev("o", start, end: start.addingTimeInterval(5 * 3600))
        XCTAssertTrue(SchedulePresentation.occurs(overnight, on: date(hcm, 2026, 11, 3, 9), calendar: cal(hcm)))
        XCTAssertTrue(SchedulePresentation.occurs(overnight, on: date(hcm, 2026, 11, 4, 9), calendar: cal(hcm)))
        let open = ev("n", start)
        XCTAssertFalse(SchedulePresentation.occurs(open, on: date(hcm, 2026, 11, 4, 9), calendar: cal(hcm)))
        let badEnd = ev("b", start, end: start.addingTimeInterval(-60))
        XCTAssertFalse(SchedulePresentation.occurs(badEnd, on: date(hcm, 2026, 11, 4, 9), calendar: cal(hcm)),
                       "an end before the start is ignored")
    }

    func testWeekHonorsFirstWeekday() {
        let wed = date(hcm, 2026, 11, 4, 12) // a Wednesday
        let mondayWeek = SchedulePresentation.week(containing: wed, calendar: cal(hcm, firstWeekday: 2))
        let sundayWeek = SchedulePresentation.week(containing: wed, calendar: cal(hcm, firstWeekday: 1))
        XCTAssertEqual(mondayWeek.count, 7)
        XCTAssertEqual(cal(hcm).component(.weekday, from: mondayWeek[0]), 2)
        XCTAssertEqual(cal(hcm).component(.weekday, from: sundayWeek[0]), 1)
        XCTAssertTrue(mondayWeek.contains { cal(hcm).isDate($0, inSameDayAs: wed) })
    }

    // MARK: proximity (banbe data only)

    func testProximityNeverClaimsOverlapWithoutEndTimes() {
        let t = date(hcm, 2026, 11, 3, 19)
        let plan = ScheduleItem(event: ev("p", t), source: .booked, sources: [.booked])
        XCTAssertEqual(SchedulePresentation.proximity(of: ev("c", t.addingTimeInterval(90 * 60)), to: [plan]), .startsNear(count: 1))
        XCTAssertEqual(SchedulePresentation.proximity(of: ev("c", t.addingTimeInterval(2 * 3600)), to: [plan]), .none)
        XCTAssertEqual(SchedulePresentation.proximity(of: ev("p", t), to: [plan]), .none, "never conflicts with itself")
    }

    func testRealOverlapOnlyWithRealEnds() {
        let t = date(hcm, 2026, 11, 3, 19)
        let plan = ScheduleItem(event: ev("p", t, end: t.addingTimeInterval(3 * 3600)), source: .booked, sources: [.booked])
        let c = ev("c", t.addingTimeInterval(2.5 * 3600), end: t.addingTimeInterval(4 * 3600))
        XCTAssertEqual(SchedulePresentation.proximity(of: c, to: [plan]), .overlaps(count: 1))
        let after = ev("a", t.addingTimeInterval(3 * 3600), end: t.addingTimeInterval(4 * 3600))
        XCTAssertEqual(SchedulePresentation.proximity(of: after, to: [plan]), .none, "touching ends do not overlap")
    }

    func testProximityCopy() {
        let en: (String, String) -> String = { _, e in e }
        XCTAssertEqual(SchedulePresentation.proximityText(.startsNear(count: 1), T: en), "Starts within 2 hours of 1 plan")
        XCTAssertEqual(SchedulePresentation.proximityText(.overlaps(count: 2), T: en), "Overlaps with 2 plans")
        XCTAssertNil(SchedulePresentation.proximityText(.none, T: en))
    }

    // MARK: formatting

    func testVenueTimeNoteOnlyWhenZonesDiffer() {
        let e = ScheduleEventInfo(key: "v", title: "V", start: date(hcm, 2026, 11, 3, 19), timeZone: hcm)
        XCTAssertNil(SchedulePresentation.venueTimeNote(e, agendaZone: hcm, vi: false))
        XCTAssertEqual(SchedulePresentation.venueTimeNote(e, agendaZone: la, vi: false), "7:00 PM at the venue")
        XCTAssertEqual(SchedulePresentation.venueTimeNote(e, agendaZone: la, vi: true), "19:00 giờ tại nơi tổ chức")
    }

    func testDayBucketsForAnalytics() {
        let c = cal(hcm)
        let today = date(hcm, 2026, 11, 3, 10)
        XCTAssertEqual(SchedulePresentation.dayBucket(today, today: today, calendar: c), "today")
        XCTAssertEqual(SchedulePresentation.dayBucket(today.addingTimeInterval(-86_400), today: today, calendar: c), "past")
        XCTAssertEqual(SchedulePresentation.dayBucket(today.addingTimeInterval(3 * 86_400), today: today, calendar: c), "next7")
        XCTAssertEqual(SchedulePresentation.dayBucket(today.addingTimeInterval(30 * 86_400), today: today, calendar: c), "later")
    }
}

final class InAppCalendarStoreTests: XCTestCase {
    private func store() throws -> InAppCalendarStore {
        InAppCalendarStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "test.schedule.\(UUID().uuidString)")))
    }

    func testAddIsIdempotentAndReversible() throws {
        let s = try store(), uid = UUID()
        XCTAssertEqual(s.add("e1", uid: uid), .added)
        XCTAssertEqual(s.add("e1", uid: uid), .alreadyAdded)
        XCTAssertEqual(s.keys(uid: uid), ["e1"])
        XCTAssertEqual(s.remove("e1", uid: uid), .removed)
        XCTAssertEqual(s.remove("e1", uid: uid), .notPresent)
        XCTAssertTrue(s.keys(uid: uid).isEmpty)
    }

    func testNamespacedPerAccount() throws {
        let s = try store(), a = UUID(), b = UUID()
        s.add("e1", uid: a)
        XCTAssertTrue(s.contains("e1", uid: a))
        XCTAssertFalse(s.contains("e1", uid: b), "another account on this device never sees it")
        s.clear(uid: a)
        XCTAssertFalse(s.contains("e1", uid: a))
    }

    func testPruneDropsIneligible() throws {
        let s = try store(), uid = UUID()
        s.add("keep", uid: uid); s.add("gone", uid: uid)
        s.prune(uid: uid) { $0 == "keep" }
        XCTAssertEqual(s.keys(uid: uid), ["keep"])
    }

    func testStoresOnlyIdsAndTimes() throws {
        let d = try XCTUnwrap(UserDefaults(suiteName: "test.schedule.\(UUID().uuidString)"))
        let s = InAppCalendarStore(defaults: d), uid = UUID()
        s.add("evt-1", uid: uid, now: Date(timeIntervalSince1970: 0))
        let raw = try XCTUnwrap(d.data(forKey: InAppCalendarStore.key(uid)))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [[String: Any]])
        XCTAssertEqual(Set(obj[0].keys), ["eventKey", "addedAt"])
    }
}

@MainActor
final class ScheduleAppStateTests: XCTestCase {
    func testAddToBanbeScheduleAvoidsDuplicatesWithHostedAndNeedsSignIn() throws {
        let app = AppState()
        let summaryJSON = """
        [{"id":"fx-h","name":"Hosted","status":"live","visibility":"public","organizer_id":"org",
          "starts_at":"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(86_400)))"},
         {"id":"fx-m","name":"Manual","status":"live","visibility":"public",
          "starts_at":"\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86_400)))"}]
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([RealEventSummary].self, from: Data(summaryJSON.utf8))
        let events = rows.map { CatalogEvent.fromReal($0) }
        for e in events { app.realEventsByID[e.key] = e }

        // Signed out: routes to Login, saves nothing.
        app.screen = .event
        XCTAssertEqual(app.addToBanbeSchedule(events[1]), .needsSignIn)
        XCTAssertEqual(app.screen, .login)
        XCTAssertEqual(app.authReturnScreen, .event)

        let uid = UUID()
        defer { InAppCalendarStore().clear(uid: uid) }
        app.userID = uid
        app.myOrganizerID = "org"
        app.myOrgEventKeys = ["fx-h"]
        app.myOrgEventOrganizerID = ["fx-h": "org"]
        app.myOrgEventSummaries = rows.filter { $0.id == "fx-h" }

        XCTAssertEqual(app.scheduleSource(for: "fx-h"), .hosting)
        XCTAssertEqual(app.addToBanbeSchedule(events[0]), .alreadyThere, "hosting already puts it on the schedule")
        XCTAssertEqual(app.addToBanbeSchedule(events[1]), .added)
        XCTAssertEqual(app.addToBanbeSchedule(events[1]), .alreadyThere)
        XCTAssertEqual(app.scheduleAddedKeys, ["fx-m"])
        app.removeFromBanbeSchedule("fx-m")
        XCTAssertFalse(app.isInMySchedule("fx-m"))
    }

    func testSignOutStateResetHidesPreviousAccountsAdditions() {
        let app = AppState()
        let uid = UUID()
        defer { InAppCalendarStore().clear(uid: uid) }
        InAppCalendarStore().add("e", uid: uid)
        app.userID = uid
        app.refreshScheduleAdded()
        XCTAssertEqual(app.scheduleAddedKeys, ["e"])
        app.resetScheduleState()
        XCTAssertTrue(app.scheduleAddedKeys.isEmpty)
        app.userID = UUID()
        app.refreshScheduleAdded()
        XCTAssertTrue(app.scheduleAddedKeys.isEmpty, "a different account never inherits them")
    }
}

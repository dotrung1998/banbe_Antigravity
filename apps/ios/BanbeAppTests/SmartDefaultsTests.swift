import XCTest
@testable import BanbeApp

/// Note 48 — smart defaults, progress maths and form gaps.
@MainActor
final class SmartDefaultsTests: XCTestCase {

    private var vn: Calendar { SmartDefaults.vnCalendar }

    /// A Vietnam-time instant from "yyyy-MM-dd HH:mm".
    private func vnInstant(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func vnDay(_ d: Date) -> String { AppState.vnDateFormatter.string(from: d) }
    private func vnTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: nextWeekday

    func testNextSaturdayIsAtLeastTwoDaysOut() {
        // Thu 2026-10-15 → Sat 17th is exactly 2 days out.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-10-15 10:00"))), "2026-10-17")
        // Fri 2026-10-16 → Sat 17th is only 1 day out, so the following Sat.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-10-16 10:00"))), "2026-10-24")
        // Sat itself → next Sat.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-10-17 10:00"))), "2026-10-24")
    }

    func testNextWeekdayUsesVietnamDayNotDeviceDay() {
        // 23:30 Fri in Vietnam is still Friday there even though it is
        // Friday afternoon in UTC; the answer must follow Vietnam's calendar.
        let lateFriday = vnInstant("2026-10-16 23:30")
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: lateFriday)), "2026-10-24")
        // 00:30 Thu in Vietnam (Wed in UTC) → Sat 17th.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-10-15 00:30"))), "2026-10-17")
    }

    func testNextWeekdayCrossesMonthAndYearEnds() {
        // Wed 2026-12-30 → Sat 2027-01-02.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-12-30 09:00"))), "2027-01-02")
        // Fri 2026-10-30 (min 2 days → Sun 1st Nov) → Sat 7th Nov.
        XCTAssertEqual(vnDay(SmartDefaults.nextWeekday(7, after: vnInstant("2026-10-30 09:00"))), "2026-11-07")
    }

    // MARK: event draft defaults

    func testFirstEventDefaultsNeverInventAPrice() {
        let d = SmartDefaults.eventDraftDefaults(last: nil, now: vnInstant("2026-10-15 10:00"))
        XCTAssertNil(d.price, "a first event's price is never pre-filled")
        XCTAssertEqual(d.seats, 0, "capacity is never pre-filled")
        XCTAssertEqual(vnTime(d.time), "19:00")
        XCTAssertEqual(vnDay(d.date), "2026-10-17")
        XCTAssertEqual(d.categories, [])
        XCTAssertNil(d.sourceName)
    }

    func testReturningHostCopiesTheirLastEvent() {
        // Last event on a Friday at 18:30, 250k, 20 seats, music.
        let last = LastEventSnapshot(name: "Jazz night", eventDate: "2026-09-25", eventTime: "18:30:00",
                                     priceVnd: 250_000, capacity: 20, catKey: "music")
        let d = SmartDefaults.eventDraftDefaults(last: last, now: vnInstant("2026-10-15 10:00"))
        XCTAssertEqual(vnDay(d.date), "2026-10-23", "same weekday (Friday), at least 2 days out")
        XCTAssertEqual(vnTime(d.time), "18:30")
        XCTAssertEqual(d.price, "250000")
        XCTAssertEqual(d.seats, 0, "capacity is never copied either")
        XCTAssertEqual(d.categories, ["music"])
        XCTAssertEqual(d.sourceName, "Jazz night")
    }

    func testReturningHostWithMissingFieldsFallsBack() {
        let last = LastEventSnapshot(name: "Draft", eventDate: nil, eventTime: "19:30",
                                     priceVnd: nil, capacity: nil, catKey: nil)
        let d = SmartDefaults.eventDraftDefaults(last: last, now: vnInstant("2026-10-15 10:00"))
        XCTAssertEqual(vnDay(d.date), "2026-10-17", "no date → Saturday")
        XCTAssertEqual(vnTime(d.time), "19:30", "HH:mm is accepted")
        XCTAssertNil(d.price)
        XCTAssertEqual(d.seats, 0)
    }

    func testDateQuickPicksAreOrderedAndInTheFuture() {
        let now = vnInstant("2026-10-15 10:00") // Thursday
        let picks = SmartDefaults.dateQuickPicks(now: now)
        XCTAssertEqual(picks.map(\.label.en), ["Tomorrow", "This Fri", "This Sat", "Next Sat"])
        XCTAssertEqual(picks.map { vnDay($0.date) }, ["2026-10-16", "2026-10-16", "2026-10-17", "2026-10-24"])
    }

    // MARK: contrast hint

    func testSimilarPriceRangeNeedsEnoughPaidSamples() {
        XCTAssertNil(SmartDefaults.similarPriceRange([0, 0, 100_000, 200_000, 300_000, 400_000]),
                     "free events don't count toward the minimum")
        let range = SmartDefaults.similarPriceRange([100_000, 200_000, 300_000, 400_000, 500_000, 900_000, 0])
        XCTAssertEqual(range, 200_000...500_000, "middle half, ignoring the outlier")
    }

    // MARK: gaps

    func testRefundAccountGapOrder() {
        XCTAssertEqual(SmartDefaults.refundAccountGap(bank: " ", account: "1", holder: "A", confirmed: true), .bank)
        XCTAssertEqual(SmartDefaults.refundAccountGap(bank: "ACB", account: "", holder: "A", confirmed: true), .account)
        XCTAssertEqual(SmartDefaults.refundAccountGap(bank: "ACB", account: "1", holder: "", confirmed: true), .holder)
        XCTAssertEqual(SmartDefaults.refundAccountGap(bank: "ACB", account: "1", holder: "A", confirmed: false), .confirm)
        XCTAssertNil(SmartDefaults.refundAccountGap(bank: "ACB", account: "1", holder: "A", confirmed: true))
    }

    func testAttendeeGapMatchesIsComplete() {
        var a = AttendeeDraft(); a.name = "An"; a.useProfileDOB = true
        var b = AttendeeDraft(); b.name = "B"
        XCTAssertEqual(SmartDefaults.attendeeGap([a, b]), .name(ticket: 2))
        b.name = "Bình"
        XCTAssertEqual(SmartDefaults.attendeeGap([a, b]), .dob(ticket: 2))
        b.dob = Date(timeIntervalSince1970: 0)
        b.email = "not-an-email"
        XCTAssertEqual(SmartDefaults.attendeeGap([a, b]), .email(ticket: 2))
        b.email = ""
        XCTAssertNil(SmartDefaults.attendeeGap([a, b]))
        XCTAssertTrue([a, b].allSatisfy(\.isComplete), "no gap ⇔ every draft complete")
    }

    // MARK: progress

    func testStepProgressHeadStart() {
        // Onboarding: account done + 5 questions → question 1 opens at 17%, not 0.
        XCTAssertEqual(StepProgressModel.percent(current: 1, total: 6), 17)
        // Booking journey: event picked → 25% on Reserve.
        XCTAssertEqual(StepProgressModel.percent(current: 1, total: 4), 25)
        XCTAssertEqual(StepProgressModel.percent(current: 4, total: 4), 100)
        XCTAssertEqual(StepProgressModel.percent(current: 9, total: 4), 100, "clamped")
        XCTAssertEqual(StepProgressModel.percent(current: 1, total: 0), 0)
    }

    // MARK: AppState create defaults

    func testGoCreateAppliesAndStartBlankClearsDefaults() {
        let app = AppState()
        app.myOrgEventSummaries = []
        app.applyCreateDefaults()
        XCTAssertNotNil(app.createEventDate)
        XCTAssertEqual(app.createSeats, "", "seats start empty (0)")
        XCTAssertEqual(app.createPrice, "")
        XCTAssertTrue(app.createDraftMatchesAppliedDefaults)

        app.createSeats = "30"
        XCTAssertFalse(app.createDraftMatchesAppliedDefaults, "an edited field is no longer a default")

        app.clearCreateDefaults()
        XCTAssertNil(app.createEventDate)
        XCTAssertNil(app.createEventTime)
        XCTAssertEqual(app.createSeats, "")
        XCTAssertNil(app.createAppliedDefaults)
    }

    func testEditingAnEventNeverAppliesDefaults() {
        let app = AppState()
        app.createEditEventId = "evt-1"
        app.createSeats = "8"
        app.applyCreateDefaults()
        XCTAssertEqual(app.createSeats, "8")
        XCTAssertNil(app.createAppliedDefaults)
    }
}

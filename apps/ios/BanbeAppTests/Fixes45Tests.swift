import XCTest
@testable import BanbeApp

/// Note 45 fixes: month view logic, Schedule snapshot cache, dock hiding while a
/// sheet is open, and the removed in-app glass setting.
@MainActor
final class Fixes45Tests: XCTestCase {
    private let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    private func cal(_ firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = hcm
        c.firstWeekday = firstWeekday
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    private func ev(_ key: String, _ start: Date) -> ScheduleEventInfo {
        ScheduleEventInfo(key: key, title: key.uppercased(), start: start)
    }

    // MARK: month grid

    func testMonthGridIsWholeWeeksStartingOnFirstWeekday() {
        // October 2026 starts on a Thursday and has 31 days.
        let monday = SchedulePresentation.monthGrid(containing: date(2026, 10, 17), calendar: cal(2))
        XCTAssertEqual(monday.count, 5)
        XCTAssertTrue(monday.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal().component(.weekday, from: monday[0][0].date), 2, "rows start on the locale's first weekday")
        XCTAssertFalse(monday[0][0].inMonth, "Mon 28 Sep belongs to the previous month")
        XCTAssertTrue(monday[0][3].inMonth, "Thu 1 Oct")
        XCTAssertEqual(monday.joined().filter(\.inMonth).count, 31)

        let sunday = SchedulePresentation.monthGrid(containing: date(2026, 10, 17), calendar: cal(1))
        XCTAssertEqual(cal().component(.weekday, from: sunday[0][0].date), 1)
        XCTAssertEqual(sunday.joined().filter(\.inMonth).count, 31)
    }

    func testMonthGridFebruaryLeapAndCoversEveryDayOnce() {
        let feb = SchedulePresentation.monthGrid(containing: date(2028, 2, 10), calendar: cal())
        XCTAssertEqual(feb.joined().filter(\.inMonth).count, 29)
        let days = feb.joined().map(\.date)
        XCTAssertEqual(Set(days).count, days.count, "no day appears twice")
    }

    func testMonthMathAcrossYearBoundary() {
        let c = cal()
        let dec = date(2026, 12, 20)
        let jan = SchedulePresentation.addMonths(1, to: dec, calendar: c)
        XCTAssertEqual(c.component(.year, from: jan), 2027)
        XCTAssertEqual(c.component(.month, from: jan), 1)
        XCTAssertEqual(c.component(.day, from: jan), 1)
        XCTAssertEqual(c.component(.month, from: SchedulePresentation.addMonths(-12, to: dec, calendar: c)), 12)
    }

    func testDayCountsAndAgendaOnlyContainRealEvents() {
        let c = cal()
        let events = [ev("a", date(2026, 10, 19, 13)), ev("b", date(2026, 10, 19, 9)), ev("c", date(2026, 10, 21)), ev("other", date(2026, 11, 3))]
        let grid = SchedulePresentation.monthGrid(containing: date(2026, 10, 1), calendar: c)
        let counts = SchedulePresentation.dayCounts(events, grid: grid, calendar: c)
        XCTAssertEqual(counts[c.startOfDay(for: date(2026, 10, 19))], 2)
        XCTAssertEqual(counts[c.startOfDay(for: date(2026, 10, 21))], 1)
        XCTAssertNil(counts[c.startOfDay(for: date(2026, 10, 20))], "no fabricated activity on empty days")

        let agenda = SchedulePresentation.monthAgenda(events, month: date(2026, 10, 1), calendar: c)
        XCTAssertEqual(agenda.map { c.component(.day, from: $0.day) }, [19, 21])
        XCTAssertEqual(agenda[0].events.map(\.key), ["b", "a"], "time order within a day")
        XCTAssertTrue(SchedulePresentation.monthAgenda([], month: date(2026, 10, 1), calendar: c).isEmpty)
    }

    func testEmptyMonthHasNoCounts() {
        let grid = SchedulePresentation.monthGrid(containing: date(2026, 10, 1), calendar: cal())
        XCTAssertTrue(SchedulePresentation.dayCounts([], grid: grid, calendar: cal()).isEmpty)
    }

    // MARK: dock hides while a sheet is open

    func testDockHidesWhileAnySheetIsOpenAndReturnsWhenLastCloses() {
        let overlay = BottomTabBarOverlay.shared
        XCTAssertFalse(overlay.hasOpenSheets)
        overlay.setSheetOpen("schedule.month", true)
        overlay.setSheetOpen("other", true)
        XCTAssertTrue(overlay.hasOpenSheets)
        overlay.setSheetOpen("schedule.month", false)
        XCTAssertTrue(overlay.hasOpenSheets, "still hidden while another sheet is up")
        overlay.setSheetOpen("other", false)
        XCTAssertFalse(overlay.hasOpenSheets)
        overlay.setSheetOpen("schedule.month", false) // closing something never opened is harmless
        XCTAssertFalse(overlay.hasOpenSheets)
    }

    // MARK: schedule snapshot cache

    func testSnapshotIsCachedUntilAnInputChangesAndIsFast() {
        let app = AppState()
        app.userID = UUID()
        let base = Date().addingTimeInterval(86_400)
        let iso = ISO8601DateFormatter()
        let rows = (0..<300).map { i in
            ["id": "e\(i)", "name": "Event \(i)", "status": "live", "visibility": "public", "cat_key": "music",
             "price_vnd": 0, "country_code": "VN", "seats_remaining": 5, "capacity": 9,
             "starts_at": iso.string(from: base.addingTimeInterval(Double(i) * 3600))] as [String: Any]
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let summaries = try! decoder.decode([RealEventSummary].self, from: JSONSerialization.data(withJSONObject: rows))
        app.discoveryEvents = summaries.map { CatalogEvent.fromReal($0) }
        // The real loader also caches each event by id; "added" plans resolve through it.
        for e in app.discoveryEvents { app.realEventsByID[e.key] = e }

        let first = app.scheduleSnapshot
        XCTAssertEqual(first.discover.count, 300)
        let key = app.scheduleInputsKey()
        XCTAssertEqual(app.scheduleInputsKey(), key, "stable while nothing changed")
        XCTAssertNotNil(app.scheduleCache)

        // Cache hit: many reads must be far cheaper than recomputing each time.
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 { _ = app.scheduleSnapshot }
        let perRead = (CFAbsoluteTimeGetCurrent() - start) / 50
        XCTAssertLessThan(perRead, 0.02, "a cached read with 300 events should take milliseconds, got \(perRead)s")

        app.scheduleAddedKeys = ["e1"]
        XCTAssertNotEqual(app.scheduleInputsKey(), key, "an input change invalidates the cache")
        XCTAssertTrue(app.scheduleSnapshot.mine.items.contains { $0.id == "e1" })
        XCTAssertFalse(app.scheduleSnapshot.discover.contains { $0.key == "e1" }, "a plan leaves Discover")
    }

    func testResetClearsCacheAndLoadThrottle() {
        let app = AppState()
        app.scheduleCache = (1, ScheduleSnapshot(mine: .init(items: [], undatedCount: 0), discover: []))
        app.scheduleLoadedAt = Date()
        app.resetScheduleState()
        XCTAssertNil(app.scheduleCache)
        XCTAssertNil(app.scheduleLoadedAt)
    }

    // MARK: no in-app glass setting

    func testStaleGlassOpacityValueIsRemovedOnLaunch() {
        UserDefaults.standard.set(0.4, forKey: "banbe.glassOpacity")
        _ = AppState()
        XCTAssertNil(UserDefaults.standard.object(forKey: "banbe.glassOpacity"))
    }
}

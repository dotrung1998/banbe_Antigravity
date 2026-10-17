import XCTest

/// Note 45 fixes, exercised on the REAL RootView (dock, headers, swipe gestures)
/// with seeded signed-in state and no network (`-uiFixture shell.*`).
final class ShellFixtureUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ variant: String, lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", lang, "-uiTesting", "1",
                                "-banbe.onboarded", "YES"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Horizontal drag between two normalized points of the window.
    private func swipe(_ app: XCUIApplication, y: CGFloat, from x0: CGFloat, to x1: CGFloat) {
        let w = app.windows.firstMatch
        let a = w.coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
        let b = w.coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y))
        a.press(forDuration: 0.05, thenDragTo: b)
    }

    // MARK: 2 — Home keeps its title

    func testHomeTitleStaysBesideTheLogoWithBellAndSearch() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20), "the word Home must stay in the header")
        XCTAssertEqual(el(app, "home.title").label, "Home")
        XCTAssertTrue(el(app, "home.notifications").exists)
        XCTAssertTrue(el(app, "home.searchFab").exists)
        XCTAssertTrue(app.images["banbe"].firstMatch.exists)
        // Title and the two controls must not overlap or run off-screen.
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(el(app, "home.searchFab").frame.maxX, screen.maxX)
        XCTAssertLessThan(el(app, "home.title").frame.maxX, el(app, "home.notifications").frame.minX)
    }

    func testHomeTitleVietnamese() {
        let app = launch("home", lang: "vi")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        XCTAssertEqual(el(app, "home.title").label, "Nhà")
    }

    // MARK: 3 — Schedule

    func testScheduleHasLogoBeforeTitleAndDockIsFive() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.title").waitForExistence(timeout: 20))
        XCTAssertTrue(app.images["banbe"].firstMatch.exists, "wordmark before the title")
        XCTAssertLessThan(app.images["banbe"].firstMatch.frame.minX, el(app, "schedule.title").frame.minX)
        for id in ["tab.home", "tab.map", "tab.schedule", "tab.inbox", "tab.profile"] {
            XCTAssertTrue(el(app, id).waitForExistence(timeout: 10), id)
        }
    }

    func testMonthViewHidesTheDockAndPicksAWeek() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 20))
        let before = el(app, "schedule.dayTitle").label
        el(app, "schedule.month").tap()
        XCTAssertTrue(el(app, "schedule.month.sheet").waitForExistence(timeout: 10))
        // The dock (its own window) is hidden while the sheet is up.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: el(app, "tab.home"))
        waitForExpectations(timeout: 6)
        XCTAssertTrue(el(app, "schedule.month.grid").exists)
        // Fixture events show as indicators/agenda: the real month agenda lists them.
        XCTAssertTrue(el(app, "schedule.month.event.fx-hosted").waitForExistence(timeout: 5))
        el(app, "schedule.month.next").tap()
        el(app, "schedule.month.prev").tap()
        // Pick a different day of the shown month: sheet closes, week view follows.
        el(app, "schedule.month.event.fx-hosted").tap()
        XCTAssertFalse(el(app, "schedule.month.sheet").waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 6), "dock returns after the sheet closes")
        XCTAssertEqual(el(app, "schedule.dayTitle").label, before)
    }

    func testMonthViewCloseButtonRestoresDock() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.month").waitForExistence(timeout: 20))
        el(app, "schedule.month").tap()
        XCTAssertTrue(el(app, "schedule.month.close").waitForExistence(timeout: 10))
        el(app, "schedule.month.close").tap()
        XCTAssertTrue(el(app, "tab.home").waitForExistence(timeout: 8))
    }

    func testSwipeOnTheWeekStripChangesWeekAndNeverTheSection() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.dayTitle").waitForExistence(timeout: 20))
        let before = el(app, "schedule.dayTitle").label
        let strip = el(app, "schedule.nextWeek").frame
        let y = (strip.midY) / app.windows.firstMatch.frame.height
        swipe(app, y: y, from: 0.85, to: 0.15)
        XCTAssertTrue(app.otherElements["screen.schedule"].waitForExistence(timeout: 3), "still on Schedule")
        XCTAssertFalse(app.otherElements["screen.inbox"].exists)
        XCTAssertNotEqual(el(app, "schedule.dayTitle").label, before, "the swipe moved a week")
        swipe(app, y: y, from: 0.15, to: 0.85)
        XCTAssertEqual(el(app, "schedule.dayTitle").label, before, "and back")
    }

    func testSwipeOverTheAgendaStillSwitchesDockSections() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.dayTitle").waitForExistence(timeout: 20))
        swipe(app, y: 0.62, from: 0.85, to: 0.15)
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 8),
                      "the exclusion is only the strip/mode picker, not the whole screen")
    }

    // MARK: 4 — Account tabs

    func testAccountTabsAreSwipeableAndStayInAccount() {
        let app = launch("account")
        XCTAssertTrue(el(app, "account.tab.personal").waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "account.tab.personal").isSelected)
        XCTAssertGreaterThanOrEqual(el(app, "account.tab.personal").frame.height, 44, "large touch targets")

        swipe(app, y: 0.115, from: 0.7, to: 0.2)
        XCTAssertTrue(el(app, "account.tab.host").waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "account.tab.host").isSelected)
        swipe(app, y: 0.115, from: 0.7, to: 0.2)
        XCTAssertTrue(el(app, "account.tab.admin").isSelected)
        // Past the last tab: nothing happens, and it never leaves Account.
        swipe(app, y: 0.115, from: 0.7, to: 0.2)
        XCTAssertTrue(el(app, "account.tab.admin").isSelected)
        XCTAssertTrue(app.otherElements["screen.profile"].exists)
        // Back with a right swipe, and past the first tab it stays put too.
        swipe(app, y: 0.115, from: 0.35, to: 0.8)
        XCTAssertTrue(el(app, "account.tab.host").isSelected)
        swipe(app, y: 0.115, from: 0.35, to: 0.8)
        XCTAssertTrue(el(app, "account.tab.personal").isSelected)
        swipe(app, y: 0.115, from: 0.35, to: 0.8)
        XCTAssertTrue(el(app, "account.tab.personal").isSelected)
        XCTAssertTrue(app.otherElements["screen.profile"].exists, "never hops to Messages")
        el(app, "account.tab.admin").tap()
        XCTAssertTrue(el(app, "account.tab.admin").isSelected, "tapping still works")
    }

    func testAccountWithOnlyPersonalKeepsTheDockSwipe() {
        let app = launch("accountSolo")
        XCTAssertTrue(el(app, "account.tab.personal").waitForExistence(timeout: 20))
        XCTAssertFalse(el(app, "account.tab.host").exists)
        swipe(app, y: 0.115, from: 0.35, to: 0.8)
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 8),
                      "nothing to swipe between, so the dock swipe stays available")
    }
}

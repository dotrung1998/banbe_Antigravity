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
        // Note 50: the round search button became the full-width search bar under the header row.
        XCTAssertTrue(el(app, "home.searchBar").exists)
        XCTAssertTrue(app.images["banbe"].firstMatch.exists)
        // Title and the bell must not overlap; nothing runs off-screen.
        let screen = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(el(app, "home.searchBar").frame.maxX, screen.maxX)
        XCTAssertLessThanOrEqual(el(app, "home.notifications").frame.maxX, screen.maxX)
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

    /// Note 48: the list area swipes between days and never leaves Schedule.
    func testSwipeOverTheAgendaChangesDayAndNeverTheSection() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.dayTitle").waitForExistence(timeout: 20))
        let before = el(app, "schedule.dayTitle").label
        swipe(app, y: 0.62, from: 0.85, to: 0.15)
        XCTAssertTrue(app.otherElements["screen.schedule"].waitForExistence(timeout: 3), "still on Schedule")
        XCTAssertFalse(app.otherElements["screen.inbox"].exists)
        XCTAssertNotEqual(el(app, "schedule.dayTitle").label, before, "the swipe moved to the next day")
        swipe(app, y: 0.62, from: 0.15, to: 0.85)
        XCTAssertEqual(el(app, "schedule.dayTitle").label, before, "and back")
    }

    /// Note 48: swipe down on the week strip opens the month in place; up closes it.
    func testWeekStripSwipeDownOpensMonthAndUpCloses() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.dayTitle").waitForExistence(timeout: 20))
        let strip = el(app, "schedule.nextWeek").frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.windows.firstMatch.frame.width / 2, dy: strip.midY))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)))
        XCTAssertTrue(el(app, "schedule.monthDay.15").waitForExistence(timeout: 3), "the whole month is shown")
        let now = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.windows.firstMatch.frame.width / 2, dy: el(app, "schedule.nextWeek").frame.midY))
        now.press(forDuration: 0.05, thenDragTo: now.withOffset(CGVector(dx: 0, dy: -90)))
        XCTAssertTrue(el(app, "schedule.monthDay.15").waitForNonExistence(timeout: 3), "back to the week")
    }

    // MARK: 4 — Account follows the mode (note 66: no tabs)

    /// Scrolls Account until `id` exists (the body is a LazyVStack).
    private func reveal(_ app: XCUIApplication, _ id: String, swipes: Int = 6) -> XCUIElement {
        let e = el(app, id)
        for _ in 0..<swipes where !e.exists || !e.isHittable { app.swipeUp() }
        return e
    }

    func testAccountHostModeShowsHostTilesAndNoTabs() {
        let app = launch("account")   // organizer mode on, admin
        XCTAssertTrue(el(app, "account.tile.events").waitForExistence(timeout: 20))
        for key in ["events", "getpaid", "team", "reports"] {
            let tile = el(app, "account.tile.\(key)")
            XCTAssertTrue(tile.exists, key)
            XCTAssertGreaterThanOrEqual(tile.frame.height, 88, "big tiles: \(key)")
        }
        XCTAssertFalse(el(app, "account.tile.tickets").exists, "goer tiles are hidden in host mode")
        XCTAssertFalse(el(app, "account.tab.personal").exists, "no Personal/Host/Admin tabs any more")
        XCTAssertFalse(el(app, "account.tabs").exists)
        // Admin tools live in More and open the Administration group.
        let admin = reveal(app, "account.adminTools")
        XCTAssertTrue(admin.exists)
        XCTAssertGreaterThanOrEqual(admin.frame.height, 44)
        admin.tap()
        XCTAssertTrue(el(app, "account.group.adminReview").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "account.adminGuide").exists)
    }

    func testAccountSignOutAppearsOnce() {
        let app = launch("account")
        XCTAssertTrue(el(app, "account.tile.events").waitForExistence(timeout: 20))
        XCTAssertTrue(reveal(app, "account.signOut", swipes: 8).exists)
        let q = app.buttons.matching(identifier: "account.signOut")
        XCTAssertEqual(q.count, 1, "Sign out renders once, not per mode or tab")
    }

    func testAccountGoerShowsGoerTilesAndKeepsTheDockSwipe() {
        let app = launch("accountSolo")   // organizer mode off, not an admin
        XCTAssertTrue(el(app, "account.tile.tickets").waitForExistence(timeout: 20))
        for key in ["tickets", "wallet", "saved", "help"] {
            XCTAssertTrue(el(app, "account.tile.\(key)").exists, key)
        }
        XCTAssertFalse(el(app, "account.tile.events").exists)
        XCTAssertFalse(el(app, "account.tab.personal").exists)
        XCTAssertTrue(el(app, "account.profileCard").exists)
        XCTAssertFalse(reveal(app, "account.adminTools").exists, "admins only")
        // Nothing to swipe between inside Account, so the dock swipe stays available.
        swipe(app, y: 0.115, from: 0.35, to: 0.8)
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 8))
    }

    // MARK: Note 47 — event zoom from Home

    /// The card's title sits right above the dock window; tap its photo instead.
    private func openCard(_ app: XCUIApplication, _ title: String) {
        let card = app.buttons[title].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -5)).tap()
        XCTAssertTrue(el(app, "event.back").waitForExistence(timeout: 5))
    }

    /// Home under Event Detail must be the SAME live HomeView on every open and close — a rebuilt one re-runs its
    /// loaders mid-zoom and cross-fades over the paper background (the jerk + white flash from the second open on).
    func testOpeningAndClosingEventsNeverRebuildsHome() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let mounts = el(app, "fixture.homeMounts")
        XCTAssertTrue(mounts.waitForExistence(timeout: 5))
        let before = mounts.label
        for _ in 0..<3 {
            openCard(app, "Fixture host supper")
            Thread.sleep(forTimeInterval: 1.0)
            el(app, "event.back").tap()
            XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1.0)
        }
        // Quick reopen inside the 1.4s open window: still lands on the event, Home still the same instance.
        openCard(app, "Fixture host supper")
        el(app, "event.back").tap()
        openCard(app, "Fixture host supper")
        Thread.sleep(forTimeInterval: 1.0)
        el(app, "event.back").tap()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(mounts.label, before, "Home was rebuilt by an event open/close")
    }

    /// The tab-swipe gesture is now always attached (masked off on pushed screens): the leading-edge swipe back
    /// from Event Detail must still win and land on Home.
    func testEdgeSwipeBackFromEventStillReachesHome() {
        let app = launch("home")
        openCard(app, "Fixture host supper")
        Thread.sleep(forTimeInterval: 1.0)
        swipe(app, y: 0.5, from: 0.01, to: 0.9)
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "event.back").exists)
    }

    /// Drag-down close lands on the same live Home as the Back button (no rebuild), and a short pull springs back.
    func testDragDownClosesEventOntoTheSameHome() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let mounts = el(app, "fixture.homeMounts")
        XCTAssertTrue(mounts.waitForExistence(timeout: 5))
        let before = mounts.label
        openCard(app, "Fixture host supper")
        Thread.sleep(forTimeInterval: 1.2)
        let w = app.windows.firstMatch
        // Short pull: below the close point, so it springs back and stays on the event.
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertTrue(el(app, "event.back").exists, "a short pull must not close the event")
        // Long pull: closes.
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(el(app, "event.back").exists)
        XCTAssertEqual(mounts.label, before, "Home was rebuilt by the drag close")
    }

    /// The dock shrinks only while a screen is scrolled down by the user: coming back to the tab that shrank it
    /// (whose scroll position is restored) must leave it full size.
    func testDockStaysExpandedWhenReturningToTheTabThatShrankIt() {
        let app = launch("home")
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        let tab = el(app, "tab.map")
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        let expanded = tab.frame.width
        // Scroll Home down (finger moves up) and keep the finger moving so the dock sees a live scroll.
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertLessThan(tab.frame.width, expanded - 1, "scrolling Home down should shrink the dock")
        // Another tab that also reports its scroll (Account): its top-of-page offset used to become the baseline,
        // so Home's restored offset then read as a big scroll down.
        el(app, "tab.profile").tap()
        Thread.sleep(forTimeInterval: 1.5)
        el(app, "tab.home").tap()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(tab.frame.width, expanded, accuracy: 1, "returning to Home must not shrink the dock again")
    }
}

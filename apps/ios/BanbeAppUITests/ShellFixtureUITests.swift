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

    func testAccountHostModeOpensOnHostTabWithPersonalAndAdmin() {
        let app = launch("account")   // organizer mode on, admin
        XCTAssertTrue(el(app, "account.tile.events").waitForExistence(timeout: 20))
        for key in ["events", "getpaid", "team", "reports"] {
            let tile = el(app, "account.tile.\(key)")
            XCTAssertTrue(tile.exists, key)
            XCTAssertGreaterThanOrEqual(tile.frame.height, 88, "big tiles: \(key)")
        }
        XCTAssertFalse(el(app, "account.tile.tickets").exists, "goer tiles live on the Personal tab")
        // Note 69: Host · Personal · Admin, Host first and selected.
        let host = el(app, "account.tab.host"), personal = el(app, "account.tab.personal"), admin = el(app, "account.tab.admin")
        XCTAssertTrue(host.exists && personal.exists && admin.exists)
        XCTAssertLessThan(host.frame.minX, personal.frame.minX)
        XCTAssertLessThan(personal.frame.minX, admin.frame.minX)
        let tools = reveal(app, "account.host.tools")
        XCTAssertTrue(tools.exists, "Hosting tools group on the Host tab")
        admin.tap()
        XCTAssertTrue(el(app, "account.group.adminReview").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "account.adminGuide").exists)
        personal.tap()
        XCTAssertTrue(el(app, "account.tile.tickets").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "account.profileCard").exists)
    }

    func testAccountSignOutAppearsOnce() {
        let app = launch("account")
        XCTAssertTrue(el(app, "account.tile.events").waitForExistence(timeout: 20))
        el(app, "account.tab.personal").tap()
        XCTAssertTrue(reveal(app, "account.signOut", swipes: 8).exists)
        let q = app.buttons.matching(identifier: "account.signOut")
        XCTAssertEqual(q.count, 1, "Sign out renders once, not per tab")
    }

    /// Note 69: Back from a row lower down lands on the same part of Account, not at the top.
    func testAccountBackKeepsScrollPosition() {
        let app = launch("accountSolo")
        XCTAssertTrue(el(app, "account.tile.tickets").waitForExistence(timeout: 20))
        let topY = el(app, "account.tile.tickets").frame.minY
        app.swipeUp(); app.swipeUp()
        let settings = el(app, "account.group.preferences")
        XCTAssertTrue(settings.isHittable)
        XCTAssertLessThan(el(app, "account.tile.tickets").frame.minY, topY - 100, "the page really scrolled")
        let before = settings.frame.minY
        settings.tap()
        let back = el(app, "accountGroup.back")
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(el(app, "account.group.preferences").waitForExistence(timeout: 5))
        let deadline = Date().addingTimeInterval(3)
        while abs(el(app, "account.group.preferences").frame.minY - before) > 12 && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(el(app, "account.group.preferences").frame.minY, before, accuracy: 12, "Back lands where you were")
        XCTAssertTrue(el(app, "account.group.preferences").isHittable, "Back lands where you were")
    }

    func testAccountGoerShowsGoerTilesAndKeepsTheDockSwipe() {
        let app = launch("accountSolo")   // organizer mode off, not an admin
        XCTAssertTrue(el(app, "account.tile.tickets").waitForExistence(timeout: 20))
        for key in ["tickets", "wallet", "saved", "help"] {
            XCTAssertTrue(el(app, "account.tile.\(key)").exists, key)
        }
        XCTAssertFalse(el(app, "account.tile.events").exists)
        XCTAssertFalse(el(app, "account.tabs").exists, "hosting off, not admin: no tabs")
        XCTAssertTrue(el(app, "account.profileCard").exists)
        XCTAssertFalse(el(app, "account.tab.admin").exists, "admins only")
        XCTAssertTrue(reveal(app, "account.personal.app").exists, "labelled groups replace More")
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

    // MARK: Simple Shell follow-up (plan items 1, 2, 5) — `-uiFixtureSimpleShell YES`

    private func launchSimple(_ variant: String = "home", host: Bool = false, extra: [String] = [], lang: String = "en") -> XCUIApplication {
        launch(variant, lang: lang, extra: ["-uiFixtureSimpleShell", "YES"] + (host ? ["-uiFixtureHostMode", "YES"] : []) + extra)
    }

    private func waitSelected(_ e: XCUIElement, _ selected: Bool = true, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    /// Goer (organizer mode off): Hosting is locked, still reachable, and opens the invitation; Home stays on Going out.
    func testLockedHostingOpensTheInvitationAndStaysOnGoingOut() {
        let app = launchSimple()
        let host = el(app, "home.mode.host"), goer = el(app, "home.mode.goer")
        XCTAssertTrue(host.waitForExistence(timeout: 20))
        XCTAssertEqual(host.label, "Hosting, locked")
        XCTAssertEqual(host.value as? String, "locked")
        XCTAssertGreaterThanOrEqual(host.frame.height, 44)
        XCTAssertTrue(goer.isSelected)
        host.tap()
        XCTAssertTrue(el(app, "startHosting.sheet").waitForExistence(timeout: 6), "the Start hosting invitation")
        XCTAssertTrue(el(app, "startHosting.confirm").exists)
        el(app, "startHosting.close").tap()
        XCTAssertTrue(el(app, "startHosting.sheet").waitForNonExistence(timeout: 5))
        XCTAssertTrue(goer.isSelected, "still Going out")
        XCTAssertFalse(el(app, "home.host.hero").exists)
        XCTAssertFalse(el(app, "home.host.plan").exists)
    }

    func testLockedHostingLabelVietnamese() {
        let app = launchSimple(lang: "vi")
        let host = el(app, "home.mode.host")
        XCTAssertTrue(host.waitForExistence(timeout: 20))
        XCTAssertEqual(host.label, "Tổ chức, đã khoá")
    }

    /// Confirming the invitation turns hosting on and lands on Home > Hosting (lock gone).
    func testConfirmingTheInvitationUnlocksHosting() {
        let app = launchSimple()
        let host = el(app, "home.mode.host")
        XCTAssertTrue(host.waitForExistence(timeout: 20))
        host.tap()
        let confirm = el(app, "startHosting.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        confirm.tap()
        XCTAssertTrue(waitSelected(host, timeout: 8))
        XCTAssertEqual(host.label, "Hosting")
        XCTAssertTrue(el(app, "home.host.hero").exists || el(app, "home.host.plan").exists)
    }

    /// Host: Going out ↔ Hosting changes only the view (no invitation, organizer mode stays on).
    func testHostTogglesGoingOutAndHostingWithoutTheInvitation() {
        let app = launchSimple(host: true)
        let host = el(app, "home.mode.host"), goer = el(app, "home.mode.goer")
        XCTAssertTrue(host.waitForExistence(timeout: 20))
        XCTAssertTrue(waitSelected(host), "a host opens on Hosting")
        XCTAssertEqual(host.label, "Hosting")
        goer.tap()
        XCTAssertTrue(waitSelected(goer))
        XCTAssertFalse(el(app, "startHosting.sheet").exists)
        XCTAssertFalse(el(app, "home.host.hero").exists)
        XCTAssertTrue(el(app, "home.searchBar").exists, "the goer feed")
        host.tap()
        XCTAssertTrue(waitSelected(host))
        XCTAssertFalse(el(app, "startHosting.sheet").waitForExistence(timeout: 1.5), "no invitation for a host")
        XCTAssertTrue(el(app, "home.host.hero").exists || el(app, "home.host.plan").exists)
    }

    func testGuestTappingHostingAsksToSignIn() {
        let app = launchSimple(extra: ["-uiFixtureGuest", "YES"])
        let host = el(app, "home.mode.host")
        XCTAssertTrue(host.waitForExistence(timeout: 20))
        XCTAssertEqual(host.label, "Hosting, locked")
        host.tap()
        XCTAssertTrue(el(app, "guestPrompt").waitForExistence(timeout: 6))
        XCTAssertFalse(el(app, "startHosting.sheet").exists)
    }

    /// Item 2: the category row is back under the search bar with its "Show all" sheet; one category shows its type
    /// chips, All hides them; the Filters sheet no longer repeats categories.
    func testCategoryRowIsBackWithShowAllAndTypeChips() {
        let app = launchSimple(extra: ["-uiFixtureEventTypes", "YES"])
        let all = el(app, "filter.all")
        XCTAssertTrue(all.waitForExistence(timeout: 20), "category row")
        XCTAssertTrue(all.isSelected)
        XCTAssertGreaterThan(all.frame.minY, el(app, "home.searchBar").frame.maxY, "under the search bar")
        el(app, "home.category.showAll").tap()
        XCTAssertTrue(el(app, "home.categorySheet").waitForExistence(timeout: 5), "Show all A-Z sheet")
        el(app, "home.categorySheet.close").tap()
        XCTAssertTrue(el(app, "home.categorySheet").waitForNonExistence(timeout: 5))
        let supper = el(app, "filter.supper")
        XCTAssertTrue(supper.waitForExistence(timeout: 5))
        supper.tap()
        let typeChip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.type.'")).firstMatch
        XCTAssertTrue(typeChip.waitForExistence(timeout: 5), "one category shows its type chips")
        el(app, "filter.all").tap()
        XCTAssertTrue(typeChip.waitForNonExistence(timeout: 5), "All hides them")
        el(app, "home.filtersButton").tap()
        XCTAssertTrue(el(app, "home.filter.seatsLeft").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "home.filter.cat.supper").exists, "no category section in the Filters sheet")
    }

    /// Note 69: Hosting Home has shortcuts, and each Submitted tile is its own button into the dashboard.
    func testHostHomeQuickActionsAndSubmittedTiles() {
        let app = launchSimple(host: true)
        XCTAssertTrue(el(app, "home.host.quick").waitForExistence(timeout: 20))
        for id in ["guests", "refunds", "story", "surveys"] {
            let chip = el(app, "home.host.quick.\(id)")
            XCTAssertTrue(chip.exists, id)
            XCTAssertGreaterThanOrEqual(chip.frame.height, 44, id)
        }
        XCTAssertEqual(app.buttons.matching(identifier: "home.host.quick.create").count
                       + app.buttons.matching(identifier: "home.host.plan.create").count, 1, "Create event shows once")
        let pending = reveal(app, "home.host.submitted.pending")
        XCTAssertTrue(pending.exists)
        pending.tap()
        XCTAssertTrue(app.otherElements["screen.dashboard"].waitForExistence(timeout: 8))
    }

    /// Item 5: the three KPI tiles are the same width, at least 88pt tall, and show the short label in full.
    func testHostKPITilesAreEqualAndShowShortLabels() {
        let app = launchSimple(host: true)
        XCTAssertTrue(el(app, "home.mode.host").waitForExistence(timeout: 20))
        let tiles = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'home.host.kpi.'"))
        for _ in 0..<5 where !(tiles.count == 3 && tiles.element(boundBy: 2).isHittable) { app.swipeUp() }
        XCTAssertEqual(tiles.count, 3)
        let frames = (0..<3).map { tiles.element(boundBy: $0).frame }
        XCTAssertEqual(frames[0].width, frames[1].width, accuracy: 1)
        XCTAssertEqual(frames[1].width, frames[2].width, accuracy: 1)
        XCTAssertEqual(frames[0].minY, frames[2].minY, accuracy: 1, "one row")
        for f in frames { XCTAssertGreaterThanOrEqual(f.height, 88) }
        let shortLabels = ["Seats confirmed", "Payments confirmed", "Upcoming", "Published", "Checked in",
                           "Refunds owed", "Refunds late"]
        for i in 0..<3 {
            XCTAssertTrue(shortLabels.contains(tiles.element(boundBy: i).label), tiles.element(boundBy: i).label)
        }
    }
}

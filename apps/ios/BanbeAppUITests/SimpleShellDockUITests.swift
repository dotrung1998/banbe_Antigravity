import XCTest

/// Simple Shell follow-up (plan items 3 + 4) on the REAL RootView with seeded state (`-uiFixture shell.*`,
/// `-uiFixtureSimpleShell YES`, no network): dragging the dock bubble across and onto the centre "+", and
/// "+" > Host an event from every tab with organizer mode off and on, plus a guest.
final class SimpleShellDockUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ variant: String, host: Bool = false, guest: Bool = false, lang: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", lang, "-uiTesting", "1",
                                "-banbe.onboarded", "YES", "-uiFixtureSimpleShell", "YES"]
        if host { app.launchArguments += ["-uiFixtureHostMode", "YES"] }
        if guest { app.launchArguments += ["-uiFixtureGuest", "YES"] }
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func center(_ e: XCUIElement) -> XCUICoordinate {
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    /// A slow scrub: press on `from`, drag to `to`, release (the bar's DragGesture, minimumDistance 0).
    private func scrub(_ app: XCUIApplication, from: String, to: String) {
        let a = el(app, from), b = el(app, to)
        XCTAssertTrue(a.waitForExistence(timeout: 20), from)
        XCTAssertTrue(b.waitForExistence(timeout: 5), to)
        center(a).press(forDuration: 0.25, thenDragTo: center(b), withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func waitSelected(_ e: XCUIElement, _ selected: Bool = true, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    // MARK: Item 3 — drag across and onto "+"

    func testDragHomeToInboxAcrossTheCentreSelectsInbox() {
        let app = launch("home")
        XCTAssertTrue(waitSelected(el(app, "tab.home"), timeout: 20))
        scrub(app, from: "tab.home", to: "tab.inbox")
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 6), "released over Inbox")
        XCTAssertTrue(waitSelected(el(app, "tab.inbox")))
        XCTAssertFalse(el(app, "dock.createMenu.host").exists, "crossing the + never opens its menu")
    }

    func testDragInboxToHomeAcrossTheCentreSelectsHome() {
        let app = launch("inbox")
        XCTAssertTrue(waitSelected(el(app, "tab.inbox"), timeout: 20))
        scrub(app, from: "tab.inbox", to: "tab.home")
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 6), "released over Home")
        XCTAssertTrue(waitSelected(el(app, "tab.home")))
    }

    /// Regression (owner report): releasing the bubble on "+" snapped back and did nothing. It opens the "+" menu,
    /// the screen stays, and the previous tab is still the selected one.
    func testDragReleasedOnCreateOpensTheMenuAndKeepsTheTab() {
        let app = launch("schedule")
        XCTAssertTrue(waitSelected(el(app, "tab.schedule"), timeout: 20))
        scrub(app, from: "tab.schedule", to: "dock.createButton")
        XCTAssertTrue(el(app, "dock.createMenu.host").waitForExistence(timeout: 5), "the + menu opened")
        XCTAssertTrue(app.otherElements["screen.schedule"].exists, "the screen did not change")
        // Dismiss by tapping well away from the popover; Schedule is still the tab.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(el(app, "dock.createMenu.host").waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["screen.schedule"].exists)
        XCTAssertTrue(waitSelected(el(app, "tab.schedule")), "Schedule stays selected")
        XCTAssertFalse(el(app, "tab.home").isSelected)
    }

    func testTapPlusOpensTheMenu() {
        let app = launch("home")
        let plus = el(app, "dock.createButton")
        XCTAssertTrue(plus.waitForExistence(timeout: 20))
        plus.tap()
        XCTAssertTrue(el(app, "dock.createMenu.host").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dock.createMenu.schedule").exists)
    }

    // MARK: Item 4 — "+" > Host an event from every tab

    private func tabID(for start: String) -> String {
        ["home": "tab.home", "schedule": "tab.schedule", "inbox": "tab.inbox", "accountSolo": "tab.profile"][start]!
    }

    private func openHostAnEvent(_ app: XCUIApplication) {
        let plus = el(app, "dock.createButton")
        XCTAssertTrue(plus.waitForExistence(timeout: 20))
        plus.tap()
        let row = el(app, "dock.createMenu.host")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Host an event row")
        row.tap()
    }

    private func assertOnHostHome(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 8), "landed on Home", file: file, line: line)
        let hero = el(app, "home.host.hero"), plan = el(app, "home.host.plan")
        let p = NSPredicate(format: "exists == true")
        let found = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: hero)], timeout: 6) == .completed
            || plan.exists
        XCTAssertTrue(found, "Home > Hosting shows its hero", file: file, line: line)
        XCTAssertTrue((hero.exists ? hero : plan).isHittable, "scrolled to the top", file: file, line: line)
        XCTAssertTrue(waitSelected(el(app, "home.mode.host")), "Hosting segment selected", file: file, line: line)
    }

    /// Organizer mode off: the Start hosting invitation, then Home > Hosting.
    func testHostAnEventWithOrganizerModeOffFromEveryTab() {
        for start in ["home", "schedule", "inbox", "accountSolo"] {
            let app = launch(start)
            XCTAssertTrue(waitSelected(el(app, tabID(for: start)), timeout: 20), start)
            openHostAnEvent(app)
            let confirm = el(app, "startHosting.confirm")
            XCTAssertTrue(confirm.waitForExistence(timeout: 6), "\(start): the invitation opened")
            confirm.tap()
            assertOnHostHome(app)
            app.terminate()
        }
    }

    /// Organizer mode on, Home switched to Going out: "+" shows the goer rows; Host an event lands on Hosting from any
    /// tab (this was a no-op before) with no invitation.
    func testHostAnEventWithOrganizerModeOnFromEveryTab() {
        for start in ["home", "schedule", "inbox", "profile"] {
            let app = launch("home", host: true)
            let goer = el(app, "home.mode.goer")
            XCTAssertTrue(goer.waitForExistence(timeout: 20))
            goer.tap()
            XCTAssertTrue(waitSelected(goer), "Going out")
            if start != "home" {
                el(app, "tab.\(start)").tap()
                XCTAssertTrue(app.otherElements["screen.\(start)"].waitForExistence(timeout: 6), start)
            }
            openHostAnEvent(app)
            XCTAssertFalse(el(app, "startHosting.confirm").waitForExistence(timeout: 1.5), "\(start): no invitation when on")
            assertOnHostHome(app)
            app.terminate()
        }
    }

    func testHostAnEventAsGuestAsksToSignIn() {
        let app = launch("home", guest: true)
        openHostAnEvent(app)
        XCTAssertTrue(el(app, "guestPrompt").waitForExistence(timeout: 6), "sign-in prompt first")
        XCTAssertFalse(el(app, "startHosting.confirm").exists)
    }
}

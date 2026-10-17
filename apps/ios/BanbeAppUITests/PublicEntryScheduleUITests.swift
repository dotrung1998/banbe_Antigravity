import XCTest

/// Phase G (note 44) against DEBUG fixtures (App/UITestFixtures.swift): public
/// entry + Login routing, launch routing, Schedule modes/cards/conflicts,
/// Add to banbe Schedule, the Apple Calendar editor (cancel only — never
/// saves to a real calendar) and the report breakdowns. No network.
final class PublicEntryScheduleUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", lang, "-uiTesting", "1"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // MARK: public entry

    func testLogInIsImmediateFromWelcome() {
        let app = launch("auth", extra: ["-banbe.publicStory.seen.v1", "NO"])
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "welcome.login").isHittable, "Log in is visible on the very first screen")
        el(app, "welcome.login").tap()
        XCTAssertTrue(el(app, "login.mode.login").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "login.mode.login").isSelected, "opens on Log in, no intermediate pages")
        XCTAssertEqual(el(app, "login.heading").label, "Welcome back")
    }

    func testGetStartedOpensSignUpAndTypedValuesSurviveBack() {
        let app = launch("auth")
        XCTAssertTrue(el(app, "welcome.getStarted").waitForExistence(timeout: 10))
        el(app, "welcome.getStarted").tap()
        XCTAssertTrue(el(app, "login.mode.signup").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "login.mode.signup").isSelected)
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("guest@example.com")
        el(app, "login.back").tap()
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 5))
        el(app, "welcome.login").tap()
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["login.email"].value as? String, "guest@example.com", "typed email kept across Back")
    }

    func testOptionalStoryBackSkipAndCTA() {
        let app = launch("auth")
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        XCTAssertTrue(el(app, "welcome.story.heading.0").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "welcome.story.progress").label, "1 of 2")
        el(app, "welcome.story.next").tap()
        XCTAssertTrue(el(app, "welcome.story.heading.1").waitForExistence(timeout: 5))
        el(app, "welcome.story.back").tap()
        XCTAssertTrue(el(app, "welcome.story.heading.0").waitForExistence(timeout: 5))
        el(app, "welcome.story.skip").tap()
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 5))
        // Last page offers both routes too.
        el(app, "welcome.story.open").tap()
        el(app, "welcome.story.next").tap()
        XCTAssertTrue(el(app, "welcome.login").waitForExistence(timeout: 5))
        el(app, "welcome.login").tap()
        XCTAssertTrue(el(app, "login.mode.login").waitForExistence(timeout: 5))
    }

    func testStorySeenIsRememberedAcrossLaunches() {
        var app = launch("auth", extra: ["-banbe.publicStory.seen.v1", "NO"])
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        XCTAssertEqual(el(app, "welcome.story.open").label, "See how banbe works")
        el(app, "welcome.story.open").tap()
        el(app, "welcome.story.skip").tap()
        app.terminate()
        app = launch("auth")
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 10), "single welcome screen, no replay")
        XCTAssertEqual(el(app, "welcome.story.open").label, "How banbe works")
    }

    func testVietnamesePublicEntry() {
        let app = launch("auth", lang: "vi")
        XCTAssertTrue(el(app, "welcome.login").waitForExistence(timeout: 10))
        XCTAssertEqual(el(app, "welcome.login").label, "Đã có tài khoản? Đăng nhập")
        XCTAssertTrue(app.buttons["Bắt đầu"].exists)
    }

    func testReduceMotionStillNavigates() {
        let app = launch("auth", extra: ["-UIAccessibilityReduceMotionEnabled", "YES"])
        XCTAssertTrue(el(app, "welcome.login").waitForExistence(timeout: 10))
        el(app, "welcome.login").tap()
        XCTAssertTrue(el(app, "login.mode.login").waitForExistence(timeout: 3))
    }

    // MARK: launch routing

    func testSignedInBypassesPublicEntry() {
        let app = launch("routing.signedIn", extra: ["-banbe.onboarded", "YES"])
        XCTAssertTrue(el(app, "fixture.screen.home").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "welcome.heading").exists)
    }

    func testSignedOutLaunchAndSignOutLandOnWelcome() {
        var app = launch("routing.signedOut", extra: ["-banbe.onboarded", "YES"])
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 10))
        app.terminate()
        app = launch("routing.signOut", extra: ["-banbe.onboarded", "YES"])
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 10), "sign-out lands on welcome, not Login")
    }

    // MARK: schedule

    func testMyScheduleDayShowsHostedAndAddedThenOpensEvent() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.item.fx-hosted").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "schedule.item.fx-added").exists)
        // Each card is one combined accessibility element; its label carries the source line.
        XCTAssertTrue(el(app, "schedule.item.fx-hosted").label.contains("You're hosting"))
        XCTAssertTrue(el(app, "schedule.item.fx-added").label.contains("Added by you"))
        el(app, "schedule.item.fx-hosted").tap()
        XCTAssertTrue(el(app, "fixture.event.fx-hosted").waitForExistence(timeout: 5))
    }

    func testDiscoverShowsOnlyNonPlansWithHonestConflictAndAdds() {
        let app = launch("schedule.discover")
        XCTAssertTrue(el(app, "schedule.discover.fx-near").waitForExistence(timeout: 10))
        XCTAssertFalse(el(app, "schedule.discover.fx-hosted").exists, "already a plan, never offered again")
        XCTAssertTrue(el(app, "schedule.conflict.fx-near").exists)
        XCTAssertEqual(el(app, "schedule.conflict.fx-near").label, "Starts within 2 hours of 1 plan")
        el(app, "schedule.add.fx-near").tap()
        XCTAssertFalse(el(app, "schedule.discover.fx-near").waitForExistence(timeout: 2), "moves out of Discover")
        el(app, "schedule.mode").buttons["My schedule"].tap()
        XCTAssertTrue(el(app, "schedule.item.fx-near").waitForExistence(timeout: 5))
    }

    func testEmptyDayOffersDiscoverAndErrorIsHonest() {
        var app = launch("schedule.empty")
        XCTAssertTrue(el(app, "schedule.empty.mine").waitForExistence(timeout: 10))
        el(app, "schedule.empty.toDiscover").tap()
        XCTAssertTrue(el(app, "schedule.discover.fx-near").waitForExistence(timeout: 5))
        app.terminate()
        app = launch("schedule.error")
        XCTAssertTrue(el(app, "schedule.error").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "schedule.retry").exists)
    }

    func testWeekNavigationAndToday() {
        let app = launch("schedule")
        XCTAssertTrue(el(app, "schedule.nextWeek").waitForExistence(timeout: 10))
        el(app, "schedule.nextWeek").tap()
        XCTAssertFalse(el(app, "schedule.item.fx-hosted").waitForExistence(timeout: 2))
        el(app, "schedule.today").tap()
        XCTAssertTrue(el(app, "schedule.dayTitle").exists)
    }

    // MARK: event plan actions

    func testAddToBanbeScheduleThenNoDuplicate() {
        let app = launch("plan")
        XCTAssertTrue(el(app, "event.plan.button").waitForExistence(timeout: 10))
        el(app, "event.plan.button").tap()
        XCTAssertTrue(el(app, "event.schedule.add").waitForExistence(timeout: 5))
        el(app, "event.schedule.add").tap()
        // Menu closed; the button now reads "Added" and the menu offers Remove instead of Add.
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 5))
        el(app, "event.plan.button").tap()
        XCTAssertTrue(el(app, "event.schedule.remove").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "event.schedule.add").exists, "no second add once it's there")
        el(app, "event.schedule.remove").tap()
        XCTAssertTrue(app.staticTexts["Discover"].waitForExistence(timeout: 5))
    }

    func testAppleCalendarEditorPresentsAndCancelIsHonest() {
        let app = launch("plan")
        XCTAssertTrue(el(app, "event.plan.button").waitForExistence(timeout: 10))
        el(app, "event.plan.button").tap()
        XCTAssertTrue(el(app, "event.appleCalendar").waitForExistence(timeout: 5))
        el(app, "event.appleCalendar").tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "system event editor should present")
        cancel.tap()
        // The system may ask to discard the pre-filled event.
        let discard = app.buttons["Discard Changes"].firstMatch
        if discard.waitForExistence(timeout: 2) { discard.tap() }
        XCTAssertTrue(el(app, "event.plan.message").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "event.plan.message").label, "Not added to Apple Calendar.")
    }

    // MARK: report breakdowns

    func testReportBreakdownsPerRole() {
        var app = launch("reports.host")
        XCTAssertTrue(el(app, "reports.insight.share.refunds_owed").waitForExistence(timeout: 10))
        app.terminate()
        app = launch("reports.admin")
        let backlog = el(app, "reports.insight.dist.pending_event_reviews.Open backlog")
        XCTAssertTrue(backlog.waitForExistence(timeout: 10))
        app.terminate()
        app = launch("reports.personal")
        XCTAssertTrue(el(app, "reports.insight.dist.outstanding_refunds.Pending refunds by status").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "reports.kpi.strip.attended_events").exists || el(app, "reports.kpi.attended_events").exists)
    }
}

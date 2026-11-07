import XCTest

/// Migration 216: the admin "Project hub demo" on the REAL RootView (`-uiFixture shell.account`, an admin). The row shows
/// only while the switch is on (`-uiFixtureProjectDemo YES`), opens the hub on the bundled sample with a demo banner,
/// and Exit returns to Account with nothing left behind. No network.
final class ProjectDemoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(demoSwitch: Bool, variant: String = "account") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", "en", "-uiTesting", "1", "-banbe.onboarded", "YES"]
            + (demoSwitch ? ["-uiFixtureProjectDemo", "YES"] : [])
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func reveal(_ app: XCUIApplication, _ id: String, swipes: Int = 6) -> XCUIElement {
        let e = el(app, id)
        for _ in 0..<swipes where !e.exists || !e.isHittable { app.swipeUp() }
        return e
    }

    /// Account › Admin › Review & Moderation, where Feature switches lives.
    private func openAdminReview(_ app: XCUIApplication) {
        let admin = el(app, "account.tab.admin")
        XCTAssertTrue(admin.waitForExistence(timeout: 30))
        admin.tap()
        let review = el(app, "account.group.adminReview")
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        review.tap()
        XCTAssertTrue(reveal(app, "admin.features").waitForExistence(timeout: 10))
    }

    private func openDemo(_ app: XCUIApplication, as role: String, eventDay: Bool = false) {
        let row = reveal(app, "admin.projectDemo")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the demo row shows for an admin with the switch on")
        row.tap()
        XCTAssertTrue(el(app, "projectDemo.title").waitForExistence(timeout: 10), "the View as picker opens")
        el(app, "projectDemo.as.\(role)").tap()
        if eventDay { el(app, "projectDemo.eventDay").switches.firstMatch.tap() }
        el(app, "projectDemo.open").tap()
        XCTAssertTrue(el(app, "project.hub").waitForExistence(timeout: 15), "the hub opens on the sample")
        XCTAssertTrue(el(app, "project.demoBanner").waitForExistence(timeout: 5), "the demo banner is on top")
    }

    func testAdminOpensTheDemoAsHostAndExitReturnsToAccount() {
        let app = launch(demoSwitch: true)
        openAdminReview(app)
        openDemo(app, as: "host")
        XCTAssertTrue(el(app, "project.tab.overview").exists)
        XCTAssertTrue(el(app, "project.tab.money").exists)
        el(app, "project.tab.money").tap()
        // Links to the real Verifications screen are blocked in the demo.
        let verify = reveal(app, "project.money.verify")
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        verify.tap()
        XCTAssertTrue(el(app, "project.hub").exists, "still in the hub")
        el(app, "project.demoExit").tap()
        XCTAssertTrue(reveal(app, "admin.projectDemo").waitForExistence(timeout: 10), "back on Account › Admin")
        XCTAssertFalse(el(app, "project.hub").exists)
        XCTAssertFalse(el(app, "project.demoBanner").exists)
    }

    func testAdminOpensTheDemoAsFinanceOnTheEventDay() {
        let app = launch(demoSwitch: true)
        openAdminReview(app)
        openDemo(app, as: "finance", eventDay: true)
        XCTAssertTrue(el(app, "project.tab.dayof").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.dayofTab").waitForExistence(timeout: 5), "event day opens on Day-of")
        el(app, "project.tab.money").tap()
        XCTAssertTrue(el(app, "project.moneyTab").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.money.hostOnly").exists, "Finance sees the member view, not the Host's")
        el(app, "project.back").tap()
        XCTAssertTrue(reveal(app, "admin.projectDemo").waitForExistence(timeout: 10), "Back also ends the demo")
        XCTAssertFalse(el(app, "project.demoBanner").exists)
    }

    func testNonAdminHasNoAdminAreaEvenWithTheSwitchOn() {
        let app = launch(demoSwitch: true, variant: "accountSolo")   // not an admin
        XCTAssertTrue(el(app, "account.tile.tickets").waitForExistence(timeout: 30))
        XCTAssertFalse(el(app, "account.tab.admin").exists)
        XCTAssertFalse(el(app, "admin.projectDemo").exists)
    }

    func testNoRowWhileTheSwitchIsOff() {
        let app = launch(demoSwitch: false)
        openAdminReview(app)
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(el(app, "admin.projectDemo").exists, "switch off: no entry")
    }
}

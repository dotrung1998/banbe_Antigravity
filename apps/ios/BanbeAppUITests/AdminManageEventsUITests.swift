import XCTest

/// Note 54: Admin > Manage events against the DEBUG fixture (UITestFixture.adminManagedEvents; same rules as
/// migrations 188/189, which are verified separately on Postgres by supabase/_localtest/13_event_removal_assert.sql).
final class AdminManageEventsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(wipe: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.adminManageEvents", "-banbe.lang", "en", "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES", "-uiFixtureWipe", wipe ? "YES" : "NO"]
        app.launch()
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testRemoveSkipsBlockedAndAsksForReason() {
        let app = launch()
        XCTAssertTrue(el(app, "adminManage.row.fx-ev-live").waitForExistence(timeout: 15))
        XCTAssertTrue(el(app, "adminManage.blocked.fx-ev-booked").exists, "a booked event says why it can't go yet")
        XCTAssertFalse(el(app, "adminManage.action.wipe").exists, "testing wipe is hidden while its switch is off")
        el(app, "adminManage.row.fx-ev-live").tap()
        el(app, "adminManage.row.fx-ev-booked").tap()
        shot("manage-selected")
        let remove = el(app, "adminManage.action.remove")
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertEqual(remove.label, "Remove (1)", "only the event with nothing in play is removable")
        remove.tap()
        let confirm = el(app, "adminManage.reason.confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled, "no reason, no removal")
        app.buttons["Spam"].firstMatch.tap()
        shot("manage-reason")
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        let banner = el(app, "adminManage.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.hasPrefix("Removed 1 event."), banner.label)
        el(app, "adminManage.filter.removed").tap()
        XCTAssertTrue(el(app, "adminManage.row.fx-ev-live").waitForExistence(timeout: 5), "now under Removed")
        shot("manage-removed-filter")
    }

    func testRestoreAndPermanentDelete() {
        let app = launch()
        XCTAssertTrue(el(app, "adminManage.filter.removed").waitForExistence(timeout: 15))
        el(app, "adminManage.filter.removed").tap()
        XCTAssertTrue(el(app, "adminManage.row.fx-ev-removed").waitForExistence(timeout: 5))
        el(app, "adminManage.row.fx-ev-removed").tap()
        XCTAssertTrue(el(app, "adminManage.action.purge").waitForExistence(timeout: 5), "never booked -> deletable")
        el(app, "adminManage.action.purge").tap()
        app.buttons["Duplicate"].firstMatch.tap()
        el(app, "adminManage.reason.confirm").tap()
        XCTAssertTrue(el(app, "adminManage.banner").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "adminManage.banner").label.hasPrefix("Permanently deleted 1 event."))
        XCTAssertFalse(el(app, "adminManage.row.fx-ev-removed").exists)
    }

    func testTestingWipeOnlyWithSwitchOn() {
        let app = launch(wipe: true)
        XCTAssertTrue(el(app, "adminManage.row.fx-ev-booked").waitForExistence(timeout: 15))
        el(app, "adminManage.row.fx-ev-booked").tap()
        let wipe = el(app, "adminManage.action.wipe")
        XCTAssertTrue(wipe.waitForExistence(timeout: 5), "testing wipe shows while the switch is on")
        shot("manage-wipe")
        wipe.tap()
        let confirm = app.buttons["Wipe permanently"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(el(app, "adminManage.banner").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "adminManage.banner").label.hasPrefix("Wiped 1 event (testing)."))
        XCTAssertFalse(el(app, "adminManage.row.fx-ev-booked").exists, "even an event with bookings is gone")
    }
}

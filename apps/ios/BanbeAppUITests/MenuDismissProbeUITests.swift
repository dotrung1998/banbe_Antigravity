import XCTest

/// Note 53 (owner report): opening + closing the dock "+" menu or Event Detail's calendar button left a white
/// overlay for a moment. Captures the dismissal frame by frame so the fix can be checked.
final class MenuDismissProbeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func launch(_ variant: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", "en", "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES"]
        app.launch()
        return app
    }

    private func burst(_ name: String, count: Int = 8) {
        for i in 0..<count {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = "\(name)-\(i)"
            a.lifetime = .keepAlways
            add(a)
        }
    }

    func testDockPlusMenuDismiss() {
        let app = launch("account")   // organizer mode on, so the dock "+" is there
        let plus = app.descendants(matching: .any)["dock.createButton"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        sleep(1)
        burst("dock-open", count: 1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        burst("dock-close")
    }

    func testEventCalendarMenuDismiss() {
        let app = launch("event")
        let button = app.descendants(matching: .any)["event.plan.button"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        sleep(1)
        burst("cal-open", count: 1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        burst("cal-close")
    }

    func testSearchFieldsShowFocusRing() {
        let app = launch("account")
        let toggle = app.descendants(matching: .any)["account.searchToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.tap()
        sleep(1)
        app.typeText("tick")
        burst("account-search-focused", count: 1)
        app.terminate()
        let inbox = launch("inbox")
        let search = inbox.buttons["Search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        sleep(1)
        inbox.typeText("bep")
        burst("inbox-search-focused", count: 1)
    }
}

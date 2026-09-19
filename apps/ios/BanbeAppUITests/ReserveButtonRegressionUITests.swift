import XCTest

/// Regression coverage for the a5fd823 real-device report: Event Detail's
/// Reserve/View Ticket action bar was visible but not tappable once
/// `BottomTabBarOverlay`'s hosting `UIWindow` widened to fit the 5-icon
/// dock (Task 1b's Home tab) — the overlay window was never hidden on
/// screens outside `BottomTabBar.visibleScreens` (Event Detail among
/// them), so it kept silently swallowing every touch in its bottom-of-
/// screen band regardless, including ones meant for the REAL action bar
/// underneath. See `BottomTabBarOverlay.updateVisibility(for:)`'s own doc
/// comment for the full root-cause writeup.
final class ReserveButtonRegressionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @discardableResult
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()

        if app.otherElements["screen.login"].waitForExistence(timeout: 45) {
            app.buttons["login.method.password"].tap()
            let email = app.textFields["login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 5))
            email.tap()
            email.typeText("doqanh0906+banbe-fast-suite-shared@gmail.com")
            let password = app.secureTextFields["login.password"]
            XCTAssertTrue(password.waitForExistence(timeout: 5))
            password.tap()
            password.typeText("BanbeE2e!Test1234")
            app.buttons["login.submit"].tap()
        }

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 45),
                      "Expected to land on Home after sign-in")
        return app
    }

    /// Taps the actual Reserve/View Ticket bar (whichever state this test
    /// account's booking for this event is in — the point isn't which
    /// state, it's that a tap on it reaches the real button and navigates
    /// away from Event Detail, rather than being silently swallowed by the
    /// tab bar's overlay window sitting on top of it).
    func testActionBarIsTappableWithFiveIconDockPresent() {
        let app = launchSignedIn()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))

        let actionBar = app.descendants(matching: .any).matching(identifier: "event.actionBar").firstMatch
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertTrue(actionBar.isHittable,
                      "Expected the Reserve/View Ticket bar to be hittable with the 5-icon dock's overlay window present")
        actionBar.tap()

        // Whichever state this landed on (Reserve, the ticket/Confirmed
        // screen, or a login gate if the session state changed) — the
        // important, tab-bar-regression-specific assertion is that the tap
        // actually navigated somewhere, i.e. Event Detail is gone. Before
        // the fix, a swallowed tap left the user stuck right here.
        let stillOnEvent = app.otherElements["screen.event"]
        let left = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: left, object: stillOnEvent)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed,
                       "Tapping the action bar did not navigate away from Event Detail — the tap was likely swallowed")
    }
}

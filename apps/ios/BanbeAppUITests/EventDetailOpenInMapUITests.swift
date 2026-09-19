import XCTest

/// Regression coverage for Task 1a: "Open in Map" only appears on Event
/// Detail when reached from Home, never when reached by tapping the event
/// inside Map Explore's own sheet list — the same `eventBackScreen`
/// convention `.claude/notes/06-design-tokens.md`'s "▪︎ Về trang chính"/
/// "▪︎ Back to home" link already established, just the opposite condition.
final class EventDetailOpenInMapUITests: XCTestCase {

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

    func testOpenInMapShowsFromHomeButNotFromMapSheet() {
        let app = launchSignedIn()

        // From Home: the button must be there.
        let card = app.buttons["card.bepnho"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["event.openInMap"].waitForExistence(timeout: 5),
                      "Expected 'Open in map' when Event Detail was reached from Home")

        // Tapping it actually opens Map Explore, centered/focused on this
        // event (its info card shows).
        app.buttons["event.openInMap"].tap()
        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10))
        // `map.selectedCard` is applied to a container whose descendants
        // (Image/StaticText/Button) each inherit it as their OWN identifier
        // with their own distinct element types — not a single `.other`
        // element — so `.any` is needed the same way BottomTabBarUITests
        // needed it for BottomTabBar's own items.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "map.selectedCard").firstMatch.waitForExistence(timeout: 15),
                      "Expected the same selected-pin info card MapExplore shows for a tapped pin/list row")

        // Now reach the SAME event's detail screen via Map's own sheet
        // list/pin flow instead — the button must NOT appear there.
        // Looked up by its visible label, not its `map.card.cta`
        // accessibilityIdentifier: confirmed via a debug accessibility-tree
        // dump while writing this test that every descendant of the
        // `map.selectedCard`-tagged VStack (MapExploreView.swift:876)
        // reports THAT container's identifier instead of its own more
        // specific one (e.g. this button's own `"map.card.cta"`,
        // MapExploreView.swift:869) — a real SwiftUI accessibility-tree
        // quirk for identifiers nested this way, not a bug in the button
        // itself; XCUITest's `[string]` subscript matches by label too, so
        // this works regardless.
        let cta = app.buttons["Xem chi tiết"]
        XCTAssertTrue(cta.waitForExistence(timeout: 5))
        cta.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["event.openInMap"].exists,
                       "Did not expect 'Open in map' when Event Detail was reached from Map's own sheet list")
    }

    /// Task 3: back/share used to live inside the hero photo (which
    /// scrolls away with the rest of the content); moved to a persistent
    /// overlay instead. Verified by actually scrolling the real ScrollView
    /// and confirming the back button is still hittable afterward, rather
    /// than just reading the source and trusting the modifier placement.
    func testBackButtonStaysVisibleWhileScrolling() {
        let app = launchSignedIn()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))

        let back = app.buttons["event.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable, "Expected the back pill to be hittable before scrolling")

        // Photos strip near the bottom of the content — several swipes to
        // get well past the hero photo's own height.
        for _ in 0..<4 { app.swipeUp() }

        XCTAssertTrue(back.exists, "Back pill should not have scrolled out of the accessibility tree")
        XCTAssertTrue(back.isHittable, "Expected the back pill to stay hittable after scrolling past the hero photo")
        back.tap()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 10),
                      "Back pill did not still work after scrolling")
    }
}

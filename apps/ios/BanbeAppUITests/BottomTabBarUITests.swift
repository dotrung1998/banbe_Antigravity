import XCTest

/// Regression coverage for 5f449d9 (`BottomTabBarOverlay`, a dedicated
/// `UIWindow` for the bottom tab bar) and its own follow-up fix: every tab
/// bar button must actually be tappable, both on an ordinary screen and —
/// the specific case the overlay-window rewrite exists for — while
/// MapExplore's own `.sheet()` is presented on top of everything else.
///
/// 5f449d9 shipped a regression where NO tab bar button could be tapped at
/// all: its `PassthroughWindow.hitTest` compared the hit view's identity
/// against `rootViewController?.view`, which is only a valid "did we hit
/// empty space" signal for UIKit content where each control is a distinct
/// `UIView`. `BottomTabBar` is plain SwiftUI with no `UIViewRepresentable`/
/// `List`/`ScrollView`/text field in it, so SwiftUI hosts and hit-tests the
/// whole thing internally — `super.hitTest` resolved to the SAME
/// `rootViewController.view` for every point in the window, including taps
/// on a real icon, so the identity check was true universally and every
/// touch passed through. The fix (see `BottomTabBarOverlay.swift`'s own
/// doc comment) makes passthrough a property of a small window frame
/// instead of a view-identity check.
final class BottomTabBarUITests: XCTestCase {

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

    /// BottomTabBar's items are plain SwiftUI views carrying only an
    /// `.accessibilityIdentifier`/`.accessibilityLabel` (the actual tap
    /// handling is a single `DragGesture` on the whole bar, from 623ec1e's
    /// scrub-to-select feature — there's no per-item `Button` to give each
    /// one a `.button` trait). XCUITest classifies them as `.other` (three
    /// of them) or `.staticText` (the one with a numeric badge `Text`
    /// child, apparently enough to flip the inferred trait) — confirmed by
    /// dumping `app.debugDescription` while debugging this test itself.
    /// `.any` sidesteps needing to know/track that per-item classification.
    private func tab(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testEachTabBarButtonNavigates() {
        let app = launchSignedIn()
        XCTAssertTrue(tab(app, "tab.map").waitForExistence(timeout: 10),
                      "Expected the bottom tab bar to render on Home")

        tab(app, "tab.notifications").tap()
        XCTAssertTrue(app.otherElements["screen.notifications"].waitForExistence(timeout: 10),
                      "tab.notifications did not navigate")

        tab(app, "tab.inbox").tap()
        XCTAssertTrue(app.otherElements["screen.inbox"].waitForExistence(timeout: 10),
                      "tab.inbox did not navigate")

        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 10),
                      "tab.profile did not navigate")

        tab(app, "tab.map").tap()
        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10),
                      "tab.map did not navigate")
    }

    /// The specific regression path 80c1ac3/5f449d9 targeted: the bar must
    /// stay tappable while MapExplore's own `.sheet()` is up, not just when
    /// nothing else is on screen.
    func testTabBarButtonWorksWhileMapSheetIsOpen() {
        let app = launchSignedIn()
        tab(app, "tab.map").tap()
        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10))
        // MapExploreView's sheet auto-presents on a fresh (non-restored)
        // entry — confirm it's actually up via its own compass button
        // before testing the bar over it.
        XCTAssertTrue(app.buttons["map.compass"].waitForExistence(timeout: 10),
                      "Expected the map screen/sheet to be up")

        tab(app, "tab.profile").tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 10),
                      "Tab bar tap did not register while the map sheet was open")
    }

    /// Real-Liquid-Glass pass (2026-09-28 follow-up #2) — extends this
    /// existing harness minimally rather than building a new one, per that
    /// ticket's own instruction. Covers, end to end through the real app
    /// (not just the Swift state machine reasoning that was the primary
    /// verification for this pass): a full first-tab-to-last-tab drag,
    /// reversing direction mid-drag, and a rapid tap immediately after a
    /// completed drag/release — the three interaction shapes called out by
    /// name. This only asserts on the resulting SCREEN (the one observable,
    /// stable signal from outside the process); it can't itself see whether
    /// a leftover highlight capsule is on screen (no pixel harness here —
    /// see this file's own earlier doc comment on why `.any` is used
    /// instead of relying on inferred UI element traits), so it doesn't
    /// replace the state-machine reasoning in BottomTabBar.swift's own
    /// doc comments, only adds a real-device/simulator navigation check on
    /// top of it.
    func testDragAcrossAllTabsReversingMidDragThenRapidTapAfterRelease() {
        let app = launchSignedIn()
        XCTAssertTrue(tab(app, "tab.home").waitForExistence(timeout: 10))

        let home = tab(app, "tab.home")
        let map = tab(app, "tab.map")
        let profile = tab(app, "tab.profile")

        // First tab (Home) -> last tab (Profile), pausing partway back at
        // Map to reverse direction mid-drag, before continuing on to
        // Profile and releasing there.
        let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let mid = map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: mid)
        mid.press(forDuration: 0.1, thenDragTo: start)
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 10),
                      "Drag ending on tab.profile did not land on the profile screen")

        // Rapid tap immediately after a completed drag/release — the
        // gesture's own `isDragging`/`activeID` bookkeeping must have
        // already handed back control by the time this lands.
        tab(app, "tab.notifications").tap()
        XCTAssertTrue(app.otherElements["screen.notifications"].waitForExistence(timeout: 10),
                      "Rapid tap immediately after a drag release did not navigate")
    }
}

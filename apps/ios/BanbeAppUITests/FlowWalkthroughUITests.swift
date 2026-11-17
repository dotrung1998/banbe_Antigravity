import XCTest

/// A real, multi-screen walkthrough driven the way a person drives the app:
/// taps and typing on the simulator, one screenshotted step per action, so the
/// whole flow can be reviewed afterwards instead of trusted.
///
/// Run it with `apps/ios/Tools/run-flow-walkthrough.sh`, which boots a
/// Simulator, runs only this suite, and exports every step's PNG to
/// `output/ios-flow-walkthrough/steps/NN-slug.png` in flow order.
///
/// The flow (guest-browsable screens only — no booking and no writes, so it is
/// safe to point at the real backend, and it works whether or not a session
/// happens to persist on the Simulator):
///
///   launch → [Welcome → "Explore events"] → Home
///          → Search (typed query) → Event Detail → Host tab → Back → Home
///
/// Screens and controls are addressed by their stable accessibility
/// identifiers, never by display copy (which is bilingual and would break
/// when the language changes) — the same convention as NavigationUITests.
final class FlowWalkthroughUITests: XCTestCase {

    private var app: XCUIApplication!
    private var stepIndex = 0

    override func setUp() {
        continueAfterFailure = false
        stepIndex = 0
    }

    // MARK: - Steps

    /// Records one step: the screenshot plus the step's own name, both kept
    /// even if a later assertion fails (`.keepAlways`), so a half-finished run
    /// still shows exactly where it got to.
    ///
    /// The name is `step-NN-slug` on purpose: no "/" (the result bundle strips
    /// it, see `scripts/lib/build_screenshot_catalog.py`), and a zero-padded
    /// number so the export can put the steps back in walking order.
    private func step(_ slug: String) {
        stepIndex += 1
        let name = String(format: "step-%02d-%@", stepIndex, slug)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Waits for a screen by its `screen.<name>` identifier (set in RootView).
    private func waitForScreen(_ name: String, timeout: TimeInterval = 30) -> Bool {
        app.otherElements["screen.\(name)"].waitForExistence(timeout: timeout)
    }

    // MARK: - The flow

    func testGuestBrowseHomeSearchEventAndBack() {
        app = XCUIApplication()
        app.launchArguments += [
            // Past language + theme onboarding: this walkthrough is about the
            // app's own flow, not the 3-question setup (note 80).
            "-banbe.onboarded", "YES",
            // A returning guest: Welcome's "Explore events" then goes straight
            // to Home instead of opening the one-time guest onboarding.
            "-banbe.guestOnboarding.v1", "YES",
            // Freeze live timers (story advance, the Home countdown tick) so
            // each screenshot shows a settled screen rather than a frame mid-motion.
            "-uiTesting", "1",
        ]
        app.launch()

        // 1. A fresh guest lands on the public Welcome; a guest who has already
        //    been through it lands straight on Home. Both are real entry states.
        let welcomeExplore = app.buttons["welcome.explore"]
        let onWelcome = welcomeExplore.waitForExistence(timeout: 10)
        if onWelcome {
            step("welcome")
            welcomeExplore.tap()
        }
        XCTAssertTrue(waitForScreen("home"), "Expected Home (guest browsing) after launch")
        step("home")

        // 2. Home → Search, by tapping the real search bar.
        let searchBar = app.buttons["home.searchBar"]
        XCTAssertTrue(searchBar.waitForExistence(timeout: 30), "Expected Home's search bar")
        searchBar.tap()

        let searchField = app.textFields["search.input"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Expected the Search field")
        step("search-idle")

        // 3. Type a query. "supper" matches the "Supper club" category label on
        //    every supper-club event, so it resolves without depending on any
        //    one event still being upcoming in live data.
        searchField.tap()
        searchField.typeText("supper")
        step("search-typed-supper")

        // 4. Open the first event result the typed query produced.
        let firstResult = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "search.event."))
            .firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 20),
                      "Expected at least one event result for \"supper\"")
        firstResult.tap()

        // 5. Event Detail, then a real in-page navigation (the Host tab), not a scroll.
        XCTAssertTrue(waitForScreen("event", timeout: 20), "Expected Event Detail from the search result")
        step("event-detail")

        // The v2.3 page keeps its tab row just above the fold until the page
        // has been scrolled, so scroll it in the way a reader would, then tap.
        let hostTab = app.buttons["event.tab.host"]
        XCTAssertTrue(hostTab.waitForExistence(timeout: 10), "Expected the Event Detail tabs")
        var swipes = 0
        while !hostTab.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(hostTab.isHittable, "Expected the Event Detail tabs after scrolling (tried \(swipes) swipes)")
        hostTab.tap()
        step("event-host-tab")

        // 6. Back out. From a search result, Back returns to the Search overlay
        //    still holding the query; from a Home card it goes straight Home.
        app.buttons["event.back"].tap()
        let backInSearch = searchField.waitForExistence(timeout: 10)
        step(backInSearch ? "back-in-search" : "back-home")

        if backInSearch {
            let close = app.buttons["search.back"]
            XCTAssertTrue(close.waitForExistence(timeout: 10), "Expected Search's Back button")
            close.tap()
        }
        XCTAssertTrue(waitForScreen("home", timeout: 20), "Expected the flow to end on Home")
        step("home-again")

        // The point of the walkthrough: every screen of the flow was reached
        // and captured, not just the first and last.
        XCTAssertGreaterThanOrEqual(stepIndex, 6, "Expected a step recorded for every screen in the flow")
    }
}

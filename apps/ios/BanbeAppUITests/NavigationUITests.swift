import XCTest

/// Smoke coverage for the screens and the navigation between them — the
/// iOS counterpart of the web app's Playwright suite. Each screen names
/// itself with a `screen.<name>` accessibility identifier (see RootView)
/// and the controls carry stable ids, the same way the web screens use
/// data-screen-label / data-testid rather than display copy (which is
/// bilingual and would break when the language changes).
///
/// These deliberately avoid anything needing a signed-in session: the
/// signed-out paths behave identically on every machine.
final class NavigationUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches straight into the feed, past onboarding.
    @discardableResult
    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15),
                      "Expected the feed to be the first screen")
        return app
    }

    func testOnboardingRunsThroughLanguageAndTheme() {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "NO"]
        app.launch()

        // The splash auto-advances after a moment; tapping skips the wait.
        if app.otherElements["screen.splash"].waitForExistence(timeout: 3) {
            app.tap()
        }
        XCTAssertTrue(app.otherElements["screen.langPick"].waitForExistence(timeout: 10))

        app.buttons["lang.vi"].tap()
        XCTAssertTrue(app.otherElements["screen.themePick"].waitForExistence(timeout: 5))

        app.buttons["theme.dark"].tap()
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5))
    }

    func testFeedOpensAnEventAndComesBack() {
        let app = launchToHome()

        let card = app.buttons["card.bepnho"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Expected the catalogue feed to render")
        card.tap()

        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))
        // Detail shows what the card doesn't — the "Included" row.
        XCTAssertTrue(app.staticTexts["Bao gồm"].waitForExistence(timeout: 5))

        app.buttons["event.back"].tap()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 5))
    }

    func testEventOpensTheOrganizerPage() {
        let app = launchToHome()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 5))

        // The organizer row sits below the hero photo and the description,
        // so it needs scrolling into view first — same as for a real user.
        let organizerRow = app.buttons["event.organizer"]
        XCTAssertTrue(organizerRow.waitForExistence(timeout: 5))
        var swipes = 0
        while !organizerRow.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        organizerRow.tap()

        XCTAssertTrue(app.otherElements["screen.organizer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sự kiện đang mở"].waitForExistence(timeout: 5))
    }

    func testCategoryFilterNarrowsTheFeed() {
        let app = launchToHome()
        XCTAssertTrue(app.buttons["card.bepnho"].waitForExistence(timeout: 15))

        app.buttons["filter.music"].tap()
        // A supper club event drops out of a music-only feed.
        XCTAssertTrue(waitForDisappearance(of: app.buttons["card.bepnho"]),
                      "Filter did not narrow the feed")
        XCTAssertTrue(app.buttons["card.jazzgac"].waitForExistence(timeout: 5))
    }

    func testAreaSheetOpensAndFiltersTheFeed() {
        let app = launchToHome()
        XCTAssertTrue(app.buttons["card.bepnho"].waitForExistence(timeout: 15))

        app.buttons["header.area"].tap()
        XCTAssertTrue(app.staticTexts["Khu vực"].waitForExistence(timeout: 5), "Area sheet did not open")

        app.buttons["area.thaodien"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["Khu vực"]))
        // Bình Thạnh events are gone; Thảo Điền ones remain.
        XCTAssertTrue(waitForDisappearance(of: app.buttons["card.bepnho"]))
        XCTAssertTrue(app.buttons["card.bandai"].waitForExistence(timeout: 5))
    }

    func testAccountAndPreferencesSwitchLanguage() {
        let app = launchToHome()
        app.buttons["header.account"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        app.buttons["account.preferences"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].waitForExistence(timeout: 5))

        // Switching to English retitles the screen in place.
        app.buttons["pref.lang.en"].tap()
        XCTAssertTrue(app.staticTexts["Language & appearance"].waitForExistence(timeout: 5))

        // Put it back, so a rerun starts from the same place.
        app.buttons["pref.lang.vi"].tap()
        XCTAssertTrue(app.staticTexts["Ngôn ngữ & hiển thị"].waitForExistence(timeout: 5))
    }

    func testDarkThemeRepaintsTheApp() {
        let app = launchToHome()
        app.buttons["header.account"].tap()
        app.buttons["account.preferences"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].waitForExistence(timeout: 5))

        app.buttons["pref.theme.dark"].tap()
        // Nothing to assert on colour directly, but the screen must survive
        // the repaint and stay interactive.
        XCTAssertTrue(app.buttons["pref.theme.light"].waitForExistence(timeout: 5))
        app.buttons["pref.theme.light"].tap()
        XCTAssertTrue(app.otherElements["screen.preferences"].exists)
    }

    func testSignedOutAccountOffersSignIn() throws {
        let app = launchToHome()
        app.buttons["header.account"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))

        // Only meaningful signed out; a restored session makes this a no-op.
        let signIn = app.buttons["account.signIn"]
        try XCTSkipUnless(signIn.waitForExistence(timeout: 3), "Already signed in on this simulator")

        signIn.tap()
        XCTAssertTrue(app.otherElements["screen.login"].waitForExistence(timeout: 5))
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

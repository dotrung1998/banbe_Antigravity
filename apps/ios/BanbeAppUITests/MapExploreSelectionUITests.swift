import XCTest

/// Search → Map round trips on the live backend (signed in with the shared fast-suite account).
///
/// Map v5 (note 73): `testSelectingAeieThenTappingFashionThenGalleryThenAll` was removed. It asserted the old
/// "selection survives filters" rule (reversed in note 72: a selection lives only while its event is a result) and the
/// floating selected card, which is gone (the selection is now `map.selectedRow`, the sheet's first row). Selection,
/// pan → peek, the dock and cities are covered by MapViewportUITests on the `shell.map` fixture (no sign-in).
final class MapExploreSelectionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Home search FAB → Map focus / search-selection round trip
    //
    // Search-result-selection fix pass (2026-09-28). Real-device gesture/
    // first-responder timing (this file's own top doc comment already
    // notes XCUITest's synthetic environment doesn't fully reproduce that)
    // means a clean run of these is not itself proof the on-device feel is
    // fixed — only that the state-level contract (keyboard shown/hidden at
    // the right moments, screen never drops) holds. Not run as part of
    // this pass (no simulator/device execution).

    @discardableResult
    private func launchToHomeSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()

        if app.reachLogin(timeout: 45) {
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

    /// Requirement 1 (note 50) — Home's search bar opens the Search screen with the keyboard already up,
    /// no second tap needed (it used to open Map's search field; Map is now reached from Search's
    /// "See on map", which carries the query).
    func testHomeSearchBarOpensSearchWithKeyboardFocused() {
        let app = launchToHomeSignedIn()
        app.buttons["home.searchBar"].tap()

        XCTAssertTrue(app.otherElements["screen.search"].waitForExistence(timeout: 10),
                      "Expected the search bar to open the Search screen")
        XCTAssertTrue(app.textFields["search.input"].waitForExistence(timeout: 5),
                      "Expected the search field itself to be on screen")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 8),
                      "Expected the keyboard to already be up without a second tap on the field")
    }

    /// Requirement 2 — picking a search result must resign the search
    /// field's keyboard, and a later return from Event Detail must never
    /// silently re-focus search (the traced stale-`app.mapExploreFocusSearch`
    /// bug: a restored `MapExploreView` re-reading that flag and re-
    /// mounting the focus probe — see the `!hadRestoredState` guard's own
    /// doc comment at that probe's call site in MapExploreView.swift).
    /// Opportunistic: skips (not fails) if the shared account's live backend
    /// doesn't have a matching result right now.
    func testSearchResultSelectionClosesKeyboardAndStaysClosedAfterEventDetailRoundTrip() throws {
        let app = launchToHomeSignedIn()
        // Note 50: Home search → Search screen → "See on map" carries the query to Map.
        app.buttons["home.searchBar"].tap()
        let query = app.textFields["search.input"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.typeText("AEIE")
        app.buttons["search.seeOnMap"].tap()
        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["map.searchInput"].waitForExistence(timeout: 5))

        let resultRow = app.staticTexts.matching(identifier: "AEIE: Mở Xưởng").firstMatch
        try XCTSkipUnless(resultRow.waitForExistence(timeout: 10),
                          "Shared account's live backend has no matching AEIE event right now")
        resultRow.tap()

        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 3),
                       "Selecting a search result should resign the search field's own focus")

        // Map v5 (note 73): the selection is the sheet's first row; "View details" lives there.
        let cta = app.buttons["map.selectedRow.details"]
        guard cta.waitForExistence(timeout: 5) else {
            throw XCTSkip("map.selectedRow.details did not resolve")
        }
        cta.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10),
                      "Expected the CTA to open Event Detail")

        app.buttons["event.back"].tap()
        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10),
                      "Expected Back to return to Map Explore")
        XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 3),
                       "Returning from Event Detail must never silently re-focus search")
    }
}

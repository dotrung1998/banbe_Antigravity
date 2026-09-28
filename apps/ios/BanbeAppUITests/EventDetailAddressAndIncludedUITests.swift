import XCTest

/// Real-event-maps-link + intro/included-parity fix pass (2026-09-28).
///
/// `CatalogEvent.lat`/`.lng` went from non-optional `Double` (silently
/// `0, 0` for every real event before this pass) to `Double?` — these
/// guard the two directly observable consequences: a known event with
/// REAL curated coordinates still shows "Xem trên bản đồ"/"Open in map"
/// (the button/action must not have regressed for the common case), and
/// the "Bao gồm"/Included row's tap-to-open-sheet behavior (new this
/// pass) works for an event that actually has structured content.
///
/// XCUITest's synthetic environment doesn't fully reproduce real-device
/// gesture/network timing (this suite's own established caveat — see
/// MapExploreSelectionUITests' top doc comment) — a clean run here is not
/// itself proof of the on-device feel, only that these state-level
/// contracts hold. Not run as part of this pass (no simulator/device
/// execution).
final class EventDetailAddressAndIncludedUITests: XCTestCase {

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

    /// A known DEMO catalogue event (`card.bepnho`, reused from
    /// MapExploreSelectionUITests' own `launchIntoMap` convention) always
    /// has real, curated, non-zero coordinates — deterministic, not
    /// opportunistic. Regression guard for the `Double?` refactor: this
    /// button must still appear for the common "has real coordinates"
    /// case, not just correctly disappear for the "doesn't" case.
    func testKnownEventWithCoordinatesShowsOpenInMap() {
        let app = launchSignedIn()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.buttons["event.openInMap"].waitForExistence(timeout: 5),
                      "A known event with real curated coordinates must still show 'Xem trên bản đồ' after the lat/lng-optional refactor")
    }

    /// Tapping "Xem trên bản đồ" must land on Map Explore with a pin at
    /// THIS event's own coordinates — `openEventOnMap(_:)`'s guard-unwrap
    /// (AppState.swift) means the tap only navigates when coordinates are
    /// genuinely present, which `testKnownEventWithCoordinatesShowsOpenInMap`
    /// already establishes for this event.
    func testOpenInMapNavigatesToMapExplore() {
        let app = launchSignedIn()
        app.buttons["card.bepnho"].tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10))

        let openInMap = app.buttons["event.openInMap"]
        XCTAssertTrue(openInMap.waitForExistence(timeout: 5))
        openInMap.tap()

        XCTAssertTrue(app.otherElements["screen.mapExplore"].waitForExistence(timeout: 10),
                      "Expected 'Xem trên bản đồ' to open Map Explore")
    }

    /// Requirement 2 (intro/included parity) — a real event with
    /// structured Included items shows a tappable row with a chevron;
    /// tapping it opens a sheet showing the introduction first (when the
    /// event has one) and the Included items below. Opportunistic: skips
    /// (not fails) if the shared account's live backend has no real event
    /// with included items right now, since this depends on live,
    /// mutable backend data, not a fixture.
    func testIncludedSectionOpensSheetWithIntroAndItems() throws {
        let app = launchSignedIn()

        // Real (non-demo) events surface through Dashboard's "my events"
        // list for a host account, or through Home's weekend/discovery
        // feed for any signed-in account — try the event detail row this
        // suite already knows how to reach a REAL event through: Map
        // Explore's own live-backed list (MapExploreSelectionUITests'
        // `launchIntoMap` reaches the same list via `header.mapExplore`).
        app.buttons["header.mapExplore"].tap()
        XCTAssertTrue(app.buttons["map.compass"].waitForExistence(timeout: 20))

        // Pins carry a per-event `map.pin.<id>` identifier (MapExploreView.swift)
        // — no single stable id exists for "any pin", so this matches by
        // prefix. Tapping one selects it (`map.selectedCard` + its own
        // `map.card.cta`), the same two-step "select, then open detail"
        // flow a real tap-through uses.
        let anyPin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).firstMatch
        try XCTSkipUnless(anyPin.waitForExistence(timeout: 15),
                          "No live Map Explore pins available right now")
        anyPin.tap()

        let cta = app.buttons["map.card.cta"]
        try XCTSkipUnless(cta.waitForExistence(timeout: 5), "map.card.cta did not resolve for this pin")
        cta.tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10),
                      "Expected the CTA to open Event Detail")

        let includedSection = app.buttons["event.includedSection"]
        try XCTSkipUnless(includedSection.waitForExistence(timeout: 10),
                          "This event has neither an introduction nor structured Included items right now")

        includedSection.tap()
        XCTAssertTrue(app.otherElements["event.includedSheet"].waitForExistence(timeout: 5),
                      "Expected tapping the Included row to open the intro/included sheet")

        app.buttons["event.includedSheet.close"].tap()
        XCTAssertFalse(app.otherElements["event.includedSheet"].exists,
                       "Expected the close button to actually dismiss the sheet")
    }
}

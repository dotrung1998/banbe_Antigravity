import XCTest

/// Real-device/simulator regression coverage for the 11-realtime-map.md
/// decoupling follow-up: a category filter change must never clear the
/// selected-event preview card, and the card must never narrow the list.
///
/// This test exists because a prior fix (feff5fe) was verified only by
/// reading the source and by a Playwright (web) sweep, and still shipped a
/// real iOS-only bug: `MapExploreView`'s `lastQueriedRegion` froze itself
/// from the FIRST `onMapCameraChange` callback ever received, which could
/// (and on a fresh launch, reliably did) fire before MapKit had caught up
/// to the density-hotspot camera position this screen sets on load —
/// reporting a region nowhere near Vietnam. Every later bounded poll/
/// pagination reload then legitimately returned zero rows for that bogus
/// region, silently wiping `app.mapEvents` to empty — which, correctly per
/// the *filter* decoupling fix, cleared the selection too, since the event
/// really was "gone" from the app's own data at that point. A category
/// filter tap was what usually surfaced it first, because
/// `recenterOnFilterDensityHotspot()`'s own camera move was often the very
/// first camera change the map ever made on a fresh launch — see
/// `centerOnDensityHotspot()`'s fix in `MapExploreView.swift`.
///
/// Assertions read the LIST/card state only through `staticTexts` (the
/// event title's own text) rather than the card's outer container or
/// button identifiers — `map.selectedCard`/`map.card.cta` proved unreliable
/// to resolve through XCUITest's accessibility snapshot in this
/// environment specifically (screenshots taken mid-run repeatedly showed
/// the card genuinely on screen at moments those particular queries still
/// reported it absent), a known class of issue with SwiftUI content
/// overlaid on a MapKit `Map`. Counting the title text avoids that entirely
/// and was reliable throughout every run.
final class MapExploreSelectionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Mandatory login (09-auth-onboarding.md) means a fresh simulator
    /// lands on Login, not Home — no guest browsing exists. Signs in with
    /// the same shared fast-suite test account `tests/global-setup.js`
    /// already uses for the web Playwright suite (password auth, not
    /// OAuth, so it's automatable here).
    @discardableResult
    private func launchIntoMap() -> XCUIApplication {
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
        app.buttons["header.mapExplore"].tap()
        XCTAssertTrue(app.buttons["map.compass"].waitForExistence(timeout: 20),
                      "Expected Map Explore to open")
        return app
    }

    /// Category chips carry no accessibilityIdentifier (only the glyph +
    /// localized label), so they're found by their visible text.
    private func chip(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Once selected, "AEIE: Mở Xưởng" legitimately appears TWICE (the list
    /// row AND the card's own title) whenever the active filter still
    /// includes it, and exactly ONCE (the card only) once a non-matching
    /// filter narrows the row away — 0 means the card itself is gone (the
    /// bug this test guards against).
    private func aeieMatchCount(_ app: XCUIApplication) -> Int {
        app.staticTexts.matching(identifier: "AEIE: Mở Xưởng").count
    }

    /// Polls `aeieMatchCount` until it reaches `expected` or `timeout`
    /// elapses — a plain instant read can race the sheet/card's own
    /// animation settling in on a freshly launched, cold simulator.
    @discardableResult
    private func waitForAeieMatchCount(_ app: XCUIApplication, _ expected: Int, timeout: TimeInterval = 15) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var last = aeieMatchCount(app)
        while last != expected && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            last = aeieMatchCount(app)
        }
        return last
    }

    func testSelectingAeieThenTappingFashionThenGalleryThenAll() {
        let app = launchIntoMap()

        let aeieRow = app.staticTexts.matching(identifier: "AEIE: Mở Xưởng").firstMatch
        XCTAssertTrue(aeieRow.waitForExistence(timeout: 20), "Expected AEIE row to load from the live backend")
        // A brief settle after the row first appears — the initial
        // loadMapEvents() page-in (triggered by the last visible row's
        // onAppear) can still be landing new rows for a moment right after
        // the list first renders.
        Thread.sleep(forTimeInterval: 1.5)
        aeieRow.tap()

        XCTAssertEqual(waitForAeieMatchCount(app, 2, timeout: 20), 2,
                       "Expected both the list row and the card title visible after selecting")

        // Fashion (AEIE's own category — matches, so this step alone would
        // pass even with the coupling bug, since the list still contains
        // AEIE either way).
        chip(app, "Thời trang").tap()
        XCTAssertEqual(waitForAeieMatchCount(app, 2), 2,
                       "BUG: list row and/or card disappeared after tapping Fashion (its own category)")

        // Gallery — a category AEIE is NOT in (its cat_key is "fashion" per
        // the live seed data, not "gallery"; "Vùng Trắng" is the gallery
        // one). This is the case the original coupling bug broke (card
        // cleared because AEIE dropped out of visibleEvents) and also the
        // case the lastQueriedRegion bug broke (an empty app.mapEvents
        // wipes the card regardless of which category was tapped).
        chip(app, "Phòng tranh").tap()
        XCTAssertEqual(waitForAeieMatchCount(app, 1), 1,
                       "BUG: expected only the card's title left (list row should narrow out, card must stay)")

        // Back to "Tất cả" — card and full list both correct.
        chip(app, "Tất cả").tap()
        XCTAssertEqual(waitForAeieMatchCount(app, 2), 2,
                       "BUG: list row and/or card disappeared after returning to All")
    }
}

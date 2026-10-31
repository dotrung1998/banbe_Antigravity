import XCTest

/// Map redesign phase 2 (web twin: tests/map-viewport.spec.js): the explored map area defines the results. Uses the
/// DEBUG `shell.map` fixture (opens straight on the Map; live public events), so no sign-in is needed.
final class MapViewportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES", "-uiFixture", "shell.map"]
        app.launch()
        return app
    }

    private func count(_ app: XCUIApplication) -> String {
        app.staticTexts["map.resultCount"].label
    }

    private func waitForCount(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["map.resultCount"]
        XCTAssertTrue(label.waitForExistence(timeout: 30))
        let settled = NSPredicate(format: "label MATCHES %@", ".*\\d+ (sự kiện|events?).*")
        expectation(for: settled, evaluatedWith: label)
        waitForExpectations(timeout: 30)
        return label.label
    }

    func testFirstOpenFramesResultsAndPinsMatchTheCount() throws {
        let app = launch()
        let text = waitForCount(app)
        let n = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        XCTAssertGreaterThan(n, 0, "first open should frame the relevant events, not an empty part of the world")
        let pins = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'"))
        XCTAssertEqual(pins.count, n, "pins and count come from the same results")
        XCTAssertFalse(app.buttons["map.searchHere"].exists, "results follow the map; no Search here button")
    }

    func testPanningFarAwayCommitsANewAreaAndShowNearestBringsResultsBack() throws {
        let app = launch()
        let before = waitForCount(app)
        // Fling the map far east several times (a user gesture): the area changes once each settle.
        let map = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        for _ in 0..<4 {
            map.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)))
        }
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: app.staticTexts["map.resultCount"])
        waitForExpectations(timeout: 10)
        let nearest = app.buttons["map.showNearest"]
        if nearest.waitForExistence(timeout: 3) {
            nearest.tap()
            let back = NSPredicate(format: "NOT (label BEGINSWITH '0 ')")
            expectation(for: back, evaluatedWith: app.staticTexts["map.resultCount"])
            waitForExpectations(timeout: 10)
        }
    }

    // MARK: Phase 3 — shared, contextual filters

    func testTimeChipFiltersInPlaceAndPinsFollowTheCount() throws {
        let app = launch()
        _ = waitForCount(app)
        let weekend = app.buttons["map.weekend"]
        XCTAssertTrue(weekend.waitForExistence(timeout: 10))
        weekend.tap()
        XCTAssertTrue(weekend.isSelected, "the chip shows its state")
        sleep(1)
        let text = count(app)
        let n = Int(text.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "0") ?? 0
        let pins = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'"))
        XCTAssertEqual(pins.count, n, "pins and count stay one list under a time filter")
        weekend.tap()
        XCTAssertFalse(weekend.isSelected)
    }

    func testFilterSheetCloseDiscardsAndApplyCommits() throws {
        let app = launch()
        let before = waitForCount(app)
        let filtersChip = app.buttons["map.filters"]
        XCTAssertTrue(filtersChip.waitForExistence(timeout: 10))
        filtersChip.tap()
        let week = app.buttons["home.filter.date.week"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.filter.date.tonight"].exists, "Map offers Tonight")
        XCTAssertFalse(app.buttons["home.filter.area"].exists, "the map is the location")
        week.tap()
        app.buttons["home.filter.close"].tap()
        sleep(1)
        XCTAssertEqual(count(app), before, "Close discards the draft")
        XCTAssertFalse(app.buttons["map.filters"].label.contains("·"))

        app.buttons["map.filters"].tap()
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        let apply = app.buttons["home.filter.apply"]
        let shown = Int(apply.value as? String ?? "0") ?? 0
        try XCTSkipIf(shown == 0, "no live event in the next 7 days")
        apply.tap()
        sleep(1)
        XCTAssertTrue(count(app).hasPrefix("\(shown) "), "Show N is the resulting list")
        XCTAssertTrue(app.buttons["map.filters"].label.contains("· 1"))
    }

    func testSelectingAPinRevealsItWithoutANewSearch() throws {
        let app = launch()
        let before = waitForCount(app)
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.pin.'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        sleep(3) // the reveal flight + its settle
        XCTAssertEqual(count(app), before, "a reveal never changes the area, the results or the count")
    }
}

import XCTest

/// Map E+ step 7 (note 79; web twin: tests/map-eplus.spec.js): the day menu + two-knob hour range. Uses the DEBUG
/// `shell.map` fixture (live public events). Cheap checks only: the knobs respond to VoiceOver-style adjust, the
/// "List · N" count only ever shrinks when a window is switched on, and the dock steps aside while a panel is open.
final class MapEPlusUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES", "-uiFixture", "shell.map"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func listCount(_ app: XCUIApplication) -> Int {
        Int(el(app, "map.listButton").value as? String ?? "-1") ?? -1
    }

    /// Wait for the loaded, framed map (the settled count says "N events").
    private func waitLoaded(_ app: XCUIApplication) {
        let label = app.staticTexts["map.resultCount"]
        XCTAssertTrue(label.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "label MATCHES %@", ".*\\d+ (sự kiện|events?).*"), evaluatedWith: label)
        waitForExpectations(timeout: 30)
        sleep(2)
    }

    /// Drag a knob sideways (nearest-knob drag on the track).
    private func drag(_ knob: XCUIElement, dx: CGFloat) {
        let start = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
    }

    private func barValue(_ app: XCUIApplication) -> String { el(app, "map.timeBar").value as? String ?? "" }

    private func pickDay(_ app: XCUIApplication, _ key: String) {
        let menu = el(app, "map.time.day")
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the day button is on the map")
        menu.tap()
        let item = app.buttons["map.time.day.\(key)"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the day menu lists \(key)")
        item.tap()
    }

    func testKnobsAreInertUntilADayIsPickedThenAdjust() throws {
        let app = launch()
        waitLoaded(app)
        XCTAssertTrue(el(app, "map.timeBar").waitForExistence(timeout: 10), "the time bar is on the map")
        XCTAssertFalse(barValue(app).contains(":"), "All days = no hours, the range is off")
        pickDay(app, "tomorrow")
        let from = el(app, "map.time.from")
        XCTAssertTrue(from.waitForExistence(timeout: 5), "a day turns the range on")
        XCTAssertEqual(from.value as? String, "17:00", "a later day starts at 17:00")
        XCTAssertEqual(el(app, "map.time.to").value as? String, "02:00", "the range runs to 02:00")
        drag(from, dx: -40)
        XCTAssertNotEqual(from.value as? String, "17:00", "the From knob moved")
        XCTAssertTrue(barValue(app).contains(from.value as? String ?? "?"), "the bar speaks the new hour")
        pickDay(app, "all")
        XCTAssertFalse(barValue(app).contains(":"), "All days switches the window back off")
    }

    func testListCountOnlyShrinksWithAWindowAndWidensWithTheRange() throws {
        let app = launch()
        waitLoaded(app)
        let all = listCount(app)
        XCTAssertGreaterThan(all, 0)
        pickDay(app, "nextWeek")
        sleep(1)
        let narrow = listCount(app)
        XCTAssertLessThanOrEqual(narrow, all, "a window only dims; it never adds events")
        // Whole range (10:00 to 02:00): at least as many as 17:00 to 02:00.
        let from = el(app, "map.time.from")
        XCTAssertTrue(from.waitForExistence(timeout: 5))
        drag(from, dx: -150)
        XCTAssertEqual(from.value as? String, "10:00", "dragged to the start of the range")
        sleep(1)
        XCTAssertGreaterThanOrEqual(listCount(app), narrow, "widening the range never loses events")
        XCTAssertLessThanOrEqual(listCount(app), all)
    }

    func testDockStepsAsideWhileAnAreaPanelIsOpen() throws {
        let app = launch()
        waitLoaded(app)
        let bubble = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'map.areaBubble.' AND NOT identifier CONTAINS '+'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 20), "the map opens on neighbourhood bubbles")
        XCTAssertTrue(el(app, "tab.home").exists, "the dock shows at rest")
        bubble.tap()
        XCTAssertTrue(el(app, "map.areaPanel").waitForExistence(timeout: 8))
        XCTAssertTrue(el(app, "map.timeBar").exists, "the time bar rides above the panel")
        XCTAssertFalse(el(app, "tab.home").waitForExistence(timeout: 3) && el(app, "tab.home").isHittable, "the dock is out of the way")
    }
}

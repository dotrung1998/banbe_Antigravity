import XCTest

/// Map E+ plan step 0 (note 79): the in-hierarchy list + `ListTopPullProbe` pull-down, on the DEBUG-only
/// `spike.mapList` screen. Simulated touches are not a real finger: this proves the logic, the device check is separate.
final class MapListSpikeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES", "-uiFixture", "spike.mapList"]
        app.launch()
        return app
    }

    private func readout(_ app: XCUIApplication) -> String { app.staticTexts["spike.readout"].label }

    private func openList(_ app: XCUIApplication) {
        let button = app.buttons["spike.listButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)["spike.row.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(readout(app).contains("list open"))
    }

    /// Drag from a point inside the list by `dy` points, with a hold so it is not read as a flick.
    private func pull(_ app: XCUIApplication, dy: CGFloat) {
        let list = app.descendants(matching: .any)["spike.list"].firstMatch
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = start.withOffset(CGVector(dx: 0, dy: dy))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func testLongPullFromTheTopClosesTheList() {
        let app = launch()
        openList(app)
        pull(app, dy: 300)
        XCTAssertTrue(app.buttons["spike.listButton"].waitForExistence(timeout: 5), "a long pull returns to the map")
        XCTAssertTrue(readout(app).contains("closes 1"))
    }

    func testShortPullSpringsBack() {
        let app = launch()
        openList(app)
        pull(app, dy: 60)
        sleep(1)
        XCTAssertTrue(readout(app).contains("list open"), "a short pull snaps back, the list stays open")
        XCTAssertTrue(readout(app).contains("closes 0"))
    }

    func testMapButtonCloses() {
        let app = launch()
        openList(app)
        app.buttons["map.list.mapButton"].tap()
        XCTAssertTrue(app.buttons["spike.listButton"].waitForExistence(timeout: 5))
    }

    func testScrollingNeverClosesAndRowsStillTap() {
        let app = launch()
        openList(app)
        let list = app.descendants(matching: .any)["spike.list"].firstMatch
        list.swipeUp(); list.swipeUp()
        XCTAssertTrue(readout(app).contains("list open"), "scrolling down does not move the sheet")
        // A row that is now on screen still takes its tap (the pull recognizer never swallows taps).
        let visible = (1...40).map { app.descendants(matching: .any)["spike.row.\($0)"].firstMatch }
            .first { $0.exists && $0.isHittable }
        XCTAssertNotNil(visible)
        visible?.tap()
        XCTAssertTrue(readout(app).contains("taps 1"), readout(app))
        XCTAssertTrue(readout(app).contains("list open"))
    }
}

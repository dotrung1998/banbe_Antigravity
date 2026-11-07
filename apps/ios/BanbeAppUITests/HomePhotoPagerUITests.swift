import XCTest

/// Map v6 (note 74): Home's discovery cards carry the same photo pager as the Map's Large cards. A sideways swipe on
/// the photos pages them and never switches dock tabs. `-uiFixture shell.home`: fx-near and fx-later have three
/// bundled photos each (UITestFixtures `demoGallery`), no network.
final class HomePhotoPagerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testSwipingACardsPhotosNeverSwitchesTabs() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.home", "-banbe.lang", "en", "-uiTesting", "1", "-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 20))
        el(app, "home.layout.cards").tap()
        // The whole pager must sit above the floating dock: XCUITest swipes at an element's hittable point, and a
        // swipe that starts on the dock scrubs between tabs (that is the dock's own gesture, not the pager's).
        let pager = el(app, "photoPager.fx-near")
        let screenH = app.windows.firstMatch.frame.height
        var tries = 0
        while !(pager.exists && pager.frame.minY > 120 && pager.frame.maxY < screenH - 160) && tries < 12 {
            if pager.exists && pager.frame.minY <= 120 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            }
            tries += 1
        }
        XCTAssertTrue(pager.exists && pager.isHittable, "a multi-photo card shows its pager")
        let id = pager.identifier.replacingOccurrences(of: "photoPager.", with: "")
        let counter = el(app, "photoPager.counter.\(id)")
        XCTAssertEqual(counter.value as? String, "1/3")
        let mid = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        mid.press(forDuration: 0.05, thenDragTo: pager.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        sleep(1)
        XCTAssertEqual(el(app, "photoPager.counter.\(id)").value as? String, "2/3", "the swipe paged the photos")
        XCTAssertTrue(el(app, "home.title").exists || el(app, "home.layout.cards").exists, "still on Home")
        XCTAssertFalse(el(app, "screen.schedule").exists, "the swipe did not switch tabs")
        XCTAssertFalse(el(app, "screen.mapExplore").exists, "the swipe did not switch to the Map tab")
    }
}

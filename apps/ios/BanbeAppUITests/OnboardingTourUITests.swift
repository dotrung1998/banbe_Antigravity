import XCTest

/// Note 64 — onboarding Version 3: the guided tour over the real shell (Home / dock / Account). The fixture starts it
/// as a replay (`-uiFixtureTourV3 YES`), so no first-run marker is written. The shell fixture has no For You
/// preferences unless `-uiFixtureForYou YES`, which makes step 2 a missing target: the tour must skip it.
/// Set TOUR_SHOTS (TEST_RUNNER_TOUR_SHOTS=…) to save review screenshots to that folder.
final class OnboardingTourUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ variant: String = "home", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.\(variant)", "-banbe.lang", "en", "-banbe.theme", "light", "-uiTesting", "1", "-banbe.onboarded", "YES",
                                "-uiFixtureTourV3", "YES"] + extra
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["TOUR_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func waitLabel(_ e: XCUIElement, contains text: String, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    func testNextBackStepJumpAndMissingTargetSkip() {
        let app = launch()
        let title = el(app, "tour.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the tour starts over the real Home")
        XCTAssertTrue(waitLabel(title, contains: "Find anything here"))
        shot("tour-1-search")

        // No For You preferences in this fixture: step 2's target never appears, so Next lands on step 3.
        el(app, "tour.next").tap()
        XCTAssertTrue(waitLabel(title, contains: "An event", timeout: 6), "missing For You target is skipped")
        XCTAssertFalse(el(app, "tour.step.2").isEnabled, "a skipped step can't be picked")
        shot("tour-3-event")

        // Direct jump to any step, then Back.
        el(app, "tour.step.5").tap()
        XCTAssertTrue(waitLabel(title, contains: "Schedule"))
        el(app, "tour.back").tap()
        XCTAssertTrue(waitLabel(title, contains: "Map"))
        shot("tour-4-map")

        // Account step moves to the real Account screen.
        el(app, "tour.step.7").tap()
        XCTAssertTrue(waitLabel(title, contains: "Want to host?", timeout: 6))
        shot("tour-7-account")
        XCTAssertEqual(el(app, "tour.next").label, "Done", "a non-host has no Create step, so this is the last one")

        el(app, "tour.next").tap()
        XCTAssertFalse(el(app, "tour.overlay").waitForExistence(timeout: 2) && el(app, "tour.overlay").exists)
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5), "Finish lands on Home")
    }

    func testHighlightedControlIsNeverPressed() {
        let app = launch()
        XCTAssertTrue(el(app, "tour.title").waitForExistence(timeout: 20))
        // Tap where the real search bar is (upper part of the screen): the scrim swallows it, Search never opens.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        XCTAssertTrue(el(app, "tour.title").exists, "still on the tour")
        XCTAssertFalse(el(app, "search.input").waitForExistence(timeout: 1.5), "the search overlay never opened")
        el(app, "tour.skip").tap()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
    }

    func testHostSeesCreateStep() {
        let app = launch("account")
        let title = el(app, "tour.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertTrue(el(app, "tour.step.8").exists, "organizer mode adds the Create step")
        el(app, "tour.step.8").tap()
        XCTAssertTrue(waitLabel(title, contains: "Create an event", timeout: 6))
        shot("tour-8-create")
    }
}

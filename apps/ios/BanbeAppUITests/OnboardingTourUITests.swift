import XCTest

/// Note 64, forward-only chapters since note 80: the guided tour over the real shell (Home / dock / Account). The
/// fixture starts it as a replay (`-uiFixtureTourV3 YES`), so no first-run marker is written. The shell fixture has
/// no For You preferences unless `-uiFixtureForYou YES`, which makes the For You step a missing target: the tour must
/// skip it. Set TOUR_SHOTS (TEST_RUNNER_TOUR_SHOTS=…) to save review screenshots to that folder.
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

    func testForwardOnlyChaptersBreaksAndMissingTargetSkip() {
        let app = launch()
        let title = el(app, "tour.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the tour starts over the real Home")
        XCTAssertTrue(waitLabel(title, contains: "Search and area"))
        XCTAssertTrue(waitLabel(el(app, "tour.chapter"), contains: "CHAPTER 1 OF 3"))
        XCTAssertFalse(el(app, "tour.back").exists, "no Back")
        XCTAssertFalse(el(app, "tour.step.1").exists, "the progress bar can't be used to jump")
        shot("tour-1-search")

        // No For You preferences in this fixture: that step's target never appears, so Next lands on the event card.
        el(app, "tour.next").tap()
        XCTAssertTrue(waitLabel(title, contains: "Open an event", timeout: 6), "missing For You target is skipped")
        el(app, "tour.next").tap()
        XCTAssertTrue(waitLabel(title, contains: "Map"))
        XCTAssertEqual(el(app, "tour.next").label, "Finish chapter")
        el(app, "tour.next").tap()

        // Chapter break: the only place to stop.
        XCTAssertTrue(el(app, "tour.break.title").waitForExistence(timeout: 5))
        XCTAssertTrue(waitLabel(el(app, "tour.break.title"), contains: "Next: plans and messages"))
        shot("tour-break-1")
        el(app, "tour.break.continue").tap()
        XCTAssertTrue(waitLabel(title, contains: "Schedule", timeout: 6))
        el(app, "tour.next").tap()
        XCTAssertTrue(waitLabel(title, contains: "Messages"))
        el(app, "tour.next").tap()
        XCTAssertTrue(el(app, "tour.break.continue").waitForExistence(timeout: 5))
        el(app, "tour.break.continue").tap()

        // The account chapter moves to the real Account screen; a non-host has no Create step.
        XCTAssertTrue(waitLabel(title, contains: "Hosting mode", timeout: 6))
        XCTAssertTrue(waitLabel(el(app, "tour.body"), contains: "Off, as you chose"))
        shot("tour-account")
        XCTAssertEqual(el(app, "tour.next").label, "Finish chapter")
        el(app, "tour.next").tap()

        XCTAssertTrue(el(app, "tour.finish.title").waitForExistence(timeout: 5), "the closing sheet after the last chapter")
        shot("tour-finish")
        el(app, "tour.finish.done").tap()
        XCTAssertFalse(el(app, "tour.overlay").waitForExistence(timeout: 2) && el(app, "tour.overlay").exists)
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5), "Finish lands on Home")
    }

    func testFinishForNowAtABreakEndsOnHome() {
        let app = launch()
        XCTAssertTrue(el(app, "tour.title").waitForExistence(timeout: 20))
        for _ in 0..<6 where !el(app, "tour.break.stop").exists {
            if el(app, "tour.next").exists { el(app, "tour.next").tap() }
            _ = el(app, "tour.break.stop").waitForExistence(timeout: 3)
        }
        el(app, "tour.break.stop").tap()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
    }

    func testDoItStepOnlyMovesOnFromItsControl() {
        let app = launch(extra: ["-uiFixtureForYou", "YES"])
        let title = el(app, "tour.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        el(app, "tour.next").tap()
        XCTAssertTrue(waitLabel(title, contains: "Your For You picks", timeout: 6))
        XCTAssertFalse(el(app, "tour.next").exists, "a do-it step has no Next")
        // A tap elsewhere does nothing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(waitLabel(title, contains: "Your For You picks"))
        el(app, "tour.doIt").tap()
        XCTAssertTrue(waitLabel(title, contains: "Open an event", timeout: 6))
    }

    func testHighlightedControlIsNeverPressed() {
        let app = launch()
        XCTAssertTrue(el(app, "tour.title").waitForExistence(timeout: 20))
        // Tap where the real search bar is (upper part of the screen): the scrim swallows it, Search never opens.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        XCTAssertTrue(el(app, "tour.title").exists, "still on the tour")
        XCTAssertFalse(el(app, "search.input").waitForExistence(timeout: 1.5), "the search overlay never opened")
        el(app, "tour.end").tap()
        XCTAssertTrue(el(app, "home.title").waitForExistence(timeout: 5))
    }

    func testHostSeesCreateStep() {
        let app = launch("account")
        let title = el(app, "tour.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        for _ in 0..<12 where !waitLabel(title, contains: "Create an event", timeout: 1) {
            if el(app, "tour.break.continue").exists { el(app, "tour.break.continue").tap() }
            else if el(app, "tour.doIt").exists { el(app, "tour.doIt").tap() }
            else if el(app, "tour.next").exists { el(app, "tour.next").tap() }
        }
        XCTAssertTrue(waitLabel(title, contains: "Create an event", timeout: 6), "organizer mode adds the Create step")
        shot("tour-create")
    }
}

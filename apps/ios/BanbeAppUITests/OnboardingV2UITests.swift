import XCTest

/// Note 63 — onboarding Version 2 (admin switch `onboarding_v2`): animated Welcome entrance and, per "How banbe
/// works" section, a swipeable deck of demo screens with Next/Skip. Version 1 is covered by
/// PublicEntryScheduleUITests / ReviewRetentionUITests (fixtures default to the switch being off).
/// Set HIW_SHOTS (TEST_RUNNER_HIW_SHOTS=…) to save review screenshots to that folder.
final class OnboardingV2UITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(v2: Bool = true, lang: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "auth", "-banbe.lang", lang, "-uiTesting", "1",
                                "-uiFixtureOnboardingV2", v2 ? "YES" : "NO"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["HIW_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testVersionTwoDeckSwipesAndNextReachesTheEnd() {
        let app = launch()
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.35)
        shot("ios-welcome-mid")
        Thread.sleep(forTimeInterval: 2.0)
        shot("ios-welcome-end")
        el(app, "welcome.story.open").tap()

        XCTAssertTrue(el(app, "hiw.deck").waitForExistence(timeout: 5), "Version 2 shows the demo deck")
        XCTAssertFalse(el(app, "welcome.story.point.0.0").exists, "not the Version 1 text points")
        XCTAssertEqual(el(app, "hiw.dots").label, "Screen 1 of 3")
        let caption0 = el(app, "hiw.caption").label
        el(app, "hiw.deck").swipeLeft()
        let moved = NSPredicate(format: "label == %@", "Screen 2 of 3")
        expectation(for: moved, evaluatedWith: el(app, "hiw.dots"))
        waitForExpectations(timeout: 5)
        XCTAssertNotEqual(el(app, "hiw.caption").label, caption0, "the caption follows the centred screen")
        Thread.sleep(forTimeInterval: 1.0)
        shot("ios-story-1")

        for page in 1...3 {
            el(app, "welcome.story.next").tap()
            XCTAssertTrue(el(app, "welcome.story.heading.\(page)").waitForExistence(timeout: 5))
            XCTAssertEqual(el(app, "welcome.story.progress").label, "\(page + 1) of 4")
            Thread.sleep(forTimeInterval: 1.6)
            shot("ios-story-\(page + 1)")
        }
        XCTAssertFalse(el(app, "welcome.story.next").exists)
        XCTAssertTrue(el(app, "welcome.login").waitForExistence(timeout: 5), "the last section offers the sign-up/log-in routes")
    }

    /// Owner, 2026-10-24: on a section's last screen a grey chevron pulses at the right edge, and swiping on moves to
    /// the next section (Next stays). On the very last screen a bouncing "done" hint; swiping on thanks the person.
    /// Screenshots every card (HIW_SHOTS) for visual review.
    func testEveryCardAndSwipeToFinish() {
        let app = launch()
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        let counts = [3, 4, 3, 7]
        for (page, count) in counts.enumerated() {
            XCTAssertTrue(el(app, "welcome.story.heading.\(page)").waitForExistence(timeout: 5))
            XCTAssertTrue(el(app, "hiw.deck").waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 1.3)
            for card in 0..<count {
                if card > 0 { el(app, "hiw.deck").swipeLeft(); Thread.sleep(forTimeInterval: 0.9) }
                shot("ios-s\(page + 1)-c\(card + 1)")
            }
            if page < 3 {
                XCTAssertTrue(el(app, "hiw.nextSectionHint").waitForExistence(timeout: 5), "grey hint on the last screen")
                el(app, "hiw.deck").swipeLeft() // swipe past → next section
            } else {
                XCTAssertTrue(el(app, "hiw.finishHint").waitForExistence(timeout: 5), "bouncing finish hint on the very last screen")
                el(app, "hiw.deck").swipeLeft() // swipe past → thank you
            }
        }
        XCTAssertTrue(el(app, "hiw.thanks").waitForExistence(timeout: 5), "thank-you after the last swipe")
        Thread.sleep(forTimeInterval: 1.5)
        shot("ios-thanks")
        XCTAssertTrue(el(app, "welcome.login").exists, "sign-up / log-in stay under the thank-you")
    }

    func testVersionTwoDemoControlsRespond() {
        let app = launch()
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        el(app, "welcome.story.next").tap()
        XCTAssertTrue(el(app, "hiw.tickets.3").waitForExistence(timeout: 5))
        let before = el(app, "hiw.tickets.total").label
        el(app, "hiw.tickets.3").tap()
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: el(app, "hiw.tickets.total"))
        waitForExpectations(timeout: 5)
    }

    func testVersionTwoSkipReturnsToWelcome() {
        let app = launch()
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        XCTAssertTrue(el(app, "welcome.story.skip").waitForExistence(timeout: 5))
        el(app, "welcome.story.skip").tap()
        XCTAssertTrue(el(app, "welcome.heading").waitForExistence(timeout: 5))
    }

    func testVersionOneKeepsTheTextPages() {
        let app = launch(v2: false)
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        XCTAssertTrue(el(app, "welcome.story.point.0.0").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "hiw.deck").exists)
    }
}

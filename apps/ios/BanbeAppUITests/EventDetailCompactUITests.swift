import XCTest

/// Note 68 — the compact Event Detail (web twin: tests/event-detail-compact.spec.js), against the DEBUG `shell.event`
/// fixture: Date / Time / Place, the Host row and the CTA are on screen without scrolling, the three tiles share one
/// height, the host appears once, and minimum age sits in the header beside the category.
final class EventDetailCompactUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.event", "-banbe.lang", "en", "-banbe.theme", theme,
                                "-uiTesting", "1", "-banbe.onboarded", "YES", "-uiFixtureEventTypes", "YES",
                                "-uiFixtureEventKey", "bepnho"]
        app.launch()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testKeyFactsHostAndCTAAboveTheFold() {
        for theme in ["light", "dark"] {
            let app = launch(theme: theme)
            let when = el(app, "event.fact.when")
            XCTAssertTrue(when.waitForExistence(timeout: 10))
            sleep(1)
            let screen = app.windows.firstMatch.frame
            let bar = el(app, "event.actionBar").frame
            XCTAssertTrue(el(app, "event.actionBar").isHittable, "the CTA is on screen")
            for id in ["event.fact.when", "event.fact.time", "event.fact.where", "event.organizer"] {
                let f = el(app, id).frame
                XCTAssertGreaterThan(f.height, 0, id)
                XCTAssertLessThanOrEqual(f.maxY, min(screen.maxY, bar.minY) + 1, "\(id) is above the fold and the sticky bar (\(theme))")
            }
            let heights = ["event.fact.when", "event.fact.time", "event.fact.where"].map { el(app, $0).frame.height }
            XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 1, "the three tiles share one height")
            // The host appears once (regression: a track-record line used to repeat it above the Host card).
            XCTAssertFalse(el(app, "event.trackRecord").exists)
            XCTAssertEqual(app.buttons.matching(identifier: "event.organizer").count, 1)
            // Minimum age is a pill in the header, on the category's row.
            let age = el(app, "event.typeFact.min_age"), cat = el(app, "event.category")
            XCTAssertTrue(age.exists && cat.exists)
            XCTAssertEqual(age.frame.midY, cat.frame.midY, accuracy: 4)
            shot("event-detail-compact-\(theme)")
            app.terminate()
        }
    }
}

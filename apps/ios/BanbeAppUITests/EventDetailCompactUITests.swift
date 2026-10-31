import XCTest

/// Notes 68 + 70 — the compact, story-first Event Detail (web twin: tests/event-detail-compact.spec.js), against the DEBUG `shell.event`
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
            // Note 70: one-row bar (≤ 12% of the screen, no 1·2·3 presets), title on the photo above the sheet, the rules
            // (chips, who can reserve) before the host, one-line place, English date, "N of M left", stepper capped.
            let area = el(app, "event.trustLine").frame.maxY - min(el(app, "event.qty.minus").frame.minY, bar.minY)
            XCTAssertLessThanOrEqual(area, screen.height * 0.12, "booking bar height (\(theme))")
            XCTAssertFalse(el(app, "event.qty.1").exists)
            XCTAssertLessThanOrEqual(el(app, "event.heroTitle").frame.maxY, el(app, "event.fact.seats").frame.minY + 1)
            XCTAssertLessThan(el(app, "event.typeFacts").frame.minY, el(app, "event.organizer").frame.minY)
            XCTAssertTrue(el(app, "event.typeFact.dietary-2").exists, "two dietary choices are two chips")
            let whenText = el(app, "event.fact.when").label
            XCTAssertFalse(whenText.hasPrefix("Th ") || whenText.contains("Th 4"), "English date: \(whenText)")
            XCTAssertFalse(el(app, "event.fact.where").label.contains("km"), "no far-away distance")
            let seatText = el(app, "event.seatStatus").label
            XCTAssertTrue(seatText.contains("of 3 left"), seatText)
            let plus = el(app, "event.qty.plus")
            for _ in 0..<5 where plus.isEnabled { plus.tap() }
            XCTAssertEqual(el(app, "event.qty.value").label, "3", "stepper stops at the seats left")
            shot("event-detail-compact-\(theme)")
            app.terminate()
        }
    }
}

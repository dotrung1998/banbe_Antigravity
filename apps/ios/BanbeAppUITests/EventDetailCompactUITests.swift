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

    /// V8 (note 75): the whole ticket stub is on screen above the sticky bar; the bar is 1·2·3 presets over the stepper
    /// + CTA (≤ 21% of the screen; note 70's 12% one-row bar is superseded by owner decision), both driving one qty.
    func testStubAboveTheBarAndPresetsShareOneQty() {
        for theme in ["light", "dark"] {
            let app = launch(theme: theme)
            let when = el(app, "event.fact.when")
            XCTAssertTrue(when.waitForExistence(timeout: 10))
            sleep(1)
            let screen = app.windows.firstMatch.frame
            let bar = el(app, "event.actionBar").frame
            XCTAssertTrue(el(app, "event.actionBar").isHittable, "the CTA is on screen")
            let presetTop = el(app, "event.qty.1").frame.minY
            for id in ["event.fact.when", "event.fact.time", "event.fact.where", "event.price", "event.seatStatus"] {
                let f = el(app, id).frame
                XCTAssertGreaterThan(f.height, 0, id)
                XCTAssertLessThanOrEqual(f.maxY, presetTop + 1, "\(id) is above the sticky bar (\(theme))")
            }
            // Title on the photo, above the stub; minimum age a pill on the category's row.
            XCTAssertLessThanOrEqual(el(app, "event.heroTitle").frame.maxY, el(app, "event.ticketStub").frame.minY + 1)
            let age = el(app, "event.typeFact.min_age"), cat = el(app, "event.category")
            XCTAssertTrue(age.exists && cat.exists)
            XCTAssertEqual(age.frame.midY, cat.frame.midY, accuracy: 4)
            // The host appears once.
            XCTAssertFalse(el(app, "event.trackRecord").exists)
            XCTAssertEqual(app.buttons.matching(identifier: "event.organizer").count, 1)
            // English date block, no far-away distance, V8 seat chip.
            let whenText = when.label
            XCTAssertFalse(whenText.hasPrefix("Th ") || whenText.contains("Th 4"), "English date: \(whenText)")
            XCTAssertFalse(el(app, "event.fact.where").label.contains("km"), "no far-away distance")
            let seatText = el(app, "event.seatStatus").label
            XCTAssertTrue(seatText.contains("tickets left") || seatText.contains("ticket left"), seatText)
            XCTAssertFalse(seatText.contains(" of "), seatText)
            // Bar height: from the preset chips to the trust line.
            let area = el(app, "event.trustLine").frame.maxY - min(presetTop, bar.minY)
            XCTAssertLessThanOrEqual(area, screen.height * 0.21, "booking bar height (\(theme))")
            // One qty: a chip sets the stepper, the stepper lights the chip.
            XCTAssertTrue(el(app, "event.qty.1").isSelected)
            el(app, "event.qty.2").tap()
            XCTAssertEqual(el(app, "event.qty.value").label, "2")
            XCTAssertTrue(el(app, "event.qty.2").isSelected)
            XCTAssertFalse(el(app, "event.qty.1").isSelected)
            el(app, "event.qty.plus").tap()
            XCTAssertTrue(el(app, "event.qty.3").isSelected)
            // The stepper stops at the seats left (bepnho fixture: 3 of 3).
            let plus = el(app, "event.qty.plus")
            for _ in 0..<5 where plus.isEnabled { plus.tap() }
            XCTAssertEqual(el(app, "event.qty.value").label, "3", "stepper stops at the seats left")
            shot("event-detail-v8-\(theme)")
            app.terminate()
        }
    }

    /// V8 (note 75): the good-to-know rows keep one row per dietary choice; the protected-booking steps are on the page.
    func testGoodToKnowAndProtection() {
        let app = launch(theme: "light")
        XCTAssertTrue(el(app, "event.fact.when").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "event.typeFact.dietary-2").exists, "two dietary choices are two rows")
        let protection = el(app, "event.protection")
        for _ in 0..<8 where !protection.isHittable { app.swipeUp() }
        XCTAssertTrue(protection.exists)
        XCTAssertTrue(protection.label.contains("banbe reminds them") || app.staticTexts["The host has 1 hour to confirm; banbe reminds them"].exists)
        shot("event-detail-v8-bottom")
    }

    /// V8 tabs (note 75; web twin tests/event-detail-tabs.spec.js): they show with the solid nav bar, the bottom lights the
    /// last tab, a tapped tab lands its section under the tab row and stays lit, and the collapsed controls keep 44pt.
    func testTabsFollowTheScroll() {
        let app = launch(theme: "light")
        XCTAssertTrue(el(app, "event.fact.when").waitForExistence(timeout: 10))
        let protection = el(app, "event.protection")
        for _ in 0..<10 where !(protection.exists && protection.isHittable && protection.frame.maxY < app.windows.firstMatch.frame.maxY - 200) { app.swipeUp() }
        for _ in 0..<3 { app.swipeUp() }
        sleep(1)
        let safe = el(app, "event.tab.safe")
        XCTAssertTrue(safe.waitForExistence(timeout: 3))
        XCTAssertTrue(safe.isSelected, "the bottom of the page lights the last tab")
        for id in ["event.back", "event.more", "event.share", "event.save"] {
            let f = el(app, id).frame
            XCTAssertGreaterThanOrEqual(f.width, 44, id)
            XCTAssertGreaterThanOrEqual(f.height, 44, id)
        }
        shot("event-detail-v8-tabs-bottom")
        el(app, "event.tab.host").tap()
        sleep(2)
        XCTAssertTrue(el(app, "event.tab.host").isSelected, "a tapped tab stays lit")
        let row = el(app, "event.tabs").frame
        let host = el(app, "event.organizer").frame
        XCTAssertGreaterThanOrEqual(host.minY, row.maxY - 2)
        XCTAssertLessThan(host.minY, row.maxY + 140)
        shot("event-detail-v8-tabs-host")
    }
}

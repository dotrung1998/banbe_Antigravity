import XCTest

/// Event type profiles (note 65), against the DEBUG fixtures (no network), switch `event_type_profiles` on via
/// `-uiFixtureEventTypes YES`: a supper club's own fields in Basics, its facts in Review and in the real Event
/// Detail preview, and tappable "Still needed" chips.
final class EventTypesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", "en", "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES", "-uiFixtureEventTypes", "YES"] + extra
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

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, max: Int = 12) {
        var n = 0
        while !(element.exists && element.isHittable) && n < max { app.swipeUp(); n += 1 }
    }

    func testSupperClubBasicsShowsItsOwnFields() {
        let app = launch("shell.create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        let details = el(app, "create.typeDetails")
        scroll(app, to: details)
        XCTAssertTrue(details.exists, "the supper club's own fields in Basics")
        XCTAssertTrue(app.staticTexts["ON THE MENU"].exists || app.staticTexts["On the menu"].exists, "Included is called On the menu")
        XCTAssertTrue(el(app, "create.detail.dietary.vegetarian").isSelected, "the draft's answer shows as selected")
        sleep(1)
        shot("types-basics-fields")
        let vegan = el(app, "create.detail.dietary.vegan")
        vegan.tap()
        XCTAssertTrue(vegan.isSelected)
        app.swipeUp()
        sleep(1)
        shot("types-basics-fields-2")
    }

    func testStillNeededChipLandsOnTheField() {
        let app = launch("shell.create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        // The fixture draft has no address yet: Next to When & where, whose footer names it.
        let gaps = el(app, "create.step.gaps")
        scroll(app, to: el(app, "create.step.next"), max: 20)
        el(app, "create.step.next").tap()
        scroll(app, to: gaps, max: 20)
        let chip = el(app, "create.missing.location")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the address gap is a chip")
        shot("types-still-needed-chip")
        chip.tap()
        XCTAssertTrue(el(app, "create.coach").waitForExistence(timeout: 5), "tapping the chip lands on the field")
        shot("types-still-needed-landed")
    }

    func testReviewAndPreviewShowTheFacts() {
        let app = launch("shell.create", extra: ["-uiFixtureReview", "YES"])
        XCTAssertTrue(app.staticTexts["Review before submitting"].waitForExistence(timeout: 10))
        let details = el(app, "create.reviewDetails")
        scroll(app, to: details)
        XCTAssertTrue(app.staticTexts["Dietary"].exists, "the type facts are rows of Event details")
        XCTAssertTrue(app.staticTexts["BYO wine"].exists)
        shot("types-review-private")
        app.buttons["Public preview"].tap()
        XCTAssertTrue(el(app, "createEvent.preview.public").waitForExistence(timeout: 5))
        let facts = el(app, "event.typeFacts")
        scroll(app, to: facts)
        XCTAssertTrue(facts.exists, "guests see the facts on the real Event Detail")
        sleep(1)
        shot("types-review-public")
    }
}

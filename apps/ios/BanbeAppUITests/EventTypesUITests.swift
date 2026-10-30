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
        let details = el(app, "create.typeField.dietary")
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
        XCTAssertTrue(app.staticTexts["Bring your own"].exists)
        shot("types-review-private")
        app.buttons["Public preview"].tap()
        XCTAssertTrue(el(app, "createEvent.preview.public").waitForExistence(timeout: 5))
        let facts = el(app, "event.typeFacts")
        scroll(app, to: facts)
        XCTAssertTrue(facts.exists, "guests see the facts on the real Event Detail")
        sleep(1)
        shot("types-review-public")
    }

    // MARK: Phase 2 (note 66)

    func testHomeCategoryRowAndShowAllSheet() {
        let app = launch("shell.home")
        let row = el(app, "filter.all")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "home.categoryCount.all").exists, "every tile carries its live count")
        XCTAssertFalse(el(app, "filter.popup").exists, "a category with no events here is not in the row")
        sleep(1)
        shot("home-category-row")
        let showAll = el(app, "home.category.showAll")
        if !showAll.isHittable { el(app, "filter.all").swipeLeft() }
        showAll.tap()
        XCTAssertTrue(el(app, "home.categorySheet.popup").waitForExistence(timeout: 5), "Show all lists every category, zero ones too")
        sleep(1)
        shot("home-category-sheet")
        el(app, "home.categorySheet.music").tap()
        XCTAssertFalse(el(app, "home.categorySheet.popup").waitForExistence(timeout: 2), "picking closes the sheet")
        XCTAssertTrue(el(app, "filter.music").isSelected, "and applies it as the category filter")
        sleep(1)
        shot("home-category-picked")
    }

    func testEventDetailFactsPerType() {
        for key in ["bepnho", "jazzgac", "khongnguoi", "aeie"] {
            let app = launch("shell.event", extra: ["-uiFixtureEventKey", key])
            let facts = el(app, "event.typeFacts")
            XCTAssertTrue(el(app, "event.fact.seats").waitForExistence(timeout: 10), key)
            scroll(app, to: facts, max: 8)
            XCTAssertTrue(facts.exists, "\(key): the type's facts on Event Detail")
            XCTAssertTrue(el(app, "event.typeFact.alcohol").exists && el(app, "event.typeFact.min_age").exists, "\(key): alcohol and age")
            sleep(1)
            shot("event-facts-\(key)")
            app.terminate()
        }
    }

    func testPopupCreateFormAsksItsOwnFacts() {
        let app = launch("shell.create", extra: ["-uiFixtureCreateType", "popup"])
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        let brands = el(app, "create.typeField.brands")
        scroll(app, to: brands, max: 20)
        XCTAssertTrue(brands.exists, "a pop-up asks for its brands")
        XCTAssertTrue(el(app, "create.typeField.entry_mode").exists)
        sleep(1)
        shot("create-popup-fields")
        scroll(app, to: el(app, "create.typeField.min_age"), max: 6)
        sleep(1)
        shot("create-popup-alcohol-age")
    }
}

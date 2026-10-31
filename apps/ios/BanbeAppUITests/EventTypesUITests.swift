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

    /// Note 69: opens a part of the current step (Basics › Details is part 4).
    private func openPart(_ app: XCUIApplication, _ i: Int) {
        let dot = el(app, "create.substeps.\(i)")
        for _ in 0..<4 where !dot.isHittable { app.swipeDown() }
        if dot.waitForExistence(timeout: 5) { dot.tap() }
    }

    private func scroll(_ app: XCUIApplication, to element: XCUIElement, max: Int = 12) {
        var n = 0
        while !(element.exists && element.isHittable) && n < max { app.swipeUp(); n += 1 }
    }

    func testSupperClubBasicsShowsItsOwnFields() {
        let app = launch("shell.create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        openPart(app, 4)   // note 69: type facts are in Basics › Details
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
        let chip = el(app, "create.missing.location")
        // Note 69: Next walks Basics' parts first, then reaches When & where.
        for _ in 0..<8 where !chip.exists {
            scroll(app, to: el(app, "create.step.next"), max: 20)
            el(app, "create.step.next").tap()
        }
        scroll(app, to: gaps, max: 20)
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

    /// Note 69: Basics › Story has long fields (2x a one-line box) with Expand → full-screen editor → Clear all (confirmed),
    /// and the introduction's font / colour; two categories ask both types' facts in Basics › Details.
    func testLongFieldsExpandClearAndTwoCategories() {
        let app = launch("shell.create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        let story = el(app, "create.substeps.1")
        XCTAssertTrue(story.waitForExistence(timeout: 5), "Basics has its own part bar")
        let nameHeight = app.textFields["Your event name"].firstMatch.frame.height
        story.tap()
        let intro = el(app, "create.intro")
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        let name = app.textFields["Your event name"].firstMatch
        XCTAssertFalse(name.exists, "one part at a time: the name is in part 1")
        XCTAssertGreaterThanOrEqual(intro.frame.height, nameHeight * 2, "long field at least twice the Event name field")
        scroll(app, to: el(app, "create.introFont.serif"))
        el(app, "create.introFont.serif").tap()
        el(app, "create.introColor.clay").tap()
        XCTAssertTrue(el(app, "create.introFont.serif").isSelected && el(app, "create.introColor.clay").isSelected)
        for _ in 0..<4 where !el(app, "create.expand.intro").isHittable { app.swipeDown() }
        el(app, "create.expand.intro").tap()
        let editor = el(app, "longText.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Expand opens the whole text")
        editor.typeText("Hello there")
        el(app, "longText.clearAll").tap()
        // The system dialog drops custom identifiers: its own "Clear all" is the second button with that label.
        let clears = app.buttons.matching(NSPredicate(format: "label == 'Clear all'"))
        let deadline = Date().addingTimeInterval(3)
        while clears.count < 2 && Date() < deadline { usleep(200_000) }
        XCTAssertGreaterThanOrEqual(clears.count, 2, "Clear all asks first")
        XCTAssertEqual((editor.value as? String) ?? "", "Hello there", "nothing cleared before confirming")
        app.buttons.matching(NSPredicate(format: "label == 'Clear all' AND identifier != 'longText.clearAll'")).firstMatch.tap()
        XCTAssertEqual((editor.value as? String) ?? "", "", "cleared")
        el(app, "longText.done").tap()
        XCTAssertTrue(intro.waitForExistence(timeout: 5))
        // Two categories: Supper club (fixture) + Music → Details asks for dietary AND lineup.
        el(app, "create.substeps.3").tap()
        let music = app.buttons["Music"].firstMatch
        scroll(app, to: music)
        music.tap()
        el(app, "create.substeps.4").tap()
        let lineup = el(app, "create.typeField.lineup")
        scroll(app, to: lineup, max: 20)
        XCTAssertTrue(lineup.exists, "the second category's own field")
        for _ in 0..<20 where !el(app, "create.typeField.dietary").exists { app.swipeDown() }
        XCTAssertTrue(el(app, "create.typeField.dietary").exists, "the first category's field stays")
    }

    func testPopupCreateFormAsksItsOwnFacts() {
        let app = launch("shell.create", extra: ["-uiFixtureCreateType", "popup"])
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        openPart(app, 4)
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

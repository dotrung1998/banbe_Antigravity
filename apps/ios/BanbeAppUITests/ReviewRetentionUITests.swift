import XCTest

/// 2026-10-21 pass, against the DEBUG fixtures (no network): the create-event Public preview is the real Event
/// Detail (inert guest controls, Confirm & submit under it), the progress header is a ring, the For You intro tiles
/// are one size, and Delete account opens the "Before you go" pop-up first.
final class ReviewRetentionUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", "en", "-banbe.theme", "light",
                                "-uiTesting", "1", "-banbe.onboarded", "YES"] + extra
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

    func testPublicPreviewIsTheRealEventDetail() {
        let app = launch("shell.create", extra: ["-uiFixtureReview", "YES"])
        XCTAssertTrue(app.staticTexts["Review before submitting"].waitForExistence(timeout: 10))
        shot("review-private")
        app.buttons["Public preview"].tap()
        XCTAssertTrue(el(app, "createEvent.preview.public").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "event.fact.when").exists, "the Date / Time / Place tiles of the new Event Detail")
        XCTAssertTrue(el(app, "event.fact.seats").exists)
        XCTAssertTrue(el(app, "event.price").exists)
        XCTAssertTrue(app.buttons["Confirm & submit"].exists, "submit stays one tap away on the preview")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS ' km'")).firstMatch.exists, "no distance on a draft")
        sleep(1)
        shot("review-public-top")
        app.swipeUp()
        sleep(1)
        shot("review-public-scrolled")
        el(app, "event.back").tap()
        XCTAssertTrue(app.staticTexts["Review before submitting"].waitForExistence(timeout: 5), "back pill returns to the Private tab")
    }

    func testProgressRing() {
        let app = launch("shell.create")
        XCTAssertTrue(el(app, "create.recipeMeter").waitForExistence(timeout: 10))
        shot("create-progress-ring")
    }

    func testOnboardingWelcomeTilesShareOneHeight() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "onboarding", "-banbe.lang", "vi", "-uiTesting", "1", "-uiFixtureReset", "YES"]
        app.launch()
        XCTAssertTrue(el(app, "onboarding.start").waitForExistence(timeout: 10))
        sleep(1)
        let tiles = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'phút' OR label CONTAINS 'Chỉ bạn thấy' OR label CONTAINS 'Đổi lúc nào'"))
        let heights = (0..<tiles.count).map { tiles.element(boundBy: $0).frame.height }
        if heights.count == 3 { XCTAssertEqual(heights.max()! - heights.min()!, 0, accuracy: 1, "tiles share one height: \(heights)") }
        shot("onboarding-welcome-vi")
    }

    func testDeleteAccountAsksBeforeYouGo() {
        let app = launch("shell.account")
        // note 66: Settings is a row in Account's More card, below the tiles.
        XCTAssertTrue(el(app, "account.tile.events").waitForExistence(timeout: 10))
        // Note 69: Settings is in the Personal tab's App group (the fixture opens on Host).
        el(app, "account.tab.personal").tap()
        let group = el(app, "account.group.preferences")
        for _ in 0..<6 where !group.exists || !group.isHittable { app.swipeUp() }
        group.tap()
        let row = el(app, "account.deleteRow")
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(el(app, "deleteStay.title").waitForExistence(timeout: 5))
        shot("delete-stay")
        el(app, "deleteStay.reason.too_many_notifications").tap()
        XCTAssertTrue(el(app, "deleteStay.offer.quieterNotifications").waitForExistence(timeout: 3))
        shot("delete-stay-offer")
        el(app, "deleteStay.continue").tap()
        XCTAssertTrue(app.staticTexts["Confirm deletion"].waitForExistence(timeout: 5), "Continue lands on the confirm step")
        XCTAssertTrue(el(app, "deleteAccount.identity").exists, "with the identity card carried up")
        shot("delete-confirm")
    }

    // MARK: 2026-10-21 second pass

    func testPriceSliderDrags() {
        let app = launch("shell.create", extra: ["-uiFixtureBench", "YES"])
        XCTAssertTrue(el(app, "create.step.next").waitForExistence(timeout: 10))
        let slider = el(app, "create.priceSlider")
        // Note 69: Next walks Basics' parts before reaching Tickets › Price.
        for _ in 0..<10 where !slider.exists {
            let next = el(app, "create.step.next")
            for _ in 0..<6 where !next.isHittable { app.swipeUp() }
            next.tap(); sleep(1)
        }
        for _ in 0..<6 where !slider.isHittable { app.swipeUp() }
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let field = app.textFields.matching(NSPredicate(format: "value CONTAINS '000'")).firstMatch
        let before = field.value as? String
        // Drag along the knob's row (the bottom of the slider) from left to near the right edge.
        let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.85))
        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(1)
        shot("create-price-slider")
        XCTAssertNotEqual(field.value as? String, before, "dragging the knob changes the price field")
    }

    func testManageEventsOrphansAndExpand() {
        let app = launch("shell.adminManageEvents")
        XCTAssertTrue(el(app, "adminManage.row.fx-ev-live").waitForExistence(timeout: 15))
        el(app, "adminManage.filter.orphan").tap()
        XCTAssertTrue(el(app, "adminManage.orphan.fx-ev-orphan-refund").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "adminManage.row.fx-ev-live").exists, "only orphans under Host deleted")
        XCTAssertTrue(el(app, "adminManage.blocked.fx-ev-orphan-refund").label.contains("banbe must contact the guests"))
        el(app, "adminManage.expand.fx-ev-orphan-refund").tap()
        XCTAssertTrue(el(app, "adminManage.detail.copy.fx-ev-orphan-refund").waitForExistence(timeout: 3), "details open")
        el(app, "adminManage.row.fx-ev-orphan-draft").tap()
        XCTAssertTrue(el(app, "adminManage.action.remove").waitForExistence(timeout: 3), "an orphan is selectable and removable")
        shot("manage-orphans")
        el(app, "adminManage.filter.review").tap()
        el(app, "adminManage.expand.fx-ev-review").tap()
        XCTAssertTrue(el(app, "adminManage.detail.review.fx-ev-review").waitForExistence(timeout: 3))
        shot("manage-review-expanded")
    }

    func testReviewPrivateTabHasSections() {
        let app = launch("shell.create", extra: ["-uiFixtureReview", "YES"])
        XCTAssertTrue(app.staticTexts["Review before submitting"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["EVENT NAME"].exists)
        XCTAssertTrue(app.staticTexts["EVENT DETAILS"].exists)
        let tabs = app.buttons["Public preview"].frame
        XCTAssertGreaterThan(el(app, "create.reviewName").frame.minY, tabs.maxY + 20, "a clear gap under the tabs")
        app.swipeUp()
        sleep(1)
        shot("review-private-scrolled")
    }

    func testHowBanbeWorksHasHostPages() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "auth", "-banbe.lang", "en", "-uiTesting", "1", "-banbe.publicStory.seen.v1", "NO"]
        app.launch()
        XCTAssertTrue(el(app, "welcome.story.open").waitForExistence(timeout: 10))
        el(app, "welcome.story.open").tap()
        XCTAssertEqual(el(app, "welcome.story.progress").label, "1 of 4")
        for _ in 0..<2 { el(app, "welcome.story.next").tap(); sleep(1) }
        XCTAssertTrue(el(app, "welcome.story.heading.2").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Host your own events"].exists)
        shot("welcome-host-page")
        el(app, "welcome.story.next").tap()
        XCTAssertTrue(app.staticTexts["Create an event in 5 steps"].waitForExistence(timeout: 5))
        shot("welcome-create-page")
    }
}

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
        let group = el(app, "account.group.preferences")
        XCTAssertTrue(group.waitForExistence(timeout: 10))
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
}

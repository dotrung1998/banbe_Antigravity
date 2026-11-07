import XCTest

/// Note 68 — the personal profile identity card (web twin: tests/public-profile-card.spec.js), against the DEBUG
/// `shell.publicProfile` fixture (own profile, a host): left-aligned compact card with the stats inside, one chip per
/// interest (regression: "Admin", "Admin"), owner actions as 44pt pills outside the card.
final class PublicProfileCardUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testIdentityCardIsCompactLeftAlignedAndDeduplicated() {
        for theme in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments += ["-uiFixture", "shell.publicProfile", "-banbe.lang", "en", "-banbe.theme", theme,
                                    "-uiTesting", "1", "-banbe.onboarded", "YES"]
            app.launch()
            let card = el(app, "publicProfile.card")
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            sleep(1)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "public-profile-\(theme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let screen = app.windows.firstMatch.frame
            XCTAssertLessThanOrEqual(card.frame.height, 220, "card + stats stay compact at the default text size")
            XCTAssertGreaterThanOrEqual(card.frame.width, screen.width - 2 * 16 - 1, "full width, 16pt gutter")
            let name = el(app, "publicProfile.displayName").frame
            XCTAssertLessThanOrEqual(name.minX - card.frame.minX, 20 + 80 + 16 + 2, "left-aligned beside the avatar")
            XCTAssertTrue(el(app, "publicProfile.stats").exists, "stats inside the card")
            XCTAssertTrue(card.frame.contains(el(app, "publicProfile.stats").frame), "the stats strip sits inside the card")
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Admin'")).count, 1, "one chip per interest")
            for id in ["publicProfile.qrCta", "publicProfile.editPersonal", "publicProfile.editCharm"] {
                let f = el(app, id).frame
                XCTAssertGreaterThanOrEqual(f.height, 44, id)
                XCTAssertGreaterThan(f.minY, card.frame.maxY, "\(id) sits outside the card")
                XCTAssertLessThanOrEqual(f.minY - card.frame.maxY, 24, "\(id): no gap above 24")
            }
            app.terminate()
        }
    }
}

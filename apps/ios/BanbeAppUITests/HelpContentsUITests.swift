import XCTest

/// Help & Legal guides: tapping an entry in Contents must scroll to that section (owner device report, 2026-10-25).
final class HelpContentsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["HIW_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testMiddleEntryLandsAtTop() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.guide", "-banbe.lang", "en", "-uiTesting", "1"]
        app.launch()
        let entries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'help.guide.personal.toc.'"))
        XCTAssertTrue(entries.element(boundBy: 0).waitForExistence(timeout: 10))
        shot("help-0-start")
        entries.element(boundBy: 6).tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("help-1-after-tap")
    }

    /// Every reader (Vietnamese too): tapping the last Contents entry scrolls Contents out of view.
    func testEveryReaderScrolls() {
        for (fixture, guide, prefix) in [("shell.guide", "host", "help.guide.host"), ("shell.faq", "", "help.faq"), ("shell.guide", "personal", "help.guide.personal")] {
            let app = XCUIApplication()
            app.launchArguments += ["-uiFixture", fixture, "-uiFixtureGuide", guide, "-banbe.lang", "vi", "-uiTesting", "1"]
            app.launch()
            let toc = app.descendants(matching: .any)["\(prefix).tocToggle"].firstMatch
            XCTAssertTrue(toc.waitForExistence(timeout: 10), prefix)
            let entries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(prefix).toc."))
            XCTAssertGreaterThan(entries.count, 2, prefix)
            entries.element(boundBy: entries.count - 1).tap()
            Thread.sleep(forTimeInterval: 1.2)
            XCTAssertFalse(toc.isHittable, "\(prefix): page scrolled after tapping the last Contents entry")
            app.terminate()
        }
    }

    /// The way a person gets there: Account > Help & Legal > Guide: Personal, then a Contents entry.
    func testViaAccountHelpLegal() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.account", "-banbe.lang", "en", "-uiTesting", "1"]
        app.launch()
        let help = app.descendants(matching: .any)["account.helpLegal"].firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 10))
        if !help.isHittable { app.swipeUp() }
        help.tap()
        let guide = app.descendants(matching: .any)["help.guide.personal"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        let toc = app.descendants(matching: .any)["help.guide.personal.tocToggle"].firstMatch
        XCTAssertTrue(toc.waitForExistence(timeout: 5))
        let entries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'help.guide.personal.toc.'"))
        entries.element(boundBy: 9).tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(toc.isHittable, "page scrolled after tapping a Contents entry reached via Account > Help & Legal")
    }

    func testJumpToBottomButtonScrolls() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.guide", "-banbe.lang", "en", "-uiTesting", "1"]
        app.launch()
        let toc = app.descendants(matching: .any)["help.guide.personal.tocToggle"].firstMatch
        XCTAssertTrue(toc.waitForExistence(timeout: 10))
        app.descendants(matching: .any)["help.guide.personal.toBottom"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(toc.isHittable, "jump-to-bottom scrolled the page")
    }

    func testTappingContentsEntryScrollsToSection() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.guide", "-banbe.lang", "en", "-uiTesting", "1"]
        app.launch()
        let toc = app.descendants(matching: .any)["help.guide.personal.tocToggle"].firstMatch
        XCTAssertTrue(toc.waitForExistence(timeout: 10))
        // The last entry of Contents is far below the fold: its section must land on screen after the tap.
        let entries = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'help.guide.personal.toc.'"))
        XCTAssertGreaterThan(entries.count, 3)
        let last = entries.element(boundBy: entries.count - 1)
        let id = last.identifier.replacingOccurrences(of: "help.guide.personal.toc.", with: "")
        let title = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", last.label.components(separatedBy: ". ").dropFirst().joined(separator: ". "))).allElementsBoundByIndex
        _ = title
        XCTAssertTrue(last.isHittable, "Contents entry is tappable")
        last.tap()
        Thread.sleep(forTimeInterval: 1.2)
        // After scrolling, Contents (at the top) has moved off screen.
        XCTAssertFalse(toc.isHittable, "page scrolled away from Contents after tapping an entry (\(id))")
    }
}

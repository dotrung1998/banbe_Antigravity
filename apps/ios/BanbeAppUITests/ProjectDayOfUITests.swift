import XCTest

/// Event Project Hub phase 5 (note 76): Day-of on the real RootView with the demo snapshot. "Now" is pinned: 3 Nov by
/// default, or `-uiFixtureProjectNow 2026-11-14T18:10:00+07:00` for the event day (the first item 40 minutes over).
final class ProjectDayOfUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let setup = "00000000-0000-4000-8000-000000000501"   // "Dựng bếp và bàn", 16:00–17:30, not ticked
    private let eventDayNow = ["-uiFixtureProjectNow", "2026-11-14T18:10:00+07:00"]

    private func launch(as role: String? = nil, lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.project", "-banbe.lang", lang, "-uiTesting", "1", "-banbe.onboarded", "YES",
                                "-uiFixtureProjectTab", "dayof"] + (role.map { ["-uiFixtureProjectAs", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(el(app, "project.dayofTab").waitForExistence(timeout: 20))
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func scrollTo(_ e: XCUIElement, in app: XCUIApplication, max: Int = 8) {
        var n = 0
        while !e.isHittable && n < max { app.swipeUp(); n += 1 }
    }

    func testBeforeTheEventDayItIsNotLiveAndTheWeekShowsWhatIsDue() {
        let app = launch()
        XCTAssertTrue(el(app, "project.dayof.info").exists, "not live on 3 Nov")
        XCTAssertFalse(el(app, "project.dayof.live").exists)
        XCTAssertTrue(el(app, "project.dayof.call").exists, "the team's call is one tap away")
        el(app, "project.dayof.day.2026-11-13").tap()
        XCTAssertTrue(el(app, "project.dayof.due").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["In thứ tự chương trình"].exists)
        el(app, "project.dayof.clearDay").tap()
        XCTAssertFalse(el(app, "project.dayof.due").waitForExistence(timeout: 1))
        attach(app, "project-dayof-list")
    }

    func testOnTheEventDayTheGridShowsTheOverrunAndTickingFreezesIt() {
        let app = launch(extra: eventDayNow)
        XCTAssertTrue(el(app, "project.dayof.live").exists, "live on the event day")
        el(app, "project.dayof.view.cal").tap()
        let block = el(app, "project.ros.block.\(setup)")
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        XCTAssertTrue(block.label.contains("40 minutes over"), block.label)
        XCTAssertTrue(el(app, "project.ros.chips").exists, "versus the plan")
        XCTAssertTrue(el(app, "project.ros.nowLine").exists)
        attach(app, "project-dayof-grid-live")
        let tick = el(app, "project.ros.tick.\(setup)")
        scrollTo(tick, in: app)
        tick.tap()
        XCTAssertEqual(el(app, "project.ros.tick.\(setup)").value as? String, "Done")
        XCTAssertTrue(el(app, "project.ros.block.\(setup)").label.contains("done"))
        XCTAssertFalse(el(app, "project.ros.block.\(setup)").label.contains("over"), "a tick freezes the end at the tick time; it is no longer running over")
    }

    func testJumpToNowBringsTheNowLineIntoView() {
        let app = launch(extra: eventDayNow)
        el(app, "project.dayof.view.cal").tap()
        let jump = el(app, "project.ros.jumpNow")
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
        jump.tap()
        XCTAssertTrue(el(app, "project.ros.nowLine").isHittable || el(app, "project.ros.nowLine").frame.minY < app.windows.firstMatch.frame.maxY)
    }

    func testTheHostAddsAnItem() {
        let app = launch()
        el(app, "project.dayof.add").tap()
        let title = el(app, "project.ros.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Thank-you speech")
        el(app, "project.ros.save").tap()
        XCTAssertTrue(app.staticTexts["Thank-you speech"].waitForExistence(timeout: 5))
    }

    func testDeletingAnItemPutsItInTheTrashAndItCanComeBack() {
        let app = launch()
        el(app, "project.ros.edit.\(setup)").tap()
        el(app, "project.ros.delete").tap()
        el(app, "project.reason.pick").tap()
        el(app, "project.ros.confirmDelete").tap()
        XCTAssertFalse(el(app, "project.ros.row.\(setup)").waitForExistence(timeout: 2))
        el(app, "project.more").tap()
        app.buttons["Trash"].tap()
        let restore = el(app, "project.trash.restore.\(setup)")
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        attach(app, "project-trash")
        restore.tap()
        el(app, "project.sheet.close").tap()
        XCTAssertTrue(el(app, "project.ros.row.\(setup)").waitForExistence(timeout: 5))
    }

    func testAHelperTicksButCannotEdit() {
        let app = launch(as: "helper", extra: eventDayNow)
        XCTAssertFalse(el(app, "project.dayof.add").exists)
        XCTAssertFalse(el(app, "project.ros.edit.\(setup)").exists)
        let tick = el(app, "project.ros.tick.\(setup)")
        scrollTo(tick, in: app)
        tick.tap()
        XCTAssertEqual(el(app, "project.ros.tick.\(setup)").value as? String, "Done")
        el(app, "project.more").tap()
        XCTAssertFalse(app.buttons["Trash"].exists, "the trash is the Host's and Managers'")
    }

    func testGridAtTheLargestTextSizeAndInVietnameseDark() {
        let big = launch(extra: eventDayNow + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        el(big, "project.dayof.view.cal").tap()
        XCTAssertTrue(el(big, "project.ros.grid").waitForExistence(timeout: 5))
        scrollTo(el(big, "project.ros.block.\(setup)"), in: big, max: 12)
        attach(big, "project-dayof-grid-axxxl")
        big.terminate()
        let vi = launch(lang: "vi", extra: eventDayNow + ["-banbe.theme", "dark"])
        el(vi, "project.dayof.view.cal").tap()
        XCTAssertTrue(el(vi, "project.ros.grid").waitForExistence(timeout: 5))
        attach(vi, "project-dayof-grid-vi-dark")
    }
}

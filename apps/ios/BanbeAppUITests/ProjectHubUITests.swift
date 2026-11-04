import XCTest

/// Event Project Hub phase 3 (note 76) on the REAL RootView with the shared demo snapshot (`-uiFixture shell.project`,
/// tests/fixtures/project-snapshot.json, "now" pinned to 3 Nov in the event's zone). No network.
final class ProjectHubUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let task02 = "00000000-0000-4000-8000-000000000302"   // "Check power", Trang's, to do
    private let task05 = "00000000-0000-4000-8000-000000000305"   // "Test the veg dish", Minh's, blocked
    private let proposal = "00000000-0000-4000-8000-000000000701"

    private func launch(as role: String? = nil, tab: String = "overview", lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.project", "-banbe.lang", lang, "-uiTesting", "1", "-banbe.onboarded", "YES",
                                "-uiFixtureProjectTab", tab] + (role.map { ["-uiFixtureProjectAs", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(el(app, "project.hub").waitForExistence(timeout: 20), "the hub opens")
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func fullyVisible(_ e: XCUIElement, in app: XCUIApplication) -> Bool {
        let w = app.windows.firstMatch.frame
        return e.exists && e.frame.minX >= w.minX - 0.5 && e.frame.maxX <= w.maxX + 0.5
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    // MARK: tab row

    func testExactlyFiveTabsVisibleAtRestAndTheSixthBySwipe() {
        let app = launch()
        let ids = ["overview", "tasks", "topics", "team", "money", "dayof"].map { "project.tab.\($0)" }
        for id in ids.prefix(5) { XCTAssertTrue(fullyVisible(el(app, id), in: app), "\(id) visible at rest") }
        XCTAssertFalse(fullyVisible(el(app, ids[5]), in: app), "the sixth tab starts off screen")
        XCTAssertTrue(el(app, "project.tabs.more").exists, "the edge hint shows while a tab is off screen")
        attach(app, "project-overview-host")
        el(app, "project.tab.money").swipeLeft()
        XCTAssertTrue(fullyVisible(el(app, ids[5]), in: app), "a swipe brings the sixth tab in")
        XCTAssertTrue(el(app, "project.tabs.atEnd").waitForExistence(timeout: 3), "the edge hint goes away at the end")
        attach(app, "project-tabs-at-end")
        el(app, ids[5]).tap()
        XCTAssertTrue(el(app, "project.dayofTab").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, ids[5]).isSelected)
    }

    func testFiveTabsStayAtTheLargestTextSize() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        for id in ["overview", "tasks", "topics", "team", "money"] {
            let e = el(app, "project.tab.\(id)")
            XCTAssertTrue(fullyVisible(e, in: app), "\(id) visible at AX XXXL")
            XCTAssertGreaterThanOrEqual(e.frame.height, 44, "\(id) keeps a 44pt target")
        }
        attach(app, "project-overview-axxxxl")
    }

    func testOpeningOnTheSixthTabScrollsItIntoView() {
        let app = launch(tab: "dayof")
        XCTAssertTrue(el(app, "project.tab.dayof").waitForExistence(timeout: 5))
        XCTAssertTrue(fullyVisible(el(app, "project.tab.dayof"), in: app), "the selected tab is scrolled into view")
        XCTAssertTrue(el(app, "project.tab.dayof").isSelected)
    }

    func testTabsReadTheirPositionToVoiceOver() {
        let app = launch()
        XCTAssertEqual(el(app, "project.tab.tasks").label, "Tasks, tab 2 of 6, needs attention")
        XCTAssertEqual(el(app, "project.tab.team").label, "Team, tab 4 of 6")
    }

    // MARK: overview

    func testHostOverviewShowsProposalsChannelsReadinessAndAttention() {
        let app = launch()
        XCTAssertTrue(el(app, "project.overview.proposals").exists, "one lane proposal waits on the Host")
        XCTAssertTrue(el(app, "project.channels").exists)
        XCTAssertTrue(el(app, "project.channels.edit").exists, "the Host edits channels")
        XCTAssertTrue(el(app, "project.overview.readiness").exists)
        XCTAssertTrue(el(app, "project.overview.attention").exists, "a blocked and a late task")
        el(app, "project.overview.review").tap()
        XCTAssertTrue(el(app, "project.tasksTab").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.proposal.approve.\(proposal)").exists)
    }

    func testOnlyTheHostEditsChannelsAndAManagerSuggests() {
        let helper = launch(as: "helper")
        XCTAssertTrue(helper.descendants(matching: .any)["project.channels"].waitForExistence(timeout: 5))
        XCTAssertFalse(el(helper, "project.channels.edit").exists, "a helper only opens channels")
        XCTAssertFalse(el(helper, "project.overview.proposals").exists, "proposals are the Host's")
        helper.terminate()
        let manager = launch(as: "manager")
        XCTAssertEqual(el(manager, "project.channels.edit").label, "Suggest a channel")
    }

    // MARK: tasks

    func testTheHostTicksATaskDone() {
        let app = launch(tab: "tasks")
        let tick = el(app, "project.task.tick.\(task02)")
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        XCTAssertEqual(tick.value as? String, "To do")
        tick.tap()
        XCTAssertEqual(el(app, "project.task.tick.\(task02)").value as? String, "Done")
    }

    func testAHelperCannotTickSomeoneElsesTask() {
        let app = launch(as: "helper", tab: "tasks")
        let tick = el(app, "project.task.tick.\(task05)")
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        tick.tap()
        XCTAssertTrue(el(app, "project.notice").waitForExistence(timeout: 3), "a plain-words refusal")
        XCTAssertEqual(el(app, "project.task.tick.\(task05)").value as? String, "Blocked", "unchanged")
        XCTAssertFalse(el(app, "project.addTask").exists, "helpers do not add tasks")
        XCTAssertFalse(el(app, "project.lane.add").exists)
    }

    func testTheHostAddsATask() {
        let app = launch(tab: "tasks")
        el(app, "project.addTask").tap()
        let title = el(app, "project.task.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Buy ice")
        el(app, "project.task.save").tap()
        XCTAssertTrue(app.staticTexts["Buy ice"].waitForExistence(timeout: 5), "the new task shows in its lane")
        attach(app, "project-tasks-host")
    }

    func testApprovingAProposalAddsTheLane() {
        let app = launch(tab: "tasks")
        el(app, "project.proposal.approve.\(proposal)").tap()
        XCTAssertFalse(el(app, "project.proposal.approve.\(proposal)").waitForExistence(timeout: 2))
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.staticTexts["TRUYỀN THÔNG"].waitForExistence(timeout: 5), "the approved lane is in the list")
    }

    func testVietnameseAndDarkStillRender() {
        let app = launch(lang: "vi", extra: ["-banbe.theme", "dark"])
        XCTAssertEqual(el(app, "project.tab.overview").label, "Tổng quan, thẻ 1 trên 6")
        attach(app, "project-overview-vi-dark")
    }
}

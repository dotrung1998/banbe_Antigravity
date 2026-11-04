import XCTest

/// Event Project Hub phase 4 (note 76): Topics, Team, invites and "Join a team", on the REAL RootView with the shared
/// demo snapshot (`-uiFixture shell.project` / `shell.projectJoin`). No network: writes change the snapshot in memory.
final class ProjectTeamTopicsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private let proposal = "00000000-0000-4000-8000-000000000404"   // Minh's, options Cá kho / Nấm kho, 2–2, I haven't voted
    private let question = "00000000-0000-4000-8000-000000000403"   // Trang asks Linh (the Manager)
    private let update = "00000000-0000-4000-8000-000000000402"     // Linh's update, I haven't seen it
    private let an = "00000000-0000-4000-8000-000000000604"         // An, Helper

    private func launch(_ fixture: String = "shell.project", as role: String? = nil, tab: String = "topics", lang: String = "en",
                        extra: [String] = [], waitFor: String = "project.hub") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", lang, "-uiTesting", "1", "-banbe.onboarded", "YES",
                                "-uiFixtureProjectTab", tab] + (role.map { ["-uiFixtureProjectAs", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(el(app, waitFor).waitForExistence(timeout: 20), "\(waitFor) opens")
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func scrollTo(_ e: XCUIElement, in app: XCUIApplication, max: Int = 6) {
        var n = 0
        while !e.isHittable && n < max { app.swipeUp(); n += 1 }
    }

    // MARK: topics

    func testWaitingOnYouHoldsTheVoteAndTheUnseenUpdate() {
        let app = launch()
        let waiting = el(app, "project.topics.waiting")
        XCTAssertTrue(waiting.waitForExistence(timeout: 5))
        XCTAssertTrue(waiting.descendants(matching: .any)["project.post.\(proposal)"].exists, "a proposal I haven't voted on")
        XCTAssertTrue(waiting.descendants(matching: .any)["project.post.\(update)"].exists, "an update I haven't seen")
        XCTAssertFalse(waiting.descendants(matching: .any)["project.post.\(question)"].exists, "a question to someone else")
        attach(app, "project-topics-host")
    }

    func testRulesCardOpensAndCloses() {
        let app = launch()
        XCTAssertFalse(el(app, "project.topics.rulesBody").exists)
        el(app, "project.topics.rules").tap()
        XCTAssertTrue(el(app, "project.topics.rulesBody").waitForExistence(timeout: 3))
        el(app, "project.topics.rules").tap()
        XCTAssertFalse(el(app, "project.topics.rulesBody").waitForExistence(timeout: 1))
    }

    func testVotingCountsAndTappingAgainTakesItBack() {
        let app = launch()
        el(app, "project.post.\(proposal)").tap()
        let option = el(app, "project.post.option.1")
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertEqual(el(app, "project.post.option.1").value as? String, "3 votes, your vote")
        el(app, "project.post.option.1").tap()
        XCTAssertEqual(el(app, "project.post.option.1").value as? String, "2 votes")
    }

    func testHostDecidesAProposalAndTheDecisionIsLogged() {
        let app = launch()
        el(app, "project.post.\(proposal)").tap()
        let decide = el(app, "project.post.decide")
        XCTAssertTrue(decide.waitForExistence(timeout: 5))
        decide.tap()
        XCTAssertTrue(app.staticTexts["Cá kho"].waitForExistence(timeout: 5), "a tie settles on the first option")
    }

    func testMarkingAnUpdateSeen() {
        let app = launch()
        el(app, "project.post.\(update)").tap()
        let seen = el(app, "project.post.seen")
        XCTAssertTrue(seen.waitForExistence(timeout: 5))
        seen.tap()
        XCTAssertTrue(el(app, "project.post.seenDone").waitForExistence(timeout: 3))
    }

    func testTheManagerRepliesToTheirQuestionAndResolvesIt() {
        let app = launch(as: "manager")
        el(app, "project.post.\(question)").tap()
        let reply = el(app, "project.post.reply")
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        reply.typeText("Yes, by the back door")
        el(app, "project.post.send").tap()
        XCTAssertTrue(app.staticTexts["Yes, by the back door"].waitForExistence(timeout: 5))
        let resolve = el(app, "project.post.resolve")
        scrollTo(resolve, in: app)
        resolve.tap()
        XCTAssertFalse(el(app, "project.post.reply").waitForExistence(timeout: 2), "a resolved question takes no more replies")
        attach(app, "project-thread-resolved")
    }

    func testComposingAQuestionAddsItToTheList() {
        let app = launch()
        el(app, "project.newPost").tap()
        el(app, "project.compose.type.question").tap()
        let title = el(app, "project.compose.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.compose.post").isEnabled, "no addressee yet")
        title.tap()
        title.typeText("Who brings the ice?")
        el(app, "project.compose.to.00000000-0000-4000-8000-000000000104").tap()
        el(app, "project.compose.post").tap()
        XCTAssertTrue(app.staticTexts["Who brings the ice?"].waitForExistence(timeout: 5))
    }

    func testAHelperCannotPostAProposalOrADecision() {
        let app = launch(as: "helper")
        el(app, "project.newPost").tap()
        XCTAssertTrue(el(app, "project.compose.type.question").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.compose.type.proposal").isEnabled)
        XCTAssertFalse(el(app, "project.compose.type.decision").isEnabled)
        XCTAssertTrue(el(app, "project.compose.type.update").isEnabled)
        attach(app, "project-compose-helper")
    }

    // MARK: team

    func testHostInvitesAHelperAndCanCancelTheInvite() {
        let app = launch(tab: "team")
        el(app, "project.team.invite").tap()
        XCTAssertTrue(el(app, "project.invite.role.manager").waitForExistence(timeout: 5), "the Host presets any role")
        el(app, "project.invite.create").tap()
        XCTAssertTrue(el(app, "project.invite.code").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.invite.copy").exists)
        attach(app, "project-invite-code")
        el(app, "project.sheet.close").tap()
        XCTAssertTrue(el(app, "project.team.invites").waitForExistence(timeout: 5), "the live invite is listed")
        let revoke = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'project.invite.revoke.'")).firstMatch
        revoke.tap()
        XCTAssertFalse(el(app, "project.team.invites").waitForExistence(timeout: 2))
    }

    func testAManagerInvitesOnlyLaneLeadsAndHelpers() {
        let app = launch(as: "manager", tab: "team")
        el(app, "project.team.invite").tap()
        XCTAssertTrue(el(app, "project.invite.role.helper").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.invite.role.lane_lead").exists)
        XCTAssertFalse(el(app, "project.invite.role.manager").exists)
        XCTAssertFalse(el(app, "project.invite.role.finance").exists)
        XCTAssertTrue(el(app, "project.invite.managerNote").exists)
    }

    func testTheHostMakesAHelperALaneLead() {
        let app = launch(tab: "team")
        el(app, "project.member.\(an)").tap()
        XCTAssertTrue(el(app, "project.member.role.lane_lead").waitForExistence(timeout: 5))
        el(app, "project.member.role.lane_lead").tap()
        el(app, "project.member.save").tap()
        XCTAssertTrue(el(app, "project.member.\(an)").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.member.\(an)").label.contains("Lane lead"), el(app, "project.member.\(an)").label)
    }

    func testAHelperSeesTheTeamReadOnly() {
        let app = launch(as: "helper", tab: "team")
        XCTAssertFalse(el(app, "project.team.invite").exists)
        XCTAssertTrue(el(app, "project.team.matrix").exists)
        el(app, "project.member.00000000-0000-4000-8000-000000000602").tap()
        XCTAssertTrue(el(app, "project.memberSheet").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.member.save").exists)
        XCTAssertFalse(el(app, "project.member.remove").exists)
    }

    func testTeamTabAtTheLargestTextSize() {
        let app = launch(tab: "team", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(app, "project.team").exists)
        attach(app, "project-team-axxxl")
        scrollTo(el(app, "project.team.privacy"), in: app, max: 30)
        XCTAssertTrue(el(app, "project.team.privacy").isHittable)
        attach(app, "project-team-axxxl-matrix")
    }

    func testVietnameseDarkTeamAndTopics() {
        let app = launch(tab: "team", lang: "vi", extra: ["-banbe.theme", "dark"])
        attach(app, "project-team-vi-dark")
        el(app, "project.tab.topics").tap()
        XCTAssertTrue(el(app, "project.topicsTab").waitForExistence(timeout: 5))
        attach(app, "project-topics-vi-dark")
    }

    // MARK: join

    func testJoiningFromALinkOpensTheProject() {
        let app = launch("shell.projectJoin", extra: ["-uiFixtureProjectJoin", "banbe://join/BB-7K2Q"], waitFor: "project.join")
        XCTAssertTrue(el(app, "project.join.card").waitForExistence(timeout: 5))
        attach(app, "project-join")
        el(app, "project.join.confirm").tap()
        XCTAssertTrue(el(app, "project.hub").waitForExistence(timeout: 5))
    }

    func testAnExpiredCodeSaysSoAndOffersNoJoin() {
        let app = launch("shell.projectJoin", extra: ["-uiFixtureProjectJoin", "BB-XPRD"], waitFor: "project.join")
        XCTAssertTrue(el(app, "project.join.state").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.join.confirm").exists)
    }

    func testAWrongCodeShowsAPlainError() {
        let app = launch("shell.projectJoin", waitFor: "project.join")
        let field = el(app, "project.join.code")
        field.tap()
        field.typeText("BB-ZZZZ")
        el(app, "project.join.check").tap()
        XCTAssertTrue(el(app, "project.join.error").waitForExistence(timeout: 3))
        XCTAssertFalse(el(app, "project.join.card").exists)
    }

    func testSignedOutJoinAsksToLogIn() {
        let app = launch("shell.projectJoin", extra: ["-uiFixtureProjectJoin", "BB-7K2Q", "-uiFixtureGuest", "YES"], waitFor: "project.join")
        XCTAssertTrue(el(app, "project.join.signIn").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.join.card").exists, "nothing about the invite shows signed out")
        attach(app, "project-join-guest")
    }
}

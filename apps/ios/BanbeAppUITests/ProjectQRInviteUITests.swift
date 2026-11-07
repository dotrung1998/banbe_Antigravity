import XCTest

/// Event Project Hub phase 4b (note 76): QR invites behind switch `project_qr_invite`, and the invitee's in-app scanner.
/// The simulator has no camera, so `-uiFixtureProjectScan` stands in for what the camera would read.
final class ProjectQRInviteUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ fixture: String, extra: [String], waitFor: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", fixture, "-banbe.lang", "en", "-uiTesting", "1", "-banbe.onboarded", "YES"] + extra
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

    func testTheQRIsReadyAtOnceAndSwitchingToMultiUseReplacesIt() {
        let app = launch("shell.project", extra: ["-uiFixtureProjectTab", "team", "-uiFixtureProjectQR", "YES"], waitFor: "project.hub")
        XCTAssertEqual(el(app, "project.team.invite").label, "Invite by QR")
        el(app, "project.team.invite").tap()
        XCTAssertTrue(el(app, "project.invite.qr").waitForExistence(timeout: 5), "minted as the sheet opens, no Create button")
        XCTAssertFalse(el(app, "project.invite.create").exists)
        XCTAssertEqual(el(app, "project.invite.code").label, "B B - 7 K 2 Q")
        XCTAssertTrue(el(app, "project.invite.uses").label.hasSuffix("single use"))
        attach(app, "project-invite-qr")

        el(app, "project.invite.singleUse").switches.firstMatch.tap()
        wait(for: [expectation(for: NSPredicate(format: "label ENDSWITH 'up to 20 people'"), evaluatedWith: el(app, "project.invite.uses"))], timeout: 3)
        let newCode = NSPredicate(format: "label != 'B B - 7 K 2 Q'")
        wait(for: [expectation(for: newCode, evaluatedWith: el(app, "project.invite.code"))], timeout: 5)
        el(app, "project.sheet.close").tap()
        let revokes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'project.invite.revoke.'"))
        XCTAssertTrue(el(app, "project.team.invites").waitForExistence(timeout: 5))
        XCTAssertEqual(revokes.count, 1, "the replaced invite was cancelled")
    }

    func testWithoutTheSwitchThereIsNoQR() {
        let app = launch("shell.project", extra: ["-uiFixtureProjectTab", "team"], waitFor: "project.hub")
        el(app, "project.team.invite").tap()
        XCTAssertTrue(el(app, "project.invite.create").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.invite.qr").exists)
        XCTAssertFalse(el(app, "project.invite.singleUse").exists)
    }

    func testScanningAnInviteQRFillsTheCodeAndShowsTheInvite() {
        let app = launch("shell.projectJoin", extra: ["-uiFixtureProjectScan", "https://www.banbe.app/join/bb-7k2q"], waitFor: "project.join")
        el(app, "project.join.scan").tap()
        XCTAssertTrue(el(app, "project.join.card").waitForExistence(timeout: 8))
        XCTAssertEqual(el(app, "project.join.code").value as? String, "BB-7K2Q", "the link is shown as the bare code")
        XCTAssertTrue(el(app, "project.join.confirm").exists)
    }

    func testScanningSomeOtherQRSaysItIsNotAnInvite() {
        let app = launch("shell.projectJoin", extra: ["-uiFixtureProjectScan", "3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f"], waitFor: "project.join")
        el(app, "project.join.scan").tap()
        let hint = el(app, "project.scan.hint")
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "label == %@", "That QR isn't a banbe team invite."), evaluatedWith: hint)], timeout: 5)
        attach(app, "project-scan-not-invite")
    }
}

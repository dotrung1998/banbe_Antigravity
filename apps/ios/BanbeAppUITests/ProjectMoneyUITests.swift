import XCTest

/// Event Project Hub phase 6 (note 76): Money & door. The Host sees the numbers and goes to the existing screens; team
/// members see the lock card (delegation arrives with phases 9a–9c).
final class ProjectMoneyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(as role: String? = nil, lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiFixture", "shell.project", "-banbe.lang", lang, "-uiTesting", "1", "-banbe.onboarded", "YES",
                                "-uiFixtureProjectTab", "money", "-uiFixtureHostMode", "YES"]
            + (role.map { ["-uiFixtureProjectAs", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(el(app, "project.moneyTab").waitForExistence(timeout: 20))
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testTheHostSeesTheNumbersAndWhatNeedsThem() {
        let app = launch()
        XCTAssertTrue(el(app, "project.money.stats").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.money.awaiting").label.hasPrefix("2"), el(app, "project.money.awaiting").label)
        XCTAssertTrue(el(app, "project.money.verify").label.contains("2 guests waiting for you"))
        XCTAssertTrue(el(app, "project.money.door").label.contains("0/11 seats in"))
        XCTAssertTrue(el(app, "project.money.team").exists, "Hà (Finance) is listed with her access")
        XCTAssertTrue(el(app, "project.tab.money").label.hasSuffix("needs attention"), "the tab shows a dot while guests wait")
        attach(app, "project-money-host")
    }

    func testCheckPaymentsOpensVerificationsAndBackReturnsToTheProject() {
        let app = launch()
        el(app, "project.money.verify").tap()
        XCTAssertTrue(el(app, "verifications.back").waitForExistence(timeout: 5))
        el(app, "verifications.back").tap()
        XCTAssertTrue(el(app, "project.moneyTab").waitForExistence(timeout: 5), "back lands on Money & door again")
    }

    func testAHelperSeesTheLockCard() {
        let app = launch(as: "helper")
        XCTAssertTrue(el(app, "project.money.lock").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.money.stats").exists)
        XCTAssertFalse(el(app, "project.money.verify").exists)
        attach(app, "project-money-lock")
    }

    func testFinanceIsToldTheirAccessIsNotOnYet() {
        let app = launch(as: "finance")
        XCTAssertTrue(el(app, "project.money.lockGranted").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.money.stats").exists, "no amounts until delegation ships")
    }

    // Phase 9a: delegated check-in (switch project_delegate_checkin).
    func testFinanceChecksGuestsInFromTheNamesOnlyList() {
        let app = launch(as: "finance", extra: ["-uiFixtureProjectDoor", "YES"])
        XCTAssertTrue(el(app, "project.door").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.money.stats").exists, "still no amounts")
        XCTAssertEqual(el(app, "project.door.count").label, "2 of 5 people in")
        attach(app, "project-door-finance")
        el(app, "project.door.checkin.door-1").tap()
        XCTAssertTrue(el(app, "project.door.in.door-1").waitForExistence(timeout: 3))
        XCTAssertEqual(el(app, "project.door.count").label, "4 of 5 people in")
        let search = el(app, "project.door.search")
        search.tap(); search.typeText("khang")
        XCTAssertTrue(el(app, "project.door.checkin.door-3").exists)
        XCTAssertFalse(el(app, "project.door.in.door-2").exists, "filtered out")
    }

    func testDelegationNeedsTheAccessAndTheSwitch() {
        let helper = launch(as: "helper", extra: ["-uiFixtureProjectDoor", "YES"])
        XCTAssertTrue(el(helper, "project.money.lock").waitForExistence(timeout: 5), "a helper without check-in access")
        helper.terminate()
        let finance = launch(as: "finance")
        XCTAssertTrue(el(finance, "project.money.lockGranted").waitForExistence(timeout: 5), "the switch is off")
        finance.terminate()
        let host = launch(extra: ["-uiFixtureProjectDoor", "YES"])
        XCTAssertTrue(el(host, "project.money.stats").waitForExistence(timeout: 5), "the Host keeps the full tab")
        XCTAssertFalse(el(host, "project.door").exists)
    }

    // Phase 9b: delegated payment confirmation (switch project_delegate_payments).
    func testFinanceConfirmsAPaymentAndOpensOnlyThatProof() {
        let app = launch(as: "finance", extra: ["-uiFixtureProjectPayments", "YES", "-uiFixtureProjectDoor", "YES"])
        XCTAssertTrue(el(app, "project.payments").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.door").exists, "Finance also has the door")
        XCTAssertFalse(el(app, "project.money.verify").exists, "not the Host's screen")
        XCTAssertFalse(el(app, "project.payments.proof.pay-2").exists, "no proof button without a proof")
        attach(app, "project-payments-finance")
        el(app, "project.payments.proof.pay-1").tap()
        XCTAssertTrue(el(app, "project.proof").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Share"].exists, "view only")
        el(app, "project.proof.close").tap()
        el(app, "project.payments.confirm.pay-1").tap()
        XCTAssertFalse(el(app, "project.payments.confirm.pay-1").waitForExistence(timeout: 2))
        XCTAssertTrue(el(app, "project.payments.confirmed").label.contains("5.390.000"), el(app, "project.payments.confirmed").label)
    }

    func testAHelperWithoutMoneyAccessStillSeesTheLock() {
        let app = launch(as: "helper", extra: ["-uiFixtureProjectPayments", "YES"])
        XCTAssertTrue(el(app, "project.money.lock").waitForExistence(timeout: 5), "this helper has no money access in the demo")
    }

    func testVietnameseDarkAndLargestText() {
        let vi = launch(lang: "vi", extra: ["-banbe.theme", "dark"])
        attach(vi, "project-money-vi-dark")
        vi.terminate()
        let big = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(big, "project.money.stats").waitForExistence(timeout: 5))
        attach(big, "project-money-axxxl")
    }
}

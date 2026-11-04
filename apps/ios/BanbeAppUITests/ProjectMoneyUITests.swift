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

    func testVietnameseDarkAndLargestText() {
        let vi = launch(lang: "vi", extra: ["-banbe.theme", "dark"])
        attach(vi, "project-money-vi-dark")
        vi.terminate()
        let big = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(big, "project.money.stats").waitForExistence(timeout: 5))
        attach(big, "project-money-axxxl")
    }
}

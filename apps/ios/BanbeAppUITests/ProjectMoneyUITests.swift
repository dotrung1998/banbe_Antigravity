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

    // Phase 9c: delegated refunds (switch project_delegate_refunds).
    private let refunds = ["-uiFixtureProjectRefunds", "YES"]

    func testFinanceRecordsARefundForTheHostToApprove() {
        let app = launch(as: "finance", extra: refunds + ["-uiFixtureProjectPayments", "YES"])
        XCTAssertTrue(el(app, "project.refunds").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.payments").exists, "under Payments to check")
        XCTAssertFalse(el(app, "project.hostRefunds").exists, "not the Host's card")
        XCTAssertTrue(el(app, "project.refunds.row.rf-2").label.contains("Disputed"), el(app, "project.refunds.row.rf-2").label)
        attach(app, "project-refunds-finance")
        el(app, "project.refunds.row.rf-1").tap()
        XCTAssertTrue(el(app, "project.refund.amount").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.refund.amount").label.contains("490.000"), el(app, "project.refund.amount").label)
        XCTAssertEqual(el(app, "project.refund.submit").label, "Record transfer for Host approval")
        XCTAssertTrue(el(app, "project.refund.footer").label.contains("only after the Host approves"))
        el(app, "project.refund.copy.number").tap()
        XCTAssertTrue(el(app, "project.refund.copy.number").label.hasPrefix("Copied"), el(app, "project.refund.copy.number").label)
        let note = el(app, "project.refund.note")
        note.tap(); note.typeText("VCB 8812")
        attach(app, "project-refund-sheet")
        el(app, "project.refund.submit").tap()
        XCTAssertTrue(el(app, "project.refunds.waiting.rf-1").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "project.refunds.waiting.rf-1").label.contains("You recorded this · waiting for the Host"),
                      el(app, "project.refunds.waiting.rf-1").label)
        XCTAssertFalse(el(app, "project.refunds.row.rf-1").exists, "no CTA while it waits")
    }

    func testNoRefundAccountMeansNoAction() {
        let app = launch(as: "finance", extra: refunds)
        XCTAssertTrue(el(app, "project.refunds.row.rf-3").waitForExistence(timeout: 5))
        el(app, "project.refunds.row.rf-3").tap()
        XCTAssertTrue(el(app, "project.refund.noAccount").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.refund.submit").isEnabled)
        XCTAssertFalse(el(app, "project.refund.copy.number").exists)
    }

    func testFinanceAloneMarksARefundSent() {
        let app = launch(as: "finance", extra: refunds + ["-uiFixtureProjectRefundMode", "finance_alone"])
        XCTAssertTrue(el(app, "project.refunds.row.rf-1").waitForExistence(timeout: 5))
        el(app, "project.refunds.row.rf-1").tap()
        XCTAssertTrue(el(app, "project.refund.submit").waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "project.refund.submit").label, "Mark refund sent")
        XCTAssertTrue(el(app, "project.refund.footer").label.contains("right away"))
        el(app, "project.refund.submit").tap()
        XCTAssertTrue(el(app, "project.refunds.row.rf-2").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.refunds.row.rf-1").exists, "sent: the row is gone")
    }

    func testTheHostApprovesATeamRecord() {
        let app = launch(extra: refunds)
        XCTAssertTrue(el(app, "project.hostRefunds").waitForExistence(timeout: 5))
        let row = el(app, "project.hostRefunds.row.rf-1")
        XCTAssertTrue(row.label.contains("Recorded by Hà") && row.label.contains("Receipt attached"), row.label)
        XCTAssertFalse(el(app, "project.refunds").exists, "the Host has no delegate list")
        attach(app, "project-refunds-host")
        el(app, "project.hostRefunds.approve.rf-1").tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts["The guest will be told the refund was sent."].exists)
        app.alerts.firstMatch.buttons["Approve"].tap()
        XCTAssertFalse(el(app, "project.hostRefunds").waitForExistence(timeout: 2), "no records left: the card hides")
    }

    func testTheHostDeclineNeedsAReason() {
        let app = launch(extra: refunds)
        XCTAssertTrue(el(app, "project.hostRefunds.decline.rf-1").waitForExistence(timeout: 5))
        el(app, "project.hostRefunds.decline.rf-1").tap()
        XCTAssertTrue(el(app, "project.refundDecline.reason").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.refundDecline.submit").isEnabled, "no reason yet")
        let reason = el(app, "project.refundDecline.reason")
        reason.tap(); reason.typeText("ok")
        XCTAssertFalse(el(app, "project.refundDecline.submit").isEnabled, "2 characters is too short")
        reason.typeText(" wrong account")
        XCTAssertTrue(el(app, "project.refundDecline.submit").isEnabled)
        el(app, "project.refundDecline.submit").tap()
        XCTAssertFalse(el(app, "project.hostRefunds").waitForExistence(timeout: 3))
    }

    func testTheHostSwitchesRefundApprovalWithAConfirmation() {
        let app = launch(extra: refunds)
        let host = el(app, "project.refunds.approval.host"), alone = el(app, "project.refunds.approval.finance")
        XCTAssertTrue(alone.waitForExistence(timeout: 5))
        XCTAssertTrue(host.isSelected)
        alone.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS 'without you'")).firstMatch.exists)
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertTrue(host.isSelected, "cancel keeps the Host approving")
        alone.tap()
        app.alerts.firstMatch.buttons["Switch"].tap()
        XCTAssertTrue(alone.waitForSelected(), "Finance can refund alone")
        host.tap()
        XCTAssertTrue(host.waitForSelected(), "back without a dialog")
    }

    func testTheHostHandsOneDisputedRefundToTheTeamAfterAccessEnds() {
        let early = launch(extra: refunds)
        XCTAssertTrue(el(early, "project.refunds.approval").waitForExistence(timeout: 5))
        XCTAssertFalse(el(early, "project.hostRefunds.grant.rf-2").exists, "the team still has access")
        early.terminate()
        let app = launch(extra: refunds + ["-uiFixtureProjectNow", "2026-11-25T10:00:00+07:00"])
        XCTAssertTrue(el(app, "project.hostRefunds.grant.rf-2").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.hostRefunds.grant.rf-1").exists, "only disputed refunds")
        el(app, "project.hostRefunds.grant.rf-2").tap()
        XCTAssertTrue(el(app, "project.grant.submit").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "project.grant.submit").isEnabled, "pick someone first")
        XCTAssertFalse(el(app, "project.grant.member.00000000-0000-4000-8000-000000000104").exists, "a helper without money access")
        el(app, "project.grant.member.00000000-0000-4000-8000-000000000106").tap()
        el(app, "project.grant.days.14").tap()
        attach(app, "project-refund-grant")
        el(app, "project.grant.submit").tap()
        XCTAssertTrue(app.staticTexts["Hà can handle this refund for 14 days."].waitForExistence(timeout: 5))
    }

    func testRefundsNeedTheSwitch() {
        let host = launch()
        XCTAssertTrue(el(host, "project.money.stats").waitForExistence(timeout: 5))
        XCTAssertFalse(el(host, "project.refunds.approval").exists, "no approval row while the switch is off")
        host.terminate()
        let helper = launch(as: "helper", extra: refunds)
        XCTAssertTrue(el(helper, "project.money.lock").waitForExistence(timeout: 5), "no money access, no refunds")
    }

    func testRefundsInVietnameseAndLargestText() {
        let vi = launch(as: "finance", lang: "vi", extra: refunds)
        XCTAssertTrue(el(vi, "project.refunds").waitForExistence(timeout: 5))
        XCTAssertEqual(el(vi, "project.refunds").label, "Hoàn tiền cần gửi")
        vi.terminate()
        let big = launch(as: "finance", extra: refunds + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(big, "project.refunds.row.rf-1").waitForExistence(timeout: 5))
        attach(big, "project-refunds-axxxl")
        el(big, "project.refunds.row.rf-1").tap()
        XCTAssertTrue(el(big, "project.refund.submit").waitForExistence(timeout: 5))
        attach(big, "project-refund-sheet-axxxl")
        big.terminate()
        let hostBig = launch(extra: refunds + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(el(hostBig, "project.hostRefunds").waitForExistence(timeout: 5))
        attach(hostBig, "project-refunds-host-axxxl")
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

private extension XCUIElement {
    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let p = NSPredicate(format: "isSelected == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: self)], timeout: timeout) == .completed
    }
}

import XCTest

/// Note 78 — the paper ticket, the What's next strip, the stub pager with its tear, and the Event details sheet,
/// against the DEBUG `shell.confirmed` fixture (web twin: tests/ticket-redesign.spec.js). Synthetic data only.
final class ConfirmedTicketUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ ticketCase: String = "upcoming", attendees: Int = 0, scanned: Int = 0, scanAfter: Double = 0,
                        theme: String = "light", lang: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-uiFixture", "shell.confirmed", "-banbe.lang", lang, "-banbe.theme", theme, "-uiTesting", "1",
                    "-banbe.onboarded", "YES", "-uiFixtureTicket", ticketCase]
        if attendees > 0 { args += ["-uiFixtureAttendees", "\(attendees)"] }
        if scanned > 0 { args += ["-uiFixtureScanned", "\(scanned)"] }
        if scanAfter > 0 { args += ["-uiFixtureScanAfter", "\(scanAfter)"] }
        app.launchArguments += args + extra
        app.launch()
        XCTAssertTrue(app.otherElements["screen.confirmed"].waitForExistence(timeout: 20), "the ticket screen did not appear")
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: cases and QR modes

    func testLiveTicketDrawsTheRealQrAndTheGroupedCode() {
        let app = launch("upcoming")
        XCTAssertTrue(el(app, "ticket.qr.real").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "ticket.qr.placeholder").exists)
        XCTAssertEqual(el(app, "confirmed.entryCode").label, "1B1 59C")
        XCTAssertTrue(el(app, "confirmed.strip").exists)
        // No celebration card above the ticket any more, and no filler animation: the ticket is calm.
        XCTAssertFalse(el(app, "confirmed.ticketReveal").exists)
        XCTAssertFalse(el(app, "confirmed.checkInMoment").exists)
        shot("ticket-upcoming-light")
    }

    func testCancelledEndedAndLockedTicketsNeverDrawTheRealQr() {
        for (name, label) in [("cancelled", "Ticket void"), ("ended", "Ended"), ("awaiting", "QR unlocks when the host confirms")] {
            let app = launch(name)
            XCTAssertTrue(el(app, "ticket.qr.placeholder").waitForExistence(timeout: 5), name)
            XCTAssertFalse(el(app, "ticket.qr.real").exists, "\(name) must not draw the real QR")
            XCTAssertEqual(el(app, "confirmed.entryCode").label, "••• •••", name)
            XCTAssertTrue(el(app, "ticket.qr.label").exists, name)
            XCTAssertEqual(el(app, "ticket.qr").label, label, name)
            app.terminate()
        }
    }

    func testAwaitingKeepsPaymentOneTapAwayWithItsOwnClock() {
        let app = launch("awaiting")
        XCTAssertTrue(el(app, "confirmed.pay").exists)
        XCTAssertTrue(el(app, "confirmed.verifyCountdown").exists)
        app.terminate()
        let cancelled = launch("bookingCancelled")
        XCTAssertFalse(el(cancelled, "confirmed.pay").exists, "a cancelled booking is no longer 'awaiting payment'")
        XCTAssertEqual(el(cancelled, "confirmed.strip.heading").label, "This booking was cancelled")
    }

    func testStripExpandsAndShowsOnlyWhatTheDataHolds() {
        let app = launch("upcoming")
        let toggle = el(app, "confirmed.strip.toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "confirmed.strip.detail").exists)
        toggle.tap()
        XCTAssertTrue(el(app, "confirmed.strip.detail").waitForExistence(timeout: 3))
        XCTAssertTrue(el(app, "confirmed.strip.link").exists)
        toggle.tap()
        XCTAssertFalse(el(app, "confirmed.strip.detail").waitForExistence(timeout: 1))
    }

    func testPolicyParagraphIsCollapsedUntilOpened() {
        let app = launch("upcoming")
        XCTAssertTrue(el(app, "confirmed.policyToggle").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "confirmed.policyText").exists)
        el(app, "confirmed.policyToggle").tap()
        XCTAssertTrue(el(app, "confirmed.policyText").waitForExistence(timeout: 3))
    }

    // MARK: multi-ticket scanning

    func testSeveralTicketsAfterTheFirstScanTheStripStaysPreCheckIn() {
        let app = launch("today", attendees: 3, scanned: 1)
        XCTAssertTrue(el(app, "confirmed.stub.1").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "confirmed.stub.badge.1").exists, "the scanned ticket shows its badge")
        XCTAssertNotEqual(el(app, "confirmed.strip.heading").label, "You're in", "one of three scanned is not 'You're in'")
    }

    func testSingleCheckedInTicketSaysYoureIn() {
        let app = launch("checkedIn")
        XCTAssertEqual(el(app, "confirmed.strip.heading").label, "You're in")
    }

    func testAScanWhileOpenTearsTheStubAndMovesOn() {
        // The fixture door scans one open ticket every 6s (slow enough to look before the first scan); after the last
        // one the strip says "You're in".
        let app = launch("today", attendees: 2, scanAfter: 6)
        XCTAssertTrue(el(app, "confirmed.stub.1").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "confirmed.stub.badge.1").exists, "nothing is torn before the scan")
        XCTAssertTrue(el(app, "confirmed.stub.badge.1").waitForExistence(timeout: 15), "the first ticket is torn once scanned")
        XCTAssertNotEqual(el(app, "confirmed.strip.heading").label, "You're in", "one of two scanned is not 'You're in'")
        XCTAssertTrue(el(app, "confirmed.stub.badge.2").waitForExistence(timeout: 20), "every ticket ends up torn")
        let heading = el(app, "confirmed.strip.heading")
        let done = NSPredicate(format: "label == %@", "You're in")
        expectation(for: done, evaluatedWith: heading)
        waitForExpectations(timeout: 10)
        shot("ticket-all-scanned")
    }

    // MARK: Event details sheet and the way back

    func testNameAndPillOpenTheSheet() {
        let app = launch("upcoming")
        el(app, "confirmed.openDetails").tap()
        XCTAssertTrue(el(app, "eventDetails.sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "eventDetails.tile.date").exists)
        XCTAssertTrue(el(app, "eventDetails.about").exists)
        XCTAssertTrue(el(app, "eventDetails.policy").exists)
        shot("sheet-light")
        el(app, "eventDetails.close").tap()
        XCTAssertFalse(el(app, "eventDetails.sheet").waitForExistence(timeout: 2))
        el(app, "confirmed.viewEvent").tap()
        XCTAssertTrue(el(app, "eventDetails.sheet").waitForExistence(timeout: 5))
    }

    func testOpenFullEventPageThenBackReturnsToTheSameTicket() {
        let app = launch("upcoming")
        el(app, "confirmed.openDetails").tap()
        XCTAssertTrue(el(app, "eventDetails.open").waitForExistence(timeout: 5))
        el(app, "eventDetails.open").tap()
        XCTAssertTrue(app.otherElements["screen.event"].waitForExistence(timeout: 10), "the full Event Detail opens")
        let back = el(app, "event.back")
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(back.label.contains("Ticket") || back.label.contains("Vé"), "the pill says where it goes: \(back.label)")
        back.tap()
        XCTAssertTrue(app.otherElements["screen.confirmed"].waitForExistence(timeout: 10), "Back returns to the ticket, not Home")
        XCTAssertFalse(app.otherElements["screen.home"].exists)
        XCTAssertEqual(el(app, "confirmed.entryCode").label, "1B1 59C", "the same booking")
        XCTAssertFalse(el(app, "eventDetails.sheet").exists)
    }

    func testEndedEventSaysViewEventPage() {
        let app = launch("ended")
        el(app, "confirmed.viewEvent").tap()
        XCTAssertTrue(el(app, "eventDetails.open").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "eventDetails.open").label.contains("View event page"))
    }

    // MARK: Dynamic Type and appearance

    func testLargestTextStaysUsable() {
        let size = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        for (theme, lang) in [("light", "vi"), ("dark", "en")] {
            let app = launch("upcoming", theme: theme, lang: lang, extra: size)
            XCTAssertTrue(el(app, "confirmed.openDetails").waitForExistence(timeout: 5))
            shot("ticket-ax5-\(theme)-\(lang)-top")
            // At the largest text the ticket is taller than the screen: the event name must be reachable by scrolling.
            var tries = 0
            while !el(app, "confirmed.openDetails").isHittable, tries < 4 { app.swipeDown(); tries += 1 }
            tries = 0
            while !el(app, "confirmed.openDetails").isHittable, tries < 4 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(el(app, "confirmed.openDetails").isHittable, "\(theme)/\(lang): the event name is reachable at AX5")
            XCTAssertTrue(el(app, "confirmed.tile.date").exists)
            app.terminate()
        }
    }

    func testReducedMotionStillMovesOnAfterAScan() {
        let app = launch("today", attendees: 2, scanAfter: 2, extra: ["-UIAccessibilityReduceMotionEnabled", "YES"])
        XCTAssertTrue(el(app, "confirmed.stub.badge.1").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "confirmed.stub.badge.2").waitForExistence(timeout: 12))
    }
}

import XCTest

/// Coverage for the payment/document screens added alongside supabase
/// migration 024. Like NavigationUITests these stay on paths that work
/// without a signed-in session, so they behave the same on every machine —
/// the signed-in halves (issuing, marking paid) are covered against a real
/// database by the SQL probe instead.
final class PaymentDocumentsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launchToAccount() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-banbe.onboarded", "YES"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 15))
        app.buttons["header.account"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))
        return app
    }

    func testInvoicesAndReceiptsAreTheirOwnRows() {
        let app = launchToAccount()
        XCTAssertTrue(app.buttons["account.invoices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.receipts"].exists)
    }

    func testReceiptsListOpensAndComesBackInOneTap() {
        let app = launchToAccount()
        app.buttons["account.receipts"].tap()
        XCTAssertTrue(app.otherElements["screen.documents"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["documents.title"].waitForExistence(timeout: 5))

        // Signed out there is nothing to list, and the empty state has to say
        // so rather than leaving a blank panel behind.
        XCTAssertTrue(app.staticTexts["documents.empty"].waitForExistence(timeout: 8))

        app.buttons["documents.back"].tap()
        XCTAssertTrue(app.otherElements["screen.profile"].waitForExistence(timeout: 5))
    }

    func testInvoicesListNamesItselfCorrectly() {
        let app = launchToAccount()
        app.buttons["account.invoices"].tap()
        XCTAssertTrue(app.otherElements["screen.documents"].waitForExistence(timeout: 5))
        // The two rows must not open the same list — the heading is what
        // tells them apart once you're inside.
        XCTAssertTrue(app.staticTexts["Hoá đơn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Biên nhận"].exists)
    }

    /// "Getting paid" is meaningless to a goer, and showing it implies banbe
    /// pays them — which is the one thing the whole feature avoids claiming.
    func testHostingPaymentRowsStayHiddenForAGoer() throws {
        let app = launchToAccount()
        try XCTSkipUnless(app.buttons["account.signIn"].waitForExistence(timeout: 3),
                          "Already signed in on this simulator")
        XCTAssertFalse(app.buttons["host.payout"].exists)
        XCTAssertFalse(app.buttons["host.invoices"].exists)
        XCTAssertFalse(app.buttons["host.receipts"].exists)
    }
}

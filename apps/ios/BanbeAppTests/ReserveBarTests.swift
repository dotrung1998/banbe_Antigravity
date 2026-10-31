import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/reserveBar.test.mjs — change both together.
final class ReserveBarTests: XCTestCase {
    func testParsesCataloguePrices() {
        XCTAssertEqual(ReserveBar.parsePrice("200.000₫").unit, 200_000)
        XCTAssertFalse(ReserveBar.parsePrice("200.000₫").free)
        XCTAssertTrue(ReserveBar.parsePrice("Miễn phí").free)
        XCTAssertTrue(ReserveBar.parsePrice("Free").free)
        XCTAssertEqual(ReserveBar.parsePrice("").unit, 0)
    }

    func testTotalMultipliesAndKeepsViForm() {
        XCTAssertEqual(ReserveBar.totalPrice("200.000₫", qty: 1), "200.000₫")
        XCTAssertEqual(ReserveBar.totalPrice("200.000₫", qty: 2), "400.000₫")
        XCTAssertEqual(ReserveBar.totalPrice("1.250.000₫", qty: 4), "5.000.000₫")
        XCTAssertEqual(ReserveBar.totalPrice("Miễn phí", qty: 4), "Miễn phí")
        XCTAssertEqual(ReserveBar.totalPrice("90.000₫", qty: 0), "90.000₫")
    }

    func testStateFollowsOldLabelPriority() {
        func s(booking: Bool = false, ticket: Bool = false, cancelled: Bool = false, ended: Bool = false, soldOut: Bool = false, blocked: Bool = false) -> ReserveBar.State {
            ReserveBar.state(booking: booking, ticket: ticket, cancelled: cancelled, ended: ended, soldOut: soldOut, blocked: blocked)
        }
        XCTAssertEqual(s(), .reserve)
        XCTAssertEqual(s(booking: true, cancelled: true), .pending)
        XCTAssertEqual(s(booking: true, ticket: true), .ticket)
        XCTAssertEqual(s(cancelled: true, ended: true, soldOut: true), .cancelled)
        XCTAssertEqual(s(ended: true, soldOut: true, blocked: true), .ended)
        XCTAssertEqual(s(soldOut: true, blocked: true), .soldOut)
        XCTAssertEqual(s(blocked: true), .blocked)
    }

    /// Phase 1 Q3: shared vectors in tests/fixtures/quick-wins.json (`endedPrecedence`), same as the web test.
    func testEndedWinsOverTheTicket() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/quick-wins.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vectors = try XCTUnwrap(root["endedPrecedence"] as? [[String: Any]])
        XCTAssertFalse(vectors.isEmpty)
        for v in vectors {
            let got = ReserveBar.state(booking: v["booking"] as? Bool ?? false, ticket: v["ticket"] as? Bool ?? false,
                                       cancelled: v["cancelled"] as? Bool ?? false, ended: v["ended"] as? Bool ?? false,
                                       soldOut: v["soldOut"] as? Bool ?? false, blocked: false)
            XCTAssertEqual(got.rawValue, v["expect"] as? String, v["case"] as? String ?? "")
        }
        XCTAssertEqual(ReserveBar.state(booking: true, ticket: true, cancelled: false, ended: true, soldOut: true, blocked: true), .endedAttended)
        XCTAssertEqual(ReserveBar.state(booking: false, ticket: false, cancelled: false, ended: true, soldOut: true,
                                        currencyUnavailable: true, blocked: true), .ended)
    }

    func testTotalFollowsTheEventsCurrency() {
        XCTAssertEqual(ReserveBar.totalPrice(amount: 200_000, currency: "VND", qty: 2), "400.000₫")
        XCTAssertEqual(ReserveBar.totalPrice(amount: 1250, currency: "USD", qty: 2), "$25")
        XCTAssertEqual(ReserveBar.totalPrice(amount: 1250, currency: "USD", qty: 1), "$12.50")
        XCTAssertEqual(ReserveBar.totalPrice(amount: 0, currency: "USD", qty: 3), "Miễn phí")
        XCTAssertEqual(ReserveBar.totalPrice(amount: 90_000, currency: "VND", qty: 0), "90.000₫")
    }

    func testPaidUSDIsADisabledStateNotAnError() {
        func s(booking: Bool = false, cancelled: Bool = false, soldOut: Bool = false, currencyUnavailable: Bool = false, blocked: Bool = false) -> ReserveBar.State {
            ReserveBar.state(booking: booking, ticket: false, cancelled: cancelled, ended: false, soldOut: soldOut,
                             currencyUnavailable: currencyUnavailable, blocked: blocked)
        }
        XCTAssertEqual(s(currencyUnavailable: true), .currencyUnavailable)
        // Meeting the criteria wouldn't make it bookable, so the currency reason wins over the criteria block…
        XCTAssertEqual(s(currencyUnavailable: true, blocked: true), .currencyUnavailable)
        // …but a booking, a cancellation or sold out still say what they always said.
        XCTAssertEqual(s(booking: true, currencyUnavailable: true), .pending)
        XCTAssertEqual(s(cancelled: true, currencyUnavailable: true), .cancelled)
        XCTAssertEqual(s(soldOut: true, currencyUnavailable: true), .soldOut)
        // Free USD events and every VND event book normally.
        XCTAssertTrue(EventMarket.paidBookingAvailable(currency: "USD", amount: 0))
        XCTAssertFalse(EventMarket.paidBookingAvailable(currency: "USD", amount: 1250))
        XCTAssertTrue(EventMarket.paidBookingAvailable(currency: "VND", amount: 150_000))
    }

    func testQuantityStaysWithinCap() {
        XCTAssertEqual(ReserveBar.clampQty(0), 1)
        XCTAssertEqual(ReserveBar.clampQty(3), 3)
        XCTAssertEqual(ReserveBar.clampQty(9), ReserveBar.maxQty)
        XCTAssertEqual(ReserveBar.clampQty(5, max: 3), 3)
        XCTAssertEqual(ReserveBar.clampQty(0, max: 3), 1)
    }

    func testCeilingNeverAboveSeatsLeft() {
        // Regression (note 70): with 3 seats left the stepper could still reach 6.
        XCTAssertEqual(ReserveBar.qtyCeiling(remaining: 3), 3)
        XCTAssertEqual(ReserveBar.qtyCeiling(remaining: 10), ReserveBar.maxQty)
        XCTAssertEqual(ReserveBar.qtyCeiling(remaining: nil), ReserveBar.maxQty)
        XCTAssertEqual(ReserveBar.qtyCeiling(remaining: 0), 1)
        XCTAssertEqual(ReserveBar.clampQty(6, max: ReserveBar.qtyCeiling(remaining: 3)), 3)
    }
}

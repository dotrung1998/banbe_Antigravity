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

    func testQuantityStaysWithinCap() {
        XCTAssertEqual(ReserveBar.clampQty(0), 1)
        XCTAssertEqual(ReserveBar.clampQty(3), 3)
        XCTAssertEqual(ReserveBar.clampQty(9), ReserveBar.maxQty)
        XCTAssertTrue(ReserveBar.presets.allSatisfy { (1...ReserveBar.maxQty).contains($0) })
    }
}

import XCTest
@testable import BanbeApp

/// Event Project Hub phase 6 (note 76): the Host's Money & door numbers.
@MainActor
final class ProjectMoneyTests: XCTestCase {
    func testTheSummaryCountsWhatTheHostActsOn() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = now.addingTimeInterval(600), earlier = now.addingTimeInterval(-600)
        let s = AppState.projectMoneySummary(bookings: [
            (2, "confirmed", 980_000, nil, nil),
            (1, "attended", 490_000, nil, nil),
            (1, "pending", 490_000, later, now),        // said "I paid": waits for the Host
            (2, "pending", 980_000, later, nil),        // a live hold, not paid yet: a seat, not waiting
            (1, "pending", 490_000, earlier, nil),      // an expired hold: nobody's seat
            (1, "pending", 490_000, earlier, earlier),  // expired but marked paid: still waits for a check
            (3, "cancelled", 1_470_000, nil, nil),
        ], refunds: [(true, false), (true, true), (false, false)], now: now)
        XCTAssertEqual(s.confirmedSeats, 3)
        XCTAssertEqual(s.confirmedAmount, 1_470_000)
        XCTAssertEqual(s.awaiting, 2)
        XCTAssertEqual(s.checkedIn, 1)
        XCTAssertEqual(s.seats, 7)
        XCTAssertEqual(s.refunds, 2, "only owed or disputed claims")
        XCTAssertEqual(s.refundsOverdue, 1)
        XCTAssertTrue(s.needsHost)
        XCTAssertFalse(ProjectMoneySummary().needsHost)
    }
}

@MainActor
final class ProjectDoorTests: XCTestCase {
    func testTheDoorListGroupsNamesByBooking() {
        let g = AppState.projectDoorGuests([
            ProjectDoorRow(bookingId: "b1", attendeeId: "a1", name: "Anh", party: 1, checkedIn: true),
            ProjectDoorRow(bookingId: "b2", attendeeId: nil, name: "Ha", party: 3, checkedIn: false),
            ProjectDoorRow(bookingId: "b1", attendeeId: "a2", name: "Binh", party: 1, checkedIn: false),
        ])
        XCTAssertEqual(g.map(\.bookingId), ["b1", "b2"], "first-seen order")
        XCTAssertEqual(g[0].names, ["Anh", "Binh"])
        XCTAssertEqual(g[0].party, 2)
        XCTAssertEqual(g[0].inside, 1)
        XCTAssertFalse(g[0].allIn)
        XCTAssertEqual(g[1].party, 3)
    }
}

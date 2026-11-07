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

/// Phase 9c (migration 215): what a refund delegate's row offers, the Host's dispute hand-off, and the view's shape.
@MainActor
final class ProjectRefundsTests: XCTestCase {
    private func claim(account: ProjectRefundAccount? = ProjectRefundAccount(bankName: "VCB", accountNumber: "0071", accountHolderName: "AN"),
                       request: ProjectRefundRequest? = nil, declined: String? = nil, dispute: Bool = false) -> ProjectRefundClaim {
        ProjectRefundClaim(claimId: "c1", bookingId: "b1", name: "An", amount: 490_000, status: dispute ? "disputed" : "owed",
                           refundDueAt: nil, disputeOpen: dispute, account: account, request: request,
                           lastDeclined: declined.map { ProjectRefundDecline(reason: $0, at: nil) })
    }

    func testTheRowStateFollowsTheAccountAndTheRecord() {
        XCTAssertEqual(AppState.projectRefundRowState(claim()), .ready(declined: nil))
        XCTAssertEqual(AppState.projectRefundRowState(claim(account: nil)), .noAccount)
        XCTAssertEqual(AppState.projectRefundRowState(claim(account: ProjectRefundAccount(bankName: "VCB", accountNumber: " ", accountHolderName: "AN"))),
                       .noAccount, "a blank part is no account")
        let mine = ProjectRefundRequest(id: "r", by: "Hà", mine: true, note: nil, hasProof: false, at: nil)
        XCTAssertEqual(AppState.projectRefundRowState(claim(request: mine)), .waiting(mine: true))
        XCTAssertEqual(AppState.projectRefundRowState(claim(account: nil, request: mine)), .waiting(mine: true), "a record wins")
        XCTAssertEqual(AppState.projectRefundRowState(claim(declined: "Sai số tài khoản")), .ready(declined: "Sai số tài khoản"),
                       "declined: may record again")
    }

    func testTheDisputeHandOffOnlyOnceTheTeamsAccessIsOver() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let open = claim(dispute: true)
        XCTAssertFalse(AppState.projectRefundGrantOffer(claim(), readOnly: true, eventEnd: end, now: end), "no dispute, no hand-off")
        XCTAssertTrue(AppState.projectRefundGrantOffer(open, readOnly: true, eventEnd: end, now: end))
        XCTAssertFalse(AppState.projectRefundGrantOffer(open, readOnly: false, eventEnd: end, now: end.addingTimeInterval(6 * 86_400), grantDays: 7))
        XCTAssertTrue(AppState.projectRefundGrantOffer(open, readOnly: false, eventEnd: end, now: end.addingTimeInterval(7 * 86_400), grantDays: 7))
        XCTAssertFalse(AppState.projectRefundGrantOffer(open, readOnly: false, eventEnd: nil, now: end))
    }

    func testTheRefundViewDecodes() throws {
        let json = """
        {"success": true, "mode": "host", "host": false, "claims": [
          {"claim_id": "c1", "booking_id": "b1", "name": "An", "amount": 490000, "status": "owed", "refund_due_at": "2026-11-12T03:00:00+00:00",
           "dispute_open": false, "account": {"bank_name": "VCB", "account_number": "0071", "account_holder_name": "AN"},
           "request": {"id": "r1", "by": "Hà", "mine": true, "note": null, "has_proof": true, "at": "2026-11-03T07:05:00.123+00:00"},
           "last_declined": null},
          {"claim_id": "c2", "booking_id": "b2", "name": "Bo", "amount": 980000, "status": "disputed", "refund_due_at": null,
           "dispute_open": true, "account": null, "request": null, "last_declined": {"reason": "Sai", "at": null}}]}
        """
        let v = try JSONDecoder().decode(ProjectRefundView.self, from: Data(json.utf8))
        XCTAssertEqual(v.mode, "host")
        XCTAssertEqual(v.claims?.count, 2)
        XCTAssertEqual(v.claims?[0].request?.hasProof, true)
        XCTAssertNil(v.claims?[1].account)
        XCTAssertEqual(AppState.projectRefundRowState(v.claims![1]), .noAccount)
    }
}

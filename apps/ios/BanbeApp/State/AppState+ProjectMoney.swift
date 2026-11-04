import Foundation

/// Event Project Hub phase 6 (note 76): Money & door for the Host. Read only, from what the Host can already read:
/// the event's bookings (bookings RLS: the organizer's own events) and `get_host_refund_claims` (077/078). Nothing new on
/// the server; the actions themselves stay in the existing Verifications, refund and Attendance screens, which the tab
/// links to. Team members see a lock card: delegated money and check-in arrive with migrations 212–214 (phases 9a–9c).
struct ProjectMoneySummary: Equatable {
    /// Confirmed or attended bookings: seats and the amount (minor units of the event's currency; VND today).
    var confirmedSeats = 0
    var confirmedAmount = 0
    /// Guests who marked "I paid" and wait for the Host to check the transfer.
    var awaiting = 0
    /// Open refund claims (owed or disputed) and how many of them are past due.
    var refunds = 0
    var refundsOverdue = 0
    /// Seats checked in out of seats booked.
    var checkedIn = 0
    var seats = 0

    var needsHost: Bool { awaiting > 0 || refunds > 0 }
}

private struct ProjectMoneyBooking: Decodable {
    let qty: Int
    let status: String
    let totalVnd: Int?
    let expiresAt: Date?
    let paidMarkedAt: Date?
    enum CodingKeys: String, CodingKey {
        case qty, status
        case totalVnd = "total_vnd", expiresAt = "expires_at", paidMarkedAt = "paid_marked_at"
    }
}

extension AppState {
    /// Money and door are the organizer accounts' own today (the existing RPCs' check, never `project_is_host`).
    var projectMoneyAccess: Bool { projectCan("money.view") }

    /// Pure: the summary from booking rows and refund claims, so the rules can be tested.
    static func projectMoneySummary(bookings: [(qty: Int, status: String, total: Int?, expiresAt: Date?, paidMarkedAt: Date?)],
                                    refunds: [(active: Bool, overdue: Bool)], now: Date) -> ProjectMoneySummary {
        var s = ProjectMoneySummary()
        for b in bookings {
            switch b.status {
            case "confirmed", "attended":
                s.confirmedSeats += b.qty
                s.confirmedAmount += b.total ?? 0
                s.seats += b.qty
                if b.status == "attended" { s.checkedIn += b.qty }
            case "pending":
                // An expired hold is nobody's seat; a live one counts as waiting only once the guest says they paid.
                guard (b.expiresAt ?? .distantFuture) > now || b.paidMarkedAt != nil else { continue }
                s.seats += b.qty
                if b.paidMarkedAt != nil { s.awaiting += 1 }
            default: break
            }
        }
        let active = refunds.filter(\.active)
        s.refunds = active.count
        s.refundsOverdue = active.filter(\.overdue).count
        return s
    }

    func loadProjectMoney() async {
        guard projectMoneyAccess else { projectMoney = nil; return }
        #if DEBUG
        if UITestFixture.isActive {
            projectMoney = ProjectMoneySummary(confirmedSeats: 9, confirmedAmount: 4_410_000, awaiting: 2, refunds: 1, refundsOverdue: 0,
                                               checkedIn: 0, seats: 11)
            return
        }
        #endif
        let eventID = projectEventID
        do {
            let rows: [ProjectMoneyBooking] = try await SupabaseService.client
                .from("bookings").select("qty, status, total_vnd, expires_at, paid_marked_at")
                .eq("event_id", value: eventID)
                .in("status", values: ["pending", "confirmed", "attended"])
                .execute().value
            // The refund list is keyed by the event's uuid; a non-uuid id has no claims to show.
            var refunds: [(active: Bool, overdue: Bool)] = []
            if UUID(uuidString: eventID) != nil {
                await loadRefundCenter(eventKey: eventID)
                refunds = refundCenterClaims.map { ($0.claim.isActiveRefundStatus, $0.overdue) }
            }
            guard eventID == projectEventID else { return }
            projectMoney = Self.projectMoneySummary(
                bookings: rows.map { ($0.qty, $0.status, $0.totalVnd, $0.expiresAt, $0.paidMarkedAt) }, refunds: refunds, now: Date())
        } catch {
            print("loadProjectMoney failed:", error)
        }
    }
}

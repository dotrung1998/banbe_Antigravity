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

// MARK: - phase 9a: delegated check-in (migration 212, switch project_delegate_checkin)

/// One row of `get_event_checkin_names`: names and check-in state only (no amounts, codes, tokens or birth dates).
struct ProjectDoorRow: Decodable, Equatable {
    let bookingId: String
    let attendeeId: String?
    let name: String
    let party: Int
    let checkedIn: Bool
    enum CodingKeys: String, CodingKey {
        case name, party
        case bookingId = "booking_id", attendeeId = "attendee_id", checkedIn = "checked_in"
    }
}

private struct ProjectDoorResult: Decodable {
    let success: Bool
    let error: String?
    let guests: [ProjectDoorRow]?
}

/// One booking at the door: its names, how many people, how many are in.
struct ProjectDoorGuest: Equatable, Identifiable {
    let bookingId: String
    var names: [String]
    var party: Int
    var inside: Int
    var id: String { bookingId }
    var allIn: Bool { inside >= party }
}

extension AppState {
    /// A team member with check-in access while the switch is on (the Host uses Attendance as before).
    var projectDoorAccess: Bool { !projectMoneyAccess && projectCan("checkin") }

    /// Pure: rows grouped by booking (named attendees count one each; a booking without names counts its party).
    static func projectDoorGuests(_ rows: [ProjectDoorRow]) -> [ProjectDoorGuest] {
        var order: [String] = []
        var map: [String: ProjectDoorGuest] = [:]
        for r in rows {
            if map[r.bookingId] == nil { order.append(r.bookingId); map[r.bookingId] = ProjectDoorGuest(bookingId: r.bookingId, names: [], party: 0, inside: 0) }
            map[r.bookingId]!.names.append(r.name)
            map[r.bookingId]!.party += r.party
            if r.checkedIn { map[r.bookingId]!.inside += r.party }
        }
        return order.compactMap { map[$0] }
    }

    func loadProjectDoor() async {
        guard projectDoorAccess else { projectDoor = nil; return }
        #if DEBUG
        if UITestFixture.isActive {
            if projectDoor == nil {
                projectDoor = Self.projectDoorGuests([
                    ProjectDoorRow(bookingId: "door-1", attendeeId: "a1", name: "Ngọc Anh", party: 1, checkedIn: false),
                    ProjectDoorRow(bookingId: "door-1", attendeeId: "a2", name: "Quốc Bảo", party: 1, checkedIn: false),
                    ProjectDoorRow(bookingId: "door-2", attendeeId: nil, name: "Thu Hà", party: 2, checkedIn: true),
                    ProjectDoorRow(bookingId: "door-3", attendeeId: nil, name: "Minh Khang", party: 1, checkedIn: false),
                ])
            }
            return
        }
        #endif
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        do {
            let result: ProjectDoorResult = try await SupabaseService.client
                .rpc("get_event_checkin_names", params: Params(pEventId: projectEventID)).execute().value
            if result.success { projectDoor = Self.projectDoorGuests(result.guests ?? []) }
            else { projectNotice = projectErrorText(result.error) }
        } catch {
            print("loadProjectDoor failed:", error)
        }
    }

    /// Check a whole party in from the list (check_in_guest 'manual'; the server writes the audit row).
    @discardableResult
    func checkInProjectGuest(_ bookingID: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            guard let i = projectDoor?.firstIndex(where: { $0.bookingId == bookingID }) else { return false }
            projectDoor?[i].inside = projectDoor?[i].party ?? 0
            return true
        }
        #endif
        struct Params: Encodable {
            let pReservationId: String; let pSource: String
            enum CodingKeys: String, CodingKey { case pReservationId = "p_reservation_id", pSource = "p_source" }
        }
        struct Result: Decodable { let success: Bool; let error: String? }
        projectBusy = true
        defer { projectBusy = false }
        do {
            let r: Result = try await SupabaseService.client.rpc("check_in_guest", params: Params(pReservationId: bookingID, pSource: "manual")).execute().value
            guard r.success else {
                projectNotice = r.error == "Guest already checked in" ? T("Khách này đã vào rồi.", "This guest is already in.")
                    : r.error == "Not authorized" ? T("Quyền check-in của bạn đã hết hoặc đang tắt.", "Your check-in access has ended or is switched off.")
                    : projectErrorText(nil)
                await loadProjectDoor()
                return false
            }
            Haptics.success()
            await loadProjectDoor()
            return true
        } catch {
            print("checkInProjectGuest failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }
}

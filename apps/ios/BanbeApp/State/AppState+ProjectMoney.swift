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
    /// The Host's own Money & door view: the organizer accounts (the existing RPCs' check, never `project_is_host`).
    /// A delegate with money access passes `money.view` too once 214's switch is on, so this also needs `isHost`.
    var projectMoneyAccess: Bool { projectSnapshot?.isHost == true && projectCan("money.view") }

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
        if projectOffline {
            projectMoney = ProjectDemo.moneySummary
            return
        }
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
    var projectDoorAccess: Bool { projectSnapshot?.isHost != true && projectCan("checkin") }

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
        if projectOffline {
            if projectDoor == nil {
                projectDoor = Self.projectDoorGuests(ProjectDemo.doorRows)
            }
            return
        }
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
        if projectOffline {
            guard let i = projectDoor?.firstIndex(where: { $0.bookingId == bookingID }) else { return false }
            projectDoor?[i].inside = projectDoor?[i].party ?? 0
            return true
        }
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

// MARK: - phase 9b: delegated payment confirmation (migration 214, switch project_delegate_payments)

/// One booking waiting for a payment check, as `get_event_money_view` returns it (no proof path, no documents).
struct ProjectAwaitingPayment: Decodable, Equatable, Identifiable {
    let bookingId: String
    let name: String
    let qty: Int
    let amount: Int
    let paymentRef: String?
    let paidMarkedAt: String?
    let hasProof: Bool
    var id: String { bookingId }
    enum CodingKeys: String, CodingKey {
        case name, qty, amount
        case bookingId = "booking_id", paymentRef = "payment_ref", paidMarkedAt = "paid_marked_at", hasProof = "has_proof"
    }
}

struct ProjectMoneyView: Decodable, Equatable {
    let success: Bool
    let error: String?
    var confirmedAmount: Int?
    var confirmedSeats: Int?
    var awaiting: [ProjectAwaitingPayment]?
    enum CodingKeys: String, CodingKey {
        case success, error, awaiting
        case confirmedAmount = "confirmed_amount", confirmedSeats = "confirmed_seats"
    }
}

private struct ProjectProofResult: Decodable {
    let success: Bool
    let error: String?
    let bucket: String?
    let path: String?
}

extension AppState {
    /// A team member with money access while the switch is on (the Host keeps the full tab).
    var projectPaymentsAccess: Bool { projectSnapshot?.isHost != true && projectCan("money.confirm") }

    func loadProjectPayments() async {
        guard projectPaymentsAccess else { projectPayments = nil; return }
        if projectOffline {
            if projectPayments == nil {
                projectPayments = ProjectDemo.payments
            }
            return
        }
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        do {
            let r: ProjectMoneyView = try await SupabaseService.client.rpc("get_event_money_view", params: Params(pEventId: projectEventID)).execute().value
            if r.success { projectPayments = r } else { projectNotice = projectErrorText(r.error) }
        } catch {
            print("loadProjectPayments failed:", error)
        }
    }

    /// "Money received" for one booking (verify_payment; the server checks access and writes the audit row).
    @discardableResult
    func confirmProjectPayment(_ bookingID: String) async -> Bool {
        if projectOffline {
            if let i = projectPayments?.awaiting?.firstIndex(where: { $0.bookingId == bookingID }), let row = projectPayments?.awaiting?[i] {
                projectPayments?.awaiting?.remove(at: i)
                projectPayments?.confirmedAmount = (projectPayments?.confirmedAmount ?? 0) + row.amount
                projectPayments?.confirmedSeats = (projectPayments?.confirmedSeats ?? 0) + row.qty
            }
            return true
        }
        struct Params: Encodable {
            let pBooking: String; let pVia: String; let pActorKind: String
            enum CodingKeys: String, CodingKey { case pBooking = "p_booking", pVia = "p_via", pActorKind = "p_actor_kind" }
        }
        struct Result: Decodable { let success: Bool; let error: String? }
        projectBusy = true
        defer { projectBusy = false }
        do {
            let r: Result = try await SupabaseService.client
                .rpc("verify_payment", params: Params(pBooking: bookingID, pVia: "project_team", pActorKind: "organizer")).execute().value
            if !r.success {
                projectNotice = r.error == "NOT_AUTHORIZED" ? T("Quyền tiền của bạn đã hết hoặc đang tắt.", "Your money access has ended or is switched off.")
                    : projectErrorText(nil)
            } else { Haptics.success() }
            await loadProjectPayments()
            return r.success
        } catch {
            print("confirmProjectPayment failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }

    /// Opens one booking's transfer proof: the server logs the open first, then a 60-second signed link is made.
    func openProjectProof(_ bookingID: String) async -> URL? {
        if projectOffline { return nil }
        struct Params: Encodable {
            let pBookingId: String
            enum CodingKeys: String, CodingKey { case pBookingId = "p_booking_id" }
        }
        do {
            let r: ProjectProofResult = try await SupabaseService.client.rpc("open_payment_proof", params: Params(pBookingId: bookingID)).execute().value
            guard r.success, let path = r.path else {
                projectNotice = r.error == "NO_PROOF" ? T("Khách chưa gửi ảnh chuyển khoản.", "The guest hasn't sent a transfer proof.")
                    : r.error == "NOT_AWAITING" ? T("Khoản này không còn chờ xác nhận.", "This payment is no longer waiting for a check.")
                    : T("Bạn không mở được ảnh này.", "You can't open this proof.")
                return nil
            }
            let results = try await SupabaseService.client.storage.from(r.bucket ?? "pay-proof")
                .createSignedURLs(paths: [path], expiresIn: ProjectLimits.shared.proofUrlSeconds)
            for result in results { if case let .success(p, url) = result, p == path { return url } }
            return nil
        } catch {
            print("openProjectProof failed:", error)
            projectNotice = projectErrorText(nil)
            return nil
        }
    }
}

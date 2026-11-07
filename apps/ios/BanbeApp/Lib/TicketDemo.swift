import Foundation

/// Admin "Ticket demo" (migration 217, switch `ticket_demo`): the real ticket screen on a sample booking in any status
/// (Hold / Pay / Review included). Admins only. Nothing reaches the server: ConfirmedView skips every read and poll and
/// answers every write with "Not available in the demo" while `AppState.ticketDemo` is set. Release-compiled.
/// Web twin: src/lib/ticketDemo.js.
enum TicketDemo {
    static let flag = "ticket_demo"

    enum Variant: String, CaseIterable { case single, named, gifted }

    struct Session { let key: String; let prevEventKey: String }

    /// Picker order. (payment state, booking status, event status, hours until the start)
    struct Spec { let key: String; let vi: String; let en: String
        let pay: PaymentPhase; let status: String; let event: String; let startHours: Double }
    static let specs: [Spec] = [
        Spec(key: "holding", vi: "Giữ chỗ (đang giữ)", en: "Hold (seats held)", pay: .holding, status: "pending", event: "live", startHours: 72),
        Spec(key: "awaiting", vi: "Thanh toán (chờ xác nhận)", en: "Pay (awaiting host)", pay: .pendingVerification, status: "pending", event: "live", startHours: 72),
        Spec(key: "review", vi: "Đang xem xét (tranh chấp)", en: "Review (dispute)", pay: .disputed, status: "confirmed", event: "live", startHours: 72),
        Spec(key: "upcoming", vi: "Vé sắp diễn ra", en: "Ticket, upcoming", pay: .confirmed, status: "confirmed", event: "live", startHours: 72),
        Spec(key: "today", vi: "Vé hôm nay", en: "Ticket, today", pay: .confirmed, status: "confirmed", event: "live", startHours: 2),
        Spec(key: "checkedIn", vi: "Đã check-in", en: "Checked in", pay: .confirmed, status: "attended", event: "live", startHours: 1),
        Spec(key: "ended", vi: "Sự kiện đã kết thúc", en: "Event ended", pay: .confirmed, status: "confirmed", event: "ended", startHours: -13),
        Spec(key: "cancelled", vi: "Sự kiện bị huỷ", en: "Event cancelled", pay: .confirmed, status: "confirmed", event: "cancelled", startHours: 72),
        Spec(key: "expired", vi: "Giữ chỗ hết hạn", en: "Hold expired", pay: .expired, status: "expired", event: "live", startHours: 72),
    ]

    /// Gate for the Account entry: admins only, switch on (missing = off).
    static func available(isAdmin: Bool, flags: [String: Bool]) -> Bool {
        isAdmin && FeatureFlags.isOn(flags, flag)
    }

    /// Variants only make sense for a paid ticket.
    static func hasVariants(_ key: String) -> Bool { !["holding", "awaiting", "review", "expired"].contains(key) }
}

extension AppState {
    var ticketDemoAvailable: Bool { TicketDemo.available(isAdmin: isAdmin, flags: featureFlags) }

    /// Shows case `key` on the ticket screen with sample data. `named`: 3 named tickets; `gifted`: the ticket was gifted.
    func startTicketDemo(_ key: String, variant: TicketDemo.Variant) {
        guard ticketDemoAvailable, let spec = TicketDemo.specs.first(where: { $0.key == key }) else { return }
        let prev = ticketDemo?.prevEventKey ?? eventKey
        let now = Date()
        let named = TicketDemo.hasVariants(key) && variant == .named
        let bookingID = UUID()
        ticketDemo = TicketDemo.Session(key: key, prevEventKey: prev)
        eventKey = "bepnho"
        liveEventStatus = LiveEventStatus(status: spec.event, startsAt: now.addingTimeInterval(spec.startHours * 3600),
                                          cancelledAt: spec.event == "cancelled" ? now : nil, cancelReason: nil, details: nil, capacity: nil)
        var b = Booking(id: bookingID, eventId: "bepnho", userId: nil, qty: named ? 3 : 1, totalVnd: 0, code: "1B159C", status: spec.status,
                        expiresAt: nil, paidMarkedAt: spec.pay == .confirmed ? now : nil, cancelledAt: nil, cancelReason: nil, createdAt: now,
                        paymentState: spec.pay,
                        holdExpiresAt: spec.pay == .holding ? now.addingTimeInterval(20 * 60) : nil,
                        verifyDueAt: spec.pay == .pendingVerification ? now.addingTimeInterval(3600) : nil,
                        admissionToken: UUID())
        if TicketDemo.hasVariants(key) && variant == .gifted { b.recipientName = "Linh"; b.claimCode = "DEMO-CLAIM" }
        booking = b
        holdDeadline = nil
        let names = ["Linh", "Minh", "An"]
        bookingAttendees = named ? names.enumerated().map { i, n in
            BookingAttendee(id: UUID(), bookingId: bookingID, seatNo: i + 1, name: n, dateOfBirth: "1995-01-01", admissionToken: UUID(), ticketCode: "1B159\(i + 1)",
                            checkedInAt: key == "checkedIn" ? now.addingTimeInterval(-600) : nil, claimCode: nil, claimedAt: nil)
        } : []
        receiptChecked = true
        receiptDoc = nil
        confirmedBack = .accountGroup
        screen = .confirmed
    }

    /// Leaves the demo and forgets the sample booking. Leaving the ticket screen any other way ends it too (AppState.screen's didSet).
    func endTicketDemo(goBack: Bool = false) {
        guard let demo = ticketDemo else { return }
        ticketDemo = nil
        booking = nil; holdDeadline = nil; liveEventStatus = nil; bookingAttendees = []
        receiptChecked = false; receiptDoc = nil
        eventKey = demo.prevEventKey
        if goBack, screen == .confirmed { screen = .accountGroup }
        Task { await loadBookingForCurrentEvent(); await loadLiveEventStatus() }
    }
}

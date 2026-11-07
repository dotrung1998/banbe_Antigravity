import Foundation

/// Ticket screen (note 78): which "What's next" case a booking is in, how its QR may be drawn, and the 3-3 entry code.
/// Twin of src/lib/ticketStatus.js; vectors in tests/fixtures/ticket-status.json are shared with
/// BanbeAppTests/TicketStatusTests.swift and tests/unit/ticketStatus.test.mjs, so change all three together.
/// Flat on purpose: the caller derives isPaid / checkedIn / daysUntil with the existing helpers.
enum TicketStatus {
    enum Key: String, CaseIterable { case cancelled, expired, review, holding, awaiting, ended, checkedIn, today, upcoming }
    /// ok/in draw the real code; lock/void/past never do (see `qrShowsToken`).
    enum QR: String { case ok, `in`, lock, void, past }
    /// Names a theme role, not a colour: alert, honey, plum, ink3, moss, clay, mist.
    struct Case: Equatable { let key: Key; let tone: String; let qr: QR }

    private static let table: [Key: (tone: String, qr: QR)] = [
        .cancelled: ("alert", .void), .expired: ("alert", .void), .review: ("honey", .lock),
        .holding: ("honey", .lock), .awaiting: ("plum", .lock), .ended: ("ink3", .past),
        .checkedIn: ("moss", .in), .today: ("clay", .ok), .upcoming: ("mist", .ok),
    ]

    /// First matching row wins. nil when there is no booking to explain.
    static func resolve(paymentState: String?, eventCancelled: Bool = false, endedHoursAgo: Int? = nil,
                        isPaid: Bool = false, checkedIn: Bool = false, daysUntil: Int? = nil) -> Case? {
        let key: Key?
        if eventCancelled || paymentState == "cancelled" { key = .cancelled }
        else if paymentState == "expired" { key = .expired }
        else if paymentState == "disputed" { key = .review }
        else if paymentState == "holding" { key = .holding }
        else if paymentState == "pending_verification" { key = .awaiting }
        else if isPaid && endedHoursAgo != nil { key = .ended }
        else if isPaid && checkedIn { key = .checkedIn }
        else if isPaid && daysUntil == 0 { key = .today }
        else if isPaid { key = .upcoming }
        else { key = nil }
        guard let key, let row = table[key] else { return nil }
        return Case(key: key, tone: row.tone, qr: row.qr)
    }

    /// The admission token may only be drawn as a real QR in these modes; everything else gets a placeholder.
    static func qrShowsToken(_ qr: QR?) -> Bool { qr == .ok || qr == .in }

    /// "1B159C" -> "1B1 59C". Anything that is not 6 characters is returned unchanged.
    static func formatEntryCode(_ code: String?) -> String {
        let c = (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard c.count == 6 else { return c }
        return String(c.prefix(3)) + " " + String(c.suffix(3))
    }

    /// Distance line for the event sheet: only when the viewer is located and it is within the 50 km rule.
    static func showDistance(km: Double?, located: Bool?, en: Bool) -> String? {
        located == true ? EventDetailPresentation.distanceLabel(km: km, en: en) : nil
    }

    // MARK: Door watch (note 78)
    // The ticket screen polls for a scan from 3h before the start to 12h after, only while a scan is still to come.
    // A booking with named tickets is done when EVERY ticket is scanned; any other booking is done once it reads
    // checked in, exactly as before. Twin of doorWatchOpen / inDoorWindow in src/lib/ticketStatus.js.
    static let doorBefore: TimeInterval = 3 * 3600
    static let doorAfter: TimeInterval = 12 * 3600

    /// Strictly inside the window: the start minus 3h and the start plus 12h themselves are outside.
    static func inDoorWindow(start: Date?, now: Date) -> Bool {
        guard let start else { return false }
        return now > start.addingTimeInterval(-doorBefore) && now < start.addingTimeInterval(doorAfter)
    }

    /// `namedScans`: one flag per named ticket (scanned or not), nil or empty when the booking has none.
    static func doorWatchOpen(namedScans: [Bool]?, checkedIn: Bool, start: Date?, now: Date) -> Bool {
        guard inDoorWindow(start: start, now: now) else { return false }
        let done = (namedScans?.isEmpty == false) ? namedScans!.allSatisfy { $0 } : checkedIn
        return !done
    }
}

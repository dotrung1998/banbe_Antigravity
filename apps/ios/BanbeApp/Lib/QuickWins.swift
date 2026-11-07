import Foundation

/// Phase 1 quick wins (docs/impl/phase1-quick-wins.md): the pure rules behind the ticket reveal, the honest wait, the
/// check-in moment, the host "You're live" card and Home's "Saved, coming up" row. Mirrors src/lib/quickWins.js; shared
/// vectors in tests/fixtures/quick-wins.json (BanbeAppTests/QuickWinsTests.swift and tests/unit/quickWins.test.mjs) —
/// change all three together.
///
/// No countdowns, no "hurry", no loss framing: every text here states a real fact or nothing at all.
enum QuickWins {
    /// Once per milestone per device. `<id>` is the booking id (ticket, check-in) or the event id (live).
    enum Moment: String, CaseIterable { case ticketReveal, checkIn, eventLive }

    static let onceKeyTemplates: [Moment: String] = [
        .ticketReveal: "banbe.moment.ticketReveal.v1.<bookingId>",
        .checkIn: "banbe.moment.checkIn.v1.<bookingId>",
        .eventLive: "banbe.moment.eventLive.v1.<eventId>",
    ]

    /// Lower-cased id, so a UUID reads the same as web's `crypto` string form.
    static func onceKey(_ moment: Moment, _ id: String) -> String? {
        guard !id.isEmpty, let tpl = onceKeyTemplates[moment],
              let range = tpl.range(of: "<[^>]+>", options: .regularExpression) else { return nil }
        return tpl.replacingCharacters(in: range, with: id.lowercased())
    }

    static func seenOnce(_ moment: Moment, _ id: String, defaults: UserDefaults = .standard) -> Bool {
        guard let key = onceKey(moment, id) else { return true }
        return defaults.object(forKey: key) != nil
    }

    /// True exactly once per key per device: records the key and says whether this is the first time.
    @discardableResult
    static func claimOnce(_ moment: Moment, _ id: String, defaults: UserDefaults = .standard) -> Bool {
        guard let key = onceKey(moment, id), defaults.object(forKey: key) == nil else { return false }
        defaults.set(true, forKey: key)
        return true
    }

    /// "This host usually confirms within about 30 minutes." from get_host_confirmation_time's median (migration 198;
    /// nil below 5 confirmations -> nothing). 5-minute steps under an hour, whole hours under a day, then whole days.
    static func typicalWaitText(minutes: Double?) -> (vi: String, en: String)? {
        guard let m = minutes, m.isFinite, m >= 0 else { return nil }
        func span(_ n: Int, _ vi: String, _ en: String) -> (vi: String, en: String) {
            ("\(n) \(vi)", "\(n) \(en)\(n == 1 ? "" : "s")")
        }
        let fiveMin = max(5, Int((m / 5).rounded()) * 5)
        let hours = max(1, Int((m / 60).rounded()))
        let s: (vi: String, en: String)
        if m < 60 && fiveMin < 60 { s = span(fiveMin, "phút", "minute") }
        else if m < 1440 && hours < 24 { s = span(hours, "giờ", "hour") }
        else { s = span(max(1, Int((m / 1440).rounded())), "ngày", "day") }
        return ("Host này thường xác nhận trong khoảng \(s.vi).", "This host usually confirms within about \(s.en).")
    }

    /// "12 of 20 taken" from the live fill (get_public_event_fill). Nothing when capacity is unknown or nobody booked.
    static func fillText(capacity: Int?, booked: Int?) -> (vi: String, en: String)? {
        guard let cap = capacity, cap > 0, let b = booked, b > 0 else { return nil }
        let n = min(b, cap)
        return ("Đã có \(n)/\(cap) chỗ", "\(n) of \(cap) taken")
    }

    struct Candidate: Equatable {
        let key: String
        let status: String
        let startsAt: Date?
    }

    static let savedRowMax = 5
    static let savedRowWithinDays = 30

    /// Home "Saved, coming up": saved events that are live and start after now, within 30 days, soonest first, at most 5.
    static func savedComingUp(_ events: [Candidate], now: Date, maxItems: Int = savedRowMax, withinDays: Int = savedRowWithinDays) -> [Candidate] {
        let end = now.addingTimeInterval(TimeInterval(withinDays) * 86_400)
        return Array(events
            .filter { e in e.status == "live" && e.startsAt.map { $0 > now && $0 <= end } == true }
            .enumerated()
            .sorted { ($0.element.startsAt!, $0.offset) < ($1.element.startsAt!, $1.offset) }
            .map(\.element)
            .prefix(maxItems))
    }

    /// Ended page "Next from this host": the host's other live events still ahead, soonest first, at most 3.
    static func nextFromHost(_ rows: [Candidate], now: Date, excluding key: String?, max: Int = 3) -> [Candidate] {
        Array(rows
            .filter { r in r.status == "live" && r.key != key && r.startsAt.map { $0 > now } == true }
            .enumerated()
            .sorted { ($0.element.startsAt!, $0.offset) < ($1.element.startsAt!, $1.offset) }
            .map(\.element)
            .prefix(max))
    }

    /// Checked in at the door: the booking became "attended", or one of its named tickets was scanned (migration 151).
    static func isCheckedIn(_ booking: Booking?, attendees: [BookingAttendee] = []) -> Bool {
        guard let booking else { return false }
        return booking.status == "attended" || attendees.contains { $0.bookingId == booking.id && $0.checkedInAt != nil }
    }

    /// How long after approval a host's dashboard still celebrates a newly live event (the notification path has no limit).
    static let liveCelebrationDays = 7

    /// A host's own event that banbe approved recently and that hasn't happened yet.
    static func isNewlyLive(status: String, reviewedAt: Date?, startsAt: Date?, now: Date) -> Bool {
        guard status == "live", let reviewedAt else { return false }
        guard now.timeIntervalSince(reviewedAt) <= TimeInterval(liveCelebrationDays) * 86_400 else { return false }
        return startsAt.map { $0 > now } ?? true
    }

    /// Referral attribution only for an account created in the last 24 hours (web redeems right after sign-up only).
    static func isFreshAccount(createdAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(createdAt) >= 0 && now.timeIntervalSince(createdAt) < 24 * 3600
    }
}

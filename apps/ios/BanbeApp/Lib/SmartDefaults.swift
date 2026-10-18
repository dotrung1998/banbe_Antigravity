import Foundation

// Smart defaults (note 48, principle 1 "decision fatigue"): pure functions
// that pick the most likely value for a form field so people scan and
// adjust instead of filling from scratch. Rules:
// - never default consent, and never default money the person didn't choose
//   (a host's own last price is theirs; a stock price is not),
// - every default is visible and editable before anything is submitted.

@MainActor
enum SmartDefaults {

    // MARK: Refund accounts

    /// Most-used Vietnamese banks, as quick picks above the free-text field.
    /// Short names as printed on the banks' own apps.
    static let commonBanks: [String] = [
        "Vietcombank", "Techcombank", "MB Bank", "BIDV", "VietinBank",
        "ACB", "VPBank", "TPBank", "Agribank", "Sacombank",
    ]

    enum RefundAccountGap: Equatable { case bank, account, holder, confirm }

    /// First missing piece of the refund-account form, in on-screen order;
    /// nil when it can be saved.
    static func refundAccountGap(bank: String, account: String, holder: String,
                                 confirmed: Bool) -> RefundAccountGap? {
        if bank.trimmingCharacters(in: .whitespaces).isEmpty { return .bank }
        if account.trimmingCharacters(in: .whitespaces).isEmpty { return .account }
        if holder.trimmingCharacters(in: .whitespaces).isEmpty { return .holder }
        if !confirmed { return .confirm }
        return nil
    }
}

// MARK: Reserve

enum AttendeeGap: Equatable {
    case name(ticket: Int)
    case dob(ticket: Int)
    case email(ticket: Int)
}

@MainActor
extension SmartDefaults {
    /// First incomplete attendee field (ticket numbers are 1-based), using
    /// the same rule as `AttendeeDraft.isComplete`.
    static func attendeeGap(_ drafts: [AttendeeDraft]) -> AttendeeGap? {
        for (i, d) in drafts.enumerated() {
            if d.name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { return .name(ticket: i + 1) }
            if d.dob == nil && !d.useProfileDOB { return .dob(ticket: i + 1) }
            if !d.emailIsValid { return .email(ticket: i + 1) }
        }
        return nil
    }
}

// MARK: Create event

/// The host's most recent event, reduced to what a new draft may reuse.
/// Location is deliberately excluded: a new event's address must be
/// re-confirmed through search (createLocConfirmed), never inherited.
struct LastEventSnapshot: Equatable {
    let name: String
    /// "yyyy-MM-dd" in Vietnam time.
    let eventDate: String?
    /// "HH:mm" or "HH:mm:ss" in Vietnam time.
    let eventTime: String?
    let priceVnd: Int?
    let capacity: Int?
    let catKey: String?
}

struct EventDraftDefaults: Equatable {
    /// Midnight (Vietnam) of the suggested day.
    let date: Date
    /// A Date whose Vietnam wall clock is the suggested time.
    let time: Date
    /// nil = leave the price empty (never invent a price for a first event).
    let price: String?
    /// 0 = left empty: the host always sets capacity themselves.
    let seats: Int
    let categories: [String]
    /// Name of the event the values came from; nil for first-event defaults.
    let sourceName: String?
}

@MainActor
extension SmartDefaults {
    static let firstEventTime = "19:00:00"
    /// Saturday in Calendar's 1 = Sunday numbering.
    static let saturday = 7
    static let seatRange = 1...500
    /// Quick-pick prices (VND). "Free" is 0.
    static let priceQuickPicks: [Int] = [0, 200_000, 300_000, 500_000]

    static var vnCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppState.vietnamTimeZone
        return cal
    }

    /// Next date (Vietnam midnight) falling on `weekday`, at least
    /// `minDaysAhead` days after `now` — far enough out to promote.
    static func nextWeekday(_ weekday: Int, after now: Date, minDaysAhead: Int = 2) -> Date {
        let cal = vnCalendar
        let start = cal.date(byAdding: .day, value: minDaysAhead, to: cal.startOfDay(for: now))!
        let current = cal.component(.weekday, from: start)
        let delta = (weekday - current + 7) % 7
        return cal.date(byAdding: .day, value: delta, to: start)!
    }

    static func timeOfDay(_ raw: String) -> Date? {
        let normalized = raw.count == 5 ? raw + ":00" : raw
        return AppState.vnTimeFormatter.date(from: normalized)
    }

    /// Defaults for a brand-new event draft. A returning host gets their own
    /// last event's weekday, time, price and category; a first-time host gets
    /// next Saturday 19:00 and no price. Seats are never pre-filled (0): the
    /// host always sets capacity themselves (note 48 follow-up).
    static func eventDraftDefaults(last: LastEventSnapshot?, now: Date = Date()) -> EventDraftDefaults {
        let fallbackTime = timeOfDay(firstEventTime)!
        guard let last else {
            return EventDraftDefaults(date: nextWeekday(saturday, after: now), time: fallbackTime,
                                      price: nil, seats: 0, categories: [], sourceName: nil)
        }
        let weekday = last.eventDate
            .flatMap { AppState.vnDateFormatter.date(from: $0) }
            .map { vnCalendar.component(.weekday, from: $0) } ?? saturday
        return EventDraftDefaults(
            date: nextWeekday(weekday, after: now),
            time: last.eventTime.flatMap(timeOfDay) ?? fallbackTime,
            price: last.priceVnd.map(String.init),
            seats: 0,
            categories: last.catKey.map { [$0] } ?? [],
            sourceName: last.name
        )
    }

    /// Date quick picks for the date sheet: "This Sat", "Next Sat", "Fri".
    static func dateQuickPicks(now: Date = Date()) -> [(label: (vi: String, en: String), date: Date)] {
        let cal = vnCalendar
        let thisSat = nextWeekday(saturday, after: now, minDaysAhead: 0)
        let nextSat = cal.date(byAdding: .day, value: 7, to: thisSat)!
        let fri = nextWeekday(6, after: now, minDaysAhead: 0)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        return [
            (("Ngày mai", "Tomorrow"), tomorrow),
            (("Thứ Sáu này", "This Fri"), fri),
            (("Thứ Bảy này", "This Sat"), thisSat),
            (("Thứ Bảy tới", "Next Sat"), nextSat),
        ]
    }

    static let timeQuickPicks = ["18:00", "18:30", "19:00", "19:30", "20:00"]

    /// Contrast hint (principle 6, honest form): the middle half of prices of
    /// similar live events, so a host never prices in a vacuum. nil when
    /// there are too few samples to mean anything.
    static func similarPriceRange(_ prices: [Int], minSamples: Int = 5) -> ClosedRange<Int>? {
        let paid = prices.filter { $0 > 0 }.sorted()
        guard paid.count >= minSamples else { return nil }
        let lo = paid[paid.count / 4]
        let hi = paid[(paid.count * 3) / 4]
        return lo...max(lo, hi)
    }
}

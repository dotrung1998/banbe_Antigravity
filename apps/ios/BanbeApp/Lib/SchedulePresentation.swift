import Foundation

// banbe Schedule — pure mapping from real app state to the in-app agenda.
// Tested in BanbeAppTests/SchedulePresentationTests.swift. Note 44.
//
// Sources, highest priority first (one row per event; the strongest wins):
//   1. booked     — booking status pending/confirmed/attended AND payment
//                   confirmed (the same rule as AppState.isGoing).
//   2. awaiting   — active booking whose payment is pending host verification.
//   3. holding    — active booking still inside its seat-hold window. An
//                   EXPIRED hold is not a plan and is dropped.
//   4. hosting    — the account's own organizer's live event.
//   5. added      — the person put it on their banbe Schedule themselves
//                   (device-local, InAppCalendarStore).
// Never included: cancelled events, cancelled bookings, expired holds, events
// with no start time (counted separately so nothing silently disappears).
// Saved/favorited events are NOT a source — "saved" means bookmarked, not
// "I plan to go".
//
// Time honesty: events carry NO end time today (note 38). An item's `end` is
// optional; "overlap" is only claimed when both items have a real end.
// Otherwise the only statement made is "starts within 2 hours of a plan".

enum ScheduleSource: Int, Comparable, CaseIterable {
    case booked = 0, awaiting, holding, hosting, added
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    func label(_ T: (String, String) -> String) -> String {
        switch self {
        case .booked: return T("Đã đặt chỗ", "Booked")
        case .awaiting: return T("Chờ host xác nhận", "Awaiting host confirmation")
        case .holding: return T("Đang giữ chỗ", "Seat on hold")
        case .hosting: return T("Bạn tổ chức", "You're hosting")
        case .added: return T("Bạn đã thêm", "Added by you")
        }
    }

    var symbol: String {
        switch self {
        case .booked: return "checkmark.seal"
        case .awaiting: return "hourglass"
        case .holding: return "timer"
        case .hosting: return "person.2"
        case .added: return "bookmark"
        }
    }
}

/// What the schedule needs about one event, already normalized.
struct ScheduleEventInfo: Equatable {
    let key: String
    let title: String
    let start: Date?
    /// Always nil for today's events (no end time in the schema).
    var end: Date? = nil
    /// The event's own zone (VN / US state); nil = unknown.
    var timeZone: TimeZone? = nil
    var location: String = ""
    var cancelled = false
    var ended = false
    var inviteOnly = false
    var soldOut = false
}

/// The booking fields that decide schedule membership.
struct ScheduleBookingInput: Equatable {
    let eventKey: String
    let status: String
    /// PaymentPhase raw value: holding | pending_verification | confirmed | cancelled | …
    let paymentState: String
    let holdExpiresAt: Date?
    /// A ticket this account bought as a GIFT for someone else — the
    /// recipient's plan, not the gifter's.
    var giftedAway = false
}

struct ScheduleItem: Identifiable, Equatable {
    var id: String { event.key }
    let event: ScheduleEventInfo
    let source: ScheduleSource
    /// Every source that put this event here (strongest first).
    let sources: [ScheduleSource]
    var start: Date { event.start ?? .distantPast }
}

enum ScheduleMode: String, CaseIterable, Equatable {
    case mine, discover
}

/// How a Discover event sits next to the person's own plans.
enum ScheduleProximity: Equatable {
    case none
    /// Both items have real end times and their intervals intersect.
    case overlaps(count: Int)
    /// No end times to compare: starts within `nearWindow` of `count` plans.
    case startsNear(count: Int)

    var count: Int {
        switch self {
        case .none: return 0
        case .overlaps(let n), .startsNear(let n): return n
        }
    }
}

enum SchedulePresentation {
    static let nearWindow: TimeInterval = 2 * 3600

    // MARK: sources

    static func source(for b: ScheduleBookingInput, now: Date) -> ScheduleSource? {
        guard !b.giftedAway, ["pending", "confirmed", "attended"].contains(b.status) else { return nil }
        switch b.paymentState {
        case "confirmed": return .booked
        case "pending_verification": return .awaiting
        case "holding":
            guard let exp = b.holdExpiresAt, exp > now else { return nil }
            return .holding
        default: return nil
        }
    }

    struct MyScheduleResult: Equatable {
        let items: [ScheduleItem]
        /// Plans whose event has no start time yet (shown as a note, not dropped silently).
        let undatedCount: Int
    }

    static func mySchedule(bookings: [ScheduleBookingInput], hostedKeys: [String], addedKeys: [String],
                           events: [String: ScheduleEventInfo], now: Date) -> MyScheduleResult {
        var byKey: [String: [ScheduleSource]] = [:]
        func add(_ key: String, _ s: ScheduleSource) {
            var list = byKey[key, default: []]
            if !list.contains(s) { list.append(s) }
            byKey[key] = list
        }
        for b in bookings { if let s = source(for: b, now: now) { add(b.eventKey, s) } }
        for k in hostedKeys { add(k, .hosting) }
        for k in addedKeys { add(k, .added) }

        var items: [ScheduleItem] = []
        var undated = 0
        for (key, sources) in byKey {
            // Past (ended) plans stay on their own day as history; only a
            // cancelled event leaves the agenda.
            guard let e = events[key], !e.cancelled else { continue }
            let sorted = sources.sorted()
            guard e.start != nil else { undated += 1; continue }
            items.append(ScheduleItem(event: e, source: sorted[0], sources: sorted))
        }
        items.sort { a, b in a.start != b.start ? a.start < b.start : a.id < b.id }
        return MyScheduleResult(items: items, undatedCount: undated)
    }

    /// Discover: upcoming, reservable, public events not already in My schedule.
    static func discover(events: [ScheduleEventInfo], excluding mine: Set<String>, now: Date) -> [ScheduleEventInfo] {
        events.filter { e in
            guard let s = e.start, s > now else { return false }
            return !e.cancelled && !e.ended && !e.inviteOnly && !e.soldOut && !mine.contains(e.key)
        }
        .sorted { a, b in (a.start ?? .distantFuture, a.key) < (b.start ?? .distantFuture, b.key) }
    }

    /// Can this event be put on the banbe Schedule by hand?
    static func canAdd(_ e: ScheduleEventInfo, now: Date) -> Bool {
        guard let s = e.start else { return false }
        return !e.cancelled && !e.ended && s > now
    }

    // MARK: days

    /// True when the item happens (at least partly) on `day`'s calendar day.
    static func occurs(_ e: ScheduleEventInfo, on day: Date, calendar: Calendar) -> Bool {
        guard let start = e.start else { return false }
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        if let end = e.end, end > start {
            return start < dayEnd && end > dayStart
        }
        return start >= dayStart && start < dayEnd
    }

    static func items(_ items: [ScheduleItem], on day: Date, calendar: Calendar) -> [ScheduleItem] {
        items.filter { occurs($0.event, on: day, calendar: calendar) }
    }

    static func events(_ events: [ScheduleEventInfo], on day: Date, calendar: Calendar) -> [ScheduleEventInfo] {
        events.filter { occurs($0, on: day, calendar: calendar) }
    }

    /// The 7 days of the week containing `date`, honoring the calendar's
    /// (locale's) first weekday.
    static func week(containing date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// Days in `week` that have at least one item — for the strip's dots.
    static func busyDays(_ week: [Date], items: [ScheduleItem], calendar: Calendar) -> Set<Date> {
        Set(week.filter { d in items.contains { occurs($0.event, on: d, calendar: calendar) } })
    }

    // MARK: month view

    struct MonthGridDay: Identifiable, Equatable {
        let date: Date          // start of that calendar day
        let inMonth: Bool
        var id: Date { date }
    }

    /// First instant of `date`'s month in `calendar`.
    static func monthStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    static func addMonths(_ n: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: n, to: monthStart(date, calendar: calendar)) ?? date
    }

    /// Whole weeks (rows of 7, honoring the calendar's first weekday) covering
    /// the month of `date`; days outside the month are flagged, not dropped,
    /// so every row is a complete week the person can pick.
    static func monthGrid(containing date: Date, calendar: Calendar) -> [[MonthGridDay]] {
        let first = monthStart(date, calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: first),
              let last = calendar.date(byAdding: .day, value: range.count - 1, to: first) else { return [] }
        var rows: [[MonthGridDay]] = []
        var cursor = week(containing: first, calendar: calendar)[0]
        let lastWeekStart = week(containing: last, calendar: calendar)[0]
        let month = calendar.component(.month, from: first)
        while cursor <= lastWeekStart {
            let days = week(containing: cursor, calendar: calendar).map {
                MonthGridDay(date: $0, inMonth: calendar.component(.month, from: $0) == month)
            }
            rows.append(days)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return rows
    }

    /// How many of `events` happen on each day of `grid` (start-of-day keyed).
    static func dayCounts(_ events: [ScheduleEventInfo], grid: [[MonthGridDay]], calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for day in grid.joined() {
            let n = events.filter { occurs($0, on: day.date, calendar: calendar) }.count
            if n > 0 { counts[day.date] = n }
        }
        return counts
    }

    /// Events of `date`'s month grouped by day, in time order — the month's agenda.
    static func monthAgenda(_ events: [ScheduleEventInfo], month date: Date, calendar: Calendar) -> [(day: Date, events: [ScheduleEventInfo])] {
        let grid = monthGrid(containing: date, calendar: calendar).joined().filter(\.inMonth)
        return grid.compactMap { d in
            let list = events.filter { occurs($0, on: d.date, calendar: calendar) }
                .sorted { ($0.start ?? .distantFuture, $0.key) < ($1.start ?? .distantFuture, $1.key) }
            return list.isEmpty ? nil : (d.date, list)
        }
    }

    // MARK: proximity (banbe data only)

    static func proximity(of candidate: ScheduleEventInfo, to plans: [ScheduleItem]) -> ScheduleProximity {
        guard let cs = candidate.start else { return .none }
        var overlaps = 0, near = 0
        for p in plans where p.event.key != candidate.key {
            guard let ps = p.event.start else { continue }
            if let ce = candidate.end, let pe = p.event.end, ce > cs, pe > ps {
                if cs < pe && ps < ce { overlaps += 1 }
            } else if abs(cs.timeIntervalSince(ps)) < nearWindow {
                near += 1
            }
        }
        if overlaps > 0 { return .overlaps(count: overlaps) }
        if near > 0 { return .startsNear(count: near) }
        return .none
    }

    static func proximityText(_ p: ScheduleProximity, T: (String, String) -> String) -> String? {
        switch p {
        case .none: return nil
        case .overlaps(let n):
            return T("Trùng với \(n) kế hoạch", "Overlaps with \(n) plan\(n == 1 ? "" : "s")")
        case .startsNear(let n):
            return T("Bắt đầu cách \(n) kế hoạch dưới 2 giờ", "Starts within 2 hours of \(n) plan\(n == 1 ? "" : "s")")
        }
    }

    // MARK: formatting

    /// "19:30" in `timeZone` (the agenda's zone), 24h for VI, locale-short for EN.
    static func time(_ d: Date, timeZone: TimeZone, vi: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: vi ? "vi_VN" : "en_US")
        f.timeZone = timeZone
        f.dateFormat = vi ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }

    /// When the event's own zone differs from the agenda's, its local time —
    /// e.g. "19:00 at the venue" — so a traveller is never misled.
    static func venueTimeNote(_ e: ScheduleEventInfo, agendaZone: TimeZone, vi: Bool) -> String? {
        guard let s = e.start, let tz = e.timeZone,
              tz.secondsFromGMT(for: s) != agendaZone.secondsFromGMT(for: s) else { return nil }
        let t = time(s, timeZone: tz, vi: vi)
        return vi ? "\(t) giờ tại nơi tổ chức" : "\(t) at the venue"
    }

    static func monthTitle(_ d: Date, calendar: Calendar, vi: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: vi ? "vi_VN" : "en_US")
        f.timeZone = calendar.timeZone
        f.dateFormat = vi ? "'Tháng' M, yyyy" : "LLLL yyyy"
        return f.string(from: d)
    }

    static func dayTitle(_ d: Date, calendar: Calendar, vi: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: vi ? "vi_VN" : "en_US")
        f.timeZone = calendar.timeZone
        f.dateFormat = vi ? "EEEE, d 'tháng' M" : "EEEE, MMMM d"
        return f.string(from: d)
    }

    /// Analytics-safe relative-day bucket for a selected date.
    static func dayBucket(_ d: Date, today: Date, calendar: Calendar) -> String {
        let a = calendar.startOfDay(for: today), b = calendar.startOfDay(for: d)
        let days = calendar.dateComponents([.day], from: a, to: b).day ?? 0
        switch days {
        case ..<0: return "past"
        case 0: return "today"
        case 1...7: return "next7"
        default: return "later"
        }
    }
}

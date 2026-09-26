import Foundation

/// Shared countdown formatting — the Swift counterpart of src/lib/countdown.js.
/// One implementation so a PHASE 1 hold and a PHASE 2 SLA read identically
/// whether they're on Home, the ticket screen, or the organizer's queue.
enum Countdown {
    /// seconds -> "12:04" (or "1:02:04" past an hour). Never negative.
    static func format(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Seconds remaining until `date`, floored at 0.
    static func secondsUntil(_ date: Date?, now: Date = Date()) -> TimeInterval {
        guard let date else { return 0 }
        return max(0, date.timeIntervalSince(now))
    }

    /// Out of a list of bookings in a given phase, the one whose deadline is
    /// soonest AND still in the future — a lapsed deadline is excluded
    /// rather than sorted last, since it is moments from being swept to
    /// 'expired' by the cron job and showing a banner for it would be
    /// showing a hold that is effectively already gone.
    static func pickSoonest(_ bookings: [PayableBooking], phase: PaymentPhase,
                            deadline: (PayableBooking) -> Date?) -> PayableBooking? {
        bookings
            .filter { $0.paymentState == phase && secondsUntil(deadline($0)) > 0 }
            .sorted { (deadline($0) ?? .distantFuture) < (deadline($1) ?? .distantFuture) }
            .first
    }

    private static func hoursSince(_ date: Date?, now: Date) -> Int? {
        guard let date else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 3600))
    }

    // 2026-09-25 fix pass — Swift counterpart of countdown.js's own
    // `liveDateOverrides`/`formatVnEventDate`/`relDaysFromNow`: root cause
    // of "wrong displayed months" was that `when`/`where`/`meta`/`until`/
    // `startDate` came ONLY from the bundled `events.json` catalogue
    // (generated once from the web static catalogue's own hardcoded
    // July-2026 strings), never from the real `events.starts_at` row this
    // app already fetches for cancelled/ended status. See countdown.js's
    // own doc comment for the full writeup — this mirrors it exactly.
    private static let vnWeekdayShort = ["CN", "Th 2", "Th 3", "Th 4", "Th 5", "Th 6", "Th 7"]
    private static let vnWeekdayLong = ["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    private struct VnEventDate { let weekdayShort: String, dayMonth: String, dayLong: String, time: String }

    private static func formatVnEventDate(_ date: Date) -> VnEventDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.weekday, .day, .month, .hour, .minute], from: date)
        // Foundation's `.weekday` is 1-based starting Sunday — matches this
        // array's own indexing (index 0 = Sunday) directly, no offset math.
        let dow = (c.weekday ?? 1) - 1
        let day = c.day ?? 1, month = c.month ?? 1, hour = c.hour ?? 0, minute = c.minute ?? 0
        return VnEventDate(
            weekdayShort: vnWeekdayShort[dow],
            dayMonth: String(format: "%02d.%02d", day, month),
            dayLong: "\(vnWeekdayLong[dow]), \(day) tháng \(month)",
            time: String(format: "%02d:%02d", hour, minute)
        )
    }

    /// Whole-day difference at local midnight — same semantics the web
    /// catalogue's own (now-bypassed) `relDays()` used, against the REAL
    /// current date instead of a hardcoded one.
    private static func relDaysFromNow(_ target: Date, now: Date) -> Int {
        let cal = Calendar.current
        let startOfTarget = cal.startOfDay(for: target)
        let startOfNow = cal.startOfDay(for: now)
        return cal.dateComponents([.day], from: startOfNow, to: startOfTarget).day ?? 0
    }

    /// Replaces the trailing ` ▪︎ `-joined segment(s) of a static catalogue
    /// string with live values, keeping the area/km prefix (no live
    /// equivalent, not the bug here) untouched.
    private static func replaceTrailingSegments(_ str: String, count: Int, with replacements: [String]) -> String {
        var parts = str.components(separatedBy: " ▪︎ ")
        guard parts.count >= count else { return str }
        parts.replaceSubrange((parts.count - count)..., with: replacements)
        return parts.joined(separator: " ▪︎ ")
    }

    // Not `private` — its fields are read back by `CatalogEvent.applyingLiveStatus`.
    struct DateOverrides {
        var startDate: Date?
        var when: String?
        var until: Int?
        var untilLabel: String?
        var meta: String?
        var where_: String?
    }

    private static func liveDateOverrides(_ live: LiveEventStatus?, staticEvent: CatalogEvent, now: Date) -> DateOverrides {
        guard let startsAt = live?.startsAt else { return DateOverrides() }
        let d = formatVnEventDate(startsAt)
        let until = relDaysFromNow(startsAt, now: now)
        return DateOverrides(
            startDate: startsAt,
            when: "\(d.weekdayShort), \(d.dayMonth) ▪︎ \(d.time)",
            until: until,
            untilLabel: EventLabels.until(until),
            meta: replaceTrailingSegments(staticEvent.meta, count: 1, with: ["\(d.weekdayShort), \(d.time)"]),
            where_: replaceTrailingSegments(staticEvent.where, count: 2, with: [d.dayLong, d.time])
        )
    }

    /// Reconciles a real `events` row's own status against the current
    /// clock, overriding the static catalogue's hardcoded cancelled/ended
    /// flags — AND its hardcoded date/time display — with a live read. The
    /// Swift counterpart of `liveEventOverrides` in src/lib/countdown.js.
    /// See that function's comment for the full rationale; `staticEvent` is
    /// only a cosmetic fallback for the "N hours ago" text and the area/km
    /// prefix of `meta`/`where`, never for the booleans or the date itself,
    /// which always come from the live row when one exists.
    static func liveEventOverrides(
        _ live: LiveEventStatus?, staticEvent: CatalogEvent, now: Date = Date()
    ) -> (cancelled: Bool, cancelledHoursAgo: Int?, endedHoursAgo: Int?, date: DateOverrides)? {
        guard let live else { return nil }
        let date = liveDateOverrides(live, staticEvent: staticEvent, now: now)
        switch live.status {
        case "cancelled":
            return (true, hoursSince(live.cancelledAt, now: now) ?? staticEvent.cancelledHoursAgo ?? 0, nil, date)
        case "ended":
            return (false, nil, hoursSince(live.startsAt, now: now) ?? staticEvent.endedHoursAgo ?? 0, date)
        default:
            // 'live' (or 'draft'/'review', not publicly reachable) — not
            // cancelled and no sweep has marked it ended.
            return (false, nil, nil, date)
        }
    }

    /// Retention roadmap follow-up — public wrapper so a REAL (non-
    /// catalogue) event's own `when` string can be built the exact same way
    /// a catalogue event's is, without a static event to merge onto (see
    /// CatalogEvent.fromReal).
    static func whenLabel(for date: Date) -> String {
        let d = formatVnEventDate(date)
        return "\(d.weekdayShort), \(d.dayMonth) ▪︎ \(d.time)"
    }

    static func hoursAgo(_ date: Date?, now: Date = Date()) -> Int? { hoursSince(date, now: now) }

    // Retention roadmap P1 ("Cuối tuần này") — the applicable weekend
    // window, computed against Asia/Ho_Chi_Minh wall-clock time specifically
    // (the roadmap's own requirement), not the device's local zone. Exact
    // Swift counterpart of thisWeekendWindow() in src/lib/countdown.js —
    // see that function's own comment for the full rationale. ICT has no
    // DST and a fixed +07:00 offset year-round, so this is a plain
    // TimeInterval shift rather than a full Calendar/TimeZone dependency.
    private static let ictOffset: TimeInterval = 7 * 3600

    static func thisWeekendWindow(now: Date = Date()) -> (start: Date, end: Date) {
        var ictCal = Calendar(identifier: .gregorian)
        ictCal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current
        let c = ictCal.dateComponents([.year, .month, .day, .weekday], from: now)
        let dow = (c.weekday ?? 1) - 1 // 0 = Sunday, 6 = Saturday
        let daysToSat = dow == 6 ? 0 : (dow == 0 ? -1 : 6 - dow)
        var satComponents = DateComponents()
        satComponents.year = c.year; satComponents.month = c.month; satComponents.day = (c.day ?? 1) + daysToSat
        satComponents.hour = 0; satComponents.minute = 0; satComponents.second = 0
        satComponents.timeZone = ictCal.timeZone
        var sunEndComponents = satComponents
        sunEndComponents.day = (satComponents.day ?? 1) + 1
        sunEndComponents.hour = 23; sunEndComponents.minute = 59; sunEndComponents.second = 59
        let satStart = ictCal.date(from: satComponents) ?? now
        let sunEnd = ictCal.date(from: sunEndComponents) ?? now
        return (max(satStart, now), sunEnd)
    }
}

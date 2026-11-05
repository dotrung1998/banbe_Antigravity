import Foundation

// Map E+ (note 79): the day + hour window that bolds the events inside it and dims the rest. Pure, no network: the
// slider recomputes `inWindow` over the loaded rows on every step. Web twin: src/lib/mapTimeWindow.js; shared cases in
// tests/fixtures/map-time-window.json.
//
// An event belongs to a SERVICE DAY: the venue's calendar day, except that 00:00 to 03:59 still counts toward the night
// before (the same rule as Home's "Tonight"). Its time is `min`, minutes since that day's 00:00, so 01:30 after a
// Friday night is Friday 25:30 (1530). The slider runs `rangeMin` to `rangeMax` hours in the same units.
enum MapTimeWindow {
    static let rangeMin = 10          // slider start, 10:00
    static let rangeMax = 26          // slider end, 02:00 the next morning
    static let rangeStep = 1          // hours
    static let serviceDayStartMin = 4 * 60
    static let todayGraceMs = 2.0 * 3600 * 1000   // an event today stays in until two hours after it began
    static let laterFrom = 17         // default start for any day that is not today

    struct Slot: Equatable { var dayKey: String; var min: Int; var ms: Double }
    struct Window: Equatable {
        var on: Bool
        var key: String
        var days: [String]
        var from: Int
        var to: Int
        var todayKey: String
    }
    struct DayOption: Equatable { var key: String; var label: String; var sub: String; var days: [String] }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    private static func ymd(_ s: String) -> (Int, Int, Int)? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : nil
    }
    private static func ymdString(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }

    /// "yyyy-mm-dd" shifted by `n` days (calendar arithmetic, no time zone involved).
    static func addDays(_ day: String, _ n: Int) -> String {
        guard let (y, m, d) = ymd(day), let base = utc.date(from: DateComponents(year: y, month: m, day: d)),
              let shifted = utc.date(byAdding: .day, value: n, to: base) else { return day }
        let c = utc.dateComponents([.year, .month, .day], from: shifted)
        return ymdString(c.year ?? y, c.month ?? m, c.day ?? d)
    }
    /// 0 = Sunday … 6 = Saturday, of a "yyyy-mm-dd".
    static func weekdayOf(_ day: String) -> Int {
        guard let (y, m, d) = ymd(day), let base = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return 0 }
        return utc.component(.weekday, from: base) - 1
    }

    /// The slot of an instant in the venue's zone, with 00:00 to 03:59 folded into the previous day.
    static func eventSlot(ms: Double, timeZone: TimeZone) -> Slot {
        let p = EventMarket.zonedParts(Date(timeIntervalSince1970: ms / 1000), timeZone: timeZone)
        var day = ymdString(p.year, p.month, p.day)
        var min = p.hour * 60 + p.minute
        if min < serviceDayStartMin { day = addDays(day, -1); min += 1440 }
        return Slot(dayKey: day, min: min, ms: ms)
    }

    /// "19:00" for hour 19, "02:00" for hour 26.
    static func hourLabel(_ n: Int) -> String { String(format: "%02d:00", n % 24) }

    private static let wdVI = ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]
    private static let wdEN = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let wdVIShort = ["CN", "Th 2", "Th 3", "Th 4", "Th 5", "Th 6", "Th 7"]
    private static let wdENShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static func dm(_ day: String) -> String { "\(day.dropFirst(8).prefix(2)).\(day.dropFirst(5).prefix(2))" }

    /// The day menu, in order: today · tomorrow · the next weekend day (the first Saturday or Sunday after tomorrow) ·
    /// next week (Monday to Sunday of the week that starts after today) · all days. "Today" is the venue's service day,
    /// so at 01:30 it is still last night. "All days" has no days and switches the filter off.
    static func dayOptions(nowMs: Double, timeZone: TimeZone, en: Bool = false) -> [DayOption] {
        let today = eventSlot(ms: nowMs, timeZone: timeZone).dayKey
        let wd = weekdayOf(today)
        func short(_ d: String) -> String { (en ? wdENShort : wdVIShort)[weekdayOf(d)] }
        let tomorrow = addDays(today, 1)
        var weekend = addDays(today, 2)
        for k in 2...8 {
            let d = addDays(today, k)
            if weekdayOf(d) == 6 || weekdayOf(d) == 0 { weekend = d; break }
        }
        let untilMonday = (8 - wd) % 7 == 0 ? 7 : (8 - wd) % 7
        let monday = addDays(today, untilMonday)
        let week = (0..<7).map { addDays(monday, $0) }
        return [
            DayOption(key: "today", label: en ? "Today" : "Hôm nay", sub: short(today), days: [today]),
            DayOption(key: "tomorrow", label: en ? "Tomorrow" : "Mai", sub: short(tomorrow), days: [tomorrow]),
            DayOption(key: "weekend", label: (en ? wdEN : wdVI)[weekdayOf(weekend)], sub: dm(weekend), days: [weekend]),
            DayOption(key: "nextWeek", label: en ? "Next week" : "Tuần sau", sub: "\(dm(week[0]))–\(dm(week[6]))", days: week),
            DayOption(key: "all", label: en ? "All days" : "Tất cả ngày", sub: "", days: []),
        ]
    }

    /// The window a day choice starts with: today from the next full hour, other days 17:00, always to 02:00; all days is off.
    static func defaultWindow(key: String, nowMs: Double, timeZone: TimeZone) -> Window {
        let slot = eventSlot(ms: nowMs, timeZone: timeZone)
        let options = dayOptions(nowMs: nowMs, timeZone: timeZone)
        let opt = options.first { $0.key == key } ?? options[4]
        if opt.key == "all" { return Window(on: false, key: "all", days: [], from: rangeMin, to: rangeMax, todayKey: slot.dayKey) }
        let from = opt.key == "today"
            ? min(rangeMax - 1, max(rangeMin, Int((Double(slot.min) / 60).rounded(.up))))
            : laterFrom
        return Window(on: true, key: opt.key, days: opt.days, from: from, to: rangeMax, todayKey: slot.dayKey)
    }

    enum Knob { case from, to }

    /// Moves one knob to `hour` (whole hours), keeping the range at least one step wide and inside rangeMin to rangeMax.
    static func moveKnob(_ win: Window, _ which: Knob, hour: Double) -> Window {
        let h = min(rangeMax, max(rangeMin, Int((hour / Double(rangeStep)).rounded()) * rangeStep))
        var w = win
        switch which {
        case .from: w.from = min(h, win.to - rangeStep)
        case .to: w.to = max(h, win.from + rangeStep)
        }
        return w
    }

    /// Is the slot inside the window? Off = everything is. Today's events stay in until `todayGraceMs` after they began.
    static func inWindow(_ slot: Slot, _ win: Window, nowMs: Double) -> Bool {
        guard win.on else { return true }
        guard win.days.contains(slot.dayKey) else { return false }
        if slot.min < win.from * 60 || slot.min >= win.to * 60 { return false }
        if slot.dayKey == win.todayKey && slot.ms < nowMs - todayGraceMs { return false }
        return true
    }

    /// Home's date filter ("today", "tonight", "tomorrow", "weekend", anything else) as the Map's window.
    static func windowFromHomeDate(_ date: String, nowMs: Double, timeZone: TimeZone) -> Window {
        switch date {
        case "today": return defaultWindow(key: "today", nowMs: nowMs, timeZone: timeZone)
        case "tonight":
            var w = defaultWindow(key: "today", nowMs: nowMs, timeZone: timeZone); w.from = laterFrom; return w
        case "tomorrow": return defaultWindow(key: "tomorrow", nowMs: nowMs, timeZone: timeZone)
        case "weekend": return defaultWindow(key: "weekend", nowMs: nowMs, timeZone: timeZone)
        default: return defaultWindow(key: "all", nowMs: nowMs, timeZone: timeZone)
        }
    }

    /// "Hôm nay · 19:00–02:00", or "Mọi ngày" / "Any day" when off. `dayLabel` is the chosen option's label.
    static func windowSummary(_ win: Window, dayLabel: String, en: Bool = false) -> String {
        guard win.on else { return en ? "Any day" : "Mọi ngày" }
        return "\(dayLabel) · \(hourLabel(win.from))–\(hourLabel(win.to))"
    }
}

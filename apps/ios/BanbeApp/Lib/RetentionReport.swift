import Foundation

/// Admin › Retention report (migration 196, admin_retention_report). Pure presentation helpers; web twin:
/// src/lib/retentionReport.js — same vectors in RetentionReportTests / tests/unit/retentionReport.test.mjs. The server
/// already hides every group under 20 people: counts arrive as numbers or the string "<20" (shown verbatim), hidden
/// rates and medians arrive as null (shown as "—").
enum RetentionReport {
    static let rangeDays = [30, 90, 365]
    static let defaultRangeDays = 90
    static let hidden = "—"
    private static let marketOrder = ["VN", "US", "unknown"]

    /// A JSON value that is a number, a string ("<20") or null.
    enum Value: Decodable, Equatable {
        case number(Double), text(String), none
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .none }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else if let s = try? c.decode(String.self) { self = .text(s) }
            else { self = .none }
        }
        var number: Double? { if case .number(let d) = self { return d } else { return nil } }
    }

    struct Market: Decodable, Equatable {
        var market: String
        var people: Value = .none, activePeople: Value = .none, newPeople: Value = .none
        var d7Returned: Value = .none, d30Returned: Value = .none
        var d7Rate: Value = .none, d30Rate: Value = .none
        var firstAttenders: Value = .none, secondWithin60d: Value = .none, secondWithin60dRate: Value = .none
        var daysToSecondMedian: Value = .none
        enum CodingKeys: String, CodingKey {
            case market, people
            case activePeople = "active_people", newPeople = "new_people"
            case d7Returned = "d7_returned", d30Returned = "d30_returned", d7Rate = "d7_rate", d30Rate = "d30_rate"
            case firstAttenders = "first_attenders", secondWithin60d = "second_within_60d"
            case secondWithin60dRate = "second_within_60d_rate", daysToSecondMedian = "days_to_second_median"
        }
        init(market: String) { self.market = market }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            market = (try? c.decode(String.self, forKey: .market)) ?? "unknown"
            func v(_ k: CodingKeys) -> Value { (try? c.decodeIfPresent(Value.self, forKey: k)) ?? Value.none }
            people = v(.people); activePeople = v(.activePeople); newPeople = v(.newPeople)
            d7Returned = v(.d7Returned); d30Returned = v(.d30Returned); d7Rate = v(.d7Rate); d30Rate = v(.d30Rate)
            firstAttenders = v(.firstAttenders); secondWithin60d = v(.secondWithin60d)
            secondWithin60dRate = v(.secondWithin60dRate); daysToSecondMedian = v(.daysToSecondMedian)
        }
    }

    struct NotificationKind: Decodable, Equatable, Identifiable {
        var kind: String
        var sent: Value = .none, read: Value = .none, readMinutesMedian: Value = .none
        var id: String { kind }
        enum CodingKeys: String, CodingKey { case kind, sent, read, readMinutesMedian = "read_minutes_median" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = (try? c.decode(String.self, forKey: .kind)) ?? ""
            sent = (try? c.decodeIfPresent(Value.self, forKey: .sent)) ?? Value.none
            read = (try? c.decodeIfPresent(Value.self, forKey: .read)) ?? Value.none
            readMinutesMedian = (try? c.decodeIfPresent(Value.self, forKey: .readMinutesMedian)) ?? Value.none
        }
    }

    struct Reply: Decodable {
        var success: Bool?
        var error: String?
        var from: String?
        var to: String?
        var markets: [Market]?
        var notifications: [NotificationKind]?
        var notificationKindsHidden: Int?
        enum CodingKeys: String, CodingKey {
            case success, error, from, to, markets, notifications
            case notificationKindsHidden = "notification_kinds_hidden"
        }
    }

    struct Row: Equatable { let key: String, vi: String, en: String, value: String }

    // MARK: formatting

    /// A count: a number (grouped, "1,234"), "<20" verbatim, anything else "—".
    static func count(_ v: Value) -> String {
        switch v {
        case .text(let s) where !s.trimmingCharacters(in: .whitespaces).isEmpty: return s
        case .number(let d) where d.isFinite:
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = Locale(identifier: "en_US")
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: d.rounded())) ?? hidden
        default: return hidden
        }
    }

    /// One decimal at most ("4", "4.6"); used for percentages and medians.
    private static func oneDecimal(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// A 0..1 share as a percentage ("12.5%", "40%"); hidden "—".
    static func rate(_ v: Value) -> String {
        guard let d = v.number, d.isFinite else { return hidden }
        return oneDecimal(d * 100) + "%"
    }

    /// A median (days or minutes); hidden "—".
    static func median(_ v: Value) -> String {
        guard let d = v.number, d.isFinite else { return hidden }
        return oneDecimal(d)
    }

    /// "count · rate" for the returned rows; just the count when the rate is hidden.
    static func countRate(_ c: Value, _ r: Value) -> String {
        r.number?.isFinite == true ? "\(count(c)) · \(rate(r))" : count(c)
    }

    // MARK: structure

    /// The last `days` days up to and including today (device-local dates), as the RPC's p_from / p_to.
    static func range(days: Int, now: Date = Date(), calendar: Calendar = .current) -> (from: String, to: String) {
        let n = rangeDays.contains(days) ? days : defaultRangeDays
        let to = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(n - 1), to: to) ?? to
        return (ymd(from, calendar), ymd(to, calendar))
    }

    private static func ymd(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// VN, US, unknown — always all three, in that order (a market missing from the answer shows as hidden).
    static func orderedMarkets(_ markets: [Market]?) -> [Market] {
        marketOrder.map { m in markets?.first(where: { $0.market == m }) ?? Market(market: m) }
    }

    static func rows(_ m: Market) -> [Row] {
        [
            Row(key: "people", vi: "Người dùng", en: "People", value: count(m.people)),
            Row(key: "active", vi: "Hoạt động trong kỳ", en: "Active in period", value: count(m.activePeople)),
            Row(key: "new", vi: "Mới trong kỳ", en: "New in period", value: count(m.newPeople)),
            Row(key: "d7", vi: "Quay lại tuần 2 (D7)", en: "Back in week 2 (D7)", value: countRate(m.d7Returned, m.d7Rate)),
            Row(key: "d30", vi: "Quay lại tuần 5 (D30)", en: "Back in week 5 (D30)", value: countRate(m.d30Returned, m.d30Rate)),
            Row(key: "first", vi: "Tham dự lần đầu", en: "First attendance", value: count(m.firstAttenders)),
            Row(key: "second", vi: "Tham dự lần 2 trong 60 ngày", en: "Second within 60 days",
                value: countRate(m.secondWithin60d, m.secondWithin60dRate)),
            Row(key: "days", vi: "Số ngày tới lần 2 (trung vị)", en: "Median days to second", value: median(m.daysToSecondMedian)),
        ]
    }

    static func marketLabel(_ market: String) -> (vi: String, en: String) {
        switch market {
        case "VN": return ("Việt Nam", "Vietnam")
        case "US": return ("Hoa Kỳ", "United States")
        default: return ("Chưa rõ", "Unknown")
        }
    }
}

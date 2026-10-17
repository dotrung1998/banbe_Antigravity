import Foundation

// Metrics & Reports dashboard — pure mapping from the canonical
// `get_account_kpis` payload (migration 097) to what the dashboard shows.
// No network, no SwiftUI: everything here is unit-tested
// (BanbeAppTests/ReportsPresentationTests.swift).
//
// Honesty rules (read before adding anything):
// - Only numbers the RPC returned are shown. There is no previous-period
//   query, so there are NO deltas/growth badges anywhere.
// - A metric without `series` is a point-in-time total and is never charted.
// - Derived stats (peak day, active days, daily average) come only from the
//   returned `series`, and are hidden when the series has no activity.

enum ReportRole: String, Equatable {
    case personal, host, admin
    init(scope: String?) { self = ReportRole(rawValue: scope ?? "") ?? .personal }

    func label(_ T: (String, String) -> String) -> String {
        switch self {
        case .personal: return T("Cá nhân", "Personal")
        case .host: return T("Tổ chức", "Host")
        case .admin: return T("Quản trị", "Admin")
        }
    }
}

enum ReportValueKind: Equatable {
    case count, money, days

    init(unit: String) {
        switch unit {
        case "vnd": self = .money
        case "days": self = .days
        default: self = .count
        }
    }
}

struct ReportSeriesPoint: Identifiable, Equatable {
    var id: String { dayKey }
    /// The server's calendar-day bucket ("yyyy-MM-dd"), kept verbatim.
    let dayKey: String
    /// Midnight UTC of that calendar day — only used for ordering/axis.
    let date: Date
    let value: Double
}

struct ReportSeriesSummary: Equatable {
    let total: Double
    let peak: ReportSeriesPoint?
    let activeDays: Int
    let dayCount: Int
    var hasActivity: Bool { activeDays > 0 }
    var dailyAverage: Double { dayCount > 0 ? total / Double(dayCount) : 0 }
}

struct ReportMetricPresentation: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let title: String
    let kind: ReportValueKind
    /// nil when the server sent a non-numeric value.
    let number: Double?
    let valueText: String
    /// Full spoken form for VoiceOver (no abbreviations).
    let accessibilityValue: String
    let series: [ReportSeriesPoint]
    let summary: ReportSeriesSummary?
    let rowCount: Int
    var isTimeSeries: Bool { !series.isEmpty }
}

struct ReportAttentionItem: Identifiable, Equatable {
    /// overdue = past a real deadline; urgent = an open conflict; pending = a queue.
    enum Severity: Equatable { case overdue, urgent, pending }
    var id: String { key }
    /// The metric the card opens.
    let key: String
    let severity: Severity
    let title: String
    let valueText: String
    let message: String
    let symbol: String
}

/// Part of a whole where numerator and denominator count the SAME population
/// from the same payload (never two differently-scoped metrics).
struct ReportShareInsight: Equatable {
    let key: String
    let title: String
    let numerator: Int
    let denominator: Int
    let caption: String
    var fraction: Double { denominator > 0 ? Double(numerator) / Double(denominator) : 0 }
}

struct ReportDistributionSegment: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int
}

/// Real grouped counts read straight off the returned rows/values.
struct ReportDistributionInsight: Equatable {
    let key: String
    let title: String
    let segments: [ReportDistributionSegment]
    var total: Int { segments.reduce(0) { $0 + $1.count } }
}

enum ReportInsight: Identifiable, Equatable {
    case share(ReportShareInsight)
    case distribution(ReportDistributionInsight)

    var id: String {
        switch self {
        case .share(let s): return "share.\(s.key)"
        case .distribution(let d): return "dist.\(d.key).\(d.title)"
        }
    }
    /// The metric whose details the insight opens.
    var metricKey: String {
        switch self {
        case .share(let s): return s.key
        case .distribution(let d): return d.key
        }
    }
}

struct ReportsDashboard: Equatable {
    let role: ReportRole
    let primary: ReportMetricPresentation?
    let overview: [ReportMetricPresentation]
    let attention: [ReportAttentionItem]
    let trends: [ReportMetricPresentation]
    /// Every metric in server order — the details list and exports.
    let all: [ReportMetricPresentation]
    /// Admin leads with its backlog; the other roles lead with the primary insight.
    let attentionFirst: Bool
    /// Breakdowns the payload truthfully supports (may be empty).
    var insights: [ReportInsight] = []
    var isEmpty: Bool { all.isEmpty }
}

struct ReportRowField: Equatable {
    let label: String
    let value: String
}

struct ReportRowPresentation: Identifiable, Equatable {
    let id: Int
    let title: String
    let fields: [ReportRowField]
    let flagged: Bool
}

enum ReportsPresentation {

    // MARK: role layout

    struct Layout {
        let primary: String?
        let overview: [String]
        let trends: [String]
        let attentionFirst: Bool
    }

    static func layout(for role: ReportRole) -> Layout {
        switch role {
        case .personal:
            return Layout(primary: "confirmed_bookings",
                          overview: ["upcoming_events", "attended_events", "saved_events", "outstanding_refunds"],
                          trends: ["attended_events"], attentionFirst: false)
        case .host:
            return Layout(primary: "confirmed_seats",
                          overview: ["confirmed_payment_amount", "upcoming_events", "published_events", "check_ins",
                                     "refunds_owed", "refunds_overdue"],
                          trends: ["confirmed_payment_amount", "check_ins"], attentionFirst: false)
        case .admin:
            return Layout(primary: "platform_new_bookings",
                          overview: ["pending_event_reviews", "unresolved_disputes", "backlog_avg_age_days",
                                     "platform_new_events"],
                          trends: ["platform_new_events"], attentionFirst: true)
        }
    }

    // MARK: dashboard

    static func dashboard(_ report: AccountKpiReport, fallbackScope: String,
                          T: (String, String) -> String) -> ReportsDashboard {
        let role = ReportRole(scope: report.scope ?? fallbackScope)
        let metrics = report.metrics ?? []
        let all = metrics.map { metric($0, T: T) }
        let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let layout = layout(for: role)

        let attention = attentionItems(role: role, metrics: metrics, T: T)
        let attentionKeys = Set(attention.map(\.key))
        // Refunds overdue is a subset of refunds owed: when it is flagged, the
        // owed card (if any) already carries the amount, so neither shows twice.
        var hiddenFromOverview = attentionKeys
        if attentionKeys.contains("refunds_overdue") || attentionKeys.contains("refunds_owed") {
            hiddenFromOverview.formUnion(["refunds_owed", "refunds_overdue"])
        }
        // The disputes card already states the average backlog age.
        if attentionKeys.contains("unresolved_disputes") { hiddenFromOverview.insert("backlog_avg_age_days") }

        let primary = layout.primary.flatMap { byKey[$0] }
        let known = Set([layout.primary].compactMap { $0 } + layout.overview)
        var overview = layout.overview.compactMap { byKey[$0] }.filter { !hiddenFromOverview.contains($0.key) }
        // A metric the client doesn't know yet still shows (server label), never dropped.
        overview += all.filter { !known.contains($0.key) && !hiddenFromOverview.contains($0.key) }
        let trends = layout.trends.compactMap { byKey[$0] }.filter(\.isTimeSeries)

        return ReportsDashboard(role: role, primary: primary, overview: overview, attention: attention,
                                trends: trends, all: all, attentionFirst: layout.attentionFirst,
                                insights: insights(role: role, metrics: metrics, T: T))
    }

    // MARK: breakdowns (only what the payload supports)

    static func insights(role: ReportRole, metrics: [AccountKpiMetric],
                         T: (String, String) -> String) -> [ReportInsight] {
        func find(_ key: String) -> AccountKpiMetric? { metrics.first { $0.key == key } }
        func num(_ m: AccountKpiMetric?) -> Int {
            if let m, case .number(let n) = m.value { return Int(n.rounded()) }
            return 0
        }
        var out: [ReportInsight] = []
        switch role {
        case .personal:
            // Outstanding refund claims by status (owed vs host-marked-sent).
            if let m = find("outstanding_refunds"), let rows = m.rows, !rows.isEmpty {
                let owed = rows.filter { $0["status"]?.displayString == "owed" }.count
                let sent = rows.filter { $0["status"]?.displayString == "host_marked_sent" }.count
                let segs = [
                    ReportDistributionSegment(id: "owed", label: statusLabel("owed", T: T), count: owed),
                    ReportDistributionSegment(id: "host_marked_sent", label: statusLabel("host_marked_sent", T: T), count: sent),
                ].filter { $0.count > 0 }
                if !segs.isEmpty {
                    out.append(.distribution(.init(key: m.key, title: T("Hoàn tiền đang chờ theo trạng thái", "Pending refunds by status"), segments: segs)))
                }
            }
        case .host:
            // Of the owed refund claims (one population, one CTE), how many are past due.
            if let m = find("refunds_owed"), let rows = m.rows, !rows.isEmpty {
                let overdue = rows.filter { if case .bool(true)? = $0["overdue"] { return true }; return false }.count
                out.append(.share(.init(key: m.key, title: T("Hoàn tiền đã quá hạn", "Refunds past their deadline"),
                                        numerator: overdue, denominator: rows.count,
                                        caption: T("\(overdue)/\(rows.count) khoản hoàn tiền còn nợ đã quá hạn",
                                                   "\(overdue) of \(rows.count) owed refund claim\(rows.count == 1 ? "" : "s") overdue"))))
            }
        case .admin:
            let reviews = find("pending_event_reviews"), disputes = find("unresolved_disputes")
            let r = num(reviews), d = num(disputes)
            if r + d > 0 {
                out.append(.distribution(.init(
                    key: r > 0 ? "pending_event_reviews" : "unresolved_disputes",
                    title: T("Hàng chờ đang mở", "Open backlog"),
                    segments: [
                        .init(id: "reviews", label: T("Sự kiện chờ duyệt", "Event reviews"), count: r),
                        .init(id: "disputes", label: T("Tranh chấp", "Disputes"), count: d),
                    ].filter { $0.count > 0 })))
            }
            let ages: [Double] = [reviews, disputes].compactMap { $0 }.flatMap { m in
                (m.rows ?? []).compactMap { row -> Double? in
                    if case .number(let a)? = row["age_days"] { return a }; return nil
                }
            }
            if !ages.isEmpty {
                let buckets: [(String, String, String, (Double) -> Bool)] = [
                    ("lt1", "Dưới 1 ngày", "Under 1 day", { $0 < 1 }),
                    ("1to3", "1–3 ngày", "1–3 days", { $0 >= 1 && $0 < 3 }),
                    ("3to7", "3–7 ngày", "3–7 days", { $0 >= 3 && $0 < 7 }),
                    ("7plus", "Từ 7 ngày", "7+ days", { $0 >= 7 }),
                ]
                let segs = buckets.map { id, vi, en, test in
                    ReportDistributionSegment(id: id, label: T(vi, en), count: ages.filter(test).count)
                }
                out.append(.distribution(.init(key: r > 0 ? "pending_event_reviews" : "unresolved_disputes",
                                               title: T("Thời gian chờ của hàng chờ", "How long items have waited"),
                                               segments: segs)))
            }
        }
        return out
    }

    /// One sentence for VoiceOver and for the large-text fallback.
    static func insightSentence(_ i: ReportInsight, T: (String, String) -> String) -> String {
        switch i {
        case .share(let s):
            return s.caption + "."
        case .distribution(let d):
            let parts = d.segments.map { "\($0.label): \($0.count)" }.joined(separator: ", ")
            return T("\(d.title). Tổng \(d.total). \(parts).", "\(d.title). Total \(d.total). \(parts).")
        }
    }

    static func metric(_ m: AccountKpiMetric, T: (String, String) -> String) -> ReportMetricPresentation {
        let kind = ReportValueKind(unit: m.unit)
        let number: Double? = { if case .number(let n) = m.value { return n }; return nil }()
        let points = seriesPoints(m.series ?? [])
        return ReportMetricPresentation(
            key: m.key,
            title: ReportMetricLabels.label(m, T),
            kind: kind,
            number: number,
            valueText: number.map { formatValue($0, kind: kind, metricKey: m.key, T: T) } ?? (m.value.displayString.isEmpty ? "—" : m.value.displayString),
            accessibilityValue: number.map { formatValue($0, kind: kind, metricKey: m.key, T: T, spoken: true) } ?? "—",
            series: points,
            summary: points.isEmpty ? nil : summarize(points),
            rowCount: m.rows?.count ?? 0)
    }

    // MARK: needs attention (only actionable, non-zero backlogs)

    static func attentionItems(role: ReportRole, metrics: [AccountKpiMetric],
                               T: (String, String) -> String) -> [ReportAttentionItem] {
        func find(_ key: String) -> AccountKpiMetric? { metrics.first { $0.key == key } }
        func num(_ m: AccountKpiMetric?) -> Double {
            if let m, case .number(let n) = m.value { return n }
            return 0
        }
        var items: [ReportAttentionItem] = []
        switch role {
        case .personal:
            if let m = find("outstanding_refunds"), num(m) > 0 {
                let rows = m.rows ?? []
                let marked = rows.filter { $0["status"]?.displayString == "host_marked_sent" }.count
                let message = marked > 0
                    ? T("\(marked) khoản host báo đã gửi, hãy xác nhận khi bạn nhận được.",
                        "\(marked) marked as sent by the host. Confirm once you've received it.")
                    : T("Đang chờ host hoàn tiền cho \(rows.count) khoản.",
                        "Waiting for hosts to refund \(rows.count) claim\(rows.count == 1 ? "" : "s").")
                items.append(.init(key: m.key, severity: .pending, title: ReportMetricLabels.label(m, T),
                                   valueText: formatValue(num(m), kind: .money, metricKey: m.key, T: T),
                                   message: message, symbol: "arrow.uturn.backward.circle"))
            }
        case .host:
            let overdue = num(find("refunds_overdue"))
            if let m = find("refunds_overdue"), overdue > 0 {
                let n = Int(overdue)
                items.append(.init(key: m.key, severity: .overdue, title: ReportMetricLabels.label(m, T),
                                   valueText: formatValue(overdue, kind: .count, metricKey: m.key, T: T),
                                   message: T("\(n) khoản hoàn tiền đã quá hạn. Hãy hoàn tiền cho khách sớm nhất có thể.",
                                              "\(n) refund\(n == 1 ? " is" : "s are") past the deadline. Refund the guest\(n == 1 ? "" : "s") as soon as you can."),
                                   symbol: "exclamationmark.triangle"))
            }
            if let m = find("refunds_owed"), num(m) > 0 {
                let claims = m.rows?.count ?? 0
                items.append(.init(key: m.key, severity: .pending, title: ReportMetricLabels.label(m, T),
                                   valueText: formatValue(num(m), kind: .money, metricKey: m.key, T: T),
                                   message: T("Còn nợ khách \(claims) khoản hoàn tiền.",
                                              "\(claims) refund claim\(claims == 1 ? "" : "s") still owed to guests."),
                                   symbol: "arrow.uturn.backward.circle"))
            }
        case .admin:
            let avgAge = num(find("backlog_avg_age_days"))
            if let m = find("pending_event_reviews"), num(m) > 0 {
                let oldest = (m.rows ?? []).compactMap { r -> Double? in
                    if case .number(let d)? = r["age_days"] { return d }; return nil
                }.max()
                let message = oldest.map {
                    T("Sự kiện chờ lâu nhất: \(formatDays($0, T: T)).", "Oldest waiting: \(formatDays($0, T: T)).")
                } ?? T("Đang chờ duyệt.", "Waiting for review.")
                items.append(.init(key: m.key, severity: .pending, title: ReportMetricLabels.label(m, T),
                                   valueText: formatValue(num(m), kind: .count, metricKey: m.key, T: T),
                                   message: message, symbol: "tray.full"))
            }
            if let m = find("unresolved_disputes"), num(m) > 0 {
                items.append(.init(key: m.key, severity: .urgent, title: ReportMetricLabels.label(m, T),
                                   valueText: formatValue(num(m), kind: .count, metricKey: m.key, T: T),
                                   message: T("Tuổi trung bình hàng chờ: \(formatDays(avgAge, T: T)).",
                                              "Average backlog age: \(formatDays(avgAge, T: T))."),
                                   symbol: "exclamationmark.bubble"))
            }
        }
        return items
    }

    // MARK: series

    static func seriesPoints(_ raw: [AccountKpiSeriesPoint]) -> [ReportSeriesPoint] {
        raw.compactMap { p in parseDay(p.d).map { ReportSeriesPoint(dayKey: p.d, date: $0, value: p.v) } }
            .sorted { $0.date < $1.date }
    }

    static func summarize(_ points: [ReportSeriesPoint]) -> ReportSeriesSummary {
        let total = points.reduce(0) { $0 + $1.value }
        // Earliest day wins a tie, so the peak is stable.
        let peak = points.reduce(nil as ReportSeriesPoint?) { best, p in
            guard p.value > 0 else { return best }
            guard let best else { return p }
            return p.value > best.value ? p : best
        }
        return ReportSeriesSummary(total: total, peak: peak, activeDays: points.filter { $0.value > 0 }.count,
                                   dayCount: points.count)
    }

    /// One-sentence chart summary for VoiceOver and the detail header.
    static func seriesSentence(_ m: ReportMetricPresentation, T: (String, String) -> String) -> String {
        guard let s = m.summary else { return T("Số liệu hiện tại.", "Current total.") }
        guard s.hasActivity, let peak = s.peak else {
            return T("Không có hoạt động trong \(s.dayCount) ngày.", "No activity across \(s.dayCount) days.")
        }
        let peakValue = formatValue(peak.value, kind: m.kind, metricKey: m.key, T: T, spoken: true)
        return T("Tổng \(m.accessibilityValue) trong \(s.dayCount) ngày, có hoạt động \(s.activeDays) ngày. Cao nhất \(peakValue) vào \(formatDay(peak.date, T: T)).",
                 "Total \(m.accessibilityValue) over \(s.dayCount) days, active on \(s.activeDays). Peak \(peakValue) on \(formatDay(peak.date, T: T)).")
    }

    // MARK: formatting

    static let displayTimeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current

    private static func isVI(_ T: (String, String) -> String) -> Bool { T("vi", "en") == "vi" }

    static func groupedInteger(_ n: Double, T: (String, String) -> String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = isVI(T) ? "." : ","
        f.decimalSeparator = isVI(T) ? "," : "."
        return f.string(from: NSNumber(value: n.rounded())) ?? String(Int(n))
    }

    static func formatDays(_ n: Double, T: (String, String) -> String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        f.decimalSeparator = isVI(T) ? "," : "."
        f.groupingSeparator = isVI(T) ? "." : ","
        let s = f.string(from: NSNumber(value: n)) ?? String(n)
        return T("\(s) ngày", n == 1 ? "\(s) day" : "\(s) days")
    }

    static func formatValue(_ n: Double, kind: ReportValueKind, metricKey: String,
                            T: (String, String) -> String, spoken: Bool = false) -> String {
        switch kind {
        case .count: return groupedInteger(n, T: T)
        case .money:
            let amount = groupedInteger(n, T: T)
            return spoken ? T("\(amount) đồng", "\(amount) dong") : "\(amount)₫"
        case .days:
            // The server coalesces an empty backlog's average age to 0.
            if metricKey == "backlog_avg_age_days" && n == 0 { return T("Không có hàng chờ", "No backlog") }
            return formatDays(n, T: T)
        }
    }

    /// Short axis label: 750k / 1,2tr (VI) · 750K / 1.2M (EN).
    static func compact(_ n: Double, kind: ReportValueKind, T: (String, String) -> String) -> String {
        guard kind == .money || abs(n) >= 10_000 else { return groupedInteger(n, T: T) }
        let vi = isVI(T)
        func trim(_ v: Double) -> String {
            let s = v >= 10 || v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
            return vi ? s.replacingOccurrences(of: ".", with: ",") : s
        }
        if abs(n) >= 1_000_000_000 { return trim(n / 1_000_000_000) + (vi ? "tỷ" : "B") }
        if abs(n) >= 1_000_000 { return trim(n / 1_000_000) + (vi ? "tr" : "M") }
        if abs(n) >= 1_000 { return trim(n / 1_000) + (vi ? "k" : "K") }
        return trim(n)
    }

    // MARK: dates

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres `timestamptz` → jsonb carries fractional seconds only when
    /// non-zero, so both shapes must parse.
    static func parseTimestamp(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    /// A series bucket is a calendar day, not an instant — parsed and
    /// formatted in UTC so no device timezone can shift it by a day.
    static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    static func formatDay(_ d: Date, T: (String, String) -> String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd/MM"
        return f.string(from: d)
    }

    static func formatDate(_ d: Date, withTime: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = displayTimeZone
        f.dateFormat = withTime ? "dd/MM/yyyy HH:mm" : "dd/MM/yyyy"
        return f.string(from: d)
    }

    static func rangeText(_ range: AccountKpiRange?) -> String {
        guard let range, let s = parseTimestamp(range.start), let e = parseTimestamp(range.end) else { return "" }
        return "\(formatDate(s, withTime: false)) – \(formatDate(e, withTime: false))"
    }

    // MARK: underlying rows (localized, never raw field keys)

    /// Display order of known columns; `id`/`event_id` are export-only.
    static let columnOrder = ["qty", "amount_vnd", "status", "starts_at", "at", "since", "due_at",
                              "submitted_at", "disputed_at", "age_days", "overdue"]
    static let hiddenColumns: Set<String> = ["id", "event_id", "event_name"]

    static func columnLabel(_ key: String, T: (String, String) -> String) -> String {
        switch key {
        case "event_name": return T("Sự kiện", "Event")
        case "qty": return T("Số chỗ", "Seats")
        case "at": return T("Thời gian", "When")
        case "starts_at": return T("Bắt đầu", "Starts")
        case "amount_vnd": return T("Số tiền", "Amount")
        case "status": return T("Trạng thái", "Status")
        case "since": return T("Từ ngày", "Since")
        case "due_at": return T("Hạn hoàn tiền", "Refund due")
        case "overdue": return T("Quá hạn", "Overdue")
        case "submitted_at": return T("Gửi duyệt", "Submitted")
        case "disputed_at": return T("Mở tranh chấp", "Disputed")
        case "age_days": return T("Đã chờ", "Waiting")
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusLabel(_ raw: String, T: (String, String) -> String) -> String {
        switch raw {
        case "owed": return T("Đang chờ host hoàn tiền", "Waiting for host refund")
        case "host_marked_sent": return T("Host báo đã gửi", "Host marked as sent")
        case "guest_confirmed": return T("Đã nhận", "Received")
        case "disputed": return T("Đang tranh chấp", "Disputed")
        default: return raw
        }
    }

    static func cell(_ key: String, _ value: KpiJSONValue?, T: (String, String) -> String) -> String? {
        guard let value else { return nil }
        switch (key, value) {
        case (_, .null): return nil
        case ("amount_vnd", .number(let n)): return formatValue(n, kind: .money, metricKey: key, T: T)
        case ("qty", .number(let n)): return groupedInteger(n, T: T)
        case ("age_days", .number(let n)): return formatDays(n, T: T)
        case ("status", .string(let s)): return statusLabel(s, T: T)
        case ("overdue", .bool(let b)): return b ? T("Có", "Yes") : T("Không", "No")
        case (_, .string(let s)) where key == "at" || key.hasSuffix("_at") || key == "since":
            return parseTimestamp(s).map { formatDate($0, withTime: true) } ?? s
        default:
            let s = value.displayString
            return s.isEmpty ? nil : s
        }
    }

    static func rows(_ metric: AccountKpiMetric, T: (String, String) -> String) -> [ReportRowPresentation] {
        (metric.rows ?? []).enumerated().map { i, row in
            let keys = columnOrder.filter { row[$0] != nil }
                + row.keys.filter { !columnOrder.contains($0) && !hiddenColumns.contains($0) }.sorted()
            let fields = keys.compactMap { k in cell(k, row[k], T: T).map { ReportRowField(label: columnLabel(k, T: T), value: $0) } }
            let title = row["event_name"]?.displayString ?? ""
            let flagged: Bool = { if case .bool(true)? = row["overdue"] { return true }; return false }()
            return ReportRowPresentation(id: i, title: title.isEmpty ? "—" : title, fields: fields, flagged: flagged)
        }
    }
}

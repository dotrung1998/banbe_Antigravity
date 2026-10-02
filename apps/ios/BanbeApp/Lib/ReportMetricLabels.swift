import Foundation

/// Localization-leak fix pass — `get_account_kpis()` (migration 097) returns
/// every metric's `label` as a single hardcoded Vietnamese string,
/// server-side, with no English counterpart in the payload at all —
/// switching the app's language to English never touched these, since
/// nothing client-side was even trying to translate them. No migration/
/// schema change for this pass (out of scope) — translated here instead,
/// keyed by the metric's own stable `key` (never its `label`, which is the
/// untranslated value this fixes), mirroring `src/lib/reportMetricLabels.js`
/// exactly so the two platforms can never show different English wording
/// for the same metric. Used by both `ReportsView.swift` (on-screen cards)
/// and `AppState+Reports.swift` (PDF export). Falls back to the raw server
/// label if a key is ever missing here (a future new metric), so this can
/// never show a blank — only, at worst, temporarily untranslated until
/// added below.
enum ReportMetricLabels {
    static let en: [String: String] = [
        "saved_events": "Saved events",
        "confirmed_bookings": "Confirmed bookings",
        "attended_events": "Attended",
        "upcoming_events": "Upcoming",
        "outstanding_refunds": "Refunds pending",
        "published_events": "Published events",
        "confirmed_seats": "Confirmed seats",
        "check_ins": "Checked in",
        "confirmed_payment_amount": "Confirmed payment amount",
        "refunds_owed": "Refunds owed",
        "refunds_overdue": "Refunds overdue",
        "pending_event_reviews": "Events pending review",
        "unresolved_disputes": "Unresolved disputes",
        "backlog_avg_age_days": "Average backlog age (days)",
        "platform_new_events": "New events platform-wide",
        "platform_new_bookings": "New bookings platform-wide",
    ]

    static func label(_ metric: AccountKpiMetric, _ T: (String, String) -> String) -> String {
        T(metric.label, en[metric.key] ?? metric.label)
    }
}

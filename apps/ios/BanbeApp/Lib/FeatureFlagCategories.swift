import Foundation

/// Admin > Feature switches, grouped (note 64). Web twin: src/lib/featureFlagCategories.js — the web unit test
/// tests/unit/featureFlagCategories.test.mjs parses this file and checks both lists match.
///
/// "onboarding_version" is not a flag key: it is the one control for onboarding_v2 + onboarding_v3 (migration 202).
/// "admin_event_wipe" only exists on iOS (testing-phase tool, note 54).
enum FeatureFlagCategories {
    struct Category: Identifiable {
        let key: String, vi: String, en: String
        let flags: [String]
        var id: String { key }
    }

    static let onboardingControl = "onboarding_version"
    static let controlKeys: [String: [String]] = [onboardingControl: ["onboarding_v2", "onboarding_v3"]]

    static let all: [Category] = [
        Category(key: "onboarding", vi: "Giới thiệu & khám phá", en: "Onboarding & discovery", flags: ["onboarding_version", "intent_foryou", "market_share"]),
        Category(key: "rewards", vi: "Phần thưởng & gắn kết", en: "Rewards & engagement", flags: ["rewards", "rewards_v2"]),
        Category(key: "notifications", vi: "Thông báo & giữ chân", en: "Notifications & retention", flags: ["push_enabled", "event_reminders", "follow_alerts", "weekly_digest", "live_activity"]),
        Category(key: "events", vi: "Sự kiện & tổng kết", en: "Events & recaps", flags: ["event_recap", "host_recap"]),
        Category(key: "platform", vi: "Nền tảng & đo lường", en: "Platform & measurement", flags: ["app_events", "admin_event_wipe"]),
    ]

    /// The flag keys a category row stands for (a control expands to its keys).
    static func keys(of row: String) -> [String] { controlKeys[row] ?? [row] }
}

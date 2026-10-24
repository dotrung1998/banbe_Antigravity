import Foundation

/// Platform feature flags (migration 187, note 51): a platform admin can hide a feature everywhere without a
/// release. Web twin: src/lib/featureFlags.js — keep both and their tests in sync.
///
/// Rules, so a flag can never hide something by accident:
/// - A key that is MISSING means "on". Only an explicit `false` from the server hides a feature.
/// - The server answer is cached on the device, so a cold start without network keeps the last-known value instead
///   of flipping a hidden feature back on (or a visible one off). The very first run, before any answer, shows
///   everything, which is the behaviour from before flags existed.
/// - Anything that is not a boolean, and any key this build does not know, is ignored.
enum FeatureFlags {
    static let keys = ["rewards", "admin_event_wipe", "rewards_v2", "push_enabled", "app_events",
                       "event_reminders", "event_recap", "host_recap", "follow_alerts", "weekly_digest", "intent_foryou", "live_activity", "market_share", "onboarding_v2"]
    /// Flags that are OFF unless the server explicitly says true (a missing key never turns them on). Note 54:
    /// "admin_event_wipe" is a TESTING-PHASE admin tool that must never switch itself on. "rewards_v2" (migration
    /// 192) is a new feature that stays dark until an admin turns it on (same list as src/lib/featureFlags.js).
    /// "push_enabled" (migration 194): real push notifications, off until an admin turns them on.
    /// "app_events" (migration 196): first-party measurement, nothing is sent until an admin turns it on.
    /// Migrations 199/200: "event_reminders" is on unless an admin turns it off; the rest stay dark until set.
    /// "onboarding_v2" (migration 201): off/missing = onboarding Version 1, on = Version 2 (note 63).
    static let offUnlessSet: Set<String> = ["admin_event_wipe", "rewards_v2", "push_enabled", "app_events",
                                            "event_recap", "host_recap", "follow_alerts", "weekly_digest", "intent_foryou", "live_activity", "market_share", "onboarding_v2"]
    static let cacheKey = "banbe.featureFlags.v1"

    /// Keep only known keys with real booleans.
    static func normalize(_ raw: [String: Bool?]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for k in keys { if let v = raw[k], let b = v { out[k] = b } }
        return out
    }

    /// Missing key = on, except for `offUnlessSet` keys (missing = off).
    static func isOn(_ flags: [String: Bool], _ key: String) -> Bool {
        offUnlessSet.contains(key) ? flags[key] == true : flags[key] != false
    }

    static func read(_ defaults: UserDefaults = .standard) -> [String: Bool] {
        guard let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return normalize(decoded.mapValues { Optional($0) })
    }

    static func write(_ flags: [String: Bool], _ defaults: UserDefaults = .standard) {
        let clean = normalize(flags.mapValues { Optional($0) })
        if let data = try? JSONEncoder().encode(clean) { defaults.set(data, forKey: cacheKey) }
    }
}

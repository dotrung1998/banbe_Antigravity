import Foundation

/// Feature-switched CONTENT (policy, guides, Q&A). Web twin: src/lib/contentFlags.js — keep both and their tests in
/// sync (note 59). Text tied to a feature carries one content key; while that key is off the text is removed before
/// any view (table of contents, search, body) sees it, so with Rewards off nothing mentions rewards.
///
/// Content keys, built on the platform flags (missing `rewards` = on, missing `rewards_v2` = off):
///   rewards        Rewards is on
///   rewards_daily  Rewards on, Rewards v2 off (the daily streak the app shows)
///   rewards_v2     Rewards on, Rewards v2 on (weekly streak, grace weeks, repair, tiers, goal)
///   push_enabled   real push notifications on (migration 194)
///   app_events     first-party measurement on (migration 196)
///   event_reminders, event_recap, host_recap, follow_alerts (199); weekly_digest, live_activity (200)
///   event_types    the event_type_profiles switch is on (migration 203/204): alcohol & minimum-age terms (A10)
enum ContentFlags {
    static func isOn(_ flags: [String: Bool], _ key: String?) -> Bool {
        guard let key else { return true }
        let rewards = FeatureFlags.isOn(flags, "rewards")
        switch key {
        case "rewards": return rewards
        case "rewards_daily": return rewards && !FeatureFlags.isOn(flags, "rewards_v2")
        case "rewards_v2": return rewards && FeatureFlags.isOn(flags, "rewards_v2")
        // Dark until set: only an explicit true shows their text (same rule as the web).
        case "push_enabled", "app_events", "event_recap", "host_recap", "follow_alerts", "weekly_digest", "live_activity":
            return flags[key] == true
        case "event_types": return flags["event_type_profiles"] == true
        // On unless an admin turned it off (migration 199 seeds it ON).
        case "event_reminders": return FeatureFlags.isOn(flags, "event_reminders")
        default: return false
        }
    }

    static func filter(_ b: HelpBlock, _ flags: [String: Bool]) -> HelpBlock? {
        switch b {
        case .flagged(let key, let inner): return isOn(flags, key) ? filter(inner, flags) : nil
        case .ul(let items):
            let kept = items.filter { isOn(flags, $0.count > 2 ? $0[2] : nil) }.map { Array($0.prefix(2)) }
            return kept.isEmpty ? nil : .ul(kept)
        case .ol(let items):
            let kept = items.filter { isOn(flags, $0.count > 2 ? $0[2] : nil) }.map { Array($0.prefix(2)) }
            return kept.isEmpty ? nil : .ol(kept)
        default: return b
        }
    }

    /// Switched-off sections, blocks and list items removed; a section left empty disappears too.
    static func filter(_ sections: [HelpSection], _ flags: [String: Bool]) -> [HelpSection] {
        sections.compactMap { s in
            guard isOn(flags, s.flag) else { return nil }
            let blocks = s.blocks.compactMap { filter($0, flags) }
            return blocks.isEmpty ? nil : HelpSection(id: s.id, vi: s.vi, en: s.en, flag: s.flag, blocks: blocks)
        }
    }

    static func filter(_ doc: HelpDoc, _ flags: [String: Bool]) -> HelpDoc {
        HelpDoc(vi: doc.vi, en: doc.en, introVi: doc.introVi, introEn: doc.introEn, adminOnly: doc.adminOnly,
                sections: filter(doc.sections, flags))
    }
}

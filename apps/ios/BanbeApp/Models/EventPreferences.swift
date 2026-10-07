import Foundation

// Event preferences ("For You") + host reservation criteria — shared models.
// Server contract: supabase/migrations/…_162_event_preferences_and_reservation_criteria.sql.
// Rules/scoring documented in .claude/notes/34-onboarding-for-you-criteria.md.

/// One selectable chip: stable server id + localized labels.
struct PrefOption: Identifiable, Hashable {
    let id: String
    let vi: String
    let en: String
}

/// The shared taxonomy. Ids MUST match `event_pref_ids()` in migration 162.
enum EventPrefTaxonomy {
    /// Server sentinel meaning "I have no preference" (stored as ["no_preference"]).
    static let noPreference = "no_preference"

    /// Existing event category ids (CreateEventView.categories / events.cat_key).
    static let interests: [PrefOption] = [
        .init(id: "supper", vi: "Supper club", en: "Supper club"),
        .init(id: "fashion", vi: "Thời trang", en: "Fashion"),
        .init(id: "gallery", vi: "Phòng tranh", en: "Gallery"),
        .init(id: "music", vi: "Nhạc", en: "Music"),
        .init(id: "popup", vi: "Pop-up", en: "Pop-up"),
    ]
    static let goals: [PrefOption] = [
        .init(id: "meet_people", vi: "Gặp gỡ mọi người", en: "Meet people"),
        .init(id: "learn", vi: "Học hỏi", en: "Learn something"),
        .init(id: "experiences", vi: "Tận hưởng trải nghiệm", en: "Enjoy experiences"),
        .init(id: "networking", vi: "Kết nối nghề nghiệp", en: "Professional networking"),
    ]
    static let availability: [PrefOption] = [
        .init(id: "weekdays", vi: "Ngày thường", en: "Weekdays"),
        .init(id: "weekends", vi: "Cuối tuần", en: "Weekends"),
        .init(id: "daytime", vi: "Ban ngày", en: "Daytime"),
        .init(id: "evening", vi: "Buổi tối", en: "Evening"),
    ]
    static let languages: [PrefOption] = [
        .init(id: "vi", vi: "Tiếng Việt", en: "Vietnamese"),
        .init(id: "en", vi: "Tiếng Anh", en: "English"),
        .init(id: "other", vi: "Ngôn ngữ khác", en: "Other"),
    ]
    static let budgetTiers: [String] = ["free", "low", "medium", "flexible"]

    static func label(_ id: String, in options: [PrefOption], vi: Bool) -> String {
        guard let o = options.first(where: { $0.id == id }) else { return id }
        return vi ? o.vi : o.en
    }
}

// MARK: - Budget (explicit local-currency ranges)

enum BudgetRegion: String, CaseIterable {
    case vn = "VN", us = "US"

    var currency: String { self == .vn ? "VND" : "USD" }

    /// Device region decides the default; the user can switch in the UI.
    static func deviceDefault(_ locale: Locale = .current) -> BudgetRegion {
        locale.region?.identifier == "US" ? .us : .vn
    }
    static func forCurrency(_ c: String?) -> BudgetRegion { c == "USD" ? .us : .vn }

    /// Upper bound (inclusive) of each tier in WHOLE currency units; medium's
    /// lower bound is low's upper bound. `nil` = unbounded.
    var lowMax: Int { self == .vn ? 200_000 : 25 }
    var mediumMax: Int { self == .vn ? 600_000 : 75 }

    private func money(_ n: Int) -> String {
        self == .vn ? EventLabels.vnd(n) : "$\(n)"
    }

    /// Explicit label for a tier, e.g. "Low · up to 200.000₫".
    func label(tier: String, vi: Bool) -> String {
        switch tier {
        case "free": return vi ? "Chỉ sự kiện miễn phí" : "Free events only"
        case "low": return vi ? "Thấp · đến \(money(lowMax))" : "Low · up to \(money(lowMax))"
        case "medium":
            return vi ? "Trung bình · \(money(lowMax)) – \(money(mediumMax))"
                      : "Medium · \(money(lowMax)) – \(money(mediumMax))"
        case "flexible": return vi ? "Linh hoạt · không giới hạn" : "Flexible · no limit"
        default: return vi ? "Không ưu tiên" : "No preference"
        }
    }

    /// Highest price (whole units) a tier tolerates; nil = no cap.
    func cap(tier: String) -> Int? {
        switch tier {
        case "free": return 0
        case "low": return lowMax
        case "medium": return mediumMax
        default: return nil
        }
    }
}

// MARK: - The user's declarations

struct BudgetPref: Codable, Equatable {
    var tier: String          // free | low | medium | flexible | no_preference
    var currency: String?     // VND | USD (omitted for free / no_preference)
}

/// profile_event_preferences.event_preferences (version 1). A nil field means
/// the question was skipped; ["no_preference"] means an explicit "no preference".
struct EventPreferences: Codable, Equatable {
    var version: Int = 1
    var interests: [String]?
    var goals: [String]?
    var availability: [String]?
    var budget: BudgetPref?
    var languages: [String]?

    /// Concrete (non-sentinel) ids declared for a question.
    static func concrete(_ values: [String]?) -> [String] {
        (values ?? []).filter { $0 != EventPrefTaxonomy.noPreference }
    }
    var declaredInterests: [String] { Self.concrete(interests) }
    var declaredGoals: [String] { Self.concrete(goals) }
    var declaredAvailability: [String] { Self.concrete(availability) }

    /// True when nothing was answered at all (all skipped).
    var isEmpty: Bool {
        interests == nil && goals == nil && availability == nil && budget == nil && languages == nil
    }

    /// Drop empty arrays → nil (skipped) so the server's "non-empty array" rule holds.
    func normalizedForSave() -> EventPreferences {
        var p = self
        func fix(_ a: [String]?) -> [String]? {
            guard let a, !a.isEmpty else { return nil }
            return a.contains(EventPrefTaxonomy.noPreference) ? [EventPrefTaxonomy.noPreference] : a
        }
        p.interests = fix(interests); p.goals = fix(goals)
        p.availability = fix(availability); p.languages = fix(languages)
        if let b = p.budget, b.tier == "free" || b.tier == EventPrefTaxonomy.noPreference {
            p.budget = BudgetPref(tier: b.tier, currency: nil)
        }
        p.version = 1
        return p
    }
}

/// `get_my_event_preferences()` payload.
struct EventPrefsServerState: Decodable {
    let success: Bool?
    let preferences: EventPreferences?
    let preferencesVersion: Int?
    let isNewAccount: Bool?
    let needsSettingsStep: Bool?
    let needsPreferencesStep: Bool?
    enum CodingKeys: String, CodingKey {
        case success, preferences
        case preferencesVersion = "preferences_version"
        case isNewAccount = "is_new_account"
        case needsSettingsStep = "needs_settings_step"
        case needsPreferencesStep = "needs_preferences_step"
    }
}

// MARK: - Host reservation criteria (eligibility, NOT recommendation)

struct CriteriaGroup: Codable, Equatable {
    var rule: String          // "any" | "all"
    var values: [String]
}

/// events.reservation_criteria. Default = Everyone. Only interests/goals.
struct ReservationCriteria: Codable, Equatable {
    var version: Int = 1
    var mode: String = "everyone"      // "everyone" | "declared"
    var interests: CriteriaGroup?
    var goals: CriteriaGroup?

    static let everyone = ReservationCriteria()
    var isEveryone: Bool { mode != "declared" }

    /// A well-formed value for the server: groups with no values are dropped,
    /// and a declared set with no groups collapses to Everyone.
    func normalizedForSave() -> ReservationCriteria {
        var c = self
        if let i = c.interests, i.values.isEmpty { c.interests = nil }
        if let g = c.goals, g.values.isEmpty { c.goals = nil }
        if c.mode != "declared" || (c.interests == nil && c.goals == nil) { return .everyone }
        return c
    }

    /// Plain-language rule for guests/hosts, e.g. "Any of Music, Gallery · All of Learn".
    func summary(vi: Bool) -> String {
        guard !isEveryone else { return vi ? "Mọi người" : "Everyone" }
        func part(_ g: CriteriaGroup?, _ opts: [PrefOption]) -> String? {
            guard let g, !g.values.isEmpty else { return nil }
            let names = g.values.map { EventPrefTaxonomy.label($0, in: opts, vi: vi) }.joined(separator: ", ")
            let head = g.rule == "all" ? (vi ? "Tất cả: " : "All of: ") : (vi ? "Một trong: " : "Any of: ")
            return head + names
        }
        let i = part(interests, EventPrefTaxonomy.interests).map { (vi ? "Sở thích: " : "Interests: ") + $0 }
        let g = part(goals, EventPrefTaxonomy.goals).map { (vi ? "Mục tiêu: " : "Goals: ") + $0 }
        return [i, g].compactMap { $0 }.joined(separator: "  ▪︎  ")
    }
}

/// `check_my_reservation_eligibility()` payload and `CRITERIA_NOT_MET`'s detail.
struct ReservationEligibility: Decodable, Equatable {
    let success: Bool?
    let eligible: Bool
    let mode: String?
    let interestRule: String?
    let goalRule: String?
    let missingInterests: [String]
    let missingGoals: [String]
    enum CodingKeys: String, CodingKey {
        case success, eligible, mode
        case interestRule = "interest_rule"
        case goalRule = "goal_rule"
        case missingInterests = "missing_interests"
        case missingGoals = "missing_goals"
    }

    /// Exact guidance, e.g. "Add at least one of: Music, Gallery" / "Add: Learn".
    func guidance(vi: Bool) -> [String] {
        func line(_ missing: [String], _ rule: String?, _ opts: [PrefOption], _ kind: String) -> String? {
            guard !missing.isEmpty else { return nil }
            let names = missing.map { EventPrefTaxonomy.label($0, in: opts, vi: vi) }.joined(separator: ", ")
            let head: String
            if rule == "any" { head = vi ? "Chọn ít nhất một" : "Pick at least one" }
            else { head = vi ? "Thêm" : "Add" }
            return "\(kind): \(head): \(names)"
        }
        return [
            line(missingInterests, interestRule, EventPrefTaxonomy.interests, vi ? "Sở thích" : "Interests"),
            line(missingGoals, goalRule, EventPrefTaxonomy.goals, vi ? "Mục tiêu" : "Goals"),
        ].compactMap { $0 }
    }
}

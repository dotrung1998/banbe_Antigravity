import Foundation

// Post-signup personalization flow — the pure part (state machine, draft
// persistence, "what your answers change" copy). No SwiftUI, no network:
// covered by BanbeAppTests/OnboardingFlowTests.swift. The screens live in
// Views/OnboardingFlowViews.swift.
//
// Server contract unchanged (migration 162, note 34): finishing calls
// `complete_preferences_onboarding(p_preferences)` exactly as before
// (nil = skipped everything, marker only); the settings step still calls
// `complete_settings_onboarding`. Answers stay owner-only.

enum OnboardingQuestion: String, CaseIterable, Codable {
    case goals, interests, availability, budget, languages

    static var count: Int { allCases.count }

    func options() -> [PrefOption] {
        switch self {
        case .goals: return EventPrefTaxonomy.goals
        case .interests: return EventPrefTaxonomy.interests
        case .availability: return EventPrefTaxonomy.availability
        case .languages: return EventPrefTaxonomy.languages
        case .budget: return []
        }
    }

    /// How many values were chosen (1 for a budget tier). Never the values.
    func answerCount(_ p: EventPreferences) -> Int {
        switch self {
        case .goals: return p.goals?.count ?? 0
        case .interests: return p.interests?.count ?? 0
        case .availability: return p.availability?.count ?? 0
        case .languages: return p.languages?.count ?? 0
        case .budget: return p.budget == nil ? 0 : 1
        }
    }

    func clear(_ p: inout EventPreferences) {
        switch self {
        case .goals: p.goals = nil
        case .interests: p.interests = nil
        case .availability: p.availability = nil
        case .languages: p.languages = nil
        case .budget: p.budget = nil
        }
    }
}

enum OnboardingStage: Equatable, Codable {
    case welcome
    case question(Int)
    case saving
    case saveFailed
    case reveal
    case settings
    case finished
}

/// Pure multi-select rules shared by onboarding and Account > Event preferences.
enum PrefSelection {
    /// "No preference" is exclusive with everything else; empty = skipped (nil).
    static func toggle(_ current: [String]?, _ id: String) -> [String]? {
        let cur = current ?? []
        if id == EventPrefTaxonomy.noPreference {
            return cur == [id] ? nil : [id]
        }
        var arr = cur.filter { $0 != EventPrefTaxonomy.noPreference }
        if let i = arr.firstIndex(of: id) { arr.remove(at: i) } else { arr.append(id) }
        return arr.isEmpty ? nil : arr
    }

    /// Single-select budget; tapping the chosen tier again clears it.
    static func pickBudget(_ current: BudgetPref?, tier: String, region: BudgetRegion) -> BudgetPref? {
        if current?.tier == tier { return nil }
        let noCurrency = tier == "free" || tier == EventPrefTaxonomy.noPreference
        return BudgetPref(tier: tier, currency: noCurrency ? nil : region.currency)
    }

    /// Switching VND/USD re-labels a currency-bound tier; free/no-preference stay as they are.
    static func switchRegion(_ current: BudgetPref?, to region: BudgetRegion) -> BudgetPref? {
        guard var b = current, b.currency != nil else { return current }
        b.currency = region.currency
        return b
    }
}

struct OnboardingFlowState: Equatable, Codable {
    var stage: OnboardingStage
    var draft = EventPreferences()
    var region: String = BudgetRegion.vn.rawValue
    /// Server says the five questions are still owed.
    var needsPreferences: Bool
    /// Server says the settings review is still owed.
    var needsSettings: Bool
    /// "Skip all": nothing is saved and there is nothing to reveal.
    var skippedAll = false
    /// Back from the save-failed screen returns here.
    var lastQuestion = OnboardingQuestion.count - 1

    var budgetRegion: BudgetRegion { BudgetRegion(rawValue: region) ?? .vn }

    var currentQuestion: OnboardingQuestion? {
        if case .question(let i) = stage, OnboardingQuestion.allCases.indices.contains(i) {
            return OnboardingQuestion.allCases[i]
        }
        return nil
    }

    /// What `complete_preferences_onboarding` receives: nil = skipped everything.
    var payload: EventPreferences? {
        let p = draft.normalizedForSave()
        return skippedAll || p.isEmpty ? nil : p
    }

    var answeredQuestionCount: Int {
        let p = draft.normalizedForSave()
        return OnboardingQuestion.allCases.filter { $0.answerCount(p) > 0 }.count
    }

    static func initial(needsPreferences: Bool, needsSettings: Bool, region: BudgetRegion) -> OnboardingFlowState {
        let stage: OnboardingStage = needsPreferences ? .welcome : (needsSettings ? .settings : .finished)
        return OnboardingFlowState(stage: stage, region: region.rawValue,
                                   needsPreferences: needsPreferences, needsSettings: needsSettings)
    }
}

enum OnboardingAction: Equatable {
    case start
    case toggle(OnboardingQuestion, String)
    case pickBudget(String)
    case setRegion(BudgetRegion)
    case next
    case skipQuestion
    case back
    case skipAll
    case saveSucceeded
    case saveFailed
    case retrySave
    /// After a failed save: leave for this session only (server marker unset).
    case skipForNow
    case revealContinue
    case settingsDone
}

enum OnboardingEffect: Equatable {
    case save(EventPreferences?)
    case track(AnalyticsEvent)
}

enum OnboardingFlow {
    /// Applies `action`; returns the side effects to run, in order. Actions
    /// that don't apply to the current stage are ignored (double taps, a late
    /// callback) — the state never moves backwards past a successful save.
    @discardableResult
    static func reduce(_ s: inout OnboardingFlowState, _ action: OnboardingAction) -> [OnboardingEffect] {
        switch (s.stage, action) {
        case (.welcome, .start):
            s.stage = .question(0)
            return [.track(.onboardingStarted), viewed(0)]

        case (.question, .toggle(let q, let id)):
            switch q {
            case .goals: s.draft.goals = PrefSelection.toggle(s.draft.goals, id)
            case .interests: s.draft.interests = PrefSelection.toggle(s.draft.interests, id)
            case .availability: s.draft.availability = PrefSelection.toggle(s.draft.availability, id)
            case .languages: s.draft.languages = PrefSelection.toggle(s.draft.languages, id)
            case .budget: break
            }
            return []

        case (.question, .pickBudget(let tier)):
            s.draft.budget = PrefSelection.pickBudget(s.draft.budget, tier: tier, region: s.budgetRegion)
            return []

        case (.question, .setRegion(let r)):
            s.region = r.rawValue
            s.draft.budget = PrefSelection.switchRegion(s.draft.budget, to: r)
            return []

        case (.question(let i), .next), (.question(let i), .skipQuestion):
            guard let q = s.currentQuestion else { return [] }
            var effects: [OnboardingEffect] = []
            if action == .skipQuestion { q.clear(&s.draft) }
            let n = q.answerCount(s.draft)
            effects.append(.track(n > 0 ? .onboardingQuestionAnswered(question: q.rawValue, answerCount: n)
                                        : .onboardingQuestionSkipped(question: q.rawValue)))
            if i + 1 < OnboardingQuestion.count {
                s.stage = .question(i + 1)
                effects.append(viewed(i + 1))
            } else {
                s.lastQuestion = i
                s.stage = .saving
                effects.append(.save(s.payload))
            }
            return effects

        case (.question(let i), .back):
            s.stage = i == 0 ? .welcome : .question(i - 1)
            return i == 0 ? [] : [viewed(i - 1)]

        case (.welcome, .skipAll), (.question, .skipAll):
            s.skippedAll = true
            s.stage = .saving
            return [.save(nil)]

        case (.saving, .saveSucceeded):
            let effect = OnboardingEffect.track(.onboardingCompleted(answeredQuestions: s.skippedAll ? 0 : s.answeredQuestionCount,
                                                                     skippedAll: s.payload == nil))
            s.needsPreferences = false
            s.stage = s.payload == nil ? afterPreferences(s) : .reveal
            return [effect]

        case (.saving, .saveFailed):
            s.stage = .saveFailed
            return []

        case (.saveFailed, .retrySave):
            s.stage = .saving
            return [.save(s.payload)]

        case (.saveFailed, .back):
            // Edit an answer after a failure; "Skip all" is undone by going back.
            s.skippedAll = false
            s.stage = .question(s.lastQuestion)
            return [viewed(s.lastQuestion)]

        case (.saveFailed, .skipForNow):
            s.stage = afterPreferences(s)
            return []

        case (.reveal, .revealContinue):
            s.stage = afterPreferences(s)
            return []

        case (.settings, .settingsDone):
            s.needsSettings = false
            s.stage = .finished
            return []

        default:
            return []
        }
    }

    private static func viewed(_ i: Int) -> OnboardingEffect {
        .track(.onboardingQuestionViewed(question: OnboardingQuestion.allCases[i].rawValue))
    }

    private static func afterPreferences(_ s: OnboardingFlowState) -> OnboardingStage {
        s.needsSettings ? .settings : .finished
    }
}

// MARK: - Draft persistence (device-local, per account)

/// Keeps an unfinished questionnaire across relaunches. Device-local
/// UserDefaults only, keyed per account, cleared on completion and sign-out;
/// never synced anywhere. Only answers and position are stored.
struct OnboardingDraftStore {
    var defaults: UserDefaults = .standard

    private func key(_ uid: UUID) -> String { "banbe.onboardingDraft.v1.\(uid.uuidString)" }

    func save(_ state: OnboardingFlowState, uid: UUID) {
        // Only an in-progress questionnaire is worth resuming.
        switch state.stage {
        case .question, .saveFailed:
            if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key(uid)) }
        case .welcome, .saving, .reveal, .settings, .finished:
            break
        }
    }

    func load(uid: UUID) -> OnboardingFlowState? {
        guard let data = defaults.data(forKey: key(uid)) else { return nil }
        return try? JSONDecoder().decode(OnboardingFlowState.self, from: data)
    }

    func clear(uid: UUID) { defaults.removeObject(forKey: key(uid)) }

    /// Fresh state from the SERVER flags, with a saved draft folded in only
    /// while the questions are still owed (the server always wins).
    func resume(uid: UUID?, needsPreferences: Bool, needsSettings: Bool, region: BudgetRegion) -> OnboardingFlowState {
        var s = OnboardingFlowState.initial(needsPreferences: needsPreferences, needsSettings: needsSettings, region: region)
        guard needsPreferences, let uid, let saved = load(uid: uid) else { return s }
        s.draft = saved.draft
        s.region = saved.region
        switch saved.stage {
        case .question(let i) where OnboardingQuestion.allCases.indices.contains(i): s.stage = .question(i)
        case .saveFailed: s.stage = .question(saved.lastQuestion)
        default: break
        }
        return s
    }
}

// MARK: - What the answers change (reveal copy, derived from ForYou's rules)

struct PreferenceImpact: Equatable {
    enum Kind: Equatable { case filter, ranking, savedOnly }
    let kind: Kind
    let text: String
}

enum PreferenceImpacts {
    /// One line per answered question, stating exactly what the For You
    /// matcher (Lib/ForYou.swift) does with it — no more, no less.
    static func lines(_ p: EventPreferences, vi: Bool) -> [PreferenceImpact] {
        func names(_ ids: [String], _ opts: [PrefOption]) -> String {
            ids.map { EventPrefTaxonomy.label($0, in: opts, vi: vi) }.joined(separator: ", ")
        }
        var out: [PreferenceImpact] = []
        let interests = p.declaredInterests
        if !interests.isEmpty {
            let n = names(interests, EventPrefTaxonomy.interests)
            out.append(.init(kind: .filter, text: vi ? "Chỉ gợi ý: \(n)" : "Only suggests: \(n)"))
        }
        if let b = p.budget {
            let region = BudgetRegion.forCurrency(b.currency)
            switch b.tier {
            case "free":
                out.append(.init(kind: .filter, text: vi ? "Chỉ sự kiện miễn phí" : "Free events only"))
            case "low", "medium":
                let cap = region.cap(tier: b.tier) ?? 0
                let money = region == .vn ? EventLabels.vnd(cap) : "$\(cap)"
                out.append(.init(kind: .filter, text: vi
                    ? "Ẩn sự kiện giá trên \(money) (khi so được cùng loại tiền)"
                    : "Hides events over \(money) (when the price is in the same currency)"))
            default: break
            }
        }
        let goals = p.declaredGoals
        if !goals.isEmpty {
            let n = names(goals, EventPrefTaxonomy.goals)
            out.append(.init(kind: .ranking, text: vi ? "Ưu tiên sự kiện hợp với: \(n)" : "Ranks higher what suits: \(n)"))
        }
        let avail = p.declaredAvailability
        if !avail.isEmpty {
            let n = names(avail, EventPrefTaxonomy.availability)
            out.append(.init(kind: .ranking, text: vi
                ? "Ưu tiên giờ \(n), giờ khác vẫn hiện nhưng xếp sau"
                : "Prefers \(n); other times still show, just lower"))
        }
        if !EventPreferences.concrete(p.languages).isEmpty {
            out.append(.init(kind: .savedOnly, text: vi
                ? "Ngôn ngữ đã lưu. Sự kiện chưa ghi ngôn ngữ nên chưa dùng để lọc."
                : "Languages saved. Events don't list a language yet, so this doesn't filter."))
        }
        return out
    }
}

import Foundation

// Post-signup personalization flow, onboarding v5 — the pure part (state machine, draft persistence, the
// "For You is never empty" reveal plan, live option counts, "what your answers change" copy). No SwiftUI, no
// network: covered by BanbeAppTests/OnboardingFlowTests.swift. The screens live in Views/OnboardingFlowViews.swift.
// Prototype: docs/prototypes/banbe-onboarding-v5-standalone.html, decisions in .claude/notes/80-onboarding-v5-ios.md.
//
// Welcome → 3 questions (interests, when, budget) → save → your For You → one choice per screen (only when the
// settings step is owed) → recap with the tour offer → Home (or the chaptered tour).
//
// Server contract unchanged (migration 162, note 34): finishing the questions calls
// `complete_preferences_onboarding(p_preferences)` (nil = skipped everything, marker only); the choices end with
// `complete_settings_onboarding`. Answers stay owner-only.

enum OnboardingQuestion: String, CaseIterable, Codable {
    case goals, interests, availability, budget, languages

    /// The questions onboarding asks, in order. Goals overlap interests and languages don't filter anything yet,
    /// so both stay in Account › Event preferences only.
    static let flow: [OnboardingQuestion] = [.interests, .availability, .budget]
    static var count: Int { flow.count }

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

/// One choice per screen. Each one writes a real, existing setting; a choice whose setting can't be changed right
/// now is never shown (decided once, when the flow starts).
enum OnboardingConsent: String, Codable, CaseIterable {
    /// iOS notification permission. Only offered while iOS has never asked and push is live in this build.
    case push
    /// Weekly digest (`set_my_digest_opt_in`, migration 200). Only while the `weekly_digest` switch is on.
    case digest
    /// Hosting mode (`set_organizer_mode`). Not offered to someone already in hosting mode.
    case hosting

    /// The screen before a system alert offers one action (Apple HIG); banbe's own switches get Continue/Not now.
    var asksSystem: Bool { self == .push }
}

enum OnboardingStage: Equatable, Codable {
    case welcome
    case question(Int)
    case saving
    case saveFailed
    case reveal
    case consent(Int)
    case settingsSaving
    case settingsFailed
    case recap
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
    /// Server says the questions are still owed.
    var needsPreferences: Bool
    /// Server says the settings step (now the one-choice screens) is still owed.
    var needsSettings: Bool
    /// The choice screens this run shows, in order.
    var consents: [OnboardingConsent] = []
    /// What each shown choice ended as (OnboardingConsent.rawValue → on). Push = what iOS answered.
    var choices: [String: Bool] = [:]
    /// "Skip all": nothing is saved and there is nothing to reveal.
    var skippedAll = false
    /// Back from the save-failed screen returns here.
    var lastQuestion = OnboardingQuestion.count - 1
    /// The recap's "Start the tour" was pressed.
    var tourRequested = false

    var budgetRegion: BudgetRegion { BudgetRegion(rawValue: region) ?? .vn }

    var currentQuestion: OnboardingQuestion? {
        if case .question(let i) = stage, OnboardingQuestion.flow.indices.contains(i) {
            return OnboardingQuestion.flow[i]
        }
        return nil
    }

    var currentConsent: OnboardingConsent? {
        if case .consent(let i) = stage, consents.indices.contains(i) { return consents[i] }
        return nil
    }

    /// What `complete_preferences_onboarding` receives: nil = skipped everything.
    var payload: EventPreferences? {
        let p = draft.normalizedForSave()
        return skippedAll || p.isEmpty ? nil : p
    }

    var answeredQuestionCount: Int {
        let p = draft.normalizedForSave()
        return OnboardingQuestion.flow.filter { $0.answerCount(p) > 0 }.count
    }

    static func initial(needsPreferences: Bool, needsSettings: Bool, region: BudgetRegion,
                        consents: [OnboardingConsent] = []) -> OnboardingFlowState {
        let stage: OnboardingStage
        if needsPreferences { stage = .welcome }
        else if needsSettings { stage = consents.isEmpty ? .settingsSaving : .consent(0) }
        else { stage = .finished }
        return OnboardingFlowState(stage: stage, region: region.rawValue, needsPreferences: needsPreferences,
                                   needsSettings: needsSettings, consents: consents)
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
    /// "Change my answers" on the reveal: back to the first question, answers kept.
    case redoAnswers
    /// The choice screen's outcome, after its setting was written (or iOS answered).
    case consentAnswered(OnboardingConsent, Bool)
    case settingsSucceeded
    case settingsFailed
    case retrySettings
    /// After a failed settings marker: on to the recap for this session only.
    case skipSettingsForNow
    case startTour
    case skipTour
}

enum OnboardingEffect: Equatable {
    case save(EventPreferences?)
    case completeSettings
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
            if s.payload != nil {
                s.stage = .reveal
                return [effect]
            }
            return [effect] + toChoices(&s)

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
            return toChoices(&s)

        case (.reveal, .revealContinue):
            return toChoices(&s)

        case (.reveal, .redoAnswers):
            s.skippedAll = false
            s.stage = .question(0)
            return [viewed(0)]

        case (.consent(let i), .consentAnswered(let kind, let on)):
            guard s.consents.indices.contains(i), s.consents[i] == kind else { return [] }
            s.choices[kind.rawValue] = on
            if i + 1 < s.consents.count {
                s.stage = .consent(i + 1)
                return []
            }
            s.stage = .settingsSaving
            return [.completeSettings]

        case (.settingsSaving, .settingsSucceeded):
            s.needsSettings = false
            s.stage = .recap
            return []

        case (.settingsSaving, .settingsFailed):
            s.stage = .settingsFailed
            return []

        case (.settingsFailed, .retrySettings):
            s.stage = .settingsSaving
            return [.completeSettings]

        case (.settingsFailed, .skipSettingsForNow):
            s.stage = .recap
            return []

        case (.recap, .startTour):
            s.tourRequested = true
            s.stage = .finished
            return []

        case (.recap, .skipTour):
            s.stage = .finished
            return []

        default:
            return []
        }
    }

    private static func viewed(_ i: Int) -> OnboardingEffect {
        .track(.onboardingQuestionViewed(question: OnboardingQuestion.flow[i].rawValue))
    }

    /// After the questions (and the reveal): the choice screens when the settings step is owed, else the recap.
    private static func toChoices(_ s: inout OnboardingFlowState) -> [OnboardingEffect] {
        guard s.needsSettings else {
            s.stage = .recap
            return []
        }
        if s.consents.isEmpty {
            s.stage = .settingsSaving
            return [.completeSettings]
        }
        s.stage = .consent(0)
        return []
    }
}

// MARK: - Draft persistence (device-local, per account)

/// Keeps an unfinished questionnaire across relaunches. Device-local
/// UserDefaults only, keyed per account, cleared on completion and sign-out;
/// never synced anywhere. Only answers and position are stored.
struct OnboardingDraftStore {
    var defaults: UserDefaults = .standard

    // v2: question indices changed with the 3-question flow, so a 5-question draft is never resumed.
    private func key(_ uid: UUID) -> String { "banbe.onboardingDraft.v2.\(uid.uuidString)" }

    func save(_ state: OnboardingFlowState, uid: UUID) {
        // Only an in-progress questionnaire is worth resuming.
        switch state.stage {
        case .question, .saveFailed:
            if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key(uid)) }
        case .welcome, .saving, .reveal, .consent, .settingsSaving, .settingsFailed, .recap, .finished:
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
    func resume(uid: UUID?, needsPreferences: Bool, needsSettings: Bool, region: BudgetRegion,
                consents: [OnboardingConsent] = []) -> OnboardingFlowState {
        var s = OnboardingFlowState.initial(needsPreferences: needsPreferences, needsSettings: needsSettings,
                                            region: region, consents: consents)
        guard needsPreferences, let uid, let saved = load(uid: uid) else { return s }
        s.draft = saved.draft
        s.region = saved.region
        switch saved.stage {
        case .question(let i) where OnboardingQuestion.flow.indices.contains(i): s.stage = .question(i)
        case .saveFailed: s.stage = .question(min(saved.lastQuestion, OnboardingQuestion.count - 1))
        default: break
        }
        return s
    }
}

// MARK: - Live counts and the reveal plan (For You is never empty)

/// How the reveal fills For You. Web twin: none yet (iOS first, note 80).
enum RevealMode: String, Equatable {
    /// 3+ upcoming events fit the answers.
    case picked
    /// Fewer than 3 fit: exact matches first, then more of the same types, then the soonest events.
    case topped
    /// Every picked type has nothing on right now: the soonest events fill in, and those types are watched.
    case soon
    /// Interests skipped: the soonest events, labelled as not personal yet.
    case popular
}

struct RevealPlan: Equatable {
    let mode: RevealMode
    /// Event keys to show, best first.
    let keys: [String]
    /// How many upcoming events fit every answer.
    let exact: Int
    /// Picked types that have events on now / that have none.
    let live: [String]
    let waiting: [String]
}

/// The same rules as `ForYou.match` (interests and budget exclude, time is compared in the event's own zone),
/// used to count what each answer would leave, and to plan the reveal. Unknown data never excludes.
enum OnboardingCounts {
    static let minimum = 3
    static let tileMax = 5

    /// Discoverable, not started yet, soonest first (key breaks ties, so the order is total).
    static func upcoming(_ events: [ForYouCandidate], now: Date = Date()) -> [ForYouCandidate] {
        events.filter { $0.isBookable && ($0.startsAt.map { $0 >= now } ?? true) }
            .sorted { a, b in
                let sa = a.startsAt ?? .distantFuture, sb = b.startsAt ?? .distantFuture
                return sa != sb ? sa < sb : a.key < b.key
            }
    }

    /// Upcoming events per interest id (an event with two types counts for both).
    static func typeCounts(_ events: [ForYouCandidate], now: Date = Date()) -> [String: Int] {
        let known = Set(EventPrefTaxonomy.interests.map(\.id))
        var out: [String: Int] = [:]
        for e in upcoming(events, now: now) {
            for c in Set(e.categories) where known.contains(c) { out[c, default: 0] += 1 }
        }
        return out
    }

    /// The question's tiles: only types with events on now, most first, at most five (no placeholders).
    static func tileTypes(_ counts: [String: Int], label: (String) -> String) -> [String] {
        counts.filter { $0.value > 0 }
            .sorted { a, b in a.value != b.value ? a.value > b.value : label(a.key) < label(b.key) }
            .prefix(tileMax).map(\.key)
    }

    static func fitsInterests(_ e: ForYouCandidate, _ interests: [String]) -> Bool {
        guard !interests.isEmpty else { return true }
        let known = e.categories.filter { c in EventPrefTaxonomy.interests.contains { $0.id == c } }
        return known.isEmpty || known.contains(where: interests.contains)
    }

    static func fitsBudget(_ e: ForYouCandidate, _ b: BudgetPref?) -> Bool {
        guard let b else { return true }
        if b.tier == "free" { return e.isFree }
        if e.isFree { return true }
        let region = BudgetRegion.forCurrency(b.currency)
        guard let cap = region.cap(tier: b.tier), let amount = e.priceAmount, let cur = e.priceCurrency,
              cur == region.currency else { return true }
        return amount <= cap
    }

    /// Day (weekdays/weekends) and time (daytime/evening) are separate groups; each picked group must fit.
    static func fitsAvailability(_ e: ForYouCandidate, _ ids: [String]) -> Bool {
        let picked = EventPreferences.concrete(ids)
        guard !picked.isEmpty, let s = e.startsAt, let tz = e.timeZone else { return true }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let weekday = cal.component(.weekday, from: s)
        let isWeekend = weekday == 1 || weekday == 7
        let isDaytime = cal.component(.hour, from: s) < 17
        let days = picked.filter { $0 == "weekdays" || $0 == "weekends" }
        let times = picked.filter { $0 == "daytime" || $0 == "evening" }
        if !days.isEmpty && !days.contains(isWeekend ? "weekends" : "weekdays") { return false }
        if !times.isEmpty && !times.contains(isDaytime ? "daytime" : "evening") { return false }
        return true
    }

    /// Upcoming events that fit every answer so far.
    static func matchCount(_ events: [ForYouCandidate], _ p: EventPreferences, now: Date = Date()) -> Int {
        let interests = p.declaredInterests, avail = p.availability ?? []
        return upcoming(events, now: now).filter {
            fitsInterests($0, interests) && fitsBudget($0, p.budget) && fitsAvailability($0, avail)
        }.count
    }

    /// The count next to one option: the answers so far with this option as the question's only answer.
    static func optionCount(_ events: [ForYouCandidate], _ p: EventPreferences, question: OnboardingQuestion,
                            option: String, region: BudgetRegion, now: Date = Date()) -> Int {
        var q = p
        switch question {
        case .availability: q.availability = [option]
        case .budget: q.budget = PrefSelection.pickBudget(nil, tier: option, region: region)
        case .interests: q.interests = [option]
        case .goals, .languages: break
        }
        return matchCount(events, q, now: now)
    }

    /// What the reveal shows. Never empty while any upcoming event exists.
    static func reveal(_ events: [ForYouCandidate], prefs: EventPreferences, now: Date = Date()) -> RevealPlan {
        let up = upcoming(events, now: now)
        let counts = typeCounts(up, now: now)
        let chosen = prefs.declaredInterests
        let live = chosen.filter { (counts[$0] ?? 0) > 0 }
        let waiting = chosen.filter { (counts[$0] ?? 0) == 0 }
        func filled(_ first: [String], upTo n: Int) -> [String] {
            var keys = first
            for e in up where keys.count < n && !keys.contains(e.key) { keys.append(e.key) }
            return Array(keys.prefix(n))
        }
        if live.isEmpty {
            var rest = prefs
            rest.interests = nil
            let ranked = ForYou.rank(up, prefs: rest, now: now).map(\.key)
            return RevealPlan(mode: chosen.isEmpty ? .popular : .soon, keys: filled(ranked, upTo: tileMax),
                              exact: 0, live: [], waiting: waiting)
        }
        let exact = ForYou.rank(up, prefs: prefs, now: now).map(\.key)
        if exact.count >= minimum {
            return RevealPlan(mode: .picked, keys: Array(exact.prefix(tileMax)), exact: exact.count,
                              live: live, waiting: waiting)
        }
        let same = ForYou.rank(up, prefs: EventPreferences(interests: live), now: now).map(\.key)
            .filter { !exact.contains($0) }
        return RevealPlan(mode: .topped, keys: filled(exact + same, upTo: minimum + 2), exact: exact.count,
                          live: live, waiting: waiting)
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
                : "Prefers \(n). Other times still show, just lower"))
        }
        if !EventPreferences.concrete(p.languages).isEmpty {
            out.append(.init(kind: .savedOnly, text: vi
                ? "Ngôn ngữ đã lưu. Sự kiện chưa ghi ngôn ngữ nên chưa dùng để lọc."
                : "Languages saved. Events don't list a language yet, so this doesn't filter."))
        }
        return out
    }
}


// MARK: - Live feedback under a question (note 53)

enum OnboardingFeedback {
    /// One short line that answers each tap ("🎵 🍽️ · only these kinds get the ★"), so picking feels like it does
    /// something before the reveal. Never says more than the reveal's impact lines. nil when nothing is picked.
    /// Web twin: `selectionFeedback` in src/lib/onboardingFlow.js (same strings; tests mirrored).
    static func line(_ question: OnboardingQuestion, picked: [String], vi: Bool) -> String? {
        guard !picked.isEmpty else { return nil }
        if picked.contains(EventPrefTaxonomy.noPreference) { return vi ? "🤷 · Câu này không lọc gì cả" : "🤷 · Nothing filtered here" }
        let faces = picked.map(PrefEmoji.of).joined(separator: " ")
        switch question {
        case .interests: return "\(faces) · " + (vi ? "chỉ những loại này được gắn ★" : "only these kinds get the ★")
        case .goals: return "\(faces) · " + (vi ? "sự kiện hợp sẽ được xếp lên trước" : "we'll rank events like this higher")
        case .availability: return "\(faces) · " + (vi ? "giờ khác vẫn hiện, chỉ xếp sau" : "other times still show, just lower")
        case .budget:
            let tail: String
            switch picked[0] {
            case "flexible": tail = vi ? "không giới hạn giá" : "no price limit"
            case "free": tail = vi ? "chỉ sự kiện miễn phí" : "free events only"
            default: tail = vi ? "ẩn sự kiện vượt mức này" : "hides events above this"
            }
            return "\(faces) · " + tail
        case .languages: return "\(faces) · " + (vi ? "đã lưu, chưa dùng để lọc" : "saved, doesn't filter yet")
        }
    }
}

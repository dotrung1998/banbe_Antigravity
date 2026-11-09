import XCTest
@testable import BanbeApp

final class OnboardingFlowTests: XCTestCase {

    private func fresh(settings: Bool = false, consents: [OnboardingConsent] = []) -> OnboardingFlowState {
        .initial(needsPreferences: true, needsSettings: settings, region: .vn, consents: consents)
    }

    private func saves(_ effects: [OnboardingEffect]) -> [EventPreferences?] {
        effects.compactMap { if case .save(let p) = $0 { return p } else { return nil } }
    }
    private func tracked(_ effects: [OnboardingEffect]) -> [AnalyticsEvent] {
        effects.compactMap { if case .track(let e) = $0 { return e } else { return nil } }
    }

    /// Answers all three questions with `next` (nothing picked) and lands on `.saving`.
    private func finishQuestions(_ s: inout OnboardingFlowState) -> [OnboardingEffect] {
        var last: [OnboardingEffect] = []
        while s.currentQuestion != nil { last = OnboardingFlow.reduce(&s, .next) }
        return last
    }

    // MARK: initial stage from server flags

    func testInitialStageFollowsServerFlags() {
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: true, needsSettings: true, region: .vn).stage, .welcome)
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: false, needsSettings: true, region: .vn, consents: [.hosting]).stage,
                       .consent(0))
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: false, needsSettings: true, region: .vn).stage, .settingsSaving,
                       "settings owed with nothing to ask: only the marker is written")
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: false, needsSettings: false, region: .vn).stage, .finished)
    }

    // MARK: question order, back, skip

    func testThreeQuestionsInOrder() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        var seen: [OnboardingQuestion] = []
        while let q = s.currentQuestion {
            seen.append(q)
            OnboardingFlow.reduce(&s, .next)
        }
        XCTAssertEqual(seen, [.interests, .availability, .budget], "goals and languages are no longer asked")
        XCTAssertEqual(OnboardingQuestion.count, 3)
        XCTAssertEqual(s.stage, .saving)
    }

    func testBackWalksToWelcomeAndKeepsAnswers() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        OnboardingFlow.reduce(&s, .next)
        XCTAssertEqual(s.currentQuestion, .availability)
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.currentQuestion, .interests)
        XCTAssertEqual(s.draft.interests, ["music"], "Back never discards an answer")
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.stage, .welcome)
    }

    func testSkipQuestionClearsOnlyThatAnswer() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        OnboardingFlow.reduce(&s, .next)
        OnboardingFlow.reduce(&s, .toggle(.availability, "weekends"))
        let effects = OnboardingFlow.reduce(&s, .skipQuestion)
        XCTAssertNil(s.draft.availability)
        XCTAssertEqual(s.draft.interests, ["music"])
        XCTAssertEqual(tracked(effects).first, .onboardingQuestionSkipped(question: "availability"))
    }

    func testNoPreferenceIsExclusiveAndMultiSelectWorks() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        OnboardingFlow.reduce(&s, .toggle(.interests, "gallery"))
        XCTAssertEqual(s.draft.interests, ["music", "gallery"])
        OnboardingFlow.reduce(&s, .toggle(.interests, EventPrefTaxonomy.noPreference))
        XCTAssertEqual(s.draft.interests, [EventPrefTaxonomy.noPreference])
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        XCTAssertEqual(s.draft.interests, ["music"])
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        XCTAssertNil(s.draft.interests, "deselecting the last option means skipped")
    }

    func testBudgetKeepsVndUsdBehaviour() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .pickBudget("low"))
        XCTAssertEqual(s.draft.budget, BudgetPref(tier: "low", currency: "VND"))
        OnboardingFlow.reduce(&s, .setRegion(.us))
        XCTAssertEqual(s.draft.budget, BudgetPref(tier: "low", currency: "USD"))
        OnboardingFlow.reduce(&s, .pickBudget("free"))
        XCTAssertEqual(s.draft.budget, BudgetPref(tier: "free", currency: nil))
        OnboardingFlow.reduce(&s, .pickBudget("free"))
        XCTAssertNil(s.draft.budget)
    }

    // MARK: saving

    func testFinishingSavesNormalizedAnswersThenReveals() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        let effects = finishQuestions(&s)
        XCTAssertEqual(saves(effects), [EventPreferences(interests: ["music"])])
        let done = OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .reveal)
        XCTAssertFalse(s.needsPreferences)
        XCTAssertEqual(tracked(done), [.onboardingCompleted(answeredQuestions: 1, skippedAll: false)])
    }

    func testAllQuestionsSkippedSavesMarkerOnlyAndSkipsReveal() {
        var s = fresh(settings: true, consents: [.hosting])
        OnboardingFlow.reduce(&s, .start)
        var last: [OnboardingEffect] = []
        while s.currentQuestion != nil { last = OnboardingFlow.reduce(&s, .skipQuestion) }
        XCTAssertEqual(saves(last), [nil], "nothing answered = marker only, no invented answers")
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .consent(0))
    }

    func testSkipAllFromWelcomeEndsOnTheRecap() {
        var s = fresh()
        let effects = OnboardingFlow.reduce(&s, .skipAll)
        XCTAssertEqual(saves(effects), [nil])
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .recap, "the recap still offers the tour")
        OnboardingFlow.reduce(&s, .skipTour)
        XCTAssertEqual(s.stage, .finished)
        XCTAssertFalse(s.tourRequested)
    }

    func testSkipAllDiscardsDraftAnswersFromPayload() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        XCTAssertEqual(saves(OnboardingFlow.reduce(&s, .skipAll)), [nil])
    }

    func testSaveFailureRetryBackAndSkipForNow() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        _ = finishQuestions(&s)
        OnboardingFlow.reduce(&s, .saveFailed)
        XCTAssertEqual(s.stage, .saveFailed)
        XCTAssertTrue(s.needsPreferences, "a failed save never counts as done")

        XCTAssertEqual(saves(OnboardingFlow.reduce(&s, .retrySave)), [EventPreferences(interests: ["music"])])
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.currentQuestion, .budget)
        XCTAssertEqual(s.draft.interests, ["music"])

        OnboardingFlow.reduce(&s, .next)
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .skipForNow)
        XCTAssertEqual(s.stage, .recap)
    }

    func testLateOrDuplicateActionsAreIgnored() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .skipAll)
        XCTAssertTrue(OnboardingFlow.reduce(&s, .skipAll).isEmpty, "double tap cannot save twice")
        OnboardingFlow.reduce(&s, .saveSucceeded)
        let before = s
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .back)
        OnboardingFlow.reduce(&s, .consentAnswered(.hosting, true))
        XCTAssertEqual(s, before, "nothing moves backwards past a successful save")
    }

    // MARK: reveal → choices → recap

    func testRevealThenOneChoicePerScreenThenRecap() {
        var s = fresh(settings: true, consents: [.push, .digest, .hosting])
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        _ = finishQuestions(&s)
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .reveal)
        OnboardingFlow.reduce(&s, .revealContinue)
        XCTAssertEqual(s.currentConsent, .push)
        XCTAssertTrue(OnboardingFlow.reduce(&s, .consentAnswered(.digest, true)).isEmpty, "an answer for another screen is ignored")
        XCTAssertEqual(s.stage, .consent(0))
        OnboardingFlow.reduce(&s, .consentAnswered(.push, false))
        OnboardingFlow.reduce(&s, .consentAnswered(.digest, false))
        let last = OnboardingFlow.reduce(&s, .consentAnswered(.hosting, true))
        XCTAssertEqual(last, [.completeSettings], "the settings marker follows the last choice")
        XCTAssertEqual(s.stage, .settingsSaving)
        XCTAssertEqual(s.choices, ["push": false, "digest": false, "hosting": true])
        OnboardingFlow.reduce(&s, .settingsSucceeded)
        XCTAssertFalse(s.needsSettings)
        XCTAssertEqual(s.stage, .recap)
        OnboardingFlow.reduce(&s, .startTour)
        XCTAssertEqual(s.stage, .finished)
        XCTAssertTrue(s.tourRequested)
    }

    func testOnlySystemAskedChoiceHasOneAction() {
        XCTAssertTrue(OnboardingConsent.push.asksSystem)
        XCTAssertFalse(OnboardingConsent.digest.asksSystem)
        XCTAssertFalse(OnboardingConsent.hosting.asksSystem)
    }

    func testRevealWithoutOwedSettingsGoesStraightToRecap() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        _ = finishQuestions(&s)
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertTrue(OnboardingFlow.reduce(&s, .revealContinue).isEmpty)
        XCTAssertEqual(s.stage, .recap)
    }

    func testSettingsOwedWithNothingToAskWritesTheMarker() {
        var s = fresh(settings: true)
        OnboardingFlow.reduce(&s, .skipAll)
        XCTAssertEqual(OnboardingFlow.reduce(&s, .saveSucceeded).last, .completeSettings)
        XCTAssertEqual(s.stage, .settingsSaving)
    }

    func testSettingsFailureRetryAndSkipForNow() {
        var s = OnboardingFlowState.initial(needsPreferences: false, needsSettings: true, region: .vn, consents: [.hosting])
        XCTAssertEqual(OnboardingFlow.reduce(&s, .consentAnswered(.hosting, false)), [.completeSettings])
        OnboardingFlow.reduce(&s, .settingsFailed)
        XCTAssertEqual(s.stage, .settingsFailed)
        XCTAssertEqual(OnboardingFlow.reduce(&s, .retrySettings), [.completeSettings])
        OnboardingFlow.reduce(&s, .settingsFailed)
        OnboardingFlow.reduce(&s, .skipSettingsForNow)
        XCTAssertEqual(s.stage, .recap)
        XCTAssertTrue(s.needsSettings, "a failed marker never counts as done")
    }

    func testChangeMyAnswersFromTheReveal() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        _ = finishQuestions(&s)
        OnboardingFlow.reduce(&s, .saveSucceeded)
        OnboardingFlow.reduce(&s, .redoAnswers)
        XCTAssertEqual(s.currentQuestion, .interests)
        XCTAssertEqual(s.draft.interests, ["music"], "answers are kept to edit")
        OnboardingFlow.reduce(&s, .toggle(.interests, "gallery"))
        XCTAssertEqual(saves(finishQuestions(&s)), [EventPreferences(interests: ["music", "gallery"])])
    }

    // MARK: analytics privacy

    func testAnalyticsCarriesIdsAndCountsNeverValues() {
        var s = fresh()
        var events: [AnalyticsEvent] = []
        events += tracked(OnboardingFlow.reduce(&s, .start))
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        OnboardingFlow.reduce(&s, .toggle(.interests, "gallery"))
        events += tracked(OnboardingFlow.reduce(&s, .next))
        XCTAssertTrue(events.contains(.onboardingQuestionAnswered(question: "interests", answerCount: 2)))
        let allProps = events.flatMap { $0.properties.values }
        XCTAssertFalse(allProps.contains { $0.contains("music") || $0.contains("gallery") })
        XCTAssertEqual(events.first?.name, "onboarding_started")
    }

    func testMatchBuckets() {
        XCTAssertEqual(AnalyticsEvent.bucket(0), "0")
        XCTAssertEqual(AnalyticsEvent.bucket(2), "1-2")
        XCTAssertEqual(AnalyticsEvent.bucket(5), "3-5")
        XCTAssertEqual(AnalyticsEvent.bucket(10), "6-10")
        XCTAssertEqual(AnalyticsEvent.bucket(400), "11+")
    }

    func testTrackFirstFiresOncePerAccount() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.analytics.\(UUID().uuidString)"))
        let sink = RecordingAnalyticsSink()
        let previous = Analytics.sink
        Analytics.sink = sink
        defer { Analytics.sink = previous }
        let a = UUID(), b = UUID()
        Analytics.trackFirst(.firstEventSaved, userID: a, defaults: defaults)
        Analytics.trackFirst(.firstEventSaved, userID: a, defaults: defaults)
        Analytics.trackFirst(.firstEventSaved, userID: b, defaults: defaults)
        Analytics.trackFirst(.firstEventSaved, userID: nil, defaults: defaults)
        XCTAssertEqual(sink.events, [.firstEventSaved, .firstEventSaved])
    }

    // MARK: draft persistence

    func testDraftResumesWhileOwedAndServerWins() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.draft.\(UUID().uuidString)"))
        let store = OnboardingDraftStore(defaults: defaults)
        let uid = UUID()
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        OnboardingFlow.reduce(&s, .next)
        store.save(s, uid: uid)

        let resumed = store.resume(uid: uid, needsPreferences: true, needsSettings: false, region: .us)
        XCTAssertEqual(resumed.stage, .question(1))
        XCTAssertEqual(resumed.draft.interests, ["music"])

        let done = store.resume(uid: uid, needsPreferences: false, needsSettings: true, region: .vn, consents: [.hosting])
        XCTAssertEqual(done.stage, .consent(0), "server says done: the local draft is ignored")
        XCTAssertNil(done.draft.interests)

        XCTAssertEqual(store.resume(uid: UUID(), needsPreferences: true, needsSettings: false, region: .vn).stage,
                       .welcome, "drafts are per account")
        store.clear(uid: uid)
        XCTAssertNil(store.load(uid: uid))
    }

    func testSaveFailedDraftResumesAtLastQuestion() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.draft.\(UUID().uuidString)"))
        let store = OnboardingDraftStore(defaults: defaults)
        let uid = UUID()
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        _ = finishQuestions(&s)
        OnboardingFlow.reduce(&s, .saveFailed)
        store.save(s, uid: uid)
        XCTAssertEqual(store.resume(uid: uid, needsPreferences: true, needsSettings: false, region: .vn).stage, .question(2))
    }

    // MARK: coordinator (real async boundaries)

    @MainActor
    func testCoordinatorSaveFailureThenSuccess() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.coord.\(UUID().uuidString)"))
        var attempts = 0
        var received: [EventPreferences?] = []
        let flow = OnboardingCoordinator(state: fresh(), uid: UUID(), store: OnboardingDraftStore(defaults: defaults)) { p in
            attempts += 1
            received.append(p)
            return attempts > 1
        }
        flow.send(.start)
        flow.send(.toggle(.interests, "gallery"))
        for _ in 0..<OnboardingQuestion.count { flow.send(.next) }
        try await waitFor { flow.state.stage == .saveFailed }
        flow.send(.retrySave)
        try await waitFor { flow.state.stage == .reveal }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(received.last, EventPreferences(interests: ["gallery"]))
    }

    @MainActor
    func testCoordinatorChoicesWriteOnlyOnContinue() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.coord.\(UUID().uuidString)"))
        var applied: [OnboardingConsent] = []
        var markers = 0
        let state = OnboardingFlowState.initial(needsPreferences: false, needsSettings: true, region: .vn,
                                                consents: [.digest, .hosting])
        let flow = OnboardingCoordinator(state: state, uid: UUID(), store: OnboardingDraftStore(defaults: defaults),
                                         save: { _ in true },
                                         completeSettings: { markers += 1; return true },
                                         applyConsent: { kind in applied.append(kind); return kind == .hosting })
        flow.answer(false)
        XCTAssertEqual(flow.state.stage, .consent(1), "Not now writes nothing")
        flow.answer(true)
        try await waitFor { flow.state.stage == .recap }
        XCTAssertEqual(applied, [.hosting])
        XCTAssertEqual(markers, 1)
        XCTAssertEqual(flow.state.choices, ["digest": false, "hosting": true])
    }

    @MainActor
    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: live counts and the reveal plan (For You is never empty)

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ key: String, _ cat: String, days: Double, price: Int = 0, bookable: Bool = true) -> ForYouCandidate {
        ForYouCandidate(key: key, categories: [cat], priceAmount: price, priceCurrency: "VND", isFree: price == 0,
                        startsAt: now.addingTimeInterval(days * 86_400), timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh"),
                        isBookable: bookable)
    }

    func testTilesAreOnlyTypesWithEventsMostFirstAtMostFive() {
        let events = [event("a", "music", days: 1), event("b", "music", days: 2), event("c", "gallery", days: 3),
                      event("d", "fashion", days: 1, bookable: false), event("e", "film", days: -1)]
        let counts = OnboardingCounts.typeCounts(events, now: now)
        XCTAssertEqual(counts, ["music": 2, "gallery": 1], "sold out / past events never count")
        XCTAssertEqual(OnboardingCounts.tileTypes(counts, label: { $0 }), ["music", "gallery"])
        let many = Dictionary(uniqueKeysWithValues: (0..<9).map { ("t\($0)", 9 - $0) })
        XCTAssertEqual(OnboardingCounts.tileTypes(many, label: { $0 }).count, OnboardingCounts.tileMax)
    }

    func testOptionCountsFollowTheMatcherRules() {
        let events = [event("a", "music", days: 1), event("b", "music", days: 2, price: 500_000), event("c", "gallery", days: 3)]
        let p = EventPreferences(interests: ["music"])
        XCTAssertEqual(OnboardingCounts.matchCount(events, p, now: now), 2)
        XCTAssertEqual(OnboardingCounts.optionCount(events, p, question: .budget, option: "free", region: .vn, now: now), 1)
        XCTAssertEqual(OnboardingCounts.optionCount(events, p, question: .budget, option: "flexible", region: .vn, now: now), 2)
        XCTAssertEqual(OnboardingCounts.optionCount(events, p, question: .budget, option: "low", region: .vn, now: now), 1,
                       "low caps at 200.000₫")
    }

    func testRevealIsNeverEmpty() {
        let events = [event("a", "music", days: 1), event("b", "music", days: 2), event("c", "music", days: 3),
                      event("d", "gallery", days: 4), event("e", "supper", days: 5)]
        let picked = OnboardingCounts.reveal(events, prefs: EventPreferences(interests: ["music"]), now: now)
        XCTAssertEqual(picked.mode, .picked)
        XCTAssertEqual(picked.exact, 3)
        XCTAssertEqual(Set(picked.keys), ["a", "b", "c"])

        let topped = OnboardingCounts.reveal(events, prefs: EventPreferences(interests: ["gallery"]), now: now)
        XCTAssertEqual(topped.mode, .topped)
        XCTAssertEqual(topped.keys.first, "d", "exact matches stay first")
        XCTAssertEqual(topped.keys.count, OnboardingCounts.minimum + 2)

        let soon = OnboardingCounts.reveal(events, prefs: EventPreferences(interests: ["film"]), now: now)
        XCTAssertEqual(soon.mode, .soon)
        XCTAssertEqual(soon.waiting, ["film"])
        XCTAssertEqual(soon.keys.first, "a", "the soonest events fill in")

        let popular = OnboardingCounts.reveal(events, prefs: EventPreferences(), now: now)
        XCTAssertEqual(popular.mode, .popular)
        XCTAssertFalse(popular.keys.isEmpty)

        XCTAssertTrue(OnboardingCounts.reveal([], prefs: EventPreferences(interests: ["music"]), now: now).keys.isEmpty,
                      "only empty when nothing is on at all")
    }

    // MARK: reveal copy is honest about what the matcher does

    func testImpactLinesMirrorMatcherRules() {
        let p = EventPreferences(interests: ["music"], goals: ["learn"], availability: ["evening"],
                                 budget: BudgetPref(tier: "low", currency: "VND"), languages: ["en"])
        let lines = PreferenceImpacts.lines(p, vi: false)
        XCTAssertEqual(lines.map(\.kind), [.filter, .filter, .ranking, .ranking, .savedOnly])
        XCTAssertEqual(lines[0].text, "Only suggests: Music")
        XCTAssertTrue(lines[1].text.contains("200.000₫"))
        XCTAssertTrue(lines[4].text.contains("doesn't filter"))
    }

    func testNoPreferenceAnswersProduceNoImpactLines() {
        let p = EventPreferences(interests: [EventPrefTaxonomy.noPreference],
                                 budget: BudgetPref(tier: EventPrefTaxonomy.noPreference, currency: nil))
        XCTAssertTrue(PreferenceImpacts.lines(p, vi: true).isEmpty)
    }

    // MARK: For You matcher boundary used by the reveal

    func testRevealUsesRealMatcherZeroMatchesWhenInterestsExclude() {
        let soon = Date().addingTimeInterval(3 * 86_400)
        let fashion = ForYouCandidate(key: "f", categories: ["fashion"], priceAmount: 0, priceCurrency: "VND",
                                      isFree: true, startsAt: soon, timeZone: nil, isBookable: true)
        let music = ForYouCandidate(key: "m", categories: ["music"], priceAmount: 0, priceCurrency: "VND",
                                    isFree: true, startsAt: soon, timeZone: nil, isBookable: true)
        let prefs = EventPreferences(interests: ["music"])
        XCTAssertTrue(ForYou.rank([fashion], prefs: prefs).isEmpty)
        XCTAssertEqual(ForYou.rank([fashion, music], prefs: prefs).map(\.key), ["m"])
        let notBookable = ForYouCandidate(key: "x", categories: ["music"], priceAmount: 0, priceCurrency: "VND",
                                          isFree: true, startsAt: soon, timeZone: nil, isBookable: false)
        XCTAssertTrue(ForYou.rank([notBookable], prefs: prefs).isEmpty, "never recommends what can't be reserved")
    }

    // MARK: activation checklist

    func testChecklistVisibility() {
        var s = ActivationChecklistState()
        let items = ActivationChecklist.items(biometricsAvailable: false)
        XCTAssertEqual(items, [.openEvent, .saveEvent])
        XCTAssertFalse(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: false, faceIDEnabled: false))
        s.enabled = true
        XCTAssertTrue(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: false, faceIDEnabled: false))
        s.openedEvent = true
        XCTAssertTrue(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: true, faceIDEnabled: false),
                      "stays up once everything is done, for the one-time celebration")
        s.celebrated = true
        XCTAssertFalse(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: true, faceIDEnabled: false),
                       "hides after the celebration played")
        XCTAssertTrue(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: false, faceIDEnabled: false),
                      "un-saving the only event brings an unfinished checklist back")
        s.celebrated = false
        s.openedEvent = false
        s.dismissed = true
        XCTAssertFalse(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: false, faceIDEnabled: false))
    }

    func testChecklistStateDecodesWithoutCelebratedKey() throws {
        let old = Data(#"{"enabled":true,"dismissed":false,"openedEvent":true}"#.utf8)
        let s = try JSONDecoder().decode(ActivationChecklistState.self, from: old)
        XCTAssertEqual(s, ActivationChecklistState(enabled: true, dismissed: false, openedEvent: true, celebrated: false))
    }
}

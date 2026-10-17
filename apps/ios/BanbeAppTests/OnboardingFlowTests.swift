import XCTest
@testable import BanbeApp

final class OnboardingFlowTests: XCTestCase {

    private func fresh(settings: Bool = false) -> OnboardingFlowState {
        .initial(needsPreferences: true, needsSettings: settings, region: .vn)
    }

    private func saves(_ effects: [OnboardingEffect]) -> [EventPreferences?] {
        effects.compactMap { if case .save(let p) = $0 { return p } else { return nil } }
    }
    private func tracked(_ effects: [OnboardingEffect]) -> [AnalyticsEvent] {
        effects.compactMap { if case .track(let e) = $0 { return e } else { return nil } }
    }

    // MARK: initial stage from server flags

    func testInitialStageFollowsServerFlags() {
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: true, needsSettings: true, region: .vn).stage, .welcome)
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: false, needsSettings: true, region: .vn).stage, .settings)
        XCTAssertEqual(OnboardingFlowState.initial(needsPreferences: false, needsSettings: false, region: .vn).stage, .finished)
    }

    // MARK: question order, back, skip

    func testOneQuestionPerScreenInOrder() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        var seen: [OnboardingQuestion] = []
        while let q = s.currentQuestion {
            seen.append(q)
            OnboardingFlow.reduce(&s, .next)
        }
        XCTAssertEqual(seen, [.goals, .interests, .availability, .budget, .languages])
        XCTAssertEqual(s.stage, .saving)
    }

    func testBackWalksToWelcomeAndKeepsAnswers() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        OnboardingFlow.reduce(&s, .next)
        XCTAssertEqual(s.currentQuestion, .interests)
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.currentQuestion, .goals)
        XCTAssertEqual(s.draft.goals, ["learn"], "Back never discards an answer")
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.stage, .welcome)
    }

    func testSkipQuestionClearsOnlyThatAnswer() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        OnboardingFlow.reduce(&s, .next)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        let effects = OnboardingFlow.reduce(&s, .skipQuestion)
        XCTAssertNil(s.draft.interests)
        XCTAssertEqual(s.draft.goals, ["learn"])
        XCTAssertEqual(tracked(effects).first, .onboardingQuestionSkipped(question: "interests"))
    }

    func testNoPreferenceIsExclusiveAndMultiSelectWorks() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        OnboardingFlow.reduce(&s, .toggle(.goals, "meet_people"))
        XCTAssertEqual(s.draft.goals, ["learn", "meet_people"])
        OnboardingFlow.reduce(&s, .toggle(.goals, EventPrefTaxonomy.noPreference))
        XCTAssertEqual(s.draft.goals, [EventPrefTaxonomy.noPreference])
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        XCTAssertEqual(s.draft.goals, ["learn"])
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        XCTAssertNil(s.draft.goals, "deselecting the last option means skipped")
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
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        for _ in 0..<4 { OnboardingFlow.reduce(&s, .next) }
        let effects = OnboardingFlow.reduce(&s, .next)
        XCTAssertEqual(saves(effects), [EventPreferences(goals: ["learn"])])
        let done = OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .reveal)
        XCTAssertFalse(s.needsPreferences)
        XCTAssertEqual(tracked(done), [.onboardingCompleted(answeredQuestions: 1, skippedAll: false)])
    }

    func testAllQuestionsSkippedSavesMarkerOnlyAndSkipsReveal() {
        var s = fresh(settings: true)
        OnboardingFlow.reduce(&s, .start)
        var last: [OnboardingEffect] = []
        for _ in 0..<5 { last = OnboardingFlow.reduce(&s, .skipQuestion) }
        XCTAssertEqual(saves(last), [nil], "nothing answered = marker only, no invented answers")
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .settings)
    }

    func testSkipAllFromWelcome() {
        var s = fresh()
        let effects = OnboardingFlow.reduce(&s, .skipAll)
        XCTAssertEqual(saves(effects), [nil])
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .finished)
    }

    func testSkipAllDiscardsDraftAnswersFromPayload() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        XCTAssertEqual(saves(OnboardingFlow.reduce(&s, .skipAll)), [nil])
    }

    func testSaveFailureRetryBackAndSkipForNow() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.interests, "music"))
        for _ in 0..<5 { OnboardingFlow.reduce(&s, .next) }
        OnboardingFlow.reduce(&s, .saveFailed)
        XCTAssertEqual(s.stage, .saveFailed)
        XCTAssertTrue(s.needsPreferences, "a failed save never counts as done")

        XCTAssertEqual(saves(OnboardingFlow.reduce(&s, .retrySave)), [EventPreferences(interests: ["music"])])
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s.currentQuestion, .languages)
        XCTAssertEqual(s.draft.interests, ["music"])

        for _ in 0..<1 { OnboardingFlow.reduce(&s, .next) }
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .skipForNow)
        XCTAssertEqual(s.stage, .finished)
    }

    func testLateOrDuplicateActionsAreIgnored() {
        var s = fresh()
        OnboardingFlow.reduce(&s, .skipAll)
        XCTAssertTrue(OnboardingFlow.reduce(&s, .skipAll).isEmpty, "double tap cannot save twice")
        OnboardingFlow.reduce(&s, .saveSucceeded)
        let before = s
        OnboardingFlow.reduce(&s, .saveFailed)
        OnboardingFlow.reduce(&s, .back)
        XCTAssertEqual(s, before, "nothing moves backwards past a successful save")
    }

    func testRevealThenSettingsThenFinished() {
        var s = fresh(settings: true)
        OnboardingFlow.reduce(&s, .start)
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        for _ in 0..<5 { OnboardingFlow.reduce(&s, .next) }
        OnboardingFlow.reduce(&s, .saveSucceeded)
        XCTAssertEqual(s.stage, .reveal)
        OnboardingFlow.reduce(&s, .revealContinue)
        XCTAssertEqual(s.stage, .settings)
        OnboardingFlow.reduce(&s, .settingsDone)
        XCTAssertEqual(s.stage, .finished)
    }

    // MARK: analytics privacy

    func testAnalyticsCarriesIdsAndCountsNeverValues() {
        var s = fresh()
        var events: [AnalyticsEvent] = []
        events += tracked(OnboardingFlow.reduce(&s, .start))
        OnboardingFlow.reduce(&s, .toggle(.goals, "networking"))
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        events += tracked(OnboardingFlow.reduce(&s, .next))
        XCTAssertTrue(events.contains(.onboardingQuestionAnswered(question: "goals", answerCount: 2)))
        let allProps = events.flatMap { $0.properties.values }
        XCTAssertFalse(allProps.contains { $0.contains("networking") || $0.contains("learn") })
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
        OnboardingFlow.reduce(&s, .toggle(.goals, "learn"))
        OnboardingFlow.reduce(&s, .next)
        store.save(s, uid: uid)

        let resumed = store.resume(uid: uid, needsPreferences: true, needsSettings: false, region: .us)
        XCTAssertEqual(resumed.stage, .question(1))
        XCTAssertEqual(resumed.draft.goals, ["learn"])

        let done = store.resume(uid: uid, needsPreferences: false, needsSettings: true, region: .vn)
        XCTAssertEqual(done.stage, .settings, "server says done: the local draft is ignored")
        XCTAssertNil(done.draft.goals)

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
        for _ in 0..<5 { OnboardingFlow.reduce(&s, .next) }
        OnboardingFlow.reduce(&s, .saveFailed)
        store.save(s, uid: uid)
        XCTAssertEqual(store.resume(uid: uid, needsPreferences: true, needsSettings: false, region: .vn).stage, .question(4))
    }

    // MARK: coordinator (real async save boundary)

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
        for _ in 0..<5 { flow.send(.next) }
        try await waitFor { flow.state.stage == .saveFailed }
        flow.send(.retrySave)
        try await waitFor { flow.state.stage == .reveal }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(received.last, EventPreferences(interests: ["gallery"]))
    }

    @MainActor
    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
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
        XCTAssertFalse(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: true, faceIDEnabled: false),
                       "hides once everything is done")
        s.openedEvent = false
        s.dismissed = true
        XCTAssertFalse(ActivationChecklist.isVisible(state: s, items: items, hasSavedEvent: false, faceIDEnabled: false))
    }
}

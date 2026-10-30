import XCTest
@testable import BanbeApp

/// First-party measurement (migration 196). tests/fixtures/app-events.json is the shared contract with
/// tests/unit/appEvents.test.mjs (web) and the server's app_event_names whitelist — change all three together.
final class AppEventsTests: XCTestCase {
    private func fixture() throws -> [String: Set<String>] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        let data = try Data(contentsOf: url.appendingPathComponent("tests/fixtures/app-events.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try XCTUnwrap(root["events"] as? [String: [String]])
        return events.mapValues(Set.init)
    }

    /// One of every case the app can emit (a new case must be added here, or the name check below fails).
    private let representative: [AnalyticsEvent] = [
        .appOpened, .eventOpened(eventID: "evt-1", source: "home"), .ticketOpened(dayBucket: "day_of"),
        .notificationOpened(kind: "new_message", source: "push"), .shareCompleted(channel: "messages", context: "event"),
        .followTapped(context: "pulse"),
        .onboardingStarted, .onboardingQuestionViewed(question: "goals"), .onboardingQuestionAnswered(question: "goals", answerCount: 2),
        .onboardingQuestionSkipped(question: "budget"), .onboardingCompleted(answeredQuestions: 3, skippedAll: false),
        .personalizedResultsViewed(matchBucket: "3-5"), .firstEventOpened, .firstEventSaved, .firstReservationStarted,
        .permissionPrompted(permission: "location"), .permissionResult(permission: "faceID", result: "granted"),
        .publicEntryViewed, .publicEntryGetStarted, .publicEntryLogin, .publicStoryOpened, .publicStoryCompleted,
        .publicStorySkipped(step: 2), .guestBrowseStarted, .guestSignInPromptShown(context: "save"),
        .guestSignInPromptAccepted(context: "reserve"), .createEventStartedBlank, .recipeOpened,
        .recipeFixTapped(ingredient: "photos"), .submitRecipeScore(bucket: "7-8"), .createEventStillNeededTapped(field: "photos"), .createEventTypeSelected(type: "supper"), .scheduleOpened,
        .scheduleModeSelected(mode: "mine"), .scheduleDaySelected(bucket: "today"), .scheduleConflictShown(countBucket: "1-2"),
        .banbeScheduleAdd, .banbeScheduleRemove, .banbeScheduleResult(result: "added"), .systemCalendarEditorOpened,
        .systemCalendarEditorResult(result: "saved"), .rewardsBadgeCelebrated(code: "first_outing"),
        .rewardsWeekMilestone(weeks: 4), .rewardsGoalSet(goal: 2),
    ]

    func testClientWhitelistIsExactlyTheFixture() throws {
        let f = try fixture()
        XCTAssertEqual(Set(AppEventsContract.allowed.keys), Set(f.keys))
        for (name, keys) in f { XCTAssertEqual(AppEventsContract.allowed[name], keys, name) }
    }

    func testEveryEmittedEventAndPropIsInTheFixture() throws {
        let f = try fixture()
        XCTAssertEqual(Set(representative.map(\.name)), Set(f.keys), "every fixture name has a case and vice versa")
        for e in representative {
            let allowed = try XCTUnwrap(f[e.name], "\(e.name) is not in tests/fixtures/app-events.json")
            XCTAssertTrue(Set(e.properties.keys).isSubset(of: allowed), "\(e.name) sends \(e.properties.keys)")
            // Every declared prop survives the client filter: nothing the case carries is silently lost.
            XCTAssertEqual(AppEventsContract.payload(e)?.props, e.properties, e.name)
        }
    }

    func testPayloadDropsLongAndEmptyValues() {
        XCTAssertEqual(AppEventsContract.payload(.followTapped(context: String(repeating: "x", count: 65)))?.props, [:])
        XCTAssertEqual(AppEventsContract.payload(.followTapped(context: ""))?.props, [:])
        XCTAssertEqual(AppEventsContract.payload(.eventOpened(eventID: "e", source: "map"))?.props, ["event_id": "e", "source": "map"])
    }

    func testAppEventsSwitchIsOffUnlessSet() {
        XCTAssertFalse(FeatureFlags.isOn([:], "app_events"))
        XCTAssertFalse(FeatureFlags.isOn(["app_events": false], "app_events"))
        XCTAssertTrue(FeatureFlags.isOn(["app_events": true], "app_events"))
        XCTAssertEqual(FeatureFlags.normalize(["app_events": true]), ["app_events": true])
    }

    // MARK: sink

    private final class Box { var batches: [[AppEventPayload]] = []; var on = true; var signedIn = true }

    private func makeSink(_ box: Box, batchSize: Int = 20, expect: XCTestExpectation? = nil) -> AppEventsSink {
        AppEventsSink(isEnabled: { box.on }, isSignedIn: { box.signedIn }, send: { batch in
            await MainActor.run { box.batches.append(batch) }
            expect?.fulfill()
        }, batchSize: batchSize, schedule: false)
    }

    func testNothingQueuedOrSentWhileOffOrSignedOut() async {
        let box = Box()
        box.on = false
        let sink = makeSink(box)
        sink.track(.appOpened)
        sink.flush()
        XCTAssertEqual(sink.count, 0)
        box.on = true
        box.signedIn = false
        sink.track(.appOpened)
        sink.flush()
        XCTAssertEqual(sink.count, 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(box.batches.isEmpty)
    }

    func testSignOutBeforeFlushDropsTheQueue() async {
        let box = Box()
        let sink = makeSink(box)
        sink.track(.appOpened)
        sink.track(.scheduleOpened)
        XCTAssertEqual(sink.count, 2)
        box.signedIn = false
        sink.flush()
        XCTAssertEqual(sink.count, 0)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(box.batches.isEmpty)
        box.signedIn = true
        sink.track(.appOpened)
        sink.stop()
        XCTAssertEqual(sink.count, 0)
    }

    func testFlushesAtBatchSizeWithFilteredProps() async {
        let box = Box()
        let sent = expectation(description: "batch sent")
        let sink = makeSink(box, batchSize: 3, expect: sent)
        sink.track(.eventOpened(eventID: "a", source: "home"))
        sink.track(.followTapped(context: "pulse"))
        XCTAssertEqual(sink.count, 2)
        sink.track(.appOpened)
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(sink.count, 0)
        XCTAssertEqual(box.batches.count, 1)
        XCTAssertEqual(box.batches[0], [
            AppEventPayload(name: "event_opened", props: ["event_id": "a", "source": "home"]),
            AppEventPayload(name: "follow_tapped", props: ["context": "pulse"]),
            AppEventPayload(name: "app_opened", props: [:]),
        ])
    }

    func testExplicitFlushSendsWhatIsQueued() async {
        let box = Box()
        let sent = expectation(description: "flushed")
        let sink = makeSink(box, expect: sent)
        sink.track(.ticketOpened(dayBucket: "before"))
        sink.flush()
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(box.batches.first?.first, AppEventPayload(name: "ticket_opened", props: ["day_bucket": "before"]))
    }

    // MARK: shared rules (same vectors as tests/unit/appEvents.test.mjs)

    func testEventOpenSource() {
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .home, searchOverlayOpen: false), "home")
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .home, searchOverlayOpen: true), "search")
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .search, searchOverlayOpen: false), "search")
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .mapExplore, searchOverlayOpen: false), "map")
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .schedule, searchOverlayOpen: false), "schedule")
        XCTAssertEqual(AppEventRules.eventOpenSource(screen: .organizerProfile, searchOverlayOpen: false), "other")
    }

    func testTicketDayBucket() throws {
        let iso = ISO8601DateFormatter()
        func at(_ s: String) throws -> Date { try XCTUnwrap(iso.date(from: s), s) }
        let hcm = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let start = try at("2026-10-23T13:00:00Z") // 20:00 in HCMC
        XCTAssertEqual(AppEventRules.ticketDayBucket(start: start, now: try at("2026-10-23T01:00:00Z"), timeZone: hcm), "day_of")
        XCTAssertEqual(AppEventRules.ticketDayBucket(start: start, now: try at("2026-10-22T16:59:00Z"), timeZone: hcm), "before")
        XCTAssertEqual(AppEventRules.ticketDayBucket(start: start, now: try at("2026-10-23T17:00:00Z"), timeZone: hcm), "after")
        let la = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(AppEventRules.ticketDayBucket(start: try at("2026-10-24T02:00:00Z"), now: try at("2026-10-23T16:00:00Z"), timeZone: la), "day_of")
    }

    func testAppOpenedOncePerLocalDay() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.appEvents.\(UUID().uuidString)"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let d1 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 8)))
        let d1b = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 23, minute: 59)))
        let d2 = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 0, minute: 1)))
        XCTAssertEqual(AppEventRules.localDayKey(d1, calendar: cal), "2026-10-23")
        XCTAssertTrue(AppEventRules.claimAppOpenedToday(defaults, now: d1, calendar: cal))
        XCTAssertFalse(AppEventRules.claimAppOpenedToday(defaults, now: d1b, calendar: cal))
        XCTAssertTrue(AppEventRules.claimAppOpenedToday(defaults, now: d2, calendar: cal))
    }

    func testShareChannelIsAFixedName() {
        XCTAssertEqual(AppEventRules.shareChannel(.message), "messages")
        XCTAssertEqual(AppEventRules.shareChannel(.copyToPasteboard), "copy")
        XCTAssertEqual(AppEventRules.shareChannel(UIActivity.ActivityType("net.whatsapp.WhatsApp.ShareExtension")), "other")
        XCTAssertEqual(AppEventRules.shareChannel(nil), "other")
    }

    // MARK: age 16 (migration 197; same vectors as tests/unit/retentionReport.test.mjs)

    func testDateOfBirthMinimumAgeOnlyWhereAsked() {
        let today = (y: 2026, m: 10, d: 23)
        func input(_ d: String, _ m: String, _ y: String) -> DateOfBirthInput { DateOfBirthInput(day: d, month: m, year: y) }
        XCTAssertEqual(input("23", "10", "2010").validate(today: today, minAge: 16), .success("2010-10-23"))
        XCTAssertEqual(input("24", "10", "2010").validate(today: today, minAge: 16), .failure(.tooYoung))
        XCTAssertEqual(input("1", "1", "2015").validate(today: today, minAge: 16), .failure(.tooYoung))
        XCTAssertEqual(input("1", "1", "2015").validate(today: today), .success("2015-01-01"))
        XCTAssertTrue(DateOfBirthInput.latestDate(minAge: 16, today: (2028, 2, 29)) == (2012, 2, 29))
        XCTAssertTrue(DateOfBirthInput.latestDate(minAge: 15, today: (2028, 2, 29)) == (2013, 2, 28))
    }
}

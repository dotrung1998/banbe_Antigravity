import XCTest
@testable import BanbeApp

final class ForYouTests: XCTestCase {
    private let hcm = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-11-01 00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_491_200)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = utc
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func ev(_ key: String, cats: [String] = ["music"], price: Int? = 0, cur: String? = "VND",
                    free: Bool = true, start: Date? = nil, tz: TimeZone? = nil, bookable: Bool = true) -> ForYouCandidate {
        ForYouCandidate(key: key, categories: cats, priceAmount: price, priceCurrency: cur, isFree: free,
                        startsAt: start ?? date(2026, 11, 5, 12), timeZone: tz, isBookable: bookable)
    }

    private func interest(_ ids: [String]) -> EventPreferences { EventPreferences(interests: ids) }

    // MARK: ordering

    func testDeterministicOrderingAndTieBreaks() {
        let p = interest(["music"])
        let t = date(2026, 11, 5, 12)
        let events = [
            ev("b", start: t), ev("a", start: t),
            ev("late", start: t.addingTimeInterval(3600)),
            ev("early", start: t.addingTimeInterval(-3600)),
        ]
        let r1 = ForYou.rank(events, prefs: p, now: now).map(\.key)
        let r2 = ForYou.rank(events.reversed(), prefs: p, now: now).map(\.key)
        XCTAssertEqual(r1, r2)
        XCTAssertEqual(r1, ["early", "a", "b", "late"])
    }

    func testHigherScoreFirst() {
        let p = EventPreferences(interests: ["music"], goals: ["meet_people"])
        let withGoal = ev("goal", cats: ["music"])
        let noGoal = ev("plain", cats: ["music"]) // same categories => same score; use gallery-less contrast below
        let other = ForYouCandidate(key: "x", categories: ["music", "fashion"], priceAmount: 0, priceCurrency: "VND",
                                    isFree: true, startsAt: date(2026, 11, 5, 12), timeZone: nil, isBookable: true)
        let r = ForYou.rank([noGoal, withGoal, other], prefs: p, now: now)
        XCTAssertEqual(r.count, 3)
        XCTAssertTrue(r.allSatisfy { $0.reasons.contains("goal") })
    }

    // MARK: interests

    func testInterestsHardExclusion() {
        let p = interest(["music"])
        XCTAssertNil(ForYou.match(ev("g", cats: ["gallery"]), prefs: p, now: now))
        XCTAssertNotNil(ForYou.match(ev("m", cats: ["gallery", "music"]), prefs: p, now: now))
    }

    func testUnknownCategoryNeverExcludedByInterests() {
        // With another affirmative signal (goal) the unknown-category event still matches.
        let p = EventPreferences(interests: ["music"], goals: ["meet_people"])
        // unknown category: interest rule skipped; goal affinity needs a taxonomy category -> none -> no signal.
        XCTAssertNil(ForYou.match(ev("u", cats: ["zzz"]), prefs: p, now: now))
        // but not because it was "excluded by interest": free budget gives a signal.
        let p2 = EventPreferences(interests: ["music"], budget: BudgetPref(tier: "free", currency: nil))
        XCTAssertNotNil(ForYou.match(ev("u", cats: ["zzz"]), prefs: p2, now: now))
        XCTAssertNotNil(ForYou.match(ev("n", cats: []), prefs: p2, now: now))
    }

    func testNoInterestsChosenDoesNotExclude() {
        let p = EventPreferences(interests: [EventPrefTaxonomy.noPreference], goals: ["learn"])
        let m = ForYou.match(ev("g", cats: ["gallery"]), prefs: p, now: now)
        XCTAssertNotNil(m)
        XCTAssertFalse(m!.reasons.contains("interest"))
        let q = EventPreferences(goals: ["learn"])
        XCTAssertNotNil(ForYou.match(ev("f", cats: ["fashion"]), prefs: q, now: now))
    }

    // MARK: budget

    func testFreeOnlyExcludesPaid() {
        let p = EventPreferences(budget: BudgetPref(tier: "free", currency: nil))
        XCTAssertNotNil(ForYou.match(ev("free"), prefs: p, now: now))
        XCTAssertNil(ForYou.match(ev("paid", price: 1, free: false), prefs: p, now: now))
    }

    func testVietnamBudgetCapBoundaries() {
        let low = EventPreferences(budget: BudgetPref(tier: "low", currency: "VND"))
        let med = EventPreferences(budget: BudgetPref(tier: "medium", currency: "VND"))
        XCTAssertNotNil(ForYou.match(ev("a", price: 200_000, free: false), prefs: low, now: now))
        XCTAssertNil(ForYou.match(ev("b", price: 200_001, free: false), prefs: low, now: now))
        XCTAssertNotNil(ForYou.match(ev("c", price: 600_000, free: false), prefs: med, now: now))
        XCTAssertNil(ForYou.match(ev("d", price: 600_001, free: false), prefs: med, now: now))
        XCTAssertEqual(BudgetRegion.vn.lowMax, 200_000)
        XCTAssertEqual(BudgetRegion.vn.mediumMax, 600_000)
    }

    func testUSDBudgetVsVNDEventIsNeutral() {
        let p = EventPreferences(interests: ["music"], budget: BudgetPref(tier: "low", currency: "USD"))
        let m = ForYou.match(ev("v", price: 5_000_000, free: false), prefs: p, now: now)
        XCTAssertNotNil(m)
        XCTAssertFalse(m!.reasons.contains("budget"))
        // Budget alone gives no signal => not matched, but not by exclusion rule (same as neutral).
        let only = EventPreferences(budget: BudgetPref(tier: "low", currency: "USD"))
        XCTAssertNil(ForYou.match(ev("v", price: 5_000_000, free: false), prefs: only, now: now))
    }

    func testFlexibleBudgetNeutral() {
        let p = EventPreferences(interests: ["music"], budget: BudgetPref(tier: "flexible", currency: "VND"))
        let m = ForYou.match(ev("x", price: 99_000_000, free: false), prefs: p, now: now)
        XCTAssertNotNil(m)
        XCTAssertFalse(m!.reasons.contains("budget"))
    }

    // MARK: availability / time zones

    func testEventTimeZoneWeekdayAndDayPart() {
        let t = date(2026, 11, 7, 23, 30)
        var h = Calendar(identifier: .gregorian); h.timeZone = hcm
        XCTAssertEqual(h.component(.weekday, from: t), 1)   // Sunday
        XCTAssertEqual(h.component(.hour, from: t), 6)
        var l = Calendar(identifier: .gregorian); l.timeZone = la
        XCTAssertEqual(l.component(.weekday, from: t), 7)   // Saturday
        XCTAssertEqual(l.component(.hour, from: t), 15)
    }

    func testAvailabilityUsesEventTimeZoneNotDevice() {
        // 2026-11-08 03:00 UTC = Sun 10:00 in HCMC (weekend+daytime), Sat 19:00 in LA (weekend+evening).
        let t = date(2026, 11, 8, 3)
        let p = EventPreferences(interests: ["music"], availability: ["weekends", "daytime"])
        let inHCM = ForYou.match(ev("h", start: t, tz: hcm), prefs: p, now: now)!
        let inLA = ForYou.match(ev("l", start: t, tz: la), prefs: p, now: now)!
        XCTAssertTrue(inHCM.reasons.contains("time"))
        XCTAssertFalse(inLA.reasons.contains("time"))
        XCTAssertEqual(inHCM.score - inLA.score, 25) // +10 vs -15
        // Weekday-only user: HCMC Sunday misses.
        let wk = EventPreferences(interests: ["music"], availability: ["weekdays"])
        XCTAssertFalse(ForYou.match(ev("h", start: t, tz: hcm), prefs: wk, now: now)!.reasons.contains("time"))
    }

    func testUnknownTimeZoneMakesAvailabilityNeutral() {
        let t = date(2026, 11, 8, 3)
        let p = EventPreferences(interests: ["music"], availability: ["weekdays", "evening"])
        let noTZ = ForYou.match(ev("n", start: t, tz: nil), prefs: p, now: now)!
        let base = ForYou.match(ev("n", start: t, tz: nil), prefs: interest(["music"]), now: now)!
        XCTAssertEqual(noTZ.score, base.score)
    }

    func testUSStateTimeZoneMapping() {
        XCTAssertEqual(ForYou.timeZone(countryCode: "US", stateProvince: "CA")?.identifier, "America/Los_Angeles")
        XCTAssertEqual(ForYou.timeZone(countryCode: "us", stateProvince: "California")?.identifier, "America/Los_Angeles")
        XCTAssertEqual(ForYou.timeZone(countryCode: "US", stateProvince: " ny ")?.identifier, "America/New_York")
        XCTAssertEqual(ForYou.timeZone(countryCode: "US", stateProvince: "Texas")?.identifier, "America/Chicago")
        XCTAssertEqual(ForYou.timeZone(countryCode: "US", stateProvince: "HI")?.identifier, "Pacific/Honolulu")
        XCTAssertNil(ForYou.timeZone(countryCode: "US", stateProvince: "Atlantis"))
        XCTAssertNil(ForYou.timeZone(countryCode: "US", stateProvince: nil))
        XCTAssertNil(ForYou.timeZone(countryCode: "FR", stateProvince: nil))
        XCTAssertEqual(ForYou.timeZone(countryCode: nil, stateProvince: nil)?.identifier, "Asia/Ho_Chi_Minh")
        XCTAssertEqual(ForYou.priceCurrency(countryCode: "VN"), "VND")
        XCTAssertNil(ForYou.priceCurrency(countryCode: "US"))
    }

    // MARK: eligibility of events

    func testNotBookableOrStartedExcluded() {
        let p = interest(["music"])
        XCTAssertNil(ForYou.match(ev("closed", bookable: false), prefs: p, now: now))
        XCTAssertNil(ForYou.match(ev("started", start: now.addingTimeInterval(-60)), prefs: p, now: now))
        XCTAssertNotNil(ForYou.match(ev("future", start: now.addingTimeInterval(60)), prefs: p, now: now))
    }

    func testNoMatchesIsEmpty() {
        let p = interest(["music"])
        XCTAssertTrue(ForYou.rank([ev("g", cats: ["gallery"]), ev("f", cats: ["fashion"])], prefs: p, now: now).isEmpty)
        XCTAssertTrue(ForYou.rank([], prefs: p, now: now).isEmpty)
    }

    func testMissingOptionalDataDoesNotExcludeEverything() {
        let e = ForYouCandidate(key: "sparse", categories: ["music"], priceAmount: nil, priceCurrency: nil,
                                isFree: false, startsAt: nil, timeZone: nil, isBookable: true)
        let p = EventPreferences(interests: ["music"], availability: ["weekends"],
                                 budget: BudgetPref(tier: "low", currency: "VND"))
        let r = ForYou.rank([e], prefs: p, now: now)
        XCTAssertEqual(r.map(\.key), ["sparse"])
    }
}

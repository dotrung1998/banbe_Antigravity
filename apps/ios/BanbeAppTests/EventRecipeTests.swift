import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/eventRecipe.test.mjs 1:1 (same BENCH fixture, same drafts, same expectations).
final class EventRecipeTests: XCTestCase {
    typealias R = EventRecipe

    private func ict(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso + "+07:00")!
    }
    private lazy var now = ict("2026-10-21T10:00:00") // Wed 10:00 in Vietnam
    private let T: R.Translate = { _, en in en }

    /// Same shape get_host_benchmarks returns (verified against migration 186 on Postgres 16), decoded from JSON
    /// so the Codable mapping is exercised too.
    private static let benchJSON = """
    {"success": true, "level": "category_city", "n": 13, "free_share": 0,
     "price": {"n": 13, "p25": 280000, "median": 320000, "p75": 380000, "min": 220000, "max": 440000,
               "histogram": [2, 1, 1, 2, 1, 1, 1, 1, 1, 2]},
     "fill": {"n": 12, "median_fill": 0.6, "median_capacity": 20, "median_booked": 12},
     "slots": [{"dow": 6, "slot": "evening", "n": 8, "median_fill": 0.85},
               {"dow": 3, "slot": "evening", "n": 5, "median_fill": 0.5}],
     "well_filled": {"n": 6, "median_photos": 6, "intro_share": 0.5, "included_share": 1, "median_lead_days": 16.4},
     "others": {"n": 6, "median_photos": 2, "intro_share": 0.5, "included_share": 0.33, "median_lead_days": 8},
     "keywords": ["wine", "rooftop", "chef"]}
    """
    private let bench = try! JSONDecoder().decode(HostBenchmarks.self, from: Data(benchJSON.utf8))
    private let cold = try! JSONDecoder().decode(HostBenchmarks.self, from: Data(#"{"success": true, "level": null, "n": 0}"#.utf8))

    private var goodDraft: R.Draft {
        R.Draft(name: "Six-course supper club in District 3", description: String(repeating: "x", count: 150), intro: "",
                includedCount: 2, keywords: ["wine", "dinner", "rooftop"], priceVnd: 300_000, seats: 16,
                startsAt: ict("2026-11-07T19:00:00"), photos: 6, chatGreeting: "Hi! Ask me anything.")
    }
    private func byID(_ checks: [R.Check]) -> [String: R.Check] {
        Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
    }
    private func draft(_ edit: (inout R.Draft) -> Void) -> R.Draft { var d = goodDraft; edit(&d); return d }

    func testAWellPreparedDraftScores10Of10AgainstRealBenchmarks() {
        XCTAssertEqual(bench.price?.histogram?.count, 10)
        XCTAssertEqual(bench.wellFilled?.medianLeadDays, 16.4)
        let checks = R.checks(goodDraft, benchmarks: bench, goal: nil, now: now)
        XCTAssertEqual(checks.count, 10)
        XCTAssertEqual(checks.filter { $0.status != .good }.map(\.id), [])
        XCTAssertEqual(R.score(checks).good, 10)
        XCTAssertEqual(R.score(checks).total, 10)
    }

    func testAnEmptyDraftFlagsObjectiveGapsAndJudgesNothingOnAGuess() {
        let c = byID(R.checks(R.Draft(), benchmarks: nil, goal: nil, now: now))
        for id in ["title", "photos", "description", "included", "keywords", "seats", "timing", "lead"] {
            XCTAssertEqual(c[id]?.status, .missing, id)
        }
        XCTAssertEqual(c["price"]?.status, .good) // free is a valid choice
        XCTAssertEqual(c["greeting"]?.status, .improve)
        XCTAssertTrue(c.values.allSatisfy { $0.source == .tip })
    }

    func testColdStartBehavesLikeNoBenchmarks() {
        XCTAssertFalse(R.hasBenchmarks(cold))
        XCTAssertTrue(R.hasBenchmarks(bench))
        let c = byID(R.checks(draft { $0.photos = 5; $0.startsAt = ict("2026-11-03T14:00:00") }, benchmarks: cold, goal: nil, now: now))
        XCTAssertEqual(c["photos"]?.target, 5)
        XCTAssertEqual(c["photos"]?.status, .good)
        XCTAssertEqual(c["timing"]?.status, .good) // a Tuesday afternoon is not judged without data
        XCTAssertEqual(c["timing"]?.source, .tip)
        XCTAssertEqual(c["price"]?.source, .tip)
        XCTAssertEqual(c["lead"]?.target, 14)
    }

    func testTitleRules() {
        func t(_ name: String) -> R.Check { byID(R.checks(R.Draft(name: name), benchmarks: nil, goal: nil, now: now))["title"]! }
        XCTAssertEqual(t("Jazz").status, .improve)
        XCTAssertEqual(t("LIVE JAZZ NIGHT TONIGHT").status, .improve)
        XCTAssertTrue(t("LIVE JAZZ NIGHT TONIGHT").shouting)
        XCTAssertEqual(t("Live jazz night at Saigon Social").status, .good)
        XCTAssertEqual(t("Đêm nhạc jazz ở Quận 1").status, .good)
    }

    func testPhotosTargetFollowsWellFilledEventsFlooredAt3() {
        XCTAssertEqual(byID(R.checks(draft { $0.photos = 5 }, benchmarks: bench, goal: nil, now: now))["photos"]?.status, .improve)
        XCTAssertEqual(byID(R.checks(draft { $0.photos = 2 }, benchmarks: bench, goal: nil, now: now))["photos"]?.status, .missing)
        var low = bench
        low.wellFilled?.medianPhotos = 1
        XCTAssertEqual(byID(R.checks(draft { $0.photos = 3 }, benchmarks: low, goal: nil, now: now))["photos"]?.target, 3)
    }

    func testPriceBandAndThePremiumGoal() {
        XCTAssertEqual(R.pricePosition(200_000, bench.price), "below")
        XCTAssertEqual(R.pricePosition(320_000, bench.price), "typical")
        XCTAssertEqual(R.pricePosition(500_000, bench.price), "premium")
        XCTAssertEqual(R.pricePosition(0, bench.price), "free")
        let pricey = draft { $0.priceVnd = 600_000 }
        XCTAssertEqual(byID(R.checks(pricey, benchmarks: bench, goal: nil, now: now))["price"]?.status, .improve)
        XCTAssertEqual(byID(R.checks(pricey, benchmarks: bench, goal: "small_premium", now: now))["price"]?.status, .good)
        XCTAssertEqual(byID(R.checks(draft { $0.priceVnd = 150_000 }, benchmarks: bench, goal: nil, now: now))["price"]?.status, .good)
    }

    func testSeatsVsTypicalGuestsAndFillEverySeatIsStricter() {
        // typical 12: default limit max(24, 22) = 24; fill_seats limit max(18, 17) = 18
        XCTAssertEqual(byID(R.checks(draft { $0.seats = 20 }, benchmarks: bench, goal: nil, now: now))["seats"]?.status, .good)
        XCTAssertEqual(byID(R.checks(draft { $0.seats = 20 }, benchmarks: bench, goal: "fill_seats", now: now))["seats"]?.status, .improve)
        XCTAssertEqual(byID(R.checks(draft { $0.seats = 30 }, benchmarks: bench, goal: nil, now: now))["seats"]?.status, .improve)
        XCTAssertEqual(byID(R.checks(draft { $0.seats = 30 }, benchmarks: nil, goal: nil, now: now))["seats"]?.status, .good)
    }

    func testTimingComparesThisSlotWithTheBestSlotOnlyWhenTheCellExists() {
        let wed = byID(R.checks(draft { $0.startsAt = ict("2026-11-04T19:30:00") }, benchmarks: bench, goal: nil, now: now))["timing"]!
        XCTAssertEqual(wed.status, .improve)
        XCTAssertEqual(wed.dow, 3); XCTAssertEqual(wed.slot, "evening"); XCTAssertEqual(wed.ownFill, 0.5)
        XCTAssertEqual(wed.best, R.BestSlot(dow: 6, slot: "evening", fill: 0.85))
        let sat = byID(R.checks(goodDraft, benchmarks: bench, goal: nil, now: now))["timing"]!
        XCTAssertEqual(sat.status, .good)
        XCTAssertNil(sat.best)
        let mon = byID(R.checks(draft { $0.startsAt = ict("2026-11-02T22:00:00") }, benchmarks: bench, goal: nil, now: now))["timing"]!
        XCTAssertEqual(mon.slot, "late")
        XCTAssertEqual(mon.status, .good) // no cell for Monday late: not judged
        XCTAssertEqual(mon.source, .tip)
    }

    func testLeadTimeUsesTheWellFilledMedianRoundedElse14Days() {
        let soon = byID(R.checks(draft { $0.startsAt = ict("2026-10-30T19:00:00") }, benchmarks: bench, goal: nil, now: now))["lead"]!
        XCTAssertEqual(soon.status, .improve); XCTAssertEqual(soon.days, 9); XCTAssertEqual(soon.target, 16)
        XCTAssertEqual(byID(R.checks(goodDraft, benchmarks: bench, goal: nil, now: now))["lead"]?.status, .good)
    }

    func testKeywordSuggestionsExcludeWhatTheHostAlreadyHas() {
        let k = byID(R.checks(draft { $0.keywords = ["Wine"] }, benchmarks: bench, goal: nil, now: now))["keywords"]!
        XCTAssertEqual(k.status, .improve)
        XCTAssertEqual(k.suggestions, ["rooftop", "chef"])
    }

    func testOutcomeEstimateUsesSimilarFillWhenKnownElseTheHonestFullHouseFigure() {
        XCTAssertEqual(R.estimateOutcome(priceVnd: 300_000, seats: 16, medianFill: 0.6), R.Outcome(guests: 10, revenueVnd: 3_000_000, basis: "similar", fill: 0.6))
        XCTAssertEqual(R.estimateOutcome(priceVnd: 300_000, seats: 16, medianFill: nil), R.Outcome(guests: 16, revenueVnd: 4_800_000, basis: "full", fill: nil))
        XCTAssertEqual(R.estimateOutcome(priceVnd: 0, seats: 10, medianFill: 0.5), R.Outcome(guests: 5, revenueVnd: 0, basis: "similar", fill: 0.5))
        XCTAssertNil(R.estimateOutcome(priceVnd: 300_000, seats: 0, medianFill: 0.6))
        XCTAssertEqual(R.estimateOutcome(priceVnd: 300_000, seats: 2, medianFill: 0.1)?.guests, 1)
    }

    func testCopyNamesItsEvidenceAndNeverShowsANumberFromATip() {
        let checks = R.checks(goodDraft, benchmarks: bench, goal: nil, now: now)
        for c in checks {
            let copy = R.copy(c, T)
            XCTAssertFalse(copy.title.isEmpty, c.id)
            XCTAssertFalse(copy.detail.isEmpty, c.id)
        }
        let price = R.copy(byID(checks)["price"]!, T)
        XCTAssertTrue(price.detail.contains("280k₫–380k₫"), price.detail)
        XCTAssertTrue(price.detail.contains("Based on 13 similar events"), price.detail)
        let coldPrice = R.copy(byID(R.checks(goodDraft, benchmarks: nil, goal: nil, now: now))["price"]!, T)
        XCTAssertNil(coldPrice.detail.rangeOfCharacter(from: .decimalDigits), coldPrice.detail)
        XCTAssertEqual(R.formatVndShort(3_300_000), "3,3M₫")
        XCTAssertEqual(R.formatVndShort(3_000_000), "3M₫")
        XCTAssertEqual(R.formatVndShort(250_000), "250k₫")
    }
}

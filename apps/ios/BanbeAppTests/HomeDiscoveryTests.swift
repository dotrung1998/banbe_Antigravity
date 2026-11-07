import XCTest
@testable import BanbeApp

/// Mirrors tests/unit/homeDiscovery.test.mjs 1:1 (same fixtures, same expectations) — change both together.
final class HomeDiscoveryTests: XCTestCase {
    typealias D = HomeDiscovery

    /// Vietnam wall clock (UTC+7, fixed offset — never the device zone).
    private func ict(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso + "+07:00")!
    }

    // Wednesday 2026-10-21 10:00 in Vietnam (UTC+7) = 03:00Z.
    private lazy var wed10 = ict("2026-10-21T10:00:00")
    private let day: TimeInterval = 86_400

    private func ev(_ key: String, startsAt: Date?? = nil, priceVnd: Int?? = nil, catKeys: [String] = ["music"],
                    booked: Int? = nil, capacity: Int? = nil, soldOut: Bool = false,
                    distanceKm: Double? = nil, popularity: Double? = nil) -> D.Item {
        D.Item(key: key, startsAt: startsAt ?? ict("2026-10-21T19:00:00"), priceVnd: priceVnd ?? 200_000, catKeys: catKeys,
               booked: booked, capacity: capacity, soldOut: soldOut, distanceKm: distanceKm, popularity: popularity)
    }

    private func window(_ option: String, _ now: Date) -> [Date]? {
        D.dateWindow(option, now: now).map { [$0.start, $0.end] }
    }

    func testTodayRunsFromNowToLocalMidnightTomorrowIsNextLocalDay() {
        XCTAssertEqual(window("today", wed10), [wed10, ict("2026-10-22T00:00:00")])
        XCTAssertEqual(window("tomorrow", wed10), [ict("2026-10-22T00:00:00"), ict("2026-10-23T00:00:00")])
    }

    func testLocalMidnightIsComputedInUTC7NotUTC() {
        let late = ict("2026-10-21T23:30:00")
        XCTAssertEqual(window("today", late), [late, ict("2026-10-22T00:00:00")])
    }

    func testWeekendIsFriday17ToMondayAndStartsNowOnSaturday() {
        XCTAssertEqual(window("weekend", wed10), [ict("2026-10-23T17:00:00"), ict("2026-10-26T00:00:00")])
        let sat = ict("2026-10-24T11:00:00")
        XCTAssertEqual(window("weekend", sat), [sat, ict("2026-10-26T00:00:00")])
        let sun = ict("2026-10-25T20:00:00")
        XCTAssertEqual(window("weekend", sun), [sun, ict("2026-10-26T00:00:00")])
    }

    func testWeekAndAPickedDate() {
        XCTAssertEqual(window("week", wed10), [wed10, wed10.addingTimeInterval(7 * day)])
        XCTAssertEqual(window("on:2026-10-30", wed10), [ict("2026-10-30T00:00:00"), ict("2026-10-31T00:00:00")])
        XCTAssertNil(window("any", wed10))
        XCTAssertNil(window("on:nope", wed10))
    }

    func testFillBadge() {
        XCTAssertEqual(D.fillBadge(booked: nil, capacity: 20), D.FillBadge(left: nil, almostFull: false, soldOut: false, going: nil))
        XCTAssertEqual(D.fillBadge(booked: 4, capacity: 0), D.FillBadge(left: nil, almostFull: false, soldOut: false, going: nil))
        XCTAssertEqual(D.fillBadge(booked: 17, capacity: 20), D.FillBadge(left: 3, almostFull: true, soldOut: false, going: 17))
        XCTAssertEqual(D.fillBadge(booked: 40, capacity: 50), D.FillBadge(left: 10, almostFull: true, soldOut: false, going: 40))
        XCTAssertEqual(D.fillBadge(booked: 4, capacity: 20), D.FillBadge(left: 16, almostFull: false, soldOut: false, going: nil))
        XCTAssertEqual(D.fillBadge(booked: 20, capacity: 20), D.FillBadge(left: 0, almostFull: false, soldOut: true, going: 20))
        XCTAssertEqual(D.fillBadge(booked: 25, capacity: 20), D.FillBadge(left: 0, almostFull: false, soldOut: true, going: 25))
    }

    private var items: [D.Item] {
        [
            ev("tonight-music"),
            ev("fri-late-supper", startsAt: ict("2026-10-23T20:00:00"), priceVnd: 450_000, catKeys: ["supper"], booked: 18, capacity: 20),
            ev("fri-noon", startsAt: ict("2026-10-23T12:00:00"), priceVnd: 0),
            ev("sat-free-gallery", startsAt: ict("2026-10-24T15:00:00"), priceVnd: 0, catKeys: ["gallery"]),
            ev("sun-soldout", startsAt: ict("2026-10-25T19:00:00"), priceVnd: 300_000, soldOut: true),
            ev("next-month", startsAt: ict("2026-11-20T19:00:00"), priceVnd: 800_000, catKeys: ["supper", "popup"]),
            ev("demo-no-date", startsAt: .some(nil), priceVnd: .some(nil)),
        ]
    }

    private func keys(_ xs: [D.Item]) -> [String] { xs.map(\.key) }
    private func f(_ build: (inout D.Filters) -> Void) -> D.Filters { var x = D.Filters(); build(&x); return x }

    func testFiltersCombineAndUnknownDatesOrPricesNeverPassADateOrPriceFilter() {
        XCTAssertEqual(D.apply(items, .default, now: wed10).count, items.count)
        XCTAssertEqual(keys(D.apply(items, f { $0.date = "weekend" }, now: wed10)), ["fri-late-supper", "sat-free-gallery", "sun-soldout"])
        XCTAssertEqual(keys(D.apply(items, f { $0.free = true }, now: wed10)), ["fri-noon", "sat-free-gallery"])
        XCTAssertEqual(keys(D.apply(items, f { $0.priceMin = 250_000; $0.priceMax = 500_000 }, now: wed10)), ["fri-late-supper", "sun-soldout"])
        XCTAssertEqual(keys(D.apply(items, f { $0.cats = ["supper"] }, now: wed10)), ["fri-late-supper", "next-month"])
        XCTAssertEqual(keys(D.apply(items, f { $0.cats = ["popup", "gallery"] }, now: wed10)), ["sat-free-gallery", "next-month"])
        XCTAssertFalse(keys(D.apply(items, f { $0.seatsLeft = true }, now: wed10)).contains("sun-soldout"))
        XCTAssertEqual(keys(D.apply(items, f { $0.almostFull = true }, now: wed10)), ["fri-late-supper"])
        XCTAssertEqual(keys(D.apply(items, f { $0.date = "weekend"; $0.free = true }, now: wed10)), ["sat-free-gallery"])
    }

    func testActiveFilterCount() {
        XCTAssertEqual(D.activeFilterCount(.default), 0)
        XCTAssertEqual(D.activeFilterCount(f { $0.date = "today"; $0.priceMin = 1; $0.priceMax = 2; $0.cats = ["music"]; $0.free = true }), 4)
    }

    func testOptionCountsEqualTheListYouGetByApplyingThatOption() {
        let filters = f { $0.free = true }
        let counts = D.optionCounts(items, filters, .date, options: ["any", "today", "tomorrow", "weekend", "week"], now: wed10)
        XCTAssertEqual(counts, ["any": 2, "today": 0, "tomorrow": 0, "weekend": 1, "week": 2])
        for (opt, n) in counts {
            var g = filters; g.date = opt
            XCTAssertEqual(D.apply(items, g, now: wed10).count, n)
        }
        // Category counts ignore the current category pick (so every pill shows what tapping it gives).
        XCTAssertEqual(D.optionCounts(items, f { $0.cats = ["music"] }, .cats, options: ["music", "supper", "gallery"], now: wed10),
                       ["music": 4, "supper": 2, "gallery": 1])
        XCTAssertEqual(D.optionCounts(items, f { $0.date = "weekend" }, .free, now: wed10), ["true": 1])
    }

    /// Plan item 2 (shared with tests/unit/homeDiscovery.test.mjs): the category row's count is exactly what tapping
    /// that category renders (type chips dropped, every other filter kept), for every category.
    func testCategoryCountEqualsTheRenderedResultsForEveryCategory() {
        let keys = D.categories.map(\.key).filter { $0 != "all" }
        let filterSets: [D.Filters] = [.default, f { $0.free = true }, f { $0.date = "weekend" },
                                       f { $0.cats = ["music"]; $0.typeFilters = ["dietary:vegan"] }, f { $0.seatsLeft = true }]
        for filters in filterSets {
            let counts = D.categoryCounts(items, filters, keys: keys, now: wed10)
            for k in keys {
                var g = filters; g.cats = [k]; g.typeFilters = []
                XCTAssertEqual(counts[k], D.apply(items, g, now: wed10).count, "\(k) \(filters)")
            }
            var all = filters; all.cats = []; all.typeFilters = []
            XCTAssertEqual(counts["all"], D.apply(items, all, now: wed10).count)
        }
    }

    func testCategoryRowAllFirstThenMostFirstZeroHiddenUnlessSelectedAndSheetAZ() {
        let keys = ["music", "supper", "gallery", "popup", "fashion"]
        let counts = D.categoryCounts(items, .default, keys: keys, now: wed10)
        let row = D.categoryRowKeys(counts, keys: keys)
        XCTAssertEqual(row.first, "all")
        XCTAssertEqual(row, ["all", "music", "supper", "gallery", "popup"])   // 4, 2, 1, 1 (tie keeps order); fashion 0 hidden
        XCTAssertFalse(row.contains("fashion"))
        XCTAssertEqual(D.categoryRowKeys(counts, keys: keys, selected: ["fashion"]).last, "fashion")
        let defs: [(key: String, vi: String, en: String)] = [("music", "Âm nhạc", "Music"), ("gallery", "Triển lãm", "Gallery"),
                                                              ("supper", "Bữa tối", "Supper club")]
        XCTAssertEqual(D.categorySheetKeys(defs, lang: "en"), ["gallery", "music", "supper"])
        XCTAssertEqual(D.categorySheetKeys(defs, lang: "vi"), ["music", "supper", "gallery"])
    }

    func testRelaxationHintsPickTheSingleChangeThatAddsTheMostEvents() {
        let hints = D.relaxationHints(items, f { $0.date = "today"; $0.free = true }, now: wed10)
        // date->any gives 2 (free events), free->off gives 1 (tonight-music): date wins.
        XCTAssertEqual(hints.map(\.id), ["date", "free"])
        XCTAssertEqual(hints.map(\.gain), [2, 1])
        XCTAssertEqual(D.apply(items, hints[0].filters, now: wed10).count, 2)
        XCTAssertEqual(D.relaxationHints(items, .default, now: wed10), [])
    }

    func testSortingIsStableWithNullsLast() {
        XCTAssertEqual(keys(D.sort(items, mode: "soonest")),
                       ["tonight-music", "fri-noon", "fri-late-supper", "sat-free-gallery", "sun-soldout", "next-month", "demo-no-date"])
        XCTAssertEqual(keys(D.sort(items, mode: "price")),
                       ["fri-noon", "sat-free-gallery", "tonight-music", "sun-soldout", "fri-late-supper", "next-month", "demo-no-date"])
        let near = [ev("a", distanceKm: 3), ev("b"), ev("c", distanceKm: 1.2)]
        XCTAssertEqual(keys(D.sort(near, mode: "nearest")), ["c", "a", "b"])
        let pop = [ev("a", popularity: 2), ev("b", popularity: 9), ev("c"), ev("d", popularity: 9)]
        XCTAssertEqual(keys(D.sort(pop, mode: "popular")), ["b", "d", "a", "c"])
        XCTAssertEqual(keys(D.sort(pop, mode: "unknown")), ["a", "b", "c", "d"])
    }

    func testMedianAndHistogram() {
        XCTAssertNil(D.median([]))
        XCTAssertEqual(D.median([3, 1, 2]), 2)
        XCTAssertEqual(D.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(D.priceHistogram([0, 0]))
        let h = D.priceHistogram([100, 200, 200, 300, 0], buckets: 4)
        XCTAssertEqual(h, D.Histogram(min: 100, max: 300, counts: [1, 0, 2, 1]))
        XCTAssertEqual(D.bucketIndex(h, price: 100), 0)
        XCTAssertEqual(D.bucketIndex(h, price: 300), 3)
        XCTAssertEqual(D.bucketIndex(h, price: 5000), 3)
        XCTAssertEqual(D.priceHistogram([500, 500], buckets: 3), D.Histogram(min: 500, max: 500, counts: [2, 0, 0]))
    }
}

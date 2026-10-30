import Foundation

// Home discovery: quick chips, filter sheet, sort, live counts, fill badges, "relax a filter" hints.
// iOS twin of src/lib/homeDiscovery.js — keep both and their tests in sync
// (HomeDiscoveryTests.swift mirrors tests/unit/homeDiscovery.test.mjs case for case).
// Pure: no SwiftUI, no network, no `Date()` inside — `now` is always passed in.
//
// Day boundaries use a FIXED UTC offset in minutes, never the device zone. Every launch market is
// Vietnam (UTC+7, no DST), so 420 is the default; tests pass it explicitly so they are exact anywhere.
enum HomeDiscovery {
    static let defaultOffsetMin = 420
    static let dateOptions = ["any", "today", "tomorrow", "weekend", "week"]
    static let sortModes = ["soonest", "nearest", "popular", "price"]

    static let almostFullSeats = 3
    static let almostFullShare = 0.2
    static let socialProofMin = 5

    private static let dayMs: Double = 86_400_000
    private static let hourMs: Double = 3_600_000

    /// One event, normalized once by the caller (real and demo events alike).
    struct Item: Equatable {
        var key: String
        var startsAt: Date?
        /// 0 = free, nil = unknown (never guessed).
        var priceVnd: Int?
        var catKeys: [String]
        var booked: Int?
        var capacity: Int?
        var soldOut: Bool
        var distanceKm: Double?
        var popularity: Double?
        /// The event's own currency (migration 195); `priceVnd` is in its MINOR unit (đồng, or cents for USD).
        var currency: String
        /// events.details (migration 203): what the event-type chips match on. Empty for legacy and demo events.
        var details: EventDetails

        init(key: String, startsAt: Date?, priceVnd: Int?, catKeys: [String], booked: Int? = nil, capacity: Int? = nil,
             soldOut: Bool = false, distanceKm: Double? = nil, popularity: Double? = nil, currency: String = "VND",
             details: EventDetails = [:]) {
            self.key = key; self.startsAt = startsAt; self.priceVnd = priceVnd; self.catKeys = catKeys
            self.booked = booked; self.capacity = capacity; self.soldOut = soldOut
            self.distanceKm = distanceKm; self.popularity = popularity; self.currency = currency; self.details = details
        }
    }

    /// `date` ∈ any | today | tomorrow | weekend | week | "on:YYYY-MM-DD". Default = everything shown.
    struct Filters: Equatable {
        var date = "any"
        var priceMin: Int?
        var priceMax: Int?
        /// The currency `priceMin`/`priceMax` were set in; a price bound never compares across currencies.
        var priceCurrency = "VND"
        var free = false
        /// Empty = all categories.
        var cats: [String] = []
        var seatsLeft = false
        var almostFull = false
        /// Event-type chip ids (e.g. "dietary:vegan"; Lib/EventTypes.swift). AND-combined.
        var typeFilters: [String] = []

        static let `default` = Filters()
    }

    struct FillBadge: Equatable {
        var left: Int?
        var almostFull = false
        var soldOut = false
        /// "N going" — only from `socialProofMin` bookings up.
        var going: Int?
    }

    enum Dimension { case date, cats, free, seatsLeft, almostFull, typeFilters }

    struct RelaxHint: Equatable {
        /// date | price | free | cats | seatsLeft | almostFull | type
        let id: String
        let gain: Int
        let filters: Filters
    }

    struct Histogram: Equatable {
        let min: Int
        let max: Int
        let counts: [Int]
    }

    // MARK: Date windows

    private static func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }
    private static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }

    /// Local midnight (in the given offset) of the day containing `ms`.
    private static func localMidnight(_ ms: Double, _ offsetMin: Int) -> Double {
        let off = Double(offsetMin) * 60_000
        return (((ms + off) / dayMs).rounded(.down)) * dayMs - off
    }

    /// 0 = Monday ... 6 = Sunday, in the given offset. 1970-01-01 was a Thursday.
    private static func localWeekday(_ ms: Double, _ offsetMin: Int) -> Int {
        let days = Int(((ms + Double(offsetMin) * 60_000) / dayMs).rounded(.down))
        let sundayBased = ((days + 4) % 7 + 7) % 7 // 0 = Sunday, like JS getUTCDay()
        return (sundayBased + 6) % 7
    }

    /// [start, end) for a date option, or nil for "any"/unknown. The window never starts before `now`.
    static func dateWindow(_ option: String, now: Date, offsetMin: Int = defaultOffsetMin) -> (start: Date, end: Date)? {
        let n = ms(now)
        let today = localMidnight(n, offsetMin)
        switch option {
        case "today": return (now, date(today + dayMs))
        case "tomorrow": return (date(today + dayMs), date(today + 2 * dayMs))
        case "week": return (now, date(n + 7 * dayMs))
        case "weekend":
            // Friday 17:00 -> Monday 00:00 (Friday evening counts as the weekend; Mobilizon issue 773).
            // Mon-Thu: the coming weekend. Fri-Sun: the current one, from now.
            let wd = localWeekday(n, offsetMin)
            let friday = today + Double(4 - wd) * dayMs
            let start = friday + 17 * hourMs
            let end = friday + 3 * dayMs
            return (date(max(start, n)), date(end))
        default:
            guard option.hasPrefix("on:") else { return nil }
            let parts = option.dropFirst(3).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            guard let midnightUTC = utc.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
            let start = ms(midnightUTC) - Double(offsetMin) * 60_000
            return (date(max(start, n)), date(start + dayMs))
        }
    }

    // MARK: Fill

    /// Seats-left / social-proof facts for one event. Unknown counts give nothing (never a guessed number).
    static func fillBadge(booked: Int?, capacity: Int?) -> FillBadge {
        guard let booked, let capacity, capacity > 0 else { return FillBadge() }
        let left = max(capacity - booked, 0)
        return FillBadge(
            left: left,
            almostFull: left > 0 && (left <= almostFullSeats || Double(left) / Double(capacity) <= almostFullShare),
            soldOut: left == 0,
            going: booked >= socialProofMin ? booked : nil
        )
    }

    private static func seatsLeft(of item: Item) -> Int? {
        if let left = fillBadge(booked: item.booked, capacity: item.capacity).left { return left }
        return item.soldOut ? 0 : nil
    }

    // MARK: Filtering

    private static func matches(_ item: Item, _ f: Filters, now: Date, offsetMin: Int) -> Bool {
        if f.date != "any", let w = dateWindow(f.date, now: now, offsetMin: offsetMin) {
            guard let s = item.startsAt, s >= w.start, s < w.end else { return false }
        }
        if f.free && item.priceVnd != 0 { return false }
        // Never mix currencies: with a price bound set, an event priced in another currency can't be compared.
        if (f.priceMin != nil || f.priceMax != nil) && item.currency != f.priceCurrency { return false }
        if let lo = f.priceMin { guard let p = item.priceVnd, p >= lo else { return false } }
        if let hi = f.priceMax { guard let p = item.priceVnd, p <= hi else { return false } }
        if !f.cats.isEmpty && !item.catKeys.contains(where: f.cats.contains) { return false }
        if f.seatsLeft && (seatsLeft(of: item) == 0 || item.soldOut) { return false }
        if f.almostFull && !fillBadge(booked: item.booked, capacity: item.capacity).almostFull { return false }
        for id in f.typeFilters {
            if let def = EventTypes.typeFilter(id), !EventTypes.matches(def, item.details) { return false }
        }
        return true
    }

    static func apply(_ items: [Item], _ filters: Filters, now: Date, offsetMin: Int = defaultOffsetMin) -> [Item] {
        items.filter { matches($0, filters, now: now, offsetMin: offsetMin) }
    }

    /// Number of non-default filters (the badge on the Filters button).
    static func activeFilterCount(_ f: Filters) -> Int {
        var n = 0
        if f.date != "any" { n += 1 }
        if f.priceMin != nil || f.priceMax != nil { n += 1 }
        if f.free { n += 1 }
        if !f.cats.isEmpty { n += 1 }
        if f.seatsLeft { n += 1 }
        if f.almostFull { n += 1 }
        n += f.typeFilters.count
        return n
    }

    /// Count for each option of one dimension, with every OTHER active filter applied — what the user would
    /// get if they tapped that pill ("This weekend · 8"). Boolean dimensions report the count under "true".
    static func optionCounts(_ items: [Item], _ f: Filters, _ dimension: Dimension, options: [String] = [],
                             now: Date, offsetMin: Int = defaultOffsetMin) -> [String: Int] {
        var out: [String: Int] = [:]
        func count(_ g: Filters) -> Int { apply(items, g, now: now, offsetMin: offsetMin).count }
        switch dimension {
        case .date:
            for opt in (options.isEmpty ? dateOptions : options) { var g = f; g.date = opt; out[opt] = count(g) }
        case .cats:
            for c in options { var g = f; g.cats = [c]; out[c] = count(g) }
        case .free: var g = f; g.free = true; out["true"] = count(g)
        case .seatsLeft: var g = f; g.seatsLeft = true; out["true"] = count(g)
        case .almostFull: var g = f; g.almostFull = true; out["true"] = count(g)
        case .typeFilters:
            // What tapping that chip would give: it joins the others (AND).
            for id in options { var g = f; g.typeFilters = g.typeFilters.filter { $0 != id } + [id]; out[id] = count(g) }
        }
        return out
    }

    private static let relaxations: [(id: String, active: (Filters) -> Bool, relax: (Filters) -> Filters)] = [
        ("date", { $0.date != "any" }, { var f = $0; f.date = "any"; return f }),
        ("price", { $0.priceMin != nil || $0.priceMax != nil }, { var f = $0; f.priceMin = nil; f.priceMax = nil; return f }),
        ("free", { $0.free }, { var f = $0; f.free = false; return f }),
        ("cats", { !$0.cats.isEmpty }, { var f = $0; f.cats = []; return f }),
        ("seatsLeft", { $0.seatsLeft }, { var f = $0; f.seatsLeft = false; return f }),
        ("almostFull", { $0.almostFull }, { var f = $0; f.almostFull = false; return f }),
        ("type", { !$0.typeFilters.isEmpty }, { var f = $0; f.typeFilters = []; return f }),
    ]

    /// "+6 events if you drop the date" — for empty / near-empty results. Each hint removes ONE active filter;
    /// sorted by events gained (desc), then the fixed order above. Only hints that add at least one event.
    static func relaxationHints(_ items: [Item], _ f: Filters, now: Date, offsetMin: Int = defaultOffsetMin, limit: Int = 2) -> [RelaxHint] {
        let base = apply(items, f, now: now, offsetMin: offsetMin).count
        let hints: [(hint: RelaxHint, order: Int)] = relaxations.enumerated().compactMap { order, r in
            guard r.active(f) else { return nil }
            let after = r.relax(f)
            let gain = apply(items, after, now: now, offsetMin: offsetMin).count - base
            return gain > 0 ? (RelaxHint(id: r.id, gain: gain, filters: after), order) : nil
        }
        return hints
            .sorted { $0.hint.gain != $1.hint.gain ? $0.hint.gain > $1.hint.gain : $0.order < $1.order }
            .prefix(limit).map(\.hint)
    }

    // MARK: Sorting

    /// nil sorts last; returns nil on a tie so the caller falls back to the incoming order.
    private static func nullsLast<T: Comparable>(_ a: T?, _ b: T?, ascending: Bool) -> Bool? {
        switch (a, b) {
        case (nil, nil): return nil
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x == y ? nil : (ascending ? x < y : x > y)
        }
    }

    /// Stable sort; ties keep the incoming order (so the caller's own ranking survives). Unknown mode = unchanged.
    static func sort(_ items: [Item], mode: String) -> [Item] {
        let by: ((Item, Item) -> Bool?)?
        switch mode {
        case "soonest": by = { nullsLast($0.startsAt, $1.startsAt, ascending: true) }
        case "nearest": by = { nullsLast($0.distanceKm, $1.distanceKm, ascending: true) }
        case "popular": by = { nullsLast($0.popularity, $1.popularity, ascending: false) }
        case "price": by = { nullsLast($0.priceVnd, $1.priceVnd, ascending: true) }
        default: by = nil
        }
        guard let by else { return items }
        return items.enumerated()
            .sorted { a, b in by(a.element, b.element) ?? (a.offset < b.offset) }
            .map(\.element)
    }

    // MARK: Price distribution

    static func median(_ values: [Double]) -> Double? {
        let v = values.filter(\.isFinite).sorted()
        guard !v.isEmpty else { return nil }
        let mid = v.count / 2
        return v.count % 2 == 1 ? v[mid] : (v[mid - 1] + v[mid]) / 2
    }

    /// Equal-width histogram of PAID prices; nil when there are none.
    /// The one currency the price histogram/bounds work in: VND unless every PAID event being filtered is USD.
    static func dominantCurrency(_ items: [Item]) -> String {
        let paid = items.filter { ($0.priceVnd ?? 0) > 0 }
        return !paid.isEmpty && paid.allSatisfy { $0.currency == "USD" } ? "USD" : "VND"
    }

    /// Prices that may feed the histogram/bounds for `currency`: that currency's events, plus free ones (0 is 0
    /// in any currency). Never a cent amount next to a đồng one.
    static func priceMarket(_ items: [Item], currency: String) -> [Int] {
        items.filter { $0.currency == currency || $0.priceVnd == 0 }.compactMap(\.priceVnd)
    }

    static func priceHistogram(_ prices: [Int], buckets: Int = 12) -> Histogram? {
        let v = prices.filter { $0 > 0 }
        guard let lo = v.min(), let hi = v.max(), buckets > 0 else { return nil }
        var counts = Array(repeating: 0, count: buckets)
        for p in v {
            let i = hi == lo ? 0 : min(Int((Double(p - lo) / Double(hi - lo) * Double(buckets)).rounded(.down)), buckets - 1)
            counts[i] += 1
        }
        return Histogram(min: lo, max: hi, counts: counts)
    }

    /// The bucket a price falls in (for highlighting the selected range).
    static func bucketIndex(_ hist: Histogram?, price: Int?) -> Int? {
        guard let hist, let price else { return nil }
        let n = hist.counts.count
        if hist.max == hist.min { return 0 }
        let raw = Int((Double(price - hist.min) / Double(hist.max - hist.min) * Double(n)).rounded(.down))
        return max(0, min(raw, n - 1))
    }
}

// MARK: - Shared labels (same wording as HomeFilterSheet.jsx DATE_LABELS / SORT_LABELS / RELAX_LABELS)

extension HomeDiscovery {
    static let dateLabels: [String: (vi: String, en: String)] = [
        "any": ("Mọi lúc", "Any time"), "today": ("Hôm nay", "Today"), "tomorrow": ("Ngày mai", "Tomorrow"),
        "weekend": ("Cuối tuần này", "This weekend"), "week": ("7 ngày tới", "Next 7 days"),
    ]
    static let sortLabels: [String: (vi: String, en: String)] = [
        "soonest": ("Sớm nhất", "Soonest"), "nearest": ("Gần nhất", "Nearest"),
        "popular": ("Nổi bật", "Popular"), "price": ("Giá thấp → cao", "Price: low to high"),
    ]
    static let relaxLabels: [String: (vi: String, en: String)] = [
        "date": ("bỏ ngày", "any date"), "price": ("bỏ khoảng giá", "any price"), "free": ("bỏ \"Miễn phí\"", "not only free"),
        "cats": ("mọi danh mục", "every category"), "seatsLeft": ("cả sự kiện hết chỗ", "include sold out"),
        "almostFull": ("bỏ \"Sắp hết\"", "not only almost full"),
        "type": ("bỏ bộ lọc theo loại", "no type filters"),
    ]

    /// Home category row + filter-sheet categories (web CATEGORY_DEFS).
    static let categories = EventTypes.categoryDefs(withAll: true) // src/data/eventTypeProfiles.json
}

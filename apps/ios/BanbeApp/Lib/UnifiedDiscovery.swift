import Foundation

// Unified discovery (note 99, switch `unified_discovery`): Home, Search and Map share ONE search, type, time, price
// and sort. Pure rules, 1:1 with src/lib/unifiedDiscovery.js (same names); shared cases in
// tests/fixtures/unified-discovery.json (BanbeAppTests/UnifiedDiscoveryTests.swift).
enum UnifiedDiscovery {
    /// Home's tabs ARE the shared time: For You = any time, Tonight = today, Weekend = the weekend, All events = any time.
    static let DATE_FOR_TAB: [String: String] = ["foryou": "any", "tonight": "today", "weekend": "weekend", "all": "any"]

    static func dateForTab(_ tab: HomeHeroTab) -> String { DATE_FOR_TAB[tab.rawValue] ?? "any" }

    /// The tab a shared date shows as selected. Tomorrow / next 7 days have no tab of their own and read as For You.
    static func tabForDate(_ date: String) -> String {
        if date == "today" { return "tonight" }
        if date == "weekend" { return "weekend" }
        return "foryou"
    }

    static func heroTab(forDate date: String) -> HomeHeroTab { HomeHeroTab(rawValue: tabForDate(date)) ?? .foryou }

    /// The tab Home shows as selected (web `resolveTab`). For You and All events share the date "any", so `allPicked`
    /// (the reader last picked All events) breaks the tie; a tab with its own date wins over the pick. Without For You
    /// preferences (`hasPrefs` false) there is no For You tab: whatever would read as it is All events.
    static func resolveTab(date: String, allPicked: Bool, hasPrefs: Bool = true) -> HomeHeroTab {
        effectiveTab(date == "any" && allPicked ? .all : heroTab(forDate: date), hasPrefs: hasPrefs)
    }

    // MARK: For You vs All events (bug 2026-11-19: both listed the same events). Web twins: visibleTabs, defaultTab,
    // effectiveTab, tabSet; cases in tests/fixtures/unified-discovery.json "tabRules".

    /// Tabs the viewer sees: For You only with preferences; "hosting" last, only when `canHost`.
    static func visibleTabs(hasPrefs: Bool, canHost: Bool = false) -> [String] {
        HomeHeroTab.allCases.map(\.rawValue).filter { $0 != "foryou" || hasPrefs } + (canHost ? ["hosting"] : [])
    }

    /// The tab Home opens on: For You with preferences, otherwise All events.
    static func defaultTab(hasPrefs: Bool) -> HomeHeroTab { hasPrefs ? .foryou : .all }

    /// A stored/selected tab, resolved: For You without preferences is All events.
    static func effectiveTab(_ tab: HomeHeroTab, hasPrefs: Bool) -> HomeHeroTab { tab == .foryou && !hasPrefs ? .all : tab }

    /// Which set a tab lists: "forYou" (the matcher's picks) for For You, else "all" (every open event; time tabs add their time).
    static func tabSet(_ tab: HomeHeroTab) -> String { tab == .foryou ? "forYou" : "all" }

    /// How many type tiles Home shows before the "All types" tile.
    static let TILE_TYPES = 5

    /// The type tiles: the `n` busiest types for the current search, time and price, most events first, ties in
    /// catalogue order.
    static func topTypes(_ counts: [String: Int], keys: [String], n: Int = TILE_TYPES) -> [String] {
        Array(keys.enumerated()
            .sorted { a, b in
                let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .prefix(n).map(\.element))
    }

    /// The "All types" tile turns into the picked type when that type is not one of the tiles; nil otherwise.
    static func pickedTileType(_ selected: String?, tiles: [String]) -> String? {
        guard let selected, !selected.isEmpty, selected != "all", !tiles.contains(selected) else { return nil }
        return selected
    }

    /// Lowercased, accents removed, đ → d (the web's `fold`).
    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// The type sheet's order: types with events first (most first, then catalogue order), then the empty ones in
    /// catalogue order. `query` keeps only names containing it (accent-folded).
    static func typeSheetOrder(_ counts: [String: Int], keys: [String], nameOf: (String) -> String = { $0 },
                               query: String = "") -> [String] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return keys.enumerated()
            .filter { q.isEmpty || fold(nameOf($0.element)).contains(q) }
            .sorted { a, b in
                let ca = counts[a.element] ?? 0, cb = counts[b.element] ?? 0
                if (ca > 0) != (cb > 0) { return ca > 0 }
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// What a map area bubble lists under its name: its types, busiest first, then catalogue order, at most `max`,
    /// plus how many more there are. `cats` = type key → count in that area.
    static func areaGlyphs(_ cats: [String: Int], keys: [String], max: Int = 4) -> (shown: [String], more: Int) {
        func idx(_ k: String) -> Int { keys.firstIndex(of: k) ?? keys.count }
        let order = cats.filter { $0.value > 0 }.map(\.key)
            .sorted { a, b in
                let ca = cats[a] ?? 0, cb = cats[b] ?? 0
                if ca != cb { return ca > cb }
                let ia = idx(a), ib = idx(b)
                return ia != ib ? ia < ib : a < b
            }
        return (Array(order.prefix(max)), Swift.max(0, order.count - max))
    }

    /// What the Filters button owns (and counts on its badge): type, price, seats, almost full, event-type chips,
    /// sort. Time has its own control (the tabs / the Map's time chip) and the query has search.
    static func ownedFilterCount(_ f: HomeDiscovery.Filters, sort: String?) -> Int {
        (f.cats.isEmpty ? 0 : 1)
            + (f.free || f.priceMin != nil || f.priceMax != nil ? 1 : 0)
            + (f.seatsLeft ? 1 : 0) + (f.almostFull ? 1 : 0)
            + (f.typeFilters.isEmpty ? 0 : 1)
            + ((sort ?? "soonest") != "soonest" ? 1 : 0)
    }

    // MARK: Map time chip ↔ shared date (iOS only: the Map's day menu keys are MapTimeWindow's)

    /// The Map's day choice as the shared date: Today → today, Tomorrow → tomorrow, the weekend day → weekend,
    /// Next week → week, All days → any.
    static func dateForMapDay(_ key: String) -> String {
        switch key {
        case "today": return "today"
        case "tomorrow": return "tomorrow"
        case "weekend": return "weekend"
        case "nextWeek": return "week"
        default: return "any"
        }
    }

    /// The shared date as the Map's day key ("all" for any time or a date the Map has no day for).
    static func mapDayForDate(_ date: String) -> String {
        switch date {
        case "today", "tonight": return "today"
        case "tomorrow": return "tomorrow"
        case "weekend": return "weekend"
        case "week": return "nextWeek"
        default: return "all"
        }
    }

    // MARK: Home "Near you" (bug 2026-11-19: web and iOS listed different events)

    /// Open = Home may still offer it: not cancelled, a known start, not past its end (`endsAt`, nil = unknown).
    /// Web twin `isOpenItem`; shared cases in tests/fixtures/unified-discovery.json "nearYou".
    static func isOpenItem(_ it: HomeDiscovery.Item, now: Date) -> Bool {
        guard !it.cancelled, it.startsAt != nil else { return false }
        if let end = it.endsAt, now >= end { return false }
        return true
    }

    /// The list under Home's hero, the map banner, the state bar and the end card, on both apps (web twin `nearYou`):
    /// every open item (area + query already applied) narrowed by Home's filters, soonest first by start unless a sort
    /// is picked. The For You RANKING is never the base. `total` = before the filters the Filters button owns; with
    /// unified discovery (`tabOwnsTime`) the tab's time stays applied, so "N of M" never counts another tab's events.
    /// The map banner and the state bar show `rows.count`, exactly the list.
    static func nearYou(_ items: [HomeDiscovery.Item], filters: HomeDiscovery.Filters, sort: String?, now: Date,
                        tabOwnsTime: Bool, offsetMin: Int = HomeDiscovery.defaultOffsetMin,
                        tab: HomeHeroTab? = nil, forYouKeys: Set<String>? = nil)
        -> (rows: [HomeDiscovery.Item], total: Int) {
        // On the For You tab the base is only the matcher's picks (`forYouKeys`); other tabs ignore them.
        let picks: Set<String>? = tab.map { tabSet($0) == "forYou" } == true ? forYouKeys : nil
        let open = items.filter { isOpenItem($0, now: now) && (picks?.contains($0.key) ?? true) }
        var timeOnly = HomeDiscovery.Filters.default
        timeOnly.date = filters.date
        let base = tabOwnsTime ? HomeDiscovery.apply(open, timeOnly, now: now, offsetMin: offsetMin) : open
        let narrowed = HomeDiscovery.apply(base, filters, now: now, offsetMin: offsetMin)
        let mode = sort.flatMap { HomeDiscovery.sortModes.contains($0) ? $0 : nil } ?? "soonest"
        return (HomeDiscovery.sort(narrowed, mode: mode), base.count)
    }
}

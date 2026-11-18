import Foundation

// Unified discovery (note 99, switch `unified_discovery`): Home, Search and Map share ONE search, type, time, price
// and sort. Pure rules, 1:1 with src/lib/unifiedDiscovery.js (same names); shared cases in
// tests/fixtures/unified-discovery.json (BanbeAppTests/UnifiedDiscoveryTests.swift).
enum UnifiedDiscovery {
    /// Home's tabs ARE the shared time: For You = any time, Tonight = today, Weekend = the weekend.
    static let DATE_FOR_TAB: [String: String] = ["foryou": "any", "tonight": "today", "weekend": "weekend"]

    static func dateForTab(_ tab: HomeHeroTab) -> String { DATE_FOR_TAB[tab.rawValue] ?? "any" }

    /// The tab a shared date shows as selected. Tomorrow / next 7 days have no tab of their own and read as For You.
    static func tabForDate(_ date: String) -> String {
        if date == "today" { return "tonight" }
        if date == "weekend" { return "weekend" }
        return "foryou"
    }

    static func heroTab(forDate date: String) -> HomeHeroTab { HomeHeroTab(rawValue: tabForDate(date)) ?? .foryou }

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
}

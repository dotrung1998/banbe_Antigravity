import Foundation

/// Map search matcher (Issue 2 fix, 2026-09-30) — the ONE canonical text
/// matcher for MapExploreView's search box, mirroring web's identical
/// `src/lib/search.js`. Keep both files in lockstep: same normalization
/// rules, same AND-token semantics, same category-alias dictionary.
///
/// Root cause this fixes: `visibleEvents`'s search filter used to match
/// only `name`/`area`/`keywords` — never the event's own category label/
/// key — while the category chip filters by `cat_key` equality directly.
/// Typing a genuine substring of a category name (e.g. "Supp" for "Supper
/// Club") could return FEWER events than clearing the query and tapping
/// that category's chip, whenever an event's `keywords` column was empty.
enum SearchMatch {
    /// Vietnamese diacritics + đ/Đ -> plain ASCII, case-folded, whitespace
    /// collapsed. `folding(options: .diacriticInsensitive)` handles ordinary
    /// combining-mark accents; đ/Đ don't fold that way (they're their own
    /// Latin letters in Unicode, not a base+combining-mark decomposition),
    /// so they're handled as an explicit extra replace, same as web's
    /// explicit `.replace(/đ/g, 'd')`.
    static func normalize(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        let dFolded = folded.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
        let collapsed = dFolded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    /// Synonyms per category (VI + EN, accent-free since the document is folded anyway) come from the event
    /// type profiles (src/data/eventTypeProfiles.json), the same file the web reads — never invented categories.
    static let categoryAliases: [String: [String]] = EventTypes.searchAliases

    /// Builds ONE normalized search document per event. Category/name
    /// coverage never depends on `keywords` being populated — it's always
    /// included from `catKey`/`catLabel` directly; `keywords` only ever
    /// SUPPLEMENTS this, it never replaces it.
    static func buildDoc(for event: MapEventRow) -> String {
        var parts: [String] = [event.name, event.area]
        if let catLabel = event.catLabel { parts.append(catLabel) }
        if let catKey = event.catKey {
            parts.append(catKey)
            parts.append(contentsOf: categoryAliases[catKey] ?? [])
        }
        if let city = event.city { parts.append(city) }
        if let organizerName = event.organizerName { parts.append(organizerName) }
        if let description = event.description { parts.append(description) }
        if let intro = event.intro { parts.append(intro) }
        parts.append(contentsOf: event.keywords ?? [])
        return normalize(parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " "))
    }

    /// The same document for a Home/Search `CatalogEvent` (real or demo), so the Search screen
    /// (note 50) and Map agree on what a query finds.
    static func buildDoc(for event: CatalogEvent) -> String {
        var parts: [String] = [event.name, event.locationLabel ?? "", event.catDisplay, event.cat]
        for key in [event.catKey, event.cat2Key].compactMap({ $0 }) where key != "all" {
            parts.append(key)
            parts.append(contentsOf: categoryAliases[key] ?? [])
        }
        if let city = event.location?.city { parts.append(city) }
        parts.append(event.orgName.isEmpty ? event.hostShort : event.orgName)
        parts.append(event.desc)
        if let intro = event.intro { parts.append(intro) }
        parts.append(contentsOf: event.keywords ?? [])
        // Event type facts (migration 203/204): "jazz", "nhiếp ảnh", a lineup name, "18+", "BYO"…
        parts.append(contentsOf: EventTypes.detailSearchTerms(EventTypes.profile(event.catKey), event.details))
        return normalize(parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " "))
    }

    /// AND semantics across whitespace-separated tokens, substring/prefix
    /// per token (not exact-word) — "supp" must match inside "supper club".
    static func matches(doc: String, query rawQuery: String) -> Bool {
        let q = normalize(rawQuery)
        guard !q.isEmpty else { return true }
        let tokens = q.components(separatedBy: " ").filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { doc.contains($0) }
    }
}

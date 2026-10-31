import Foundation

/// Event type profiles: what changes per kind of event (supper club, music…) in the create flow, Event Detail
/// and Home. The data is src/data/eventTypeProfiles.json, bundled as-is (apps/ios/project.yml); this is the
/// logic on top of it. The first picked category is the PRIMARY type (benchmarks, card line, Home filters). Note 69
/// (migration 207): a second pick now shapes the form and the detail page too: `combined` merges both types' fields,
/// required list and facts (shared alcohol / minimum age once). The second key is stored as `details.cat2`.
/// Web twin: src/lib/eventTypes.js. Shared vectors: tests/fixtures/event-types.json.
struct EventTypeProfile: Decodable {
    struct Pair: Decodable, Equatable {
        let vi: String
        let en: String
        func text(_ lang: String) -> String { lang == "vi" ? vi : en }
    }
    struct Option: Decodable, Equatable {
        let id: String
        let vi: String
        let en: String
        /// The card's shorter wording ("BYO", "Drop-in"); the full label otherwise.
        let short: Pair?
    }
    struct DetailField: Decodable {
        let kind: String // multi | enum | text | list
        let label: Pair
        let options: [Option]?
        /// text: max characters; list: max items.
        let max: Int?
        /// list: max characters per item.
        let itemMax: Int?
        let placeholder: Pair?
        let hint: Pair?
        /// list: "{n} artists" on cards instead of the first item.
        let countLabel: Pair?
    }
    struct Wizard: Decodable {
        var required: [String]
        let includedTitle: Pair?
        let includedPlaceholder: Pair?
        var details: [String]
    }
    struct Detail: Decodable {
        let includedTitle: Pair?
        let facts: [String]
    }
    /// Card line: an optional table size ("table"), then each listed field.
    struct Card: Decodable { let capacity: String?; let fields: [String]? }
    struct Recipe: Decodable { let ingredients: [String] }
    struct HomeFilter: Decodable, Identifiable {
        let id: String
        let field: String
        let value: [String]
        let vi: String
        let en: String

        private enum CodingKeys: String, CodingKey { case id, field, value, vi, en }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            field = try c.decode(String.self, forKey: .field)
            if let many = try? c.decode([String].self, forKey: .value) { value = many } else { value = [try c.decode(String.self, forKey: .value)] }
            vi = try c.decode(String.self, forKey: .vi)
            en = try c.decode(String.self, forKey: .en)
        }
    }
    struct Home: Decodable { let filters: [HomeFilter] }

    let key: String
    let label: Pair?
    let emoji: String?
    let icon: [String: String]?
    let aliases: [String]?
    let keywordSeeds: [String: [String]]?
    var wizard: Wizard?
    var detailFields: [String: DetailField]?
    let detail: Detail?
    let card: Card?
    let home: Home?
    let recipe: Recipe?

    /// The generic event: today's behaviour, used for unknown or legacy keys.
    static func generic(_ key: String) -> EventTypeProfile {
        EventTypeProfile(key: key, label: nil, emoji: nil, icon: nil, aliases: [], keywordSeeds: [:], wizard: nil,
                         detailFields: nil, detail: nil, card: nil, home: nil, recipe: nil)
    }
}

/// One published detail value: a list (multi) or a single string (enum, text).
enum EventDetailValue: Hashable {
    case list([String])
    case text(String)

    init?(json: Any?) {
        if let a = json as? [String] { self = .list(a) } else if let s = json as? String { self = .text(s) } else { return nil }
    }
    var json: Any {
        switch self {
        case .list(let a): return a
        case .text(let s): return s
        }
    }
}

typealias EventDetails = [String: EventDetailValue]

/// `events.details` as stored: {} or {"v": 1, <field>: <list or string>}. Decodes leniently (unknown value
/// shapes and the version key are skipped), so a row from a newer server never fails to load.
struct EventDetailsPayload: Codable, Hashable {
    var values: EventDetails

    init(_ values: EventDetails = [:]) { self.values = values }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        var out: EventDetails = [:]
        if let c = try? decoder.container(keyedBy: Key.self) {
            for k in c.allKeys where k.stringValue != "v" {
                if let a = try? c.decode([String].self, forKey: k) { out[k.stringValue] = .list(a) }
                else if let s = try? c.decode(String.self, forKey: k) { out[k.stringValue] = .text(s) }
            }
        }
        values = out
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        guard !values.isEmpty else { return }
        try c.encode(EventTypes.detailsVersion, forKey: Key(stringValue: "v"))
        for (k, v) in values {
            switch v {
            case .list(let a): try c.encode(a, forKey: Key(stringValue: k))
            case .text(let s): try c.encode(s, forKey: Key(stringValue: k))
            }
        }
    }
}

enum EventTypes {
    static let detailsVersion = 1

    private struct Common: Decodable { let required: [String]; let detailFields: [String: EventTypeProfile.DetailField] }
    private struct File: Decodable { let version: Int; let common: Common?; let types: [EventTypeProfile] }
    /// The shared fields' order in the form (alcohol, then minimum age), as in the JSON.
    private static let commonOrder = ["alcohol", "min_age"]

    /// `common` (alcohol + minimum age) is merged into every type: its fields, its form block and its required list.
    static let all: [EventTypeProfile] = {
        guard let url = Bundle.main.url(forResource: "eventTypeProfiles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            assertionFailure("eventTypeProfiles.json missing from the bundle — run xcodegen generate")
            return []
        }
        guard let common = file.common else { return file.types }
        let commonIDs = commonOrder.filter { common.detailFields[$0] != nil }
            + common.detailFields.keys.sorted().filter { !commonOrder.contains($0) }
        return file.types.map { t in
            var p = t
            p.detailFields = (t.detailFields ?? [:]).merging(common.detailFields) { _, new in new }
            if var w = t.wizard {
                w.required += common.required
                w.details += commonIDs
                p.wizard = w
            }
            return p
        }
    }()

    /// Every detail field id any type uses (for the create form's field anchors).
    static var detailFieldIDs: Set<String> { Set(all.flatMap { ($0.detailFields ?? [:]).keys }) }

    static var keys: [String] { all.map(\.key) }

    static func profile(_ key: String?) -> EventTypeProfile {
        all.first { $0.key == key } ?? .generic(key ?? "")
    }

    /// True when the type changes the form, the detail page or Home (it has more than an identity).
    static func isShaped(_ p: EventTypeProfile) -> Bool {
        p.wizard != nil || p.detail != nil || p.card != nil || p.home != nil
    }

    /// (key, vi, en) in display order, optionally with the leading "All".
    static func categoryDefs(withAll: Bool = false) -> [(key: String, vi: String, en: String)] {
        let defs = all.map { (key: $0.key, vi: $0.label?.vi ?? $0.key, en: $0.label?.en ?? $0.key) }
        return withAll ? [(key: "all", vi: "Tất cả", en: "All")] + defs : defs
    }

    static var emoji: [String: String] {
        Dictionary(uniqueKeysWithValues: all.compactMap { p in p.emoji.map { (p.key, $0) } })
    }

    /// Search synonyms per category key (already accent-free, as the matcher folds accents).
    static var searchAliases: [String: [String]] {
        var out: [String: [String]] = ["all": []]
        for p in all { out[p.key] = p.aliases ?? [] }
        return out
    }

    // MARK: Two categories + introduction style (note 69, migration 207)

    /// Keys stored in `events.details` that are not type facts: the second category and the introduction's style.
    static let extraKeys = ["cat2", "intro_font", "intro_color"]
    static let introFonts = ["sans", "serif", "rounded", "mono"]
    static let introColors = ["ink", "ink2", "clay", "honey", "alert"]

    private static func unique(_ a: [String]) -> [String] {
        var seen = Set<String>()
        return a.filter { seen.insert($0).inserted }
    }

    /// One profile for one or two picked categories. One key = that type unchanged. Two = the first type's identity
    /// (key, card, Home filters, benchmarks) with both types' fields, form blocks, required fields, facts and recipe;
    /// the shared fields (alcohol, minimum age) appear once, after both types' own fields.
    static func combined(_ keys: [String]) -> EventTypeProfile {
        let p = profile(keys.first)
        guard keys.count > 1, keys[1] != keys[0] else { return p }
        let q = profile(keys[1])
        guard isShaped(q) else { return p }
        let fields = (p.detailFields ?? [:]).merging(q.detailFields ?? [:]) { a, _ in a }
        var wizard = p.wizard ?? q.wizard
        if let a = p.wizard, let b = q.wizard {
            let shared = commonOrder
            wizard?.details = unique(a.details.filter { !shared.contains($0) } + b.details.filter { !shared.contains($0) }
                                     + a.details.filter { shared.contains($0) })
            wizard?.required = unique(a.required + b.required)
        }
        let detail: EventTypeProfile.Detail? = (p.detail == nil && q.detail == nil) ? nil
            : .init(includedTitle: p.detail?.includedTitle ?? q.detail?.includedTitle,
                    facts: unique((p.detail?.facts ?? []) + (q.detail?.facts ?? [])))
        let recipe: EventTypeProfile.Recipe? = (p.recipe == nil && q.recipe == nil) ? nil
            : .init(ingredients: unique((p.recipe?.ingredients ?? []) + (q.recipe?.ingredients ?? [])))
        return EventTypeProfile(key: p.key, label: p.label, emoji: p.emoji, icon: p.icon, aliases: p.aliases,
                                keywordSeeds: p.keywordSeeds, wizard: wizard, detailFields: fields, detail: detail,
                                card: p.card, home: p.home, recipe: recipe)
    }

    /// The second category stored on a published event (`details.cat2`), when it is a known type other than the first.
    static func secondCategory(_ details: EventDetails, primary: String?) -> String? {
        guard case .text(let k)? = details["cat2"], k != primary, all.contains(where: { $0.key == k }) else { return nil }
        return k
    }

    /// A published event's profile: its own type plus the second category, if any.
    static func eventProfile(catKey: String?, details: EventDetails) -> EventTypeProfile {
        combined([catKey, secondCategory(details, primary: catKey)].compactMap { $0 })
    }

    /// Which picked type a field's draft value is kept under: the first type that has it as its OWN field, the first
    /// type for shared fields (alcohol, minimum age).
    static func owner(of field: String, keys: [String]) -> String? {
        guard let first = keys.first else { return nil }
        if commonOrder.contains(field) { return first }
        return keys.first { k in profile(k).detailFields?[field] != nil } ?? first
    }

    /// The create form's draft as one set of values for the picked types (each field read from its owner).
    static func mergedDraft(_ keys: [String], _ draft: [String: EventDetails]) -> EventDetails {
        let p = combined(keys)
        var out: EventDetails = [:]
        for id in (p.detailFields ?? [:]).keys {
            if let k = owner(of: id, keys: keys), let v = draft[k]?[id] { out[id] = v }
        }
        return out
    }

    /// The introduction's stored style, nil parts when unset or unknown.
    static func introStyle(_ details: EventDetails) -> (font: String?, color: String?) {
        var font: String?, color: String?
        if case .text(let f)? = details["intro_font"], introFonts.contains(f) { font = f }
        if case .text(let c)? = details["intro_color"], introColors.contains(c) { color = c }
        return (font, color)
    }

    /// What `set_event_details` gets for a create draft: both types' facts cleaned, plus `cat2` and the intro style.
    static func publishDetails(keys: [String], draft: [String: EventDetails], introFont: String?, introColor: String?) -> EventDetails {
        var out = clean(combined(keys), mergedDraft(keys, draft))
        if keys.count > 1, keys[1] != keys[0], all.contains(where: { $0.key == keys[1] }) { out["cat2"] = .text(keys[1]) }
        if let f = introFont, introFonts.contains(f), f != "sans" { out["intro_font"] = .text(f) }
        if let c = introColor, introColors.contains(c), c != "ink" { out["intro_color"] = .text(c) }
        return out
    }

    static func requiredFields(_ p: EventTypeProfile) -> [String] {
        p.wizard?.required ?? CreateProgress.defaultRequired
    }

    /// Required detail fields still empty for this type: [id: true] (the create form's progress reads it).
    static func missingDetails(_ p: EventTypeProfile, _ raw: EventDetails) -> [String: Bool] {
        let cleaned = clean(p, raw)
        let fields = p.detailFields ?? [:]
        var out: [String: Bool] = [:]
        for id in requiredFields(p) where fields[id] != nil { out[id] = cleaned[id] == nil }
        return out
    }

    /// Cleaned the same way the server validates (validate_event_details, migration 204): known keys and option
    /// ids only, text and list items trimmed and capped (a list keeps its order, drops blanks and repeats, at most
    /// `max` items). Empty when nothing is set, so an untouched form stores nothing.
    /// Encode with `json(_:)`, which adds the version.
    static func clean(_ p: EventTypeProfile, _ raw: EventDetails) -> EventDetails {
        guard let fields = p.detailFields else { return [:] }
        var out: EventDetails = [:]
        for (id, def) in fields {
            let ids = (def.options ?? []).map(\.id)
            switch (def.kind, raw[id]) {
            case ("multi", .list(let v)?):
                let kept = ids.filter(v.contains)
                if !kept.isEmpty { out[id] = .list(kept) }
            case ("enum", .text(let v)?) where ids.contains(v):
                out[id] = .text(v)
            case ("text", .text(let v)?):
                let t = String(v.trimmingCharacters(in: .whitespacesAndNewlines).prefix(def.max ?? 80))
                if !t.isEmpty { out[id] = .text(t) }
            case ("list", .list(let v)?):
                var items: [String] = []
                for x in v {
                    let t = String(x.trimmingCharacters(in: .whitespacesAndNewlines).prefix(def.itemMax ?? 60))
                    if !t.isEmpty && !items.contains(t) { items.append(t) }
                }
                if !items.isEmpty { out[id] = .list(Array(items.prefix(def.max ?? 6))) }
            default: break
            }
        }
        return out
    }

    /// The payload for `set_event_details`: {} or {"v": 1, …}.
    static func json(_ details: EventDetails) -> [String: Any] {
        guard !details.isEmpty else { return [:] }
        var out: [String: Any] = ["v": detailsVersion]
        for (k, v) in details { out[k] = v.json }
        return out
    }

    /// Reads an `events.details` JSON object (the version key is skipped).
    static func details(fromJSON obj: Any?) -> EventDetails {
        guard let dict = obj as? [String: Any] else { return [:] }
        var out: EventDetails = [:]
        for (k, v) in dict where k != "v" { if let d = EventDetailValue(json: v) { out[k] = d } }
        return out
    }

    /// Draft values kept for other types the host tried earlier, which would not be published.
    static func droppedDetailTypes(primary: String, draft: [String: EventDetails]) -> [String] {
        draft.keys.sorted().filter { $0 != primary && !clean(profile($0), draft[$0] ?? [:]).isEmpty }
    }

    private static func optionLabel(_ def: EventTypeProfile.DetailField, _ id: String, _ lang: String, short: Bool = false) -> String? {
        guard let o = (def.options ?? []).first(where: { $0.id == id }) else { return nil }
        if short, let s = o.short { return s.text(lang) }
        return lang == "vi" ? o.vi : o.en
    }

    struct Fact: Equatable { let id: String; let label: String; let value: String }

    /// Facts for Event Detail, in the order the profile lists them; empty values are skipped.
    static func detailFacts(_ p: EventTypeProfile, _ details: EventDetails, lang: String) -> [Fact] {
        let fields = p.detailFields ?? [:]
        return (p.detail?.facts ?? []).compactMap { id in
            guard let def = fields[id], let v = details[id] else { return nil }
            let value: String?
            switch (def.kind, v) {
            case ("multi", .list(let a)): value = a.compactMap { optionLabel(def, $0, lang) }.joined(separator: ", ")
            case ("enum", .text(let s)): value = optionLabel(def, s, lang)
            case ("text", .text(let s)): value = s
            case ("list", .list(let a)): value = a.joined(separator: ", ")
            default: value = nil
            }
            guard let value, !value.isEmpty else { return nil }
            return Fact(id: id, label: def.label.text(lang), value: value)
        }
    }

    /// The short type-aware line under a Home card, or nil. From the profile's `card`: an optional table size, then
    /// each listed field (a choice's short label, a list's count or first item).
    static func cardLine(_ p: EventTypeProfile, capacity: Int, details: EventDetails, lang: String) -> String? {
        guard let card = p.card else { return nil }
        var parts: [String] = []
        if card.capacity == "table", capacity > 0 { parts.append(lang == "vi" ? "Bàn \(capacity) người" : "Table for \(capacity)") }
        for id in card.fields ?? [] {
            guard let def = p.detailFields?[id], let v = details[id] else { continue }
            switch (def.kind, v) {
            case ("multi", .list(let a)): if let f = a.first, let l = optionLabel(def, f, lang, short: true) { parts.append(l) }
            case ("enum", .text(let s)): if let l = optionLabel(def, s, lang, short: true) { parts.append(l) }
            case ("list", .list(let a)) where !a.isEmpty:
                parts.append(def.countLabel.map { $0.text(lang).replacingOccurrences(of: "{n}", with: String(a.count)) } ?? a[0])
            default: break
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Words an event's facts add to its search document: option labels in both languages, list items, text.
    static func detailSearchTerms(_ p: EventTypeProfile, _ details: EventDetails) -> [String] {
        let fields = p.detailFields ?? [:]
        var out: [String] = []
        for (id, v) in details {
            guard let def = fields[id] else { continue }
            let values: [String] = { switch v { case .list(let a): return a; case .text(let s): return [s] } }()
            if def.kind == "multi" || def.kind == "enum" {
                for x in values { if let o = def.options?.first(where: { $0.id == x }) { out += [o.vi, o.en] } }
            } else {
                out += values
            }
        }
        return out
    }

    static func homeFilters(_ p: EventTypeProfile) -> [EventTypeProfile.HomeFilter] { p.home?.filters ?? [] }

    /// A Home type chip by id (ids are unique across types), or nil.
    static func typeFilter(_ id: String) -> EventTypeProfile.HomeFilter? {
        all.lazy.flatMap(homeFilters).first { $0.id == id }
    }

    static func matches(_ f: EventTypeProfile.HomeFilter, _ details: EventDetails) -> Bool {
        switch details[f.field] {
        case .list(let a)?: return a.contains(where: f.value.contains)
        case .text(let s)?: return f.value.contains(s)
        case nil: return false
        }
    }

    /// Keyword ideas for the create form: the type's own seeds, the area, then what other hosts use.
    /// Already-typed and dismissed ones are skipped; at most `limit`.
    static func keywordSuggestions(_ p: EventTypeProfile, lang: String, area: String, benchmark: [String],
                                   typed: [String], dismissed: [String], limit: Int = 5) -> [String] {
        let skip = Set((typed + dismissed).map(SearchMatch.normalize))
        var seen = Set<String>()
        var out: [String] = []
        for k in (p.keywordSeeds?[lang == "vi" ? "vi" : "en"] ?? []) + [area] + benchmark {
            let f = SearchMatch.normalize(k)
            guard !f.isEmpty, !skip.contains(f), !seen.contains(f) else { continue }
            seen.insert(f)
            out.append(f)
            if out.count >= limit { break }
        }
        return out
    }
}

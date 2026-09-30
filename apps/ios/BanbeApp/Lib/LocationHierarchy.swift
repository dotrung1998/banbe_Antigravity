import Foundation

/// Location hierarchy (migration 112) — the ONE place the discovery
/// feed's location tree is modelled on iOS. Built to the same spec as
/// web's `src/state/GocContext.jsx` hierarchy (implemented independently):
///
///   Vietnam (VN) → State/Province → legacy "familiar area" (`events.area`)
///                → neighborhood
///   United States (US) → State → City → neighborhood
///
/// VN/US roots are always shown, even with zero events (an honest empty
/// state — nothing is ever seeded). An event with no `state_province`
/// (true today for every Ho Chi Minh City row — it's a direct-controlled
/// municipality, most geocoders return no "state" for it) groups DIRECTLY
/// under its country instead of being hidden. An event with no
/// `country_code` at all lands under a separate "country not set" root,
/// shown only when such events exist — never silently guessed as VN.
///
/// Node IDs are deterministic composite keys built only from the RAW
/// column strings (never a translated label, never an array index):
///
///   "all"                                   everything
///   "c:VN"                                  country
///   "c:VN|s:Tỉnh Lâm Đồng"                  state/province
///   "c:VN|a:Quận 1"                         legacy area (state unknown)
///   "c:VN|s:Tỉnh Lâm Đồng|a:Da Lat"         legacy area under a state
///   "c:VN|a:Quận 1|n:Yentown"               neighborhood
///   "c:US|s:California|ci:San Francisco|n:Mission"
///
/// Each value is whitespace-trimmed, with `%` and `|` percent-escaped so a
/// raw value can never forge a segment boundary. Because every event maps
/// to exactly ONE leaf path, "All in [X]" (X + all descendants) is simply
/// "leaf == X or leaf starts with X + '|'" — each event is counted once
/// per node, never double-summed.
struct EventLocation: Codable, Hashable {
    var countryCode: String?
    var stateProvince: String?
    var city: String?
    var area: String?
    var neighborhood: String?

    enum CodingKeys: String, CodingKey {
        case countryCode = "country_code"
        case stateProvince = "state_province"
        case city, area, neighborhood
    }
}

/// One event as the tree sees it — just an id, its location and whether
/// it's still open (for the sheet's counts).
struct LocatedEvent {
    let id: String
    let location: EventLocation
    let isOpen: Bool
}

enum LocationNodeKind: String {
    case country = "c"
    case state = "s"
    case city = "ci"
    case legacyArea = "a"
    case neighborhood = "n"

    /// Sibling ordering — administrative levels before the free-text
    /// familiar-area names that sit beside them when state is unknown.
    var sortRank: Int {
        switch self {
        case .country: return 0
        case .state: return 1
        case .city: return 2
        case .legacyArea: return 3
        case .neighborhood: return 4
        }
    }
}

struct LocationNode: Identifiable {
    let id: String
    let kind: LocationNodeKind
    /// The raw column value (ISO code for a country).
    let raw: String
    let parentID: String?
    var children: [LocationNode]
    /// Distinct event ids in this node's whole subtree (itself included).
    var eventIDs: Set<String>
    /// Distinct OPEN event ids in the subtree — what the sheet displays.
    var openCount: Int
}

enum LocationHierarchy {
    static let allID = "all"
    static let alwaysShownCountries = ["VN", "US"]
    static let unknownCountry = "_"

    struct Segment: Hashable {
        let kind: LocationNodeKind
        let raw: String
    }

    // MARK: IDs

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "|", with: "%7C")
    }

    private static func unescape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "%7C", with: "|").replacingOccurrences(of: "%25", with: "%")
    }

    static func nodeID(_ segments: [Segment]) -> String {
        segments.map { "\($0.kind.rawValue):\(escape($0.raw))" }.joined(separator: "|")
    }

    /// Parses an ID back into its segments (used for labels when a
    /// selected node isn't present in the currently-loaded tree).
    static func segments(ofID id: String) -> [Segment] {
        guard id != allID else { return [] }
        return id.components(separatedBy: "|").compactMap { part in
            guard let colon = part.firstIndex(of: ":"),
                  let kind = LocationNodeKind(rawValue: String(part[..<colon])) else { return nil }
            return Segment(kind: kind, raw: unescape(String(part[part.index(after: colon)...])))
        }
    }

    /// The full path for one event's location.
    static func segments(for loc: EventLocation) -> [Segment] {
        let country = clean(loc.countryCode)?.uppercased() ?? unknownCountry
        var out = [Segment(kind: .country, raw: country)]
        let state = clean(loc.stateProvince)
        let neighborhood = clean(loc.neighborhood)
        if let state { out.append(Segment(kind: .state, raw: state)) }
        if country == "US" {
            // US: State → City → neighborhood. `area` (the VN familiar-
            // area column) is not a US level — never invented into one.
            let city = clean(loc.city)
            if let city { out.append(Segment(kind: .city, raw: city)) }
            if let neighborhood, !sameName(neighborhood, city), !sameName(neighborhood, state) {
                out.append(Segment(kind: .neighborhood, raw: neighborhood))
            }
        } else {
            // VN (and any other country): State → legacy familiar area
            // (raw `events.area`, never presented as a current official
            // administrative unit) → neighborhood.
            let area = clean(loc.area)
            if let area, !sameName(area, state) { out.append(Segment(kind: .legacyArea, raw: area)) }
            if let neighborhood, !sameName(neighborhood, area), !sameName(neighborhood, state) {
                out.append(Segment(kind: .neighborhood, raw: neighborhood))
            }
        }
        return out
    }

    private static func sameName(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return SearchMatch.normalize(a) == SearchMatch.normalize(b)
    }

    static func leafID(for loc: EventLocation) -> String { nodeID(segments(for: loc)) }

    /// "All in [selection]": the selection itself plus every descendant.
    static func matches(leafID: String, selection: String) -> Bool {
        selection == allID || leafID == selection || leafID.hasPrefix(selection + "|")
    }

    /// Every ancestor ID of `id` (not including `id` itself), root first.
    static func ancestorIDs(of id: String) -> [String] {
        let segs = segments(ofID: id)
        guard segs.count > 1 else { return [] }
        return (1..<segs.count).map { nodeID(Array(segs.prefix($0))) }
    }

    // MARK: Legacy selection keys

    /// The OLD hardcoded `AreaOption` keys → their equivalent new node ID.
    /// "other" (every district except three) and "danang" (a placeholder
    /// that never matched anything) have no single-node equivalent, so
    /// both widen to the Vietnam root rather than silently resetting to
    /// "all" or pointing at a node that was never real.
    static let legacyKeyMap: [String: String] = [
        "all": allID,
        "q1": nodeID([Segment(kind: .country, raw: "VN"), Segment(kind: .legacyArea, raw: "Quận 1")]),
        "thaodien": nodeID([Segment(kind: .country, raw: "VN"), Segment(kind: .legacyArea, raw: "Thảo Điền")]),
        "binhthanh": nodeID([Segment(kind: .country, raw: "VN"), Segment(kind: .legacyArea, raw: "Bình Thạnh")]),
        "other": nodeID([Segment(kind: .country, raw: "VN")]),
        "danang": nodeID([Segment(kind: .country, raw: "VN")]),
    ]

    /// Pure: a stored/incoming selection value → a valid new-shape node ID.
    /// Legacy keys are mapped, new-shape IDs pass through unchanged, and
    /// anything unparseable falls back to "all".
    static func migrateSelection(_ raw: String) -> String {
        if let mapped = legacyKeyMap[raw] { return mapped }
        let segs = segments(ofID: raw)
        guard let first = segs.first, first.kind == .country else { return allID }
        return raw
    }

    /// Reverse lookup for stable accessibility identifiers (UI tests keep
    /// addressing e.g. "area.thaodien"). Only the three 1:1 area keys.
    static func legacyKey(forNodeID id: String) -> String? {
        ["q1", "thaodien", "binhthanh"].first { legacyKeyMap[$0] == id }
    }

    // MARK: Tree

    static func build(from events: [LocatedEvent]) -> [LocationNode] {
        struct Acc { var kind: LocationNodeKind; var raw: String; var parent: String?; var ids: Set<String>; var open: Set<String> }
        var nodes: [String: Acc] = [:]
        var childIDs: [String: Set<String>] = [:]
        for code in alwaysShownCountries {
            let id = nodeID([Segment(kind: .country, raw: code)])
            nodes[id] = Acc(kind: .country, raw: code, parent: nil, ids: [], open: [])
        }
        for event in events {
            let segs = segments(for: event.location)
            var parent: String?
            for depth in 1...segs.count {
                let id = nodeID(Array(segs.prefix(depth)))
                let seg = segs[depth - 1]
                var acc = nodes[id] ?? Acc(kind: seg.kind, raw: seg.raw, parent: parent, ids: [], open: [])
                acc.ids.insert(event.id)
                if event.isOpen { acc.open.insert(event.id) }
                nodes[id] = acc
                if let parent { childIDs[parent, default: []].insert(id) }
                parent = id
            }
        }
        func make(_ id: String) -> LocationNode {
            let acc = nodes[id]!
            let kids = (childIDs[id] ?? []).map(make).sorted(by: siblingOrder)
            return LocationNode(id: id, kind: acc.kind, raw: acc.raw, parentID: acc.parent, children: kids, eventIDs: acc.ids, openCount: acc.open.count)
        }
        let roots = nodes.filter { $0.value.parent == nil }.keys.map(make)
        return roots.sorted { a, b in
            rootRank(a.raw) != rootRank(b.raw) ? rootRank(a.raw) < rootRank(b.raw) : a.raw < b.raw
        }
    }

    private static func rootRank(_ code: String) -> Int {
        if let i = alwaysShownCountries.firstIndex(of: code) { return i }
        return code == unknownCountry ? 99 : 50
    }

    private static func siblingOrder(_ a: LocationNode, _ b: LocationNode) -> Bool {
        if a.kind.sortRank != b.kind.sortRank { return a.kind.sortRank < b.kind.sortRank }
        if a.eventIDs.count != b.eventIDs.count { return a.eventIDs.count > b.eventIDs.count }
        return a.raw.localizedStandardCompare(b.raw) == .orderedAscending
    }

    static func flatten(_ roots: [LocationNode]) -> [LocationNode] {
        roots.flatMap { [$0] + flatten($0.children) }
    }

    static func find(_ id: String, in roots: [LocationNode]) -> LocationNode? {
        for node in roots {
            if node.id == id { return node }
            if id.hasPrefix(node.id + "|"), let hit = find(id, in: node.children) { return hit }
        }
        return nil
    }

    // MARK: Labels

    static func label(kind: LocationNodeKind, raw: String, T: (String, String) -> String) -> String {
        guard kind == .country else { return raw }
        switch raw {
        case "VN": return T("Việt Nam", "Vietnam")
        case "US": return T("Hoa Kỳ", "United States")
        case unknownCountry: return T("Chưa rõ quốc gia", "Country not set")
        default:
            let vi = Locale(identifier: "vi_VN").localizedString(forRegionCode: raw) ?? raw
            let en = Locale(identifier: "en_US").localizedString(forRegionCode: raw) ?? raw
            return T(vi, en)
        }
    }

    static func label(_ node: LocationNode, T: (String, String) -> String) -> String {
        label(kind: node.kind, raw: node.raw, T: T)
    }

    /// Short, disambiguating header label — the node's own name, plus its
    /// parent's name ONLY when another node in the tree shares the same
    /// name (e.g. two "Quận 1"s under different provinces). Never a full
    /// breadcrumb. Works from the ID alone when the node isn't loaded.
    static func shortLabel(for id: String, roots: [LocationNode], T: (String, String) -> String) -> String {
        guard id != allID else { return T("Mọi nơi", "Everywhere") }
        let segs = segments(ofID: id)
        guard let last = segs.last else { return T("Mọi nơi", "Everywhere") }
        let own = label(kind: last.kind, raw: last.raw, T: T)
        guard segs.count > 1, last.kind != .country else { return own }
        let key = SearchMatch.normalize(last.raw)
        let clash = flatten(roots).contains { $0.id != id && $0.kind != .country && SearchMatch.normalize($0.raw) == key }
        guard clash else { return own }
        let parent = segs[segs.count - 2]
        return "\(own) · \(label(kind: parent.kind, raw: parent.raw, T: T))"
    }

    // MARK: Search

    /// `nil` for an empty query (show the tree as the user left it).
    /// Otherwise: `visible` = every matching node + its ancestors + its
    /// descendants; `autoExpanded` = the ancestors of matches, so matches
    /// are revealed WITHOUT mutating the user's own expand/collapse state.
    /// Matching reuses `SearchMatch` (accent/đ-insensitive, AND tokens).
    static func search(_ roots: [LocationNode], query: String, T: (String, String) -> String) -> (visible: Set<String>, autoExpanded: Set<String>)? {
        guard !SearchMatch.normalize(query).isEmpty else { return nil }
        var visible = Set<String>()
        var autoExpanded = Set<String>()
        for node in flatten(roots) {
            let doc = SearchMatch.normalize(label(node, T: T) + " " + node.raw)
            guard SearchMatch.matches(doc: doc, query: query) else { continue }
            visible.insert(node.id)
            for ancestor in ancestorIDs(of: node.id) {
                visible.insert(ancestor)
                autoExpanded.insert(ancestor)
            }
            for descendant in flatten(node.children) { visible.insert(descendant.id) }
        }
        return (visible, autoExpanded)
    }

    // MARK: Geocoder helpers

    /// MapKit's `administrativeArea` for US addresses is the USPS
    /// abbreviation ("CA"); web's geocoder (Nominatim) returns the full
    /// name ("California"). Expanded here so a US state node's ID is the
    /// same regardless of which platform created the event.
    static func fullUSStateName(_ value: String) -> String {
        usStates[value.uppercased()] ?? value
    }

    private static let usStates: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "PR": "Puerto Rico",
    ]
}

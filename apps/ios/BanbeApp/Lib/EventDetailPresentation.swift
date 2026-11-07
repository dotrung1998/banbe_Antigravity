import Foundation

/// Event Detail presentation rules (notes 68, 70): the seat status beside the price, how the event type's facts are
/// laid out, the About and included sections, the place distance, the date tile and the photo strip. Pure logic, port of src/lib/eventDetailPresentation.js through the shared
/// tests/fixtures/event-detail-presentation.json (tests: EventDetailPresentationTests.swift and
/// tests/unit/eventDetailPresentation.test.mjs) — change both together.
enum EventDetailPresentation {
    /// "N left" turns honey at or under this share of capacity (and never above 2 seats for tiny tables).
    static let fewShare = 0.2
    static let fewMin = 2

    enum SeatKind: String { case going, soldOut, few, open, unknown }

    struct SeatStatus: Equatable {
        let kind: SeatKind
        let left: Int?
        /// Booked share of capacity for the thin bar; nil = no bar (also when nothing is booked yet, note 70).
        let ratio: Double?
    }

    /// `going` = the viewer holds a ticket; `remaining` = seats still free (nil when unknown). Sold out also when
    /// nothing is left but the row has not been marked sold out yet (the old full clay bar at 0).
    static func seatStatus(capacity: Int?, remaining: Int?, soldOut: Bool, going: Bool) -> SeatStatus {
        if going { return SeatStatus(kind: .going, left: remaining, ratio: nil) }
        if soldOut || (remaining.map { $0 <= 0 } ?? false) { return SeatStatus(kind: .soldOut, left: 0, ratio: nil) }
        guard let remaining else { return SeatStatus(kind: .unknown, left: nil, ratio: nil) }
        let cap = (capacity ?? 0) > 0 ? capacity : nil
        let ratio: Double? = cap.flatMap { c in c - remaining > 0 ? min(1, Double(c - remaining) / Double(c)) : nil }
        let few = cap.map { remaining <= max(fewMin, Int((Double($0) * fewShare).rounded(.up))) } ?? (remaining <= fewMin)
        return SeatStatus(kind: few ? .few : .open, left: remaining, ratio: ratio)
    }

    /// Facts that become chips under the tiles; minimum age becomes a pill beside the category.
    static let chipFacts = ["alcohol", "dietary"]
    static let pillFact = "min_age"

    struct SplitFacts: Equatable {
        let minAge: EventTypes.Fact?
        let chips: [EventTypes.Fact]
        let rows: [EventTypes.Fact]
    }

    /// Minimum age first (a restriction), then icon chips, then the rest as an aligned list. A multi-choice chip fact
    /// becomes one chip per choice ("Vegetarian-friendly" · "Can adjust on request", note 70).
    static func splitFacts(_ facts: [EventTypes.Fact]) -> SplitFacts {
        var minAge: EventTypes.Fact?
        var chips: [EventTypes.Fact] = [], rows: [EventTypes.Fact] = []
        for f in facts {
            if f.id == pillFact { minAge = f }
            else if chipFacts.contains(f.id) {
                if let vs = f.values, vs.count > 1 {
                    chips += vs.map { EventTypes.Fact(id: f.id, label: f.label, value: $0, values: [$0]) }
                } else { chips.append(f) }
            }
            else { rows.append(f) }
        }
        chips.sort { (chipFacts.firstIndex(of: $0.id) ?? 0) < (chipFacts.firstIndex(of: $1.id) ?? 0) }
        return SplitFacts(minAge: minAge, chips: chips, rows: rows)
    }

    static let aboutLines = 3
    /// ~3 lines at 15pt on a 390pt-wide phone.
    static let aboutClampChars = 140

    struct About: Equatable {
        let visible: Bool
        let body: String
        /// Long enough to clamp; "Read more" expands it in place (the sheet never repeats the description).
        let clampable: Bool
        /// The About & Included sheet has an intro or items ("More ›" on the heading opens it).
        let hasSheet: Bool
    }

    /// The description (else the intro's first paragraph) clamped to 3 lines. The included items have their own
    /// section (note 70). Never a heading with nothing under it (the old "About … More ›" block for an intro-only event).
    static func aboutSection(desc: String?, intro: String?, includedCount: Int) -> About {
        let d = (desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = (intro ?? "").components(separatedBy: "\n")
            .reduce(into: [[String]]([[]])) { acc, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { acc.append([]) } else { acc[acc.count - 1].append(line) }
            }
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let body = d.isEmpty ? (paragraphs.first ?? "") : d
        return About(visible: !body.isEmpty, body: body,
                     clampable: body.count > aboutClampChars, hasSheet: includedCount > 0 || !paragraphs.isEmpty)
    }

    /// The included items' own section under About: visible only with at least one item.
    static func includedSection(_ items: [String]) -> (visible: Bool, items: [String]) {
        let list = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (!list.isEmpty, list)
    }

    /// Distance under the place only when it helps choose (same metro); far away it is noise ("9662,0 km away").
    static let distanceMaxKm = 50.0

    /// "850 m" / "2.4 km" (EN) · "2,4 km" (VI) / "12 km", or nil when unknown or farther than distanceMaxKm.
    static func distanceLabel(km: Double?, en: Bool) -> String? {
        guard let km, km.isFinite, km >= 0, km <= distanceMaxKm else { return nil }
        if km < 1 { return "\(max(50, Int((km * 1000 / 50).rounded()) * 50)) m" }
        let text = km < 10 ? String(format: "%.1f", km) : String(Int(km.rounded()))
        return (en ? text : text.replacingOccurrences(of: ".", with: ",")) + " km"
    }

    private static let weekdayEN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let monthEN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The date tile in the app's language, from the same "Th 4, 04.11" text the Time tile is split from
    /// (`event.when`, already in the venue's zone), so date and time never disagree: EN "Wed 4 Nov", VI unchanged.
    static func dateTileLabel(_ raw: String, en: Bool) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard en, let m = text.wholeMatch(of: #/(CN|Th ([2-7])),\s*(\d{1,2})\.(\d{1,2})/#) else { return text }
        let wd = m.output.1 == "CN" ? 0 : (Int(m.output.2 ?? "") ?? 1) - 1
        guard let day = Int(m.output.3), let month = Int(m.output.4), (1...12).contains(month), (0...6).contains(wd) else { return text }
        return "\(weekdayEN[wd]) \(day) \(monthEN[month - 1])"
    }

    /// The photo strip under the hero: never the cover again, never the same URL twice.
    static func stripPhotos<T>(_ photos: [T], heroURL: String?, url: (T) -> String?) -> [T] {
        var seen = Set<String>()
        if let heroURL { seen.insert(heroURL) }
        return photos.filter { p in
            guard let u = url(p), !u.isEmpty, !seen.contains(u) else { return false }
            seen.insert(u)
            return true
        }
    }

    /// Story-first hero (note 70): stops as shares of the hero height and alpha of near-black. The title band starts
    /// at or below `full`, so its weakest backing is `alpha`. Same values as web HERO_SCRIM.
    static let heroScrim = (start: 0.2, full: 0.55, alpha: 0.7, end: 0.78)

    /// Contrast of white text over the scrim at `alpha` on a photo pixel (the worst case is a white photo).
    static func scrimContrast(alpha: Double, pixel: [Double] = [255, 255, 255], scrim: [Double] = [12, 10, 8]) -> Double {
        func lin(_ c: Double) -> Double { let v = c / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let m = zip(pixel, scrim).map { $0 * (1 - alpha) + $1 * alpha }
        let l = 0.2126 * lin(m[0]) + 0.7152 * lin(m[1]) + 0.0722 * lin(m[2])
        return 1.05 / (l + 0.05)
    }

    // MARK: V8 ticket stub (note 75)

    private static let weekdayVILong = ["CHỦ NHẬT", "THỨ HAI", "THỨ BA", "THỨ TƯ", "THỨ NĂM", "THỨ SÁU", "THỨ BẢY"]

    struct DateBlock: Equatable { let month: String; let day: String; let weekday: String }

    /// The stub's date block from the same "Th 4, 04.11" text as the Time (never from startDate, note 70):
    /// EN NOV / 04 / WED, VI THG 11 / 04 / THỨ TƯ. Nil when unrecognised.
    static func dateBlock(_ raw: String, en: Bool) -> DateBlock? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let m = text.wholeMatch(of: #/(CN|Th ([2-7])),\s*(\d{1,2})\.(\d{1,2})/#) else { return nil }
        let wd = m.output.1 == "CN" ? 0 : (Int(m.output.2 ?? "") ?? 1) - 1
        guard let day = Int(m.output.3), let month = Int(m.output.4), (1...12).contains(month), (0...6).contains(wd) else { return nil }
        return DateBlock(month: en ? monthEN[month - 1].uppercased() : "THG \(month)",
                         day: String(format: "%02d", day),
                         weekday: en ? weekdayEN[wd].uppercased() : weekdayVILong[wd])
    }

    /// The seat chip beside the price (V8, owner decision 5): "Còn N vé" / "N tickets left" (no "of M").
    static func ticketsLeftText(_ left: Int, en: Bool) -> String {
        let n = max(0, left)
        if !en { return "Còn \(n) vé" }
        return n == 1 ? "1 ticket left" : "\(n) tickets left"
    }

    enum NeedIcon: String { case alcohol, dietary, age, fact }

    struct NeedRow: Equatable {
        let id: String
        /// Identifier suffix: dietary rows keep `dietary`, `dietary-2`…; the age row is `min_age-row`.
        let key: String
        let icon: NeedIcon
        var badge: String? = nil
        let title: String
        let sub: String?
    }

    /// Host-written sub-lines (phase 7); nil or blank = no sub-line (never invented copy).
    struct NeedNotes: Equatable {
        var alcohol: String? = nil
        var dietary: String? = nil
        var id: String? = nil
    }

    /// "Good to know" rows in V8 order: alcohol, one row per dietary choice (the dietary note on the first), minimum
    /// age, then the type's other facts as label over value. Web twin `needToKnowRows`.
    static func needToKnowRows(_ facts: [EventTypes.Fact], notes: NeedNotes = NeedNotes(), en: Bool) -> [NeedRow] {
        func clean(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        var alcohol: [NeedRow] = [], dietary: [NeedRow] = [], age: [NeedRow] = [], rest: [NeedRow] = []
        for f in facts {
            switch f.id {
            case "alcohol":
                alcohol.append(NeedRow(id: f.id, key: "alcohol", icon: .alcohol, title: f.value, sub: clean(notes.alcohol)))
            case "dietary":
                let vals = (f.values?.isEmpty == false) ? f.values! : [f.value]
                for (i, v) in vals.enumerated() {
                    dietary.append(NeedRow(id: f.id, key: i == 0 ? "dietary" : "dietary-\(i + 1)", icon: .dietary, title: v,
                                           sub: i == 0 ? clean(notes.dietary) : nil))
                }
            case pillFact:
                let n = f.value.filter(\.isNumber)
                age.append(NeedRow(id: f.id, key: "\(pillFact)-row", icon: .age, badge: f.value,
                                   title: n.isEmpty ? f.value : (en ? "Ages \(n) and up" : "Từ \(n) tuổi"), sub: clean(notes.id)))
            default:
                rest.append(NeedRow(id: f.id, key: f.id, icon: .fact, title: f.label, sub: clean(f.value)))
            }
        }
        return alcohol + dietary + age + rest
    }

    /// The menu cards (V8): up to 3 included items as label + detail (detail may be empty), blanks dropped. No icons.
    static let menuMax = 3
    static func menuCards(_ items: [IncludedItem]) -> [IncludedItem] {
        Array(items
            .map { IncludedItem(label: $0.label.trimmingCharacters(in: .whitespacesAndNewlines),
                                detail: $0.detail.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.label.isEmpty }
            .prefix(menuMax))
    }
}

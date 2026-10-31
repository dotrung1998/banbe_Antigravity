import Foundation

/// Event Detail presentation rules (note 68): the seat status beside the price, how the event type's facts are laid
/// out, and the About section. Pure logic, port of src/lib/eventDetailPresentation.js through the shared
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
        /// Booked share of capacity for the thin bar; nil = no bar.
        let ratio: Double?
    }

    /// `going` = the viewer holds a ticket; `remaining` = seats still free (nil when unknown). Sold out also when
    /// nothing is left but the row has not been marked sold out yet (the old full clay bar at 0).
    static func seatStatus(capacity: Int?, remaining: Int?, soldOut: Bool, going: Bool) -> SeatStatus {
        if going { return SeatStatus(kind: .going, left: remaining, ratio: nil) }
        if soldOut || (remaining.map { $0 <= 0 } ?? false) { return SeatStatus(kind: .soldOut, left: 0, ratio: nil) }
        guard let remaining else { return SeatStatus(kind: .unknown, left: nil, ratio: nil) }
        let cap = (capacity ?? 0) > 0 ? capacity : nil
        let ratio = cap.map { min(1, max(0, Double($0 - remaining) / Double($0))) }
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

    /// Minimum age first (a restriction), then icon chips, then the rest as an aligned list.
    static func splitFacts(_ facts: [EventTypes.Fact]) -> SplitFacts {
        var minAge: EventTypes.Fact?
        var chips: [EventTypes.Fact] = [], rows: [EventTypes.Fact] = []
        for f in facts {
            if f.id == pillFact { minAge = f } else if chipFacts.contains(f.id) { chips.append(f) } else { rows.append(f) }
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

    /// The description (else the intro's first paragraph) clamped to 3 lines, then the included line. Never a heading
    /// with nothing under it (the old "About … More ›" block for an intro-only event).
    static func aboutSection(desc: String?, intro: String?, includedCount: Int) -> About {
        let d = (desc ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = (intro ?? "").components(separatedBy: "\n")
            .reduce(into: [[String]]([[]])) { acc, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { acc.append([]) } else { acc[acc.count - 1].append(line) }
            }
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let body = d.isEmpty ? (paragraphs.first ?? "") : d
        return About(visible: !body.isEmpty || includedCount > 0, body: body,
                     clampable: body.count > aboutClampChars, hasSheet: includedCount > 0 || !paragraphs.isEmpty)
    }
}

import Foundation

/// Event Project Hub, Day-of tab (note 76): where each run-of-show item sits on the time grid "now".
/// Web twin: src/lib/rosLayout.js. Shared vectors: tests/fixtures/ros-layout.json.
///
/// A port of layoutDay() in banbe_hosting_project_hub_v6.html, rule for rule:
/// - An unticked item whose predecessor is ticked (or the first item) stretches along the clock once the clock passes
///   its planned end.
/// - Only the very next item is squeezed: it starts at min(previous end, its planned end - 10 min). Later items keep
///   their planned times; anything still overlapped is flagged, never moved.
/// - Ticking freezes the end at max(planned end, done at).
/// Overrun and squeeze are derived here and never stored. Everything is absolute epoch milliseconds, so items crossing
/// midnight or a DST change need no zone logic. The axis is rounded to UTC half hours, which are local half hours in
/// every zone whose offset is a whole or half hour (all VN and US zones).
enum RosLayout {
    struct Item: Equatable {
        let id: String
        let startsAt: Int
        let endsAt: Int
        /// nil while unticked.
        let doneAt: Int?
    }

    struct Placed: Equatable {
        let id: String
        let plannedStart: Int, plannedEnd: Int
        let start: Int, end: Int
        let done: Bool
        let overrunMin: Int, squeezedMin: Int
        let overlap: Bool
        let active: Bool
        let overrun: Bool
        let squeezed: Bool
    }

    enum ChipKind: String, Equatable { case overrun, squeezed, overlap }
    struct Chip: Equatable { let id: String; let kind: ChipKind; let minutes: Int }
    struct Axis: Equatable { let start: Int; let end: Int }
    struct Result: Equatable { let items: [Placed]; let chips: [Chip]; let axis: Axis? }

    private static let minute = 60_000
    private static let halfHour = 30 * 60_000

    static func layout(_ items: [Item], now: Int, minMinutes: Int = ProjectLimits.shared.rosMinMinutes) -> Result {
        let minLen = minMinutes * minute
        // A zero or negative planned length gets the minimum (the server CHECK makes this impossible for saved rows).
        let plan = items
            .map { Item(id: $0.id, startsAt: $0.startsAt, endsAt: max($0.endsAt, $0.startsAt + minLen), doneAt: $0.doneAt) }
            .sorted { $0.startsAt != $1.startsAt ? $0.startsAt < $1.startsAt : $0.id < $1.id }

        var out: [Placed] = []
        for (i, b) in plan.enumerated() {
            let prev = out.last
            let canRun = i == 0 || plan[i - 1].doneAt != nil
            var end = b.endsAt
            if let doneAt = b.doneAt { end = max(b.endsAt, doneAt) }
            else if canRun && now > b.endsAt { end = now }
            var start = b.startsAt
            if let prev, prev.end > b.startsAt { start = min(prev.end, b.endsAt - minLen) }
            let latestEnd = out.map(\.end).max() ?? Int.min
            let overlap = i > 0 && latestEnd > start
            if end < start + minLen { end = start + minLen }
            let overrunMin = roundedMinutes(end - b.endsAt)
            let squeezedMin = roundedMinutes(start - b.startsAt)
            let done = b.doneAt != nil
            out.append(Placed(id: b.id, plannedStart: b.startsAt, plannedEnd: b.endsAt, start: start, end: end, done: done,
                              overrunMin: overrunMin, squeezedMin: squeezedMin, overlap: overlap,
                              active: !done && now >= start && now < end,
                              overrun: !done && overrunMin > 0,
                              squeezed: squeezedMin > 0 && !overlap))
        }

        // "Versus the plan" chips, in the prototype's order.
        var chips: [Chip] = []
        for l in out {
            if l.overrun { chips.append(Chip(id: l.id, kind: .overrun, minutes: l.overrunMin)) }
            if l.squeezed { chips.append(Chip(id: l.id, kind: .squeezed, minutes: l.squeezedMin)) }
            if l.overlap { chips.append(Chip(id: l.id, kind: .overlap, minutes: 0)) }
        }

        var axis: Axis?
        if let first = out.map(\.start).min(), let last = out.map(\.end).max() {
            axis = Axis(start: floorDiv(first - halfHour, halfHour) * halfHour,
                        end: ceilDiv(last + halfHour, halfHour) * halfHour)
        }
        return Result(items: out, chips: chips, axis: axis)
    }

    /// Math.round for the non-negative minute counts used here.
    private static func roundedMinutes(_ ms: Int) -> Int { Int((Double(ms) / Double(minute)).rounded(.toNearestOrAwayFromZero)) }
    private static func floorDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.down)) }
    private static func ceilDiv(_ a: Int, _ b: Int) -> Int { Int((Double(a) / Double(b)).rounded(.up)) }
}

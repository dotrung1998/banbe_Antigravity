import Foundation

/// Simple Shell Home (note 66): exactly ONE main block at the top of Home per mode. Goer priority: an event of
/// yours within 24h (Next up) > the most urgent Action Center item > the new-user checklist > nothing. Guests get
/// the guest banner. Host: the next event you host (not yet ended) > "Plan your next event".
/// Web twin: src/lib/homeHero.js. Shared vectors: tests/fixtures/home-hero.json.
enum HomeHero {
    enum Goer: String { case guest, nextUp, action, checklist, none }

    static func goer(signedIn: Bool, hasNextUp: Bool, actionCount: Int, checklistVisible: Bool) -> Goer {
        if !signedIn { return .guest }
        if hasNextUp { return .nextUp }
        if actionCount > 0 { return .action }
        if checklistVisible { return .checklist }
        return .none
    }

    struct HostedEvent: Equatable {
        let key: String
        let startsAt: Date
        var endsAt: Date?
        var status: String
    }

    /// The soonest hosted event that has not ended (ongoing counts); nil = "Plan your next event".
    static func host(_ events: [HostedEvent], now: Date) -> HostedEvent? {
        let skipped: Set<String> = ["cancelled", "removed", "ended", "rejected"]
        return events
            .filter { e in
                guard !skipped.contains(e.status) else { return false }
                if let end = e.endsAt { return end > now }
                return e.startsAt.addingTimeInterval(12 * 3600) > now
            }
            .sorted { $0.startsAt == $1.startsAt ? $0.key < $1.key : $0.startsAt < $1.startsAt }
            .first
    }
}

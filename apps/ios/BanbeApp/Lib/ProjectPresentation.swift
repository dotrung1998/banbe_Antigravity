import Foundation

/// Event Project Hub (note 76): what the Overview, Tasks and Hosting Home show, derived from one snapshot. Pure, so the
/// numbers can be tested: shared vectors tests/fixtures/project-presentation.json over project-snapshot.json (the web
/// twin reads the same files in phase 8). Days are always counted in the EVENT's zone, never the phone's.
enum ProjectPresentation {
    struct Readiness: Equatable { let done: Int; let total: Int; let percent: Int }
    struct LaneProgress: Equatable, Identifiable { let laneId: String; let name: String; let done: Int; let total: Int; var id: String { laneId } }
    enum AwaitKind: String { case laneReview, question, vote, unseen }
    struct Awaiting: Equatable, Identifiable { let kind: AwaitKind; let id: String }
    enum DueLabel: Equatable { case today, tomorrow, late(Int), date(String) }

    static func readiness(_ tasks: [ProjectTask]) -> Readiness {
        let done = tasks.filter { $0.status == "done" }.count
        let total = tasks.count
        return Readiness(done: done, total: total, percent: total == 0 ? 0 : Int((Double(done) * 100 / Double(total)).rounded()))
    }

    static func laneProgress(_ lanes: [ProjectLane], _ tasks: [ProjectTask]) -> [LaneProgress] {
        lanes.sorted { $0.position < $1.position }.map { l in
            let mine = tasks.filter { $0.laneId == l.id }
            return LaneProgress(laneId: l.id, name: l.name, done: mine.filter { $0.status == "done" }.count, total: mine.count)
        }
    }

    /// Whole days from today (in `tz`) to a "yyyy-MM-dd" day: 0 = today, 1 = tomorrow, -2 = two days late.
    static func dayDelta(_ day: String?, now: Date, tz: TimeZone) -> Int? {
        guard let day, let target = localDay(day, tz: tz) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: target).day
    }

    static func dueLabel(_ day: String?, now: Date, tz: TimeZone) -> DueLabel? {
        guard let day, let n = dayDelta(day, now: now, tz: tz) else { return nil }
        if n < 0 { return .late(-n) }
        if n == 0 { return .today }
        if n == 1 { return .tomorrow }
        return .date(day)
    }

    /// Days until the event day (negative once it has passed).
    static func daysToGo(_ event: ProjectEvent?, now: Date) -> Int? {
        guard let event else { return nil }
        let day = event.eventDate ?? ProjectDates.parse(event.startsAt).map { ymd($0, tz: event.timeZone) }
        return dayDelta(day, now: now, tz: event.timeZone)
    }

    /// Open first by due day (no due day last), keeping the server's order among equals.
    static func byDue(_ tasks: [ProjectTask]) -> [ProjectTask] {
        tasks.enumerated().sorted { a, b in
            switch (a.element.dueDate, b.element.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    static func open(_ tasks: [ProjectTask]) -> [ProjectTask] { tasks.filter { $0.status != "done" } }

    static func myOpenTasks(_ tasks: [ProjectTask], me: String?) -> [ProjectTask] {
        guard let me else { return [] }
        return byDue(open(tasks).filter { $0.assigneeId?.lowercased() == me.lowercased() })
    }

    /// Blocked tasks first, then the late ones (due before today in the event's zone), each by due day.
    static func attention(_ tasks: [ProjectTask], now: Date, tz: TimeZone) -> [ProjectTask] {
        let blocked = byDue(tasks.filter { $0.status == "blocked" })
        let late = byDue(open(tasks).filter { $0.status != "blocked" && (dayDelta($0.dueDate, now: now, tz: tz) ?? 0) < 0 })
        return blocked + late
    }

    static func comingUp(_ tasks: [ProjectTask], limit: Int = 4) -> [ProjectTask] { Array(byDue(open(tasks)).prefix(limit)) }

    /// What waits on me: (Host) proposals to review, then open posts in the snapshot's order (newest first): a question
    /// addressed to me, a proposal I have not voted on, an update I have not seen. My own posts never wait on me.
    static func awaiting(_ snap: ProjectSnapshot, me: String?) -> [Awaiting] {
        let uid = me?.lowercased()
        var out: [Awaiting] = []
        if snap.isHost == true {
            out += (snap.changeRequests ?? []).filter { $0.status == "pending" }.map { Awaiting(kind: .laneReview, id: $0.id) }
        }
        for p in snap.posts ?? [] where p.state == "open" && p.authorId?.lowercased() != uid {
            if p.type == "question", p.addresseeId?.lowercased() == uid, uid != nil { out.append(Awaiting(kind: .question, id: p.id)) }
            else if p.type == "proposal", p.myVote == nil { out.append(Awaiting(kind: .vote, id: p.id)) }
            else if p.type == "update", !p.seenByMe { out.append(Awaiting(kind: .unseen, id: p.id)) }
        }
        return out
    }

    static func decisions(_ posts: [ProjectPost]) -> [ProjectPost] { posts.filter { $0.type == "decision" } }

    // MARK: day helpers

    static func ymd(_ date: Date, tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Midnight of a "yyyy-MM-dd" day in `tz`.
    static func localDay(_ day: String, tz: TimeZone) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

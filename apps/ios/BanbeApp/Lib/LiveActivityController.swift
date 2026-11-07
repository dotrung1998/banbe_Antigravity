import ActivityKit
import Foundation

/// One confirmed ticket that may get an event-day Live Activity (State/AppState+LiveActivity.swift builds these).
struct EventDayTicket: Equatable {
    let bookingID: String
    let eventName: String
    let venue: String
    let startsAt: Date
    let ticketCode: String
    let timeZoneID: String
    let market: String
}

/// L7 day-of card (docs/impl/phase3-extras.md; switch `live_activity`). Starts, updates and ends the event-day Live
/// Activity ON THE DEVICE, never with a push token (pushType nil). Timing is CoreLoops.liveActivityPhase
/// (core-loops.json `liveActivity`): from 6 h before the start ('upcoming'), 'started' at the start, ended at
/// start + 12 h. The app re-checks on launch, on every return to the foreground, when tickets load and, while it is
/// running, at the next phase change. iOS itself may end a Live Activity earlier (it limits how long one stays active).
///
/// One card per ticket, started at most once: a card the person swiped away is not started again.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private let startedKey = "banbe.liveActivity.started.v1" // bookingID -> end time (epoch s), pruned when past
    private var nextCheck: Task<Void, Never>?
    /// When the app last looked (AppState+LiveActivity throttles on it).
    var lastSync: Date?

    /// Whether iOS (Settings > banbe > Live Activities) allows them at all. Never prompts.
    var activitiesAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var live: [Activity<EventDayAttributes>] {
        Activity<EventDayAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    var hasCards: Bool { !Activity<EventDayAttributes>.activities.isEmpty }

    /// Switch off, signed out: every card goes, and nothing is remembered.
    func endAll() async {
        nextCheck?.cancel(); nextCheck = nil
        lastSync = nil
        UserDefaults.standard.removeObject(forKey: startedKey)
        for a in Activity<EventDayAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// Brings the cards in line with `tickets` at `now`. `onNextChange` runs at the next phase change while the app
    /// is running (it should call this again with fresh tickets).
    func sync(tickets: [EventDayTicket], lang: String, now: Date = Date(), onNextChange: @escaping @MainActor () -> Void) async {
        nextCheck?.cancel(); nextCheck = nil
        guard activitiesAllowed else { return }

        var desired: [String: (EventDayTicket, EventDayAttributes.Phase)] = [:]
        for t in tickets {
            if let phase = CoreLoops.liveActivityPhase(startsAt: t.startsAt, now: now) { desired[t.bookingID] = (t, phase) }
        }

        var started = (UserDefaults.standard.dictionary(forKey: startedKey) as? [String: Double]) ?? [:]
        started = started.filter { $0.value > now.timeIntervalSince1970 }

        for a in live {
            guard let (t, phase) = desired[a.attributes.bookingID] else {
                await a.end(nil, dismissalPolicy: .immediate) // past its end, cancelled, or no longer a ticket
                continue
            }
            if a.content.state.phase != phase {
                await a.update(ActivityContent(state: .init(phase: phase), staleDate: CoreLoops.liveActivityEnd(startsAt: t.startsAt)))
            }
        }

        let running = Set(live.map(\.attributes.bookingID))
        for (id, (t, phase)) in desired where !running.contains(id) && started[id] == nil {
            let attributes = EventDayAttributes(bookingID: t.bookingID, eventName: t.eventName, venue: t.venue,
                                                startsAt: t.startsAt, ticketCode: t.ticketCode,
                                                timeZoneID: t.timeZoneID, market: t.market, lang: lang)
            let end = CoreLoops.liveActivityEnd(startsAt: t.startsAt)
            do {
                _ = try Activity.request(attributes: attributes,
                                         content: ActivityContent(state: .init(phase: phase), staleDate: end),
                                         pushType: nil)
                started[id] = end.timeIntervalSince1970
            } catch {
                #if DEBUG
                print("Live Activity request failed:", error)
                #endif
            }
        }
        UserDefaults.standard.set(started, forKey: startedKey)

        // While the app is running, look again at the next open / start / end.
        guard let next = tickets.compactMap({ CoreLoops.liveActivityNextChange(startsAt: $0.startsAt, now: now) }).min() else { return }
        let wait = max(1, next.timeIntervalSince(now) + 1)
        nextCheck = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onNextChange()
        }
    }
}

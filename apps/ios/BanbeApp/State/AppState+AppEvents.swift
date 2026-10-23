import Foundation
import Supabase

// First-party measurement (migration 196; web: BanBeContext.jsx "First-party measurement"). The sink exists only
// while someone is signed in AND the admin switch `app_events` is on; signing out or the switch going off removes
// it and drops anything still queued. Best-effort: a failed send is never retried and never surfaces.

/// What the sink checks before queueing or sending, kept outside AppState so the sink can read it from any thread.
final class AppEventsGate {
    private let lock = NSLock()
    private var on = false
    private var uid: UUID?
    func set(on: Bool, uid: UUID?) { lock.lock(); self.on = on; self.uid = uid; lock.unlock() }
    var isOn: Bool { lock.lock(); defer { lock.unlock() }; return on }
    func isSignedIn(as account: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return uid == account }
}

extension AppState {
    static let appEventsGate = AppEventsGate()

    /// Product measurement (migration 196). Off unless an admin turns it on.
    var appEventsEnabled: Bool { FeatureFlags.isOn(featureFlags, "app_events") }

    /// Installs or removes the sink to match the current account + switch. Called on sign-in, sign-out and whenever
    /// the flags change.
    func syncAppEventsSink() {
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures never reach the server
        #endif
        let gate = AppState.appEventsGate
        gate.set(on: appEventsEnabled, uid: userID)
        var current = Analytics.sink as? AppEventsSink
        guard let uid = userID, appEventsEnabled else {
            if let current { current.stop(); Analytics.sink = NoopAnalyticsSink() }
            return
        }
        if let sink = current, sink.owner != uid { sink.stop(); current = nil } // another account: never mix queues
        if current == nil {
            Analytics.sink = AppEventsSink(
                owner: uid,
                isEnabled: { gate.isOn },
                isSignedIn: { gate.isSignedIn(as: uid) },
                send: { batch in
                    struct Params: Encodable {
                        let events: [AppEventPayload], platform: String
                        enum CodingKeys: String, CodingKey { case events = "p_events", platform = "p_platform" }
                    }
                    _ = try? await SupabaseService.client
                        .rpc("log_app_events", params: Params(events: batch, platform: "ios")).execute()
                })
        }
        noteAppActiveForMeasurement()
    }

    /// app_opened: once per local day per device, on launch and on every return to the foreground (signed in, switch on).
    func noteAppActiveForMeasurement() {
        guard userID != nil, appEventsEnabled, Analytics.sink is AppEventsSink else { return }
        if AppEventRules.claimAppOpenedToday() { Analytics.track(.appOpened) }
    }
}

import Foundation

/// "For You" attention state: which preference-matching events are NEW to this
/// account since it last looked. Pure state machine; mirror of
/// src/lib/forYouAlert.js (keep both in sync, same unit cases).
///
/// VERSION per event (`ForYouAlert.version`): reviewed_at | submitted_at | status | visibility.
/// `events.updated_at` isn't selected today, so the publication moment is the best stable
/// field: admin approval stamps `reviewed_at`, a resubmission `submitted_at`, and
/// status+visibility are appended so a draft->live / invite->public flip also bumps it.
/// Price tweaks / seats sold do NOT change it, so polling never re-alerts.
struct ForYouAlertMatch: Equatable {
    var id: String
    var version: String
    var accessible: Bool = true
    var draft: Bool = false
}

struct ForYouAlertState: Codable, Equatable {
    var baselined = false
    var prefsVersion: Int? = nil
    var seen: [String: String] = [:]
    /// Insertion order of `seen`, oldest first (for the bound).
    var order: [String] = []
    var pending: [String: String] = [:]

    var hasPending: Bool { !pending.isEmpty }
}

enum ForYouAlert {
    static let seenLimit = 1000

    static func version(reviewedAt: Date?, submittedAt: Date?, status: String?, visibility: String?) -> String {
        let iso = ISO8601DateFormatter()
        return [reviewedAt.map(iso.string) ?? "", submittedAt.map(iso.string) ?? "", status ?? "", visibility ?? ""].joined(separator: "|")
    }

    private static func bound(_ seen: [String: String], _ order: [String], limit: Int) -> ([String: String], [String]) {
        guard order.count > limit else { return (seen, order) }
        let drop = order.count - limit
        var s = seen
        for id in order.prefix(drop) { s.removeValue(forKey: id) }
        return (s, Array(order.dropFirst(drop)))
    }

    static func observe(_ state: ForYouAlertState, matches: [ForYouAlertMatch], prefsVersion: Int,
                        loading: Bool, limit: Int = seenLimit) -> ForYouAlertState {
        if loading { return state }
        let list = matches.filter { $0.accessible && !$0.draft }
        if !state.baselined || state.prefsVersion != prefsVersion {
            var seen: [String: String] = [:]; var order: [String] = []
            for m in list { if seen[m.id] == nil { order.append(m.id) }; seen[m.id] = m.version }
            let (s, o) = bound(seen, order, limit: limit)
            return ForYouAlertState(baselined: true, prefsVersion: prefsVersion, seen: s, order: o, pending: [:])
        }
        var seen = state.seen; var order = state.order; var pending: [String: String] = [:]
        let present = Set(list.map(\.id))
        for (id, v) in state.pending where present.contains(id) { pending[id] = v }
        for m in list where seen[m.id] != m.version {
            if seen[m.id] == nil { order.append(m.id) }
            seen[m.id] = m.version
            pending[m.id] = m.version
        }
        let (s, o) = bound(seen, order, limit: limit)
        return ForYouAlertState(baselined: true, prefsVersion: prefsVersion, seen: s, order: o, pending: pending)
    }

    /// Opening For You: clear only the ids currently loaded; later arrivals stay pending.
    static func acknowledge(_ state: ForYouAlertState, loadedIDs: [String]) -> ForYouAlertState {
        var s = state
        for id in loadedIDs { s.pending.removeValue(forKey: id) }
        return s
    }

    // MARK: persistence (per account)

    static func storageKey(userID: String) -> String { "banbe.forYouAlert.v1:\(userID)" }

    static func load(userID: String, defaults: UserDefaults = .standard) -> ForYouAlertState {
        guard let data = defaults.data(forKey: storageKey(userID: userID)),
              let st = try? JSONDecoder().decode(ForYouAlertState.self, from: data) else { return ForYouAlertState() }
        return st
    }

    static func save(_ state: ForYouAlertState, userID: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey(userID: userID))
    }
}

/// View-facing holder: persists per account and tracks which pending ids the
/// one-shot animation already ran for (memory only, so re-renders never replay it).
@MainActor
final class ForYouAlertModel: ObservableObject {
    @Published private(set) var state = ForYouAlertState()
    /// True for ~3 s after the pending set gains an id it hasn't animated for.
    @Published private(set) var animating = false
    /// Bumped on every replay so the effect re-runs even when `animating` was already true.
    @Published private(set) var replayToken = 0
    private var userID: String?
    private var animated = Set<String>()
    private var stopTask: Task<Void, Never>?

    var hasPending: Bool { state.hasPending }

    func observe(userID: String?, matches: [ForYouAlertMatch], prefsVersion: Int, loading: Bool) {
        guard let userID else { return }
        if self.userID != userID {
            self.userID = userID
            animated = []
            animating = false
            state = ForYouAlert.load(userID: userID)
        }
        let next = ForYouAlert.observe(state, matches: matches, prefsVersion: prefsVersion, loading: loading)
        guard next != state else { return }
        state = next
        ForYouAlert.save(next, userID: userID)
        let fresh = next.pending.keys.filter { !animated.contains($0) }
        guard !fresh.isEmpty else { return }
        animated.formUnion(fresh)
        animating = true
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self?.animating = false }
        }
    }

    /// Replays the one-shot halo (Home re-entry), regardless of pending state.
    func replay() {
        replayToken += 1
        animating = true
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { self?.animating = false }
        }
    }

    /// Read-only attach (Map): loads this account's persisted state WITHOUT observing, so a
    /// partial viewport set can never baseline/flag matches — Home owns observation.
    func attach(userID: String?) {
        guard let userID, self.userID != userID else { return }
        self.userID = userID
        animated = []
        animating = false
        state = ForYouAlert.load(userID: userID)
    }

    func acknowledge(loadedIDs: [String]) {
        let next = ForYouAlert.acknowledge(state, loadedIDs: loadedIDs)
        guard next != state else { return }
        state = next
        if let userID { ForYouAlert.save(next, userID: userID) }
        if !next.hasPending { animating = false }
    }
}

import SwiftUI

/// One-shot sweep + halo (about 2.4 s), run only when `animating` flips to true.
/// Not repeatForever; Reduce Motion => nothing animates (the static "New" pill remains).
struct ForYouAttentionEffect: ViewModifier {
    var animating: Bool
    var reduceMotion: Bool
    var token: Int = 0
    /// Start of the current run; nil = idle (timeline paused, nothing drawn).
    @State private var startedAt: Date?
    @State private var stopTask: Task<Void, Never>?

    // Web parity (ForYouChip.jsx CSS), evaluated per frame from elapsed time so conditionals
    // (opacity hold-then-fade) are exact — SwiftUI would not re-evaluate them mid-animation.
    //  halo:  keyframes 0% {spread 0, a .6} -> 100% {spread 12, a 0}, 1.2 s ease-out, x2
    //  sheen: translateX -120% -> 220% of its own width, 2.4 s ease-in-out, once;
    //         opacity 1 until 85% then ease-in-out to 0 (per-keyframe timing function).
    private static let haloDuration = 1.2
    private static let sheenDuration = 2.4
    private static let easeOut = UnitBezier(0, 0, 0.58, 1)
    private static let easeInOut = UnitBezier(0.42, 0, 0.58, 1)

    func body(content: Content) -> some View {
        content
            .overlay {
                TimelineView(.animation(paused: startedAt == nil)) { ctx in
                    let t = elapsed(ctx.date)
                    let sp = t < Self.sheenDuration ? Self.easeInOut.solve(t / Self.sheenDuration) : 1
                    let lin = t / Self.sheenDuration
                    let op: Double = t >= Self.sheenDuration ? 0 : (lin < 0.85 ? 1 : 1 - Self.easeInOut.solve((lin - 0.85) / 0.15))
                    GeometryReader { geo in
                        let w = geo.size.width * 0.45
                        // 100deg CSS gradient ~ near-horizontal, slightly tilted.
                        LinearGradient(colors: [.clear, Color(red: 1, green: 0.886, blue: 0.549).opacity(0.75), .clear],
                                       startPoint: UnitPoint(x: 0.0, y: 0.4), endPoint: UnitPoint(x: 1.0, y: 0.6))
                            .frame(width: w)
                            .offset(x: (-1.2 + 3.4 * sp) * w)
                            .opacity(op)
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .background {
                TimelineView(.animation(paused: startedAt == nil)) { ctx in
                    let t = elapsed(ctx.date)
                    let total = Self.haloDuration * 2
                    let cycle = t < total ? Self.easeOut.solve((t.truncatingRemainder(dividingBy: Self.haloDuration)) / Self.haloDuration) : 1
                    let spread = 12 * cycle
                    let alpha = t < total ? 0.6 * (1 - cycle) : 0
                    // Outer-only shadow ring: stroke centred on a capsule inflated by spread/2.
                    Capsule()
                        .stroke(Color(red: 224 / 255, green: 165 / 255, blue: 38 / 255).opacity(alpha), lineWidth: max(spread, 0.001))
                        .padding(-spread / 2)
                        .allowsHitTesting(false)
                }
            }
            // Never stop on `animating` going false: the run is self-terminating (2.6 s).
            .onChange(of: animating) { _, on in if on { run() } }
            .onChange(of: token) { _, _ in run() }
            // Every time the chip appears (Home re-entry, or matches finishing loading) — not
            // gated on the model's 3 s window, which may already have expired by then.
            .onAppear { run() }
    }

    private func elapsed(_ date: Date) -> Double {
        guard let startedAt else { return 1_000 }
        return max(0, date.timeIntervalSince(startedAt))
    }

    private func run() {
        stopTask?.cancel()
        guard !reduceMotion else { startedAt = nil; return }
        startedAt = Date()
        stopTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { startedAt = nil }
        }
    }
}

/// CSS-style cubic-bezier(x1, y1, x2, y2) timing curve: progress x in 0...1 -> eased y.
struct UnitBezier {
    let ax, bx, cx, ay, by, cy: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }
    func solve(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        var t = x
        for _ in 0..<8 {  // Newton
            let err = ((ax * t + bx) * t + cx) * t - x
            if abs(err) < 1e-6 { break }
            let d = (3 * ax * t + 2 * bx) * t + cx
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        var lo = 0.0, hi = 1.0
        if t < 0 || t > 1 || abs(((ax * t + bx) * t + cx) * t - x) > 1e-5 {  // bisection fallback
            t = x
            for _ in 0..<30 {
                let v = ((ax * t + bx) * t + cx) * t
                if abs(v - x) < 1e-6 { break }
                if v < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return ((ay * t + by) * t + cy) * t
    }
}

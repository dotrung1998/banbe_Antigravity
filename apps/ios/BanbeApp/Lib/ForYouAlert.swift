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
    /// 1 = resting/finished.
    @State private var phase: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color(red: 1, green: 0.89, blue: 0.55).opacity(0.75), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.45)
                        .offset(x: -geo.size.width * 0.45 + phase * geo.size.width * 1.45)
                        .opacity(phase < 1 ? 1 : 0)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
            .background {
                Capsule()
                    .stroke(Color(red: 0.88, green: 0.65, blue: 0.15), lineWidth: 3)
                    .scaleEffect(1 + 0.2 * phase)
                    .opacity(Double(1 - phase) * 0.8)
                    .allowsHitTesting(false)
            }
            .onChange(of: animating) { _, on in
                guard on, !reduceMotion else { phase = 1; return }
                phase = 0
                withAnimation(.easeOut(duration: 2.4)) { phase = 1 }
            }
    }
}

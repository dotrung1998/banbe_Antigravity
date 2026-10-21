import Foundation

// Small, dismissible "get started" checklist shown on Home right after the
// personalization flow. Device-local, per account; it only stores whether it
// is on/dismissed and whether an event was opened. Every other item is read
// from real app state (saved events, Face ID), never self-reported.

struct ActivationChecklistState: Codable, Equatable {
    var enabled = false
    var dismissed = false
    var openedEvent = false
    /// The "all set" celebration has played once; after that a finished
    /// checklist stays hidden.
    var celebrated = false

    init(enabled: Bool = false, dismissed: Bool = false, openedEvent: Bool = false, celebrated: Bool = false) {
        self.enabled = enabled
        self.dismissed = dismissed
        self.openedEvent = openedEvent
        self.celebrated = celebrated
    }

    // Tolerant decode: states saved before `celebrated` existed must still load
    // (a synthesized decoder would throw on the missing key and reset everything).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        dismissed = try c.decodeIfPresent(Bool.self, forKey: .dismissed) ?? false
        openedEvent = try c.decodeIfPresent(Bool.self, forKey: .openedEvent) ?? false
        celebrated = try c.decodeIfPresent(Bool.self, forKey: .celebrated) ?? false
    }
}

enum ActivationChecklistItem: String, CaseIterable, Equatable {
    case openEvent, saveEvent, faceID
}

enum ActivationChecklist {
    static func key(_ uid: UUID) -> String { "banbe.activation.v1.\(uid.uuidString)" }

    static func load(uid: UUID, defaults: UserDefaults = .standard) -> ActivationChecklistState {
        guard let data = defaults.data(forKey: key(uid)),
              let s = try? JSONDecoder().decode(ActivationChecklistState.self, from: data) else { return .init() }
        return s
    }

    static func save(_ s: ActivationChecklistState, uid: UUID, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key(uid)) }
    }

    /// Items that apply on this device (Face ID only when biometrics exist).
    static func items(biometricsAvailable: Bool) -> [ActivationChecklistItem] {
        biometricsAvailable ? ActivationChecklistItem.allCases : [.openEvent, .saveEvent]
    }

    static func isDone(_ item: ActivationChecklistItem, state: ActivationChecklistState,
                       hasSavedEvent: Bool, faceIDEnabled: Bool) -> Bool {
        switch item {
        case .openEvent: return state.openedEvent
        case .saveEvent: return hasSavedEvent
        case .faceID: return faceIDEnabled
        }
    }

    static func allDone(state: ActivationChecklistState, items: [ActivationChecklistItem],
                        hasSavedEvent: Bool, faceIDEnabled: Bool) -> Bool {
        items.allSatisfy { isDone($0, state: state, hasSavedEvent: hasSavedEvent, faceIDEnabled: faceIDEnabled) }
    }

    /// Visible while switched on and not dismissed, and either something is
    /// left to do or the one-time "all set" celebration hasn't played yet.
    static func isVisible(state: ActivationChecklistState, items: [ActivationChecklistItem],
                          hasSavedEvent: Bool, faceIDEnabled: Bool) -> Bool {
        guard state.enabled, !state.dismissed else { return false }
        return !state.celebrated
            || !allDone(state: state, items: items, hasSavedEvent: hasSavedEvent, faceIDEnabled: faceIDEnabled)
    }
}

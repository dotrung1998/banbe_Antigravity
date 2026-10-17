import Foundation

// Small, dismissible "get started" checklist shown on Home right after the
// personalization flow. Device-local, per account; it only stores whether it
// is on/dismissed and whether an event was opened. Every other item is read
// from real app state (saved events, Face ID), never self-reported.

struct ActivationChecklistState: Codable, Equatable {
    var enabled = false
    var dismissed = false
    var openedEvent = false
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

    /// Visible while switched on, not dismissed, and something is left to do.
    static func isVisible(state: ActivationChecklistState, items: [ActivationChecklistItem],
                          hasSavedEvent: Bool, faceIDEnabled: Bool) -> Bool {
        guard state.enabled, !state.dismissed else { return false }
        return items.contains { !isDone($0, state: state, hasSavedEvent: hasSavedEvent, faceIDEnabled: faceIDEnabled) }
    }
}

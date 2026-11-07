import Foundation

/// "Add to banbe Schedule" — events a person put on their in-app agenda by
/// hand. DEVICE-LOCAL ONLY (UserDefaults), keyed by account id: there is no
/// backend relationship for this yet, so it does not follow the account to
/// another device or to web (note 44). Stores event ids and the time added —
/// nothing about attendees, payment or the person.
///
/// It is NOT a reservation and NOT an external calendar export.
struct InAppCalendarStore {
    var defaults: UserDefaults = .standard

    struct Entry: Codable, Equatable {
        let eventKey: String
        let addedAt: Date
    }

    enum Result: String, Equatable {
        case added, alreadyAdded, removed, notPresent
    }

    static func key(_ uid: UUID) -> String { "banbe.schedule.added.v1.\(uid.uuidString)" }

    func entries(uid: UUID) -> [Entry] {
        guard let data = defaults.data(forKey: Self.key(uid)),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list
    }

    func keys(uid: UUID) -> [String] { entries(uid: uid).map(\.eventKey) }

    func contains(_ eventKey: String, uid: UUID) -> Bool { keys(uid: uid).contains(eventKey) }

    /// Idempotent: adding twice keeps one entry (and the original time).
    @discardableResult
    func add(_ eventKey: String, uid: UUID, now: Date = Date()) -> Result {
        var list = entries(uid: uid)
        guard !list.contains(where: { $0.eventKey == eventKey }) else { return .alreadyAdded }
        list.append(Entry(eventKey: eventKey, addedAt: now))
        save(list, uid: uid)
        return .added
    }

    @discardableResult
    func remove(_ eventKey: String, uid: UUID) -> Result {
        var list = entries(uid: uid)
        guard let i = list.firstIndex(where: { $0.eventKey == eventKey }) else { return .notPresent }
        list.remove(at: i)
        save(list, uid: uid)
        return .removed
    }

    /// Drops entries for events that are gone or no longer schedulable.
    func prune(uid: UUID, keep: (String) -> Bool) {
        let list = entries(uid: uid)
        let kept = list.filter { keep($0.eventKey) }
        if kept.count != list.count { save(kept, uid: uid) }
    }

    func clear(uid: UUID) { defaults.removeObject(forKey: Self.key(uid)) }

    private func save(_ list: [Entry], uid: UUID) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.key(uid)) }
    }
}

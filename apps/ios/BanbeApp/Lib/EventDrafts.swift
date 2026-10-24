import UIKit

/// A saved, not-yet-submitted event (host feature: up to `EventDraftStore.maxDrafts` per account, on this device).
/// Text fields live in UserDefaults as JSON, photos as JPEG files in Application Support, both keyed by account.
struct HostEventDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var savedAt = Date()
    var step = 0
    var photoFiles: [String] = []
    var coverIndex = 0

    var name = "", desc = "", intro = "", chatGreeting = "", chatGreetingEn = "", keywords = ""
    var cats: [String] = []
    var included: [IncludedItem] = []
    var price = "", seats = "", visibility = "public"
    var hostGoal: String?
    var criteria = ReservationCriteria.everyone
    var eventDate: Date?, eventTime: Date?
    var loc = "", locLabel = "", addressLine = "", district = "", city = "", postalCode = ""
    var lat: Double?, lng: Double?
    var countryCode: String?, stateProvince: String?, neighborhood: String?, placeTimeZoneID: String?
    var locConfirmed = false

    var displayName: String { name.trimmingCharacters(in: .whitespaces) }
}

enum EventDraftStore {
    static let maxDrafts = 5

    private static func key(_ uid: UUID) -> String { "banbe.eventDrafts.v1.\(uid.uuidString.lowercased())" }
    private static func folder(_ id: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("event-drafts/\(id.uuidString)", isDirectory: true)
    }

    static func load(_ uid: UUID) -> [HostEventDraft] {
        guard let data = UserDefaults.standard.data(forKey: key(uid)),
              let list = try? JSONDecoder().decode([HostEventDraft].self, from: data) else { return [] }
        return list.sorted { $0.savedAt > $1.savedAt }
    }

    private static func persist(_ list: [HostEventDraft], _ uid: UUID) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key(uid)) }
    }

    /// Adds a new draft or replaces the one with the same id. False when it would be a 6th.
    @discardableResult
    static func save(_ draft: HostEventDraft, photos: [UIImage], uid: UUID) -> Bool {
        var list = load(uid)
        let isUpdate = list.contains { $0.id == draft.id }
        guard isUpdate || list.count < maxDrafts else { return false }
        var d = draft
        d.savedAt = Date()
        let dir = folder(d.id)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        d.photoFiles = []
        for (i, image) in photos.enumerated() {
            let name = "\(i).jpg"
            if let jpg = image.jpegData(compressionQuality: 0.9), (try? jpg.write(to: dir.appendingPathComponent(name))) != nil {
                d.photoFiles.append(name)
            }
        }
        d.coverIndex = min(max(d.coverIndex, 0), max(d.photoFiles.count - 1, 0))
        list.removeAll { $0.id == d.id }
        list.insert(d, at: 0)
        persist(list, uid)
        return true
    }

    static func photos(of draft: HostEventDraft) -> [UIImage] {
        draft.photoFiles.compactMap { UIImage(contentsOfFile: folder(draft.id).appendingPathComponent($0).path) }
    }

    /// The draft's cover, downscaled for a list row (nil without photos).
    static func coverThumbnail(of draft: HostEventDraft) -> UIImage? {
        guard draft.photoFiles.indices.contains(draft.coverIndex) || !draft.photoFiles.isEmpty else { return nil }
        let file = draft.photoFiles.indices.contains(draft.coverIndex) ? draft.photoFiles[draft.coverIndex] : draft.photoFiles[0]
        guard let image = UIImage(contentsOfFile: folder(draft.id).appendingPathComponent(file).path) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? image
    }

    static func delete(_ id: UUID, uid: UUID) {
        persist(load(uid).filter { $0.id != id }, uid)
        try? FileManager.default.removeItem(at: folder(id))
    }
}

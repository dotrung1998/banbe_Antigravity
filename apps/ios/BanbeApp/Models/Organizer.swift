import Foundation

/// Mirrors the `organizers` table. `id` is a human-readable text slug (not a
/// uuid) — matches the web app's `organizers.id text PRIMARY KEY`.
struct Organizer: Codable, Identifiable, Hashable {
    let id: String
    var ownerId: UUID?
    var userId: UUID?
    var name: String
    var igHandle: String
    var bio: String
    var hostingSince: String
    var verified: Bool
    var disputesOpen: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case userId = "user_id"
        case name
        case igHandle = "ig_handle"
        case bio
        case hostingSince = "hosting_since"
        case verified
        case disputesOpen = "disputes_open"
        case createdAt = "created_at"
    }
}

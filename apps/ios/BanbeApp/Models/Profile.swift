import Foundation

/// Mirrors the `profiles` table (supabase/migrations/…_001_core_schema.sql).
/// One row per auth.users id; RLS restricts SELECT/UPDATE to the owning user.
struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var phone: String
    var phoneVerified: Bool
    var avatarURL: String?
    var locale: String       // "vi" | "en"
    var theme: String?       // "light" | "dark" (migration 018)
    /// False until this account has made an explicit language/theme choice —
    /// distinguishes "never chose" from "chose the defaults", so a fresh
    /// sign-in doesn't overwrite a real preference with a default.
    var prefsSaved: Bool?
    var role: String         // "participant" | "organizer" | "admin"
    var attendedCount: Int
    var noShowCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phone
        case phoneVerified = "phone_verified"
        case avatarURL = "avatar_url"
        case locale
        case theme
        case prefsSaved = "prefs_saved"
        case role
        case attendedCount = "attended_count"
        case noShowCount = "no_show_count"
        case createdAt = "created_at"
    }
}

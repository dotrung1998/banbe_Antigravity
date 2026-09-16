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
    /// Task 4 (migration 056) — the one-time opt-in for auto-emailed
    /// payment document copies. Absent on any row created before that
    /// migration's default backfill, hence Optional.
    var autoEmailDocuments: Bool?
    /// Proof-of-consent (migration 055, banbe_User_Policy.md B1/B3) — nil
    /// until AppState+Data.swift's applySession() records it. Note 10 (this
    /// field was previously never read or written anywhere on iOS at all —
    /// see that note's Task 1 for the gap this closes).
    var policyAcceptedAt: Date?

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
        case autoEmailDocuments = "auto_email_documents"
        case policyAcceptedAt = "policy_accepted_at"
    }
}

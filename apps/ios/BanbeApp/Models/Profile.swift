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
    /// BUG 4 (07-notifications.md's 2026-09-18 follow-up, migration 062) —
    /// the "•••" menu's "Tắt loại thông báo này" action. Absent on any row
    /// created before that migration's default backfill, hence Optional.
    var mutedNotificationKinds: [String]?
    /// TASK D (2026-10-01 UX foundation pass) — shareable profile card
    /// fields (migration 079). `handle` is NOT NULL server-side (every
    /// profile is backfilled one), but this struct decodes it as optional
    /// since a row selected before that migration ran (or a stale cached
    /// response) simply has no such column.
    var handle: String?
    var bio: String?
    var city: String?
    var interests: [String]?
    var profileTheme: String?
    // Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE long-form
    // intro (never overwrites `bio` above) + optional social links,
    // both validated server-side (sanitize_social_links, migration 102).
    var introLong: String?
    var socialLinks: [SocialLink]?
    // Account regression fix pass (2026-09-27), Item 3 — an admin's OWN
    // host-UI preference, separate from `role` (migration 103). Defaults
    // true server-side; optional here only because a row from before this
    // migration has no such column at all.
    var organizerModeEnabled: Bool?

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
        case mutedNotificationKinds = "muted_notification_kinds"
        case handle
        case bio
        case city
        case interests
        case profileTheme = "profile_theme"
        case introLong = "intro_long"
        case socialLinks = "social_links"
        case organizerModeEnabled = "organizer_mode_enabled"
    }
}

/// Organizer Team pass (2026-09-27, Stage 3) — one entry in either a
/// personal profile's or an organizer's `social_links` jsonb column.
/// Server-side validation (sanitize_social_links) is the real boundary;
/// this is just the shape both sides agree on.
struct SocialLink: Codable, Hashable, Identifiable {
    var id: String { platform + url }
    var platform: String
    var url: String
}

import Foundation
import Supabase
import UIKit

/// TASK D (2026-10-01 UX foundation pass) — shareable profile card: the
/// owner's own edit flow, the public read-only profile screen (reachable by
/// handle, works signed-out too), avatar upload, follow/unfollow, share,
/// and the universal-link entry point. Mirrors src/state/BanBeContext.jsx's
/// own TASK D section function-for-function.
struct PublicProfile: Decodable, Equatable {
    struct OrganizerSummary: Decodable, Equatable {
        let id: String
        let name: String
        let verified: Bool
        let hostingSinceYear: Int?
        let eventCount: Int
        var followerCount: Int
        var following: Bool
        enum CodingKeys: String, CodingKey {
            case id, name, verified
            case hostingSinceYear = "hosting_since_year"
            case eventCount = "event_count"
            case followerCount = "follower_count"
            case following
        }
    }

    let success: Bool?
    let error: String?
    let id: UUID?
    let handle: String?
    let displayName: String?
    let avatarURL: String?
    let bio: String?
    let city: String?
    let interests: [String]?
    let profileTheme: String?
    let isOrganizer: Bool?
    // Account extension (2026-09-27, Stage 1) — "organizer mode OFF means
    // host UI is OFF" reaches the Founder line too: migration 096 exposes
    // this profile's own real organizer-mode preference read-only, so
    // PublicProfileView can hide it for every visitor while off.
    let organizerMode: Bool?
    var organizer: OrganizerSummary?
    // Organizer Team pass (2026-09-27, Stage 3) — a SEPARATE long-form
    // intro (never overwrites `bio`) + optional social links.
    let introLong: String?
    let socialLinks: [SocialLink]?
    // Organizer Team pass (2026-09-27, Stage 2) — this profile's OWN
    // opted-in Team badges + real, accepted event-organizing credits
    // (migration 100), both gated server-side on the SAME live
    // public_visible flag — never a client-side guess.
    var teamBadges: [PublicProfileTeamBadge]?
    var creditedEvents: [PublicProfileCreditedEvent]?

    enum CodingKeys: String, CodingKey {
        case success, error, id, handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio, city, interests
        case profileTheme = "profile_theme"
        case isOrganizer = "is_organizer"
        case organizerMode = "organizer_mode"
        case organizer
        case introLong = "intro_long"
        case socialLinks = "social_links"
        case teamBadges = "team_badges"
        case creditedEvents = "credited_events"
    }
}

struct PublicProfileTeamBadge: Decodable, Equatable, Identifiable {
    var id: String { organizerId }
    let organizerId: String
    let organizerName: String
    let publicRole: String
    enum CodingKeys: String, CodingKey {
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
        case publicRole = "public_role"
    }
}

struct PublicProfileCreditedEvent: Decodable, Equatable, Identifiable {
    var id: String { eventId }
    let eventId: String
    let eventName: String
    let organizerId: String
    let organizerName: String
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventName = "event_name"
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
    }
}

/// Personal-vs-organizer hierarchy pass (2026-09-27) — the organizer's own,
/// SEPARATE public profile (get_organizer_profile, migration 095), reached
/// by organizer id — never the owner's personal handle. Mirrors
/// `PublicProfile.OrganizerSummary` field-for-field (same RPC logic,
/// migration 091) plus `about`/`avatarPath`, which that nested summary
/// doesn't carry.
/// A host's live track record: events published (live/ended) and the year of
/// their first one (nil when none has a start time).
struct OrganizerStats: Equatable {
    let count: Int
    let sinceYear: Int?
}

struct OrganizerProfile: Decodable, Equatable {
    let success: Bool?
    let error: String?
    let id: String?
    // DATA FRESHNESS FIX — name/about/avatarPath/introLong/socialLinks are
    // `var`, same as followerCount/following just below (already mutated in
    // place by toggleFollowOrganizer), so saveOrganizerProfile can patch
    // this already-loaded snapshot with exactly what it just wrote to the
    // DB instead of leaving it stale until the screen is reopened.
    var name: String?
    var about: String?
    var avatarPath: String?
    var avatarR2Ref: String? = nil   // organizers.avatar_r2_ref (migration 153), fetched separately
    let verified: Bool?
    let hostingSinceYear: Int?
    let eventCount: Int?
    var followerCount: Int?
    var following: Bool?
    // Organizer Team pass (2026-09-27, Stage 3).
    var introLong: String?
    var socialLinks: [SocialLink]?
    enum CodingKeys: String, CodingKey {
        case success, error, id, name, about, verified, following
        case avatarPath = "avatar_path"
        case hostingSinceYear = "hosting_since_year"
        case eventCount = "event_count"
        case followerCount = "follower_count"
        case introLong = "intro_long"
        case socialLinks = "social_links"
    }
}

/// A concise, real "upcoming events" preview for the organizer profile —
/// never the demo catalogue.
struct OrganizerUpcomingEvent: Decodable, Identifiable {
    let id: String
    let name: String
    /// The event's real first photo (lowest sort_order) as a public URL —
    /// filled in after the fetch; nil when the event has no photo yet.
    var coverURL: String? = nil
    var startsAt: Date? = nil
    var status: String = "live"
    enum CodingKeys: String, CodingKey { case id, name, status; case startsAt = "starts_at" }
}
private struct OrganizerUpcomingCoverRow: Decodable { let event_id: String; let storage_path: String; var r2_ref: String? = nil }

private struct SaveProfileResult: Decodable {
    let success: Bool?
    let error: String?
    let handle: String?
}

private struct SaveProfileParams: Encodable {
    let pHandle: String
    let pDisplayName: String
    let pBio: String
    let pCity: String
    let pInterests: [String]
    let pTheme: String
    let pAvatarUrl: String?
    let pIntroLong: String
    let pSocialLinks: [SocialLink]
    enum CodingKeys: String, CodingKey {
        case pHandle = "p_handle", pDisplayName = "p_display_name", pBio = "p_bio"
        case pCity = "p_city", pInterests = "p_interests", pTheme = "p_theme", pAvatarUrl = "p_avatar_url"
        case pIntroLong = "p_intro_long", pSocialLinks = "p_social_links"
    }
}

extension AppState {
    func openEditProfile() {
        editProfileHandle = user?.handle ?? ""
        editProfileName = user?.displayName ?? ""
        editProfileBio = user?.bio ?? ""
        editProfileCity = user?.city ?? ""
        editProfileInterests = (user?.interests ?? []).joined(separator: ", ")
        editProfileTheme = user?.profileTheme ?? "default"
        editProfileIntroLong = user?.introLong ?? ""
        editProfileLinks = user?.socialLinks ?? []
        editProfileLinksOpen = false
        editProfileError = ""
        editProfileBusy = false
        screen = .editProfile
    }
    func backFromEditProfile() { screen = .profile }

    @discardableResult
    func saveProfileFields(avatarURLOverride: String? = nil) async -> Bool {
        editProfileBusy = true
        editProfileError = ""
        defer { editProfileBusy = false }
        let interests = editProfileInterests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let links = editProfileLinks.filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
        do {
            let result: SaveProfileResult = try await SupabaseService.client
                .rpc("save_profile", params: SaveProfileParams(
                    pHandle: editProfileHandle, pDisplayName: editProfileName, pBio: editProfileBio,
                    pCity: editProfileCity, pInterests: interests, pTheme: editProfileTheme, pAvatarUrl: avatarURLOverride,
                    pIntroLong: editProfileIntroLong, pSocialLinks: links
                ))
                .execute().value
            guard result.success == true else {
                editProfileError = {
                    switch result.error {
                    case "HANDLE_TAKEN": return T("Tên người dùng này đã có người dùng.", "That handle is already taken.")
                    case "INVALID_HANDLE": return T("Tên người dùng chỉ gồm chữ thường, số, dấu gạch dưới (3-24 ký tự).", "Handle must be lowercase letters/numbers/underscore, 3-24 characters.")
                    case "INVALID_NAME": return T("Vui lòng nhập tên hiển thị.", "Please enter a display name.")
                    case "INTRO_TOO_LONG": return T("Giới thiệu quá dài (tối đa 4000 ký tự).", "Intro is too long (4000 characters max).")
                    case "INVALID_LINKS": return T("Một liên kết không hợp lệ. Chỉ chấp nhận đường dẫn https://.", "One of the links is invalid. Only https:// links are accepted.")
                    default: return T("Không thể lưu lúc này. Vui lòng thử lại.", "Could not save right now. Please try again.")
                    }
                }()
                return false
            }
            user?.displayName = editProfileName
            user?.handle = result.handle ?? editProfileHandle
            user?.bio = editProfileBio
            user?.city = editProfileCity
            user?.interests = interests
            user?.profileTheme = editProfileTheme
            user?.introLong = editProfileIntroLong
            user?.socialLinks = links
            if let avatarURLOverride { user?.avatarURL = avatarURLOverride.isEmpty ? nil : avatarURLOverride }
            screen = .profile
            return true
        } catch {
            print("saveProfileFields failed:", error, "userID:", userID?.uuidString ?? "nil")
            editProfileError = T("Không thể lưu lúc này. Vui lòng thử lại.", "Could not save right now. Please try again.")
            return false
        }
    }

    /// Owner-only avatar upload — validated client-side before ever reaching
    /// Storage; the avatars bucket's own RLS (avatars_owner_write, migration
    /// 079/104) additionally enforces the path is under this user's own id.
    /// iPhone fix pass (2026-09-27), Issue 2 — CONFIRMED root cause of
    /// "picking a new image shows 'Vui lòng thử lại' for the personal
    /// profile": `uid.uuidString` is Swift's UPPERCASE UUID representation;
    /// migration 079's RLS compared it against `auth.uid()::text`, which
    /// Postgres always renders lowercase — a case-sensitive `=` never
    /// matched, so every real upload was silently rejected by RLS (not a
    /// decode/size/type problem at all). `.lowercased()` here is the
    /// client-side half of that fix (migration 104 is the authoritative,
    /// any-client-safe half); "Remove" never hit this because
    /// removeAvatar() below never uploads anything.
    /// Returns the new object's (public URL, storage path) — the path is
    /// what a caller needs to roll this upload back if the SUBSEQUENT
    /// save_profile() call fails, so a rejected save never leaves an
    /// orphaned, unreferenced file behind (see changeAvatarAndSave() below).
    func uploadAvatar(_ image: UIImage) async -> (url: String, path: String)? {
        guard let uid = userID else { return nil }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            #if DEBUG
            print("[avatar] stage=decode result=FAILED — UIImage.jpegData returned nil")
            #endif
            editProfileError = T("Không thể tải ảnh lên. Vui lòng thử lại.", "Could not upload the image. Please try again.")
            return nil
        }
        if data.count > 5 * 1024 * 1024 {
            editProfileError = T("Ảnh tối đa 5MB.", "Image must be under 5MB.")
            return nil
        }
        editProfileBusy = true
        editProfileError = ""
        defer { editProfileBusy = false }
        let path = "\(uid.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        do {
            _ = try await SupabaseService.client.storage.from("avatars")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            #if DEBUG
            print("[avatar] stage=upload result=OK path=\(path)")
            #endif
            let url = try SupabaseService.client.storage.from("avatars").getPublicURL(path: path)
            return (url.absoluteString, path)
        } catch {
            #if DEBUG
            // DEBUG only, per this ticket's own instruction — never a
            // token/private URL/bank-data field, just the SDK's own error
            // description and which stage produced it.
            print("[avatar] stage=upload result=FAILED bucket=avatars error=\(error)")
            #endif
            print("uploadAvatar failed:", error, "userID:", uid.uuidString)
            editProfileError = T("Không thể tải ảnh lên. Vui lòng thử lại.", "Could not upload the image. Please try again.")
            return nil
        }
    }

    /// iPhone fix pass (2026-09-27), Issue 2 — replaces EditProfileView's
    /// own two-step "upload, then save" call so this file owns the
    /// rollback: a successful upload followed by a FAILED save_profile()
    /// (a genuinely different failure stage — validation, network, RLS on
    /// `profiles` itself) used to leave that upload permanently orphaned in
    /// the avatars bucket, counted against nothing. Deletes it the instant
    /// the save comes back false.
    @discardableResult
    func changeAvatarAndSave(_ image: UIImage) async -> Bool {
        guard let (url, path) = await uploadAvatar(image) else { return false }
        let saved = await saveProfileFields(avatarURLOverride: url)
        if !saved {
            #if DEBUG
            print("[avatar] stage=save result=FAILED — rolling back orphaned upload path=\(path)")
            #endif
            _ = try? await SupabaseService.client.storage.from("avatars").remove(paths: [path])
        }
        return saved
    }
    func removeAvatar() async { await saveProfileFields(avatarURLOverride: "") }

    /// Personal public profile screen — reachable by handle, works for a
    /// signed-out visitor too (get_public_profile() is granted to anon,
    /// migration 079). Personal-only (2026-09-27 hierarchy pass): never
    /// shows an organizer edit/guest-preview affordance any more — the
    /// organizer's own public page is `openOrganizerProfile` below.
    func openPublicProfile(handle: String, back: Screen = .profile) {
        publicProfileBackScreen = back
        publicProfile = nil
        publicProfileLoading = true
        publicProfileError = ""
        publicProfileHandle = handle
        screen = .publicProfile
        Task { await loadPublicProfile(handle: handle) }
    }
    func loadPublicProfile(handle: String) async {
        do {
            let result: PublicProfile = try await SupabaseService.client
                .rpc("get_public_profile", params: ["p_handle": handle])
                .execute().value
            guard result.success == true else {
                publicProfileLoading = false
                publicProfileError = T("Không tìm thấy hồ sơ này.", "This profile couldn't be found.")
                return
            }
            publicProfile = result
            publicProfileLoading = false
        } catch {
            print("loadPublicProfile failed:", error, "handle:", handle)
            publicProfileLoading = false
            publicProfileError = T("Không tìm thấy hồ sơ này.", "This profile couldn't be found.")
        }
    }
    func backFromPublicProfile() { screen = publicProfileBackScreen }

    /// Bumps WHICHEVER of the two screens (personal profile's merged
    /// organizer summary, or the organizer's own standalone page) currently
    /// holds this organizer id — never both unconditionally, since only
    /// one is ever the actual match.
    func toggleFollowOrganizer(_ organizerID: String) async {
        guard userID != nil else { return }
        // A server-fresh flag a profile loaded with wins over a possibly stale local list.
        let fresh: Bool? = publicProfile?.organizer?.id == organizerID ? publicProfile?.organizer?.following
            : (organizerProfile?.id == organizerID ? organizerProfile?.following : nil)
        let wasFollowing = fresh ?? followedOrgIDs.contains(organizerID)
        await setFollowing(organizerID, !wasFollowing)
    }

    /// The organizer's own, separate public profile — reachable by
    /// organizer_id (never the owner's personal handle), so a shared
    /// /org/<id> link resolves without exposing or requiring any personal
    /// profile field. Fetches only the core stats; the upcoming-events/
    /// photos "extras" are fetched by loadOrganizerProfileExtras below,
    /// called from the view's own `.task` regardless of entry path (in-app
    /// nav or a deep link).
    func openOrganizerProfile(organizerID: String, back: Screen = .profile) {
        organizerProfileBackScreen = back
        organizerProfileReturnsToPulse = false
        organizerProfile = nil
        organizerProfileLoading = true
        organizerProfileError = ""
        organizerProfileID = organizerID
        organizerProfileExtrasLoadedFor = ""
        organizerProfilePast = []
        screen = .organizerProfile
        Task { await loadOrganizerProfile(organizerID: organizerID) }
    }
    func loadOrganizerProfile(organizerID: String) async {
        do {
            let result: OrganizerProfile = try await SupabaseService.client
                .rpc("get_organizer_profile", params: ["p_organizer_id": organizerID])
                .execute().value
            guard result.success == true else {
                organizerProfileLoading = false
                organizerProfileError = T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.")
                return
            }
            organizerProfile = result
            organizerProfileLoading = false
            if let id = result.id { reconcileFollow(id, following: result.following ?? false) }
            // Best effort: organizers.avatar_r2_ref (migration 153) isn't in the RPC.
            if !MediaColumns.missing, result.avatarR2Ref == nil {
                struct RefRow: Decodable { let avatarR2Ref: String?
                    enum CodingKeys: String, CodingKey { case avatarR2Ref = "avatar_r2_ref" } }
                do {
                    let rows: [RefRow] = try await SupabaseService.client
                        .from("organizers").select("avatar_r2_ref").eq("id", value: organizerID).limit(1).execute().value
                    if let ref = rows.first?.avatarR2Ref, organizerProfile?.id == organizerID { organizerProfile?.avatarR2Ref = ref }
                } catch {
                    if MediaColumns.isUndefinedColumn(error) { MediaColumns.markMissing() }
                }
            }
        } catch {
            print("loadOrganizerProfile failed:", error, "organizerID:", organizerID)
            organizerProfileLoading = false
            organizerProfileError = T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.")
        }
    }
    /// Opened from the Pulse popup: Pulse is an overlay, so remember the
    /// screen underneath and restore Pulse itself on back (not Account).
    func openOrganizerProfileFromPulse(organizerID: String) {
        let origin = screen == .organizerProfile ? organizerProfileBackScreen : screen
        closePulseOrganizerSheet()
        pulseOpen = false
        openOrganizerProfile(organizerID: organizerID, back: origin)
        organizerProfileReturnsToPulse = true
    }
    /// The organizer profile is the one host page; an event's "Organizer"
    /// row, a `banbe://organizer/<eventKey>` link and similar entry points
    /// resolve the event's organizer id here and open it. Remembers the
    /// event so back returns to that same event (events opened from the
    /// profile can change `eventKey` in between).
    func openEventOrganizer(eventKey key: String, back: Screen = .event) {
        Task {
            guard let id = await resolveOrganizerID(forEventKey: key) else { return }
            organizerProfileEventKey = key
            if back == .event { eventKey = key }
            openOrganizerProfile(organizerID: id, back: back)
        }
    }
    /// events.organizer_id for a real event; for a demo-catalogue event with
    /// no real row, falls back to the organizer whose name matches.
    func resolveOrganizerID(forEventKey key: String) async -> String? {
        struct EventOrg: Decodable { let organizerId: String?
            enum CodingKeys: String, CodingKey { case organizerId = "organizer_id" } }
        struct OrgRow: Decodable { let id: String }
        if let rows: [EventOrg] = try? await SupabaseService.client
            .from("events").select("organizer_id").eq("id", value: key).limit(1).execute().value,
           let id = rows.first?.organizerId { return id }
        let name = EventCatalog.find(key)?.orgName ?? (key == eventKey ? currentEvent.orgName : "")
        guard !name.isEmpty else { return nil }
        let rows: [OrgRow]? = try? await SupabaseService.client
            .from("organizers").select("id").eq("name", value: name).limit(1).execute().value
        return rows?.first?.id
    }
    /// Fetches (and caches) an organizer's real track record. Re-fetched each
    /// time a screen asks, so it stays current; the cache only avoids a blank flash.
    func loadOrganizerStats(organizerID: String) async {
        guard let result: OrganizerProfile = try? await SupabaseService.client
            .rpc("get_organizer_profile", params: ["p_organizer_id": organizerID])
            .execute().value,
            result.success == true else { return }
        organizerStats[organizerID] = OrganizerStats(count: result.eventCount ?? 0, sinceYear: result.hostingSinceYear)
    }
    func loadEventOrgStats(forEventKey key: String) async {
        let id: String?
        if let known = eventOrganizerID[key] { id = known } else { id = await resolveOrganizerID(forEventKey: key) }
        guard let id else { return }
        eventOrganizerID[key] = id
        await loadOrganizerStats(organizerID: id)
    }
    func backFromOrganizerProfile() {
        let toPulse = organizerProfileReturnsToPulse
        organizerProfileReturnsToPulse = false
        if organizerProfileBackScreen == .event, !organizerProfileEventKey.isEmpty, eventKey != organizerProfileEventKey {
            eventKey = organizerProfileEventKey
            Task { await loadBookingForCurrentEvent() }
            Task { await loadLiveEventStatus() }
        }
        screen = organizerProfileBackScreen
        if toPulse { pulseOpen = true }  // lists kept — no refetch/clear
    }

    /// Small preview content for the organizer public profile — real
    /// upcoming events (published, soonest first) and a handful of real
    /// photos from those same events, never invented. Guarded on
    /// `organizerProfileExtrasLoadedFor` so returning to an already-loaded
    /// organizer doesn't re-fetch.
    func loadOrganizerProfileExtras(organizerID: String) async {
        guard organizerProfileExtrasLoadedFor != organizerID else { return }
        organizerProfileExtrasLoadedFor = organizerID
        do {
            // Live + ended in one query; split below. Events have no end time and the server only
            // flips live -> ended on a cron, so a live row 12h+ past its start counts as past too.
            let rows: [OrganizerUpcomingEvent] = try await SupabaseService.client
                .from("events").select("id, name, status, starts_at")
                .eq("organizer_id", value: organizerID).in("status", values: ["live", "ended"])
                .order("starts_at", ascending: true).limit(200)
                .execute().value
            let cutoff = Date().addingTimeInterval(-12 * 3600)
            func isPast(_ e: OrganizerUpcomingEvent) -> Bool {
                e.status == "ended" || (e.startsAt.map { $0 < cutoff } ?? false)
            }
            var upcoming = Array(rows.filter { !isPast($0) }.prefix(5))
            var past = Array(rows.filter(isPast).sorted { ($0.startsAt ?? .distantPast) > ($1.startsAt ?? .distantPast) }.prefix(30))
            let coverIDs = upcoming.map(\.id) + past.map(\.id)
            if !coverIDs.isEmpty {
                let covers: [OrganizerUpcomingCoverRow] = (try? await MediaColumns.retrying { withR2 in
                    try await SupabaseService.client
                        .from("event_photos").select(MediaColumns.cols("event_id, storage_path", "r2_ref", withR2))
                        .in("event_id", values: coverIDs)
                        .order("sort_order", ascending: true)
                        .execute().value
                }) ?? []
                func fill(_ list: inout [OrganizerUpcomingEvent]) {
                    for i in list.indices {
                        guard let c = covers.first(where: { $0.event_id == list[i].id }) else { continue }
                        list[i].coverURL = MediaURLs.eventPhoto(storagePath: c.storage_path, r2Ref: c.r2_ref, variant: .card)?.absoluteString
                    }
                }
                fill(&upcoming); fill(&past)
            }
            organizerProfileUpcoming = upcoming
            organizerProfilePast = past
        } catch {
            print("loadOrganizerProfileExtras failed:", error, "organizerID:", organizerID)
        }
    }

    /// https://banbe.app/u/<handle> (personal) and .../org/<organizer_id>
    /// (the organizer's own separate page) — the universal link's in-app
    /// destinations. Falls through silently (does nothing) for any other
    /// path; RootView/BanbeApp.swift's .onContinueUserActivity handler is
    /// the only caller.
    ///
    /// Under Config/PersonalTeamDebug.xcconfig (.claude/notes/
    /// 18-ios-personal-team-signing.md) this function is simply never
    /// reached at all — that build's entitlements omit
    /// com.apple.developer.associated-domains, so iOS never routes a
    /// banbe.app link to this app in the first place; it opens in Safari
    /// instead, the ordinary system behavior for a link with no verified
    /// app association. No code here needs to detect or special-case that.
    func handleUniversalLink(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "u": openPublicProfile(handle: parts[1].lowercased(), back: .home)
        case "org": openOrganizerProfile(organizerID: parts[1], back: .home)
        case "surveys": Task { await self.openSurveyPublic(publicID: parts[1], back: .home) }
        default: break
        }
    }
}

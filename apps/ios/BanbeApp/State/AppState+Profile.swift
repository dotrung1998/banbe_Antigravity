import Foundation
import Supabase
import UIKit

/// TASK D (2026-10-01 UX foundation pass) — shareable profile card: the
/// owner's own edit flow, the public read-only profile screen (reachable by
/// handle, works signed-out too), avatar upload, follow/unfollow, share,
/// and the universal-link entry point. Mirrors src/state/GocContext.jsx's
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
    var organizer: OrganizerSummary?

    enum CodingKeys: String, CodingKey {
        case success, error, id, handle
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bio, city, interests
        case profileTheme = "profile_theme"
        case isOrganizer = "is_organizer"
        case organizer
    }
}

/// Personal-vs-organizer hierarchy pass (2026-09-27) — the organizer's own,
/// SEPARATE public profile (get_organizer_profile, migration 095), reached
/// by organizer id — never the owner's personal handle. Mirrors
/// `PublicProfile.OrganizerSummary` field-for-field (same RPC logic,
/// migration 091) plus `about`/`avatarPath`, which that nested summary
/// doesn't carry.
struct OrganizerProfile: Decodable, Equatable {
    let success: Bool?
    let error: String?
    let id: String?
    let name: String?
    let about: String?
    let avatarPath: String?
    let verified: Bool?
    let hostingSinceYear: Int?
    let eventCount: Int?
    var followerCount: Int?
    var following: Bool?
    enum CodingKeys: String, CodingKey {
        case success, error, id, name, about, verified, following
        case avatarPath = "avatar_path"
        case hostingSinceYear = "hosting_since_year"
        case eventCount = "event_count"
        case followerCount = "follower_count"
    }
}

/// A concise, real "upcoming events" preview for the organizer profile —
/// never the demo catalogue.
struct OrganizerUpcomingEvent: Decodable, Identifiable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case id, name }
}
private struct OrganizerProfilePhotoEventRow: Decodable { let id: String }

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
    enum CodingKeys: String, CodingKey {
        case pHandle = "p_handle", pDisplayName = "p_display_name", pBio = "p_bio"
        case pCity = "p_city", pInterests = "p_interests", pTheme = "p_theme", pAvatarUrl = "p_avatar_url"
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
        do {
            let result: SaveProfileResult = try await SupabaseService.client
                .rpc("save_profile", params: SaveProfileParams(
                    pHandle: editProfileHandle, pDisplayName: editProfileName, pBio: editProfileBio,
                    pCity: editProfileCity, pInterests: interests, pTheme: editProfileTheme, pAvatarUrl: avatarURLOverride
                ))
                .execute().value
            guard result.success == true else {
                editProfileError = {
                    switch result.error {
                    case "HANDLE_TAKEN": return T("Tên người dùng này đã có người dùng.", "That handle is already taken.")
                    case "INVALID_HANDLE": return T("Tên người dùng chỉ gồm chữ thường, số, dấu gạch dưới (3-24 ký tự).", "Handle must be lowercase letters/numbers/underscore, 3-24 characters.")
                    case "INVALID_NAME": return T("Vui lòng nhập tên hiển thị.", "Please enter a display name.")
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
    /// 079) additionally enforces the path is under this user's own id.
    func uploadAvatar(_ image: UIImage) async -> String? {
        guard let uid = userID else { return nil }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        if data.count > 5 * 1024 * 1024 {
            editProfileError = T("Ảnh tối đa 5MB.", "Image must be under 5MB.")
            return nil
        }
        editProfileBusy = true
        editProfileError = ""
        defer { editProfileBusy = false }
        let path = "\(uid.uuidString)/\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        do {
            _ = try await SupabaseService.client.storage.from("avatars")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let url = try SupabaseService.client.storage.from("avatars").getPublicURL(path: path)
            return url.absoluteString
        } catch {
            print("uploadAvatar failed:", error, "userID:", uid.uuidString)
            editProfileError = T("Không thể tải ảnh lên. Vui lòng thử lại.", "Could not upload the image. Please try again.")
            return nil
        }
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
        guard let uid = userID else { return }
        let matchesPublicProfile = publicProfile?.organizer?.id == organizerID
        let matchesOrganizerProfile = organizerProfile?.id == organizerID
        guard matchesPublicProfile || matchesOrganizerProfile else { return }
        let wasFollowing = matchesPublicProfile ? (publicProfile?.organizer?.following ?? false) : (organizerProfile?.following ?? false)
        func apply(_ following: Bool) {
            let sign = following ? 1 : -1
            if matchesPublicProfile {
                publicProfile?.organizer?.following = following
                publicProfile?.organizer?.followerCount += sign
            }
            if matchesOrganizerProfile {
                organizerProfile?.following = following
                organizerProfile?.followerCount = (organizerProfile?.followerCount ?? 0) + sign
            }
        }
        apply(!wasFollowing)
        do {
            if wasFollowing {
                _ = try await SupabaseService.client.from("follows")
                    .delete().eq("user_id", value: uid.uuidString).eq("organizer_id", value: organizerID).execute()
            } else {
                _ = try await SupabaseService.client.from("follows")
                    .insert(["user_id": uid.uuidString, "organizer_id": organizerID]).execute()
            }
        } catch {
            print("toggleFollowOrganizer failed:", error)
            apply(wasFollowing)
        }
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
        organizerProfile = nil
        organizerProfileLoading = true
        organizerProfileError = ""
        organizerProfileID = organizerID
        organizerProfileExtrasLoadedFor = ""
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
        } catch {
            print("loadOrganizerProfile failed:", error, "organizerID:", organizerID)
            organizerProfileLoading = false
            organizerProfileError = T("Không tìm thấy tổ chức này.", "This organizer couldn't be found.")
        }
    }
    func backFromOrganizerProfile() { screen = organizerProfileBackScreen }

    /// Small preview content for the organizer public profile — real
    /// upcoming events (published, soonest first) and a handful of real
    /// photos from those same events, never invented. Guarded on
    /// `organizerProfileExtrasLoadedFor` so returning to an already-loaded
    /// organizer doesn't re-fetch.
    func loadOrganizerProfileExtras(organizerID: String) async {
        guard organizerProfileExtrasLoadedFor != organizerID else { return }
        organizerProfileExtrasLoadedFor = organizerID
        do {
            async let upcomingReq: [OrganizerUpcomingEvent] = SupabaseService.client
                .from("events").select("id, name")
                .eq("organizer_id", value: organizerID).eq("status", value: "live")
                .order("starts_at", ascending: true).limit(5)
                .execute().value
            async let photoEventsReq: [OrganizerProfilePhotoEventRow] = SupabaseService.client
                .from("events").select("id")
                .eq("organizer_id", value: organizerID).eq("status", value: "live").eq("visibility", value: "public")
                .execute().value
            let (upcoming, photoEvents) = try await (upcomingReq, photoEventsReq)
            organizerProfileUpcoming = upcoming
            let photoEventIDs = photoEvents.map(\.id)
            if photoEventIDs.isEmpty {
                organizerProfilePhotos = []
            } else {
                organizerProfilePhotos = try await SupabaseService.client
                    .from("event_photos").select("id, event_id, storage_path, sort_order")
                    .in("event_id", values: photoEventIDs)
                    .order("sort_order", ascending: true).limit(8)
                    .execute().value
            }
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
        default: break
        }
    }
}

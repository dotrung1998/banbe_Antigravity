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
        let hostingSince: String?
        let eventCount: Int
        var followerCount: Int
        var following: Bool
        enum CodingKeys: String, CodingKey {
            case id, name, verified
            case hostingSince = "hosting_since"
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

    /// Public profile screen — reachable by handle, works for a signed-out
    /// visitor too (get_public_profile() is granted to anon, migration 079).
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

    func toggleFollowOrganizer(_ organizerID: String) async {
        guard let uid = userID, var org = publicProfile?.organizer else { return }
        let wasFollowing = org.following
        org.following.toggle()
        org.followerCount += wasFollowing ? -1 : 1
        publicProfile?.organizer = org
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
            org.following = wasFollowing
            org.followerCount += wasFollowing ? 1 : -1
            publicProfile?.organizer = org
        }
    }

    /// https://banbe.app/u/<handle> — the universal link's in-app
    /// destination. Falls through silently (does nothing) for any other
    /// path; RootView/BanbeApp.swift's .onContinueUserActivity handler is
    /// the only caller.
    func handleUniversalLink(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "u" else { return }
        openPublicProfile(handle: parts[1].lowercased(), back: .home)
    }
}

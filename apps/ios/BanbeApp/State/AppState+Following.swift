import Foundation
import Supabase

// Account > Following + the shared "✓ Following" marker (web: src/lib/followSync.js + follows.js).
// Reads/writes ONLY the signed-in user's own `follows(user_id, organizer_id)` rows (owner-only
// RLS, migration 003): the list is never published. Organizer ids are the only identity used.
// Every async step re-checks the account, one write per host at a time, a failed write reverts
// and says so, and everything is cleared the moment the account changes.

enum FollowedStatus: Equatable { case idle, loading, loaded, error }

struct FollowedHost: Identifiable, Equatable {
    let organizerID: String
    var name: String
    var avatarPath: String
    var avatarR2Ref: String
    var verified: Bool
    /// false = the organizer row is no longer readable (deleted/hidden): still listed so it can be unfollowed.
    var available: Bool
    var id: String { organizerID }
}

/// Pure logic, kept free of AppState/network so it is unit-testable.
enum FollowLogic {
    static func applyChange(_ ids: Set<String>, _ organizerID: String, following: Bool) -> Set<String> {
        var out = ids
        if following { out.insert(organizerID) } else { out.remove(organizerID) }
        return out
    }

    struct OrgRow: Decodable {
        let id: String
        let name: String?
        let avatarPath: String?
        let avatarR2Ref: String?
        let verified: Bool?
        enum CodingKeys: String, CodingKey { case id, name, verified; case avatarPath = "avatar_path"; case avatarR2Ref = "avatar_r2_ref" }
    }

    /// follows ids + readable organizers -> rows, alphabetical (accent-insensitive), unavailable last.
    static func build(followIDs: [String], orgs: [OrgRow]) -> [FollowedHost] {
        let byID = Dictionary(orgs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var rows: [FollowedHost] = []
        for id in followIDs where !id.isEmpty && seen.insert(id).inserted {
            if let o = byID[id] {
                rows.append(FollowedHost(organizerID: id, name: o.name ?? "", avatarPath: o.avatarPath ?? "",
                                         avatarR2Ref: o.avatarR2Ref ?? "", verified: o.verified ?? false, available: true))
            } else {
                rows.append(FollowedHost(organizerID: id, name: "", avatarPath: "", avatarR2Ref: "", verified: false, available: false))
            }
        }
        return rows.sorted { a, b in
            if a.available != b.available { return a.available }
            let na = SearchMatch.normalize(a.name), nb = SearchMatch.normalize(b.name)
            return na != nb ? na < nb : a.organizerID < b.organizerID
        }
    }

    /// Name-only, accent/case-insensitive, multi-token AND (the app's one matcher).
    static func filter(_ rows: [FollowedHost], query: String) -> [FollowedHost] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return rows }
        return rows.filter { $0.available && SearchMatch.matches(doc: SearchMatch.normalize($0.name), query: q) }
    }

    /// A write is fine when it worked or the row already was in the wanted state.
    static func writeOK(error: Error?, following: Bool) -> Bool {
        guard let error else { return true }
        guard following else { return false }
        if let pg = error as? PostgrestError { return pg.code == "23505" || pg.message.localizedCaseInsensitiveContains("duplicate key") }
        return false
    }
}

extension AppState {

    func isFollowing(_ organizerID: String?) -> Bool {
        guard let organizerID else { return false }
        return followedOrgIDs.contains(organizerID)
    }

    /// Clears every follow-related field (account switch / sign-out).
    func resetFollowState() {
        followedOrgIDs = []
        followedHosts = []
        followedStatus = .idle
        followedError = ""
        followWriteError = ""
        followBusy = []
        followOwnerID = nil
    }

    /// Call whenever the signed-in account may have changed.
    func syncFollowOwner() {
        guard followOwnerID != userID else { return }
        resetFollowState()
        followOwnerID = userID
        if userID != nil { Task { await loadFollowedHosts(silent: true) } }
    }

    func loadFollowedHosts(silent: Bool = false) async {
        guard let uid = userID else { return }
        if followOwnerID != uid { followOwnerID = uid }
        if !silent { followedStatus = (followedStatus == .loaded) ? .loaded : .loading; followedError = "" }
        func fail() {
            followedStatus = (followedStatus == .loaded) ? .loaded : .error
            followedError = T("Không tải được danh sách đang theo dõi.", "Couldn't load the hosts you follow.")
        }
        struct FollowRow: Decodable { let organizerId: String
            enum CodingKeys: String, CodingKey { case organizerId = "organizer_id" } }
        do {
            let rows: [FollowRow] = try await SupabaseService.client.from("follows")
                .select("organizer_id").eq("user_id", value: uid.uuidString).execute().value
            guard userID == uid else { return } // signed out / switched account meanwhile
            let ids = rows.map(\.organizerId)
            var orgs: [FollowLogic.OrgRow] = []
            if !ids.isEmpty {
                orgs = try await SupabaseService.client.from("organizers")
                    .select("id, name, avatar_path, avatar_r2_ref, verified").in("id", values: ids).execute().value
                guard userID == uid else { return }
            }
            if !followBusy.isEmpty { return } // a write is in flight; its completion re-reads
            followedOrgIDs = Set(ids)
            followedHosts = FollowLogic.build(followIDs: ids, orgs: orgs)
            followedStatus = .loaded
            followedError = ""
        } catch {
            print("loadFollowedHosts failed:", error)
            guard userID == uid else { return }
            fail()
        }
    }

    /// Follow/unfollow one organizer by id — the ONE write path every control uses.
    /// Returns true on success; on failure the UI is reverted and `followWriteError` is set.
    @discardableResult
    func setFollowing(_ organizerID: String, _ following: Bool) async -> Bool {
        guard let uid = userID, !organizerID.isEmpty else { return false }
        if followedOwnerMismatch(uid) { return false }
        guard !followBusy.contains(organizerID) else { return false } // double tap
        followBusy.insert(organizerID)
        let before = followedOrgIDs.contains(organizerID)
        let hostRow = followedHosts.first { $0.organizerID == organizerID }
        followWriteError = ""
        patchFollowViews(organizerID, following)
        var ok = false
        do {
            if following {
                _ = try await SupabaseService.client.from("follows")
                    .insert(["user_id": uid.uuidString, "organizer_id": organizerID]).execute()
            } else {
                _ = try await SupabaseService.client.from("follows")
                    .delete().eq("user_id", value: uid.uuidString).eq("organizer_id", value: organizerID).execute()
            }
            ok = true
        } catch {
            ok = FollowLogic.writeOK(error: error, following: following)
            if !ok { print("setFollowing failed:", error) }
        }
        guard userID == uid else { return ok } // account changed mid-write: resetFollowState owns the state now
        followBusy.remove(organizerID)
        if !ok {
            patchFollowViews(organizerID, before)
            if before, let hostRow, !followedHosts.contains(where: { $0.organizerID == organizerID }) { followedHosts.append(hostRow) }
            followWriteError = following
                ? T("Không thể theo dõi lúc này. Thử lại nhé.", "Couldn't follow right now. Please try again.")
                : T("Không thể bỏ theo dõi lúc này. Thử lại nhé.", "Couldn't unfollow right now. Please try again.")
            return false
        }
        await loadFollowedHosts(silent: true)
        return true
    }

    private func followedOwnerMismatch(_ uid: UUID) -> Bool {
        if followOwnerID == uid { return false }
        resetFollowState()
        followOwnerID = uid
        return false
    }

    /// Patches every in-memory view that carries a per-host `following` flag (never the network).
    private func patchFollowViews(_ organizerID: String, _ following: Bool) {
        let was = followedOrgIDs.contains(organizerID)
        let sign = (was == following) ? 0 : (following ? 1 : -1)
        followedOrgIDs = FollowLogic.applyChange(followedOrgIDs, organizerID, following: following)
        if !following { followedHosts.removeAll { $0.organizerID == organizerID } }
        if publicProfile?.organizer?.id == organizerID, publicProfile?.organizer?.following != following {
            publicProfile?.organizer?.following = following
            publicProfile?.organizer?.followerCount = max(0, (publicProfile?.organizer?.followerCount ?? 0) + sign)
        }
        if organizerProfile?.id == organizerID, (organizerProfile?.following ?? false) != following {
            organizerProfile?.following = following
            organizerProfile?.followerCount = max(0, (organizerProfile?.followerCount ?? 0) + sign)
        }
        if pulseOrganizerSheet?.organizerId == organizerID { pulseOrganizerSheet?.following = following }
    }

    /// A server-fresh flag (e.g. get_organizer_profile) folded into the list. Returns true when it differed.
    @discardableResult
    func reconcileFollow(_ organizerID: String, following: Bool) -> Bool {
        guard followedStatus == .loaded, followedOrgIDs.contains(organizerID) != following else { return false }
        followedOrgIDs = FollowLogic.applyChange(followedOrgIDs, organizerID, following: following)
        Task { await loadFollowedHosts(silent: true) }
        return true
    }
}

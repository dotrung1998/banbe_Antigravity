import Foundation

/// Photo-interactions redesign (2026-09-26) — the iOS port of
/// src/state/GocContext.jsx's own canonical `photoEngagement` section.
/// Migration 086 (already live, do not re-run `supabase db push`) added
/// `get_photo_engagement(p_photo_ids)`, the general-purpose read path for
/// ANY real `event_photos` id (migration 083's `get_pulse_photo_ranked`
/// only ever covers the top-20 ranked photos, not every photo in a
/// gallery). `toggle_photo_like`/`log_photo_share` (both 083) are unchanged.
///
/// One row of `get_photo_engagement()`'s own response, and the shape
/// `loadPulsePhotos()` (AppState+Pulse.swift) also builds from its ranking
/// RPC's rows + a separate own-liked-ids query, so both loaders can feed
/// the SAME `mergePhotoEngagement` below.
struct PhotoEngagementRow: Decodable {
    let photoId: String
    let eventId: String
    let likeCount: Int
    let shareCount: Int
    let likedByMe: Bool
    enum CodingKeys: String, CodingKey {
        case photoId = "photo_id"
        case eventId = "event_id"
        case likeCount = "like_count"
        case shareCount = "share_count"
        case likedByMe = "liked_by_me"
    }
}

private struct PhotoEngagementResult: Decodable {
    let success: Bool?
    let items: [PhotoEngagementRow]?
}

/// Pure merge — mirrors GocContext.jsx's own top-level `mergePhotoEngagement`
/// function-for-function: merges rows into the canonical map WITHOUT
/// dropping ids not present in THIS particular batch (used by every loader
/// that touches `photoEngagement`), never a full replace.
func mergePhotoEngagement(_ existing: [String: PhotoEngagement], rows: [PhotoEngagementRow]) -> [String: PhotoEngagement] {
    guard !rows.isEmpty else { return existing }
    var next = existing
    for r in rows {
        next[r.photoId] = PhotoEngagement(likeCount: r.likeCount, shareCount: r.shareCount, likedByMe: r.likedByMe)
    }
    return next
}

extension AppState {
    /// General-purpose engagement read path for ANY real `event_photos`
    /// ids — called (fire-and-forget, not awaited) right after
    /// `loadEventPhotos`/`loadOrganizerPhotos` set their own photo arrays
    /// (AppState+Data.swift), same call sites web's own `loadPhotoEngagement`
    /// is wired into.
    func loadPhotoEngagement(_ photoIds: [String]) async {
        guard !photoIds.isEmpty else { return }
        do {
            let result: PhotoEngagementResult = try await SupabaseService.client
                .rpc("get_photo_engagement", params: ["p_photo_ids": photoIds])
                .execute().value
            guard result.success == true else { return }
            photoEngagement = mergePhotoEngagement(photoEngagement, rows: result.items ?? [])
        } catch {
            print("loadPhotoEngagement failed:", error)
        }
    }

    /// Real, server-enforced like toggle for ANY real photo (migration
    /// 083's `toggle_photo_like` RPC) — the ONE like path for EventDetail's/
    /// Organizer's grids, the full-screen PhotoViewerView AND Pulse's photo
    /// tab (replaces the old per-surface `togglePulsePhotoLike`, folded in
    /// here — mirrors web's unified `togglePhotoLike` in GocContext.jsx).
    /// Optimistic with rollback on failure; `photoEngagementBusy` blocks a
    /// double-tap/racing toggle on the same photo id.
    ///
    /// Race-condition discipline (proven live on web, see GocContext.jsx's
    /// own comment on this exact function): `optimistic` is computed ONCE,
    /// from the state observed BEFORE this function's only `await`, and
    /// captured in a local `let` — never re-derived a second time from
    /// `self.photoEngagement` after the RPC resolves. Only the boolean
    /// field is corrected post-await, from the RPC's own authoritative
    /// response; the count stays exactly what was already applied
    /// optimistically. Re-reading `self.photoEngagement[photoId]` again
    /// inside the post-await continuation instead would risk observing a
    /// stale pre-optimistic-update snapshot and silently reverting the
    /// count bump — the same bug class in Swift as in a JS state updater
    /// that runs after an `await`.
    func togglePhotoLike(_ photoId: String) async {
        guard isSignedIn else { requireAuth(returnTo: .profile, backTo: .profile); return }
        guard !photoEngagementBusy.contains(photoId) else { return }
        let cur = photoEngagement[photoId] ?? PhotoEngagement(likeCount: 0, shareCount: 0, likedByMe: false)
        let wasLiked = cur.likedByMe
        let delta = wasLiked ? -1 : 1
        let optimistic = PhotoEngagement(likeCount: max(0, cur.likeCount + delta), shareCount: cur.shareCount, likedByMe: !wasLiked)
        photoEngagement[photoId] = optimistic
        photoEngagementBusy.insert(photoId)
        do {
            let liked: Bool = try await SupabaseService.client
                .rpc("toggle_photo_like", params: ["p_event_photo_id": photoId])
                .execute().value
            // Reconcile against the RPC's own authoritative boolean only —
            // `optimistic` (captured above, before the await) is reused
            // verbatim for the count, never re-read from `self` here.
            photoEngagement[photoId] = PhotoEngagement(likeCount: optimistic.likeCount, shareCount: optimistic.shareCount, likedByMe: liked)
            photoEngagementBusy.remove(photoId)
        } catch {
            print("togglePhotoLike failed:", error)
            photoEngagement[photoId] = cur
            photoEngagementBusy.remove(photoId)
        }
    }

    /// Real share tracking for ANY real photo (migration 083's
    /// `log_photo_share` RPC) — logged ONLY once a share genuinely
    /// completes (a `UIActivityViewController`'s own
    /// `completionWithItemsHandler` reporting `completed == true`), never
    /// merely from presenting the share sheet. A single post-await `set` —
    /// no earlier optimistic step, so no race risk (mirrors web's
    /// `sharePhoto`'s own `logShare`, which only ever writes once, after
    /// the RPC succeeds).
    func logPhotoShare(_ photoId: String, channel: String = "native") async {
        do {
            _ = try await SupabaseService.client
                .rpc("log_photo_share", params: ["p_event_photo_id": photoId, "p_channel": channel])
                .execute()
            let cur = photoEngagement[photoId] ?? PhotoEngagement(likeCount: 0, shareCount: 0, likedByMe: false)
            photoEngagement[photoId] = PhotoEngagement(likeCount: cur.likeCount, shareCount: cur.shareCount + 1, likedByMe: cur.likedByMe)
        } catch {
            print("logPhotoShare failed:", error)
        }
    }
}

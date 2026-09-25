import Foundation

/// TASK E (2026-10-01 UX foundation pass) — Banbe Pulse: a permanent,
/// system-generated ring entry — deliberately NOT a real row in `stories`
/// (that table hard-expires everything in 24h). Mirrors src/state/
/// GocContext.jsx's own TASK E section function-for-function.
// 2026-09-25 fix pass — `.photos` added for the third Pulse tab (ranked
// individual event photos). `loadPulsePhotos()` below always calls the RPC
// with `daily`'s window (see that function's own doc comment for why), so
// this case is purely a UI tab selector, never itself sent as `p_period`.
enum PulseTab: String { case daily, weekly, photos }

struct PulseItem: Decodable, Identifiable, Equatable {
    let eventId: String
    let eventName: String
    let photoPath: String?
    let organizerId: String
    let organizerName: String
    let organizerVerified: Bool
    let score: Double
    var following: Bool = false
    var id: String { eventId }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventName = "event_name"
        case photoPath = "photo_path"
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
        case organizerVerified = "organizer_verified"
        case score
    }
}

private struct PulseResult: Decodable {
    let success: Bool?
    let period: String?
    let items: [PulseItem]?
}

/// 2026-09-25 fix pass — one row of `get_pulse_photo_ranked()` (migration
/// 083): a single real `event_photos` row ranked by likes/shares, distinct
/// from `PulseItem` (which ranks ORGANIZERS via their best event). `var`
/// count fields so `togglePulsePhotoLike`/`sharePulsePhoto` can patch them
/// optimistically in place, same mutability `PulseItem.following` already
/// has for the same reason.
struct PulsePhotoItem: Decodable, Identifiable, Equatable {
    let photoId: String
    let eventId: String
    let eventName: String
    let photoPath: String?
    let organizerId: String
    let organizerName: String
    let organizerVerified: Bool
    var likeCount: Int
    var shareCount: Int
    let score: Double
    var id: String { photoId }

    enum CodingKeys: String, CodingKey {
        case photoId = "photo_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case photoPath = "photo_path"
        case organizerId = "organizer_id"
        case organizerName = "organizer_name"
        case organizerVerified = "organizer_verified"
        case likeCount = "like_count"
        case shareCount = "share_count"
        case score
    }
}

private struct PulsePhotoResult: Decodable {
    let success: Bool?
    let period: String?
    let items: [PulsePhotoItem]?
}

extension AppState {
    func loadPulse(period: PulseTab) async {
        let seq: Int
        if period == .weekly { pulseWeeklySeq += 1; seq = pulseWeeklySeq; pulseWeeklyLoading = true }
        else { pulseDailySeq += 1; seq = pulseDailySeq; pulseDailyLoading = true }
        do {
            let result: PulseResult = try await SupabaseService.client
                .rpc("goc_pulse_ranked", params: ["p_period": period.rawValue])
                .execute().value
            // Only the newest call for THIS period may write — reopening
            // Pulse quickly can't let an older response overwrite a newer
            // one (same pattern as loadRefundQueue/loadAttendanceGuests).
            guard (period == .weekly ? seq == pulseWeeklySeq : seq == pulseDailySeq) else { return }
            guard result.success == true else {
                if period == .weekly { pulseWeeklyLoading = false } else { pulseDailyLoading = false }
                return
            }
            let items = result.items ?? []
            if period == .weekly { pulseWeekly = items; pulseWeeklyLoading = false }
            else { pulseDaily = items; pulseDailyLoading = false }
        } catch {
            guard (period == .weekly ? seq == pulseWeeklySeq : seq == pulseDailySeq) else { return }
            print("loadPulse failed:", error, "period:", period.rawValue)
            if period == .weekly { pulseWeeklyLoading = false } else { pulseDailyLoading = false }
        }
    }

    /// 2026-09-25 fix pass — the third Pulse tab's own ranking, loaded
    /// alongside daily/weekly on every open (same "never leave stale data
    /// sitting there" rule as loadPulse above). Fixed at the 'daily'
    /// window — this ticket asks for one photo-ranking tab, not a second
    /// period toggle layered underneath it; 'daily' matches the event
    /// tabs' own default.
    func loadPulsePhotos() async {
        pulsePhotosSeq += 1
        let seq = pulsePhotosSeq
        pulsePhotosLoading = true
        do {
            let result: PulsePhotoResult = try await SupabaseService.client
                .rpc("get_pulse_photo_ranked", params: ["p_period": "daily"])
                .execute().value
            guard seq == pulsePhotosSeq else { return }
            guard result.success == true else { pulsePhotosLoading = false; return }
            pulsePhotos = result.items ?? []
            pulsePhotosLoading = false
        } catch {
            guard seq == pulsePhotosSeq else { return }
            print("loadPulsePhotos failed:", error)
            pulsePhotosLoading = false
        }
    }

    func openPulseViewer() {
        pulseTab = .daily
        // Never leave a previous session's rank sitting there indefinitely
        // (rule A5) — cleared before the fresh fetch, not just overwritten
        // once it lands, so the loading state (not stale data) is what
        // shows in the gap.
        pulseDaily = []
        pulseWeekly = []
        pulsePhotos = []
        pulseOpen = true
        Task { await loadPulse(period: .daily) }
        Task { await loadPulse(period: .weekly) }
        Task { await loadPulsePhotos() }
    }
    func closePulseViewer() { pulseOpen = false; pulseOrganizerSheet = nil; pulsePhotoSheet = nil }
    func openPulseOrganizerSheet(_ item: PulseItem) { pulseOrganizerSheet = item }
    func closePulseOrganizerSheet() { pulseOrganizerSheet = nil }
    func openPulsePhotoSheet(_ item: PulsePhotoItem) { pulsePhotoSheet = item }
    func closePulsePhotoSheet() { pulsePhotoSheet = nil }

    /// Follow straight from the Pulse organizer sheet — same plain
    /// optimistic table write as toggleFollowOrganizer (TASK D), just
    /// patching the lighter PulseItem shape.
    func followPulseOrganizer(_ organizerID: String) async {
        guard let uid = userID else { return }
        pulseOrganizerSheet?.following = true
        do {
            _ = try await SupabaseService.client.from("follows")
                .insert(["user_id": uid.uuidString, "organizer_id": organizerID]).execute()
        } catch {
            print("followPulseOrganizer failed:", error)
            pulseOrganizerSheet?.following = false
        }
    }

    /// Real, server-enforced like toggle for a ranked photo (migration
    /// 083's toggle_photo_like RPC) — replaces the local-only heart button
    /// for this Pulse-photo context specifically (PhotoViewer's own is
    /// left untouched — it only ever operates on the bundled static demo
    /// gallery, structurally disconnected from real event_photos rows; see
    /// 17-ux-foundation-release.md's 2026-10-03 fix pass for the full
    /// trace). Optimistic, with rollback on failure, patching both the
    /// list row and the open popup (if it's the same photo).
    func togglePulsePhotoLike(_ photoID: String) async {
        guard isSignedIn else { return requireAuth(returnTo: .profile, backTo: .profile) }
        guard pulsePhotoBusy[photoID] != true else { return }
        let wasLiked = pulsePhotoLiked[photoID] == true
        let delta = wasLiked ? -1 : 1
        pulsePhotoLiked[photoID] = !wasLiked
        pulsePhotoBusy[photoID] = true
        patchPulsePhotoLikeCount(photoID, delta: delta)
        do {
            let liked: Bool = try await SupabaseService.client
                .rpc("toggle_photo_like", params: ["p_event_photo_id": photoID])
                .execute().value
            // Reconcile against the RPC's own authoritative boolean — same
            // "server always wins" reasoning as the web equivalent.
            pulsePhotoLiked[photoID] = liked
            pulsePhotoBusy[photoID] = false
        } catch {
            print("togglePulsePhotoLike failed:", error)
            pulsePhotoLiked[photoID] = wasLiked
            pulsePhotoBusy[photoID] = false
            patchPulsePhotoLikeCount(photoID, delta: -delta)
        }
    }

    private func patchPulsePhotoLikeCount(_ photoID: String, delta: Int) {
        if let idx = pulsePhotos.firstIndex(where: { $0.photoId == photoID }) {
            pulsePhotos[idx].likeCount = max(0, pulsePhotos[idx].likeCount + delta)
        }
        if pulsePhotoSheet?.photoId == photoID {
            pulsePhotoSheet?.likeCount = max(0, (pulsePhotoSheet?.likeCount ?? 0) + delta)
        }
    }

    /// Real share tracking for a ranked photo (migration 083's
    /// log_photo_share RPC) — logged ONLY once the native share sheet
    /// genuinely completes (`UIActivityViewController`'s own
    /// `completionWithItemsHandler` reporting `completed == true`), never
    /// merely from presenting the sheet. Called from PulseViewerView's own
    /// share button, which owns presenting the `UIActivityViewController`
    /// (needs a view controller to present from — kept out of AppState,
    /// same split `EventDetailView.share()` already uses).
    func logPulsePhotoShare(_ photoID: String) async {
        do {
            _ = try await SupabaseService.client
                .rpc("log_photo_share", params: ["p_event_photo_id": photoID, "p_channel": "native"])
                .execute()
            patchPulsePhotoShareCount(photoID, delta: 1)
        } catch {
            print("logPulsePhotoShare failed:", error)
        }
    }

    private func patchPulsePhotoShareCount(_ photoID: String, delta: Int) {
        if let idx = pulsePhotos.firstIndex(where: { $0.photoId == photoID }) {
            pulsePhotos[idx].shareCount = max(0, pulsePhotos[idx].shareCount + delta)
        }
        if pulsePhotoSheet?.photoId == photoID {
            pulsePhotoSheet?.shareCount = max(0, (pulsePhotoSheet?.shareCount ?? 0) + delta)
        }
    }
}

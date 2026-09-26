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

/// Migration 086 — `goc_pulse_ranked()` (080, unchanged ranking) now also
/// returns a transparent breakdown of the real score components, plus the
/// event's category/"bao gồm" fields. All new fields decode with a default
/// (never fabricated when absent) so this struct stays source-compatible
/// with any older cached response shape. `followCount` is the organizer's
/// TOTAL follower count (a documented proxy, not period-scoped — `follows`
/// has no `created_at` column yet) — must never be relabelled as
/// period-scoped in any UI reading it.
struct PulseItem: Decodable, Identifiable, Equatable {
    let eventId: String
    let eventName: String
    let photoPath: String?
    let organizerId: String
    let organizerName: String
    let organizerVerified: Bool
    let score: Double
    var category: String?
    var catLabel: String?
    var included: String?
    var bookingCount: Int = 0
    var checkinCount: Int = 0
    var followCount: Int = 0
    var saveCount: Int = 0
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
        case category
        case catLabel = "cat_label"
        case included
        case bookingCount = "booking_count"
        case checkinCount = "checkin_count"
        case followCount = "follow_count"
        case saveCount = "save_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(String.self, forKey: .eventId)
        eventName = try c.decode(String.self, forKey: .eventName)
        photoPath = try c.decodeIfPresent(String.self, forKey: .photoPath)
        organizerId = try c.decode(String.self, forKey: .organizerId)
        organizerName = try c.decode(String.self, forKey: .organizerName)
        organizerVerified = try c.decode(Bool.self, forKey: .organizerVerified)
        score = try c.decode(Double.self, forKey: .score)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        catLabel = try c.decodeIfPresent(String.self, forKey: .catLabel)
        included = try c.decodeIfPresent(String.self, forKey: .included)
        bookingCount = try c.decodeIfPresent(Int.self, forKey: .bookingCount) ?? 0
        checkinCount = try c.decodeIfPresent(Int.self, forKey: .checkinCount) ?? 0
        followCount = try c.decodeIfPresent(Int.self, forKey: .followCount) ?? 0
        saveCount = try c.decodeIfPresent(Int.self, forKey: .saveCount) ?? 0
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

/// `loadPulsePhotos()`'s own per-user like-state batch query row.
private struct LikedPhotoRow: Decodable {
    let eventPhotoId: String
    enum CodingKeys: String, CodingKey { case eventPhotoId = "event_photo_id" }
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
    /// 2026-09-26 photo-interactions redesign — the signed-in user's own
    /// like state for this batch, plus the ranking RPC's own counts, are
    /// now merged into the CANONICAL `photoEngagement` map (via
    /// `mergePhotoEngagement`, AppState+PhotoEngagement.swift) TOGETHER
    /// with `pulsePhotos` below, in the SAME `set`-equivalent — never a
    /// separate, later write — so there is no render in between where a
    /// liked photo would flash as "not liked." This is also what keeps this
    /// tab's counts/liked-state identical to whatever EventDetail/
    /// Organizer/PhotoViewerView already show for the same photo id.
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
            let items = result.items ?? []
            var liked: [String: Bool] = [:]
            if let uid = userID, !items.isEmpty {
                do {
                    let rows: [LikedPhotoRow] = try await SupabaseService.client
                        .from("photo_likes").select("event_photo_id")
                        .eq("user_id", value: uid)
                        .in("event_photo_id", values: items.map(\.photoId))
                        .execute().value
                    guard seq == pulsePhotosSeq else { return }
                    for row in rows { liked[row.eventPhotoId] = true }
                } catch {
                    print("loadPulsePhotos like-state failed:", error)
                }
            }
            let engagementRows = items.map {
                PhotoEngagementRow(photoId: $0.photoId, eventId: $0.eventId,
                                    likeCount: $0.likeCount, shareCount: $0.shareCount,
                                    likedByMe: liked[$0.photoId] == true)
            }
            pulsePhotos = items
            photoEngagement = mergePhotoEngagement(photoEngagement, rows: engagementRows)
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

    // 2026-09-26 photo-interactions redesign — the old Pulse-local
    // `togglePulsePhotoLike`/`logPulsePhotoShare`/patch-count helpers are
    // gone. A ranked photo's like toggle and share logging now go through
    // the SAME canonical `togglePhotoLike(_:)`/`logPhotoShare(_:)`
    // (AppState+PhotoEngagement.swift) every other surface uses — one
    // shared source of truth instead of a second, Pulse-only copy.
}

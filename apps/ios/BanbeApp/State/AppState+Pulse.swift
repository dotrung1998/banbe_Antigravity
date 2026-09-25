import Foundation

/// TASK E (2026-10-01 UX foundation pass) — Banbe Pulse: a permanent,
/// system-generated ring entry — deliberately NOT a real row in `stories`
/// (that table hard-expires everything in 24h). Mirrors src/state/
/// GocContext.jsx's own TASK E section function-for-function.
enum PulseTab: String { case daily, weekly }

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

    func openPulseViewer() {
        pulseTab = .daily
        // Never leave a previous session's rank sitting there indefinitely
        // (rule A5) — cleared before the fresh fetch, not just overwritten
        // once it lands, so the loading state (not stale data) is what
        // shows in the gap.
        pulseDaily = []
        pulseWeekly = []
        pulseOpen = true
        Task { await loadPulse(period: .daily) }
        Task { await loadPulse(period: .weekly) }
    }
    func closePulseViewer() { pulseOpen = false; pulseOrganizerSheet = nil }
    func openPulseOrganizerSheet(_ item: PulseItem) { pulseOrganizerSheet = item }
    func closePulseOrganizerSheet() { pulseOrganizerSheet = nil }

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
}

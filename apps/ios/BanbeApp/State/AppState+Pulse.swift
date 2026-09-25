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
        do {
            let result: PulseResult = try await SupabaseService.client
                .rpc("goc_pulse_ranked", params: ["p_period": period.rawValue])
                .execute().value
            guard result.success == true else { return }
            let items = result.items ?? []
            if period == .weekly { pulseWeekly = items } else { pulseDaily = items }
        } catch {
            print("loadPulse failed:", error, "period:", period.rawValue)
        }
    }

    func openPulseViewer() {
        pulseTab = .daily
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

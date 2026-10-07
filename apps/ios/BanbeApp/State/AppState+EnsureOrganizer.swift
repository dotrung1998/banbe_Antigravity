import Foundation
import Supabase

/// Pure decision/name logic for ensure_my_organizer (migration 163).
/// Root cause fixed: an `organizers` row used to be created only lazily by
/// create_event_draft, so an Organizer-Mode user with no event yet owned no
/// organizer and the Host card had nothing to show.
enum EnsureOrganizerLogic {
    static func defaultName(displayName: String?, isEN: Bool) -> String {
        let raw = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let phoneChars = CharacterSet(charactersIn: "0123456789+()-. \t")
        let phoneLike = !raw.isEmpty && raw.unicodeScalars.allSatisfy { phoneChars.contains($0) }
        if raw.isEmpty || raw.contains("@") || phoneLike {
            return isEN ? "My events" : "Sự kiện của tôi"
        }
        return String(raw.prefix(60)) + (isEN ? " Events" : " Sự kiện")
    }

    /// Call only when organizer mode is on, the owned-organizer lookup is a
    /// CONFIRMED empty result, and no ensure is running or already failed
    /// (a failure waits for an explicit Retry; no automatic loop).
    static func shouldEnsure(hasUser: Bool, organizerMode: Bool, idsStatus: String,
                             ownedCount: Int, ensureStatus: String) -> Bool {
        guard hasUser, organizerMode, idsStatus == "loaded", ownedCount == 0 else { return false }
        return ensureStatus != "loading" && ensureStatus != "error"
    }
}

private struct EnsureMyOrganizerResult: Decodable {
    let success: Bool
    let organizerId: String?
    let created: Bool?
    let name: String?
    let error: String?
}

extension AppState {
    /// Idempotent + single-flight (status guard). Refreshes myOrganizerID/IDs
    /// and the Host card immediately. Never touches roles or publishes.
    func ensureOrganizerIfNeeded(force: Bool = false) async {
        guard userID != nil else { return }
        if ensureOrganizerStatus == "loading" { return }
        if !force {
            guard EnsureOrganizerLogic.shouldEnsure(
                hasUser: true, organizerMode: organizerMode, idsStatus: myOrganizerIdsStatus,
                ownedCount: myOrganizerIDs.count, ensureStatus: ensureOrganizerStatus) else { return }
        } else if !organizerMode || !myOrganizerIDs.isEmpty { return }
        ensureOrganizerStatus = "loading"
        do {
            let r: EnsureMyOrganizerResult = try await SupabaseService.client
                .rpc("ensure_my_organizer").execute().value
            guard r.success, let id = r.organizerId else {
                ensureOrganizerStatus = "error"
                return
            }
            if !myOrganizerIDs.contains(id) { myOrganizerIDs.append(id) }
            if myOrganizerID == nil { myOrganizerID = id }
            if orgRegName.isEmpty, let n = r.name { orgRegName = n }
            ensureOrganizerStatus = "idle"
            await loadMyEvents()
        } catch {
            #if DEBUG
            print("[ensureOrganizer] failed:", error)
            #endif
            ensureOrganizerStatus = "error"
        }
    }

    func retryEnsureOrganizer() {
        guard ensureOrganizerStatus == "error" else { return }
        Task { await ensureOrganizerIfNeeded(force: true) }
    }
}

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
    /// `modeBusy`: organizerMode flips on optimistically before set_organizer_mode returns, so
    /// ensure_my_organizer would run while the server role is still `participant` and fail with
    /// ORGANIZER_MODE_REQUIRED (the old "retry" card). Wait for the mode change to settle.
    static func shouldEnsure(hasUser: Bool, organizerMode: Bool, idsStatus: String,
                             ownedCount: Int, ensureStatus: String, modeBusy: Bool = false) -> Bool {
        guard hasUser, organizerMode, !modeBusy, idsStatus == "loaded", ownedCount == 0 else { return false }
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
    /// `modeSettled`: pass true from the organizer-mode toggle itself right after the server confirmed
    /// the change (its busy flag is still set at that point).
    func ensureOrganizerIfNeeded(force: Bool = false, modeSettled: Bool = false) async {
        guard userID != nil else { return }
        if ensureOrganizerStatus == "loading" { return }
        // While the setup sheet is open the user has not agreed to create a host profile yet; only the
        // sheet's own Create button (force) may create it.
        if !force && hostSetupOpen { return }
        if !force {
            guard EnsureOrganizerLogic.shouldEnsure(
                hasUser: true, organizerMode: organizerMode, idsStatus: myOrganizerIdsStatus,
                ownedCount: myOrganizerIDs.count, ensureStatus: ensureOrganizerStatus,
                modeBusy: organizerModeBusy && !modeSettled) else { return }
        } else if !organizerMode || !myOrganizerIDs.isEmpty { return }
        // Organizer mode is on but the account owns no organizer: never create one silently. Ask for the
        // host profile through the setup sheet, whose Create button is the only thing that creates it
        // (`force`), regardless of whether this device remembers an earlier setup.
        if !force { hostSetupOpen = true; return }
        ensureOrganizerStatus = "loading"
        do {
            let r: EnsureMyOrganizerResult = try await SupabaseService.client
                .rpc("ensure_my_organizer").execute().value
            guard r.success, let id = r.organizerId else {
                ensureOrganizerErrorCode = r.error ?? "EMPTY_RESULT"
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
            ensureOrganizerErrorCode = (error as? PostgrestError)?.code ?? "RPC_ERROR"
            ensureOrganizerStatus = "error"
        }
    }

    func retryEnsureOrganizer() {
        guard ensureOrganizerStatus == "error" else { return }
        Task { await ensureOrganizerIfNeeded(force: true) }
    }
}

// MARK: - First-time host setup flag

extension AppState {
    private func hostSetupKey(_ uid: UUID) -> String { "banbe.hostSetup.v1:\(uid.uuidString)" }

    /// True once the user finished or skipped the setup sheet (per account, per device).
    var hostSetupResolved: Bool {
        guard let uid = userID else { return true }
        return UserDefaults.standard.string(forKey: hostSetupKey(uid)) != nil
    }

    /// X on the setup sheet: not becoming a host after all. Organizer mode goes back off and nothing is
    /// created; the sheet is not marked resolved, so switching organizer mode on again offers it again.
    func cancelHostSetup() {
        hostSetupOpen = false
        Task {
            // The toggle that opened the sheet may still be finishing; applyOrganizerMode ignores calls until it is.
            var waited = 0
            while organizerModeInFlight, waited < 30 { try? await Task.sleep(nanoseconds: 100_000_000); waited += 1 }
            await applyOrganizerMode(false)
        }
    }

    func finishHostSetup(_ how: String) {
        if let uid = userID { UserDefaults.standard.set(how, forKey: hostSetupKey(uid)) }
        hostSetupOpen = false
    }
}

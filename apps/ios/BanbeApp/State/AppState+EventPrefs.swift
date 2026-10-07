import Foundation
import Supabase

// Event preferences, onboarding markers, For You and reservation-criteria RPCs
// (migration 162, note 34). All reads/writes go through owner-scoped SECURITY
// DEFINER RPCs — the preferences table has no direct client access, and hosts
// never receive a guest's answers (only the per-event eligibility result).

private struct SuccessEnvelope: Decodable {
    let success: Bool?
    let error: String?
    let preferencesVersion: Int?
    enum CodingKeys: String, CodingKey { case success, error; case preferencesVersion = "preferences_version" }
}

extension AppState {

    // MARK: lifecycle

    func resetEventPrefsState() {
        eventPrefs = nil
        eventPrefsVersion = 0
        eventPrefsLoaded = false
        needsSettingsOnboarding = false
        needsPreferencesOnboarding = false
        eventOnboardingIsNewAccount = false
        filterForYou = false
    }

    private static func isFunctionMissing(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError {
            return pg.code == "PGRST202" || pg.code == "42883"
                || pg.message.localizedCaseInsensitiveContains("could not find the function")
        }
        return false
    }

    /// Reads this account's preferences + whether onboarding is still owed.
    /// A project without migration 162 simply owes nothing (no gate, no For You).
    func loadEventPreferences() async {
        guard userID != nil else { resetEventPrefsState(); return }
        do {
            let s: EventPrefsServerState = try await SupabaseService.client
                .rpc("get_my_event_preferences").execute().value
            guard s.success == true else { eventPrefsLoaded = true; return }
            eventPrefs = s.preferences
            eventPrefsVersion = s.preferencesVersion ?? 0
            needsSettingsOnboarding = s.needsSettingsStep == true
            needsPreferencesOnboarding = s.needsPreferencesStep == true
            eventOnboardingIsNewAccount = s.isNewAccount == true
            eventPrefsLoaded = true
        } catch {
            if Self.isFunctionMissing(error) {
                needsSettingsOnboarding = false
                needsPreferencesOnboarding = false
                eventPrefsLoaded = true
            } else {
                print("loadEventPreferences failed:", error)
                // Unknown failure: never trap the user in onboarding on a flaky read.
                needsSettingsOnboarding = false
                needsPreferencesOnboarding = false
            }
        }
    }

    /// Opens Event preferences. `returnTo` (e.g. `.event`) makes Back/Done land
    /// there instead of the Account group; nil = the normal Account entry.
    func openEventPreferences(returnTo: Screen? = nil) {
        eventPrefsReturnScreen = returnTo
        screen = .eventPreferences
    }

    // MARK: writes

    /// Account > Event preferences (and the onboarding step). Returns false on failure.
    @discardableResult
    func saveEventPreferences(_ prefs: EventPreferences) async -> Bool {
        let body = prefs.normalizedForSave()
        do {
            let r: SuccessEnvelope = try await SupabaseService.client
                .rpc("save_my_event_preferences", params: ["p_preferences": body]).execute().value
            guard r.success == true else { return false }
            eventPrefs = body
            eventPrefsVersion = r.preferencesVersion ?? (eventPrefsVersion + 1)
            return true
        } catch { print("saveEventPreferences failed:", error); return false }
    }

    /// Marks the settings-review step done. Never writes any setting itself.
    @discardableResult
    func completeSettingsOnboarding() async -> Bool {
        do {
            let r: SuccessEnvelope = try await SupabaseService.client
                .rpc("complete_settings_onboarding").execute().value
            if r.success == true { needsSettingsOnboarding = false; return true }
            return false
        } catch { print("completeSettingsOnboarding failed:", error); return false }
    }

    /// Finishes the five-question step. `nil` = skipped everything (marker only).
    @discardableResult
    func completePreferencesOnboarding(_ prefs: EventPreferences?) async -> Bool {
        let body = prefs?.normalizedForSave()
        do {
            let r: SuccessEnvelope = try await SupabaseService.client
                .rpc("complete_preferences_onboarding", params: ["p_preferences": body])
                .execute().value
            guard r.success == true else { return false }
            if let body { eventPrefs = body; eventPrefsVersion = r.preferencesVersion ?? (eventPrefsVersion + 1) }
            needsPreferencesOnboarding = false
            return true
        } catch { print("completePreferencesOnboarding failed:", error); return false }
    }

    // MARK: reservation criteria

    /// Host side: persists the event's criteria (owner-only on the server).
    @discardableResult
    func setReservationCriteria(eventID: String, _ criteria: ReservationCriteria) async -> Bool {
        do {
            _ = try await SupabaseService.client
                .rpc("set_event_reservation_criteria",
                     params: ["p_event_id": AnyJSON.string(eventID),
                              "p_criteria": try AnyJSON(criteria.normalizedForSave())])
                .execute()
            return true
        } catch {
            if Self.isFunctionMissing(error) { return criteria.normalizedForSave().isEveryone }
            print("setReservationCriteria failed:", error); return false
        }
    }

    /// Guest side: "can I reserve this?" for the caller only. nil = could not check
    /// (older server without migration 162 ⇒ treated by callers as eligible; the
    /// server still enforces in hold_seats either way).
    func checkReservationEligibility(eventKey: String) async -> ReservationEligibility? {
        do {
            let r: ReservationEligibility = try await SupabaseService.client
                .rpc("check_my_reservation_eligibility", params: ["p_event_id": eventKey])
                .execute().value
            return r.success == false ? nil : r
        } catch {
            if !Self.isFunctionMissing(error) { print("checkReservationEligibility failed:", error) }
            return nil
        }
    }

    /// Decodes the `CRITERIA_NOT_MET` error raised by hold_seats/claim_seats
    /// (its DETAIL carries the same JSON as `check_my_reservation_eligibility`).
    static func eligibility(fromBookingError error: Error) -> ReservationEligibility? {
        guard let pg = error as? PostgrestError,
              pg.message.contains("CRITERIA_NOT_MET") else { return nil }
        if let detail = pg.details, let data = detail.data(using: .utf8),
           let e = try? JSONDecoder().decode(ReservationEligibility.self, from: data) { return e }
        return ReservationEligibility(success: false, eligible: false, mode: "declared", interestRule: nil,
                                      goalRule: nil, missingInterests: [], missingGoals: [])
    }

    // MARK: For You

    /// Real, discoverable (public) events only — the demo catalogue is fixtures
    /// and is never recommended. Already RLS-filtered by `loadDiscoveryEvents`.
    var forYouCandidates: [ForYouCandidate] {
        discoveryEvents.map { raw in
            let e = withLive(raw)
            let loc = eventLocation(e)
            return ForYou.candidate(
                key: e.key, catKey: e.catKey, cat2Key: e.cat2Key, priceVnd: e.priceVnd, isFree: e.isFree,
                countryCode: loc.countryCode, stateProvince: loc.stateProvince, startsAt: e.startDate,
                isBookable: !e.inviteOnly && e.isOpen && !e.soldOut)
        }
    }

    /// Ordered matches for the current preferences, composed with the Home
    /// area filter. Empty when the user has no preferences / nothing matches.
    var forYouMatches: [ForYouMatch] {
        guard let prefs = eventPrefs, !prefs.isEmpty else { return [] }
        let inArea = Set(discoveryEvents.filter { matchesArea(withLive($0)) }.map(\.key))
        return ForYou.rank(forYouCandidates.filter { inArea.contains($0.key) }, prefs: prefs)
    }

    /// The gold star shows only when at least one matching event exists.
    var hasForYouMatches: Bool { !forYouMatches.isEmpty }

    // MARK: For You on Map

    /// Same ranker, same area rule as Home — fed with Map's loaded rows (public + live only,
    /// RLS-filtered by `loadMapEvents`). Map rows carry no invite flag because the query is
    /// `visibility = 'public'`; a sold-out/ended row is not bookable and never matches.
    var mapForYouMatches: [ForYouMatch] {
        guard let prefs = eventPrefs, !prefs.isEmpty else { return [] }
        let now = Date()
        let cands = mapEvents
            .filter { area == LocationHierarchy.allID || matchesArea($0) }
            .map { row in
                ForYou.candidate(
                    key: row.id, catKey: row.catKey, cat2Key: nil, priceVnd: row.priceVnd, isFree: row.priceVnd == 0,
                    countryCode: row.countryCode, stateProvince: row.stateProvince, startsAt: row.startsAt,
                    isBookable: row.status == "live" && (row.seatsRemaining ?? 1) > 0)
            }
        return ForYou.rank(cands, prefs: prefs, now: now)
    }
}

import Foundation
import Supabase

// Platform feature flags (migration 187, note 51; web: BanBeContext.jsx `loadFeatureFlags` / `setFeatureFlag`).
// Best-effort by design: an error or a missing function leaves the last-known flags untouched (see
// Lib/FeatureFlags.swift), so a flaky network never flips a feature on or off.

/// get_feature_flags() returns one jsonb object. Decode each value leniently so a non-boolean never fails the whole read.
private struct LenientBool: Decodable {
    let value: Bool?
    init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(Bool.self) }
}

extension AppState {
    /// Rewards & badges visibility (an admin can hide it everywhere). Missing flag = shown.
    var rewardsEnabled: Bool { FeatureFlags.isOn(featureFlags, "rewards") }
    /// Rewards v2 (migration 192): weekly streak, tiers, next badge, monthly goal. Off unless an admin turns it on.
    var rewardsV2Enabled: Bool { rewardsEnabled && FeatureFlags.isOn(featureFlags, "rewards_v2") }

    /// Real push notifications (migration 194). Off unless an admin turns them on; registration and the Q6 ask wait for it.
    var pushEnabled: Bool { FeatureFlags.isOn(featureFlags, "push_enabled") }

    /// Active onboarding version (notes 63/64): 1, 2 or 3. Version 1 unless an admin picks another.
    var onboardingVersion: Int { FeatureFlags.onboardingVersion(featureFlags) }
    /// Version 2 visuals (animated Welcome entrance + swipeable demo screens). Version 3 keeps them and adds the
    /// guided tour over the real app after the first sign-in.
    var onboardingV2Enabled: Bool { onboardingVersion >= 2 }

    /// Event type profiles (migration 203): the create form, Event Detail and Home adapt to the kind of event.
    /// Off unless an admin turns it on.
    var eventTypesEnabled: Bool { FeatureFlags.isOn(featureFlags, "event_type_profiles") }

    /// Called when the flags changed: turning Rewards off clears its numbers; turning it on loads them. Push turning
    /// on re-registers a device iOS already allows (never prompts).
    func featureFlagsDidChange(from old: [String: Bool]) {
        if !FeatureFlags.isOn(old, "push_enabled"), pushEnabled { resumePushRegistrationIfAllowed() }
        if FeatureFlags.isOn(old, "app_events") != appEventsEnabled { syncAppEventsSink() }
        if FeatureFlags.isOn(old, "live_activity") != liveActivityEnabled { syncLiveActivities(force: true) }
        let was = FeatureFlags.isOn(old, "rewards"), now = rewardsEnabled
        guard was != now else { return }
        if !now { resetRewardsState() }
        else if userID != nil { Task { await loadRewardsSummary() } }
    }

    /// Reads the flags on start, on returning to the foreground and after sign-in (at most every 20s unless forced).
    func loadFeatureFlags(force: Bool = false) async {
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures pin their own state
        #endif
        if !force, let last = featureFlagsFetchedAt, Date().timeIntervalSince(last) < 20 { return }
        featureFlagsFetchedAt = Date()
        do {
            let raw: [String: LenientBool] = try await SupabaseService.client.rpc("get_feature_flags").execute().value
            let next = FeatureFlags.normalize(raw.mapValues { $0.value })
            FeatureFlags.write(next)
            featureFlags = next
        } catch {
            #if DEBUG
            print("get_feature_flags unavailable (migration 187 not applied?):", error)
            #endif
        }
    }

    /// Admin only (the server enforces it). The local flag changes only after the server accepted the change.
    func setFeatureFlag(_ key: String, enabled: Bool) async -> (ok: Bool, error: String?) {
        guard featureFlagBusy.isEmpty else { return (false, "BUSY") }
        #if DEBUG
        if UITestFixture.isActive { featureFlags[key] = enabled; return (true, nil) } // fixtures never reach the server
        #endif
        featureFlagBusy = key
        defer { featureFlagBusy = "" }
        struct Reply: Decodable { var success: Bool?; var error: String? }
        struct Params: Encodable {
            let key: String, enabled: Bool
            enum CodingKeys: String, CodingKey { case key = "p_key", enabled = "p_enabled" }
        }
        do {
            let r: Reply = try await SupabaseService.client
                .rpc("admin_set_feature_flag", params: Params(key: key, enabled: enabled)).execute().value
            guard r.success == true else { return (false, r.error ?? "UNKNOWN") }
            var next = featureFlags
            next[key] = enabled
            FeatureFlags.write(next)
            featureFlags = next
            return (true, nil)
        } catch {
            return (false, RewardsLogic.isFunctionMissing(error) ? "NOT_DEPLOYED" : "NETWORK")
        }
    }

    /// Note 64, migration 202: one audited RPC sets onboarding_v2 + onboarding_v3 together, so exactly one onboarding
    /// version is active. The local flags change only after the server accepted it.
    func setOnboardingVersion(_ version: Int) async -> (ok: Bool, error: String?) {
        guard featureFlagBusy.isEmpty else { return (false, "BUSY") }
        #if DEBUG
        if UITestFixture.isActive {
            featureFlags["onboarding_v2"] = version == 2
            featureFlags["onboarding_v3"] = version == 3
            return (true, nil)
        }
        #endif
        featureFlagBusy = "onboarding_version"
        defer { featureFlagBusy = "" }
        struct Reply: Decodable { var success: Bool?; var error: String? }
        struct Params: Encodable {
            let version: Int
            enum CodingKeys: String, CodingKey { case version = "p_version" }
        }
        do {
            let r: Reply = try await SupabaseService.client
                .rpc("admin_set_onboarding_version", params: Params(version: version)).execute().value
            guard r.success == true else { return (false, r.error ?? "UNKNOWN") }
            var next = featureFlags
            next["onboarding_v2"] = version == 2
            next["onboarding_v3"] = version == 3
            FeatureFlags.write(next)
            featureFlags = next
            return (true, nil)
        } catch {
            return (false, RewardsLogic.isFunctionMissing(error) ? "NOT_DEPLOYED" : "NETWORK")
        }
    }
}

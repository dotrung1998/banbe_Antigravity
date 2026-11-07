import Foundation
import UIKit
import UserNotifications

// Step 3 of .claude/notes/07-notifications.md: everything that can be wired
// up WITHOUT a real APNs credential — permission request, device-token
// capture (AppDelegate.swift), and storing it against the signed-in
// account. Sending an actual push still needs a server-side piece this
// repo doesn't have yet; see this session's final report for exactly what
// credential unblocks it.
extension AppState {
    /// Called after sign-in (applySession) and whenever the `push_enabled` switch arrives ON. NEVER shows the system
    /// prompt: the prompt only follows the person's own tap in the pre-permission sheet (Q6, `PushAskSheet`). When
    /// iOS already allows notifications for banbe and the switch is on, it (re)registers so the server has a fresh
    /// token. Nothing happens while the switch is off, in an ENABLE_PUSH=NO build (PersonalTeamDebug), or signed out.
    func resumePushRegistrationIfAllowed() {
        #if ENABLE_PUSH
        guard userID != nil, pushEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        #endif
    }

    // MARK: Q6 contextual ask

    static func pushAskOfferedKey(_ uid: String) -> String { "banbe.pushAsk.offered.v1.\(uid)" }

    /// The first time a confirmed ticket is on screen: offer reminders, once per account per device, only while the
    /// switch is on and iOS has never asked. Shows banbe's own explanation sheet; the system prompt comes only from
    /// its Continue button.
    func offerPushAskIfAppropriate(hasConfirmedTicket: Bool) {
        #if ENABLE_PUSH
        guard let uid = userID?.uuidString.lowercased(), hasConfirmedTicket, !pushAskPresented else { return }
        let offered = UserDefaults.standard.bool(forKey: Self.pushAskOfferedKey(uid))
        let pushOn = pushEnabled  // read here on the main actor, not inside the Sendable settings callback
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ask = PushAsk.shouldOffer(pushEnabled: pushOn, hasConfirmedTicket: hasConfirmedTicket,
                                          alreadyOffered: offered, systemNotDetermined: settings.authorizationStatus == .notDetermined)
            guard ask else { return }
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: Self.pushAskOfferedKey(uid))
                self.pushAskPresented = true
            }
        }
        #endif
    }

    /// Continue in the sheet: the real system prompt, then registration if allowed.
    func acceptPushAsk() {
        pushAskPresented = false
        #if ENABLE_PUSH
        guard pushEnabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { print("Push authorization request failed:", error) }
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
        #endif
    }

    /// Not now: nothing is asked again automatically (the person can allow it later in iOS Settings).
    func declinePushAsk() { pushAskPresented = false }

    /// The last token this device registered (UserDefaults), so sign-out can unregister exactly that one.
    static let lastPushTokenKey = "banbe.push.lastToken.v1"

    /// Called by AppDelegate once UIKit hands back a real device token —
    /// unreachable when ENABLE_PUSH is off, since
    /// requestPushAuthorizationIfNeeded() above never calls
    /// registerForRemoteNotifications() in that build, but guarded here too
    /// rather than relying on that alone. `register_push_token()` upserts by
    /// token, so a reinstall/relaunch on the same device just refreshes
    /// `updated_at` rather than erroring or creating a duplicate row.
    /// Migration 194 also stores which APNs gateway the token belongs to
    /// (`PushEnvironment.current`: sandbox for a development-signed build,
    /// production for TestFlight/App Store) and the bundle id it was minted for.
    func registerPushToken(_ token: String) async {
        #if !ENABLE_PUSH
        return
        #else
        // The switch can be turned off after iOS already handed out a token: then nothing is stored.
        guard userID != nil, pushEnabled else { return }
        struct Params: Encodable {
            let token: String
            let platform: String
            let environment: String
            let appID: String?
            let timezone: String
            enum CodingKeys: String, CodingKey {
                case token = "p_token", platform = "p_platform", environment = "p_environment", appID = "p_app_id",
                     timezone = "p_timezone"
            }
        }
        do {
            _ = try await SupabaseService.client
                .rpc("register_push_token", params: Params(token: token, platform: "ios", environment: PushEnvironment.current,
                                                           appID: Bundle.main.bundleIdentifier,
                                                           timezone: TimeZone.current.identifier))
                .execute()
            UserDefaults.standard.set(token, forKey: Self.lastPushTokenKey)
        } catch {
            // A server without migration 194 only has register_push_token(p_token, p_platform).
            do {
                _ = try await SupabaseService.client
                    .rpc("register_push_token", params: ["p_token": token, "p_platform": "ios"])
                    .execute()
                UserDefaults.standard.set(token, forKey: Self.lastPushTokenKey)
            } catch {
                print("register_push_token failed:", error)
            }
        }
        #endif
    }

    /// Sign-out: stop this device receiving the leaving account's pushes. Must run BEFORE the session is cleared
    /// (`unregister_push_token` is scoped to auth.uid()). Best-effort: a failure (offline, a server without 194)
    /// never blocks signing out; the row then simply moves to the next account that registers this token.
    func unregisterPushTokenForSignOut() async {
        #if ENABLE_PUSH
        guard userID != nil, let token = UserDefaults.standard.string(forKey: Self.lastPushTokenKey) else { return }
        do {
            _ = try await SupabaseService.client
                .rpc("unregister_push_token", params: ["p_token": token])
                .execute()
        } catch {
            print("unregister_push_token failed:", error)
        }
        UserDefaults.standard.removeObject(forKey: Self.lastPushTokenKey)
        setAppBadge(0)
        #endif
    }

    /// Account deletion (Task 2, Account/Settings pass) — client-side
    /// cleanup step for "drop any push-token registration this device
    /// holds for this now-deleted account". The server-side row itself is
    /// already gone by the time this runs: `device_push_tokens.user_id`
    /// references `profiles(id)` (migration 049), which cascades from
    /// `auth.users` the same way every other per-user table does, so
    /// `admin.auth.admin.deleteUser()` (the delete-account endpoint's own
    /// final step) already removed it server-side. Locally only the
    /// remembered token (`lastPushTokenKey`) and the app badge are left.
    func forgetPushTokenLocally() {
        #if ENABLE_PUSH
        UserDefaults.standard.removeObject(forKey: Self.lastPushTokenKey)
        setAppBadge(0)
        UIApplication.shared.unregisterForRemoteNotifications()
        #endif
    }

    // MARK: Badge

    /// The app icon badge follows the unread notification count (called from `notifications`' didSet).
    /// ENABLE_PUSH builds only: without push there is nothing outside the app that could raise it.
    func syncAppBadge() {
        #if ENABLE_PUSH
        let count = userID == nil ? 0 : unreadNotifications
        guard count != appBadgeCount else { return }
        setAppBadge(count)
        #endif
    }

    func setAppBadge(_ count: Int) {
        #if ENABLE_PUSH
        appBadgeCount = count
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error { print("setBadgeCount failed:", error) }
        }
        #endif
    }

    // MARK: Push taps

    /// A push arrived while the app is open: the in-app toast shows it (willPresent returns no banner), so only
    /// make sure the list/toast poll picks it up now instead of on its next 5s tick.
    func pushArrivedInForeground() {
        guard userID != nil else { return }
        Task { await loadNotifications() }
    }

    /// The person tapped a push. Signed in: route it like a bell tap (marks it read, opens its screen). Cold launch
    /// or not signed in yet: keep it until `applySession` has loaded the account (`routePendingPushIfReady`).
    func handlePushTap(_ notification: AppNotification) {
        pendingPushNotification = notification
        routePendingPushIfReady()
    }

    func routePendingPushIfReady() {
        guard let pending = pendingPushNotification, let uid = userID, !policyGateActive else { return }
        pendingPushNotification = nil
        var n = pending
        n.recipientId = uid
        if let loaded = notifications.first(where: { $0.id == n.id }) { n = loaded }
        openNotification(n, source: "push")
    }
}

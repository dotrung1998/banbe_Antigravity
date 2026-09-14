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
    /// Asks once per install (UNUserNotificationCenter itself no-ops a
    /// second prompt if the person already answered) — called right after
    /// sign-in, alongside the rest of applySession()'s post-login setup.
    func requestPushAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                // Already decided (allowed or denied) in a previous
                // session — .registerForRemoteNotifications() below is
                // still safe to call either way; UIKit just won't
                // actually deliver anything if the person said no.
                if settings.authorizationStatus == .authorized {
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error { print("Push authorization request failed:", error) }
                guard granted else { return }
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    /// Called by AppDelegate once UIKit hands back a real device token.
    /// `register_push_token()` (migration 049) upserts by token, so a
    /// reinstall/relaunch on the same device just refreshes `updated_at`
    /// rather than erroring or creating a duplicate row.
    func registerPushToken(_ token: String) async {
        guard userID != nil else { return }
        do {
            _ = try await SupabaseService.client
                .rpc("register_push_token", params: ["p_token": token, "p_platform": "ios"])
                .execute()
        } catch {
            print("register_push_token failed:", error)
        }
    }
}

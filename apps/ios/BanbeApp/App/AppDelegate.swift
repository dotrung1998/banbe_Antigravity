import UIKit

/// Only exists to catch the two UIApplicationDelegate callbacks SwiftUI's
/// App protocol has no equivalent for: the real APNs device token (or the
/// failure to get one). Everything else about app launch still goes
/// through BanbeApp.swift/RootView as before.
///
/// Wiring this up, requesting permission, and storing the token is as far
/// as this goes without a real APNs credential — see
/// .claude/notes/07-notifications.md and this session's final report for
/// exactly what's still needed (an Auth Key from the Apple Developer
/// account) before a push can actually be sent to a token captured here.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by BanbeApp.swift once AppState exists, since this delegate is
    /// constructed before the SwiftUI environment is — there's no other way
    /// for it to hand the token off to app state.
    static var appState: AppState?

    // Unreachable in an ENABLE_PUSH=NO build (Config/Debug.xcconfig, the
    // default free/personal-team config): AppState+Push.swift's
    // requestPushAuthorizationIfNeeded() never calls
    // registerForRemoteNotifications() in that build, so UIKit has nothing
    // to invoke this with. registerPushToken() itself is guarded too (see
    // that file) rather than relying on this callback simply not firing.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { await AppDelegate.appState?.registerPushToken(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected and harmless in the Simulator (no APNs there at all) and
        // on any real device until a Push Notifications capability +
        // provisioning profile actually exist for this bundle id.
        print("Remote notification registration failed:", error)
    }
}

import SwiftUI

@main
struct BanbeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var appState = AppState()

    init() {
        // AppDelegate is instantiated by UIKit before any SwiftUI @StateObject
        // exists, so it can't reach `appState` any other way — set once here.
        AppDelegate.appState = appState
        // .claude/notes/18-ios-personal-team-signing.md — developer-only
        // signal (console, never a user-facing banner) that this build was
        // compiled under Config/PersonalTeamDebug.xcconfig, which omits
        // aps-environment and com.apple.developer.associated-domains
        // entirely. Nothing else reads this flag to change behavior beyond
        // what ENABLE_PUSH=NO and the missing entitlement already do on
        // their own — it's purely informational.
        #if PERSONAL_TEAM_BUILD
        print("Personal Team build: push and Universal Links are disabled.")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(appState)
                .onOpenURL { url in appState.handleDeepLink(url) }
                // TASK D (2026-10-01 UX foundation pass) — universal links
                // (https://banbe.app/...) arrive as an NSUserActivity, not
                // through onOpenURL (that's only ever the custom `banbe://`
                // scheme, e.g. the OAuth callback). Separate handler,
                // separate mechanism.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    appState.handleUniversalLink(url)
                }
        }
    }
}

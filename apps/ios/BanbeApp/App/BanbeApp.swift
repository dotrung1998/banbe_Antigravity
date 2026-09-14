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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(appState)
                .onOpenURL { url in appState.handleDeepLink(url) }
        }
    }
}

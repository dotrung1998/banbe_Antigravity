import SwiftUI

/// Top-level screen switch — the iOS equivalent of the SCREENS map in
/// App.jsx, just reduced to "signed in or not" for this initial scaffold.
struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        Group {
            if auth.isSignedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .onOpenURL { url in
            Task { await auth.handleAuthCallback(url: url) }
        }
    }
}

#Preview {
    RootView().environmentObject(AuthViewModel())
}

import SwiftUI

/// Top-level screen switch — the iOS equivalent of the SCREENS map in
/// App.jsx, just reduced to "signed in or not" for this initial scaffold.
struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        // No onOpenURL here — sign-in is code-entry only (see
        // AuthViewModel.sendEmailCode/verifyEmailCode), so there's no
        // emailed link to catch a redirect from.
        Group {
            if auth.isSignedIn {
                HomeView()
                    // Sits on top of an already-restored session — see
                    // AuthViewModel.isLocked and FaceIDLockView.
                    .overlay {
                        if auth.isLocked {
                            FaceIDLockView()
                        }
                    }
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    RootView().environmentObject(AuthViewModel())
}

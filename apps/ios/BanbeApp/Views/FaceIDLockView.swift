import SwiftUI

/// Covers the app whenever AuthViewModel.isLocked is true — a restored
/// session exists (Supabase already did that on its own) but Face ID
/// app-lock is turned on and hasn't cleared for this launch yet.
struct FaceIDLockView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var errorMessage: String?
    @State private var isAuthenticating = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: BanbeTheme.LoadingVisual.reservationGap) {
                // A3 (Pulse/loading UX pass, 2026-09-27) — the shared
                // Banbe loading GIF as a branded "waiting" visual, shown
                // WHILE `isAuthenticating` (i.e. the real system Face ID
                // prompt from BiometricAuthService.authenticate is up or
                // about to appear) — the system prompt is its own separate
                // overlay LAContext presents on top of the app, so this
                // never covers or replaces it; at rest (not authenticating
                // yet) this still shows the plain Face ID glyph, unchanged.
                if isAuthenticating {
                    // Lifted a little: the GIF's rotating bounds used to overlap the logo below.
                    BanbeLoadingVisual(size: 44).offset(y: -14)
                } else {
                    Image(systemName: "faceid")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    // The wordmark — same asset the Home screen uses —
                    // standing in for the word "banbe" itself.
                    BanbeLogo(kind: .wordmark, height: 50)
                    Text("is locked")
                        .font(.headline)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Button {
                    Task { await unlock() }
                } label: {
                    if isAuthenticating {
                        ProgressView()
                    } else {
                        Label("Unlock with Face ID", systemImage: "faceid")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }
        }
        .task { await unlock() }
    }

    private func unlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let unlocked = await BiometricAuthService.authenticate(reason: "Unlock banbe")
        if unlocked {
            errorMessage = nil
            auth.isLocked = false
        } else {
            errorMessage = "Face ID didn't succeed. Try again."
        }
    }
}

#Preview {
    FaceIDLockView().environmentObject(AuthViewModel())
}

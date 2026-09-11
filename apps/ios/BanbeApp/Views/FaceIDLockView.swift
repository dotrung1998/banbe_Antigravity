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
            VStack(spacing: 16) {
                Image(systemName: "faceid")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("banbe is locked")
                    .font(.headline)
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

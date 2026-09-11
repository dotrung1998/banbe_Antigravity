import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    private let biometricsAvailable = BiometricAuthService.canAuthenticate()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Unlock with Face ID", isOn: $auth.faceIDEnabled)
                        .disabled(!biometricsAvailable)
                    if !biometricsAvailable {
                        Text("Face ID isn't available on this device, or isn't set up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("When on, banbe asks for Face ID each time you return to the app — on top of the sign-in you already have, not instead of it.")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView().environmentObject(AuthViewModel())
}

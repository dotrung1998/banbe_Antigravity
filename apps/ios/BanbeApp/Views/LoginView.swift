import SwiftUI

/// Matches src/screens/Login.jsx's email-link path (the Zalo/Facebook/
/// Instagram/phone-OTP buttons there are left as future work — see README).
struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("banbe")
                    .font(.system(size: 28, weight: .semibold))
                Text("One account for everything. To host events, switch on organizer mode from your Account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("ban@email.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await auth.sendMagicLink(to: email) }
                } label: {
                    if auth.isSendingLink {
                        ProgressView()
                    } else {
                        Text("Send sign-in link")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || auth.isSendingLink)

                if auth.linkSent {
                    Text("Sign-in link sent. Open the email on this device to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(24)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    LoginView().environmentObject(AuthViewModel())
}

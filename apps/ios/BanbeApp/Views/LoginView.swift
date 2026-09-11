import SwiftUI

/// Matches src/screens/Login.jsx's email-code path — request a 6-digit
/// code, enter it to sign in. There is no "sign in via link" option: that
/// used to be requested with a `banbe://login-callback` redirect that was
/// never actually registered as a URL scheme anywhere in the app, so
/// tapping it in the email did nothing. See AuthViewModel.sendEmailCode.
/// (The Zalo/Facebook/Instagram/phone-OTP buttons on the web screen, and
/// password login/signup, are left as future work — see README.)
struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var email: String = ""
    @State private var code: String = ""

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
                    .disabled(auth.codeSent)
                    .textFieldStyle(.roundedBorder)

                if auth.codeSent {
                    TextField("6-digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task {
                        if auth.codeSent {
                            await auth.verifyEmailCode(email: email, code: code)
                        } else {
                            await auth.sendEmailCode(to: email)
                        }
                    }
                } label: {
                    if auth.isSendingCode {
                        ProgressView()
                    } else {
                        Text(auth.codeSent ? "Verify" : "Send sign-in code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isSendingCode || (auth.codeSent ? code.isEmpty : email.isEmpty))

                if auth.codeSent {
                    Text("A code was sent to your email. Enter it above to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Use a different email") {
                        auth.codeSent = false
                        code = ""
                    }
                    .font(.footnote)
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

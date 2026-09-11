import SwiftUI

/// Matches src/screens/Login.jsx's email-code path — request a 6-digit
/// code, enter it to sign in or finish signing up. There is no "sign in
/// via link" option: that used to be requested with a
/// `banbe://login-callback` redirect that was never actually registered
/// as a URL scheme anywhere in the app, so tapping it in the email did
/// nothing. See AuthViewModel.sendEmailCode.
/// (The Zalo/Facebook/Instagram/phone-OTP buttons on the web screen, and
/// password login/signup, are left as future work — see README.)
struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @State private var mode: AuthMode = .login
    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var code: String = ""

    private var canSubmitRequest: Bool {
        !email.isEmpty && (mode == .login || !displayName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("banbe")
                    .font(.system(size: 28, weight: .semibold))
                Text("One account for everything. To host events, switch on organizer mode from your Account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !auth.codeSent {
                    Picker("Mode", selection: $mode) {
                        Text("Log in").tag(AuthMode.login)
                        Text("Sign up").tag(AuthMode.signup)
                    }
                    .pickerStyle(.segmented)

                    if mode == .signup {
                        TextField("Your display name", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("ban@email.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("6-digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task {
                        if auth.codeSent {
                            await auth.verifyEmailCode(email: email, code: code, mode: mode)
                        } else {
                            await auth.sendEmailCode(to: email, mode: mode, displayName: displayName)
                        }
                    }
                } label: {
                    if auth.isSendingCode {
                        ProgressView()
                    } else {
                        Text(auth.codeSent ? "Verify" : (mode == .signup ? "Send sign-up code" : "Send sign-in code"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(auth.isSendingCode || (auth.codeSent ? code.isEmpty : !canSubmitRequest))

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

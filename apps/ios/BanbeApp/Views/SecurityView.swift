import SwiftUI

/// Account security — the Face ID app-lock, and this account's password.
/// iOS-only: the web app has no equivalent screen (Face ID gates a device
/// that's already signed in, and the web sets passwords during its own
/// login flow, which iOS's code-only sign-in doesn't have).
struct SecurityView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordBusy = false
    @State private var passwordError = ""
    @State private var passwordSaved = false
    @State private var resetBusy = false
    @State private var resetSent = false
    @State private var faceIDError = ""

    private var biometryName: String {
        BiometricAuthService.biometryType() == .touchID ? "Touch ID" : "Face ID"
    }

    private var canSubmitPassword: Bool {
        !passwordBusy && password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }

                Text(app.T("Bảo mật", "Security"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 16)
                Text(app.T("Khoá ứng dụng và mật khẩu tài khoản của bạn.",
                           "Your app lock and account password."))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .padding(.top, 10)

                if BiometricAuthService.canAuthenticate() {
                    faceIDSection
                }

                if auth.isSignedIn {
                    passwordSection
                } else {
                    Text(app.T("Đăng nhập để đặt mật khẩu cho tài khoản.",
                               "Sign in to set a password for your account."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.top, 28)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 42)
        }
    }

    // MARK: - Face ID

    private var faceIDSection: some View {
        section(app.T("Khoá ứng dụng", "App lock")) {
            Button {
                let turningOn = !auth.faceIDEnabled
                Task {
                    faceIDError = ""
                    let ok = await auth.setFaceIDEnabled(
                        turningOn,
                        reason: app.T("Xác nhận để bật khoá \(biometryName) cho banbe.",
                                      "Confirm to turn on \(biometryName) for banbe.")
                    )
                    if turningOn && !ok {
                        faceIDError = app.T(
                            "Chưa bật được. Hãy cho phép \(biometryName) cho banbe trong Cài đặt rồi thử lại.",
                            "Couldn't turn it on. Allow \(biometryName) for banbe in Settings, then try again."
                        )
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.T("Mở khoá bằng \(biometryName)", "Unlock with \(biometryName)"))
                            .font(BanbeTheme.display(17))
                        Text(app.T("Hỏi \(biometryName) mỗi lần bạn mở lại ứng dụng.",
                                   "Ask for \(biometryName) each time you return to the app."))
                            .font(.system(size: 11.5))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    toggleSwitch(on: auth.faceIDEnabled)
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 18).padding(.vertical, 17)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(auth.faceIDEnabled ? app.palette.ink : app.palette.rule,
                                lineWidth: auth.faceIDEnabled ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("security.faceID")

            if !faceIDError.isEmpty {
                Text(faceIDError)
                    .font(.system(size: 12))
                    .foregroundStyle(BanbeTheme.alert)
            }
        }
    }

    private func toggleSwitch(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? app.palette.ink : app.palette.ink.opacity(0.18))
                .frame(width: 44, height: 26)
            Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
        }
        .animation(.easeInOut(duration: 0.15), value: on)
    }

    // MARK: - Password

    private var passwordSection: some View {
        section(app.T("Mật khẩu", "Password")) {
            // Deliberately one form for both cases the section has to serve:
            // an account that has only ever used emailed sign-in codes is
            // setting its first password, and one that already has a
            // password is replacing it. Supabase treats both as the same
            // update on the signed-in user, and nothing the client can read
            // reliably says which of the two an account is — so branching
            // here would mean guessing at the label and getting it wrong
            // half the time.
            Text(app.T(
                "Đặt mật khẩu để đăng nhập bằng email và mật khẩu, thay vì chờ mã gửi qua email mỗi lần.",
                "Set a password so you can sign in with your email and password instead of waiting for a code every time."
            ))
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(app.palette.ink.opacity(0.75))

            BanbeField(label: nil, placeholder: app.T("Mật khẩu mới", "New password"),
                       text: $password, secure: true)
                .accessibilityIdentifier("security.password")
            BanbeField(label: nil, placeholder: app.T("Nhập lại mật khẩu", "Re-enter password"),
                       text: $confirmPassword, secure: true)
                .accessibilityIdentifier("security.passwordConfirm")

            if !passwordError.isEmpty {
                Text(passwordError)
                    .font(.system(size: 12))
                    .foregroundStyle(BanbeTheme.alert)
            } else if passwordSaved {
                Text(app.T("Đã lưu mật khẩu mới.", "New password saved."))
                    .font(.system(size: 12))
            } else if !password.isEmpty && password.count < 8 {
                Text(app.T("Mật khẩu cần ít nhất 8 ký tự.", "Passwords need at least 8 characters."))
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
            }

            InkButton(title: passwordBusy ? app.T("Đang lưu…", "Saving…") : app.T("Lưu mật khẩu", "Save password"),
                      enabled: canSubmitPassword) {
                Task { await savePassword() }
            }

            forgotPasswordLink
        }
    }

    private var forgotPasswordLink: some View {
        VStack(alignment: .leading, spacing: 8) {
            if resetSent {
                // Same message whether or not that address has an account —
                // the endpoint won't say, on purpose.
                Text(app.T(
                    "Đã gửi email đặt lại mật khẩu. Mở link trong email để chọn mật khẩu mới, rồi quay lại đây.",
                    "Password reset email sent. Open the link in it to choose a new password, then come back here."
                ))
                .font(.system(size: 12))
                .lineSpacing(3)
            } else {
                Button {
                    Task { await sendReset() }
                } label: {
                    Text(resetBusy
                         ? app.T("Đang gửi…", "Sending…")
                         : app.T("Quên mật khẩu hiện tại?", "Forgotten your current password?"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .underline()
                        .foregroundStyle(app.palette.ink)
                }
                .buttonStyle(.plain)
                .disabled(resetBusy || app.userEmail == nil)
                .accessibilityIdentifier("security.forgotPassword")

                Text(app.T(
                    "Chúng tôi sẽ gửi link đặt lại mật khẩu tới email của bạn.",
                    "We'll email you a link to reset it."
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(app.palette.ink.opacity(0.65))
            }
        }
        .padding(.top, 6)
    }

    private func savePassword() async {
        passwordError = ""
        passwordSaved = false
        guard password.count >= 8 else {
            passwordError = app.T("Mật khẩu cần ít nhất 8 ký tự.", "Passwords need at least 8 characters.")
            return
        }
        guard password == confirmPassword else {
            passwordError = app.T("Hai mật khẩu chưa khớp nhau.", "Those two passwords don't match.")
            return
        }
        passwordBusy = true
        defer { passwordBusy = false }
        do {
            try await auth.updatePassword(password)
            password = ""
            confirmPassword = ""
            passwordSaved = true
        } catch {
            passwordError = app.T("Không lưu được mật khẩu lúc này. Vui lòng thử lại.",
                                  "We couldn't save that password right now. Please try again.")
        }
    }

    private func sendReset() async {
        guard let email = app.userEmail else { return }
        resetBusy = true
        defer { resetBusy = false }
        // Failures are shown as sent too — the endpoint already refuses to
        // reveal whether an address has an account, and a visible error
        // here would leak the same thing by omission.
        try? await auth.sendPasswordReset(to: email)
        resetSent = true
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            content()
        }
        .padding(.top, 28)
    }
}

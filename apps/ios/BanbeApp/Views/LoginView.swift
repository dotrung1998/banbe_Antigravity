import SwiftUI

/// Port of src/screens/Login.jsx — a Log in/Sign up toggle, then either an
/// emailed 6-digit code or an email + password, the same two methods the
/// web app offers. There is no "sign in via link": that used to be
/// requested with a `banbe://login-callback` redirect no URL scheme was
/// ever registered for. The social buttons are still web-only.
struct LoginView: View {
    /// Mirrors the web's `authMethod` — which of the two ways in is showing.
    private enum Method { case code, password }

    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @State private var mode: AuthMode = .login
    @State private var method: Method = .code
    @State private var email = ""
    @State private var displayName = ""
    @State private var code = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var resetRequested = false
    @State private var localError = ""

    /// The same pattern every /api/auth/* endpoint enforces, checked
    /// against the trimmed value those endpoints actually receive — so the
    /// button never offers to send something the server will bounce.
    private var emailFormatOk: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }

    /// An empty field isn't an error yet — it's just unfinished — so it
    /// hides the button without complaining. Something typed that isn't an
    /// address does say so.
    private var showEmailFormatError: Bool {
        !auth.codeSent && !email.trimmingCharacters(in: .whitespaces).isEmpty && !emailFormatOk
    }

    /// Once a code has been sent the address is already settled and the
    /// button verifies the code instead, so the email check doesn't apply.
    private var showSubmit: Bool { auth.codeSent || emailFormatOk }

    private var canRequest: Bool {
        guard emailFormatOk else { return false }
        if mode == .signup && displayName.isEmpty { return false }
        if method == .password {
            // Signing up needs a password worth keeping and a matching
            // confirmation; logging in just needs something typed.
            return mode == .login ? !password.isEmpty
                                  : (password.count >= 8 && password == passwordConfirm)
        }
        return true
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = app.authBackScreen }

                HStack(spacing: 16) {
                    ForEach([AuthMode.login, AuthMode.signup], id: \.self) { option in
                        Button {
                            mode = option
                            resetFormState()
                        } label: {
                            VStack(spacing: 6) {
                                Text(option == .login ? app.T("Đăng nhập", "Log in") : app.T("Đăng ký", "Sign up"))
                                    .font(.system(size: 11.5, weight: mode == option ? .semibold : .regular))
                                Rectangle()
                                    .fill(mode == option ? app.palette.ink : .clear)
                                    .frame(height: 2)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 24)
                .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }

                Text(mode == .signup
                     ? app.T("Tạo tài khoản banbe", "Create your banbe account")
                     : app.T("Chào mừng trở lại", "Welcome back"))
                    .font(BanbeTheme.display(25))
                    .padding(.top, 16)

                Text(app.T(
                    "Một tài khoản cho tất cả. Muốn tổ chức sự kiện, bạn chỉ cần bật chế độ tổ chức trong Tài khoản.",
                    "One account for everything. To host events, just switch on organizer mode from your Account."
                ))
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .padding(.top, 12)

                if auth.codeSent {
                    BanbeField(label: nil, placeholder: app.T("Mã 6 số", "6-digit code"),
                               text: $code, keyboard: .numberPad)
                        .padding(.top, 22)
                } else {
                    methodTabs
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        if mode == .signup {
                            BanbeField(label: nil, placeholder: app.T("Tên hiển thị của bạn", "Your display name"),
                                       text: $displayName)
                        }
                        BanbeField(label: nil, placeholder: "ban@email.com", text: $email, keyboard: .emailAddress)
                            .accessibilityIdentifier("login.email")
                        if showEmailFormatError {
                            Text(app.T("Email chưa đúng định dạng — ví dụ: ban@email.com",
                                       "That doesn't look like an email address — e.g. ban@email.com"))
                                .font(.system(size: 12))
                                .foregroundStyle(BanbeTheme.alert)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("login.emailError")
                        }
                        if method == .password {
                            BanbeField(label: nil, placeholder: app.T("Mật khẩu", "Password"),
                                       text: $password, secure: true)
                                .accessibilityIdentifier("login.password")
                            if mode == .signup {
                                BanbeField(label: nil, placeholder: app.T("Nhập lại mật khẩu", "Re-enter password"),
                                           text: $passwordConfirm, secure: true)
                                    .accessibilityIdentifier("login.passwordConfirm")
                            }
                        }
                    }
                    .padding(.top, 14)

                    if method == .password && mode == .login {
                        Button(app.T("Quên mật khẩu?", "Forgot password?")) {
                            Task { await sendReset() }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 8)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("login.forgotPassword")
                    }
                }

                if showSubmit {
                    InkButton(title: submitLabel, enabled: !auth.isSendingCode && (auth.codeSent ? !code.isEmpty : canRequest)) {
                        Task { await submit() }
                    }
                    .padding(.top, 14)
                    .accessibilityIdentifier("login.submit")
                }

                if resetRequested {
                    // Same message whether or not that address has an
                    // account — the endpoint won't say, on purpose.
                    Text(app.T("Nếu email đó có tài khoản, chúng tôi đã gửi link đặt lại mật khẩu.",
                               "If that email has an account, we've sent it a reset link."))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                if auth.codeSent {
                    Text(app.T("Đã gửi mã tới email của bạn. Nhập mã để tiếp tục.",
                               "A code was sent to your email. Enter it to continue."))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                    Button(app.T("Dùng email khác", "Use a different email")) {
                        resetFormState()
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .buttonStyle(.plain)
                }

                if let error = localError.isEmpty ? auth.errorMessage : localError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private var methodTabs: some View {
        HStack(spacing: 0) {
            methodTab(.code, label: app.T("Mã qua email", "Email code"))
            methodTab(.password, label: app.T("Mật khẩu", "Password"))
        }
        .padding(3)
        .background(app.palette.field, in: Capsule())
    }

    private func methodTab(_ option: Method, label: String) -> some View {
        Button {
            method = option
            resetFormState()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: method == option ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(method == option ? app.palette.ink.opacity(0.1) : .clear, in: Capsule())
                .foregroundStyle(app.palette.ink)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(option == .code ? "login.method.code" : "login.method.password")
    }

    private func submit() async {
        localError = ""
        resetRequested = false

        // The emailed code finishes every flow that has one, including a
        // password sign-up — the account exists by then but is unconfirmed.
        if auth.codeSent {
            await auth.verifyEmailCode(email: email, code: code, mode: mode)
            return
        }

        switch (method, mode) {
        case (.code, _):
            await auth.sendEmailCode(to: email, mode: mode, displayName: displayName)
        case (.password, .login):
            await auth.signInWithPassword(email: email, password: password)
        case (.password, .signup):
            guard password.count >= 8 else {
                localError = app.T("Mật khẩu cần ít nhất 8 ký tự.", "Passwords need at least 8 characters.")
                return
            }
            guard password == passwordConfirm else {
                localError = app.T("Mật khẩu xác nhận không khớp.", "Passwords do not match.")
                return
            }
            await auth.signUpWithPassword(email: email, password: password,
                                          displayName: displayName, locale: app.lang)
        }
    }

    private func sendReset() async {
        localError = ""
        guard emailFormatOk else {
            localError = app.T("Nhập email của bạn trước.", "Enter your email first.")
            return
        }
        // Shown as sent either way: the endpoint already refuses to reveal
        // whether an address has an account, and surfacing a failure here
        // would leak the same thing by omission.
        try? await auth.sendPasswordReset(to: email)
        resetRequested = true
    }

    private func resetFormState() {
        auth.codeSent = false
        auth.errorMessage = nil
        localError = ""
        resetRequested = false
        code = ""
        password = ""
        passwordConfirm = ""
    }

    private var submitLabel: String {
        if auth.isSendingCode { return app.T("Đang gửi…", "Sending…") }
        if auth.codeSent { return app.T("Xác nhận", "Verify") }
        if method == .password {
            return mode == .signup ? app.T("Tạo tài khoản", "Create account")
                                   : app.T("Đăng nhập", "Log in")
        }
        return mode == .signup ? app.T("Gửi mã đăng ký", "Send sign-up code")
                               : app.T("Gửi mã đăng nhập", "Send sign-in code")
    }
}

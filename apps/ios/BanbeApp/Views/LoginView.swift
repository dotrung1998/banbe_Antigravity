import SwiftUI

/// Port of src/screens/Login.jsx's email-code path — a Log in/Sign up
/// toggle, then a 6-digit code by email (requested through the same
/// Gmail-backed API the web app uses; see AuthAPIService). There is no
/// "sign in via link": that used to be requested with a
/// `banbe://login-callback` redirect no URL scheme was ever registered for.
/// Password login/signup and the social buttons are still web-only.
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var displayName = ""
    @State private var code = ""

    private var canRequest: Bool {
        !email.isEmpty && (mode == .login || !displayName.isEmpty)
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.screen = app.authBackScreen }

                HStack(spacing: 16) {
                    ForEach([AuthMode.login, AuthMode.signup], id: \.self) { option in
                        Button {
                            mode = option
                            auth.codeSent = false
                            auth.errorMessage = nil
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
                    VStack(spacing: 12) {
                        if mode == .signup {
                            BanbeField(label: nil, placeholder: app.T("Tên hiển thị của bạn", "Your display name"),
                                       text: $displayName)
                        }
                        BanbeField(label: nil, placeholder: "ban@email.com", text: $email, keyboard: .emailAddress)
                    }
                    .padding(.top, 22)
                }

                InkButton(title: submitLabel, enabled: !auth.isSendingCode && (auth.codeSent ? !code.isEmpty : canRequest)) {
                    Task {
                        if auth.codeSent {
                            await auth.verifyEmailCode(email: email, code: code, mode: mode)
                        } else {
                            await auth.sendEmailCode(to: email, mode: mode, displayName: displayName)
                        }
                    }
                }
                .padding(.top, 14)

                if auth.codeSent {
                    Text(app.T("Đã gửi mã tới email của bạn. Nhập mã để tiếp tục.",
                               "A code was sent to your email. Enter it to continue."))
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                    Button(app.T("Dùng email khác", "Use a different email")) {
                        auth.codeSent = false
                        code = ""
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .buttonStyle(.plain)
                }

                if let error = auth.errorMessage {
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

    private var submitLabel: String {
        if auth.isSendingCode { return app.T("Đang gửi…", "Sending…") }
        if auth.codeSent { return app.T("Xác nhận", "Verify") }
        return mode == .signup ? app.T("Gửi mã đăng ký", "Send sign-up code")
                               : app.T("Gửi mã đăng nhập", "Send sign-in code")
    }
}

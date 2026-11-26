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
    /// Proof it is the owner before the change: the current password, or the emailed 6-digit code.
    @State private var currentPassword = ""
    @State private var proofMode: PasswordChange.ProofMode = .password
    @State private var reauthCode = ""
    @State private var codeSent = false
    @State private var passwordBusy = false
    @State private var passwordError = ""
    /// nil = nothing saved yet; true = saved and other devices signed out; false = saved, sign-out of others failed.
    @State private var passwordSaved: Bool?
    @State private var faceIDError = ""
    @State private var promoConfirmOpen = false

    private var biometryName: String {
        BiometricAuthService.biometryType() == .touchID ? "Touch ID" : "Face ID"
    }

    private var passwordBlocker: PasswordChange.Blocker? {
        PasswordChange.blocker(mode: proofMode, current: currentPassword, code: reauthCode,
                               password: password, confirm: confirmPassword)
    }

    private var canSubmitPassword: Bool { !passwordBusy && passwordBlocker == nil }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-section-of-a-group back-navigation fix (2026-09-29,
                // second pass) — was hardcoded to `.profile`, skipping the
                // "Tùy chỉnh"/"Preferences" group page this is actually
                // opened from (AccountGroupView). `goBack()` already routes
                // `.security` to `.accountGroup` correctly.
                BackLink(label: app.backLabel(for: app.backTargetScreen)) { app.goBack() }
                    .accessibilityIdentifier("security.back")

                Text(app.T("Bảo mật", "Security"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 16)
                Text(app.T("Khoá ứng dụng và mật khẩu tài khoản của bạn.",
                           "Your app lock and account password."))
                    .font(.app(size: 13.5))
                    .lineSpacing(3)
                    .padding(.top, 10)

                if BiometricAuthService.canAuthenticate() {
                    faceIDSection
                }

                if auth.isSignedIn {
                    passwordSection
                    section(app.T("Số điện thoại", "Phone number")) { PhoneVerificationSection() }
                    promoConsentSection
                } else {
                    Text(app.T("Đăng nhập để đặt mật khẩu cho tài khoản.",
                               "Sign in to set a password for your account."))
                        .font(.app(size: 12.5))
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
                            .font(.app(size: 11.5))
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
                    .font(.app(size: 12))
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

    // MARK: - Host promotional messages

    /// Consent is its own switch, separate from signing in, OFF unless the user
    /// turns it on here. Turning it on asks for an explicit confirmation;
    /// turning it off applies immediately.
    private var promoConsentSection: some View {
        let on = app.hostPromoConsent ?? false
        return section(app.T("Tin nhắn quảng bá từ host", "Host promotional messages")) {
            Button {
                if on {
                    Task { await app.setHostPromoConsent(false) }
                } else {
                    promoConfirmOpen = true
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.T("Cho phép host nhắn tin quảng bá", "Allow hosts to text me promotions"))
                            .font(BanbeTheme.display(17))
                        Text(app.T("Mặc định tắt. Chỉ các host mà bạn đã đặt chỗ, theo dõi hoặc lưu sự kiện mới được soạn tin quảng bá ngắn cho bạn qua SMS, và chỉ khi bạn bật mục này.",
                                   "Off by default. Only hosts you've booked with, follow or saved an event from can compose a short promo text to you, and only while this is on."))
                            .font(.app(size: 11.5))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    toggleSwitch(on: on)
                }
                .padding(.horizontal, 18).padding(.vertical, 15)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.hostPromoConsentBusy || app.hostPromoConsent == nil)
            .accessibilityIdentifier("security.hostPromoConsent")
            Text(app.T("Host tự soạn và tự bấm gửi từng tin trong ứng dụng Tin nhắn của chính host (trên máy của host). banbe không gửi hàng loạt hay tự động, và không đảm bảo tin được nhận. Tắt mục này sẽ chặn các tin quảng bá do banbe hỗ trợ trong tương lai, nhưng không ảnh hưởng tới tin nhắn mà host gửi độc lập sau khi đã có số của bạn.",
                       "Hosts write and send each text themselves from the host's own Messages app (on the host's phone). Banbe never sends in bulk or automatically and can't guarantee delivery. Turning this off blocks future banbe-assisted promos, but doesn't affect messages a host sends independently after already having your number."))
                .font(.app(size: 11.5))
                .foregroundStyle(app.palette.ink.opacity(0.7))
            if !app.hostPromoConsentError.isEmpty {
                Text(app.hostPromoConsentError).font(.app(size: 12)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .task { await app.loadHostPromoConsent() }
        .confirmationDialog(
            app.T("Cho phép tin nhắn quảng bá từ host?", "Allow promotional texts from hosts?"),
            isPresented: $promoConfirmOpen, titleVisibility: .visible
        ) {
            Button(app.T("Đồng ý", "I agree")) { Task { await app.setHostPromoConsent(true) } }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.T("Host mà bạn đã tương tác có thể soạn tin quảng bá sự kiện trong ứng dụng Tin nhắn của host, gửi tới số điện thoại đã xác minh của bạn. Host tự bấm gửi. banbe không gửi hộ. Bạn có thể tắt bất cứ lúc nào.",
                       "Hosts you've interacted with may compose an event promo text in the host's own Messages app, addressed to your verified phone number. The host sends it themselves. banbe doesn't send for them. You can turn this off any time."))
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        section(app.T("Đổi mật khẩu", "Change password")) {
            // One form for a first password and a replacement (the client cannot reliably tell which an account
            // has), but always behind proof it is the owner, not just a session left open on some device.
            Text(app.T(
                "Để bảo vệ tài khoản, hãy xác nhận đó là bạn trước khi đặt mật khẩu mới.",
                "To protect your account, confirm it is you before setting a new password."
            ))
            .font(.app(size: 12.5))
            .lineSpacing(3)
            .foregroundStyle(app.palette.ink.opacity(0.75))

            if proofMode == .code {
                codeProof
            } else {
                BanbeField(label: app.T("Mật khẩu hiện tại", "Current password"), placeholder: "",
                           text: $currentPassword, secure: true, contentType: .password)
                    .accessibilityIdentifier("security.currentPassword")
                    .onChange(of: currentPassword) { _, _ in clearFeedback() }
                proofLink(app.T("Chưa có hoặc quên mật khẩu? Xác nhận bằng mã qua email",
                                "No password or forgot it? Confirm with an email code"), id: "security.useCode") {
                    switchProof(to: .code)
                }
            }

            BanbeField(label: app.T("Mật khẩu mới", "New password"), placeholder: "",
                       text: $password, secure: true, contentType: .newPassword)
                .accessibilityIdentifier("security.password")
                .onChange(of: password) { _, _ in clearFeedback() }
            PasswordChecklist(password: password, isEN: app.isEN)
            BanbeField(label: app.T("Nhập lại mật khẩu mới", "Re-enter new password"), placeholder: "",
                       text: $confirmPassword, secure: true, contentType: .newPassword)
                .accessibilityIdentifier("security.passwordConfirm")
                .onChange(of: confirmPassword) { _, _ in clearFeedback() }

            if !passwordError.isEmpty {
                Text(passwordError)
                    .font(.app(size: 12))
                    .foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("security.passwordError")
            } else if let saved = passwordSaved {
                Text(saved
                     ? app.T("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.",
                             "Password changed. Other devices have been signed out.")
                     : app.T("Đã đổi mật khẩu. Chưa đăng xuất được các thiết bị khác, hãy thử lại sau.",
                             "Password changed. We could not sign out your other devices yet, try again later."))
                    .font(.app(size: 12))
                    .accessibilityIdentifier("security.passwordSaved")
            } else if let hint = passwordHint {
                Text(hint)
                    .font(.app(size: 12))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
            }

            InkButton(title: passwordBusy ? app.T("Đang lưu…", "Saving…") : app.T("Đổi mật khẩu", "Change password"),
                      enabled: canSubmitPassword) {
                Task { await savePassword() }
            }
            .accessibilityIdentifier("security.savePassword")
        }
    }

    /// Quiet hints only once the person has typed into the field they concern.
    private var passwordHint: String? {
        switch passwordBlocker {
        case .same where !password.isEmpty:
            return app.T("Mật khẩu mới phải khác mật khẩu hiện tại.", "Your new password must be different from the current one.")
        case .confirm where !confirmPassword.isEmpty:
            return app.T("Mật khẩu xác nhận không khớp.", "Passwords do not match.")
        default:
            return nil
        }
    }

    private var codeProof: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(codeSent
                 ? app.T("Đã gửi mã 6 số tới \(app.userEmail ?? "email của bạn").",
                         "We sent a 6-digit code to \(app.userEmail ?? "your email").")
                 : app.T("Chúng tôi sẽ gửi mã 6 số tới email của tài khoản.",
                         "We'll send a 6-digit code to this account's email."))
                .font(.app(size: 12.5))
                .lineSpacing(3)
            if codeSent {
                BanbeField(label: app.T("Mã xác nhận", "Confirmation code"), placeholder: "123456",
                           text: $reauthCode, keyboard: .numberPad, contentType: .oneTimeCode)
                    .accessibilityIdentifier("security.reauthCode")
                    .onChange(of: reauthCode) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { reauthCode = digits }
                        clearFeedback()
                    }
            }
            proofLink(codeSent ? app.T("Gửi lại mã", "Send a new code") : app.T("Gửi mã qua email", "Email me a code"),
                      id: "security.sendCode") {
                Task { await sendCode() }
            }
            .disabled(passwordBusy)
            proofLink(app.T("Dùng mật khẩu hiện tại", "Use my current password"), id: "security.usePassword") {
                switchProof(to: .password)
            }
        }
    }

    private func proofLink(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(size: 12.5, weight: .semibold))
                .underline()
                .foregroundStyle(app.palette.ink)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func clearFeedback() {
        passwordError = ""
        passwordSaved = nil
    }

    private func switchProof(to mode: PasswordChange.ProofMode) {
        proofMode = mode
        currentPassword = ""
        reauthCode = ""
        codeSent = false
        clearFeedback()
    }

    private func sendCode() async {
        clearFeedback()
        passwordBusy = true
        defer { passwordBusy = false }
        do {
            try await auth.sendReauthenticationCode()
            reauthCode = ""
            codeSent = true
        } catch {
            passwordError = PasswordChange.updateMessage(for: error, isEN: app.isEN)
        }
    }

    private func savePassword() async {
        clearFeedback()
        if let blocker = passwordBlocker {
            if blocker == .same { passwordError = passwordHint ?? "" }
            if blocker == .confirm { passwordError = app.T("Mật khẩu xác nhận không khớp.", "Passwords do not match.") }
            return
        }
        guard !passwordBusy else { return }
        passwordBusy = true
        defer { passwordBusy = false }

        if proofMode == .password {
            do {
                try await auth.verifyCurrentPassword(currentPassword)
            } catch {
                passwordError = PasswordChange.currentPasswordMessage(for: error, isEN: app.isEN)
                return
            }
        }
        do {
            let nonce = proofMode == .code ? reauthCode.trimmingCharacters(in: .whitespaces) : nil
            try await auth.updatePassword(password, nonce: nonce)
        } catch {
            passwordError = PasswordChange.updateMessage(for: error, isEN: app.isEN)
            // The server wants the emailed code on this session: switch the form to it.
            if PasswordChange.isReauthenticationNeeded(error) && proofMode == .password {
                proofMode = .code
                currentPassword = ""
                reauthCode = ""
                codeSent = false
            }
            return
        }
        let othersSignedOut = await auth.signOutOtherSessions()
        password = ""
        confirmPassword = ""
        currentPassword = ""
        reauthCode = ""
        codeSent = false
        proofMode = .password
        passwordSaved = othersSignedOut
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.app(size: 11.5, weight: .semibold))
            content()
        }
        .padding(.top, 28)
    }
}

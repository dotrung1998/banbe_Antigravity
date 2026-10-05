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
    @State private var promoConfirmOpen = false

    private var biometryName: String {
        BiometricAuthService.biometryType() == .touchID ? "Touch ID" : "Face ID"
    }

    private var canSubmitPassword: Bool {
        !passwordBusy && password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-section-of-a-group back-navigation fix (2026-09-29,
                // second pass) — was hardcoded to `.profile`, skipping the
                // "Tùy chỉnh"/"Preferences" group page this is actually
                // opened from (AccountGroupView). `goBack()` already routes
                // `.security` to `.accountGroup` correctly.
                BackLink(label: app.backLabel(for: app.backTargetScreen)) { app.goBack() }

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
                    section(app.T("Số điện thoại", "Phone number")) { PhoneVerificationSection() }
                    promoConsentSection
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
                            .font(.system(size: 11.5))
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
            Text(app.T("Host tự soạn và tự bấm gửi từng tin trong ứng dụng Tin nhắn của chính host (trên máy của host); banbe không gửi hàng loạt hay tự động, và không đảm bảo tin được nhận. Tắt mục này sẽ chặn các tin quảng bá do banbe hỗ trợ trong tương lai, nhưng không ảnh hưởng tới tin nhắn mà host gửi độc lập sau khi đã có số của bạn.",
                       "Hosts write and send each text themselves from the host's own Messages app (on the host's phone). Banbe never sends in bulk or automatically and can't guarantee delivery. Turning this off blocks future banbe-assisted promos, but doesn't affect messages a host sends independently after already having your number."))
                .font(.system(size: 11.5))
                .foregroundStyle(app.palette.ink.opacity(0.7))
            if !app.hostPromoConsentError.isEmpty {
                Text(app.hostPromoConsentError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
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
            Text(app.T("Host mà bạn đã tương tác có thể soạn tin quảng bá sự kiện trong ứng dụng Tin nhắn của host, gửi tới số điện thoại đã xác minh của bạn. Host tự bấm gửi; banbe không gửi hộ. Bạn có thể tắt bất cứ lúc nào.",
                       "Hosts you've interacted with may compose an event promo text in the host's own Messages app, addressed to your verified phone number. The host sends it themselves; banbe doesn't send for them. You can turn this off any time."))
        }
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

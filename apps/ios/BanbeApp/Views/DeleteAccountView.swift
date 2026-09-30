import SwiftUI

/// Account deletion (Task 2, Account/Settings pass) — mirrors
/// src/screens/sheets/DeleteAccountSheet.jsx step for step. Presented as a
/// `.fullScreenCover` from RootView, driven by `app.deleteAccountOpen`
/// (AccountGroupView's `preferences` case is the one entry point). All
/// wizard state (step/reason/phrase/reauth) is local `@State` here — this
/// view is the only thing that needs it.
///
/// SAFETY: this view can genuinely complete the real deletion (calls
/// `AuthAPIService.deleteAccount`, which hits the live `/api/auth` dispatcher's
/// `delete_account` action). It was never exercised end-to-end this
/// session — verified by reading, not by running it.
private let deleteAccountPhrase = "DELETE banbe"

private let deleteAccountReasons: [(code: String, vi: String, en: String)] = [
    ("not_using", "Tôi không còn dùng banbe nữa", "I don't use banbe anymore"),
    ("privacy", "Lo ngại về quyền riêng tư", "Privacy concerns"),
    ("found_alternative", "Tôi dùng ứng dụng khác", "I use a different app"),
    ("too_many_notifications", "Quá nhiều thông báo/email", "Too many notifications/emails"),
    ("other", "Khác", "Other"),
    ("prefer_not_say", "Không muốn cung cấp", "Prefer not to say"),
]

private enum DeleteAccountStep {
    case intro, reason, confirm, submitting, done
}

struct DeleteAccountView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    @State private var step: DeleteAccountStep = .intro
    @State private var reasonCode = ""
    @State private var reasonText = ""
    @State private var phraseInput = ""
    @State private var reauthSent = false
    @State private var reauthCode = ""
    @State private var reauthVerified = false
    @State private var reauthBusy = false
    @State private var reauthError = ""
    @State private var submitError = ""

    private var oauthProvider: String? {
        auth.session?.user.identities?.first(where: { $0.provider != "email" })?.provider
    }
    private var phraseMatches: Bool { phraseInput.trimmingCharacters(in: .whitespacesAndNewlines) == deleteAccountPhrase }
    private var readyToSubmit: Bool { phraseMatches && reauthVerified && step != .submitting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .intro: introSection
                    case .reason: reasonSection
                    case .confirm, .submitting: confirmSection
                    case .done: doneSection
                    }
                }
                .padding(20)
                .padding(.top, 20)
            }
            .background(app.palette.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .done {
                        Button(app.T("Huỷ", "Cancel")) { app.deleteAccountOpen = false }
                            .accessibilityIdentifier("deleteAccount.cancel")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var introSection: some View {
        Text(app.T("Xóa tài khoản", "Delete account")).font(BanbeTheme.display(24))
        VStack(alignment: .leading, spacing: 4) {
            Text(app.T("Tài khoản đang đăng nhập", "Currently signed in as")).font(.system(size: 11)).opacity(0.65)
            Text(app.user?.displayName ?? auth.session?.user.email ?? app.T("tài khoản của bạn", "your account")).font(.system(size: 15, weight: .semibold))
            if let email = auth.session?.user.email { Text(email).font(.system(size: 12)).opacity(0.7) }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("deleteAccount.identity")

        Text(app.T(
            "Đây là hành động vĩnh viễn. Sau khi xóa: các đặt chỗ/tin nhắn của bạn sẽ được tách khỏi danh tính thay vì bị xóa hoàn toàn khi cần giữ hồ sơ giao dịch; các dữ liệu cá nhân khác sẽ bị xóa hẳn. Nếu bạn đang sở hữu một sự kiện còn đang mở, bạn sẽ cần hủy/kết thúc sự kiện đó trước.",
            "This is permanent. After deletion: your bookings/messages are detached from your identity rather than fully erased where a transaction record needs to stay; other personal data is erased outright. If you currently own an open event, you’ll need to cancel/end it first."
        )).font(.system(size: 13)).lineSpacing(4)

        primaryButton(app.T("Tiếp tục", "Continue"), identifier: "deleteAccount.continue") { step = .reason }
    }

    @ViewBuilder
    private var reasonSection: some View {
        Text(app.T("Vì sao bạn muốn rời đi?", "Why are you leaving?")).font(BanbeTheme.display(20))
        Text(app.T("Không bắt buộc — chỉ để chúng tôi cải thiện.", "Optional — just helps us improve.")).font(.system(size: 12)).opacity(0.7)
        ForEach(deleteAccountReasons, id: \.code) { r in
            Button { reasonCode = r.code } label: {
                HStack {
                    Text(app.T(r.vi, r.en)).font(.system(size: 13.5))
                    Spacer()
                    if reasonCode == r.code { Image(systemName: "checkmark") }
                }
                .padding(13)
                .foregroundStyle(app.palette.ink)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(reasonCode == r.code ? app.palette.ink : app.palette.rule, lineWidth: reasonCode == r.code ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("deleteAccount.reason.\(r.code)")
        }
        if reasonCode == "other" {
            TextField(app.T("Cho chúng tôi biết thêm (không bắt buộc)", "Tell us more (optional)"), text: $reasonText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("deleteAccount.reasonText")
        }
        primaryButton(app.T("Tiếp tục", "Continue"), identifier: "deleteAccount.reasonContinue") { step = .confirm }
    }

    @ViewBuilder
    private var confirmSection: some View {
        let submitting = step == .submitting

        Text(app.T("Xác nhận xóa", "Confirm deletion")).font(BanbeTheme.display(20))

        // Reauthentication — reuses the SAME emailed login-code flow
        // Login/AuthViewModel already establish (`auth.sendEmailCode` /
        // `auth.verifyEmailCode`), never a parallel mechanism. An OAuth-only
        // account is told a fresh sign-in is required instead — this app
        // has no Sign in with Apple anywhere (confirmed by grep) and no
        // distinct Google/Facebook re-consent path beyond a normal
        // `signInWithOAuth` call, so this pass doesn't fabricate one. Face
        // ID (BiometricAuthService/FaceIDLockView) is a LOCAL convenience
        // only and is never read here as server-side proof.
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Bước 1 — Xác minh danh tính", "Step 1 — Verify it’s you")).font(.system(size: 12.5, weight: .semibold))
            if let provider = oauthProvider {
                Text(app.T(
                    "Tài khoản này đăng nhập qua \(provider). Vui lòng đăng xuất và đăng nhập lại gần đây trước khi xóa tài khoản.",
                    "This account signs in via \(provider). Please sign out and sign back in recently before deleting."
                )).font(.system(size: 12.5)).lineSpacing(3)
            } else if reauthVerified {
                Label(app.T("Đã xác minh", "Verified"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(.green)
                    .accessibilityIdentifier("deleteAccount.reauthDone")
            } else if !reauthSent {
                Button {
                    Task {
                        reauthBusy = true
                        await auth.sendEmailCode(to: auth.session?.user.email ?? "", mode: .login)
                        reauthBusy = false
                        reauthSent = auth.errorMessage == nil
                        if let err = auth.errorMessage { reauthError = err }
                    }
                } label: {
                    Text(reauthBusy ? app.T("Đang gửi…", "Sending…") : app.T("Gửi mã xác minh tới email", "Send verification code to email"))
                }
                .buttonStyle(DeleteAccountButtonStyle(app: app))
                .disabled(reauthBusy)
                .accessibilityIdentifier("deleteAccount.reauthSend")
            } else {
                TextField(app.T("Nhập mã 8 số", "Enter the 8-digit code"), text: $reauthCode)
                    .keyboardType(.numberPad)
                    .padding(11)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("deleteAccount.reauthCode")
                Button {
                    Task {
                        reauthBusy = true
                        await auth.verifyEmailCode(email: auth.session?.user.email ?? "", code: reauthCode, mode: .login)
                        reauthBusy = false
                        if let err = auth.errorMessage {
                            reauthError = err
                        } else {
                            reauthVerified = true
                            reauthError = ""
                        }
                    }
                } label: {
                    Text(reauthBusy ? app.T("Đang kiểm tra…", "Checking…") : app.T("Xác minh", "Verify"))
                }
                .buttonStyle(DeleteAccountButtonStyle(app: app))
                .disabled(reauthBusy)
                .accessibilityIdentifier("deleteAccount.reauthVerify")
                if !reauthError.isEmpty {
                    Text(reauthError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        // Exact-phrase gate.
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Bước 2 — Gõ để xác nhận", "Step 2 — Type to confirm")).font(.system(size: 12.5, weight: .semibold))
            HStack(spacing: 4) {
                Text(app.T("Gõ chính xác cụm sau:", "Type the exact phrase:")).font(.system(size: 12)).opacity(0.75)
                Text(deleteAccountPhrase).font(.system(size: 12, weight: .bold))
            }
            TextField(deleteAccountPhrase, text: $phraseInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(11)
                .background(app.palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("deleteAccount.phraseInput")
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        if !submitError.isEmpty {
            Text(submitError).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                .accessibilityIdentifier("deleteAccount.error")
        }

        // Final button — disabled until BOTH gates pass, disabled again
        // immediately on tap, real loading state, never claims "deleted"
        // until the server call has actually returned success.
        Button {
            guard readyToSubmit else { return }
            step = .submitting
            Task {
                do {
                    _ = try await AuthAPIService.deleteAccount(reasonCode: reasonCode.isEmpty ? nil : reasonCode, reasonText: reasonText.isEmpty ? nil : reasonText)
                    step = .done
                    // Client-side session cleanup — sign out of the
                    // now-nonexistent session and drop this device's push
                    // token registration (AppState+Push.swift's own guard
                    // already no-ops when ENABLE_PUSH isn't compiled in;
                    // this call is the explicit "forget it" regardless).
                    await auth.signOut()
                    app.forgetPushTokenLocally()
                } catch {
                    submitError = error.localizedDescription
                    step = .confirm
                }
            }
        } label: {
            Text(step == .submitting ? app.T("Đang xóa…", "Deleting…") : app.T("Xóa vĩnh viễn tài khoản", "Permanently delete account"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(DeleteAccountButtonStyle(app: app, destructive: true))
        .disabled(!readyToSubmit)
        .opacity(readyToSubmit ? 1 : 0.4)
        .accessibilityIdentifier("deleteAccount.final")
    }

    @ViewBuilder
    private var doneSection: some View {
        Text(app.T("Đã xóa tài khoản", "Account deleted")).font(BanbeTheme.display(24)).padding(.top, 30)
        Text(app.T("Tài khoản của bạn đã được xóa. Cảm ơn bạn đã dùng banbe.", "Your account has been deleted. Thanks for using banbe."))
            .font(.system(size: 13.5)).lineSpacing(4)
            .accessibilityIdentifier("deleteAccount.doneMessage")
        primaryButton(app.T("Đóng", "Close"), identifier: "deleteAccount.doneClose") {
            app.deleteAccountOpen = false
            app.screen = .home
        }
    }

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(DeleteAccountButtonStyle(app: app, destructive: true))
        .accessibilityIdentifier(identifier)
    }
}

private struct DeleteAccountButtonStyle: ButtonStyle {
    let app: AppState
    var destructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(14)
            .foregroundStyle(destructive ? Color.white : app.palette.ink)
            .background(destructive ? BanbeTheme.alert : app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

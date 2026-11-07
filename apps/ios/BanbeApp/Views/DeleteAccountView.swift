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

/// Shared with the "Before you go" pop-up (Lib/AccountRetention.swift).
private let deleteAccountReasons = AccountRetention.reasons

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
    @State private var reauthProof = ""
    /// Step 1 asks for the date of birth right here; the emailed code is the fallback for an account with none on file.
    @State private var reauthMode = "dob"
    @State private var dob = DateOfBirthInput()
    @State private var dobProblem = ""
    @State private var reauthBusy = false
    @State private var reauthError = ""
    @State private var submitError = ""
    /// Opened from the "Before you go" pop-up: the reason is already chosen, so the wizard starts at
    /// confirm, with the identity card and the "permanent" note carried up there.
    @State private var cameFromStay = false

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
            .onAppear {
                guard let preset = app.deleteAccountPresetReason else { return }
                app.deleteAccountPresetReason = nil
                reasonCode = preset
                cameFromStay = true
                step = .confirm
            }
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
        identityCard
        permanenceNote
        primaryButton(app.T("Tiếp tục", "Continue"), identifier: "deleteAccount.continue") { step = .reason }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(app.T("Tài khoản đang đăng nhập", "Currently signed in as")).font(.system(size: 11)).opacity(0.65)
            Text(app.user?.displayName ?? auth.session?.user.email ?? app.T("tài khoản của bạn", "your account")).font(.system(size: 15, weight: .semibold))
            if let email = auth.session?.user.email { Text(email).font(.system(size: 12)).opacity(0.7) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("deleteAccount.identity")
    }

    private var permanenceNote: some View {
        Text(app.T(
            "Đây là hành động vĩnh viễn. Sau khi xóa: các đặt chỗ/tin nhắn của bạn sẽ được tách khỏi danh tính thay vì bị xóa hoàn toàn khi cần giữ hồ sơ giao dịch. Các dữ liệu cá nhân khác sẽ bị xóa hẳn. Nếu bạn đang sở hữu một sự kiện còn đang mở, bạn sẽ cần hủy/kết thúc sự kiện đó trước.",
            "This is permanent. After deletion: your bookings/messages are detached from your identity rather than fully erased where a transaction record needs to stay. Other personal data is erased outright. If you currently own an open event, you’ll need to cancel/end it first."
        )).font(.system(size: 13)).lineSpacing(4)
    }

    @ViewBuilder
    private var reasonSection: some View {
        Text(app.T("Vì sao bạn muốn rời đi?", "Why are you leaving?")).font(BanbeTheme.display(20))
        Text(app.T("Không bắt buộc. Chỉ để chúng tôi cải thiện.", "Optional. Just helps us improve.")).font(.system(size: 12)).opacity(0.7)
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

    private func reauthMessage(_ error: Error) -> String {
        let f = error as? ReauthFailure
        switch f?.code {
        case "REAUTH_CODE_INVALID": return app.T("Mã không đúng hoặc đã hết hạn.", "That code is wrong or has expired.")
        case "REAUTH_DOB_INCORRECT":
            let n = f?.attemptsLeft ?? 0
            return app.T("Ngày sinh chưa đúng. Còn \(n) lần thử.", "That date of birth isn't right. \(n) tries left.")
        case "REAUTH_DOB_LOCKED":
            let mins = max(1, Int(ceil(Double(f?.retryAfter ?? 900) / 60)))
            return app.T("Bạn đã nhập sai quá nhiều lần. Thử lại sau \(mins) phút.", "Too many wrong tries. Try again in \(mins) min.")
        case "REAUTH_DOB_NOT_SET":
            return app.T("Tài khoản này chưa có ngày sinh. Hãy xác minh bằng mã gửi qua email.", "This account has no date of birth on file. Verify with an emailed code instead.")
        case "AUTH_REQUIRED":
            return app.T("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.", "Your session has expired. Please sign in again.")
        default:
            return app.T("Không thể xác minh lúc này. Vui lòng thử lại.", "We couldn't verify right now. Please try again.")
        }
    }

    private func submitDob() async {
        switch dob.validate() {
        case .failure(let problem):
            dobProblem = {
                switch problem {
                case .incomplete: return app.T("Nhập đủ ngày, tháng và năm (4 chữ số).", "Enter the day, month and a 4-digit year.")
                case .invalidDate: return app.T("Ngày này không có trong lịch.", "That date doesn't exist.")
                case .future: return app.T("Ngày sinh không thể ở tương lai.", "Date of birth can't be in the future.")
                case .tooOld: return app.T("Hãy nhập năm sinh từ 1900 trở đi.", "Enter a year from 1900 onward.")
                case .tooYoung: return app.T("banbe dành cho người từ 16 tuổi trở lên.", "banbe is for people aged 16 and over.") // not asked here
                }
            }()
        case .success(let iso):
            dobProblem = ""; reauthError = ""; reauthBusy = true
            do {
                reauthProof = try await AuthAPIService.verifyDeleteReauth(dob: iso)
                reauthVerified = true
            } catch {
                reauthError = reauthMessage(error)
                if (error as? ReauthFailure)?.code == "REAUTH_DOB_NOT_SET" { reauthMode = "email" }
            }
            reauthBusy = false
        }
    }

    @ViewBuilder
    private var confirmSection: some View {
        Text(app.T("Xác nhận xóa", "Confirm deletion")).font(BanbeTheme.display(20))
        if cameFromStay {
            identityCard
            permanenceNote
        }

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
            Text(app.T("Bước 1. Xác minh danh tính", "Step 1. Verify it’s you")).font(.system(size: 12.5, weight: .semibold))
            if reauthMode == "dob" || reauthVerified {
                if reauthVerified {
                    Label(app.T("Đã xác minh", "Verified"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(.green)
                        .accessibilityIdentifier("deleteAccount.reauthDone")
                } else {
                    Text(app.T("Nhập ngày sinh của bạn để xác nhận đây là bạn.", "Enter your date of birth to confirm it’s you."))
                        .font(.system(size: 12.5)).opacity(0.8)
                    DOBFieldsView(input: $dob, identifierPrefix: "deleteAccount.dob")
                    Button {
                        Task { await submitDob() }
                    } label: {
                        Text(reauthBusy ? app.T("Đang kiểm tra…", "Checking…") : app.T("Xác minh", "Verify"))
                    }
                    .buttonStyle(DeleteAccountButtonStyle(app: app))
                    .disabled(reauthBusy)
                    .accessibilityIdentifier("deleteAccount.dobVerify")
                    if !dobProblem.isEmpty || !reauthError.isEmpty {
                        Text(dobProblem.isEmpty ? reauthError : dobProblem)
                            .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                            .accessibilityIdentifier("deleteAccount.dobError")
                    }
                    Button(app.T("Dùng mã gửi qua email thay thế", "Use an emailed code instead")) {
                        dobProblem = ""; reauthError = ""; reauthMode = "email"
                    }
                    .font(.system(size: 12)).underline().opacity(0.75).buttonStyle(.plain)
                    .accessibilityIdentifier("deleteAccount.useEmail")
                }
            } else if let provider = oauthProvider {
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
                        do {
                            reauthProof = try await AuthAPIService.verifyDeleteReauth(code: reauthCode.trimmingCharacters(in: .whitespaces))
                            reauthVerified = true
                            reauthError = ""
                        } catch {
                            reauthError = reauthMessage(error)
                        }
                        reauthBusy = false
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
            if reauthMode == "email", !reauthVerified {
                Button(app.T("Dùng ngày sinh thay thế", "Use date of birth instead")) { reauthError = ""; reauthMode = "dob" }
                    .font(.system(size: 12)).underline().opacity(0.75).buttonStyle(.plain)
                    .accessibilityIdentifier("deleteAccount.useDob")
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        // Exact-phrase gate.
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Bước 2. Gõ để xác nhận", "Step 2. Type to confirm")).font(.system(size: 12.5, weight: .semibold))
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
                    _ = try await AuthAPIService.deleteAccount(reasonCode: reasonCode.isEmpty ? nil : reasonCode, reasonText: reasonText.isEmpty ? nil : reasonText, reauthProof: reauthProof)
                    step = .done
                    // Client-side session cleanup — sign out of the
                    // now-nonexistent session and drop this device's push
                    // token registration (AppState+Push.swift's own guard
                    // already no-ops when ENABLE_PUSH isn't compiled in;
                    // this call is the explicit "forget it" regardless).
                    await auth.signOut()
                    app.forgetPushTokenLocally()
                } catch {
                    if (error as? AccountDeletionError)?.code == "REAUTH_REQUIRED" {
                        // The 10-minute proof expired: ask for a fresh code.
                        reauthVerified = false; reauthProof = ""; reauthSent = false; reauthCode = ""
                        submitError = app.T("Phiên xác minh đã hết hạn. Vui lòng xác minh lại.", "Your verification expired. Please verify again.")
                    } else {
                        submitError = error.localizedDescription
                    }
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
            .foregroundStyle(destructive ? BanbeTheme.onAlert : app.palette.ink)
            .background(destructive ? BanbeTheme.alert : app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

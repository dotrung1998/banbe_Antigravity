import SwiftUI

/// Note 48 — the contextual sign-in ask shown to a guest at the moment an
/// action needs an account. Says why, keeps "Not now" as easy as "Continue",
/// and never says "Sign up" up front (the video's reciprocity rule: the ask
/// follows the value, and is framed as keeping what they're doing).
struct GuestPromptSheet: View {
    @EnvironmentObject private var app: AppState
    let prompt: GuestPrompt

    var body: some View {
        let copy = AppState.guestPromptCopy(prompt.context, T: app.T)
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.title)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(copy.body)
                .font(.body).lineSpacing(3)
                .foregroundStyle(app.palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            InkButton(title: app.T("Tiếp tục", "Continue"), font: .headline) {
                app.continueFromGuestPrompt(.signup)
            }
            .accessibilityIdentifier("guestPrompt.continue")
            .padding(.top, 6)
            Button {
                app.continueFromGuestPrompt(.login)
            } label: {
                Text(app.T("Đã có tài khoản? Đăng nhập", "Already have an account? Log in"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guestPrompt.login")
            Button {
                app.guestPrompt = nil
            } label: {
                Text(app.T("Để sau", "Not now"))
                    .font(.subheadline)
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("guestPrompt.notNow")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.paper)
        .presentationDetents([.height(340), .medium])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("guestPrompt")
    }
}

/// Home, signed out: a quiet line saying they're browsing as a guest, with
/// the account options one tap away (never a wall in front of the feed).
struct GuestBrowseBanner: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.T("Bạn đang xem với tư cách khách", "You're browsing as a guest"))
                    .font(.system(size: 13, weight: .semibold))
                Text(app.T("Tạo tài khoản để lưu, giữ chỗ và nhắn tin cho host.",
                           "Create an account to save, hold seats and message hosts."))
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(app.T("Đăng nhập", "Log in")) { app.openAuth(.login, from: app.screen) }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("home.guest.login")
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.guestBanner")
    }
}

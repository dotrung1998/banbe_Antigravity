import SwiftUI

/// Note 48 — the contextual sign-in ask shown to a guest at the moment an
/// action needs an account. Says why, keeps "Not now" as easy as "Continue",
/// and never says "Sign up" up front (the video's reciprocity rule: the ask
/// follows the value, and is framed as keeping what they're doing).
struct GuestPromptSheet: View {
    @EnvironmentObject private var app: AppState
    let prompt: GuestPrompt

    private var symbol: String {
        switch prompt.context {
        case .save: return "heart.fill"
        case .follow: return "person.crop.circle.badge.plus"
        case .reserve: return "ticket.fill"
        case .message: return "bubble.left.and.bubble.right.fill"
        case .like: return "hand.thumbsup.fill"
        }
    }

    /// What an account gives, the same three for every context so the ask
    /// reads as value, not a wall. The row matching the context comes first.
    private var benefits: [(icon: String, text: String)] {
        var rows: [(GuestPromptContext, String, String)] = [
            (.save, "heart", app.T("Lưu sự kiện, xem lại trên mọi thiết bị", "Save events and see them on every device")),
            (.reserve, "ticket", app.T("Giữ chỗ trong vài giây, nhận vé QR", "Hold a seat in seconds, get a QR ticket")),
            (.message, "bubble.left", app.T("Nhắn trực tiếp cho host", "Message hosts directly")),
        ]
        if let i = rows.firstIndex(where: { $0.0 == prompt.context }) { rows.insert(rows.remove(at: i), at: 0) }
        if prompt.context == .follow {
            rows[2] = (.follow, "bell", app.T("Biết ngay khi host bạn theo dõi có sự kiện mới", "Hear first when hosts you follow post events"))
        }
        return rows.map { ($0.1, $0.2) }
    }

    var body: some View {
        let copy = AppState.guestPromptCopy(prompt.context, T: app.T)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [app.palette.ink.opacity(0.10), app.palette.ink.opacity(0.03)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(app.palette.ink)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)

            Text(copy.title)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 18)
            Text(copy.body)
                .font(.subheadline).lineSpacing(3)
                .foregroundStyle(app.palette.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(app.palette.ink.opacity(0.07), in: Circle())
                            .accessibilityHidden(true)
                        Text(row.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            .padding(.top, 20)

            InkButton(title: app.T("Tiếp tục", "Continue"), font: .headline) {
                app.continueFromGuestPrompt(.signup)
            }
            .accessibilityIdentifier("guestPrompt.continue")
            .padding(.top, 22)

            HStack {
                Button {
                    app.continueFromGuestPrompt(.login)
                } label: {
                    Text(app.T("Đăng nhập", "Log in"))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("guestPrompt.login")
                Spacer()
                Button {
                    app.guestPrompt = nil
                } label: {
                    Text(app.T("Để sau", "Not now"))
                        .font(.subheadline)
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("guestPrompt.notNow")
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.paper)
        // The dock sits in its own window above sheets; hide it while this is up.
        .hidesDock("guestPrompt")
        .presentationDetents([.height(560), .large])
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

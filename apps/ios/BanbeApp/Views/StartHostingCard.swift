import SwiftUI

/// "Host your first event" (Simple Shell follow-up, plan item 1): one card, used inline on Account and inside the
/// Start hosting invitation sheet. One primary action. Someone who can already host (`canHost`) but has organizer
/// mode off sees "Turn on hosting" instead of the first-event pitch. Web twin: src/components/StartHostingCard.jsx.
struct StartHostingCard: View {
    @EnvironmentObject private var app: AppState
    /// Inline on Account the card sits on a block fill; in the sheet it is the sheet's whole content.
    var inSheet = false
    let action: () -> Void

    private var turnOn: Bool { app.canHost }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turnOn ? app.T("Bật chế độ tổ chức", "Turn on hosting")
                        : app.T("Tổ chức sự kiện đầu tiên", "Host your first event"))
                .font(BanbeTheme.display(inSheet ? 22 : 17))
                .accessibilityAddTraits(.isHeader)
            Text(turnOn
                 ? app.T("Bật lại để tạo và quản lý sự kiện của bạn.", "Turn it back on to create and manage your events.")
                 : app.T("Miễn phí khi banbe còn mới. Không phí đăng, không phí giao dịch.",
                         "Free while banbe is new. No listing or transaction fees."))
                .font(inSheet ? .subheadline : .footnote)
                .foregroundStyle(app.palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            InkButton(title: turnOn ? app.T("Bật chế độ tổ chức", "Turn on hosting")
                                    : app.T("Bắt đầu tổ chức ▪︎ miễn phí", "Start hosting ▪︎ free")) {
                action()
            }
            .padding(.top, inSheet ? 8 : 0)
            .accessibilityIdentifier(inSheet ? "startHosting.confirm" : "account.hostFirstEvent.start")
        }
        .foregroundStyle(app.palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Start hosting invitation (RootView presents it from `app.startHostingInviteOpen`). The primary action only
/// marks the intent and closes the sheet; RootView's `onDismiss` then runs `confirmStartHosting()`, so the
/// first-activation HostSetupView opens after this sheet is fully gone (two presentations never overlap).
struct StartHostingSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(app.palette.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Đóng", "Close"))
                .accessibilityIdentifier("startHosting.close")
            }
            StartHostingCard(inSheet: true) {
                app.startHostingAfterInvite = true
                dismiss()
            }
            .padding(.horizontal, 24)
            if !app.organizerModeError.isEmpty {
                Text(app.organizerModeError)
                    .font(.footnote)
                    .foregroundStyle(BanbeTheme.alert)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .accessibilityIdentifier("startHosting.error")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(app.palette.paper.ignoresSafeArea())
        .presentationDetents([.height(300), .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startHosting.sheet")
        .hidesDock("startHostingInvite")
    }
}

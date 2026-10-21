import SwiftUI

/// "Before you go" pop-up shown when someone taps Delete account (owner, 2026-10-21). It shows what they would
/// lose, asks why, and offers the one fix for that reason. "Continue deleting" is always visible and opens the
/// existing DeleteAccountView at its confirm step with the reason filled in. Logic lives in
/// Lib/AccountRetention.swift; web twin: src/screens/sheets/DeleteAccountStaySheet.jsx.
struct DeleteAccountStayView: View {
    @EnvironmentObject private var app: AppState
    @State private var reasonCode = ""
    @State private var offerBusy = false
    @State private var quieted = false

    private var lossRows: [AccountRetention.LossRow] {
        AccountRetention.lossRows(
            bookedEvents: app.attending.count, savedEvents: app.favorites.count,
            followedHosts: app.followedHosts.count, coins: app.rewardsSummary?.balance,
            rewardsEnabled: app.rewardsEnabled, hostedEvents: app.myOrgPublishedEventCount ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🥺").font(.system(size: 40)).accessibilityHidden(true)
                        Text(app.T("Trước khi bạn đi…", "Before you go…"))
                            .font(BanbeTheme.display(26))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("deleteStay.title")
                        Text(app.T("Xoá tài khoản là vĩnh viễn và không thể khôi phục.",
                                   "Deleting your account is permanent and can't be undone."))
                            .font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.75))
                    }

                    if !lossRows.isEmpty { lossSection }
                    reasonSection
                    if let offer = AccountRetention.offer(for: reasonCode) { offerCard(offer) }

                    VStack(spacing: 8) {
                        InkButton(title: app.T("Giữ tài khoản của tôi", "Keep my account")) {
                            Haptics.success()
                            app.deleteAccountStayOpen = false
                        }
                        .accessibilityIdentifier("deleteStay.keep")
                        Button {
                            app.deleteAccountPresetReason = reasonCode
                            app.deleteAccountContinue = true
                            app.deleteAccountStayOpen = false
                        } label: {
                            Text(app.T("Tiếp tục xoá tài khoản", "Continue deleting my account"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BanbeTheme.alert)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("deleteStay.continue")
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(app.palette.paper)
            .foregroundStyle(app.palette.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Đóng", "Close")) { app.deleteAccountStayOpen = false }
                        .accessibilityIdentifier("deleteStay.close")
                }
            }
        }
    }

    // MARK: sections

    private var lossSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Bạn sẽ mất", "You'd lose")).font(.footnote.weight(.semibold))
                .foregroundStyle(app.palette.ink.opacity(0.7))
            ForEach(lossRows, id: \.kind) { row in
                HStack(spacing: 12) {
                    Image(systemName: icon(row.kind))
                        .font(.body.weight(.semibold))
                        .frame(width: 28)
                        .foregroundStyle(app.palette.clay)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(row)).font(.subheadline.weight(.semibold))
                        if row.kind == .hostedEvents {
                            Text(app.T("Sự kiện đang mở cần được huỷ hoặc kết thúc trước khi xoá.",
                                       "Open events must be cancelled or ended before you can delete."))
                                .font(.caption).foregroundStyle(app.palette.ink.opacity(0.7))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("deleteStay.losses")
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Vì sao bạn muốn rời đi?", "Why are you leaving?")).font(.headline)
            Text(app.T("Không bắt buộc — giúp chúng tôi gợi ý cách khắc phục.", "Optional — helps us suggest a fix."))
                .font(.caption).foregroundStyle(app.palette.ink.opacity(0.7))
            FlowChips(items: AccountRetention.reasons.map { ($0.code, app.T($0.vi, $0.en)) },
                      selected: reasonCode) { code in
                withAnimation(.easeOut(duration: 0.2)) { reasonCode = reasonCode == code ? "" : code }
                quieted = false
            }
        }
    }

    private func offerCard(_ offer: RetentionOffer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(offerTitle(offer)).font(.subheadline.weight(.semibold))
            Text(offerBody(offer)).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if offer == .quieterNotifications && quieted {
                Label(app.T("Đã tắt. Bạn vẫn nhận thông báo về vé, thanh toán và hoàn tiền.",
                            "Done. You'll still get ticket, payment and refund alerts."),
                      systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("deleteStay.quieted")
            } else {
                SecondaryButton(title: offerButton(offer)) { Task { await run(offer) } }
                    .disabled(offerBusy)
                    .accessibilityIdentifier("deleteStay.offer.\(offer.rawValue)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.clay.opacity(0.5), lineWidth: 1.5))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: actions

    private func run(_ offer: RetentionOffer) async {
        switch offer {
        case .quieterNotifications:
            offerBusy = true
            for kind in AccountRetention.quietedNotificationKinds { await app.muteNotificationKind(kind) }
            // Unknown (not loaded yet) counts as possibly on: switching it off is harmless.
            if app.hostPromoConsent != false { _ = await app.setHostPromoConsent(false) }
            offerBusy = false
            Haptics.success()
            withAnimation { quieted = true }
        case .retuneForYou:
            app.deleteAccountStayOpen = false
            app.openEventPreferences()
        case .reviewPrivacy:
            app.deleteAccountStayOpen = false
            app.openSecurity()
        case .takeABreak:
            app.deleteAccountStayOpen = false
            await app.signOut()
        }
    }

    // MARK: copy

    private func icon(_ kind: AccountRetention.LossKind) -> String {
        switch kind {
        case .bookedEvents: return "ticket"
        case .hostedEvents: return "person.3"
        case .savedEvents: return "heart"
        case .followedHosts: return "person.crop.circle.badge.checkmark"
        case .coins: return "star.circle"
        }
    }

    private func label(_ row: AccountRetention.LossRow) -> String {
        let n = row.count
        switch row.kind {
        case .bookedEvents: return app.T("\(n) sự kiện bạn đã đặt chỗ", n == 1 ? "1 event you've booked" : "\(n) events you've booked")
        case .hostedEvents: return app.T("\(n) sự kiện bạn tổ chức", n == 1 ? "1 event you host" : "\(n) events you host")
        case .savedEvents: return app.T("\(n) sự kiện đã lưu", n == 1 ? "1 saved event" : "\(n) saved events")
        case .followedHosts: return app.T("\(n) host bạn theo dõi", n == 1 ? "1 host you follow" : "\(n) hosts you follow")
        case .coins: return app.T("\(n) xu thưởng", n == 1 ? "1 reward coin" : "\(n) reward coins")
        }
    }

    private func offerTitle(_ offer: RetentionOffer) -> String {
        switch offer {
        case .quieterNotifications: return app.T("Bớt thông báo, giữ tài khoản", "Fewer notifications, same account")
        case .retuneForYou: return app.T("Gợi ý chưa hợp với bạn?", "Suggestions not a fit?")
        case .reviewPrivacy: return app.T("Bạn kiểm soát những gì được chia sẻ", "You control what's shared")
        case .takeABreak: return app.T("Cần nghỉ một chút?", "Need a break?")
        }
    }

    private func offerBody(_ offer: RetentionOffer) -> String {
        switch offer {
        case .quieterNotifications:
            return app.T("Tắt tin quảng bá từ host và thông báo chung của sự kiện. Thông báo về vé, thanh toán và hoàn tiền vẫn giữ.",
                         "Turn off host promos and event announcements. Ticket, payment and refund alerts stay on.")
        case .retuneForYou:
            return app.T("Trả lời lại 5 câu ngắn để ★ Dành cho bạn chọn sự kiện sát hơn.",
                         "Re-answer 5 quick questions so ★ For You picks closer matches.")
        case .reviewPrivacy:
            return app.T("Sở thích của bạn chỉ mình bạn thấy. Xem và chỉnh cài đặt bảo mật, khoá Face ID và tin quảng bá.",
                         "Your preferences are only visible to you. Review security, Face ID lock and promo settings.")
        case .takeABreak:
            return app.T("Đăng xuất thay vì xoá — vé, lịch sử và sự kiện đã lưu vẫn còn khi bạn quay lại.",
                         "Sign out instead of deleting — your tickets, history and saved events are here when you're back.")
        }
    }

    private func offerButton(_ offer: RetentionOffer) -> String {
        switch offer {
        case .quieterNotifications: return app.T("Tắt bớt thông báo", "Quiet my notifications")
        case .retuneForYou: return app.T("Chỉnh lại gợi ý", "Retune my suggestions")
        case .reviewPrivacy: return app.T("Mở cài đặt bảo mật", "Open security settings")
        case .takeABreak: return app.T("Đăng xuất", "Sign out")
        }
    }
}

/// Wrapping single-select chips.
private struct FlowChips: View {
    let items: [(code: String, label: String)]
    let selected: String
    let onTap: (String) -> Void
    @EnvironmentObject private var app: AppState

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(items, id: \.code) { item in
                let on = item.code == selected
                Button { onTap(item.code) } label: {
                    Text(item.label)
                        .font(.footnote.weight(on ? .semibold : .regular))
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                        .background(on ? app.palette.ink : app.palette.field, in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : app.palette.rule, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("deleteStay.reason.\(item.code)")
            }
        }
    }
}

/// Minimal left-aligned wrapping layout for the reason chips.
private struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import SwiftUI

/// The yellow "Awaiting Verification" entry for ONE disputed refund — the
/// counterpart of the pinned yellow section in Messages, placed where the
/// person who has to act about it already is (the goer's payment screen,
/// PaymentDetailsView; the host's verification queue, VerificationsView).
///
/// It deliberately does NOT embed the chat itself. The chat's home is the
/// Messages dispute section, where both parties can expand it inline
/// alongside their conversations; this is the shortcut to it — one tap from
/// the payment screen straight into that specific conversation, expanded and
/// ready to type into. Embedding a second copy here would mean two live 4s
/// polls of the same transcript, two places to keep the retention state in
/// sync, and a screen that grows a full chat transcript inside a card about
/// something else.
struct RefundDisputeEntry: View {
    @EnvironmentObject private var app: AppState
    let refundClaimId: UUID
    var amountVnd: Int?
    var eventName: String?
    @State private var didFetch = false

    /// Same 6s cadence as the Inbox's own dispute poll — nothing in this app
    /// subscribes to Supabase Realtime, and this entry only matters for a
    /// handful of seconds on a screen that's already polling its own data.
    private static let pollInterval: UInt64 = 6_000_000_000

    private var chat: DisputeChatSummary? {
        app.disputeChats.first { $0.refundClaimId == refundClaimId }
    }

    private var concluded: Bool { chat?.isConcluded == true }

    /// "Ends in ~N days" — a static, render-time countdown, same idea as
    /// DisputeChatPanel's own retention label, in days because this window is
    /// 7 days wide and hour granularity here would just read as noise.
    private var daysLeftLabel: String? {
        guard let purgeAfter = chat?.purgeAfter else { return nil }
        let days = Int(ceil(purgeAfter.timeIntervalSinceNow / 86400))
        guard days > 0 else { return nil }
        return days <= 1
            ? app.T("tự xoá sau ~1 ngày", "deletes in ~1 day")
            : app.T("tự xoá sau ~\(days) ngày", "deletes in ~\(days) days")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(concluded
                     ? app.T("Đã xác minh ▪︎ tranh chấp đã kết thúc", "Verified ▪︎ this dispute has ended")
                     : app.T("Chờ xác minh", "Awaiting Verification"))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(app.palette.honey)
                    .accessibilityIdentifier("refundDisputeEntry.title")

                Text(concluded
                     ? app.T("Khoản hoàn đã được xử lý xong. Đoạn chat vẫn còn để đọc trong 7 ngày rồi tự xoá.",
                             "The refund is settled. The chat stays readable for 7 days, then deletes itself.")
                     : app.T("Chưa thống nhất được về khoản hoàn này. Mở cuộc trò chuyện tạm thời để trao đổi trực tiếp với phía bên kia.",
                             "You and the other side aren't agreed on this refund yet. Open the temporary chat to sort it out directly."))
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink.opacity(0.75))

                if eventName != nil || amountVnd != nil {
                    Text([eventName, amountVnd.map(formatVnd)].compactMap { $0 }.joined(separator: " ▪︎ "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                }

                if let body = chat?.lastMessageBody {
                    Text(app.T("Tin nhắn mới nhất: ", "Latest message: ") + body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.7))
                }

                if let daysLeftLabel {
                    Text(daysLeftLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)

            // The jump. Hidden rather than shown-disabled when the chat row
            // hasn't resolved yet, so the entry never presents a dead control
            // the way a disabled "Open chat" would.
            if let chat, !concluded {
                Divider().overlay(app.palette.honey)
                SwipeSafeButton {
                    app.openDisputeChatInInbox(chat.threadId)
                } label: {
                    HStack(spacing: 4) {
                        Text(chat.viewerRole == "organizer"
                             ? app.T("Mở chat với khách ›", "Open chat with the guest ›")
                             : app.T("Mở chat với người tổ chức ›", "Open chat with the organizer ›"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(app.palette.honey)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }
                .accessibilityIdentifier("refundDisputeEntry.openChat")
            }
        }
        .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(app.palette.honey, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 12)
        .accessibilityIdentifier("refundDisputeEntry")
        // The chat row is normally already in state (Messages keeps it fresh,
        // and raising the dispute refreshes it). If this screen is reached
        // first — deep link, notification, cold open — fetch once, then keep
        // retrying on the usual poll only while it's still missing, so a
        // genuinely thread-less claim can't spin a request forever.
        .task {
            if chat == nil && !didFetch {
                didFetch = true
                await app.loadDisputeChats()
            }
        }
        .task(id: chat?.threadId) {
            guard chat == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                if Task.isCancelled { return }
                if chat != nil { return }
                await app.loadDisputeChats()
            }
        }
    }
}
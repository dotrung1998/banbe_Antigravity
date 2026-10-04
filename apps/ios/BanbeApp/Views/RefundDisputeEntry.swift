import SwiftUI

/// Which side of the refund dispute the screen this entry sits on belongs to.
///
/// The label used to be derived from `viewer_role` off whatever row happened
/// to be in the polled get_my_dispute_chats() list, so the HOST's queue could
/// read "Open chat with the organizer" — i.e. with themselves — whenever that
/// list was empty or one poll behind, and the button could be missing
/// altogether. The screen already knows unambiguously which role it is (a
/// host's Awaiting Verification queue vs. a goer's own refund card), so it
/// says so; the SERVER still verifies ownership independently, in
/// get_refund_dispute_thread().
enum RefundDisputeViewer: String {
    case host
    case goer

    var isHost: Bool { self == .host }
}

/// The refund-dispute card on a refund screen — the goer's own payment screen
/// (PaymentDetailsView) and the host's Awaiting Verification queue
/// (VerificationsView).
///
/// It deliberately does NOT embed the transcript itself. The transcript's home
/// is the EXISTING booking conversation for this claim (ChatView, via
/// get_refund_dispute_for_conversation), which both parties already have — so
/// this is one tap from the refund screen straight into that conversation with
/// its dispute block expanded and ready to type into. Embedding a second copy
/// here would mean two live 4s polls of the same transcript, two places to
/// keep the closure state in sync, and a full chat growing inside a card about
/// something else.
struct RefundDisputeEntry: View {
    @EnvironmentObject private var app: AppState
    let refundClaimId: UUID
    /// Explicit screen context — see RefundDisputeViewer.
    let viewer: RefundDisputeViewer
    var amountVnd: Int?
    var eventName: String?
    /// Where "Open chat" returns to. Both parties come from somewhere
    /// different (the goer's payment screen, the host's notification bell),
    /// and a dispute that jumps you somewhere you can't get back out of is
    /// its own bug.
    var back: Screen = .paymentDetails

    @State private var didFetch = false
    @State private var flowRequest: RefundDisputeFlowRequest?

    /// Same 6s cadence as the rest of this screen's own polls — nothing in
    /// this app subscribes to Supabase Realtime, and this card only needs to
    /// stay fresh while someone is looking at it.
    private static let pollInterval: UInt64 = 6_000_000_000

    /// The VERIFIED per-claim dispute state, fetched by exact claim id. This
    /// is what the card renders from — not the cached dispute list — so a
    /// missing or stale list can neither hide the actions nor mislabel who the
    /// other side is.
    private var dispute: RefundDisputeThread? {
        app.refundDisputeThreads[refundClaimId]?.found == true ? app.refundDisputeThreads[refundClaimId] : nil
    }

    private var loading: Bool { app.refundDisputeThreadsLoading.contains(refundClaimId) }
    private var completed: Bool { dispute?.isCompleted == true }

    /// "Deletes in ~N days" — the retention deadline for a closed transcript,
    /// in days because this window is 7 days wide and hour granularity here
    /// would read as noise.
    private var retentionLabel: String? {
        guard completed, let purgeAfter = dispute?.purgeAfter else { return nil }
        let days = Int(ceil(purgeAfter.timeIntervalSinceNow / 86400))
        let vi = formatShortDate(purgeAfter, lang: "vi") ?? ""
        let en = formatShortDate(purgeAfter, lang: "en") ?? ""
        guard !vi.isEmpty, !en.isEmpty else { return nil }
        return app.T("Bản ghi bị xoá vào \(vi).", "Transcript is deleted on \(en).")
            + (days > 0 ? app.T(" (còn ~\(days) ngày)", " (~\(days) days left)") : "")
    }

    private var copyDeleted: Bool { app.refundDisputeDeletedCopies.contains(refundClaimId) }

    var body: some View {
        if copyDeleted {
            deletedCopyCard
        } else {
            card
        }
    }

    /// The goer removed their own copy. The refund itself is unaffected and
    /// the organizer's record is not shown here.
    private var deletedCopyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Bạn đã xoá bản của mình", "You deleted your copy"))
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(app.palette.honey)
            Text(app.T("Cuộc trò chuyện không còn trong tài khoản của bạn. Khoản hoàn không thay đổi. Người tổ chức vẫn giữ bản ghi của họ đến khi hết hạn.",
                       "The conversation is no longer in your account. The refund is unchanged. The organizer keeps their record until it expires."))
                .font(.system(size: 12))
                .foregroundStyle(app.palette.ink.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.honey, lineWidth: 1))
        .padding(.top, 12)
        .accessibilityIdentifier("refundDisputeEntry.deletedCopy")
        .task { if !copyDeleted { await app.loadRefundDisputeThread(refundClaimId, force: true) } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(completed
                         ? app.T("Tranh chấp đã hoàn tất", "Dispute completed")
                         : app.T("Chờ xác minh", "Awaiting Verification"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(app.palette.honey)
                        .accessibilityIdentifier("refundDisputeEntry.title")
                    Spacer(minLength: 0)
                    if !completed {
                        Text(app.T("Tranh chấp đang diễn ra", "Dispute in progress"))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(BanbeTheme.alert)
                            .accessibilityIdentifier("refundDisputeEntry.inProgress")
                    }
                }

                Text(completed
                     ? app.T("Khoản hoàn vẫn được xử lý như bình thường. Bản ghi tranh chấp còn đọc được một thời gian rồi tự xoá.",
                             "The refund itself is still being handled as usual. The dispute transcript stays readable for a while, then deletes itself.")
                     : app.T("Chưa thống nhất được về khoản hoàn này. Mở cuộc trò chuyện tạm thời để trao đổi trực tiếp với phía bên kia.",
                             "You and the other side aren't agreed on this refund yet. Open the temporary chat to sort it out directly."))
                    .font(.system(size: 12))
                    .foregroundStyle(app.palette.ink.opacity(0.75))

                if eventName != nil || amountVnd != nil {
                    Text([eventName, amountVnd.map(formatVnd)].compactMap { $0 }.joined(separator: " ▪︎ "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                }

                if let amount = dispute?.amountVnd, amountVnd != amount {
                    Text(formatVnd(amount))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                }

                if let retentionLabel {
                    Text(retentionLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.55))
                        .accessibilityIdentifier("refundDisputeEntry.retention")
                }

                if loading && dispute == nil {
                    Text(app.T("Đang tải…", "Loading…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)

            // The actions. Present exactly when this account IS a verified
            // party — the jump is hidden rather than shown-disabled when it
            // isn't, so the card never presents a dead control.
            if dispute != nil {
                Divider().overlay(app.palette.honey)
                VStack(spacing: 0) {
                    SwipeSafeButton {
                        Task { await app.openDisputeForRefundClaim(refundClaimId, back: back) }
                    } label: {
                        actionRow(
                            icon: "bubble.left.and.bubble.right",
                            label: chatLabel,
                            tint: app.palette.honey,
                            identifier: "refundDisputeEntry.openChat"
                        )
                    }
                    Divider().overlay(app.palette.honey)
                    SwipeSafeButton {
                        flowRequest = .download
                    } label: {
                        actionRow(
                            icon: "square.and.arrow.down",
                            label: exportRunning
                                ? app.T("Đang chuẩn bị bản tải về…", "Preparing your download…")
                                : app.T("Tải bản ghi tranh chấp", "Download dispute transcript"),
                            tint: app.palette.ink.opacity(0.8),
                            identifier: "refundDisputeEntry.download",
                            disabled: exportRunning
                        )
                    }
                    if !completed {
                        Divider().overlay(app.palette.honey)
                        SwipeSafeButton {
                            flowRequest = .close
                        } label: {
                            actionRow(
                                icon: "checkmark.circle",
                                label: app.T("Đóng tranh chấp", "Close dispute"),
                                tint: (dispute?.refundSettled == true) ? BanbeTheme.alert : app.palette.ink.opacity(0.35),
                                identifier: "refundDisputeEntry.close",
                                disabled: flowBusy || dispute?.refundSettled != true
                            )
                        }
                        .disabled(dispute?.refundSettled != true)
                        if dispute?.refundSettled != true {
                            Text(app.T("Chỉ đóng được sau khi người tổ chức đánh dấu đã hoàn tiền và khách xác nhận đã nhận.",
                                       "You can close this after the host marks the refund sent and the guest confirms it was received."))
                                .font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.55))
                                .padding(.horizontal, 15).padding(.bottom, 10)
                        }
                    } else if dispute?.viewerRole == "guest" {
                        Divider().overlay(app.palette.honey)
                        SwipeSafeButton {
                            flowRequest = .deleteCopy
                        } label: {
                            actionRow(
                                icon: "trash",
                                label: app.T("Xoá bản của tôi", "Delete my copy"),
                                tint: BanbeTheme.alert,
                                identifier: "refundDisputeEntry.deleteCopy",
                                disabled: flowBusy
                            )
                        }
                    }
                }
            }

            if !app.disputeCloseError.isEmpty {
                Text(app.disputeCloseError)
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    .padding(.horizontal, 15).padding(.bottom, 12)
                    .accessibilityIdentifier("refundDisputeEntry.closeError")
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
        // Resolved by exact claim id, so this is correct on a cold open, on a
        // deep link, and the instant after either party raises the dispute —
        // none of which depend on the Messages list ever having been loaded.
        .task {
            if dispute == nil && !didFetch {
                didFetch = true
                await app.loadRefundDisputeThread(refundClaimId, force: true)
            }
        }
        .task(id: dispute == nil) {
            // Keep retrying on the usual cadence only while the thread is
            // genuinely missing, so a claim that was never disputed can't spin
            // a request forever.
            guard dispute == nil, !copyDeleted else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                if Task.isCancelled { return }
                if dispute != nil || copyDeleted { return }
                await app.loadRefundDisputeThread(refundClaimId, force: true)
            }
        }
        .refundDisputeFlows(claimID: refundClaimId, request: $flowRequest)
    }

    private var exportRunning: Bool {
        app.disputeExport.claimID == refundClaimId && app.disputeExport.status == .running
    }

    private var flowBusy: Bool {
        app.refundDisputeClosingClaimId != nil || app.refundDisputeDeletingClaimId != nil
    }

    /// "Open chat with the goer" on the host's queue, "…with the organizer" on
    /// the goer's own screen — decided by the SCREEN, which knows its own
    /// role exactly, instead of by a polled row that might not be there.
    private var chatLabel: String {
        viewer.isHost
            ? app.T("Mở chat với khách ›", "Open chat with the goer ›")
            : app.T("Mở chat với người tổ chức ›", "Open chat with the organizer ›")
    }

    private func actionRow(icon: String, label: String, tint: Color, identifier: String, disabled: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .opacity(disabled ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
    }
}
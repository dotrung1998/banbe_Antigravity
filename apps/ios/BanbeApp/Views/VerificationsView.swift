import SwiftUI
import PhotosUI

/// The organizer's manual-verification queue — the fallback for whatever the
/// bank webhook didn't reconcile on its own. Oldest first: this is a queue
/// people are waiting in, and the longest wait is the closest to giving up.
struct VerificationsView: View {
    @EnvironmentObject private var app: AppState
    /// Which row's reason form is open, and for which action — one field,
    /// two possible destinations, so opening one always closes the other.
    @State private var reasonFor: (bookingId: UUID, kind: ReasonKind)?
    @State private var reason = ""
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()
    // Flow 2 (host refund -> guest confirmation).
    @State private var refundQueuePollTask: Task<Void, Never>?
    @State private var refundNoteFor: UUID?
    @State private var refundNoteText = ""
    @State private var refundProofItem: PhotosPickerItem?
    @State private var refundProofJPEG: Data?
    @State private var refundProofPreview: UIImage?
    // Point 2 — diagnostics panel toggle (5 taps on the "Hoàn tiền" title).
    @State private var diagOpen = false
    @State private var diagTapCount = 0

    private enum ReasonKind { case reject, escalate }

    private var overdueCount: Int { app.verifications.filter { $0.overdue == true }.count }

    // 14-organizer-checkin.md: Attendance's "Check payment" button
    // (openVerificationDetail) sets verificationsFocusBookingID so the
    // organizer lands on exactly the one booking they tapped from — whether
    // it's the only pending item or buried far down a long queue — instead
    // of the full list.
    private var visibleVerifications: [PendingVerification] {
        guard let focusID = app.verificationsFocusBookingID else { return app.verifications }
        return app.verifications.filter { $0.bookingId == focusID }
    }

    var body: some View {
        ScreenScaffold(scrollPositionID: $app.verificationsScrollAnchorID) {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-section-of-a-group back-navigation fix (2026-09-29,
                // second pass) — label now also distinguishes the
                // "hostOps" group page (AccountGroupView, where this is
                // now correctly routed back to) from a plain "Account",
                // matching that group's own title text.
                BackLink(label: app.backLabel(for: app.verificationsBack)) { app.screen = app.verificationsBack }
                    .padding(.top, 8)
                    .accessibilityIdentifier("verifications.back")

                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background((ROW_ACCENT_COLORS["hostOps"] ?? .clear).opacity(0.33), in: Circle())
                    Text(app.verificationsFocusBookingID != nil ? app.T("Chi tiết thanh toán", "Payment Detail") : app.T("Chờ xác nhận", "Awaiting Verification"))
                        .font(BanbeTheme.display(24))
                }
                .padding(.top, 10)
                    .accessibilityIdentifier("verifications.title")
                Text(app.T("Khách đã báo chuyển khoản. Đối chiếu với sao kê rồi xác nhận: chỗ của họ đang được giữ và đồng hồ đã dừng.",
                           "These guests reported a transfer. Check your statement, then confirm: their seat is held and their clock has stopped."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                if app.verificationsFocusBookingID == nil, overdueCount > 0 {
                    Text("\(overdueCount) " + app.T("khoản đã quá hạn xác nhận.", "past the response window."))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                }

                if app.verificationsFocusBookingID != nil {
                    Button { app.verificationsFocusBookingID = nil } label: {
                        Text(app.T("‹ Xem tất cả", "‹ View all"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(app.palette.ink.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .accessibilityIdentifier("verifications.clearFocus")
                }

                VStack(spacing: 12) {
                    ForEach(visibleVerifications) { row in card(row) }

                    if visibleVerifications.isEmpty {
                        Text(app.verificationsLoading
                             ? app.T("Đang tải…", "Loading…")
                             : app.verificationsFocusBookingID != nil
                             ? app.T("Khoản thanh toán này không còn trong danh sách chờ nữa.", "This payment is no longer in the pending queue.")
                             : app.T("Không có khoản nào đang chờ. Thanh toán khớp nội dung chuyển khoản sẽ được xác nhận tự động.",
                                     "Nothing waiting. Payments that match their reference are confirmed automatically."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("verifications.empty")
                    }
                }
                .padding(.top, 18)

                // Escalated bookings leave the queue above entirely (no
                // longer 'pending_verification') — this is the only place
                // left on this screen to keep talking with the guest while
                // banbe decides. Hidden while focused on one booking
                // (14-organizer-checkin.md) — that view is meant to be
                // exactly one booking's own detail.
                //
                // "Open dispute chat" opens the EXISTING booking conversation
                // with this booking's own dispute card already hung off it,
                // rather than mounting a second, parallel copy of the
                // transcript here — one conversation per booking, and the
                // temporary messages stay in dispute_messages, separate from
                // the permanent ones.
                if app.verificationsFocusBookingID == nil, !app.openDisputes.isEmpty {
                    Text(app.T("Đang chờ banbe quyết định", "Awaiting banbe's decision"))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.top, 24)
                    VStack(spacing: 12) {
                        ForEach(app.openDisputes) { d in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(d.guestName ?? app.T("Khách", "Guest")) ▪︎ \(d.eventName ?? "")")
                                        .font(.system(size: 14)).foregroundStyle(app.palette.ink)
                                    Spacer(minLength: 8)
                                    Text(formatVnd(d.totalVnd)).font(BanbeTheme.display(16))
                                }
                                SwipeSafeButton {
                                    Task { await openDisputeConversation(d.bookingId) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(app.T("Mở chat với khách ›", "Open chat with the goer ›"))
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("verification.openDisputeChat")
                            }
                            .padding(14)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("verification.disputeRow")
                        }
                    }
                    .padding(.top, 12)
                }

                // Flow 2 — refund queue (TASK A/B, 2026-09-30 pass):
                // app.refundQueue now comes from the exact same
                // get_host_refund_claims() RPC + RefundClaim.hasValidDestination
                // /isActiveRefundStatus AttendanceView's Refund Center uses —
                // no more separate "what's actionable" logic that could drift
                // out of sync. activeRefundRows mirrors the old owed/disputed
                // filter; host_marked_sent claims get their own non-actionable
                // "Đang chờ xác nhận" section instead of being silently
                // dropped. Hidden while focused on one verification booking,
                // same reasoning as the dispute section above.
                // Investigation fix — distinguish "still checking whether
                // you organize anything" / "that check failed" / "failed
                // to load" / "genuinely nothing to act on" / "here are the
                // rows." Before this, every one of the first four collapsed
                // to the exact same "render nothing," indistinguishable
                // from the section simply not existing — "do not show
                // failed loading as empty."
                if app.verificationsFocusBookingID == nil {
                    let hasRows = !activeRefundRows.isEmpty || !pendingRefundRows.isEmpty
                    let awaitingOrganizerDiscovery = app.refundQueueGateReason == "awaiting-organizer-discovery"
                    let showLoading = (app.refundQueueLoading || awaitingOrganizerDiscovery) && !hasRows
                    let showError = !app.refundQueueError.isEmpty && !hasRows
                    let showEmpty = !hasRows && !showLoading && !showError
                    VStack(alignment: .leading, spacing: 12) {
                        Text(app.T("Hoàn tiền", "Refunds"))
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink.opacity(0.7))
                            .accessibilityIdentifier("refundQueue.title")
                            .onTapGesture { diagTapCount += 1; if diagTapCount >= 5 { diagTapCount = 0; diagOpen.toggle() } }
                        // Point 1's own explicit requirement — the host does
                        // not create or hold any receiving payment method
                        // here; the GOER already chose/snapshotted their own
                        // destination, the host only reviews it and
                        // transfers externally, then marks sent.
                        if hasRows || showEmpty {
                            Text(app.T(
                                "Khách đã chọn tài khoản nhận hoàn tiền của họ. Bạn chuyển khoản trực tiếp cho khách rồi đánh dấu đã hoàn tiền — không cần tạo phương thức nhận tiền riêng.",
                                "The guest has already chosen their own refund destination. You transfer to them directly, then mark it sent — no receiving payment method of your own is needed here."
                            ))
                            .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                        if showLoading {
                            Text(app.T("Đang tải…", "Loading…")).font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                        if showError {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(app.refundQueueError).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                                Button(app.T("Thử lại", "Retry")) { Task { await app.loadRefundQueue() } }
                                    .font(.system(size: 12.5, weight: .semibold)).underline()
                            }
                        }
                        if showEmpty {
                            Text(app.T("Không có khoản hoàn tiền nào cần xử lý.", "No refunds need action right now."))
                                .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                        }
                        if diagOpen { RefundDiagnosticsPanel() }
                        VStack(spacing: 12) {
                            ForEach(activeRefundRows) { claim in refundRow(claim) }
                            ForEach(pendingRefundRows) { claim in pendingRefundRow(claim) }
                        }
                    }
                    .padding(.top, 24)
                    .id("refundSection")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.verifications")
        .task { await app.loadVerifications() }
        .task { await app.loadOpenDisputes() }
        .task { await app.loadRefundQueue() }
        .onAppear {
            startTicking()
            startRefundQueuePolling()
            // Tapping a 'dispute_message' toast/notification used to land an
            // organizer here with app.chatHighlight set, which this screen
            // turned into an inline chat panel. The transcript now lives in
            // the booking conversation (ChatView), so this opens that
            // conversation with its dispute card attached instead.
            if let bookingID = app.chatHighlight?.bookingID {
                Task { await openDisputeConversation(bookingID) }
            }
            // One-shot scroll-to-refunds (openVerificationsRefunds) —
            // `.scrollPosition(id:)` applies the scroll once this id is
            // set and a matching `.id(...)` exists; clearing it shortly
            // after is enough here (unlike HomeView's own restore-on-
            // return use of this same mechanism, this is a single jump,
            // never re-triggered for the same id on this screen).
            if app.verificationsScrollAnchorID != nil {
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    app.verificationsScrollAnchorID = nil
                }
            }
        }
        .onDisappear { tickTask?.cancel(); refundQueuePollTask?.cancel() }
        .onChange(of: app.chatHighlight?.bookingID) { _, newValue in
            if let newValue { Task { await openDisputeConversation(newValue) } }
        }
    }

    private var activeRefundRows: [RefundClaim] { app.refundQueue.filter(\.isActiveRefundStatus) }
    private var pendingRefundRows: [RefundClaim] { app.refundQueue.filter { $0.status == "host_marked_sent" } }

    /// Open this booking's EXISTING conversation with its dispute card
    /// attached. When no conversation exists for this (event, guest) pair
    /// yet, there is genuinely nowhere to go — say so rather than silently
    /// doing nothing or fabricating a duplicate thread.
    private func openDisputeConversation(_ bookingID: UUID) async {
        if await app.openDisputeForBooking(bookingID, back: app.verificationsBack) { return }
        app.pushToast(AppNotification(
            id: UUID(), recipientId: app.userID ?? UUID(), kind: "stale_notice",
            title: app.T("Chưa có cuộc trò chuyện nào với khách này.", "There's no conversation with this guest yet."),
            body: "", data: [:], readAt: Date(), createdAt: Date()
        ))
    }

    @ViewBuilder
    private func refundRow(_ claim: RefundClaim) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(claim.guestName.isEmpty ? app.T("Khách", "Guest") : claim.guestName)
                        .font(BanbeTheme.display(16))
                    Text(claim.eventName).font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
                Spacer(minLength: 8)
                Text(formatVnd(claim.amountVnd)).font(BanbeTheme.display(19))
            }

            if let snapshot = claim.recipientSnapshot, claim.hasValidDestination {
                RefundRecipientQRView(snapshot: snapshot)
            }

            if claim.status == "disputed" {
                // A disputed claim is not something the host can silently
                // overwrite as "sent" — no action button here, just the
                // visible state and the yellow "Awaiting Verification" entry
                // whose button jumps into the temporary chat both sides now
                // share (migration 129).
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.T("Khách báo chưa nhận được tiền", "Guest reports not receiving this refund"))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("refundQueue.disputed")
                    RefundDisputeEntry(
                        refundClaimId: claim.id,
                        viewer: .host,
                        amountVnd: claim.amountVnd,
                        eventName: claim.eventName,
                        back: app.verificationsBack
                    )
                }
            } else if !claim.hasValidDestination {
                // TASK B — the actual fix for the reported bug: an owed
                // claim with no valid recipient snapshot is NEVER
                // actionable here, exactly like AttendanceView's own Refund
                // Center — never a "Mark refund sent" CTA for it.
                Text(app.T("Khách chưa chọn tài khoản nhận hoàn tiền.", "The guest hasn't chosen a refund destination yet."))
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("refundQueue.needsDestination")
            } else if refundNoteFor == claim.id {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(app.T("Ghi chú/mã tham chiếu (không bắt buộc)", "Note/reference (optional)"), text: $refundNoteText)
                        .font(.system(size: 13))
                        .padding(11)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("refundQueue.note")
                    // Optional proof of the transfer — shown to the guest when
                    // they're asked to confirm they received the money.
                    if let refundProofPreview {
                        Image(uiImage: refundProofPreview)
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityIdentifier("refundQueue.proofPreview")
                    }
                    let proofTitle = refundProofJPEG == nil
                        ? app.T("Đính kèm ảnh chuyển khoản (không bắt buộc)", "Attach transfer proof (optional)")
                        : app.T("Đã chọn ảnh chuyển khoản", "Transfer proof selected")
                    let proofAction = refundProofJPEG == nil ? app.T("Chọn", "Choose") : app.T("Đổi", "Change")
                    let inkColor = app.palette.ink
                    let fieldColor = app.palette.field
                    PhotosPicker(selection: $refundProofItem, matching: .images) {
                        HStack {
                            Text(proofTitle)
                                .font(.system(size: 13)).foregroundStyle(inkColor)
                            Spacer()
                            Text(proofAction)
                                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(inkColor.opacity(0.75))
                        }
                        .padding(11)
                        .background(fieldColor, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityIdentifier("refundQueue.proofPick")
                    .onChange(of: refundProofItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                                refundProofJPEG = ProofImage.jpegDataUnderLimit(from: img)
                                refundProofPreview = img
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        action(
                            app.refundActionBusy == claim.id ? app.T("Đang lưu…", "Saving…") : app.T("Xác nhận", "Confirm"),
                            id: "refundQueue.markSentConfirm"
                        ) {
                            let note = refundNoteText, proof = refundProofJPEG
                            refundNoteFor = nil; refundNoteText = ""
                            refundProofItem = nil; refundProofJPEG = nil; refundProofPreview = nil
                            Task { await app.markRefundSent(claim.id, note: note, proofJPEG: proof) }
                        }
                        .disabled(app.refundActionBusy == claim.id)
                        action(app.T("Huỷ", "Cancel"), ghost: true) {
                            refundNoteFor = nil; refundNoteText = ""
                            refundProofItem = nil; refundProofJPEG = nil; refundProofPreview = nil
                        }
                    }
                }
            } else {
                action(
                    app.refundActionBusy == claim.id ? app.T("Đang lưu…", "Saving…") : app.T("Đã hoàn tiền", "Mark refund sent"),
                    id: "refundQueue.markSent"
                ) { refundNoteFor = claim.id }
            }
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("refundQueue.row")
    }

    @ViewBuilder
    private func pendingRefundRow(_ claim: RefundClaim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(claim.guestName.isEmpty ? app.T("Khách", "Guest") : claim.guestName)
                        .font(BanbeTheme.display(16))
                    Text(claim.eventName).font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
                Spacer(minLength: 8)
                Text(formatVnd(claim.amountVnd)).font(BanbeTheme.display(19))
            }
            Text(app.T("Đang chờ khách xác nhận đã nhận tiền.", "Awaiting guest confirmation."))
                .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
        }
        .padding(14)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("refundQueue.rowPending")
    }

    private func startRefundQueuePolling() {
        refundQueuePollTask?.cancel()
        // Same 6s cadence PaymentDetailsView's own poll already uses
        // elsewhere in this app — not a novel interval.
        refundQueuePollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                await app.loadRefundQueue()
            }
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled {
                tick = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @ViewBuilder
    private func card(_ row: PendingVerification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.guestName ?? app.T("Khách", "Guest")).font(BanbeTheme.display(16))
                    Text("\(row.eventName ?? "") ▪︎ \(row.qty) " + app.T("vé", "tix"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
                Text(formatVnd(row.totalVnd)).font(BanbeTheme.display(19))
            }

            VStack(spacing: 4) {
                line(app.T("Nội dung CK", "Reference"), row.paymentRef ?? app.T("Không Có Thông Tin", "Not Provided"))
                line(app.T("Mã giao dịch", "Transaction ID"), row.transactionId ?? app.T("Không Có Thông Tin", "Not Provided"))
                line(app.T("Đã chờ", "Waiting"), waited(row.proofSubmittedAt))
                if let dueAt = row.verifyDueAt {
                    let secondsLeft = Countdown.secondsUntil(dueAt, now: tick)
                    let overdue = secondsLeft == 0
                    line(
                        overdue ? app.T("Đã quá hạn", "Past due") : app.T("Thời hạn phản hồi", "Response window"),
                        overdue ? app.T("Cần xử lý ngay", "Needs action now") : Countdown.format(secondsLeft),
                        urgent: overdue
                    )
                    .accessibilityIdentifier("verification.slaCountdown")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // The actual receipt/transfer screenshot the guest submitted —
            // this used to be invisible here entirely, leaving "Money
            // received"/"Can't find it" a decision made on the reference and
            // transaction ID text alone, never the evidence itself.
            if let proofPath = row.proofPath {
                if let url = app.proofUrls[proofPath] {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("verification.proofImage")
                } else {
                    Text(app.T("Đang tải ảnh biên lai…", "Loading receipt image…"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityIdentifier("verification.proofLoading")
                }
            }

            // row.disputeReason means "Can't find it" already fired here —
            // reject_payment (migration 041) now opens a dispute_threads
            // row the moment that happens, not only once
            // escalate_payment_dispute runs. That transcript lives in the
            // booking conversation, so this opens it rather than mounting a
            // second inline copy of it here.
            if let reason = row.disputeReason, !reason.isEmpty {
                SwipeSafeButton {
                    Task { await openDisputeConversation(row.bookingId) }
                } label: {
                    HStack(spacing: 4) {
                        Text(app.T("Mở chat với khách ›", "Open chat with the goer ›"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("verification.openNotFoundChat")
            }

            if let current = reasonFor, current.bookingId == row.bookingId {
                TextField(current.kind == .escalate
                          ? app.T("Mô tả ngắn gọn vướng mắc cho banbe", "Briefly describe the issue for banbe")
                          : app.T("Vì sao chưa xác nhận được?", "Why can't you confirm it?"), text: $reason)
                    .font(.system(size: 13)).padding(11)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(current.kind == .escalate
                     ? app.T("banbe sẽ xem xét và đưa ra quyết định. Chỗ của khách vẫn được giữ trong lúc chờ.",
                             "banbe will review and decide. The guest's seat stays held while you wait.")
                     : app.T("Lý do này được gửi thẳng cho khách qua tin nhắn để họ bổ sung, chỗ vẫn được giữ, banbe không tham gia ở bước này.",
                             "This reason goes straight to the guest by chat so they can follow up. The seat stays held, and banbe is not involved at this step."))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                HStack(spacing: 8) {
                    action(app.T("Gửi", "Submit"), id: "verification.rejectConfirm") {
                        let kind = current.kind
                        Task {
                            if kind == .escalate { await app.escalateDispute(row.bookingId, reason: reason) }
                            else { await app.rejectPayment(row.bookingId, reason: reason) }
                        }
                        reasonFor = nil; reason = ""
                    }
                    action(app.T("Huỷ", "Cancel"), ghost: true) { reasonFor = nil; reason = "" }
                }
            } else {
                HStack(spacing: 8) {
                    action(app.verificationBusy == row.bookingId
                           ? app.T("Đang lưu…", "Saving…")
                           : app.T("Đã nhận tiền", "Money received"), id: "verification.approve") {
                        Task { await app.approvePayment(row.bookingId) }
                    }
                    action(app.T("Chưa thấy", "Can't find it"), ghost: true, id: "verification.reject") {
                        reasonFor = (row.bookingId, .reject)
                    }
                }
            }
        }
        .padding(18)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("verification.row")
    }

    private func waited(_ since: Date?) -> String {
        guard let since else { return "—" }
        let mins = max(0, Int(Date().timeIntervalSince(since) / 60))
        if mins < 60 { return "\(mins) " + app.T("phút", "min") }
        return "\(mins / 60)" + app.T(" giờ ", "h ") + "\(mins % 60)" + app.T(" phút", "m")
    }

    private func line(_ label: String, _ value: String, urgent: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(urgent ? BanbeTheme.alert : app.palette.ink)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    private func action(_ title: String, ghost: Bool = false, id: String? = nil,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(ghost ? Color.clear : app.palette.ink,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(ghost ? app.palette.ink : app.palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(ghost ? app.palette.rule : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id ?? title)
    }
}

/// Point 2 of the refund-discoverability investigation — an explicit
/// opt-in diagnostic panel (NOT gated on a DEBUG compiler flag, since the
/// person reproducing this is testing against a real Release/PersonalTeamDebug
/// build on a physical iPhone) that answers exactly the questions that
/// distinguish "hidden by a client gate," "still loading," "failed," and
/// "genuinely empty" from each other, without ever logging a JWT/refresh
/// token/password/bank detail/email code or a full response payload.
/// Toggled by 5 taps on the "Hoàn tiền" section title.
private struct RefundDiagnosticsPanel: View {
    @EnvironmentObject private var app: AppState
    @State private var authUserID = "(checking…)"

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10, design: .monospaced)).opacity(0.6)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 10, design: .monospaced)).multilineTextAlignment(.trailing)
        }
    }

    var body: some View {
        let activeCount = app.refundQueue.filter(\.isActiveRefundStatus).count
        let pendingCount = app.refundQueue.filter { $0.status == "host_marked_sent" }.count
        VStack(alignment: .leading, spacing: 4) {
            Text("DIAGNOSTICS (refund queue)").font(.system(size: 9.5, weight: .bold)).foregroundStyle(BanbeTheme.alert)
            // auth.user() re-verifies against the server (not just the
            // locally cached session) — the one value a raw SQL Editor
            // auth.uid() can never actually confirm, since that only
            // proves what the query editor's OWN session is.
            row("auth.user() id", authUserID)
            row("app-state user id", app.userID?.uuidString ?? "(nil)")
            row("profile role (accountType)", app.accountType)
            row("organizerMode", String(app.organizerMode))
            row("supabase host", URL(string: AppConfig.supabaseURL)?.host ?? "(unknown)")
            row("myOrganizerIdsStatus", app.myOrganizerIdsStatus)
            row("myOrganizerIDs", app.myOrganizerIDs.description)
            row("refundQueueLoading", String(app.refundQueueLoading))
            row("refundQueueGateReason", app.refundQueueGateReason.isEmpty ? "(never set)" : app.refundQueueGateReason)
            row("refundQueueError (user-facing)", app.refundQueueError.isEmpty ? "(none)" : app.refundQueueError)
            row("RPC call shape", "get_host_refund_claims(pEventId: nil)")
            row("failed stage", app.refundQueueErrorStage.isEmpty ? "(no failure)" : app.refundQueueErrorStage)
            row("server error code", app.refundQueueErrorCode.isEmpty ? "(none)" : app.refundQueueErrorCode)
            row("server error message", app.refundQueueErrorMessage.isEmpty ? "(none)" : app.refundQueueErrorMessage)
            row("refundQueue ids+status", app.refundQueue.map { "\($0.id):\($0.status)" }.joined(separator: ", "))
            row("presentation (active/pending)", "\(activeCount) / \(pendingCount)")
            row("verificationsFocusBookingID", app.verificationsFocusBookingID?.uuidString ?? "(nil)")
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(BanbeTheme.alert, style: StrokeStyle(lineWidth: 1, dash: [4])))
        .task {
            if let user = try? await SupabaseService.client.auth.user() {
                authUserID = user.id.uuidString
            } else {
                authUserID = "(no session / error)"
            }
        }
    }
}

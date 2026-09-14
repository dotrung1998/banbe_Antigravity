import SwiftUI

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
    @State private var openChatBookingID: UUID?

    private enum ReasonKind { case reject, escalate }

    private var overdueCount: Int { app.verifications.filter { $0.overdue == true }.count }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)
                    .accessibilityIdentifier("verifications.back")

                Text(app.T("Chờ xác nhận", "Awaiting verification"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityIdentifier("verifications.title")
                Text(app.T("Khách đã báo chuyển khoản. Đối chiếu với sao kê rồi xác nhận — chỗ của họ đang được giữ và đồng hồ đã dừng.",
                           "These guests reported a transfer. Check your statement, then confirm — their seat is held and their clock has stopped."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                if overdueCount > 0 {
                    Text("\(overdueCount) " + app.T("khoản đã quá hạn xác nhận.", "past the response window."))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                }

                VStack(spacing: 12) {
                    ForEach(app.verifications) { row in card(row) }

                    if app.verifications.isEmpty {
                        Text(app.verificationsLoading
                             ? app.T("Đang tải…", "Loading…")
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
                // banbe decides.
                if !app.openDisputes.isEmpty {
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
                                if openChatBookingID == d.bookingId {
                                    DisputeChatPanel(bookingID: d.bookingId)
                                } else {
                                    Button { openChatBookingID = d.bookingId } label: {
                                        Text(app.T("Mở đoạn chat tranh chấp ›", "Open dispute chat ›"))
                                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("verification.openDisputeChat")
                                }
                            }
                            .padding(14)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityIdentifier("verification.disputeRow")
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.verifications")
        .task { await app.loadVerifications() }
        .task { await app.loadOpenDisputes() }
        .onAppear { startTicking() }
        .onDisappear { tickTask?.cancel() }
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
                line(app.T("Nội dung CK", "Reference"), row.paymentRef ?? "—")
                line(app.T("Mã giao dịch", "Transaction ID"), row.transactionId ?? "—")
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

            if let current = reasonFor, current.bookingId == row.bookingId {
                TextField(current.kind == .escalate
                          ? app.T("Mô tả ngắn gọn vướng mắc cho banbe", "Briefly describe the issue for banbe")
                          : app.T("Vì sao chưa xác nhận được?", "Why can't you confirm it?"), text: $reason)
                    .font(.system(size: 13)).padding(11)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(current.kind == .escalate
                     ? app.T("banbe sẽ xem xét và đưa ra quyết định — chỗ của khách vẫn được giữ trong lúc chờ.",
                             "banbe will review and decide — the guest's seat stays held while you wait.")
                     : app.T("Lý do này được gửi thẳng cho khách qua tin nhắn để họ bổ sung — chỗ vẫn được giữ, banbe không tham gia ở bước này.",
                             "This reason goes straight to the guest by chat so they can follow up — the seat stays held, and banbe is not involved at this step."))
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
                // Deliberately separate from "Can't find it" — that's just
                // feedback to the guest. This is the one action that
                // actually brings banbe in, for when the two of you
                // genuinely can't resolve it directly.
                Button {
                    reasonFor = (row.bookingId, .escalate)
                } label: {
                    Text(app.T("Không tự giải quyết được ▪︎ chuyển cho banbe", "Can't resolve it directly ▪︎ escalate to banbe"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("verification.escalate")
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

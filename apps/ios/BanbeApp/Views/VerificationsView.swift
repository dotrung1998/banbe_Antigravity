import SwiftUI

/// The organizer's manual-verification queue — the fallback for whatever the
/// bank webhook didn't reconcile on its own. Oldest first: this is a queue
/// people are waiting in, and the longest wait is the closest to giving up.
struct VerificationsView: View {
    @EnvironmentObject private var app: AppState
    @State private var rejecting: UUID?
    @State private var reason = ""
    @State private var tickTask: Task<Void, Never>?
    @State private var tick = Date()

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
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.verifications")
        .task { await app.loadVerifications() }
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

            if rejecting == row.bookingId {
                TextField(app.T("Vì sao chưa xác nhận được?", "Why can't you confirm it?"), text: $reason)
                    .font(.system(size: 13)).padding(11)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(app.T("Chỗ của khách vẫn được giữ và banbe sẽ xem xét — từ chối không huỷ vé ngay.",
                           "The guest's seat stays held and banbe will review it — rejecting does not cancel them outright."))
                    .font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.7))
                HStack(spacing: 8) {
                    action(app.T("Gửi", "Submit"), id: "verification.rejectConfirm") {
                        Task { await app.rejectPayment(row.bookingId, reason: reason) }
                        rejecting = nil; reason = ""
                    }
                    action(app.T("Huỷ", "Cancel"), ghost: true) { rejecting = nil; reason = "" }
                }
            } else {
                HStack(spacing: 8) {
                    action(app.verificationBusy == row.bookingId
                           ? app.T("Đang lưu…", "Saving…")
                           : app.T("Đã nhận tiền", "Money received"), id: "verification.approve") {
                        Task { await app.approvePayment(row.bookingId) }
                    }
                    action(app.T("Chưa thấy", "Can't find it"), ghost: true, id: "verification.reject") {
                        rejecting = row.bookingId
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

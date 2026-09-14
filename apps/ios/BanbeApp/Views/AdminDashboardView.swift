import SwiftUI

/// Platform admin dispute desk — the iOS counterpart of src/screens/Disputes.jsx.
/// Reachable only via AccountView's admin-gated "Admin Panel" row
/// (app.isAdmin), and openAdminDashboard() itself guards again before
/// switching screens — RLS (v_disputes, resolve_dispute, payment_audit_log,
/// the 'pay-proof' bucket) is the real backstop either way.
///
/// Shows the buyer's evidence (receipt image, reference, transaction id)
/// and the full T1/T2/T3 audit trail side by side, because that trail is
/// the only thing here neither party could have edited after the fact.
struct AdminDashboardView: View {
    @EnvironmentObject private var app: AppState
    @State private var note = ""
    @State private var openChatBookingID: UUID?

    private var open: [DisputeRow] { app.adminDisputes.filter { $0.disputeResolvedAt == nil } }
    private var closed: [DisputeRow] { app.adminDisputes.filter { $0.disputeResolvedAt != nil } }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }
                    .padding(.top, 8)
                    .accessibilityIdentifier("admin.back")

                Text(app.T("Tranh chấp thanh toán", "Payment disputes"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityIdentifier("admin.title")
                Text(app.T("Khách khẳng định đã chuyển, người tổ chức không tìm thấy. Chỗ vẫn đang bị khoá cho tới khi có quyết định.",
                           "The guest says they paid; the organizer can't find it. The seat stays locked until this is decided."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(open) { row in disputeCard(row) }

                    if open.isEmpty {
                        Text(app.adminDisputesLoading
                             ? app.T("Đang tải…", "Loading…")
                             : app.T("Không có tranh chấp nào đang mở.", "No open disputes."))
                            .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("admin.empty")
                    }

                    if !closed.isEmpty {
                        Text(app.T("Đã xử lý", "Resolved"))
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(closed) { row in
                            HStack {
                                Text("\(row.paymentRef ?? "") ▪︎ \(row.guestName ?? "")")
                                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                                Spacer(minLength: 8)
                                Text(row.disputeResolution?.isEmpty == false ? row.disputeResolution! : app.T("đã xử lý", "resolved"))
                                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.6))
                            }
                            .padding(12)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.top, 18)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .accessibilityIdentifier("screen.adminDashboard")
        .task { await app.loadAdminDisputes() }
    }

    @ViewBuilder
    private func disputeCard(_ row: DisputeRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.guestName ?? app.T("Khách", "Guest")).font(BanbeTheme.display(16))
                    Text("\(row.eventName ?? "") ▪︎ \(row.organizerName ?? "")")
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                }
                Spacer(minLength: 0)
                Text(formatVnd(row.totalVnd)).font(BanbeTheme.display(19))
            }

            VStack(spacing: 4) {
                line(app.T("Nội dung CK", "Reference"), row.paymentRef ?? "—")
                line(app.T("Mã giao dịch khách khai", "Buyer transaction ID"), row.transactionId ?? "—")
                line(app.T("Lý do từ chối", "Rejection reason"), row.disputeReason?.isEmpty == false ? row.disputeReason! : "—")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // The actual evidence, not just "on file" — ruling on a dispute
            // between two people who disagree needs to see the receipt
            // itself, not take either side's word for its existence.
            if let proofPath = row.proofPath {
                if let url = app.proofUrls[proofPath] {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() } else { Color.clear }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("admin.proofImage")
                } else {
                    Text(app.T("Đang tải ảnh biên lai…", "Loading receipt image…"))
                        .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Button {
                if app.auditBookingId == row.bookingId { app.auditBookingId = nil }
                else { Task { await app.loadAuditTrail(row.bookingId) } }
            } label: {
                Text(app.T("Xem nhật ký T1/T2/T3 ›", "View T1/T2/T3 trail ›"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("admin.auditOpen")

            if app.auditBookingId == row.bookingId && !app.auditTrail.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(app.auditTrail) { a in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.action).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            Text(a.at.formatted() + (a.actorKind.map { " ▪︎ \($0)" } ?? ""))
                                .font(.system(size: 10.5)).foregroundStyle(app.palette.ink.opacity(0.65))
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("admin.auditTrail")
            }

            if openChatBookingID == row.bookingId {
                DisputeChatPanel(bookingID: row.bookingId)
            } else {
                Button { openChatBookingID = row.bookingId } label: {
                    Text(app.T("Xem đoạn chat giữa khách và người tổ chức ›", "View the guest/organizer chat ›"))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("admin.openChat")
            }

            TextField(app.T("Ghi chú quyết định", "Resolution note"), text: $note)
                .font(.system(size: 13)).padding(11)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("admin.note")

            HStack(spacing: 8) {
                actionButton(app.disputeBusy == row.bookingId
                             ? app.T("Đang lưu…", "Saving…")
                             : app.T("Khách đúng ▪︎ cấp vé", "Buyer is right ▪︎ issue ticket"),
                             id: "admin.uphold") {
                    Task { await app.resolveDispute(row.bookingId, uphold: true, note: note); note = "" }
                }
                actionButton(app.T("Mở lại chỗ", "Release seat"), ghost: true, id: "admin.release") {
                    Task { await app.resolveDispute(row.bookingId, uphold: false, note: note); note = "" }
                }
            }

            if !app.disputeEmailError.isEmpty {
                Text(app.T("Email xác nhận chưa gửi được: ", "Confirmation email didn't send: ") + app.disputeEmailError)
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("admin.emailError")
            }
        }
        .padding(16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("admin.disputeRow")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(app.palette.ink.opacity(0.65))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func actionButton(_ title: String, ghost: Bool = false, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(ghost ? Color.clear : app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(ghost ? app.palette.ink : app.palette.paper)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ghost ? app.palette.rule : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

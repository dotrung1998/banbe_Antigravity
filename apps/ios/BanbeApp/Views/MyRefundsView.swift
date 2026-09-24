import SwiftUI

/// Refund MVP (product rule A) — a persistent list of every active refund
/// claim for the signed-in goer, reachable from Account and Payment &
/// refund accounts, independent of any notification.
struct MyRefundsView: View {
    @EnvironmentObject private var app: AppState
    @State private var pollTask: Task<Void, Never>?

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "owed": return app.T("Khoản hoàn tiền này đang cần được xử lý", "This refund is still being processed")
        case "host_marked_sent": return app.T("Đang chờ bạn xác nhận đã nhận tiền", "Awaiting your confirmation")
        case "disputed": return app.T("Đang tranh chấp", "Disputed")
        default: return "—"
        }
    }

    private func isOverdue(_ c: RefundClaim) -> Bool {
        (c.status == "owed" && (c.refundDueAt.map { $0 < Date() } ?? false))
            || (c.status == "disputed" && (c.hostResponseDueAt.map { $0 < Date() } ?? false))
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.backFromMyRefunds() }

                Text(app.T("Hoàn tiền", "Refunds")).font(BanbeTheme.display(24)).padding(.top, 14)
                Text(app.T("Các khoản hoàn tiền đang cần xử lý của bạn.", "Your refund claims that are still active."))
                    .font(.system(size: 12.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                if app.myRefunds.isEmpty {
                    Text(app.myRefundsLoading ? app.T("Đang tải…", "Loading…") : app.T("Không có khoản hoàn tiền nào đang xử lý.", "No refunds in progress."))
                        .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .center)
                        .padding(20).background(app.palette.field, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(app.myRefunds) { c in
                            Button {
                                if let bookingID = c.bookingId ?? c.reservationId {
                                    app.paymentBookingID = bookingID
                                    app.screen = .paymentDetails
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(c.eventName.isEmpty ? app.T("Sự kiện", "Event") : c.eventName).font(BanbeTheme.display(14))
                                        Spacer()
                                        Text(formatVnd(c.amountVnd)).font(.system(size: 13, weight: .semibold))
                                    }
                                    Text(isOverdue(c) ? app.T("Quá hạn hoàn tiền.", "Refund overdue.") : statusLabel(c.status))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(isOverdue(c) ? BanbeTheme.alert : app.palette.ink.opacity(0.7))
                                }
                                .foregroundStyle(app.palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(14)
                            if c.id != app.myRefunds.last?.id { Divider().overlay(app.palette.rule) }
                        }
                    }
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 40)
        }
        .onAppear {
            Task { await app.loadMyRefunds() }
            pollTask?.cancel()
            pollTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if Task.isCancelled { return }
                    await app.loadMyRefunds()
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
    }
}

import SwiftUI

/// Port of src/screens/Refunded.jsx — shown for a saved event the organizer
/// cancelled: what was refunded, and a way to ask them about it.
struct RefundedView: View {
    @EnvironmentObject var app: AppState

    private var event: CatalogEvent { app.currentEvent }
    private var refundAmount: String {
        event.isFree ? app.T("Miễn phí", "Free")
                     : EventLabels.vnd(event.priceVnd * (app.tickets[event.key] ?? 1))
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.T("Sự kiện đã hủy", "Event cancelled")).font(.system(size: 11.5))
                        Text(app.T("Đừng lo, tiền của bạn đã về túi rồi!", "No worries, you're already refunded!"))
                            .font(BanbeTheme.display(27))
                            .padding(.top, 12)
                        Text(app.T(
                            "Người tổ chức đã hủy sự kiện này. Tiền đã tự động hoàn về phương thức thanh toán ban đầu, bạn không cần làm gì thêm. Buổi sau nhé!",
                            "The organizer cancelled this one. Your payment was automatically refunded, nothing else to do. See you at the next one!"
                        ))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .padding(.top, 18)

                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.T("Số tiền hoàn", "Amount refunded"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(app.T("Về phương thức thanh toán ban đầu, 3–5 ngày làm việc",
                                           "To your original payment method, 3–5 business days"))
                                    .font(.system(size: 11.5))
                            }
                            Spacer(minLength: 0)
                            Text(refundAmount).font(BanbeTheme.display(24))
                        }
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 24)

                        Divider().overlay(app.palette.rule).padding(.top, 28)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.name).font(BanbeTheme.display(17))
                            Text(app.trStatus(app.stripKm(event.where, event: event))).font(.system(size: 12))
                            if let hours = event.cancelledHoursAgo {
                                Text(app.trStatus(EventLabels.ago(hours))
                                     + app.T(" ▪︎ người tổ chức đã hủy", " ▪︎ cancelled by the organizer"))
                                    .font(.system(size: 11.5))
                            }
                        }
                        .padding(.top, 14)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 30)
                    .padding(.top, 30)
                }

                VStack(spacing: 0) {
                    Divider().overlay(app.palette.rule)
                    Button(app.T("Có câu hỏi? Nhắn cho ", "Questions? Message ") + event.hostShort) { app.goChat() }
                        .font(.system(size: 13.5))
                        .foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                    Divider().overlay(app.palette.rule)
                    Button(app.T("Về trang chính", "Back to home")) { app.goHome() }
                        .font(.system(size: 13.5))
                        .foregroundStyle(app.palette.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

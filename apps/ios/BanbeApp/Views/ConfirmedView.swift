import SwiftUI

/// Port of src/screens/Confirmed.jsx — the ticket: hold countdown while the
/// booking is still pending, the entry code, and a real scannable QR of the
/// booking id (the same value the organizer's scanner reads).
///
/// The QR/entry-code ticket only ever shows once `booking.paidMarkedAt` is
/// set — never off `booking.status` alone. Every seeded demo event uses
/// 'instant' approval, which marks a booking 'confirmed' the moment it's
/// created; gating on status was exactly what let this screen show a ticket
/// before anyone had paid anything.
struct ConfirmedView: View {
    @EnvironmentObject var app: AppState
    @State private var pollTask: Task<Void, Never>?

    private var event: CatalogEvent { app.currentEvent }
    private var isPaid: Bool { app.booking?.paidMarkedAt != nil }
    private var awaitingPayment: Bool { app.booking != nil && !isPaid }
    private var holdActive: Bool {
        !isPaid && app.booking?.status == "pending" && (app.holdDeadline ?? .distantPast) > app.now
    }
    private var countdown: String {
        let remaining = max(0, Int((app.holdDeadline ?? app.now).timeIntervalSince(app.now)))
        return String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }
    private var guestName: String {
        let typed = app.formName.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? app.T("Bạn", "You") : typed
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isPaid ? app.T("Đã xác nhận", "Confirmed")
                             : holdActive ? app.T("Đang giữ chỗ cho bạn", "Holding your spot")
                             : app.T("Đang chờ thanh toán", "Awaiting payment"))
                            .font(.system(size: 11.5))

                        Text(guestName + (isPaid
                            ? app.T(", vé của bạn đã sẵn sàng.", ", your ticket is ready.")
                            : holdActive
                                ? app.T(", chỗ của bạn đang được giữ.", ", your spot is being held.")
                                : app.T(", hoàn tất thanh toán để nhận vé.", ", complete payment to get your ticket.")))
                            .font(BanbeTheme.display(27))
                            .padding(.top, 12)

                        Text(app.T(
                            "banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
                            "banbe does not collect money. Pay the organizer directly using the instructions in chat; if they cancel, they are responsible for your refund."
                        ))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .padding(.top, 18)

                        if holdActive {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.T("Giữ chỗ còn", "Hold expires in"))
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(app.T("Trả trước khi hết giờ để xác nhận", "Pay before it runs out to confirm"))
                                        .font(.system(size: 11.5))
                                }
                                Spacer()
                                Text(countdown).font(BanbeTheme.display(30)).monospacedDigit()
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 22)
                        }

                        if awaitingPayment, let bookingID = app.booking?.id {
                            Button {
                                app.openPaymentDetails(bookingID, back: .confirmed)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.T("Xem thông tin chuyển khoản", "See payment details"))
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Text(app.T("Số tài khoản, số tiền và nội dung cần ghi.",
                                                   "Account number, amount and the reference to use."))
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(app.palette.ink.opacity(0.7))
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Text("›").font(.system(size: 17))
                                }
                                .foregroundStyle(app.palette.ink)
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, holdActive ? 12 : 22)
                            .accessibilityIdentifier("confirmed.pay")
                        }

                        Divider().overlay(app.palette.rule).padding(.top, 28)

                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.name).font(BanbeTheme.display(17))
                                Text(app.trStatus(app.stripKm(event.where, event: event))).font(.system(size: 12))
                                if isPaid, let code = app.booking?.code {
                                    Text(app.T("Mã vào cửa: ", "Entry code: ") + code)
                                        .font(.system(size: 12, weight: .semibold))
                                        .kerning(1.5)
                                } else if !isPaid {
                                    Text(app.T("Vé sẽ hiện ở đây sau khi thanh toán được xác nhận.",
                                               "Your ticket appears here once payment is confirmed."))
                                        .font(.system(size: 11.5))
                                }
                                if isPaid {
                                    Text(app.T("Đưa mã này ở cửa", "Show this code at the door"))
                                        .font(.system(size: 10.5))
                                }
                            }
                            Spacer(minLength: 0)
                            if isPaid, let booking = app.booking {
                                QRCodeImage(value: booking.id.uuidString)
                            }
                        }
                        .padding(.top, 14)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 0) {
                    if isPaid {
                        footerButton(app.T("Tặng vé cho bạn bè", "Give a ticket to a friend")) { giveTicket() }
                    }
                    footerButton(app.calAdded ? app.T("Đã thêm vào lịch", "Added to calendar")
                                              : app.T("Thêm vào lịch", "Add to calendar")) {
                        app.addToCalendar()
                    }
                    footerButton(app.T("Về trang chính", "Back to home")) { app.goHome() }
                }
            }
        }
        .onAppear { startPollingIfNeeded() }
        .onChange(of: app.booking?.id) { _, _ in startPollingIfNeeded() }
        .onChange(of: isPaid) { _, paid in if paid { pollTask?.cancel() } }
        .onDisappear { pollTask?.cancel() }
    }

    /// While the booking is sitting unpaid, poll for the organizer having
    /// confirmed it — the guest may already be looking at this screen when
    /// that happens, and shouldn't have to leave and come back via the
    /// notification to see the ticket unlock.
    private func startPollingIfNeeded() {
        pollTask?.cancel()
        guard let bookingID = app.booking?.id, !isPaid else { return }
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                guard app.booking?.id == bookingID, app.booking?.paidMarkedAt == nil else { return }
                if let fresh: Booking = try? await SupabaseService.client
                    .from("bookings").select().eq("id", value: bookingID.uuidString)
                    .single().execute().value,
                   fresh.paidMarkedAt != nil, app.booking?.id == bookingID {
                    app.booking = fresh
                    return
                }
            }
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(app.palette.rule)
            Button(action: action) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(app.palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
            }
            .buttonStyle(.plain)
        }
    }

    private func giveTicket() {
        guard let url = URL(string: "https://banbe.app/ve/\(event.key)-x7f2") else { return }
        let text = app.T("Mình có vé cho bạn", "I have a ticket for you")
        let activity = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(activity, animated: true)
    }
}

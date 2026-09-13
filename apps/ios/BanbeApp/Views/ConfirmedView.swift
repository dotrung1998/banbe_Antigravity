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
    // payment_state is the source of truth for every phase distinction
    // below — never booking.status/paidMarkedAt alone, which is the
    // pre-state-machine model this screen used to read exclusively.
    private var phase: PaymentPhase { app.booking?.paymentState ?? .holding }
    private var isPaid: Bool { phase == .confirmed || app.booking?.paidMarkedAt != nil }
    private var isHolding: Bool { app.booking != nil && phase == .holding }
    private var isPendingVerification: Bool { phase == .pendingVerification }
    private var isDisputed: Bool { phase == .disputed }
    private var awaitingPayment: Bool { app.booking != nil && !isPaid }
    private var holdDeadline: Date? { app.booking?.holdExpiresAt ?? app.holdDeadline }
    private var countdown: String {
        Countdown.format(Countdown.secondsUntil(holdDeadline, now: app.now))
    }
    private var verifySecondsLeft: TimeInterval {
        Countdown.secondsUntil(app.booking?.verifyDueAt, now: app.now)
    }
    private var verifyOverdue: Bool { app.booking?.verifyDueAt != nil && verifySecondsLeft == 0 }
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
                             : isHolding ? app.T("Đang giữ chỗ cho bạn", "Holding your spot")
                             : isPendingVerification ? app.T("Đang chờ xác nhận", "Awaiting confirmation")
                             : isDisputed ? app.T("Đang được xem xét", "Under review")
                             : app.T("Đang chờ thanh toán", "Awaiting payment"))
                            .font(.system(size: 11.5))

                        Text(guestName + (isPaid
                            ? app.T(", vé của bạn đã sẵn sàng.", ", your ticket is ready.")
                            : isHolding
                                ? app.T(", chỗ của bạn đang được giữ.", ", your spot is being held.")
                                : isPendingVerification
                                    ? app.T(", chỗ của bạn đã được khoá.", ", your seat is locked.")
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

                        if isHolding {
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
                            .accessibilityIdentifier("confirmed.holdCountdown")
                        }

                        // PHASE 2: the buyer's own clock is gone — replaced
                        // by a reassurance countdown for the organizer's own
                        // response window, framed so it never reads as a
                        // threat to the seat itself.
                        if isPendingVerification {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.T("Chỗ đã khoá ▪︎ không còn đếm ngược cho bạn",
                                                   "Seat locked ▪︎ no countdown against you"))
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text(verifyOverdue
                                             ? app.T("Người tổ chức đang xử lý — có thể mất thêm chút thời gian",
                                                     "The organizer is on it — may take a little longer")
                                             : app.T("Người tổ chức thường phản hồi trong",
                                                     "The organizer typically responds within"))
                                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.75))
                                    }
                                    Spacer(minLength: 8)
                                    if !verifyOverdue, app.booking?.verifyDueAt != nil {
                                        Text(Countdown.format(verifySecondsLeft))
                                            .font(BanbeTheme.display(24)).monospacedDigit()
                                    }
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 22)
                            .accessibilityIdentifier("confirmed.verifyCountdown")
                        }

                        if isDisputed {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(app.T("banbe đang xem xét", "banbe is reviewing this"))
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text(app.T("Chỗ của bạn vẫn được giữ trong lúc chờ xem xét.",
                                           "Your seat stays held while this is reviewed."))
                                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.75))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 22)
                            .accessibilityIdentifier("confirmed.disputed")
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
                            .padding(.top, (isHolding || isPendingVerification || isDisputed) ? 12 : 22)
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
        .onChange(of: phase) { _, newPhase in
            if newPhase == .confirmed { pollTask?.cancel() } else { startPollingIfNeeded() }
        }
        .onDisappear { pollTask?.cancel() }
        // app.now ticks every second app-wide, which is what drives
        // `countdown` above — the moment it notices this screen's own
        // deadline has passed while still 'holding', forfeit immediately
        // rather than leave the ticket sitting stale until the next poll or
        // the minutely server sweep gets to it. Self-guards against firing
        // twice: forfeitExpiredHold flips booking.paymentState to .expired,
        // so `isHolding` (derived from `phase`) is false on the very next tick.
        .onChange(of: app.now) { _, _ in
            if isHolding, let deadline = holdDeadline, Countdown.secondsUntil(deadline, now: app.now) == 0,
               let current = app.booking {
                app.forfeitExpiredHold(current)
            }
        }
    }

    /// While the booking is sitting unpaid, poll for a phase change — the
    /// organizer confirming, the bank webhook matching, or the guest
    /// freezing it from PaymentDetailsView on another screen. The guest may
    /// already be looking at this exact screen when any of those happen, and
    /// shouldn't have to leave and come back via a notification to see it
    /// update. Generalised to sync the whole row (not just paidMarkedAt) so
    /// PHASE 1 -> PHASE 2 shows up live here too.
    private func startPollingIfNeeded() {
        pollTask?.cancel()
        guard let bookingID = app.booking?.id, phase != .confirmed else { return }
        let phaseAtStart = phase
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                guard app.booking?.id == bookingID, app.booking?.paymentState == phaseAtStart else { return }
                if let fresh: Booking = try? await SupabaseService.client
                    .from("bookings").select().eq("id", value: bookingID.uuidString)
                    .single().execute().value,
                   fresh.paymentState != phaseAtStart, app.booking?.id == bookingID {
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

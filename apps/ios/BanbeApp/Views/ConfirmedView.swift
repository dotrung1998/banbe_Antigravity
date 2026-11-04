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
    // Bug 1 (15-organizer-checkin.md follow-up): a separate poll from
    // `pollTask` above — different stop condition (runs until a receipt is
    // actually found, not until the payment phase changes) — matching this
    // app's established polling convention elsewhere (AttendanceView's own
    // 6s poll, 41340ee; PaymentViews' 6s poll).
    @State private var receiptPollTask: Task<Void, Never>?
    /// Note 44 — Apple Calendar goes through the system editor (no access request).
    @State private var appleCalendarRequest: CalendarExportRequest?
    @State private var walletDesignOpen = false
    /// Attendee tickets ticked for download (migration 151).
    @State private var selectedAttendeeIDs: Set<UUID> = []
    /// ticket_opened is counted once per confirmed ticket shown (migration 196).
    @State private var ticketOpenedFor: UUID?
    // Phase 1 quick wins (Lib/QuickWins.swift). Q1/Q4: the moment shown for this booking (once per booking per device).
    @State private var moment: (kind: MomentKind, bookingID: UUID)?
    // Q2: this host's typical confirmation time, asked once per screen open.
    @State private var typicalWait: (vi: String, en: String)?
    @State private var waitAskedFor: UUID?
    // Q1 "Next": venue address + the host's own note, read once per ticket.
    @State private var nextInfo = AppState.TicketNextInfo()
    @State private var nextInfoFor: UUID?
    // Q4: while the event is about to start or under way, watch for the door scan (6s, like the polls below).
    @State private var doorPollTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum MomentKind { case ticket, checkIn }

    private var event: CatalogEvent { app.currentEvent }
    /// This booking's named tickets, once loaded. Empty for a booking made
    /// before per-attendee tickets, which keeps its single booking-level QR.
    private var attendees: [BookingAttendee] {
        guard let id = app.booking?.id else { return [] }
        return app.bookingAttendees.filter { $0.bookingId == id }
    }
    private var hasNamedAttendees: Bool { !attendees.isEmpty }
    // payment_state is the source of truth for every phase distinction
    // below — never booking.status/paidMarkedAt alone, which is the
    // pre-state-machine model this screen used to read exclusively.
    private var phase: PaymentPhase { app.booking?.paymentState ?? .holding }
    // TASK B (2026-10-01 UX foundation pass) — Booking.isTicket is the one
    // shared rule (status AND payment_state both "confirmed"); the
    // paidMarkedAt fallback below is for a booking decoded before
    // payment_state existed and must ALSO require status == "confirmed" —
    // it previously didn't, which could read a disputed/cancelled booking
    // that once had paidMarkedAt set as still "paid".
    private var isPaid: Bool {
        guard let booking = app.booking else { return false }
        // A checked-in booking is "attended" (check_in_guest, migration 021) and is still the same paid ticket.
        return booking.isTicket || (booking.paidMarkedAt != nil && booking.status == "confirmed")
            || (booking.status == "attended" && booking.paymentState == .confirmed)
    }
    private var checkedIn: Bool { isPaid && QuickWins.isCheckedIn(app.booking, attendees: attendees) }
    private var shownMoment: MomentKind? { moment?.bookingID == app.booking?.id ? moment?.kind : nil }
    private var isHolding: Bool { app.booking != nil && phase == .holding }
    private var isPendingVerification: Bool { phase == .pendingVerification }
    private var isDisputed: Bool { phase == .disputed }
    private var isExpired: Bool { phase == .expired }
    private var awaitingPayment: Bool { app.booking != nil && !isPaid && !isExpired }
    /// Booking journey step (note 48); hidden for expired/disputed bookings,
    /// which have left the happy path.
    private var journeyStep: Int? {
        // Only while the booking is still on its way: once the ticket is issued (paid/confirmed, gifted tickets
        // included) the journey is over, so the progress bar goes away, like any finished checkout.
        guard app.booking != nil, !isExpired, !isDisputed, !isPaid else { return nil }
        if isPendingVerification { return 3 }
        return 2
    }
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
                // Back, top-left, where the thumb and the OS convention expect
                // it. Names the destination (honours confirmedBack) instead of
                // the old bottom row that read "Back to home".
                HStack {
                    Button {
                        app.screen = app.confirmedBack
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                            Text(app.confirmedBack == .notifications ? app.T("Thông báo", "Notifications")
                                 : app.confirmedBack == .accountGroup ? app.T("Tài khoản", "Account")
                                 : app.T("Quay lại", "Back"))
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(.vertical, 8).padding(.trailing, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("confirmed.back")
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let journeyStep {
                            BookingJourneyProgress(current: journeyStep)
                                .padding(.bottom, 16)
                        }
                        Text(isPaid ? app.T("Đã xác nhận", "Confirmed")
                             : isHolding ? app.T("Đang giữ chỗ cho bạn", "Holding your spot")
                             : isPendingVerification ? app.T("Đang chờ xác nhận", "Awaiting confirmation")
                             : isDisputed ? app.T("Đang được xem xét", "Under review")
                             : isExpired ? app.T("Đã hết hạn giữ chỗ", "Hold expired")
                             : app.T("Đang chờ thanh toán", "Awaiting payment"))
                            .font(.system(size: 11.5))

                        Text(guestName + (isPaid
                            ? app.T(", vé của bạn đã sẵn sàng.", ", your ticket is ready.")
                            : isHolding
                                ? app.T(", chỗ của bạn đang được giữ.", ", your spot is being held.")
                                : isPendingVerification
                                    ? app.T(", chỗ của bạn đã được khoá.", ", your seat is locked.")
                                    : isExpired
                                        ? app.T(", chỗ giữ đã hết hạn và đã được mở lại.",
                                                ", your hold expired and the seat's been released.")
                                        : app.T(", hoàn tất thanh toán để nhận vé.", ", complete payment to get your ticket.")))
                            .font(BanbeTheme.display(27))
                            .padding(.top, 12)

                        Text(isExpired
                            ? app.T("Bạn chưa chuyển khoản trước khi hết giờ giữ chỗ, nên chỗ đã được mở lại cho người khác. Bạn có thể giữ chỗ lại nếu vẫn còn chỗ trống.",
                                    "You didn't complete payment before the hold ran out, so the seat was released back. You can reserve again if there's still room.")
                            : app.T(
                                "banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
                                "banbe does not collect money. Pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund."
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
                                             ? app.T("Người tổ chức đang xử lý, có thể mất thêm chút thời gian",
                                                     "The organizer is on it, may take a little longer")
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

                            // Q2 honest waiting: what happens next, and this host's typical time when it's real data.
                            VStack(alignment: .leading, spacing: 6) {
                                Text(app.T("Tiếp theo là gì", "What happens next"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(app.T("Host kiểm tra khoản chuyển khoản và xác nhận. Chúng tôi sẽ báo cho bạn.",
                                           "The host checks the transfer and confirms. We'll notify you."))
                                    .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.8))
                                if let typicalWait {
                                    Text(app.T(typicalWait.vi, typicalWait.en))
                                        .font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.8))
                                        .accessibilityIdentifier("confirmed.typicalWait")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 12)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("confirmed.whatNext")
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

                        if isExpired {
                            Button { app.goReserve() } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.T("Giữ chỗ lại", "Reserve again"))
                                            .font(.system(size: 13.5, weight: .semibold))
                                        Text(app.T("Nếu vẫn còn chỗ trống.", "If there's still room."))
                                            .font(.system(size: 11.5)).foregroundStyle(app.palette.ink.opacity(0.7))
                                    }
                                    Spacer()
                                    Text("›").font(.system(size: 17))
                                }
                                .foregroundStyle(app.palette.ink)
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 22)
                            .accessibilityIdentifier("confirmed.expiredReserve")
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

                        // Q1/Q4 moment: a short peak, then the calm ticket below.
                        if let kind = shownMoment {
                            momentCard(kind)
                                .padding(.top, 22)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                        }

                        Divider().overlay(app.palette.rule).padding(.top, 28)

                        if isPaid && hasNamedAttendees && app.booking?.isGifted != true {
                            attendeeTickets
                        } else {
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(event.name).font(BanbeTheme.display(17))
                                Text(app.trStatus(app.stripKm(event.where, event: event))).font(.system(size: 12))
                                if isPaid, let code = app.booking?.code {
                                    Text(app.T("Mã vào cửa: ", "Entry code: ") + code)
                                        .font(.system(size: 12, weight: .semibold))
                                        .kerning(1.5)
                                } else if !isPaid {
                                    Text(isExpired
                                        ? app.T("Chỗ này đã được mở lại.", "This seat has been released.")
                                        : app.T("Vé sẽ hiện ở đây sau khi thanh toán được xác nhận.",
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
                                if booking.isGifted {
                                    // No QR: this seat belongs to the recipient
                                    // now, and the purchaser already downloaded
                                    // their copy of the PDF.
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.T("Đã tặng", "Gifted")).font(.system(size: 11, weight: .semibold)).opacity(0.65)
                                        Text(booking.recipientName ?? "").font(.system(size: 15, weight: .semibold))
                                    }
                                } else {
                                    // The scannable value is the booking's ADMISSION
                                    // credential, not its id: gifting a seat rotates
                                    // that token, which is exactly what makes a
                                    // screenshot taken before the gift stop working.
                                    QRCodeImage(value: booking.admissionQRCodeValue)
                                }
                            }
                        }
                        .padding(.top, 14)
                        }

                        // Real-device follow-up (2026-09-27) — fills the
                        // empty space below the ticket row (this
                        // ScrollView's own frame is taller than its
                        // top-anchored content, leaving blank scrollable
                        // room above the footer buttons) with the shared
                        // Banbe loading GIF, at half its previous pixel
                        // size (public/banbe-loading.gif was resized
                        // 380x297 -> 190x148, not just displayed smaller).
                        if isPaid, app.booking?.isGifted != true {
                            nextBlock.padding(.top, 22)
                        }

                        HStack {
                            Spacer()
                            BanbeLoadingVisual(size: 190)
                            Spacer()
                        }
                        .padding(.top, 20)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 30)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 0) {
                    if isPaid, let booking = app.booking, booking.isGifted {
                            footerButton(app.T("Tải lại vé PDF", "Re-download the PDF"), icon: "arrow.down.doc") {
                                downloadGiftPDF(booking)
                            }
                            .accessibilityIdentifier("confirmed.giftedPDF")
                        } else if isPaid && !hasNamedAttendees {
                            footerButton(app.T("Tặng vé cho bạn bè", "Give a ticket to a friend"), icon: "gift") {
                                giveTicket()
                            }
                            .accessibilityIdentifier("confirmed.giveTicket")
                        }
                    // Wallet and the single-PDF row carry the BOOKING-level
                    // credential, which the door refuses for a named-attendee
                    // booking — those get per-attendee downloads above instead.
                    if isPaid, let booking = app.booking, !booking.isGifted, !hasNamedAttendees {
                        footerButton(app.T("Thêm vào Apple Wallet", "Add to Apple Wallet"), icon: "wallet.bifold") {
                            walletDesignOpen = true
                        }
                        .accessibilityIdentifier("confirmed.addToWallet")
                        footerButton(app.T("Tải vé PDF", "Download PDF"), icon: "arrow.down.doc") {
                            downloadOwnPDF(booking)
                        }
                        .accessibilityIdentifier("confirmed.downloadPDF")
                    }
                    // A Menu, like Messages' "Settings" button: iOS expands it out
                    // of the row as a glass popover and dismisses it on a tap
                    // anywhere outside.
                    VStack(spacing: 0) {
                        Divider().overlay(app.palette.rule)
                        Menu {
                            Button { app.addToCalendarGoogle(event) } label: {
                                Label("Google Calendar", systemImage: "globe")
                            }
                            .accessibilityIdentifier("confirmed.calendar.google")
                            Button {
                                Analytics.track(.systemCalendarEditorOpened)
                                if let draft = app.calendarDraft(for: event) {
                                    appleCalendarRequest = CalendarExportRequest(draft: draft)
                                } else {
                                    app.calendarError = app.T("Sự kiện này chưa có giờ bắt đầu.", "This event has no start time yet.")
                                }
                            } label: {
                                Label(app.T("Lịch Apple", "Apple Calendar"), systemImage: "calendar")
                            }
                            .accessibilityIdentifier("confirmed.calendar.apple")
                        } label: {
                            footerRow(app.calAdded ? app.T("Đã thêm vào lịch", "Added to calendar")
                                                   : app.T("Thêm vào lịch", "Add to calendar"),
                                      icon: app.calAdded ? "calendar.badge.checkmark" : "calendar.badge.plus",
                                      chip: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .accessibilityIdentifier("confirmed.addToCalendar")
                    .sheet(item: $appleCalendarRequest) { req in
                        SystemEventEditor(draft: req.draft) { result in
                            appleCalendarRequest = nil
                            Analytics.track(.systemCalendarEditorResult(result: result.rawValue))
                            if result == .saved { app.calAdded = true }
                        }
                        .ignoresSafeArea()
                    }
                    if !app.calendarError.isEmpty {
                        Text(app.calendarError)
                            .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22).padding(.top, 8)
                    }
                    // 15-organizer-checkin.md follow-up: receipts are
                    // organizer-uploaded now (08-payment-documents.md), not
                    // auto-issued the moment a booking is confirmed — this
                    // screen can't assume one exists yet. `receiptChecked`
                    // distinguishes "haven't looked" from "looked, none
                    // yet" (both mean nil `receiptDoc`).
                    if isPaid && app.receiptChecked {
                        footerButton(receiptButtonLabel, icon: "doc.text") { receiptButtonTapped() }
                            .opacity(app.receiptRequestSending ? 0.6 : 1)
                            .accessibilityIdentifier("confirmed.viewReceipt")
                        if !app.receiptRequestError.isEmpty {
                            Text(app.receiptRequestError)
                                .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 22).padding(.top, 8)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $walletDesignOpen) {
            if let booking = app.booking {
                WalletPassDesignView(bookingID: booking.id, eventName: event.name,
                                     venue: app.trStatus(app.stripKm(event.where, event: event)))
                    .environmentObject(app)
            }
        }
        // Q6: a confirmed ticket on screen is the moment a reminder is useful (once per account per device, switch on).
        .sheet(isPresented: $app.pushAskPresented) { PushAskSheet().environmentObject(app) }
        .onAppear { startPollingIfNeeded(); refreshReceiptStatusIfNeeded(); loadAttendeesIfNeeded(); app.offerPushAskIfAppropriate(hasConfirmedTicket: isPaid); trackTicketOpened(); quickWinsRefresh() }
        .onChange(of: app.booking?.id) { _, _ in startPollingIfNeeded(); refreshReceiptStatusIfNeeded(); loadAttendeesIfNeeded(); trackTicketOpened(); quickWinsRefresh() }
        .onChange(of: isPaid) { _, paid in refreshReceiptStatusIfNeeded(); app.offerPushAskIfAppropriate(hasConfirmedTicket: paid); trackTicketOpened(); quickWinsRefresh() }
        .onChange(of: checkedIn) { _, _ in quickWinsRefresh() }
        .onChange(of: isPendingVerification) { _, _ in quickWinsRefresh() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .confirmed { pollTask?.cancel() } else { startPollingIfNeeded() }
        }
        .onDisappear { pollTask?.cancel(); receiptPollTask?.cancel(); doorPollTask?.cancel() }
        .onChange(of: app.receiptDoc) { _, _ in startReceiptPollingIfNeeded() }
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
        guard let bookingID = app.booking?.id, phase != .confirmed, phase != .expired else { return }
        let phaseAtStart = phase
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                guard app.booking?.id == bookingID, app.booking?.paymentState == phaseAtStart else { return }
                guard let fresh: Booking = try? await SupabaseService.client
                    .from("bookings").select().eq("id", value: bookingID.uuidString)
                    .single().execute().value
                else { continue }
                guard app.booking?.id == bookingID else { return }
                // The server row can still read .holding past its own
                // deadline for a moment — the sweep hasn't reached it yet,
                // or this same client's own forfeit RPC (fired the instant
                // the local countdown hit 0) hasn't landed. Blindly copying
                // that stale row over would revive a ticket this screen
                // already forfeited every 6 seconds until the server
                // catches up. Treat it as expired here too instead, and let
                // forfeitExpiredHold retry the RPC rather than regressing
                // local state backwards.
                if fresh.paymentState == .holding, let deadline = fresh.holdExpiresAt,
                   Countdown.secondsUntil(deadline, now: Date()) == 0 {
                    app.forfeitExpiredHold(fresh)
                    return
                }
                if fresh.paymentState != phaseAtStart {
                    app.booking = fresh
                    return
                }
            }
        }
    }

    private var receiptButtonLabel: String {
        if app.receiptDoc != nil {
            return app.T("Xem Receipt", "View Receipt")
        } else if app.receiptRequestSending {
            return app.T("Đang gửi yêu cầu…", "Sending request…")
        } else if app.receiptRequestSent {
            return app.T("Đã gửi yêu cầu ▪︎ Đang chờ người tổ chức", "Request sent ▪︎ waiting on the organizer")
        } else {
            return app.T("Yêu cầu Receipt", "Request Receipt")
        }
    }

    private func receiptButtonTapped() {
        if let doc = app.receiptDoc {
            Task { await app.openDocumentFromNotification(doc.id, backTo: .confirmed) }
        } else if !app.receiptRequestSent, let bookingID = app.booking?.id {
            Task { await app.requestReceipt(bookingID: bookingID) }
        }
    }

    // MARK: Phase 1 quick wins (same rules as web Confirmed.jsx)

    /// Runs every per-booking quick win once the booking/phase settles: the once-only moment, the honest-wait
    /// lookup, the "Next" details and the door watch.
    private func quickWinsRefresh() {
        evaluateMoment()
        loadTypicalWaitIfNeeded()
        loadNextInfoIfNeeded()
        startDoorPollIfNeeded()
    }

    /// Q1: the first time this device shows a confirmed ticket for a booking, "Your ticket is ready"; Q4: the first
    /// time it sees that booking checked in, "You're in". A ticket first seen at the door goes straight to Q4.
    private func evaluateMoment() {
        guard isPaid, let id = app.booking?.id else { return }
        let key = id.uuidString
        var kind: MomentKind?
        if checkedIn {
            QuickWins.claimOnce(.ticketReveal, key)
            if QuickWins.claimOnce(.checkIn, key) { kind = .checkIn }
        } else if QuickWins.claimOnce(.ticketReveal, key) {
            kind = .ticket
        }
        guard let kind else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.42, dampingFraction: 0.78)) {
            moment = (kind, id)
        }
        if kind == .ticket { Haptics.success() } else { Haptics.light() }
        UIAccessibility.post(notification: .announcement, argument: momentTitle(kind))
    }

    private func momentTitle(_ kind: MomentKind) -> String {
        kind == .ticket ? app.T("Vé của bạn đã sẵn sàng", "Your ticket is ready")
                        : app.T("Bạn đã vào cửa. Chúc bạn vui!", "You're in. Enjoy tonight!")
    }

    private func momentCard(_ kind: MomentKind) -> some View {
        HStack(spacing: 12) {
            Text(kind == .ticket ? "🎟️" : "✓").font(.system(size: 26)).accessibilityHidden(true)
            Text(momentTitle(kind)).font(BanbeTheme.display(18))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .top) { ConfettiBurst().padding(.top, 18) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(kind == .ticket ? "confirmed.ticketReveal" : "confirmed.checkInMoment")
    }

    /// Q2: get_host_confirmation_time once per screen open; nothing extra on error or below 5 confirmations.
    private func loadTypicalWaitIfNeeded() {
        guard isPendingVerification, let booking = app.booking, waitAskedFor != booking.id else { return }
        waitAskedFor = booking.id
        let eventID = booking.eventId
        Task { @MainActor in
            let minutes = await app.hostConfirmationMinutes(eventID: eventID)
            guard app.booking?.id == booking.id else { return }
            typicalWait = QuickWins.typicalWaitText(minutes: minutes)
        }
    }

    private func loadNextInfoIfNeeded() {
        guard isPaid, let booking = app.booking, nextInfoFor != booking.id else { return }
        nextInfoFor = booking.id
        nextInfo = AppState.TicketNextInfo()
        let eventID = booking.eventId
        Task { @MainActor in
            let info = await app.ticketNextInfo(eventID: eventID)
            guard app.booking?.id == booking.id else { return }
            nextInfo = info
        }
    }

    /// Q1 calm ending: where to go and what the host said. Calendar and "Give a ticket" are the rows below.
    private var nextBlock: some View {
        let note = app.lang == "en" ? (nextInfo.noteEn.isEmpty ? nextInfo.noteVi : nextInfo.noteEn)
                                    : (nextInfo.noteVi.isEmpty ? nextInfo.noteEn : nextInfo.noteVi)
        let place = nextInfo.address.isEmpty ? app.trStatus(app.stripKm(event.where, event: event)) : nextInfo.address
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Tiếp theo", "Next")).font(BanbeTheme.display(17))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Địa điểm", "Place")).font(.system(size: 11.5, weight: .semibold)).opacity(0.65)
                    Text(place).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let url = event.mapsURL {
                    Link(destination: url) {
                        Text(app.T("Chỉ đường", "Directions") + " ↗")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(app.palette.field, in: Capsule())
                    }
                    .accessibilityIdentifier("confirmed.directions")
                }
            }
            if !note.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Lời nhắn từ host", "Note from the host")).font(.system(size: 11.5, weight: .semibold)).opacity(0.65)
                    Text(note).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("confirmed.hostNote")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("confirmed.next")
    }

    /// Q4: from 3h before the start to 12h after, re-read the booking (and its named tickets) every 6s until it is
    /// checked in. Outside that window nothing is polled.
    private func startDoorPollIfNeeded() {
        doorPollTask?.cancel()
        guard isPaid, !checkedIn, let bookingID = app.booking?.id, let start = event.startDate else { return }
        let now = Date()
        guard now > start.addingTimeInterval(-3 * 3600), now < start.addingTimeInterval(12 * 3600) else { return }
        let named = hasNamedAttendees
        doorPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                guard app.booking?.id == bookingID, !checkedIn else { return }
                if let fresh: Booking = try? await SupabaseService.client
                    .from("bookings").select().eq("id", value: bookingID.uuidString)
                    .single().execute().value,
                   app.booking?.id == bookingID, fresh.status != app.booking?.status {
                    app.booking = fresh
                }
                if named { await app.loadBookingAttendees(bookingID) }
            }
        }
    }

    /// ticket_opened: the event's day vs today in the venue's zone (same rule as web Confirmed.jsx).
    private func trackTicketOpened() {
        guard isPaid, let bookingID = app.booking?.id, ticketOpenedFor != bookingID, let start = event.startDate else { return }
        ticketOpenedFor = bookingID
        let bucket = AppEventRules.ticketDayBucket(start: start, now: Date(), timeZone: EventMarket.timeZone(event.timeZoneID))
        Analytics.track(.ticketOpened(dayBucket: bucket))
    }

    private func refreshReceiptStatusIfNeeded() {
        guard isPaid, let bookingID = app.booking?.id else {
            app.receiptDoc = nil
            app.receiptChecked = false
            app.receiptRequestSent = false
            app.receiptRequestError = ""
            receiptPollTask?.cancel()
            return
        }
        Task { await app.loadReceiptStatus(bookingID: bookingID) }
        startReceiptPollingIfNeeded()
    }

    private func startReceiptPollingIfNeeded() {
        receiptPollTask?.cancel()
        guard isPaid, app.receiptDoc == nil, let bookingID = app.booking?.id else { return }
        receiptPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                guard app.booking?.id == bookingID, app.receiptDoc == nil else { return }
                await app.loadReceiptStatus(bookingID: bookingID)
            }
        }
    }

    /// One footer row: a fixed-width icon column (so every icon and label lines
    /// up down the page), the title, and a quiet trailing chevron. `chip` puts
    /// the icon on the soft round `field` disc the Messages "Settings" button
    /// uses; the other rows keep a bare icon in the same column.
    private func footerButton(_ title: String, icon: String, chip: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(app.palette.rule)
            Button(action: action) { footerRow(title, icon: icon, chip: chip) }
                .buttonStyle(.plain)
        }
    }

    /// The row itself. Every icon sits in the SAME 34pt frame at the SAME size,
    /// so icons and labels line up whether or not a row has the soft disc.
    private func footerRow(_ title: String, icon: String, chip: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .background(chip ? app.palette.field : Color.clear, in: Circle())
            Text(title)
                .font(.system(size: 13.5))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.35)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func loadAttendeesIfNeeded() {
        guard let id = app.booking?.id, !app.bookingAttendees.contains(where: { $0.bookingId == id }) else { return }
        Task { await app.loadBookingAttendees(id) }
    }

    /// One card per attendee, each with its own QR, entry code and PDF, plus
    /// "download selected" / "download all". Ticking is how several (but not
    /// all) tickets are picked; tapping a row's own button downloads just it.
    @ViewBuilder
    private var attendeeTickets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(event.name).font(BanbeTheme.display(17))
                Spacer()
                Text(app.T("\(attendees.count) vé", attendees.count == 1 ? "1 ticket" : "\(attendees.count) tickets"))
                    .font(.system(size: 11.5, weight: .semibold)).opacity(0.65)
            }
            Text(app.trStatus(app.stripKm(event.where, event: event))).font(.system(size: 12))
            Text(app.T("Mỗi người có mã QR riêng. Đưa mã của chính họ ở cửa.",
                       "Each person has their own QR. Show their own code at the door."))
                .font(.system(size: 11)).opacity(0.65)

            ForEach(attendees) { att in
                attendeeRow(att)
            }

            HStack(spacing: 10) {
                pdfButton(app.T("Tải đã chọn (\(selectedAttendeeIDs.count))", "Download selected (\(selectedAttendeeIDs.count))"),
                          enabled: !selectedAttendeeIDs.isEmpty, id: "confirmed.downloadSelected") {
                    downloadAttendees(attendees.filter { selectedAttendeeIDs.contains($0.id) })
                }
                pdfButton(app.T("Tải tất cả", "Download all"), enabled: true, id: "confirmed.downloadAll") {
                    downloadAttendees(attendees)
                }
            }
            .padding(.top, 2)
        }
        .padding(.top, 14)
        .accessibilityIdentifier("confirmed.attendeeTickets")
    }

    private func attendeeRow(_ att: BookingAttendee) -> some View {
        let selected = selectedAttendeeIDs.contains(att.id)
        return HStack(alignment: .center, spacing: 12) {
            Button {
                if selected { selectedAttendeeIDs.remove(att.id) } else { selectedAttendeeIDs.insert(att.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("confirmed.attendee.select.\(att.seatNo)")

            VStack(alignment: .leading, spacing: 3) {
                Text(att.name).font(.system(size: 14, weight: .semibold))
                if let age = att.age {
                    Text(app.T("\(age) tuổi", "Age \(age)")).font(.system(size: 11.5)).opacity(0.65)
                }
                Text(att.ticketCode).font(.system(size: 11.5, weight: .semibold)).kerning(1)
                if att.checkedInAt != nil {
                    Text(app.T("Đã vào cửa", "Checked in"))
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(BanbeTheme.alert)
                }
            }
            Spacer(minLength: 6)
            QRCodeImage(value: att.admissionToken.uuidString, size: 84)
            Button {
                downloadAttendees([att])
            } label: {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 15))
                    .frame(width: 34, height: 34)
                    .background(app.palette.field, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("confirmed.attendee.download.\(att.seatNo)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(app.palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("confirmed.attendee.\(att.seatNo)")
    }

    private func pdfButton(_ title: String, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc").font(.system(size: 13))
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }

    /// One share sheet carrying every chosen PDF (Save to Files / AirDrop / print).
    private func downloadAttendees(_ chosen: [BookingAttendee]) {
        guard let booking = app.booking, !chosen.isEmpty else { return }
        let urls = app.exportAttendeeTicketPDFs(for: booking, attendees: chosen)
        guard !urls.isEmpty else { return }
        UIApplication.shared.topViewController?
            .present(UIActivityViewController(activityItems: urls, applicationActivities: nil), animated: true)
    }

    /// The holder's own ticket as a PDF, handed to the share sheet (Save to
    /// Files / AirDrop / print).
    private func downloadOwnPDF(_ booking: Booking) {
        guard let url = app.exportOwnTicketPDF(for: booking, holderName: guestName) else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.topViewController?.present(share, animated: true)
    }

    /// Migration 132 replaced the old share-a-banbe.app-link behaviour: this
    /// now moves one seat to a named recipient on the server and hands back a
    /// PDF, instead of sharing a link to a destination this deployment does not
    /// serve.
    private func giveTicket() {
        guard let booking = app.booking else { return }
        app.openGiftForm(GiftTicketContext(booking: booking, eventName: event.name))
    }

    /// A gifted seat stays re-downloadable for the purchaser forever — it is
    /// their record of what they sent, and it costs them nothing to keep.
    private func downloadGiftPDF(_ booking: Booking) {
        guard let url = app.exportGiftPDF(for: booking) else { return }
        let share = UIActivityViewController(
            activityItems: [booking.recipientName.map { "\($0)" } ?? booking.code ?? url.lastPathComponent, url],
            applicationActivities: nil)
        UIApplication.shared.topViewController?.present(share, animated: true)
    }
}

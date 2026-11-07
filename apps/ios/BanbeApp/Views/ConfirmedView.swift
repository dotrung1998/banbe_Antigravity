import SwiftUI
import Combine

/// Port of src/screens/Confirmed.jsx: the ticket, redesigned as one paper ticket (note 78). A slim "What's next" strip
/// explains where the booking stands (9 cases, Lib/TicketStatus.swift + Lib/TicketCopy.swift), the event's name and
/// Date/Time/Area tiles sit above a perforation, and the stub below holds the QR and the 3-3 entry code (a swipeable stub
/// per attendee for named tickets). Tapping the event name or "View event" opens the Event details sheet.
///
/// The QR/entry-code ticket only ever shows a REAL code for a paid, live ticket (Booking.isTicket or the attended
/// equivalent); a cancelled, ended, locked or unconfirmed ticket draws a blurred placeholder with a status label
/// (TicketQrView), never the admission token. Every seeded demo event uses 'instant' approval, which marks a booking
/// 'confirmed' the moment it's created; gating on status alone was what once let this screen show a ticket before anyone
/// had paid anything.
struct ConfirmedView: View {
    @EnvironmentObject var app: AppState
    @State private var pollTask: Task<Void, Never>?
    /// This screen's own 1-second tick for its countdowns (AppState.now no longer publishes app-wide; PaymentViews twin).
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    // Bug 1 (15-organizer-checkin.md follow-up): a separate poll from
    // `pollTask` above, with a different stop condition (runs until a receipt is
    // actually found, not until the payment phase changes), matching this
    // app's established polling convention elsewhere (AttendanceView's own
    // 6s poll, 41340ee; PaymentViews' 6s poll).
    @State private var receiptPollTask: Task<Void, Never>?
    /// Note 44: Apple Calendar goes through the system editor (no access request).
    @State private var appleCalendarRequest: CalendarExportRequest?
    @State private var walletDesignOpen = false
    /// Migration 217: the admin Ticket demo. No read, poll or write reaches the server; writes say so instead.
    @State private var demoNotice: String?
    private var demo: Bool { app.ticketDemo != nil }
    /// True (and says so on the banner) when `demo` blocks the action about to run.
    private func demoBlocked() -> Bool {
        guard demo else { return false }
        demoNotice = app.T("Không có trong bản demo.", "Not available in the demo.")
        Task { @MainActor in try? await Task.sleep(nanoseconds: 3_000_000_000); demoNotice = nil }
        return true
    }
    /// ticket_opened is counted once per confirmed ticket shown (migration 196).
    @State private var ticketOpenedFor: UUID?
    // Q2: this host's typical confirmation time, asked once per screen open.
    @State private var typicalWait: (vi: String, en: String)?
    @State private var waitAskedFor: UUID?
    // The venue address + the host's own note, read once per ticket (shown in the Event details sheet).
    @State private var nextInfo = AppState.TicketNextInfo()
    @State private var nextInfoFor: UUID?
    // Q4: while the event is about to start or under way, watch for the door scan (6s, like the polls below).
    @State private var doorPollTask: Task<Void, Never>?
    // Note 78: the collapsed policy paragraph, the Event details sheet, the stub being shown and the calendar chooser.
    @State private var policyOpen = false
    @State private var detailsOpen = false
    @State private var detailsAction: DetailsAction?
    @State private var stubIndex = 0
    @State private var calendarChooserOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum DetailsAction { case openEvent, message }

    private var event: CatalogEvent { app.currentEvent }
    /// This booking's named tickets, once loaded. Empty for a booking made
    /// before per-attendee tickets, which keeps its single booking-level QR.
    private var attendees: [BookingAttendee] {
        guard let id = app.booking?.id else { return [] }
        return app.bookingAttendees.filter { $0.bookingId == id }
    }
    private var hasNamedAttendees: Bool { !attendees.isEmpty }
    // payment_state is the source of truth for every phase distinction
    // below, never booking.status/paidMarkedAt alone, which is the
    // pre-state-machine model this screen used to read exclusively.
    private var phase: PaymentPhase { app.booking?.paymentState ?? .holding }
    // TASK B (2026-10-01 UX foundation pass): Booking.isTicket is the one
    // shared rule (status AND payment_state both "confirmed"); the
    // paidMarkedAt fallback below is for a booking decoded before
    // payment_state existed and must ALSO require status == "confirmed".
    private var isPaid: Bool {
        guard let booking = app.booking else { return false }
        // A checked-in booking is "attended" (check_in_guest, migration 021) and is still the same paid ticket.
        return booking.isTicket || (booking.paidMarkedAt != nil && booking.status == "confirmed")
            || (booking.status == "attended" && booking.paymentState == .confirmed)
    }
    private var checkedIn: Bool { isPaid && QuickWins.isCheckedIn(app.booking, attendees: attendees) }
    private var isHolding: Bool { app.booking != nil && phase == .holding }
    private var isPendingVerification: Bool { phase == .pendingVerification }
    private var isExpired: Bool { phase == .expired }
    /// Only a hold or a transfer the host has not confirmed yet is still payable; cancelled / disputed / expired are not.
    private var showPayButton: Bool { app.booking != nil && (isHolding || isPendingVerification) }
    /// Booking journey step (note 48): only while the booking is still on its way to a ticket.
    private var journeyStep: Int? {
        guard app.booking != nil, isHolding || isPendingVerification else { return nil }
        return isPendingVerification ? 3 : 2
    }
    private var holdDeadline: Date? { app.booking?.holdExpiresAt ?? app.holdDeadline }
    private var countdown: String {
        Countdown.format(Countdown.secondsUntil(holdDeadline, now: now))
    }
    private var verifySecondsLeft: TimeInterval {
        Countdown.secondsUntil(app.booking?.verifyDueAt, now: now)
    }
    private var verifyOverdue: Bool { app.booking?.verifyDueAt != nil && verifySecondsLeft == 0 }
    private var guestName: String {
        let typed = app.formName.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        let profile = (app.user?.displayName ?? "").trimmingCharacters(in: .whitespaces)
        return profile.isEmpty ? app.T("Bạn", "You") : profile
    }

    // MARK: Note 78: the case, its copy and its tone

    /// Several named tickets are scanned one by one: the booking only counts as checked in once ALL of them are, and the
    /// door watch keeps going while any is still open and the door window lasts (Lib/TicketStatus.swift, shared
    /// vectors). A booking without named tickets keeps the old rule and the old poll exactly.
    private var pendingScans: Bool { hasNamedAttendees && attendees.contains { $0.checkedInAt == nil } }
    private var stripCheckedIn: Bool { isPaid && (hasNamedAttendees ? !pendingScans : checkedIn) }

    private var dateParts: [String] { event.when.components(separatedBy: " ▪︎ ") }
    private var whenDateRaw: String { dateParts.first ?? "" }
    private var whenTime: String { dateParts.count > 1 ? dateParts[1] : "" }
    private var areaText: String { app.trStatus(event.where.components(separatedBy: " ▪︎ ").first ?? "") }
    private var daysUntil: Int? {
        Countdown.daysUntilInZone(whenDateRaw, start: event.startDate, timeZone: EventMarket.timeZone(event.timeZoneID))
    }
    /// The booking row's own status can say cancelled/expired even when payment_state has not caught up.
    private var caseState: String {
        switch app.booking?.status {
        case "cancelled": return "cancelled"
        case "expired": return "expired"
        default: return phase.rawValue
        }
    }
    private var ticketCase: TicketStatus.Case? {
        guard app.booking != nil else { return nil }
        return TicketStatus.resolve(paymentState: caseState, eventCancelled: event.cancelled, endedHoursAgo: event.endedHoursAgo,
                                    isPaid: isPaid, checkedIn: stripCheckedIn, daysUntil: daysUntil)
    }
    private var hasRefund: Bool { app.myRefunds.contains { $0.bookingId == app.booking?.id } }
    private var copy: TicketCopy.Copy? {
        guard let ticketCase else { return nil }
        var c = TicketCopy.Context()
        c.en = app.isEN
        c.eventCancelled = event.cancelled
        c.dateText = EventDetailPresentation.dateTileLabel(whenDateRaw, en: app.isEN)
        c.timeText = whenTime
        c.areaText = areaText
        c.daysUntil = daysUntil
        c.typicalWait = typicalWait
        c.verifyOverdue = verifyOverdue
        c.hasReceipt = app.receiptDoc != nil
        c.hasRefund = hasRefund
        c.hasDirections = event.mapsURL != nil
        return TicketCopy.copy(for: ticketCase.key, c)
    }
    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "alert": return BanbeTheme.alert
        case "honey": return app.palette.honey
        case "plum": return app.palette.plum
        case "clay": return app.palette.clay
        case "moss": return app.palette.update
        case "mist": return app.palette.question
        default: return app.palette.ink3
        }
    }
    /// A cancelled / ended / unconfirmed ticket never draws the real QR (TicketQrView); an unmapped state is treated as void.
    private var qrMode: TicketStatus.QR { ticketCase?.qr ?? .void }
    private var qrShows: Bool { TicketStatus.qrShowsToken(qrMode) }
    private var qrLabel: String {
        switch qrMode {
        case .ok: return app.T("Mã QR vé", "Ticket QR")
        case .in: return app.T("Bạn đã check-in", "Checked in")
        case .lock: return app.T("QR sẽ mở khi host xác nhận", "QR unlocks when the host confirms")
        case .past: return app.T("Đã kết thúc", "Ended")
        case .void: return app.T("Vé không còn hiệu lực", "Ticket void")
        }
    }
    private var stripTail: (text: String, id: String)? {
        switch ticketCase?.key {
        case .holding: return (countdown, "confirmed.holdCountdown")
        case .awaiting:
            guard !verifyOverdue, app.booking?.verifyDueAt != nil else { return nil }
            return (Countdown.format(verifySecondsLeft), "confirmed.verifyCountdown")
        case .today:
            guard let start = event.startDate else { return nil }
            let s = start.timeIntervalSince(now)
            guard s > 0 else { return nil }
            return (s >= 3600 ? "\(Int(s / 3600))h" : "\(max(1, Int(s / 60)))m", "confirmed.todayCountdown")
        default: return nil
        }
    }
    private var policyNote: String {
        app.T("banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn. Nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.",
              "banbe does not collect money. Pay the organizer directly using the instructions in chat. If they cancel, they are responsible for your refund.")
    }
    private var hostNoteText: String {
        app.lang == "en" ? (nextInfo.noteEn.isEmpty ? nextInfo.noteVi : nextInfo.noteEn)
                         : (nextInfo.noteVi.isEmpty ? nextInfo.noteEn : nextInfo.noteVi)
    }
    private var eventOver: Bool { event.cancelled || event.endedHoursAgo != nil }

    private func runLink(_ link: TicketCopy.Link?) {
        guard let link, let booking = app.booking else { return }
        if link.kind != .calendar, link.kind != .directions, demoBlocked() { return }
        switch link.kind {
        case .refunds: app.openMyRefunds(back: .confirmed)
        case .reserve: app.goReserve()
        case .pay: app.openPaymentDetails(booking.id, back: .confirmed)
        case .chat: Task { await app.openChat(for: event.key, back: .confirmed) }
        case .receipt: if let doc = app.receiptDoc { Task { await app.openDocumentFromNotification(doc.id, backTo: .confirmed) } }
        case .calendar: calendarChooserOpen = true
        case .directions: break   // a real Link to the map
        }
    }

    // MARK: body

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

                if demo {
                    HStack {
                        Text(demoNotice ?? app.T("Demo · dữ liệu mẫu · không lưu gì", "Demo · sample data · nothing is saved"))
                            .font(.footnote)
                        Spacer(minLength: 8)
                        Button(app.T("Thoát demo", "Exit demo")) { app.endTicketDemo(goBack: true) }
                            .font(.footnote.weight(.bold)).frame(minHeight: 44)
                            .accessibilityIdentifier("confirmed.demo.exit")
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 12)
                    .background(app.palette.block, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 22).padding(.top, 6)
                    .accessibilityIdentifier("confirmed.demo.banner")
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let journeyStep {
                            BookingJourneyProgress(current: journeyStep)
                                .padding(.bottom, 14)
                        }
                        if let copy, let ticketCase { statusHeader(copy.label, ticketCase.tone) }
                        if let booking = app.booking {
                            PaperTicketView(
                                holderLabel: app.T("Vé của ", "Ticket for ") + (booking.isGifted ? (booking.recipientName ?? "") : guestName),
                                title: event.name,
                                tiles: [
                                    TicketTile(id: "date", label: app.T("Ngày", "Date"), value: EventDetailPresentation.dateTileLabel(whenDateRaw, en: app.isEN)),
                                    TicketTile(id: "time", label: app.T("Giờ", "Time"), value: whenTime),
                                    TicketTile(id: "area", label: app.T("Khu vực", "Area"), value: areaText),
                                ],
                                viewLabel: app.T("Xem sự kiện", "View event"),
                                onOpenDetails: { detailsOpen = true },
                                strip: { ticketStrip },
                                stub: { ticketStub(booking) })
                        }
                        // Money first: while a hold or an unconfirmed transfer is open, the payment details stay one tap away.
                        if showPayButton, let bookingID = app.booking?.id { payButton(bookingID).padding(.top, 14) }
                        if typeSize.isAccessibilitySize { actionsArea.padding(.top, 16).padding(.horizontal, -0) }
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                if !typeSize.isAccessibilitySize { actionsArea }
            }
        }
        .sheet(isPresented: $walletDesignOpen) {
            if let booking = app.booking {
                WalletPassDesignView(bookingID: booking.id, eventName: event.name,
                                     venue: app.trStatus(app.stripKm(event.where, event: event)))
                    .environmentObject(app)
            }
        }
        // The Event details sheet. Its two actions run after it has dismissed (onDismiss), so navigation never races it.
        .sheet(isPresented: $detailsOpen, onDismiss: runDetailsAction) {
            EventDetailsSheet(
                event: event,
                tiles: [
                    TicketTile(id: "date", label: app.T("Ngày", "Date"), value: EventDetailPresentation.dateTileLabel(whenDateRaw, en: app.isEN)),
                    TicketTile(id: "time", label: app.T("Giờ", "Time"), value: whenTime),
                    TicketTile(id: "place", label: app.T("Địa điểm", "Place"), value: areaText),
                ],
                about: EventDetailPresentation.aboutSection(desc: event.desc, intro: event.intro, includedCount: event.includedItems?.count ?? 0),
                included: includedForSheet,
                place: nextInfo.address.isEmpty ? areaText : nextInfo.address,
                hostNote: hostNoteText,
                // Distance only when it helps choose: located, and within 50 km (never "9662 km away").
                distance: TicketStatus.showDistance(km: haversineKm(from: app.userCoords, to: event), located: app.located, en: app.isEN),
                policyNote: isExpired ? "" : policyNote,
                over: eventOver,
                onOpenEvent: { detailsAction = .openEvent },
                onMessage: { detailsAction = .message })
                .environmentObject(app)
        }
        // The strip's "Add to calendar" link offers the same two choices as the tile.
        .confirmationDialog(app.T("Thêm vào lịch", "Add to calendar"), isPresented: $calendarChooserOpen, titleVisibility: .visible) {
            Button("Google Calendar") { app.addToCalendarGoogle(event) }
            Button(app.T("Lịch Apple", "Apple Calendar")) { addToAppleCalendar() }
        }
        // Q6: a confirmed ticket on screen is the moment a reminder is useful (once per account per device, switch on).
        .sheet(isPresented: $app.pushAskPresented) { PushAskSheet().environmentObject(app) }
        .onAppear { startPollingIfNeeded(); refreshReceiptStatusIfNeeded(); loadAttendeesIfNeeded(); if !demo { app.offerPushAskIfAppropriate(hasConfirmedTicket: isPaid) }; trackTicketOpened(); quickWinsRefresh(); loadRefundsIfNeeded() }
        .onChange(of: app.booking?.id) { _, _ in stubIndex = 0; startPollingIfNeeded(); refreshReceiptStatusIfNeeded(); loadAttendeesIfNeeded(); trackTicketOpened(); quickWinsRefresh(); loadRefundsIfNeeded() }
        .onChange(of: isPaid) { _, paid in refreshReceiptStatusIfNeeded(); if !demo { app.offerPushAskIfAppropriate(hasConfirmedTicket: paid) }; trackTicketOpened(); quickWinsRefresh() }
        .onChange(of: checkedIn) { _, _ in quickWinsRefresh() }
        .onChange(of: pendingScans) { _, _ in quickWinsRefresh() }
        .onChange(of: isPendingVerification) { _, _ in quickWinsRefresh() }
        .onChange(of: ticketCase?.key) { _, _ in loadRefundsIfNeeded() }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .confirmed { pollTask?.cancel() } else { startPollingIfNeeded() }
        }
        .onDisappear { pollTask?.cancel(); receiptPollTask?.cancel(); doorPollTask?.cancel() }
        .onChange(of: app.receiptDoc) { _, _ in startReceiptPollingIfNeeded() }
        // `ticker` ticks every second, which is what drives
        // `countdown` above: the moment it notices this screen's own
        // deadline has passed while still 'holding', forfeit immediately
        // rather than leave the ticket sitting stale until the next poll or
        // the minutely server sweep gets to it. Self-guards against firing
        // twice: forfeitExpiredHold flips booking.paymentState to .expired,
        // so `isHolding` (derived from `phase`) is false on the very next tick.
        .onReceive(ticker) { tick in
            now = tick
            if !demo, isHolding, let deadline = holdDeadline, Countdown.secondsUntil(deadline, now: tick) == 0,
               let current = app.booking {
                app.forfeitExpiredHold(current)
            }
        }
    }

    // MARK: pieces

    /// Wallet / Calendar tiles, More options and the collapsed policy line (note 77/78). Pinned under the ticket; at
    /// accessibility text sizes it scrolls WITH the ticket instead, or it would take the screen from the ticket.
    private var actionsArea: some View {
        // Note 77: the ticket's actions as two tiles (the most used ones) and a "More" menu for the rest.
        // No hairlines: the block fills and the gaps separate them.
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // The ticket's status picks the two tiles (note 79 follow-up; web twin: Confirmed.jsx `actionable`).
                if actionable, let booking = app.booking {
                    if booking.isGifted {
                        Button { downloadGiftPDF(booking) } label: {
                            actionTile(app.T("Tải lại vé PDF", "Re-download the PDF"), icon: "arrow.down.doc")
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("confirmed.giftedPDF")
                    } else if hasNamedAttendees {
                        if let current = attendees[safe: min(stubIndex, attendees.count - 1)] {
                            Button { downloadAttendees([current]) } label: {
                                actionTile(app.T("Tải vé này", "Download this ticket"), icon: "arrow.down.doc")
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityIdentifier("confirmed.downloadCurrent")
                        }
                    } else if walletPrimary {
                        Button { if !demoBlocked() { walletDesignOpen = true } } label: {
                            actionTile(app.T("Thêm vào Apple Wallet", "Add to Apple Wallet"), icon: "wallet.bifold.fill")
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("confirmed.addToWallet")
                    } else {
                        Button { downloadOwnPDF(booking) } label: {
                            actionTile(app.T("Tải vé PDF", "Download PDF"), icon: "arrow.down.doc")
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityIdentifier("confirmed.downloadPDF")
                    }
                    if ticketOver && app.receiptChecked {
                        Button { receiptButtonTapped() } label: { actionTile(receiptButtonLabel, icon: "doc.text") }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(app.receiptRequestSending)
                            .accessibilityIdentifier("confirmed.viewReceipt")
                    }
                }
                if showCalendar {
                // A Menu, like Messages' "Settings" button: iOS expands it as a glass popover.
                Menu {
                    Button { app.addToCalendarGoogle(event) } label: {
                        Label("Google Calendar", systemImage: "globe")
                    }
                    .accessibilityIdentifier("confirmed.calendar.google")
                    Button { addToAppleCalendar() } label: {
                        Label(app.T("Lịch Apple", "Apple Calendar"), systemImage: "calendar")
                    }
                    .accessibilityIdentifier("confirmed.calendar.apple")
                } label: {
                    actionTile(app.calAdded ? app.T("Đã thêm vào lịch", "Added to calendar") : app.T("Thêm vào lịch", "Add to calendar"),
                               icon: nil, done: app.calAdded)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirmed.addToCalendar")
                }
            }
            .sheet(item: $appleCalendarRequest) { req in
                SystemEventEditor(draft: req.draft) { result in
                    appleCalendarRequest = nil
                    Analytics.track(.systemCalendarEditorResult(result: result.rawValue))
                    if result == .saved { app.calAdded = true }
                }
                .ignoresSafeArea()
            }
            if hasMoreActions {
                Menu {
                    if ticketLive, let booking = app.booking, !booking.isGifted, !hasNamedAttendees {
                        Button { giveTicket() } label: { Label(app.T("Tặng vé cho bạn bè", "Give a ticket to a friend"), systemImage: "gift") }
                            .accessibilityIdentifier("confirmed.giveTicket")
                        if walletPrimary {
                            Button { downloadOwnPDF(booking) } label: { Label(app.T("Tải vé PDF", "Download PDF"), systemImage: "arrow.down.doc") }
                                .accessibilityIdentifier("confirmed.downloadPDF")
                        }
                    }
                    if actionable, hasNamedAttendees, attendees.count > 1 {
                        Button { downloadAttendees(attendees) } label: { Label(app.T("Tải tất cả", "Download all"), systemImage: "arrow.down.doc.fill") }
                            .accessibilityIdentifier("confirmed.downloadAll")
                    }
                    // Receipts are organizer-uploaded (08-payment-documents.md); once the event is over the receipt is a tile.
                    if actionable && !ticketOver && app.receiptChecked {
                        Button { receiptButtonTapped() } label: { Label(receiptButtonLabel, systemImage: "doc.text") }
                            .disabled(app.receiptRequestSending)
                            .accessibilityIdentifier("confirmed.viewReceipt")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                        Text(app.T("Thêm tuỳ chọn", "More options")).font(.system(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(app.palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(app.palette.block, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("confirmed.more")
            }
            ForEach([app.calendarError, app.receiptRequestError].filter { !$0.isEmpty }, id: \.self) { err in
                Text(err)
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                    .multilineTextAlignment(.center)
            }
            // Note 78: the policy paragraph is unchanged and only collapsed. Hidden for an expired hold, as
            // before (the strip explains it).
            if app.booking != nil, !isExpired { policyDisclosure }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }


    private func statusHeader(_ label: String, _ tone: String) -> some View {
        HStack {
            BanbeLogo(kind: .wordmark, width: 56).opacity(0.7).accessibilityLabel("banbe")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(toneColor(tone)).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(label).font(.caption.weight(.semibold)).dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("confirmed.status")
        }
        .padding(.horizontal, 6).padding(.bottom, 12)
    }

    @ViewBuilder private var ticketStrip: some View {
        if let ticketCase, let copy {
            WhatsNextStrip(
                key: ticketCase.key, tone: toneColor(ticketCase.tone), solid: ticketCase.key == .checkedIn,
                heading: copy.heading, sub: copy.sub, tail: stripTail?.text, tailID: stripTail?.id,
                detail: copy.detail, linkLabel: copy.link?.label,
                linkURL: copy.link?.kind == .directions ? event.mapsURL : nil,
                onLink: { runLink(copy.link) })
                // A new case is a new strip, collapsed again.
                .id(ticketCase.key.rawValue)
        }
    }

    @ViewBuilder private func ticketStub(_ booking: Booking) -> some View {
        if isPaid, hasNamedAttendees, !booking.isGifted {
            TicketStubPager(attendees: attendees, qrMode: qrMode, qrLabel: qrLabel, activeIndex: $stubIndex)
        } else if isPaid, booking.isGifted {
            // No QR: this seat belongs to the recipient now, and the purchaser already downloaded their copy of the PDF.
            VStack(spacing: 3) {
                Text(app.T("Đã tặng", "Gifted")).font(.caption.weight(.semibold)).foregroundStyle(app.palette.ink2)
                Text(booking.recipientName ?? "").font(.title3.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("confirmed.gifted")
        } else {
            VStack(spacing: 0) {
                // The scannable value is the booking's ADMISSION credential, not its id: gifting a seat rotates that
                // token, which is exactly what makes a screenshot taken before the gift stop working.
                TicketQrView(mode: qrMode, value: booking.admissionQRCodeValue, size: 220, padding: 10, label: qrLabel)
                if let code = booking.code, !code.isEmpty {
                    Text(app.T("Mã vào cửa", "Entry code").uppercased())
                        .font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(app.palette.ink3)
                        .padding(.top, 16)
                    // A locked / void / ended ticket shows a mask, never the real code.
                    Text(qrShows ? TicketStatus.formatEntryCode(code) : "••• •••")
                        .font(.system(.title, design: .monospaced).weight(.semibold)).tracking(3)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .opacity(qrShows ? 1 : 0.35)
                        .padding(.top, 4)
                        .accessibilityIdentifier("confirmed.entryCode")
                }
                if qrShows {
                    Text(app.T("Đưa mã này ở cửa", "Show this code at the door"))
                        .font(.footnote).foregroundStyle(app.palette.ink2).padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func payButton(_ bookingID: UUID) -> some View {
        Button {
            if demoBlocked() { return }
            app.openPaymentDetails(bookingID, back: .confirmed)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Xem thông tin chuyển khoản", "See payment details")).font(.body.weight(.semibold))
                    Text(app.T("Số tài khoản, số tiền và nội dung cần ghi.", "Account number, amount and the reference to use."))
                        .font(.caption).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(app.palette.paper)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier("confirmed.pay")
    }

    private var policyDisclosure: some View {
        VStack(spacing: 4) {
            Button {
                if reduceMotion { policyOpen.toggle() } else { withAnimation(.easeOut(duration: 0.2)) { policyOpen.toggle() } }
            } label: {
                HStack(spacing: 6) {
                    Text(app.T("Về tiền và hoàn tiền", "About money and refunds")).font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(policyOpen ? 90 : 0))
                }
                .foregroundStyle(app.palette.ink2)
                .frame(minHeight: 44).padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(policyOpen ? app.T("Đang mở", "Expanded") : app.T("Đang thu gọn", "Collapsed"))
            .accessibilityIdentifier("confirmed.policyToggle")
            if policyOpen {
                Text(policyNote).font(.system(size: 13.5)).lineSpacing(3)
                    .foregroundStyle(app.palette.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("confirmed.policyText")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var includedForSheet: (visible: Bool, items: [String]) {
        if let items = event.includedItems, !items.isEmpty { return EventDetailPresentation.includedSection(items.map(\.label)) }
        return EventDetailPresentation.includedSection(event.included.components(separatedBy: CharacterSet(charactersIn: "▪︎,·")))
    }

    private func runDetailsAction() {
        let action = detailsAction
        detailsAction = nil
        if action != nil, demoBlocked() { return }
        switch action {
        case .openEvent: app.goEvent(event.key)
        case .message: Task { await app.openChat(for: event.key, back: .confirmed) }
        case nil: break
        }
    }

    private func addToAppleCalendar() {
        Analytics.track(.systemCalendarEditorOpened)
        if let draft = app.calendarDraft(for: event) {
            appleCalendarRequest = CalendarExportRequest(draft: draft)
        } else {
            app.calendarError = app.T("Sự kiện này chưa có giờ bắt đầu.", "This event has no start time yet.")
        }
    }

    /// "Track refund" only when this booking really has an open refund claim (loaded on demand for a cancelled ticket).
    private func loadRefundsIfNeeded() {
        guard !demo, ticketCase?.key == .cancelled, app.booking?.id != nil else { return }
        Task { await app.loadMyRefunds() }
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
        guard !demo, let bookingID = app.booking?.id, phase != .confirmed, phase != .expired else { return }
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
        if demoBlocked() { return }
        if let doc = app.receiptDoc {
            Task { await app.openDocumentFromNotification(doc.id, backTo: .confirmed) }
        } else if !app.receiptRequestSent, let bookingID = app.booking?.id {
            Task { await app.requestReceipt(bookingID: bookingID) }
        }
    }

    // MARK: Phase 1 quick wins (same rules as web Confirmed.jsx)

    /// Runs every per-booking quick win once the booking/phase settles: the honest-wait lookup, the venue details and
    /// the door watch.
    private func quickWinsRefresh() {
        loadTypicalWaitIfNeeded()
        loadNextInfoIfNeeded()
        startDoorPollIfNeeded()
    }

    /// Q2: get_host_confirmation_time once per screen open; nothing extra on error or below 5 confirmations.
    private func loadTypicalWaitIfNeeded() {
        guard !demo, isPendingVerification, let booking = app.booking, waitAskedFor != booking.id else { return }
        waitAskedFor = booking.id
        let eventID = booking.eventId
        Task { @MainActor in
            let minutes = await app.hostConfirmationMinutes(eventID: eventID)
            guard app.booking?.id == booking.id else { return }
            typicalWait = QuickWins.typicalWaitText(minutes: minutes)
        }
    }

    private func loadNextInfoIfNeeded() {
        guard !demo, isPaid, let booking = app.booking, nextInfoFor != booking.id else { return }
        nextInfoFor = booking.id
        nextInfo = AppState.TicketNextInfo()
        let eventID = booking.eventId
        Task { @MainActor in
            let info = await app.ticketNextInfo(eventID: eventID)
            guard app.booking?.id == booking.id else { return }
            nextInfo = info
        }
    }

    /// Q4: from 3h before the start to 12h after, re-read the booking (and its named tickets) every 6s until it is
    /// checked in. Outside that window nothing is polled. Named tickets: it keeps going while any is still unscanned
    /// and the window lasts, and stops the moment all are scanned or the window ends (TicketStatus.doorWatchOpen).
    private func startDoorPollIfNeeded() {
        doorPollTask?.cancel()
        guard !demo, isPaid, let bookingID = app.booking?.id, let start = event.startDate else { return }
        let named = hasNamedAttendees
        guard TicketStatus.doorWatchOpen(namedScans: named ? attendees.map { $0.checkedInAt != nil } : nil,
                                         checkedIn: checkedIn, start: start, now: Date()) else { return }
        doorPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { return }
                guard app.booking?.id == bookingID else { return }
                if named {
                    // Re-read from state each tick: stop as soon as every ticket is scanned or the window has closed.
                    let scans = attendees.map { $0.checkedInAt != nil }
                    guard TicketStatus.doorWatchOpen(namedScans: scans, checkedIn: checkedIn, start: start, now: Date()) else { return }
                } else {
                    guard !checkedIn else { return }
                }
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
        guard !demo, isPaid, let bookingID = app.booking?.id, ticketOpenedFor != bookingID, let start = event.startDate else { return }
        ticketOpenedFor = bookingID
        let bucket = AppEventRules.ticketDayBucket(start: start, now: Date(), timeZone: EventMarket.timeZone(event.timeZoneID))
        Analytics.track(.ticketOpened(dayBucket: bucket))
    }

    private func refreshReceiptStatusIfNeeded() {
        if demo { return }   // the sample ticket has no receipt to look up
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

    /// Whether anything is left for the "More" menu (note 77; named tickets add their PDFs, note 78).
    private var hasMoreActions: Bool {
        guard actionable else { return false }
        if hasNamedAttendees { return attendees.count > 1 || (!ticketOver && app.receiptChecked) }
        return (ticketLive && app.booking.map { !$0.isGifted } == true) || (!ticketOver && app.receiptChecked)
    }

    // Status-driven actions (web twin: Confirmed.jsx). Over = ended or checked in; nothing at all once cancelled / expired / in review.
    private var ticketKey: TicketStatus.Key? { ticketCase?.key }
    private var ticketLive: Bool { ticketKey == .upcoming || ticketKey == .today }
    private var ticketOver: Bool { ticketKey == .ended || ticketKey == .checkedIn }
    private var ticketDead: Bool { ticketKey == .cancelled || ticketKey == .expired || ticketKey == .review }
    private var actionable: Bool { isPaid && !ticketDead }
    private var showCalendar: Bool { !ticketOver && !ticketDead }
    private var walletPrimary: Bool { ticketLive && !hasNamedAttendees && !(app.booking?.isGifted ?? false) }

    /// The day / month for the calendar tile's mini page (same date text as Event Detail's stub).
    private var calendarBlock: EventDetailPresentation.DateBlock? {
        event.when.components(separatedBy: " ▪︎ ").first(where: { !$0.isEmpty })
            .flatMap { EventDetailPresentation.dateBlock($0, en: app.isEN) }
    }

    /// One action tile (note 77): the icon on a soft clay disc (or the mini calendar page when `icon` is nil), the
    /// label under it. Equal height side by side; a block fill instead of divider lines.
    private func actionTile(_ title: String, icon: String?, done: Bool = false) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(app.palette.clay)
                        .frame(width: 36, height: 36)
                        .background(app.palette.clayBg, in: Circle())
                } else {
                    MiniCalendarPage(day: calendarBlock?.day ?? "", month: calendarBlock?.weekday ?? "", size: 36, fixedLight: true)
                        .overlay(alignment: .bottomTrailing) {
                            if done {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white, Color(red: 0.2, green: 0.62, blue: 0.36))
                                    .offset(x: 5, y: 5)
                            }
                        }
                }
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(app.palette.ink)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadAttendeesIfNeeded() {
        guard !demo, let id = app.booking?.id, !app.bookingAttendees.contains(where: { $0.bookingId == id }) else { return }
        Task { await app.loadBookingAttendees(id) }
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
        if demoBlocked() { return }
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

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

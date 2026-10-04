import Foundation
import UIKit
import Supabase

extension AppState {

    // MARK: - Recipient form

    /// Opens the recipient form for one seat. `context.seats` decides what the
    /// review step promises: a single-seat booking transfers outright, a
    /// multi-seat one gives exactly one seat away and the rest stay with the
    /// purchaser.
    func openGiftForm(_ context: GiftTicketContext) {
        giftTicketContext = context
        giftFormName = ""
        giftFormEmail = ""
        giftFormDOB = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
        giftFormStep = .form
        giftError = ""
        giftResult = nil
        giftPDFURL = nil
        giftICSURL = nil
    }

    func closeGiftForm() {
        giftTicketContext = nil
        giftFormStep = .form
        giftError = ""
        giftResult = nil
        giftPDFURL = nil
        giftICSURL = nil
    }

    var giftForm: GiftRecipientForm {
        GiftRecipientForm(name: giftFormName, email: giftFormEmail, dob: giftFormDOB)
    }

    /// Collect -> review. Nothing is sent to the server until the second step
    /// is confirmed, so a typo is caught before a seat moves.
    func advanceGiftToReview() {
        guard giftForm.isValid else {
            giftError = T("Vui lòng nhập đầy đủ họ tên, email và ngày sinh của người nhận.",
                          "Please fill in the recipient's full name, email and date of birth.")
            return
        }
        giftError = ""
        giftFormStep = .review
    }

    /// Gifts exactly one ticket from the booking to a friend.
    func confirmGift() async {
        guard let context = giftTicketContext else { return }
        let form = giftForm
        guard form.isValid else {
            giftFormStep = .form
            giftError = T("Vui lòng nhập đầy đủ họ tên, email và ngày sinh của người nhận.",
                          "Please fill in the recipient's full name, email and date of birth.")
            return
        }

        giftBusy = true
        giftError = ""
        defer { giftBusy = false }

        struct GiftParams: Encodable {
            let p_booking_id: String
            let p_recipient_name: String
            let p_recipient_email: String
            let p_recipient_dob: String
            let p_idempotency_key: String
        }

        // One key per form session: a double tap, a retried request after a
        // dropped connection or a relaunch mid-flight all replay the server's
        // original answer instead of gifting a second seat. The server keys it
        // against the purchaser, so it is not a capability anyone else can use.
        let params = GiftParams(
            p_booking_id: context.id.uuidString,
            p_recipient_name: form.trimmedName,
            p_recipient_email: form.trimmedEmail,
            p_recipient_dob: Self.giftDateFormatter.string(from: form.dob),
            p_idempotency_key: giftIdempotencyKey(contextID: context.id, email: form.trimmedEmail)
        )

        do {
            let res: GiftTicketResult = try await SupabaseService.client
                .rpc("gift_ticket", params: params)
                .execute().value

            guard res.success else {
                giftError = giftErrorMessage(res.error ?? "")
                giftFormStep = .form
                return
            }

            giftResult = res
            giftFormStep = .done
            // Both exports come from the same RPC result the sheet then shows,
            // so the PDF can never disagree with what the server recorded.
            if let event = giftEvent(for: context.eventKey) {
                let document = giftDocument(from: res, event: event)
                giftPDFURL = writeExportFile(name: "banbe-gift-ticket-\(document.ticketCode).pdf",
                                             data: GiftTicketPDFGenerator.renderPDF(document: document, isEN: isEN))
                giftICSURL = writeExportFile(name: "banbe-event-\(context.eventKey).ics",
                                             data: GiftTicketPDFGenerator.renderICS(document: document))
            }

            // Refresh every list that shows this ticket, and patch the open
            // ticket screen if the gift was made from it.
            await loadPaymentBookings()
            if self.booking?.id == context.id {
                self.booking?.recipientName = res.recipientName
                self.booking?.recipientEmail = res.recipientEmail
                self.booking?.recipientDob = res.recipientDob
                self.booking?.claimCode = res.claimCode
                self.booking?.giftedAt = Date()
                self.booking?.admissionToken = res.admissionToken
                if let code = res.ticketCode { self.booking?.code = code }
            }
            Haptics.success()
        } catch {
            print("confirmGift failed:", error)
            giftError = T("Không thể tặng vé lúc này. Vui lòng thử lại sau.",
                          "Couldn't gift the ticket right now. Please try again later.")
        }
    }

    /// Reuses the purchaser's own address to key the request, so a retried
    /// submit of an unchanged form replays and a genuinely different recipient
    /// is treated as a different gift rather than silently reusing the old one.
    private func giftIdempotencyKey(contextID: UUID, email: String) -> String {
        "\(contextID.uuidString):\(email)"
    }

    private static let giftDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Builds the printable document from what the server just wrote, never
    /// from whatever the client hoped for.
    private func giftDocument(from res: GiftTicketResult, event: CatalogEvent) -> GiftTicketDocument {
        GiftTicketDocument(
            eventName: event.name,
            organizer: event.orgName.isEmpty ? event.host : event.orgName,
            startDate: event.startDate,
            whenText: event.when,
            venue: event.locationLabel ?? event.where,
            details: event.desc,
            recipientName: res.recipientName ?? giftForm.trimmedName,
            ticketCode: res.ticketCode ?? "",
            admissionToken: res.admissionToken ?? UUID(),
            claimCode: res.claimCode,
            reference: res.bookingId?.uuidString ?? ""
        )
    }

    /// The catalogue entry for a real (host-created) event when one has been
    /// fetched, else the bundled demo entry. Same fallback the rest of the app
    /// uses for a real event's chrome.
    private func giftEvent(for eventKey: String) -> CatalogEvent? {
        if let real = realEventsByID[eventKey] ?? nil { return real }
        return EventCatalog.find(eventKey)
    }

    // MARK: - Recipient import

    /// Opens the import entry point. A code that arrives before there is a
    /// session is parked and re-offered after sign-in, so the link that sent
    /// them here still finishes the job.
    func openGiftImport(prefilledCode: String? = nil) {
        let code = (prefilledCode ?? pendingGiftClaimCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !isSignedIn {
            pendingGiftClaimCode = code
            giftImportCode = code
            giftImportError = ""
            giftImportNotice = ""
            requireAuth(returnTo: .accountGroup, backTo: .home)
            return
        }
        giftImportCode = code
        giftImportError = ""
        giftImportNotice = ""
        giftImportOpen = true
    }

    func closeGiftImport() {
        giftImportOpen = false
        giftImportBusy = false
        giftImportError = ""
    }

    /// Re-offered by the sign-in task once there IS a session
    /// (RootView's `.task(id: GateTaskKey)`), so the parked code is used
    /// rather than quietly dropped.
    func checkPendingGiftClaimOnSignIn() {
        guard let code = pendingGiftClaimCode, !code.isEmpty, isSignedIn else { return }
        giftImportCode = code
        giftImportError = ""
        giftImportNotice = ""
        giftImportOpen = true
    }

    /// Adds the gifted ticket to the signed-in account. The server decides
    /// whether this is the right account: it compares the authenticated,
    /// VERIFIED email against the recipient address, and a date of birth alone
    /// is never accepted as proof of ownership. A repeat import is safe.
    func claimGiftTicket() async {
        let code = giftImportCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            giftImportError = T("Vui lòng nhập mã nhận vé bạn được tặng.",
                                "Please enter the gift claim code you were given.")
            return
        }
        guard isSignedIn else {
            pendingGiftClaimCode = code
            requireAuth(returnTo: .accountGroup, backTo: .home)
            return
        }

        giftImportBusy = true
        giftImportError = ""
        giftImportNotice = ""
        defer { giftImportBusy = false }

        struct ClaimParams: Encodable { let p_claim_code: String }

        do {
            let res: GiftClaimResult = try await SupabaseService.client
                .rpc("claim_gift_ticket", params: ClaimParams(p_claim_code: code))
                .execute().value

            guard res.success else {
                giftImportError = giftErrorMessage(res.error ?? "", expectedEmail: res.expectedEmail)
                return
            }

            pendingGiftClaimCode = nil
            giftImportNotice = (res.alreadyClaimed ?? false)
                ? T("Vé này đã nằm trong tài khoản của bạn — không có vé nào khác được tạo thêm.",
                     "This ticket is already in your account — no extra ticket was created.")
                : T("Vé đã được thêm vào tài khoản của bạn. Không có vé nào khác được tạo thêm.",
                     "The ticket was added to your account. No extra ticket was created.")
            await loadPaymentBookings()
            await loadMyEvents()
            Haptics.success()
        } catch {
            print("claimGiftTicket failed:", error)
            giftImportError = T("Không thể nhận vé lúc này. Vui lòng thử lại.",
                                "Couldn't import the ticket right now. Please try again.")
        }
    }

    /// The server's error codes, in the reader's language. One switch, so the
    /// same code can never be explained two different ways on two screens.
    private func giftErrorMessage(_ errorKey: String, expectedEmail: String? = nil) -> String {
        switch errorKey {
        case "EMAIL_MISMATCH":
            if let expected = expectedEmail, !expected.isEmpty {
                return T("Email tài khoản không khớp. Vé này được tặng cho \(expected). Vui lòng đăng nhập đúng tài khoản.",
                         "Account email mismatch. This ticket was gifted to \(expected). Please sign in with that account.")
            }
            return T("Email tài khoản không khớp với email người nhận vé này.",
                     "Your account email does not match the recipient email for this gift.")
        case "EMAIL_NOT_VERIFIED":
            return T("Hãy xác minh email của tài khoản trước khi nhận vé. Ngày sinh không dùng để chứng minh bạn là người nhận.",
                     "Verify your account email before importing the ticket. A date of birth isn't proof you're the recipient.")
        case "INVALID_CLAIM_CODE":
            return T("Mã nhận vé không hợp lệ hoặc không tồn tại.",
                     "Invalid or nonexistent gift claim code.")
        case "ALREADY_CLAIMED":
            return T("Vé này đã được nhận bởi một tài khoản khác.",
                     "This ticket has already been imported by another account.")
        case "ALREADY_GIFTED":
            return T("Vé này đã được tặng trước đó.",
                     "This ticket has already been gifted.")
        case "NOT_ELIGIBLE", "TICKET_CANCELLED":
            return T("Vé không hợp lệ hoặc đã bị huỷ.",
                     "This ticket is not eligible or has been cancelled.")
        case "EVENT_ENDED":
            return T("Sự kiện đã kết thúc, không thể thực hiện thao tác này.",
                     "The event has ended, so this is unavailable.")
        case "NOT_AUTHORIZED":
            return T("Bạn không có quyền thực hiện thao tác này.",
                     "You are not authorized for this action.")
        case "BOOKING_NOT_FOUND", "NOT_FOUND":
            return T("Không tìm thấy vé này.",
                     "This ticket could not be found.")
        case "INVALID_EMAIL":
            return T("Email người nhận không hợp lệ.",
                     "Invalid recipient email.")
        case "INVALID_NAME":
            return T("Tên người nhận phải có ít nhất 2 ký tự.",
                     "Recipient name must be at least 2 characters.")
        case "INVALID_DOB":
            return T("Ngày sinh không hợp lệ.",
                     "Invalid date of birth.")
        case "AUTH_REQUIRED", "EMAIL_NOT_FOUND":
            return T("Hãy đăng nhập bằng email nhận vé để nhập vé này.",
                     "Please sign in with the recipient email to import this ticket.")
        case "GATE_REQUIRED":
            return T("Tài khoản của bạn chưa hoàn tất xác minh nên chưa thể nhập vé.",
                     "Finish verifying your account before importing a ticket.")
        default:
            return T("Đã có lỗi xảy ra. Vui lòng thử lại.",
                     "Something went wrong. Please try again.")
        }
    }

    // MARK: - PDF / calendar exports

    /// Re-derives the PDF for a ticket the purchaser is no longer attending
    /// with. Always from the CURRENT server row, never from a cached copy, so
    /// a re-download after the recipient claimed it still shows live truth.
    /// Same re-download for a screen that holds the ticket as a plain
    /// `Booking` (ConfirmedView).
    func exportGiftPDF(for booking: Booking) -> URL? {
        guard let event = giftEvent(for: booking.eventId) else { return nil }
        let document = GiftTicketDocument.make(booking: booking, event: event)
        return writeExportFile(name: "banbe-gift-ticket-\(document.ticketCode).pdf",
                               data: GiftTicketPDFGenerator.renderPDF(document: document, isEN: isEN))
    }

    func exportGiftPDF(for payable: PayableBooking) {
        guard let event = giftEvent(for: payable.eventKey) else {
            giftPDFURL = nil
            return
        }
        let document = GiftTicketDocument.make(payable: payable, event: event)
        let url = writeExportFile(name: "banbe-gift-ticket-\(document.ticketCode).pdf",
                                  data: GiftTicketPDFGenerator.renderPDF(document: document, isEN: isEN))
        giftPDFURL = url
    }

    func exportGiftICS(for payable: PayableBooking) {
        guard let event = giftEvent(for: payable.eventKey) else {
            giftICSURL = nil
            return
        }
        let document = GiftTicketDocument.make(payable: payable, event: event)
        giftICSURL = writeExportFile(name: "banbe-event-\(payable.eventKey).ics",
                                     data: GiftTicketPDFGenerator.renderICS(document: document))
    }

    private func writeExportFile(name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("writeExportFile failed:", error)
            return nil
        }
    }

    // MARK: - Event lifecycle

    /// Whether an event has ended, checking the bundled catalogue and the
    /// real event row. Used to move a finished gift out of the active ticket
    /// list WITHOUT changing any financial status — a completed event is not a
    /// cancelled one, and the purchase keeps its refund record either way.
    func isEventEnded(eventKey: String) -> Bool {
        if let cat = EventCatalog.find(eventKey) {
            let merged = cat.applyingLiveStatus(homeLiveEvents[eventKey])
            if merged.endedHoursAgo != nil { return true }
            if let start = merged.startDate, start < Date().addingTimeInterval(-4 * 3600) { return true }
        }
        if let real = realEventsByID[eventKey] ?? nil {
            if real.endedHoursAgo != nil { return true }
            if let start = real.startDate, start < Date().addingTimeInterval(-4 * 3600) { return true }
        }
        return false
    }

    /// A gift whose event is over belongs with the finished rows, not the
    /// live ones. Read-only: no status is written, so the purchase is never
    /// turned into a cancellation it wasn't.
    func isFinishedGift(_ payable: PayableBooking) -> Bool {
        payable.isGifted && isEventEnded(eventKey: payable.eventKey)
    }
}
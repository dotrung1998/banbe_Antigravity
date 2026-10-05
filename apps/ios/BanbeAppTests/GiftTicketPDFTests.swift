import XCTest
import PDFKit
@testable import BanbeApp

/// Migration 132 — the gift ticket's printable/claimable artifacts.
///
/// The two credentials a gift carries are deliberately tested apart here: the
/// ADMISSION token is what the printed QR encodes and the door reads, and the
/// CLAIM code is the account-import secret that must never appear on the page
/// a stranger could photograph.
final class GiftTicketPDFTests: XCTestCase {

    private func document(claimCode: String? = "CLAIM-DEADBEEF") -> GiftTicketDocument {
        GiftTicketDocument(
            eventName: "Midnight Rooftop",
            organizer: "banbe Collective",
            startDate: Date(timeIntervalSince1970: 1_790_000_000),
            whenText: "20:00 · 14/03/2026",
            venue: "42 Nguyễn Huệ, Quận 1",
            details: "Doors at 19:30.",
            recipientName: "Bảo Châu Nguyễn",
            ticketCode: "GIFT-1A2B3C",
            admissionToken: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!,
            claimCode: claimCode,
            reference: "13200000-0000-4000-8000-000000000001"
        )
    }

    private func pdfText(_ data: Data) throws -> String {
        let pdf = try XCTUnwrap(PDFDocument(data: data), "the renderer produced an unreadable PDF")
        return (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    // MARK: - The document itself

    func testPDFIsOneReadablePage() throws {
        let data = GiftTicketPDFGenerator.renderPDF(document: document())
        XCTAssertFalse(data.isEmpty)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
    }

    func testPDFCarriesTheFactsTheDoorActuallyNeeds() throws {
        let text = try pdfText(GiftTicketPDFGenerator.renderPDF(document: document()))
        for expected in ["Bảo Châu Nguyễn", "Midnight Rooftop", "banbe Collective",
                         "42 Nguyễn Huệ, Quận 1", "GIFT-1A2B3C", "GMT+7"] {
            XCTAssertTrue(text.contains(expected), "gift PDF is missing \(expected)")
        }
        // The label that tells the holder this isn't their own purchase.
        XCTAssertTrue(text.uppercased().contains("GIFT") || text.contains("TẶNG"),
                      "the gift label is missing from the PDF")
    }

    /// The claim code is the account credential, not the door credential. It
    /// rides in the link annotation only — printing it would let anyone holding
    /// the sheet try to import the ticket.
    func testPDFNeverPrintsTheClaimCode() throws {
        let text = try pdfText(GiftTicketPDFGenerator.renderPDF(document: document()))
        XCTAssertFalse(text.contains("CLAIM-DEADBEEF"), "the claim code leaked into the visible PDF")
    }

    func testPDFWithNoClaimCodeStillRenders() throws {
        let data = GiftTicketPDFGenerator.renderPDF(document: document(claimCode: nil))
        XCTAssertEqual(try XCTUnwrap(PDFDocument(data: data)).pageCount, 1)
    }

    // MARK: - Links: real destinations only

    func testPDFLinksPointAtRealDestinations() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: GiftTicketPDFGenerator.renderPDF(document: document())))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let links = page.annotations.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(links.count, 4, "expected exactly Wallet, Apple Calendar, Google Calendar and import")

        // Wallet: keyed by the admission token (what the QR already carries),
        // never by the claim code.
        let walletLink = try XCTUnwrap(links.first { $0.contains("/api/wallet-pass") })
        XCTAssertTrue(walletLink.contains("gift=\(document().admissionToken.uuidString.lowercased())"))
        XCTAssertFalse(walletLink.contains("CLAIM-DEADBEEF"), "claim code leaked into the Wallet link")
        XCTAssertNotNil(links.first { $0.hasPrefix("webcal://") }, "Apple Calendar link missing")

        let importLink = try XCTUnwrap(links.first { $0.hasPrefix("banbe://") })
        XCTAssertTrue(importLink.contains("code=CLAIM-DEADBEEF"))

        let calendarLink = try XCTUnwrap(links.first { $0.hasPrefix("https://calendar.google.com") })
        XCTAssertTrue(calendarLink.contains("action=TEMPLATE"))

        // No invented destinations: this deployment serves no banbe.app and has
        // no App Store listing, so neither may appear as a link.
        for link in links {
            XCTAssertFalse(link.contains("banbe.app"), "invented banbe.app link: \(link)")
            XCTAssertFalse(link.lowercased().contains("apps.apple.com"), "invented App Store link: \(link)")
            XCTAssertFalse(link.lowercased().contains("testflight"), "invented TestFlight link: \(link)")
        }
    }

    func testClaimURLUsesTheRegisteredScheme() throws {
        let url = try XCTUnwrap(GiftTicketPDFGenerator.claimURL(for: "CLAIM-ABC12345"))
        XCTAssertEqual(url.scheme, "banbe")
        XCTAssertEqual(url.host, "gift")
        XCTAssertEqual(url.path, "/claim")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value, "CLAIM-ABC12345")
        XCTAssertNil(GiftTicketPDFGenerator.claimURL(for: ""))
    }

    // MARK: - The QR is the admission credential

    func testQREncodesTheAdmissionTokenAndNothingElse() throws {
        let token = document().admissionToken
        XCTAssertNotNil(GiftTicketPDFGenerator.generateQRCodeImage(token.uuidString, size: 120),
                        "no QR could be generated for the admission token")
        // The claim code must never be a scannable payload either.
        XCTAssertNotEqual(token.uuidString, "CLAIM-DEADBEEF")
    }

    // MARK: - Calendar

    func testICSCarriesTheEventAndNotTheClaimSecret() throws {
        let ics = String(decoding: GiftTicketPDFGenerator.renderICS(document: document()), as: UTF8.self)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("END:VCALENDAR"))
        XCTAssertTrue(ics.contains("SUMMARY:Midnight Rooftop"))
        XCTAssertTrue(ics.contains("DTSTART:"))
        XCTAssertTrue(ics.contains("DTEND:"))
        XCTAssertTrue(ics.contains("LOCATION:42 Nguyễn Huệ\\, Quận 1"), "the venue comma must be escaped")
        XCTAssertTrue(ics.contains("UID:\(document().admissionToken.uuidString)@banbe"))
        XCTAssertFalse(ics.contains("CLAIM-DEADBEEF"))
    }

    /// RFC 5545 requires commas, semicolons and backslashes to be escaped or
    /// the whole event is silently dropped by stricter calendar apps.
    func testICSEscapesReservedCharacters() {
        let doc = GiftTicketDocument(
            eventName: "Rock, Roll; Repeat \\ Again",
            organizer: "o", startDate: Date(timeIntervalSince1970: 1_790_000_000),
            whenText: "", venue: "A, B; C", details: "line one\nline two",
            recipientName: "R", ticketCode: "T1",
            admissionToken: UUID(), claimCode: nil, reference: "r")
        let ics = String(decoding: GiftTicketPDFGenerator.renderICS(document: doc), as: UTF8.self)
        XCTAssertTrue(ics.contains("SUMMARY:Rock\\, Roll\\; Repeat \\\\ Again"))
        XCTAssertTrue(ics.contains("LOCATION:A\\, B\\; C"))
        XCTAssertTrue(ics.contains("line one\\nline two"))
        XCTAssertFalse(ics.contains("SUMMARY:Rock, Roll; Repeat"), "unescaped reserved characters survived")
    }

    // MARK: - Form validation

    func testGiftRecipientFormRequiresNameEmailAndAPastDate() {
        let twentyYearsAgo = Calendar.current.date(byAdding: .year, value: -20, to: Date())!
        var form = GiftRecipientForm(name: "", email: "", dob: twentyYearsAgo)
        XCTAssertFalse(form.isValid, "an empty form must not be submittable")

        form.name = "Bảo"
        XCTAssertFalse(form.isValid, "a one-character name must not be submittable")

        form.name = "Bảo Châu"
        form.email = "not-an-email"
        XCTAssertFalse(form.isValid)

        form.email = "Chau@Example.COM "
        XCTAssertTrue(form.trimmedEmail == "chau@example.com", "email should be trimmed and lowercased")
        XCTAssertTrue(form.isValid)

        form.dob = Date().addingTimeInterval(86_400)
        XCTAssertFalse(form.isValid, "a date of birth in the future is not a date of birth")

        // No age floor is invented: a child is a valid recipient, because banbe
        // states no age restriction to enforce one against.
        form.dob = Calendar.current.date(byAdding: .year, value: -8, to: Date())!
        XCTAssertTrue(form.isValid)
    }

    // MARK: - Booking/credential plumbing

    func testBookingFallsBackToItsIDWhenNoAdmissionTokenWasDecoded() {
        let id = UUID()
        let booking = Booking(id: id, eventId: "e", userId: nil, qty: 1, totalVnd: 0, code: "C",
                              status: "confirmed", expiresAt: nil, paidMarkedAt: nil, cancelledAt: nil,
                              cancelReason: nil, createdAt: Date(), paymentState: .confirmed)
        XCTAssertEqual(booking.admissionQRCodeValue, id.uuidString,
                       "a row written before migration 132 must still scan as its own id")
        XCTAssertFalse(booking.isGifted)
    }

    func testGiftedBookingIsRecognisedAndIsNotStillThePurchasersTicket() {
        let booking = Booking(id: UUID(), eventId: "e", userId: UUID(), qty: 1, totalVnd: 0,
                              code: "GIFT-1234", status: "confirmed", expiresAt: nil, paidMarkedAt: nil,
                              cancelledAt: nil, cancelReason: nil, createdAt: Date(),
                              paymentState: .confirmed, recipientName: "Bảo Châu",
                              admissionToken: UUID())
        XCTAssertTrue(booking.isGifted)
        XCTAssertFalse(booking.isClaimed)
        XCTAssertNotEqual(booking.admissionQRCodeValue, booking.id.uuidString,
                          "a gifted seat must scan as its rotated token, not its row id")
    }

    // MARK: - The holder's own ticket ("Download PDF" on the confirmed screen)

    func testOwnTicketPDFIsATicketNotAGift() throws {
        let text = try pdfText(GiftTicketPDFGenerator.renderPDF(document: document(claimCode: nil), isEN: true, isOwnTicket: true))
        let flat = text.uppercased().filter { !$0.isWhitespace }   // tracked caps may extract letter-spaced
        XCTAssertTrue(flat.contains("TICKETHOLDER"))
        XCTAssertTrue(text.contains("Midnight Rooftop"))
        XCTAssertFalse(flat.contains("GIFTTICKET") || flat.contains("GIFTEDTO"), "an own ticket must not be labelled as a gift")
        XCTAssertFalse(text.contains("Apple Wallet"), "the gift wallet link must not appear on an own ticket")
        XCTAssertFalse(text.contains("Register & import"))
    }

    func testWalletSymbolsExistOnThisOS() {
        // A misspelt SF Symbol renders nothing, silently — in the app and in the PDF.
        XCTAssertNotNil(UIImage(systemName: "wallet.bifold"))
        XCTAssertNotNil(UIImage(systemName: "wallet.bifold.fill"))
    }

    func testAttendeePDFCarriesItsOwnImportLinkButNoWalletLink() throws {
        var doc = document(claimCode: "ATT-1234567890")
        doc.recipientName = "Bao Tran"
        let pdf = try XCTUnwrap(PDFDocument(data: GiftTicketPDFGenerator.renderPDF(document: doc, isEN: true, isOwnTicket: true)))
        let links = try XCTUnwrap(pdf.page(at: 0)).annotations.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(links.contains { $0.contains("gift/claim") && $0.contains("code=ATT-1234567890") },
                      "the attendee's PDF must carry the link that imports THAT ticket")
        XCTAssertFalse(links.contains { $0.contains("/api/wallet-pass") },
                       "the gift wallet link must not appear on an attendee ticket")
    }
}

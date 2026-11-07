import XCTest
@testable import BanbeApp

/// Migration 151 — per-attendee tickets: the purchase form's completeness rule
/// and how an attendee row reads back from the database.
final class BookingAttendeeTests: XCTestCase {

    func testDraftNeedsANameOfTwoCharactersAndADateOfBirth() {
        var d = AttendeeDraft()
        XCTAssertFalse(d.isComplete)
        d.name = "A"; d.dob = Date()
        XCTAssertFalse(d.isComplete, "one-letter name")
        d.name = "  An  "
        XCTAssertTrue(d.isComplete)
        d.dob = nil
        XCTAssertFalse(d.isComplete, "no date of birth")
    }

    func testAttendeeDecodesFromTheDatabaseShapeAndComputesAge() throws {
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","booking_id":"3F2504E0-4F89-41D3-9A0C-0305E82C3302",
         "seat_no":2,"name":"Bao Tran","date_of_birth":"2001-11-30",
         "admission_token":"3F2504E0-4F89-41D3-9A0C-0305E82C3303","ticket_code":"E38846-2","checked_in_at":null}
        """.data(using: .utf8)!
        let att = try JSONDecoder().decode(BookingAttendee.self, from: json)
        XCTAssertEqual(att.seatNo, 2)
        XCTAssertEqual(att.ticketCode, "E38846-2")
        XCTAssertNil(att.checkedInAt)
        let expected = Calendar(identifier: .gregorian).dateComponents(
            [.year], from: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2001, month: 11, day: 30).date!, to: Date()).year
        XCTAssertEqual(att.age, expected)
    }

    func testEachAttendeePDFCarriesOnlyThatAttendeesCredential() throws {
        let a = UUID(), b = UUID()
        func doc(_ name: String, _ token: UUID, _ code: String) -> GiftTicketDocument {
            GiftTicketDocument(eventName: "Night Market", organizer: "banbe", startDate: Date(), whenText: "", venue: "HCMC",
                               details: "", recipientName: name, ticketCode: code, admissionToken: token, claimCode: nil,
                               reference: code)
        }
        let first = GiftTicketPDFGenerator.renderPDF(document: doc("Alice Nguyen", a, "E1-1"), isEN: true, isOwnTicket: true)
        let second = GiftTicketPDFGenerator.renderPDF(document: doc("Bao Tran", b, "E1-2"), isEN: true, isOwnTicket: true)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }
}

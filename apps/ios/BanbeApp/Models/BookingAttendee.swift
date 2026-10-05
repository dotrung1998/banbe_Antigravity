import Foundation

/// One named ticket inside a booking (migration 151). Each attendee carries
/// their OWN admission token — what their QR encodes and what the door scans —
/// so one downloaded PDF admits one person, never the whole party.
struct BookingAttendee: Codable, Identifiable, Hashable {
    let id: UUID
    let bookingId: UUID
    let seatNo: Int
    let name: String
    /// "yyyy-MM-dd", exactly as Postgres returns a `date`.
    let dateOfBirth: String
    let admissionToken: UUID
    let ticketCode: String
    let checkedInAt: Date?
    /// The secret behind this attendee's "Open in banbe" link (migration 152).
    let claimCode: String?
    let claimedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case bookingId = "booking_id"
        case seatNo = "seat_no"
        case dateOfBirth = "date_of_birth"
        case admissionToken = "admission_token"
        case ticketCode = "ticket_code"
        case checkedInAt = "checked_in_at"
        case claimCode = "claim_code"
        case claimedAt = "claimed_at"
    }

    /// Whole years today, or nil if the stored date can't be read.
    var age: Int? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let dob = f.date(from: dateOfBirth) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: dob, to: Date()).year
    }
}

/// A row of the purchase form, before anything is sent.
struct AttendeeDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var dob: Date?

    var isComplete: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && dob != nil
    }
}

struct HoldSeatsWithAttendeesParams: Encodable {
    struct Attendee: Encodable { let name: String; let dob: String }
    let event: String
    let attendees: [Attendee]
    enum CodingKeys: String, CodingKey {
        case event = "p_event"
        case attendees = "p_attendees"
    }
}

/// A ticket another account imported into THIS account (migration 152) —
/// one row of get_my_imported_tickets(). The booking, its payment and refunds
/// stay with the buyer; this account only holds the one named ticket.
struct ImportedTicket: Codable, Identifiable, Hashable {
    let attendeeId: UUID
    let bookingId: UUID
    let seatNo: Int
    let name: String
    let admissionToken: UUID
    let ticketCode: String
    let checkedInAt: Date?
    let eventId: String
    let eventKey: String?
    let eventName: String
    let startsAt: Date?
    let eventStatus: String?
    let bookingStatus: String?
    let claimedAt: Date?
    var id: UUID { attendeeId }

    /// Cancelled booking or event: shown, but struck out and not scannable.
    var isVoid: Bool { bookingStatus == "cancelled" || bookingStatus == "expired" || eventStatus == "cancelled" }

    enum CodingKeys: String, CodingKey {
        case attendeeId = "attendee_id", bookingId = "booking_id", seatNo = "seat_no", name
        case admissionToken = "admission_token", ticketCode = "ticket_code", checkedInAt = "checked_in_at"
        case eventId = "event_id", eventKey = "event_key", eventName = "event_name", startsAt = "starts_at"
        case eventStatus = "event_status", bookingStatus = "booking_status", claimedAt = "claimed_at"
    }
}

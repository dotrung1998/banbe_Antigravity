import Foundation

/// What the gifting form is acting on. Deliberately a small value type rather
/// than the `Booking`/`PayableBooking` pair the two entry points happen to hold
/// (`ConfirmedView` has a `Booking`, Tickets & Bookings has a `PayableBooking`)
/// so the sheet has one input either way and neither screen has to convert.
struct GiftTicketContext: Identifiable, Equatable {
    /// The booking row the seat is transferred FROM. For a multi-seat booking
    /// this is the purchase; the server splits exactly one seat out of it.
    let id: UUID
    let eventKey: String
    let eventName: String
    /// Seats on this booking, so the review step can say "1 of 3 seats" rather
    /// than implying the whole booking changes hands.
    let seats: Int
    /// Already gifted — the caller must not offer a second gift, but the PDF
    /// re-download path reuses the same context shape.
    let isGifted: Bool
    let recipientName: String?

    init(booking: Booking, eventName: String = "") {
        self.init(id: booking.id, eventKey: booking.eventId, eventName: eventName, seats: booking.qty,
                  isGifted: booking.isGifted, recipientName: booking.recipientName)
    }

    init(payable: PayableBooking) {
        self.init(id: payable.id, eventKey: payable.eventKey, eventName: payable.eventName,
                  seats: payable.qty, isGifted: payable.isGifted,
                  recipientName: payable.recipientName)
    }

    init(id: UUID, eventKey: String, eventName: String, seats: Int, isGifted: Bool, recipientName: String?) {
        self.id = id
        self.eventKey = eventKey
        self.eventName = eventName
        self.seats = seats
        self.isGifted = isGifted
        self.recipientName = recipientName
    }
}

/// The gifting sheet is two explicit steps — collect, then review — so the
/// person being named is never discovered only after the server has already
/// moved a seat.
enum GiftFormStep: Equatable {
    case form
    case review
    case done
}

/// Form payload when gifting a ticket to a friend.
struct GiftRecipientForm {
    var name: String = ""
    var email: String = ""
    var dob: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// A real name, a real email, and a date of birth that has actually
    /// happened. No age rule is invented here — banbe sells no age-restricted
    /// event class of its own, so a minimum age would be a restriction this
    /// product never states. The server enforces exactly the same three.
    var isValid: Bool {
        trimmedName.count >= 2 && trimmedEmail.contains("@") && trimmedEmail.contains(".")
            && dob <= Calendar.current.startOfDay(for: Date())
    }
}

/// RPC result from `gift_ticket`.
struct GiftTicketResult: Decodable {
    let success: Bool
    let alreadyGifted: Bool?
    let bookingId: UUID?
    let admissionToken: UUID?
    let ticketCode: String?
    let claimCode: String?
    let recipientName: String?
    let recipientEmail: String?
    let recipientDob: String?
    let eventId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyGifted = "already_gifted"
        case bookingId = "booking_id"
        case admissionToken = "admission_token"
        case ticketCode = "ticket_code"
        case claimCode = "claim_code"
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case recipientDob = "recipient_dob"
        case eventId = "event_id"
        case error
    }
}

/// RPC result from `claim_gift_ticket`.
struct GiftClaimResult: Decodable {
    let success: Bool
    let alreadyClaimed: Bool?
    let bookingId: UUID?
    let eventId: String?
    let expectedEmail: String?
    let actualEmail: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case alreadyClaimed = "already_claimed"
        case bookingId = "booking_id"
        case eventId = "event_id"
        case expectedEmail = "expected_email"
        case actualEmail = "actual_email"
        case error
    }
}

/// Everything the gift PDF needs, resolved from whichever booking model the
/// calling screen holds. `admissionToken` and `claimCode` are kept apart on
/// purpose: the first is the door credential that is printed and scanned, the
/// second is the account-claim secret that must never be printed.
struct GiftTicketDocument {
    var eventName: String
    var organizer: String
    var startDate: Date?
    var whenText: String
    var venue: String
    var details: String
    var recipientName: String
    var ticketCode: String
    var admissionToken: UUID
    var claimCode: String?
    var reference: String

    static func make(booking: Booking, event: CatalogEvent) -> GiftTicketDocument {
        GiftTicketDocument(
            eventName: event.name,
            organizer: event.orgName.isEmpty ? event.host : event.orgName,
            startDate: event.startDate,
            whenText: event.when,
            venue: event.locationLabel ?? event.where,
            details: event.desc,
            recipientName: booking.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            ticketCode: booking.code ?? "",
            admissionToken: booking.admissionToken ?? booking.id,
            claimCode: booking.claimCode,
            reference: booking.id.uuidString
        )
    }

    /// `event` is optional: an ended event may no longer be in the catalogue or
    /// the live cache, and the purchaser must still be able to re-download the
    /// PDF from what the booking itself carries.
    static func make(payable: PayableBooking, event: CatalogEvent?) -> GiftTicketDocument {
        GiftTicketDocument(
            eventName: (event?.name.isEmpty == false ? event?.name : nil) ?? payable.eventName,
            organizer: event.map { $0.orgName.isEmpty ? $0.host : $0.orgName } ?? payable.organizerName,
            startDate: event?.startDate,
            whenText: event?.when ?? "",
            venue: event.map { $0.locationLabel ?? $0.where } ?? "",
            details: event?.desc ?? "",
            recipientName: payable.recipientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            ticketCode: payable.code,
            admissionToken: payable.admissionToken ?? payable.id,
            claimCode: payable.claimCode,
            reference: payable.id.uuidString
        )
    }
}
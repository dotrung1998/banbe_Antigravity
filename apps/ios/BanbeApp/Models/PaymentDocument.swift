import Foundation

/// One row of `payment_documents` (supabase migration 024) — an invoice or
/// a receipt.
///
/// Every party and amount here is the snapshot frozen when the document was
/// issued, never a live join, which is why these are plain values rather
/// than ids to look up. An organizer renaming themselves next month must not
/// rewrite a receipt somebody already downloaded.
struct PaymentDocument: Codable, Identifiable, Hashable {
    let id: UUID
    var bookingId: UUID
    var eventId: String?
    var organizerId: String?
    var userId: UUID?
    var kind: String          // "invoice" | "receipt"
    var number: String
    var issuedAt: Date
    var seller: DocumentParty
    var buyer: DocumentParty
    var event: DocumentEvent
    var lines: [DocumentLine]
    var totalVnd: Int
    var payMethod: String
    var paidAt: Date?
    var note: String

    var isReceipt: Bool { kind == "receipt" }

    enum CodingKeys: String, CodingKey {
        case id, kind, number, seller, buyer, event, lines, note
        case bookingId = "booking_id"
        case eventId = "event_id"
        case organizerId = "organizer_id"
        case userId = "user_id"
        case issuedAt = "issued_at"
        case totalVnd = "total_vnd"
        case payMethod = "pay_method"
        case paidAt = "paid_at"
    }
}

struct DocumentParty: Codable, Hashable {
    var name: String?
    var address: String?
    var phone: String?
    var taxCode: String?
    var bankName: String?
    var bankAccountName: String?
    var bankAccountNo: String?
    var momoPhone: String?

    enum CodingKeys: String, CodingKey {
        case name, address, phone
        case taxCode = "tax_code"
        case bankName = "bank_name"
        case bankAccountName = "bank_account_name"
        case bankAccountNo = "bank_account_no"
        case momoPhone = "momo_phone"
    }
}

struct DocumentEvent: Codable, Hashable {
    var id: String?
    var key: String?
    var name: String?
    var area: String?
    var bookingCode: String?

    enum CodingKeys: String, CodingKey {
        case id, key, name, area
        case bookingCode = "booking_code"
    }
}

struct DocumentLine: Codable, Hashable {
    var description: String?
    var qty: Int?
    var unitVnd: Int?
    var amountVnd: Int?

    enum CodingKeys: String, CodingKey {
        case description, qty
        case unitVnd = "unit_vnd"
        case amountVnd = "amount_vnd"
    }
}

/// A booking of the signed-in account's, with enough of the organizer's
/// payment details attached to actually pay it.
struct PayableBooking: Identifiable, Hashable {
    let id: UUID
    var qty: Int
    var totalVnd: Int
    var code: String
    var status: String
    var paidMarkedAt: Date?
    var proofUploadedAt: Date?
    var eventName: String
    var organizerName: String
    var payMethods: [String]
    var bankName: String
    var bankAccountName: String
    var bankAccountNo: String
    var momoPhone: String
    var payNote: String

    var isPaid: Bool { paidMarkedAt != nil }
    var hasBank: Bool { payMethods.contains("bank") && !bankAccountNo.isEmpty }
    var hasMomo: Bool { payMethods.contains("momo") && !momoPhone.isEmpty }
    var hasAnyPayRail: Bool { hasBank || hasMomo }
}

/// Formats an amount the way the rest of the app does: Vietnamese grouping,
/// symbol last. Mirrors formatVnd() in src/lib/paymentDocument.js.
func formatVnd(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.groupingSize = 3
    return (formatter.string(from: NSNumber(value: amount)) ?? "\(amount)") + "₫"
}

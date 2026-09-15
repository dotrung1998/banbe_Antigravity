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
    // Migration 056 — organizer-uploaded file replacing auto-generation.
    // All nil/absent on a legacy, pre-upload document (falls back to the
    // rendered-HTML viewer — see DocumentViewerView).
    var filePath: String?
    var uploadedBy: UUID?
    var uploadReason: String?
    var supersededAt: Date?
    var purgeAfter: Date?

    var isReceipt: Bool { kind == "receipt" }
    var isUploaded: Bool { filePath?.isEmpty == false }

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
        case filePath = "file_path"
        case uploadedBy = "uploaded_by"
        case uploadReason = "upload_reason"
        case supersededAt = "superseded_at"
        case purgeAfter = "purge_after"
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
/// The two-phase payment machine's states (migration 026). `holding` runs a
/// countdown; `pendingVerification` deliberately has none — the seat is
/// frozen until someone verifies it.
enum PaymentPhase: String, Codable {
    case holding
    case pendingVerification = "pending_verification"
    case confirmed
    case expired
    case disputed
    case cancelled

    /// Whether a countdown should be shown at all. Showing one in PHASE 2
    /// tells a buyer who has just paid that they are about to lose the seat.
    var isCountingDown: Bool { self == .holding }
}

struct PayableBooking: Identifiable, Hashable {
    let id: UUID
    /// The event's own key/id — bookings.event_id — used to remove this
    /// event from `attending` the instant its hold is forfeited.
    var eventKey: String
    var qty: Int
    var totalVnd: Int
    var code: String
    var status: String
    var paymentState: PaymentPhase
    var paymentRef: String
    var holdExpiresAt: Date?
    var transactionId: String
    var verifyDueAt: Date?
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
    /// Set by reject_payment() ("Can't find it") — non-nil/non-empty means
    /// a dispute_threads row already exists for this booking even though
    /// paymentState is still .pendingVerification (escalate_payment_dispute
    /// hasn't run). See PaymentViews.swift's needsInfoCard.
    var disputeReason: String?

    var isPaid: Bool { paymentState == .confirmed || paidMarkedAt != nil }
    var isFrozen: Bool { paymentState == .pendingVerification }
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

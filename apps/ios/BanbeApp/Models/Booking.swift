import Foundation

/// Mirrors the `bookings` table (aka `reservations` view). `status` follows
/// the `booking_status` enum: pending, confirmed, cancelled, expired,
/// no_show, attended.
struct Booking: Codable, Identifiable, Hashable {
    let id: UUID
    var eventId: String
    var userId: UUID?
    var qty: Int
    var totalVnd: Int
    var code: String?
    var status: String
    var expiresAt: Date?
    var paidMarkedAt: Date?
    var cancelledAt: Date?
    var cancelReason: String?
    var createdAt: Date
    // The two-phase payment machine (migration 026). `select('*')` and
    // `select()` (its shorthand) already return these — this struct just
    // wasn't decoding them, which is why the ticket screen fell back to the
    // pre-state-machine `status`/`expiresAt` fields for its phase logic
    // instead of the columns that are actually authoritative now.
    var paymentState: PaymentPhase = .holding
    var paymentRef: String?
    var holdExpiresAt: Date?
    var verifyDueAt: Date?
    var transactionId: String?
    var purchaserId: UUID?
    var recipientName: String?
    var recipientEmail: String?
    var recipientDob: String?
    var giftedAt: Date?
    var claimCode: String?
    var claimedAt: Date?
    var claimedByUserId: UUID?
    var admissionToken: UUID?
    var originalBookingId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case userId = "user_id"
        case qty
        case totalVnd = "total_vnd"
        case code
        case status
        case expiresAt = "expires_at"
        case paidMarkedAt = "paid_marked_at"
        case cancelledAt = "cancelled_at"
        case cancelReason = "cancel_reason"
        case createdAt = "created_at"
        case paymentState = "payment_state"
        case paymentRef = "payment_ref"
        case holdExpiresAt = "hold_expires_at"
        case verifyDueAt = "verify_due_at"
        case transactionId = "transaction_id"
        case purchaserId = "purchaser_id"
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case recipientDob = "recipient_dob"
        case giftedAt = "gifted_at"
        case claimCode = "claim_code"
        case claimedAt = "claimed_at"
        case claimedByUserId = "claimed_by_user_id"
        case admissionToken = "admission_token"
        case originalBookingId = "original_booking_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventId = try c.decode(String.self, forKey: .eventId)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        qty = try c.decode(Int.self, forKey: .qty)
        totalVnd = try c.decode(Int.self, forKey: .totalVnd)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        status = try c.decode(String.self, forKey: .status)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        paidMarkedAt = try c.decodeIfPresent(Date.self, forKey: .paidMarkedAt)
        cancelledAt = try c.decodeIfPresent(Date.self, forKey: .cancelledAt)
        cancelReason = try c.decodeIfPresent(String.self, forKey: .cancelReason)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Defensive default: a booking row selected before migration 026 (or
        // by an older cached response) simply has no payment_state column —
        // that must read as PHASE 1, not crash the decode.
        paymentState = try c.decodeIfPresent(PaymentPhase.self, forKey: .paymentState) ?? .holding
        paymentRef = try c.decodeIfPresent(String.self, forKey: .paymentRef)
        holdExpiresAt = try c.decodeIfPresent(Date.self, forKey: .holdExpiresAt)
        verifyDueAt = try c.decodeIfPresent(Date.self, forKey: .verifyDueAt)
        transactionId = try c.decodeIfPresent(String.self, forKey: .transactionId)
        purchaserId = try c.decodeIfPresent(UUID.self, forKey: .purchaserId)
        recipientName = try c.decodeIfPresent(String.self, forKey: .recipientName)
        recipientEmail = try c.decodeIfPresent(String.self, forKey: .recipientEmail)
        recipientDob = try c.decodeIfPresent(String.self, forKey: .recipientDob)
        giftedAt = try c.decodeIfPresent(Date.self, forKey: .giftedAt)
        claimCode = try c.decodeIfPresent(String.self, forKey: .claimCode)
        claimedAt = try c.decodeIfPresent(Date.self, forKey: .claimedAt)
        claimedByUserId = try c.decodeIfPresent(UUID.self, forKey: .claimedByUserId)
        admissionToken = try c.decodeIfPresent(UUID.self, forKey: .admissionToken)
        originalBookingId = try c.decodeIfPresent(UUID.self, forKey: .originalBookingId)
    }

    init(id: UUID, eventId: String, userId: UUID?, qty: Int, totalVnd: Int, code: String?,
        status: String, expiresAt: Date?, paidMarkedAt: Date?, cancelledAt: Date?,
        cancelReason: String?, createdAt: Date, paymentState: PaymentPhase = .holding,
        paymentRef: String? = nil, holdExpiresAt: Date? = nil, verifyDueAt: Date? = nil,
        transactionId: String? = nil, purchaserId: UUID? = nil, recipientName: String? = nil,
        recipientEmail: String? = nil, recipientDob: String? = nil, giftedAt: Date? = nil,
        claimCode: String? = nil, claimedAt: Date? = nil, claimedByUserId: UUID? = nil,
        admissionToken: UUID? = nil, originalBookingId: UUID? = nil) {
        self.id = id; self.eventId = eventId; self.userId = userId; self.qty = qty
        self.totalVnd = totalVnd; self.code = code; self.status = status
        self.expiresAt = expiresAt; self.paidMarkedAt = paidMarkedAt
        self.cancelledAt = cancelledAt; self.cancelReason = cancelReason; self.createdAt = createdAt
        self.paymentState = paymentState; self.paymentRef = paymentRef
        self.holdExpiresAt = holdExpiresAt; self.verifyDueAt = verifyDueAt
        self.transactionId = transactionId
        self.purchaserId = purchaserId
        self.recipientName = recipientName
        self.recipientEmail = recipientEmail
        self.recipientDob = recipientDob
        self.giftedAt = giftedAt
        self.claimCode = claimCode
        self.claimedAt = claimedAt
        self.claimedByUserId = claimedByUserId
        self.admissionToken = admissionToken
        self.originalBookingId = originalBookingId
    }

    /// TASK B (2026-10-01 UX foundation pass) — the ONE shared rule for
    /// "does a real ticket exist yet": BOTH `status == "confirmed"` AND
    /// `paymentState == .confirmed`, never either alone. Any screen that
    /// wants to show ticket QR / check-in code / "Xem vé" must check this,
    /// not re-derive its own condition.
    var isTicket: Bool { status == "confirmed" && paymentState == .confirmed }

    /// A gifted ticket has a recipient set.
    var isGifted: Bool { recipientName?.trimmingCharacters(in: .whitespaces).isEmpty == false }
    var isClaimed: Bool { claimedAt != nil }

    /// Scannable admission credential — uses the rotated admission_token if present, falling back to id.
    var admissionQRCodeValue: String { (admissionToken ?? id).uuidString }
}

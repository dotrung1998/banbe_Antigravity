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
    }
}

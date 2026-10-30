import Foundation

/// The real `events` row's own status for whichever event is currently
/// open — the Swift counterpart of the same-named fetch in BanBeContext.jsx.
/// Unlike `Booking`, this has nothing to do with a signed-in account: an
/// event being cancelled or having ended is public information, so this is
/// fetched for every visitor regardless of session.
struct LiveEventStatus: Codable, Hashable {
    var status: String
    var startsAt: Date?
    var cancelledAt: Date?
    var cancelReason: String?
    /// Migration 203: the event type facts + capacity, so a bundled catalogue event (whose text is static) still
    /// shows the facts its real row carries. nil when not selected or not on the server.
    var details: EventDetailsPayload?
    var capacity: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case startsAt = "starts_at"
        case cancelledAt = "cancelled_at"
        case cancelReason = "cancel_reason"
        case details, capacity
    }
}

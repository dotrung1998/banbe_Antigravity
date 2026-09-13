import Foundation

/// The real `events` row's own status for whichever event is currently
/// open — the Swift counterpart of the same-named fetch in GocContext.jsx.
/// Unlike `Booking`, this has nothing to do with a signed-in account: an
/// event being cancelled or having ended is public information, so this is
/// fetched for every visitor regardless of session.
struct LiveEventStatus: Codable, Hashable {
    var status: String
    var startsAt: Date?
    var cancelledAt: Date?
    var cancelReason: String?

    enum CodingKeys: String, CodingKey {
        case status
        case startsAt = "starts_at"
        case cancelledAt = "cancelled_at"
        case cancelReason = "cancel_reason"
    }
}

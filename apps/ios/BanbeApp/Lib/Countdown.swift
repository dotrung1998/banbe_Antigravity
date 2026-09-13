import Foundation

/// Shared countdown formatting — the Swift counterpart of src/lib/countdown.js.
/// One implementation so a PHASE 1 hold and a PHASE 2 SLA read identically
/// whether they're on Home, the ticket screen, or the organizer's queue.
enum Countdown {
    /// seconds -> "12:04" (or "1:02:04" past an hour). Never negative.
    static func format(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Seconds remaining until `date`, floored at 0.
    static func secondsUntil(_ date: Date?, now: Date = Date()) -> TimeInterval {
        guard let date else { return 0 }
        return max(0, date.timeIntervalSince(now))
    }

    /// Out of a list of bookings in a given phase, the one whose deadline is
    /// soonest AND still in the future — a lapsed deadline is excluded
    /// rather than sorted last, since it is moments from being swept to
    /// 'expired' by the cron job and showing a banner for it would be
    /// showing a hold that is effectively already gone.
    static func pickSoonest(_ bookings: [PayableBooking], phase: PaymentPhase,
                            deadline: (PayableBooking) -> Date?) -> PayableBooking? {
        bookings
            .filter { $0.paymentState == phase && secondsUntil(deadline($0)) > 0 }
            .sorted { (deadline($0) ?? .distantFuture) < (deadline($1) ?? .distantFuture) }
            .first
    }
}

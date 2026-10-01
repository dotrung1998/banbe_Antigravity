import Foundation

/// FIX PASS (2026-09-30) — ONE centralized enum deriving every numeric
/// badge shown anywhere in the app's navigation chain (child row -> group
/// card -> account tab -> dock icon), mirroring `src/lib/badges.js`
/// verbatim so the two platforms can never drift on what counts as a real
/// badge source or how they're summed. See that file's own top-of-file
/// comment for the full dedup/permission rules — restated briefly here:
///
/// - Every number is either the count of ONE distinct canonical array
///   (`app.pendingEventsCount`, `app.verifications`, `app.refundQueue`), or
///   the sum of two-or-more that are structurally guaranteed to never share
///   an item (different Postgres tables, different primary keys) — never a
///   sum of already-aggregated badges (that would double count).
/// - Admin counts are 0 (hidden) for anything but `accountType == "admin"`;
///   host counts are 0 (hidden) unless `organizerMode` is on — matching the
///   exact same gates `AccountView`'s own Admin/Host tabs already use.
/// - No badge is fabricated for Home/Map/static settings/the dock "+" —
///   nothing here computes a number for any of them.
enum AccountBadges {
    /// Admin's one real moderation queue today — the SAME number the
    /// "Sự kiện chờ duyệt" row / "Duyệt & kiểm duyệt" group card / Admin
    /// tab / Account dock icon all derive from.
    static func adminModerationCount(accountType: String, pendingEventsCount: Int) -> Int {
        guard accountType == "admin" else { return 0 }
        return pendingEventsCount
    }

    /// Host's real outstanding duties. `verifications` and `refundQueue`
    /// both ultimately route to the same Verifications screen
    /// (`app.openVerifications`/`onOpenRefundCenter` equivalents), so
    /// summing them here is exactly what that shared destination actually
    /// contains, not an invented aggregate.
    static func hostActionCount(organizerMode: Bool, verificationsCount: Int, refundQueueCount: Int) -> Int {
        guard organizerMode else { return 0 }
        return verificationsCount + refundQueueCount
    }

    /// Refund-discoverability fix — a dedicated "Refunds" row's own badge,
    /// same `refundQueueCount` term `hostActionCount` already sums in,
    /// never a second, differently-defined count.
    static func refundActionCount(organizerMode: Bool, refundQueueCount: Int) -> Int {
        guard organizerMode else { return 0 }
        return refundQueueCount
    }

    /// Account (dock/profile) icon badge — top of the whole chain. Sums
    /// admin + host counts (never each other's own already-summed value)
    /// since a real admin queue item and a real host queue item are always
    /// distinct underlying rows.
    static func accountDockBadge(accountType: String, organizerMode: Bool, pendingEventsCount: Int, verificationsCount: Int, refundQueueCount: Int) -> Int {
        adminModerationCount(accountType: accountType, pendingEventsCount: pendingEventsCount)
            + hostActionCount(organizerMode: organizerMode, verificationsCount: verificationsCount, refundQueueCount: refundQueueCount)
    }

    /// Personal-tab "Tickets & Bookings" group badge (Account IA reorg,
    /// 2026-09-30) — real bookings this account itself needs to act on: a
    /// still-holding/awaiting-payment/pending-verification booking (active
    /// status, not yet a real ticket per `Booking.isTicket`). Reads the
    /// SAME `paymentBookings` array `AccountView`'s own Action Center
    /// already loads (no new query) — a third view of one already-loaded
    /// array. Deliberately NOT summed into `accountDockBadge` — that chain
    /// is scoped to admin/host duties (see its own doc comment); this is a
    /// personal-tab-only signal mirroring `src/lib/badges.js`'s
    /// `computeMyTicketsActionCount` exactly.
    static func myTicketsActionCount(paymentBookings: [PayableBooking]) -> Int {
        paymentBookings.filter { b in
            ["pending", "confirmed", "attended"].contains(b.status) && !b.isTicket
        }.count
    }

    /// Shared "99+" cap for a badge that should not be limited to the
    /// existing "9+" convention (Notifications) — the exact count stays
    /// available to the caller for its own accessibility label.
    static func format(_ n: Int, cap: Int = 99) -> String {
        n > cap ? "\(cap)+" : "\(n)"
    }
}

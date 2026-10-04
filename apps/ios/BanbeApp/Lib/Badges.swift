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

    // Stale-badge fix pass — `app.refundQueue` (`get_host_refund_claims()`)
    // is every claim ever created for a host's events, not just outstanding
    // ones; `host_marked_sent`/`guest_confirmed`/`waived`/`resolved` all
    // stay in that array forever. Every call site below used to pass a raw
    // `.count`, which is exactly why a host could see the Refunds/
    // Verifications screen genuinely empty of actionable rows while the
    // badge still showed a leftover positive number from old history.
    // `RefundClaim.isActiveRefundStatus` (AppState+Payments.swift, already
    // the same canonical check `VerificationsView`'s own active-rows filter
    // uses) is reused here, not copied — mirrors `src/lib/badges.js`'s own
    // `countActionableRefunds` fix exactly: ONE place filters, every caller
    // just passes the raw array through.
    private static func actionableRefundCount(_ refundQueue: [RefundClaim]) -> Int {
        refundQueue.filter(\.isActiveRefundStatus).count
    }

    /// Host's real outstanding duties. `verifications` and `refundQueue`
    /// both ultimately route to the same Verifications screen
    /// (`app.openVerifications`/`onOpenRefundCenter` equivalents), so
    /// summing them here is exactly what that shared destination actually
    /// contains, not an invented aggregate.
    /// `holdingCount` is the "Guests holding seats" Things-to-do item, so the
    /// Host tab and the dock badge count it too (it used to be listed without
    /// ever being counted).
    static func hostActionCount(organizerMode: Bool, verificationsCount: Int, refundQueue: [RefundClaim], holdingCount: Int = 0) -> Int {
        guard organizerMode else { return 0 }
        return verificationsCount + actionableRefundCount(refundQueue) + holdingCount
    }

    /// Refund-discoverability fix — a dedicated "Refunds" row's own badge,
    /// same actionable-refund count `hostActionCount` already sums in,
    /// never a second, differently-defined count.
    static func refundActionCount(organizerMode: Bool, refundQueue: [RefundClaim]) -> Int {
        guard organizerMode else { return 0 }
        return actionableRefundCount(refundQueue)
    }

    /// Account (dock/profile) icon badge — top of the whole chain. Sums
    /// admin + host counts (never each other's own already-summed value)
    /// since a real admin queue item and a real host queue item are always
    /// distinct underlying rows.
    static func accountDockBadge(accountType: String, organizerMode: Bool, pendingEventsCount: Int, verificationsCount: Int, refundQueue: [RefundClaim], paymentBookings: [PayableBooking], myRefunds: [RefundClaim], holdingCount: Int = 0) -> Int {
        adminModerationCount(accountType: accountType, pendingEventsCount: pendingEventsCount)
            + hostActionCount(organizerMode: organizerMode, verificationsCount: verificationsCount, refundQueue: refundQueue, holdingCount: holdingCount)
            + personalActionCount(paymentBookings: paymentBookings, myRefunds: myRefunds)
    }

    /// Personal-tab "Tickets & Bookings" group badge (Account IA reorg,
    /// 2026-09-30) — real bookings this account itself needs to act on: a
    /// still-holding/awaiting-payment/pending-verification booking (active
    /// status, not yet a real ticket per `Booking.isTicket`). Reads the
    /// SAME `paymentBookings` array `AccountView`'s own Action Center
    /// already loads (no new query) — a third view of one already-loaded
    /// array. Part of `personalActionCount`, which `accountDockBadge` sums
    /// in. Mirrors `src/lib/badges.js`'s
    /// `computeMyTicketsActionCount` exactly.
    static func myTicketsActionCount(paymentBookings: [PayableBooking]) -> Int {
        paymentBookings.filter { b in
            ["pending", "confirmed", "attended"].contains(b.status) && !b.isTicket
        }.count
    }

    /// Goer-side refunds needing action — same three conditions as the
    /// goer items in `buildActionCenterItems`, once per distinct claim.
    /// Mirrors `computeMyRefundActionCount` in src/lib/badges.js.
    static func myRefundActionCount(myRefunds: [RefundClaim]) -> Int {
        myRefunds.filter { c in
            c.status == "host_marked_sent" || c.status == "disputed"
                || (c.status == "owed" && c.selectedDestinationId == nil)
        }.count
    }

    static func personalActionCount(paymentBookings: [PayableBooking], myRefunds: [RefundClaim]) -> Int {
        myTicketsActionCount(paymentBookings: paymentBookings) + myRefundActionCount(myRefunds: myRefunds)
    }

    /// Shared "99+" cap for a badge that should not be limited to the
    /// existing "9+" convention (Notifications) — the exact count stays
    /// available to the caller for its own accessibility label.
    static func format(_ n: Int, cap: Int = 99) -> String {
        n > cap ? "\(cap)+" : "\(n)"
    }
}

import Foundation

/// Notification kinds -> categories and the switch groups of Notification preferences. Pure, no SwiftUI.
/// A group is "on" while none of its kinds is in profiles.muted_notification_kinds (migration 062; the push sender
/// honours the same list, migration 194). Web twin: src/lib/notificationPrefs.js (same kinds, same semantics).
enum NotificationPrefs {
    struct Group: Identifiable, Equatable {
        let key: String
        let titleVi: String
        let titleEn: String
        let subVi: String
        let subEn: String
        let kinds: [String]
        var id: String { key }
    }

    /// Kind -> category (the Notifications glyphs).
    static let kindCategory: [String: String] = [
        "refund_marked_sent": "refund", "refund_confirmed": "refund", "refund_disputed": "refund", "refund_overdue": "refund",
        "dispute_message": "dispute", "dispute_resolved": "dispute", "payment_disputed": "dispute",
        "payment_awaiting_verification": "payment", "payment_confirmed": "payment", "payment_document_uploaded": "payment",
        "payment_document_replaced": "payment", "payment_verification_nudge": "payment", "payment_needs_info": "payment",
        "hold_created": "payment", "hold_expired": "payment",
        "booking_requested": "booking", "booking_cancelled": "booking", "booking_declined": "booking",
        "checked_in": "booking", "checkin_undo": "booking", "checkin_undone": "booking", "undo_check_in": "booking",
        "reject_pending_guest": "booking", "receipt_requested": "booking",
        "event_share": "event", "referral_joined": "event",
        "new_message": "message", "event_announcement": "message",
        "organizer_invite": "team", "organizer_invite_response": "team", "event_credit_invite": "team",
        "event_reminder_day": "reminder", "event_reminder_soon": "reminder",
        "event_recap": "event", "host_event_recap": "event", "follow_alert": "event", "weekly_digest": "event",
    ]

    private static let holds = ["hold_created", "hold_expired"]

    /// Kinds of the given categories, sorted so the list is deterministic (the web uses object-key order; only the
    /// SET matters to either side).
    private static func kinds(of cats: [String]) -> [String] {
        kindCategory.filter { cats.contains($0.value) }.map(\.key).sorted()
    }

    /// Disputes are never mutable (deadlines, admin decisions). The weekly digest has its own opt-in, and new
    /// messages are always delivered, so neither is muted through this list.
    static let groups: [Group] = [
        Group(key: "tickets", titleVi: "Vé", titleEn: "Tickets",
              subVi: "Xác nhận, giữ chỗ, check-in", subEn: "Confirmations, holds, check-in",
              kinds: kinds(of: ["booking"]) + holds),
        Group(key: "payments", titleVi: "Thanh toán", titleEn: "Payments",
              subVi: "Nhắc hạn thanh toán, hoàn tiền", subEn: "Pay-by reminders, refunds",
              kinds: kinds(of: ["payment", "refund"]).filter { !holds.contains($0) }),
        Group(key: "events", titleVi: "Sự kiện", titleEn: "Events",
              subVi: "Thông báo, nhắc nhở, host bạn theo dõi", subEn: "Announcements, reminders, hosts you follow",
              kinds: (kinds(of: ["event", "reminder", "team"]) + ["event_announcement"]).filter { $0 != "weekly_digest" }),
    ]

    static func isOn(_ muted: [String], _ group: Group) -> Bool {
        !group.kinds.contains { muted.contains($0) }
    }

    /// The muted list after flipping one group: on -> add all its kinds, off -> remove them.
    static func toggled(_ muted: [String], _ group: Group) -> [String] {
        if isOn(muted, group) {
            var out = muted
            for k in group.kinds where !out.contains(k) { out.append(k) }
            return out
        }
        return muted.filter { !group.kinds.contains($0) }
    }

    /// One-line summary ("All on", "2 of 3 on", "All off").
    static func summary(_ muted: [String], isEN: Bool) -> String {
        let n = groups.filter { isOn(muted, $0) }.count
        let total = groups.count
        if n == total { return isEN ? "All on" : "Đang bật hết" }
        if n == 0 { return isEN ? "All off" : "Đang tắt hết" }
        return isEN ? "\(n) of \(total) on" : "Bật \(n)/\(total)"
    }
}

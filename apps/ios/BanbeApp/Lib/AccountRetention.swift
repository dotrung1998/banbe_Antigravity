import Foundation

// "Before you go" pop-up in front of account deletion (owner, 2026-10-21; from "We Studied 393 Cancel Flows. This
// Wins People Back."): show what the person would lose, ask why, and offer the one fix that matches the reason —
// with deletion always one plain tap away (no confirmshaming, App Store 5.1.1(v)). Pure logic, unit-tested.
// Web twin: src/lib/accountRetention.js — change both together.

/// The fix offered for a leaving reason.
enum RetentionOffer: String, Equatable {
    /// Turn off host promo messages + mute event announcements; booking/payment/refund alerts stay on.
    case quieterNotifications
    /// Re-answer the For You questions.
    case retuneForYou
    /// Open Security & privacy settings.
    case reviewPrivacy
    /// Sign out instead — the account, tickets and history are kept.
    case takeABreak
}

enum AccountRetention {
    /// Same codes the server's `delete_account` accepts as `reasonCode`.
    static let reasons: [(code: String, vi: String, en: String)] = [
        ("not_using", "Tôi không còn dùng banbe nữa", "I don't use banbe anymore"),
        ("privacy", "Lo ngại về quyền riêng tư", "Privacy concerns"),
        ("found_alternative", "Tôi dùng ứng dụng khác", "I use a different app"),
        ("too_many_notifications", "Quá nhiều thông báo/email", "Too many notifications/emails"),
        ("other", "Khác", "Other"),
        ("prefer_not_say", "Không muốn cung cấp", "Prefer not to say"),
    ]

    /// Notification kinds "quieter notifications" mutes. Only the broadcast kind — every transactional
    /// kind (bookings, payments, refunds, disputes, check-in) stays on.
    static let quietedNotificationKinds = ["event_announcement"]

    /// nil = no reason picked yet (the pop-up then shows only Keep / Continue deleting).
    static func offer(for reason: String) -> RetentionOffer? {
        switch reason {
        case "too_many_notifications": return .quieterNotifications
        case "not_using": return .retuneForYou
        case "privacy": return .reviewPrivacy
        case "found_alternative", "other", "prefer_not_say": return .takeABreak
        default: return nil
        }
    }

    enum LossKind: String, Equatable { case bookedEvents, savedEvents, followedHosts, coins, hostedEvents }

    struct LossRow: Equatable {
        let kind: LossKind
        let count: Int
    }

    /// What deleting would take away, most valuable first. Zero rows are left out; coins only while the
    /// Rewards feature switch is on (note 51).
    static func lossRows(bookedEvents: Int, savedEvents: Int, followedHosts: Int,
                         coins: Int?, rewardsEnabled: Bool, hostedEvents: Int) -> [LossRow] {
        var rows: [LossRow] = [
            LossRow(kind: .bookedEvents, count: bookedEvents),
            LossRow(kind: .hostedEvents, count: hostedEvents),
            LossRow(kind: .savedEvents, count: savedEvents),
            LossRow(kind: .followedHosts, count: followedHosts),
        ]
        if rewardsEnabled, let coins { rows.append(LossRow(kind: .coins, count: coins)) }
        return rows.filter { $0.count > 0 }
    }
}

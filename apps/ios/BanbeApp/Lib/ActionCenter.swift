import Foundation

/// TASK A (2026-10-01 UX foundation pass) — the ONE shared "what does this
/// account need to act on right now" builder, mirroring src/lib/
/// actionCenter.js exactly (same sources, same ordering rule). Consumed by
/// HomeView, AccountView and DashboardView. Every item comes from an
/// already-loaded canonical server array (app.paymentBookings, app.
/// myRefunds, app.verifications, app.refundQueue) — nothing here invents
/// state of its own, so an item disappears the instant its source array no
/// longer contains it.
struct ActionCenterItem: Identifiable {
    enum Severity: Int { case overdue = 0, deadlineSoon = 1, money = 2, normal = 3 }
    let id: String
    /// Stable, UI-test-friendly identifier — unlike `id` (includes a
    /// dynamic uuid/count), this is the same string across runs for the
    /// same KIND of item. Mirrors src/lib/actionCenter.js's own `testId`.
    let testId: String
    let severity: Severity
    let deadline: Date?
    let label: String
    let detail: String
    let ctaLabel: String
    let onTap: () -> Void
}

enum ActionCenterRole { case goer, host }

func sortActionCenterItems(_ items: [ActionCenterItem]) -> [ActionCenterItem] {
    items.sorted { a, b in
        if a.severity.rawValue != b.severity.rawValue { return a.severity.rawValue < b.severity.rawValue }
        let da = a.deadline ?? .distantFuture
        let db = b.deadline ?? .distantFuture
        return da < db
    }
}

struct ActionCenterInputs {
    var role: ActionCenterRole
    var now: Date = Date()
    var myHolding: PayableBooking?
    var myPendingVerification: PayableBooking?
    /// This account's own pending admin invite (loadMyAdminInvite()); nil once
    /// accepted/declined/revoked/expired, so the item disappears with it.
    var myAdminInvite: AdminInvite?
    var myRefunds: [RefundClaim] = []
    var verifications: [PendingVerification] = []
    var refundQueue: [RefundClaim] = []
    /// The goer's saved refund accounts; nil until loaded (then the item
    /// never claims "no account" or "default" it can't verify).
    var refundDestinations: [RefundDestination]? = nil
    var orgHolding: OrganizerHoldingSummary?
    var onOpenPayment: (UUID) -> Void = { _ in }
    var onOpenMyRefunds: () -> Void = {}
    var onOpenAdminInvite: () -> Void = {}
    var onOpenRefundAccounts: () -> Void = {}
    var onOpenVerifications: () -> Void = {}
    var onOpenRefundCenter: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
    /// Opens one event's check-in/attendance (the event key).
    var onOpenAttendance: (String) -> Void = { _ in }
    /// Opens the EXACT booking conversation this refund claim's dispute
    /// belongs to, with its dispute card expanded. Takes the claim id (the
    /// stable identity) and the screen to return to. Declared last (before
    /// `T`) purely so existing call sites keep their argument order.
    var onOpenRefundDispute: (UUID, Screen) -> Void = { _, _ in }
    var T: (String, String) -> String
}

func buildActionCenterItems(_ p: ActionCenterInputs) -> [ActionCenterItem] {
    var items: [ActionCenterItem] = []
    let T = p.T

    func msLeft(_ date: Date?) -> TimeInterval? {
        guard let date else { return nil }
        let t = date.timeIntervalSince(p.now)
        return t > 0 ? t : 0
    }

    switch p.role {
    case .goer:
        if let holding = p.myHolding {
            let left = msLeft(holding.holdExpiresAt)
            items.append(ActionCenterItem(
                id: "hold-\(holding.id)", testId: "action-center-hold",
                severity: left == 0 ? .overdue : (left != nil && left! < 300) ? .deadlineSoon : .money,
                deadline: holding.holdExpiresAt,
                label: T("Đang giữ chỗ", "Holding a seat"),
                detail: holding.eventName + T(" ▪︎ Chờ xác nhận thanh toán", " ▪︎ Awaiting payment confirmation"),
                ctaLabel: T("Xem trạng thái thanh toán", "View payment status"),
                onTap: { p.onOpenPayment(holding.id) }
            ))
        }
        if let pending = p.myPendingVerification {
            items.append(ActionCenterItem(
                id: "pending-verify-\(pending.id)", testId: "action-center-pending-verification",
                severity: .normal, deadline: nil,
                label: T("Đang chờ xác nhận", "Awaiting confirmation"),
                detail: pending.eventName + T(" ▪︎ đồng hồ đã dừng, chỗ được khoá", " ▪︎ clock stopped, seat locked"),
                ctaLabel: T("Xem", "View"),
                onTap: { p.onOpenPayment(pending.id) }
            ))
        }
        for c in p.myRefunds where c.status == "owed" || c.status == "disputed" {
            if c.selectedDestinationId == nil {
                if let dests = p.refundDestinations, dests.isEmpty {
                    items.append(ActionCenterItem(
                        id: "refund-dest-add-\(c.id)", testId: "action-center-refund-destination-add", severity: .money, deadline: c.refundDueAt,
                        label: T("Thêm tài khoản nhận hoàn tiền", "Add a refund account"),
                        detail: c.eventName, ctaLabel: T("Thêm tài khoản", "Add account"),
                        onTap: p.onOpenRefundAccounts
                    ))
                } else {
                    items.append(ActionCenterItem(
                        id: "refund-dest-\(c.id)", testId: "action-center-refund-destination", severity: .money, deadline: c.refundDueAt,
                        label: T("Cần chọn tài khoản nhận hoàn tiền", "Refund destination required"),
                        detail: c.eventName, ctaLabel: T("Chọn tài khoản", "Choose account"),
                        onTap: p.onOpenMyRefunds
                    ))
                }
            } else if let snapshot = c.recipientSnapshot {
                // A destination is set: say which kind (default vs another),
                // with the account's last 4 digits. Informational — not a
                // pending action, so it's not part of any badge count.
                let isDefault = p.refundDestinations?.first(where: \.isDefault)?.id == c.selectedDestinationId
                let last4 = "..." + String(snapshot.accountNumber.suffix(4))
                let chosenVi = isDefault ? "Tài khoản mặc định đã được chọn" : "Đã chọn tài khoản khác"
                let chosenEn = isDefault ? "Default account selected" : "Different account selected"
                items.append(ActionCenterItem(
                    id: "refund-dest-chosen-\(c.id)", testId: "action-center-refund-destination-chosen", severity: .normal, deadline: nil,
                    label: T(chosenVi, chosenEn) + " " + last4,
                    detail: c.eventName, ctaLabel: T("Xem", "View"),
                    onTap: p.onOpenMyRefunds
                ))
            }
        }
        for c in p.myRefunds where c.status == "host_marked_sent" {
            items.append(ActionCenterItem(
                id: "refund-confirm-\(c.id)", testId: "action-center-refund-confirm", severity: .money, deadline: nil,
                label: T("Xác nhận đã nhận hoàn tiền", "Confirm refund received"),
                detail: c.eventName + autoConfirmNote(c, T),
                ctaLabel: T("Xem", "View"),
                onTap: p.onOpenMyRefunds
            ))
        }
        if let invite = p.myAdminInvite {
            let vi = invite.expiresAt.flatMap { formatShortDate($0, lang: "vi") }
            let en = invite.expiresAt.flatMap { formatShortDate($0, lang: "en") }
            items.append(ActionCenterItem(
                id: "admin-invite-\(invite.id)", testId: "action-center-admin-invite",
                // Rare and expiring: rank with the deadline-soon items so the 3-item cap
                // never pushes it behind a busy host's payments/refunds into "See all".
                severity: .deadlineSoon,
                deadline: invite.expiresAt,
                label: T("Bạn có lời mời quản trị", "You have an admin invite"),
                detail: (vi != nil && en != nil) ? T("Trả lời trước \(vi!)", "Respond before \(en!)") : T("Chấp nhận hoặc từ chối", "Accept or decline"),
                ctaLabel: T("Trả lời", "Respond"),
                onTap: p.onOpenAdminInvite
            ))
        }
for c in p.myRefunds where c.status == "disputed" && c.disputeClosedAt == nil {
            items.append(ActionCenterItem(
                id: "refund-dispute-\(c.id)", testId: "action-center-refund-dispute", severity: .overdue, deadline: c.hostResponseDueAt,
                label: T("Tranh chấp hoàn tiền đang chờ", "Refund dispute open"),
                detail: c.eventName, ctaLabel: T("Xem", "View"),
                // Straight into the conversation this dispute lives in, with
                // its dispute card expanded — not into the refund list, which
                // is one more tap away from the thing the item is about.
                onTap: { p.onOpenRefundDispute(c.id, .profile) }
            ))
        }

    case .host:
        if !p.verifications.isEmpty {
            let soonest = p.verifications.compactMap(\.verifyDueAt).min()
            let left = msLeft(soonest)
            items.append(ActionCenterItem(
                id: "verify-queue", testId: "action-center-verify-queue",
                severity: left == 0 ? .overdue : (left != nil && left! < 300) ? .deadlineSoon : .money,
                deadline: soonest,
                label: T("Chờ bạn xác nhận thanh toán", "Payments awaiting your OK"),
                detail: "\(p.verifications.count)" + T(" khoản", p.verifications.count == 1 ? " payment" : " payments"),
                ctaLabel: T("Xem", "View"),
                onTap: p.onOpenVerifications
            ))
        }
        let owed = p.refundQueue.filter { $0.status == "owed" }
        if !owed.isEmpty {
            let anyOverdue = owed.contains { ($0.refundDueAt ?? .distantFuture) < p.now }
            items.append(ActionCenterItem(
                id: "refund-owed", testId: "action-center-refund-owed",
                severity: anyOverdue ? .overdue : .money,
                deadline: owed.compactMap(\.refundDueAt).min(),
                label: T("Khoản hoàn tiền cần xử lý", "Refunds you owe"),
                detail: "\(owed.count)" + T(" khoản", owed.count == 1 ? " refund" : " refunds"),
                ctaLabel: T("Xem", "View"),
                onTap: p.onOpenRefundCenter
            ))
        }
        let disputed = p.refundQueue.filter { $0.status == "disputed" && $0.disputeClosedAt == nil }
        if !disputed.isEmpty {
            // One open dispute goes STRAIGHT to that dispute's conversation,
            // so the host's own link reaches the same dispute the goer's does.
            // Several at once stay a queue — an item that silently picked one
            // of four disputes would be worse than one honest hop.
            let single = disputed.count == 1 ? disputed.first : nil
            items.append(ActionCenterItem(
                id: "refund-dispute-queue", testId: "action-center-refund-dispute-queue", severity: .overdue,
                deadline: disputed.compactMap(\.hostResponseDueAt).min(),
                label: T("Tranh chấp hoàn tiền cần phản hồi", "Refund disputes need a response"),
                detail: "\(disputed.count)" + T(" khoản", disputed.count == 1 ? " claim" : " claims"),
                ctaLabel: T("Xem", "View"),
                onTap: {
                    if let single {
                        p.onOpenRefundDispute(single.id, .dashboard)
                    } else {
                        p.onOpenRefundCenter()
                    }
                }
            ))
        }
        if let orgHolding = p.orgHolding, orgHolding.count > 0 {
            items.append(ActionCenterItem(
                id: "org-holding", testId: "action-center-org-holding", severity: .normal, deadline: orgHolding.soonestHoldExpiresAt,
                label: T("Khách đang giữ chỗ", "Guests holding seats"),
                detail: "\(orgHolding.count)" + T(" chỗ", orgHolding.count == 1 ? " seat" : " seats"),
                ctaLabel: T("Xem", "View"),
                onTap: {
                    // The held seat's own event check-in, not the host profile.
                    if let key = orgHolding.singleEventKey { p.onOpenAttendance(key) } else { p.onOpenDashboard() }
                }
            ))
        }
    }

    return sortActionCenterItems(items)
}


/// " ▪︎ Tự động xác nhận vào 10 thg 10 nếu bạn không phản hồi" — the explicit
/// 7-day auto-confirm rule, shown wherever a host_marked_sent refund is
/// listed. Empty when the date is unknown.
func autoConfirmNote(_ c: RefundClaim, _ T: (String, String) -> String) -> String {
    guard let at = c.autoConfirmAt else { return "" }
    let vi = formatShortDate(at, lang: "vi") ?? "", en = formatShortDate(at, lang: "en") ?? ""
    return T(" ▪︎ Tự động xác nhận vào \(vi) nếu bạn không phản hồi", " ▪︎ Auto-confirms on \(en) if you don't respond")
}

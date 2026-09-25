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
    var myRefunds: [RefundClaim] = []
    var verifications: [PendingVerification] = []
    var refundQueue: [RefundClaim] = []
    var orgHolding: OrganizerHoldingSummary?
    var onOpenPayment: (UUID) -> Void = { _ in }
    var onOpenMyRefunds: () -> Void = {}
    var onOpenVerifications: () -> Void = {}
    var onOpenRefundCenter: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
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
        for c in p.myRefunds where (c.status == "owed" || c.status == "disputed") && c.selectedDestinationId == nil {
            items.append(ActionCenterItem(
                id: "refund-dest-\(c.id)", testId: "action-center-refund-destination", severity: .money, deadline: c.refundDueAt,
                label: T("Cần chọn tài khoản nhận hoàn tiền", "Refund destination required"),
                detail: c.eventName, ctaLabel: T("Chọn tài khoản", "Choose account"),
                onTap: p.onOpenMyRefunds
            ))
        }
        for c in p.myRefunds where c.status == "host_marked_sent" {
            items.append(ActionCenterItem(
                id: "refund-confirm-\(c.id)", testId: "action-center-refund-confirm", severity: .money, deadline: nil,
                label: T("Xác nhận đã nhận hoàn tiền", "Confirm refund received"),
                detail: c.eventName, ctaLabel: T("Xem", "View"),
                onTap: p.onOpenMyRefunds
            ))
        }
        for c in p.myRefunds where c.status == "disputed" {
            items.append(ActionCenterItem(
                id: "refund-dispute-\(c.id)", testId: "action-center-refund-dispute", severity: .overdue, deadline: c.hostResponseDueAt,
                label: T("Tranh chấp hoàn tiền đang chờ", "Refund dispute open"),
                detail: c.eventName, ctaLabel: T("Xem", "View"),
                onTap: p.onOpenMyRefunds
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
        let disputed = p.refundQueue.filter { $0.status == "disputed" }
        if !disputed.isEmpty {
            items.append(ActionCenterItem(
                id: "refund-dispute-queue", testId: "action-center-refund-dispute-queue", severity: .overdue,
                deadline: disputed.compactMap(\.hostResponseDueAt).min(),
                label: T("Tranh chấp hoàn tiền cần phản hồi", "Refund disputes need a response"),
                detail: "\(disputed.count)" + T(" khoản", disputed.count == 1 ? " claim" : " claims"),
                ctaLabel: T("Xem", "View"),
                onTap: p.onOpenRefundCenter
            ))
        }
        if let orgHolding = p.orgHolding, orgHolding.count > 0 {
            items.append(ActionCenterItem(
                id: "org-holding", testId: "action-center-org-holding", severity: .normal, deadline: orgHolding.soonestHoldExpiresAt,
                label: T("Khách đang giữ chỗ", "Guests holding seats"),
                detail: "\(orgHolding.count)" + T(" chỗ", orgHolding.count == 1 ? " seat" : " seats"),
                ctaLabel: T("Xem", "View"),
                onTap: p.onOpenDashboard
            ))
        }
    }

    return sortActionCenterItems(items)
}

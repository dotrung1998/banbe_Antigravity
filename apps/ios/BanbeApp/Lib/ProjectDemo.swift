import Foundation

/// Admin "Project hub demo" (note 76, migration 216, switch `project_hub_demo`). An admin opens the Event Project Hub on
/// the built-in sample data (tests/fixtures/project-snapshot.json, bundled with the app, the same synthetic data the
/// phases were tested with) to show the feature to colleagues. Compiled into every build, unlike the DEBUG UI fixtures.
///
/// Rules:
/// - The entry shows only for an admin while the switch is on (`available`). A missing switch is off.
/// - Inside the demo every project switch counts as on (`projectFlags`), even when it is off for real users.
/// - Nothing reaches the server: while `AppState.projectDemo` is set, `AppState.projectOffline` is true and every project
///   read and write changes the in-memory snapshot instead (see AppState+Project*.swift), and links out of the hub to
///   real screens or outside apps are blocked.
/// - Leaving the hub (Exit demo, Back, a dock tab, signing out) clears everything (`AppState.endProjectDemo`).
enum ProjectDemo {
    static let flag = "project_hub_demo"
    /// The switches the demo treats as on, inside the demo only.
    static let projectFlags = ["event_project_hub", "project_qr_invite", "project_delegate_checkin",
                               "project_delegate_payments", "project_delegate_refunds"]

    /// The gate for the Account entry: admins only, switch on.
    static func available(isAdmin: Bool, flags: [String: Bool]) -> Bool {
        isAdmin && FeatureFlags.isOn(flags, flag)
    }

    /// Who the admin views the demo as. `fixtureKey` is the member the snapshot re-casts (nil = the Host); it is the
    /// same value `-uiFixtureProjectAs` takes.
    enum Role: String, CaseIterable, Identifiable {
        case host, manager, finance, lead, helper
        var id: String { rawValue }
        var fixtureKey: String? { self == .host ? nil : rawValue }
        var vi: String {
            switch self {
            case .host: return "Chủ sự kiện"
            case .manager: return "Quản lý"
            case .finance: return "Tài chính & cổng"
            case .lead: return "Trưởng hạng mục"
            case .helper: return "Hỗ trợ"
            }
        }
        var en: String {
            switch self {
            case .host: return "Host"
            case .manager: return "Manager"
            case .finance: return "Finance & door"
            case .lead: return "Lane lead"
            case .helper: return "Helper"
            }
        }
    }

    /// One open demo: who it is viewed as and the pinned clock.
    struct Session: Equatable {
        var role: Role
        var eventDay: Bool
        var now: Date { eventDay ? ProjectDemo.eventDayNow : ProjectDemo.defaultNow }
    }

    /// The sample's "today" (3 Nov, event zone) and the event day (14 Nov, 18:10, the first item 40 minutes over).
    static let defaultNow = ISO8601DateFormatter().date(from: "2026-11-03T10:00:00+07:00")!
    static let eventDayNow = ISO8601DateFormatter().date(from: "2026-11-14T18:10:00+07:00")!

    /// The account the sample is written for ("Bạn", the Host). The real viewer's id takes its place.
    static let sampleUserID = "00000000-0000-4000-8000-00000000f1f0"
    static let eventID = "fx_project"

    static let memberIDs = ["manager": "00000000-0000-4000-8000-000000000102", "lead": "00000000-0000-4000-8000-000000000103",
                            "helper": "00000000-0000-4000-8000-000000000104", "finance": "00000000-0000-4000-8000-000000000106"]

    static func sampleText(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "project-snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The sample snapshot with `me` as the Host, or re-cast so `me` is that member (`as`: manager, lead, helper, finance).
    static func snapshot(as role: String?, me: String, text: String? = nil) -> ProjectSnapshot? {
        guard var text = text ?? sampleText() else { return nil }
        let me = me.lowercased()
        text = text.replacingOccurrences(of: sampleUserID, with: me)
        if let role, let member = memberIDs[role] {
            // The Host becomes someone else, and the viewer takes that member's place.
            text = text.replacingOccurrences(of: me, with: "00000000-0000-4000-8000-0000000001ff")
                .replacingOccurrences(of: "\"display_name\": \"Bạn\"", with: "\"display_name\": \"Lan\"")
                .replacingOccurrences(of: member, with: me)
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              var snap = root["snapshot"] as? [String: Any] else { return nil }
        if role != nil, let members = snap["members"] as? [[String: Any]],
           let mine = members.first(where: { ($0["user_id"] as? String) == me }) {
            snap["is_host"] = false
            snap["me"] = ["member_id": mine["member_id"] ?? "", "role": mine["role"] ?? "helper", "lane_id": mine["lane_id"] ?? NSNull(),
                          "cap_money": mine["cap_money"] ?? false, "cap_checkin": mine["cap_checkin"] ?? false,
                          "grant_expires_at": "2026-11-21T17:00:00+00:00"]
        }
        guard let json = try? JSONSerialization.data(withJSONObject: snap) else { return nil }
        return try? JSONDecoder().decode(ProjectSnapshot.self, from: json)
    }

    // MARK: sample money and door data (synthetic)

    static let moneySummary = ProjectMoneySummary(confirmedSeats: 9, confirmedAmount: 4_410_000, awaiting: 2, refunds: 1, refundsOverdue: 0,
                                                  checkedIn: 0, seats: 11)

    static var doorRows: [ProjectDoorRow] {
        [
            ProjectDoorRow(bookingId: "door-1", attendeeId: "a1", name: "Ngọc Anh", party: 1, checkedIn: false),
            ProjectDoorRow(bookingId: "door-1", attendeeId: "a2", name: "Quốc Bảo", party: 1, checkedIn: false),
            ProjectDoorRow(bookingId: "door-2", attendeeId: nil, name: "Thu Hà", party: 2, checkedIn: true),
            ProjectDoorRow(bookingId: "door-3", attendeeId: nil, name: "Minh Khang", party: 1, checkedIn: false),
        ]
    }

    static var payments: ProjectMoneyView {
        ProjectMoneyView(success: true, error: nil, confirmedAmount: 4_410_000, confirmedSeats: 9, awaiting: [
            ProjectAwaitingPayment(bookingId: "pay-1", name: "Ngọc Anh", qty: 2, amount: 980_000, paymentRef: "BB1A2B", paidMarkedAt: nil, hasProof: true),
            ProjectAwaitingPayment(bookingId: "pay-2", name: "Minh Khang", qty: 1, amount: 490_000, paymentRef: "BB3C4D", paidMarkedAt: nil, hasProof: false),
        ])
    }

    /// One claim ready with an account, one disputed, one without an account. The Host also sees one team record (Hà's).
    static func refunds(host: Bool, mode: String) -> ProjectRefundView {
        let account = { (bank: String, number: String, holder: String) in
            ProjectRefundAccount(bankName: bank, accountNumber: number, accountHolderName: holder)
        }
        var claims = [
            ProjectRefundClaim(claimId: "rf-1", bookingId: "pay-1", name: "Ngọc Anh", amount: 490_000, status: "owed",
                               refundDueAt: "2026-11-12T10:00:00+07:00", disputeOpen: false,
                               account: account("Vietcombank", "0071000123456", "NGUYEN NGOC ANH"), request: nil, lastDeclined: nil),
            ProjectRefundClaim(claimId: "rf-2", bookingId: "pay-2", name: "Minh Khang", amount: 980_000, status: "disputed",
                               refundDueAt: "2026-11-10T10:00:00+07:00", disputeOpen: true,
                               account: account("Techcombank", "19033344455566", "TRAN MINH KHANG"), request: nil, lastDeclined: nil),
            ProjectRefundClaim(claimId: "rf-3", bookingId: "pay-3", name: "Thu Hà", amount: 490_000, status: "owed",
                               refundDueAt: "2026-11-15T10:00:00+07:00", disputeOpen: false, account: nil, request: nil, lastDeclined: nil),
        ]
        if host {
            claims[0].request = ProjectRefundRequest(id: "rq-1", by: "Hà", mine: false, note: "VCB 8812 lúc 14:05", hasProof: true, at: "2026-11-03T14:05:00+07:00")
        }
        return ProjectRefundView(success: true, error: nil, mode: mode, host: host, claims: claims)
    }

    /// What `peek_project_invite` would say: BB-7K2Q is a live Helper invite, BB-XPRD an expired one, anything else not found.
    static func joinPeek(_ code: String) -> ProjectInvitePeek? {
        let value = ProjectInviteLink.parse(code).map { inv -> String in
            switch inv { case .token: return "BB-7K2Q"; case .code(let c): return c }
        }
        guard value == "BB-7K2Q" || value == "BB-XPRD" else { return nil }
        return ProjectInvitePeek(success: true, error: nil, state: value == "BB-7K2Q" ? "ok" : "expired", eventId: eventID,
                                 eventName: "Bếp Nhỏ №13", eventDate: "2026-11-14", startsAt: "2026-11-14T12:00:00+00:00",
                                 tz: "Asia/Ho_Chi_Minh", organizerName: "Bếp Nhỏ", role: "helper", laneName: nil,
                                 expiresAt: "2026-11-05T03:00:00+00:00")
    }

    // MARK: what the demo wrote (in memory only, cleared when it ends)

    /// Replies written during the run (the snapshot only carries counts).
    static var replies: [String: [ProjectReply]] = [:]
    /// Invites minted in this run (the first is BB-7K2Q, later ones get other codes).
    static var inviteCount = 0
    /// What the trash holds (items deleted during the run go here).
    static var trash: [ProjectTrashItem] = []

    static func resetStore() {
        replies = [:]
        inviteCount = 0
        trash = []
    }
}

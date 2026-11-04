import Foundation

// MARK: - phase 9c: delegated refunds (migration 215, switch project_delegate_refunds)
//
// A team member with money access sends a refund from their own bank and records it. Under the default approval mode
// ('host') the guest is told only once the Host approves; under 'finance_alone' the member marks it sent directly. The
// Host approves or declines team records, switches the mode, and can give one money member rights on one disputed
// refund past the project's dates. The server decides everything (get_event_refund_view and friends); this only offers.

struct ProjectRefundAccount: Decodable, Equatable {
    let bankName: String?
    let accountNumber: String?
    let accountHolderName: String?
    enum CodingKeys: String, CodingKey {
        case bankName = "bank_name", accountNumber = "account_number", accountHolderName = "account_holder_name"
    }
}

/// A pending "I sent this refund" record by a team member.
struct ProjectRefundRequest: Decodable, Equatable {
    let id: String
    let by: String?
    let mine: Bool
    let note: String?
    let hasProof: Bool
    let at: String?
    enum CodingKeys: String, CodingKey { case id, by, mine, note, at, hasProof = "has_proof" }
}

struct ProjectRefundDecline: Decodable, Equatable {
    let reason: String?
    let at: String?
}

/// One open refund claim (owed or disputed), as `get_event_refund_view` returns it. Never a proof or an invoice.
struct ProjectRefundClaim: Decodable, Equatable, Identifiable {
    let claimId: String
    let bookingId: String?
    let name: String
    let amount: Int
    let status: String
    let refundDueAt: String?
    let disputeOpen: Bool
    let account: ProjectRefundAccount?
    var request: ProjectRefundRequest?
    var lastDeclined: ProjectRefundDecline?
    var id: String { claimId }
    enum CodingKeys: String, CodingKey {
        case name, amount, status, account, request
        case claimId = "claim_id", bookingId = "booking_id", refundDueAt = "refund_due_at", disputeOpen = "dispute_open"
        case lastDeclined = "last_declined"
    }
}

private struct ProjectRefundResult: Decodable { let success: Bool?; let error: String? }

struct ProjectRefundView: Decodable, Equatable {
    let success: Bool
    let error: String?
    var mode: String?
    var host: Bool?
    var claims: [ProjectRefundClaim]?
}

/// What a delegate's row offers.
enum ProjectRefundRowState: Equatable {
    /// The guest hasn't added a refund account: nothing to send to.
    case noAccount
    /// A team record waits for the Host (mine: I made it).
    case waiting(mine: Bool)
    /// Ready to send; `declined` is the Host's reason when my last record was declined.
    case ready(declined: String?)
}

extension AppState {
    /// Pure: what a delegate may do with one claim.
    static func projectRefundRowState(_ c: ProjectRefundClaim) -> ProjectRefundRowState {
        if let r = c.request { return .waiting(mine: r.mine) }
        let a = c.account
        let hasAccount = [a?.bankName, a?.accountNumber, a?.accountHolderName].allSatisfy { !($0 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if !hasAccount { return .noAccount }
        return .ready(declined: c.lastDeclined?.reason)
    }

    /// Pure: may the Host offer "Let the team handle this refund" for this claim. Only while its dispute is open, and once
    /// the team's own access is over: the project is read-only, or the default grant (event end + grantDays) has ended.
    static func projectRefundGrantOffer(_ c: ProjectRefundClaim, readOnly: Bool, eventEnd: Date?, now: Date,
                                        grantDays: Int = ProjectLimits.shared.grantDays) -> Bool {
        guard c.disputeOpen else { return false }
        if readOnly { return true }
        guard let end = eventEnd else { return false }
        return now >= end.addingTimeInterval(TimeInterval(grantDays) * 86_400)
    }

    var projectRefundsSwitchOn: Bool { FeatureFlags.isOn(featureFlags, "project_delegate_refunds") }

    /// A team member who may record or mark refunds (the Host keeps the full tab).
    var projectRefundsAccess: Bool {
        projectSnapshot?.isHost != true && (projectCan("refund.request") || projectCan("refund.markSent"))
    }

    /// The Host's refund card and approval row: the Host's Money view while the switch is on.
    var projectRefundsHostAccess: Bool { projectMoneyAccess && projectRefundsSwitchOn }

    /// "host" or "finance_alone": the server's answer once loaded, else the snapshot's.
    var projectRefundMode: String { projectRefunds?.mode ?? projectSnapshot?.project?.refundApproval ?? "host" }

    /// Money members the Host may hand one disputed refund to: Finance, or anyone with money access.
    var projectRefundGrantCandidates: [ProjectMember] {
        (projectSnapshot?.members ?? []).filter { $0.role == "finance" || $0.capMoney }
    }

    func loadProjectRefunds() async {
        guard projectRefundsAccess || projectRefundsHostAccess else { projectRefunds = nil; return }
        #if DEBUG
        if UITestFixture.isActive {
            if projectRefunds == nil { projectRefunds = Self.fixtureProjectRefunds(host: projectSnapshot?.isHost == true, mode: projectRefundMode) }
            return
        }
        #endif
        struct Params: Encodable {
            let pEventId: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id" }
        }
        let eventID = projectEventID
        do {
            let r: ProjectRefundView = try await SupabaseService.client.rpc("get_event_refund_view", params: Params(pEventId: eventID)).execute().value
            guard eventID == projectEventID else { return }
            if r.success {
                projectRefunds = r
                if let mode = r.mode { projectSnapshot?.project?.refundApproval = mode }
            } else if projectRefundsAccess {
                projectNotice = projectErrorText(r.error)
            }
        } catch {
            print("loadProjectRefunds failed:", error)
        }
    }

    /// Delegate: record the transfer for the Host ('host' mode, request_refund_send) or mark it sent ('finance_alone',
    /// mark_refund_sent). The optional receipt goes into the claim's own refund-proof folder first.
    @discardableResult
    func recordProjectRefund(_ claimID: String, note: String, receiptJPEG: Data?) async -> Bool {
        let alone = projectRefundMode == "finance_alone"
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        #if DEBUG
        if UITestFixture.isActive {
            guard let i = projectRefunds?.claims?.firstIndex(where: { $0.claimId == claimID }) else { return false }
            if alone { projectRefunds?.claims?.remove(at: i) }
            else {
                projectRefunds?.claims?[i].request = ProjectRefundRequest(id: "rq-\(claimID)", by: T("Bạn", "You"), mine: true,
                                                                          note: trimmed.isEmpty ? nil : trimmed, hasProof: receiptJPEG != nil, at: nil)
                projectRefunds?.claims?[i].lastDeclined = nil
            }
            Haptics.success()
            return true
        }
        #endif
        struct Params: Encodable {
            let pClaimId: String; let pNote: String; let pProofPath: String?
            enum CodingKeys: String, CodingKey { case pClaimId = "p_claim_id", pNote = "p_note", pProofPath = "p_proof_path" }
        }
        struct Result: Decodable { let success: Bool?; let error: String? }
        projectBusy = true
        defer { projectBusy = false }
        do {
            var path: String?
            if let receiptJPEG { path = try await uploadRefundProof(receiptJPEG, claimID: claimID) }
            let r: Result = try await SupabaseService.client
                .rpc(alone ? "mark_refund_sent" : "request_refund_send", params: Params(pClaimId: claimID.lowercased(), pNote: trimmed, pProofPath: path))
                .execute().value
            if r.success == true { Haptics.success() } else { projectNotice = refundErrorText(r.error) }
            await loadProjectRefunds()
            return r.success == true
        } catch {
            print("recordProjectRefund failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }

    /// Host: approve a team record (marks the refund sent; the guest is told).
    @discardableResult
    func approveProjectRefund(_ claimID: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            projectRefunds?.claims?.removeAll { $0.claimId == claimID }
            Haptics.success()
            return true
        }
        #endif
        struct Params: Encodable {
            let pClaimId: String
            enum CodingKeys: String, CodingKey { case pClaimId = "p_claim_id" }
        }
        return await projectRefundCall("approve_refund_send", Params(pClaimId: claimID.lowercased()))
    }

    /// Host: decline a team record with a reason (3 to 140 characters); the member is told the reason.
    @discardableResult
    func declineProjectRefund(_ claimID: String, reason: String) async -> Bool {
        let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (ProjectLimits.shared.reasonMin...ProjectLimits.shared.reasonMax).contains(r.count) else {
            projectNotice = projectErrorText("REASON_REQUIRED"); return false
        }
        #if DEBUG
        if UITestFixture.isActive {
            if let i = projectRefunds?.claims?.firstIndex(where: { $0.claimId == claimID }) { projectRefunds?.claims?[i].request = nil }
            return true
        }
        #endif
        struct Params: Encodable {
            let pClaimId: String; let pReason: String
            enum CodingKeys: String, CodingKey { case pClaimId = "p_claim_id", pReason = "p_reason" }
        }
        return await projectRefundCall("decline_refund_send", Params(pClaimId: claimID.lowercased(), pReason: r))
    }

    /// Host: who may tell guests a refund was sent ("host" or "finance_alone").
    @discardableResult
    func setProjectRefundApproval(_ mode: String) async -> Bool {
        #if DEBUG
        if UITestFixture.isActive {
            projectRefunds?.mode = mode
            projectSnapshot?.project?.refundApproval = mode
            return true
        }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pMode: String
            enum CodingKeys: String, CodingKey { case pEventId = "p_event_id", pMode = "p_mode" }
        }
        struct Result: Decodable { let success: Bool?; let error: String?; let mode: String? }
        projectBusy = true
        defer { projectBusy = false }
        do {
            let r: Result = try await SupabaseService.client
                .rpc("project_set_refund_approval", params: Params(pEventId: projectEventID, pMode: mode)).execute().value
            guard r.success == true else { projectNotice = refundErrorText(r.error); return false }
            let m = r.mode ?? mode
            projectRefunds?.mode = m
            projectSnapshot?.project?.refundApproval = m
            Haptics.success()
            return true
        } catch {
            print("setProjectRefundApproval failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }

    /// Host: give one money member refund rights on one disputed claim for `days` (7, 14 or 30) from now.
    @discardableResult
    func extendProjectDisputeGrant(userID: String, claimID: String, days: Int) async -> Bool {
        let d = min(max(days, 1), ProjectLimits.shared.disputeGrantMaxDays)
        #if DEBUG
        if UITestFixture.isActive { Haptics.success(); return true }
        #endif
        struct Params: Encodable {
            let pEventId: String; let pUserId: String; let pRefundClaimId: String; let pUntil: String
            enum CodingKeys: String, CodingKey {
                case pEventId = "p_event_id", pUserId = "p_user_id", pRefundClaimId = "p_refund_claim_id", pUntil = "p_until"
            }
        }
        // A minute short of the cap, so the server's "until <= now + max days" never trips on clock drift.
        let until = Date().addingTimeInterval(TimeInterval(d) * 86_400 - 60)
        return await projectRefundCall("project_extend_dispute_grant", Params(
            pEventId: projectEventID, pUserId: userID.lowercased(), pRefundClaimId: claimID.lowercased(),
            pUntil: ISO8601DateFormatter().string(from: until)))
    }

    private func projectRefundCall<P: Encodable & Sendable>(_ fn: String, _ params: P) async -> Bool {
        projectBusy = true
        defer { projectBusy = false }
        do {
            let r: ProjectRefundResult = try await SupabaseService.client.rpc(fn, params: params).execute().value
            if r.success == true { Haptics.success() } else { projectNotice = refundErrorText(r.error) }
            await loadProjectRefunds()
            return r.success == true
        } catch {
            print("\(fn) failed:", error)
            projectNotice = projectErrorText(nil)
            return false
        }
    }

    /// NOT_AUTHORIZED on a refund means the member's money access ended or is off (like 9b's payments).
    func refundErrorText(_ code: String?) -> String {
        if code == "NOT_AUTHORIZED", projectSnapshot?.isHost != true {
            return T("Quyền tiền của bạn đã hết hoặc đang tắt.", "Your money access has ended or is switched off.")
        }
        return projectErrorText(code)
    }

    /// "Due Thu 12/11" in the event's zone.
    func projectRefundDueText(_ iso: String?) -> String? {
        guard let date = ProjectDates.parse(iso) else { return nil }
        let f = DateFormatter()
        f.timeZone = projectSnapshot?.event?.timeZone ?? TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        f.locale = Locale(identifier: T("vi_VN", "en_US"))
        f.setLocalizedDateFormatFromTemplate("EEE d/M")
        return T("Hạn \(f.string(from: date))", "Due \(f.string(from: date))")
    }

    #if DEBUG
    /// Synthetic demo claims: one ready with an account, one disputed, one without an account. The Host also sees one
    /// team record (Hà's) to approve or decline.
    static func fixtureProjectRefunds(host: Bool, mode: String) -> ProjectRefundView {
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
    #endif
}

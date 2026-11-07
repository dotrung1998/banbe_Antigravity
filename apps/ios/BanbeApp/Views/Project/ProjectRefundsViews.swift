import PhotosUI
import SwiftUI
import UIKit

/// Phase 9c (migration 215, switch project_delegate_refunds): refunds a team member with money access sends from their
/// own bank. Name, amount, due date and the guest's refund account, never a proof or invoice. Under the default mode the
/// member records the transfer and the guest is told once the Host approves; under "Finance can refund alone" the
/// member marks it sent directly.
struct ProjectRefundsList: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var open: ProjectRefundClaim?

    var body: some View {
        let view = app.projectRefunds
        let rows = view?.claims ?? []
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Hoàn tiền cần gửi", "Refunds to send")).font(BanbeTheme.display(20)).accessibilityAddTraits(.isHeader)
                    // On the title: the list can be the tab's only child, so an id on it merges into the tab's own.
                    .accessibilityIdentifier("project.refunds")
                Text(app.projectRefundMode == "finance_alone"
                     ? app.T("Chuyển từ ngân hàng của bạn rồi bấm “Đã hoàn tiền”. Khách được báo ngay. Mỗi lần đều được ghi lại cho Chủ sự kiện.",
                             "Send from your bank, then tap “Mark refund sent”. The guest is told right away. Each one is recorded for the Host.")
                     : app.T("Chuyển từ ngân hàng của bạn rồi ghi nhận. Khách chỉ được báo sau khi Chủ sự kiện duyệt.",
                             "Send from your bank, then record it. The guest is told only after the Host approves."))
                    .font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project.refunds.mode")
            }
            if view == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if rows.isEmpty {
                Text(app.T("Không có khoản hoàn nào cần gửi.", "No refunds to send.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .accessibilityIdentifier("project.refunds.empty")
            } else {
                ProjectRowsCard(items: rows) { c in row(c) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.refunds.list")
            }
        }
        .sheet(item: $open) { c in ProjectRefundSheet(claim: c) { open = nil } }
    }

    @ViewBuilder
    private func row(_ c: ProjectRefundClaim) -> some View {
        let state = AppState.projectRefundRowState(c)
        let content = VStack(alignment: .leading, spacing: 6) {
            ProjectNameAmount(name: c.name, amount: c.amount)
            HStack(spacing: 8) {
                if let due = app.projectRefundDueText(c.refundDueAt) {
                    Text(due).font(.footnote).foregroundStyle(app.palette.ink2)
                }
                if c.disputeOpen {
                    Text(app.T("Đang khiếu nại", "Disputed")).font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
                }
            }
            switch state {
            case .waiting(let mine):
                Label(mine ? app.T("Bạn đã ghi nhận · đang chờ Chủ sự kiện", "You recorded this · waiting for the Host")
                           : app.T("Đang chờ Chủ sự kiện", "Waiting for Host"), systemImage: "hourglass")
                    .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                    .accessibilityIdentifier("project.refunds.waiting.\(c.claimId)")
            case .noAccount:
                Text(app.T("Khách chưa thêm tài khoản nhận hoàn tiền.", "The guest hasn't added a refund account yet."))
                    .font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
            case .ready(let declined):
                if let declined {
                    Text(app.T("Chủ sự kiện từ chối: ", "Host declined: ") + declined)
                        .font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("project.refunds.declined.\(c.claimId)")
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)

        if case .waiting = state {
            content.accessibilityElement(children: .combine)
        } else {
            Button { app.projectNotice = ""; open = c } label: {
                HStack(spacing: 8) {
                    content
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink3).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("project.refunds.row.\(c.claimId)")
        }
    }
}

/// One refund: the amount, the guest's account (each part with Copy), an optional note and receipt, and the one action
/// the mode allows. Delegates can't read receipts back, so a chosen receipt is only ever shown here before sending.
struct ProjectRefundSheet: View {
    @EnvironmentObject private var app: AppState
    let claim: ProjectRefundClaim
    let close: () -> Void
    @State private var note = ""
    @State private var receiptItem: PhotosPickerItem?
    @State private var receiptJPEG: Data?
    @State private var copied: String?
    @State private var error = ""

    var body: some View {
        let state = AppState.projectRefundRowState(claim)
        let alone = app.projectRefundMode == "finance_alone"
        let canSend: Bool = { if case .ready = state { return true } else { return false } }()
        CardSheet(title: app.T("Gửi hoàn tiền", "Send a refund"), closeID: "project.refund.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(claim.name).font(.headline)
                        Text(EventMarket.formatMoney(claim.amount, currency: "VND")).font(.title.weight(.bold).monospacedDigit())
                            .accessibilityIdentifier("project.refund.amount")
                        if let due = app.projectRefundDueText(claim.refundDueAt) {
                            Text(due).font(.footnote).foregroundStyle(app.palette.ink2)
                        }
                    }
                    if let a = claim.account, case .ready(let declined) = state {
                        VStack(spacing: 0) {
                            copyRow(app.T("Ngân hàng", "Bank"), a.bankName ?? "", id: "bank")
                            Rectangle().fill(app.palette.divider).frame(height: 1)
                            copyRow(app.T("Số tài khoản", "Account number"), a.accountNumber ?? "", id: "number", mono: true)
                            Rectangle().fill(app.palette.divider).frame(height: 1)
                            copyRow(app.T("Chủ tài khoản", "Account holder"), a.accountHolderName ?? "", id: "holder")
                        }
                        .projectCard(padding: 4)
                        if let declined {
                            Text(app.T("Chủ sự kiện từ chối lần trước: ", "The Host declined last time: ") + declined)
                                .font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert).fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(app.T("Ghi chú cho Chủ sự kiện (không bắt buộc)", "Note for the Host (optional)"), text: $note, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(12)
                                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityIdentifier("project.refund.note")
                                .onChange(of: note) { _, v in if v.count > 280 { note = String(v.prefix(280)) } }
                            Text("\(note.count)/280").font(.caption).foregroundStyle(app.palette.ink3)
                        }
                        receiptPicker
                    } else if case .waiting = state {
                        Text(app.T("Khoản này đang chờ Chủ sự kiện duyệt.", "This refund is waiting for the Host."))
                            .font(.subheadline).foregroundStyle(app.palette.ink2)
                    }
                    if !error.isEmpty {
                        Text(error).font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("project.refund.error")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task {
                                app.projectNotice = ""
                                if await app.recordProjectRefund(claim.claimId, note: note, receiptJPEG: receiptJPEG) { close() }
                                else { error = app.projectNotice; app.projectNotice = "" }
                            }
                        } label: {
                            Text(alone ? app.T("Đã hoàn tiền", "Mark refund sent") : app.T("Ghi nhận để chủ sự kiện duyệt", "Record transfer for Host approval"))
                                .font(.body.weight(.bold)).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 12)
                                .foregroundStyle(app.palette.paper)
                                .background(canSend ? app.palette.ink : app.palette.ink3, in: Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(!canSend || app.projectBusy)
                        .accessibilityIdentifier("project.refund.submit")
                        if case .noAccount = state {
                            Text(app.T("Khách chưa thêm tài khoản nhận hoàn tiền.", "The guest hasn't added a refund account yet."))
                                .font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                                .accessibilityIdentifier("project.refund.noAccount")
                        }
                        Text(alone ? app.T("Khách được báo ngay.", "The guest is told right away.")
                                   : app.T("Khách chỉ được báo sau khi Chủ sự kiện duyệt.", "The guest is told only after the Host approves."))
                            .font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("project.refund.footer")
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.refund")
    }

    private var receiptPicker: some View {
        let ink = app.palette.ink, field = app.palette.field
        let title = receiptJPEG == nil ? app.T("Đính kèm biên lai (không bắt buộc)", "Attach receipt (optional)") : app.T("Đã đính kèm biên lai", "Receipt attached")
        let action = receiptJPEG == nil ? app.T("Chọn", "Choose") : app.T("Đổi", "Change")
        return PhotosPicker(selection: $receiptItem, matching: .images) {
            HStack {
                Label(title, systemImage: receiptJPEG == nil ? "paperclip" : "checkmark.circle.fill").font(.subheadline).foregroundStyle(ink)
                Spacer(minLength: 8)
                Text(action).font(.subheadline.weight(.semibold)).foregroundStyle(ink.opacity(0.75))
            }
            .padding(12).frame(minHeight: 44)
            .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier("project.refund.receipt")
        .onChange(of: receiptItem) { _, item in
            guard let item else { return }
            Task {
                // Same rules as the Host's own refund receipt: re-encoded as a JPEG under the proof size limit.
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    receiptJPEG = ProofImage.jpegDataUnderLimit(from: img)
                }
            }
        }
    }

    private func copyRow(_ label: String, _ value: String, id: String, mono: Bool = false) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(app.palette.ink2)
                Text(value.isEmpty ? "—" : value).font(mono ? .body.weight(.semibold).monospacedDigit() : .body.weight(.semibold))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button {
                UIPasteboard.general.string = value
                copied = id
                Haptics.success()
            } label: {
                Text(copied == id ? app.T("Đã chép", "Copied") : app.T("Chép", "Copy"))
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(app.palette.blockInset, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(value.isEmpty)
            .accessibilityLabel(copied == id ? app.T("Đã chép \(label)", "Copied \(label)") : app.T("Chép \(label)", "Copy \(label)"))
            .accessibilityIdentifier("project.refund.copy.\(id)")
        }
        .padding(.vertical, 8)
    }
}

/// The Host's half (Money & door, below the numbers): team records to approve or decline, the approval mode, and the
/// one-claim hand-off for a disputed refund once the team's own access is over.
struct ProjectHostRefunds: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snap: ProjectSnapshot
    @State private var approving: ProjectRefundClaim?
    @State private var declining: ProjectRefundClaim?
    @State private var granting: ProjectRefundClaim?
    @State private var confirmAlone = false

    var body: some View {
        let claims = app.projectRefunds?.claims ?? []
        let requested = claims.filter { $0.request != nil }
        let offers = claims.filter {
            AppState.projectRefundGrantOffer($0, readOnly: snap.project?.readOnly == true,
                                             eventEnd: ProjectDates.parse(snap.project?.eventEndAt), now: app.projectNow)
        }
        VStack(alignment: .leading, spacing: 0) {
            if !requested.isEmpty {
                header(app.T("Hoàn tiền từ đội", "Refunds from the team"), id: "project.hostRefunds")
                ProjectRowsCard(items: requested) { c in requestRow(c) }
                    .accessibilityElement(children: .contain)
            }
            if !offers.isEmpty {
                header(app.T("Khiếu nại hoàn tiền", "Disputed refunds"), id: "project.hostRefunds.disputes")
                ProjectRowsCard(items: offers) { c in offerRow(c) }
                    .accessibilityElement(children: .contain)
            }
            approval
        }
        .alert(app.T("Duyệt khoản hoàn này?", "Approve this refund?"), isPresented: Binding(get: { approving != nil }, set: { if !$0 { approving = nil } }),
               presenting: approving) { c in
            Button(app.T("Duyệt", "Approve")) { Task { await app.approveProjectRefund(c.claimId) } }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(app.T("Khách sẽ được báo là đã hoàn tiền.", "The guest will be told the refund was sent."))
        }
        .alert(app.T("Để Tài chính tự hoàn tiền?", "Let Finance refund alone?"), isPresented: $confirmAlone) {
            Button(app.T("Đồng ý", "Switch")) { Task { await app.setProjectRefundApproval("finance_alone") } }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.T("Tài chính & cổng và thành viên có quyền tiền sẽ báo được cho khách là đã hoàn tiền mà không cần bạn.",
                       "Finance & door and members with money access will be able to tell guests a refund was sent without you."))
        }
        .sheet(item: $declining) { c in ProjectRefundDeclineSheet(claim: c) { declining = nil } }
        .sheet(item: $granting) { c in ProjectDisputeGrantSheet(claim: c) { granting = nil } }
    }

    private func header(_ title: String, id: String) -> some View {
        Text(title).font(BanbeTheme.display(20)).accessibilityAddTraits(.isHeader)
            .padding(.top, 22).padding(.bottom, 10)
            .accessibilityIdentifier(id)
    }

    private func requestRow(_ c: ProjectRefundClaim) -> some View {
        let r = c.request
        let buttons = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                ProjectNameAmount(name: c.name, amount: c.amount)
                Text(app.T("\(r?.by ?? "—") đã ghi nhận chuyển khoản", "Recorded by \(r?.by ?? "—")"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                if let note = r?.note, !note.isEmpty {
                    Text("“\(note)”").font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
                if r?.hasProof == true {
                    Label(app.T("Có biên lai", "Receipt attached"), systemImage: "paperclip").font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("project.hostRefunds.row.\(c.claimId)")
            buttons {
                Button { approving = c } label: {
                    Text(app.T("Duyệt", "Approve")).font(.subheadline.weight(.bold))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(app.projectBusy)
                .accessibilityIdentifier("project.hostRefunds.approve.\(c.claimId)")
                Button { declining = c } label: {
                    Text(app.T("Từ chối", "Decline")).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(app.palette.blockInset, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(app.projectBusy)
                .accessibilityIdentifier("project.hostRefunds.decline.\(c.claimId)")
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }

    private func offerRow(_ c: ProjectRefundClaim) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectNameAmount(name: c.name, amount: c.amount)
                .accessibilityElement(children: .combine)
            Button { granting = c } label: {
                Label(app.T("Để đội xử lý khoản hoàn này", "Let the team handle this refund"), systemImage: "person.badge.clock")
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(app.palette.blockInset, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(app.projectRefundGrantCandidates.isEmpty)
            .accessibilityIdentifier("project.hostRefunds.grant.\(c.claimId)")
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var approval: some View {
        let mode = app.projectRefundMode
        let can = app.projectCan("refund.approval.set")
        header(app.T("Duyệt hoàn tiền", "Refund approval"), id: "project.refunds.approval")
        VStack(spacing: 0) {
            option(app.T("Chủ sự kiện duyệt", "Host approves"),
                   detail: app.T("Đội ghi nhận, bạn duyệt rồi khách mới được báo.", "The team records it. The guest is told after you approve."),
                   on: mode != "finance_alone", id: "project.refunds.approval.host") {
                Task { await app.setProjectRefundApproval("host") }
            }
            Rectangle().fill(app.palette.divider).frame(height: 1)
            option(app.T("Tài chính tự hoàn tiền", "Finance can refund alone"),
                   detail: app.T("Đội báo khách đã hoàn tiền mà không cần bạn duyệt.", "The team tells the guest without waiting for you."),
                   on: mode == "finance_alone", id: "project.refunds.approval.finance") { confirmAlone = true }
        }
        .projectCard(padding: 4)
        .disabled(!can || app.projectBusy)
    }

    private func option(_ title: String, detail: String, on: Bool, id: String, run: @escaping () -> Void) -> some View {
        Button { if !on { run() } } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").font(.title3)
                    .foregroundStyle(on ? app.palette.clay : app.palette.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// Decline a team record: a reason is required (the member sees it).
struct ProjectRefundDeclineSheet: View {
    @EnvironmentObject private var app: AppState
    let claim: ProjectRefundClaim
    let close: () -> Void
    @State private var reason = ""
    @State private var error = ""

    var body: some View {
        let lim = ProjectLimits.shared
        let n = reason.trimmingCharacters(in: .whitespacesAndNewlines).count
        let ok = (lim.reasonMin...lim.reasonMax).contains(n)
        CardSheet(title: app.T("Từ chối khoản hoàn", "Decline this refund"), closeID: "project.refundDecline.close", fullHeight: true, onClose: close) {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.T("\(claim.name) · \(EventMarket.formatMoney(claim.amount, currency: "VND"))",
                           "\(claim.name) · \(EventMarket.formatMoney(claim.amount, currency: "VND"))")).font(.headline)
                Text(app.T("Người ghi nhận sẽ thấy lý do và có thể ghi nhận lại. Khách không được báo.",
                           "The person who recorded it sees the reason and can record it again. The guest isn't told."))
                    .font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                TextField(app.T("Lý do (bắt buộc)", "Reason (required)"), text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("project.refundDecline.reason")
                    .onChange(of: reason) { _, v in if v.count > lim.reasonMax { reason = String(v.prefix(lim.reasonMax)) } }
                Text(app.T("\(lim.reasonMin) đến \(lim.reasonMax) ký tự", "\(lim.reasonMin) to \(lim.reasonMax) characters"))
                    .font(.caption).foregroundStyle(app.palette.ink3)
                if !error.isEmpty {
                    Text(error).font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                        .accessibilityIdentifier("project.refundDecline.error")
                }
                Button {
                    Task {
                        app.projectNotice = ""
                        if await app.declineProjectRefund(claim.claimId, reason: reason) { close() }
                        else { error = app.projectNotice; app.projectNotice = "" }
                    }
                } label: {
                    Text(app.T("Từ chối", "Decline")).font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(app.palette.paper).background(ok ? app.palette.ink : app.palette.ink3, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!ok || app.projectBusy)
                .accessibilityIdentifier("project.refundDecline.submit")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.refundDecline")
    }
}

/// Give one money member refund rights on one disputed claim, for 7, 14 or 30 days (only while the dispute is open).
struct ProjectDisputeGrantSheet: View {
    @EnvironmentObject private var app: AppState
    let claim: ProjectRefundClaim
    let close: () -> Void
    @State private var member: String?
    @State private var days = 7
    @State private var error = ""

    var body: some View {
        let people = app.projectRefundGrantCandidates
        CardSheet(title: app.T("Để đội xử lý", "Let the team handle it"), closeID: "project.grant.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(app.T("\(claim.name) · \(EventMarket.formatMoney(claim.amount, currency: "VND"))",
                               "\(claim.name) · \(EventMarket.formatMoney(claim.amount, currency: "VND"))")).font(.headline)
                    Text(app.T("Người bạn chọn chỉ xử lý được khoản hoàn này, khi khiếu nại còn mở. Không gồm chat khiếu nại, thanh toán hay check-in.",
                               "The person you pick can handle only this refund, while the dispute is open. Not the dispute chat, payments or check-in."))
                        .font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                    Text(app.T("Ai", "Who")).font(.subheadline.weight(.bold)).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { i, m in
                            let on = member == m.userId
                            Button { member = m.userId } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(on ? app.palette.clay : app.palette.ink3).accessibilityHidden(true)
                                    ProjectAvatar(name: app.projectPersonName(m.userId), size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.projectPersonName(m.userId)).font(.body.weight(.semibold))
                                        Text(app.projectRoleName(m.role)).font(.footnote).foregroundStyle(app.palette.ink2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10).frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(on ? .isSelected : [])
                            .accessibilityIdentifier("project.grant.member.\(m.userId)")
                            if i < people.count - 1 { Rectangle().fill(app.palette.divider).frame(height: 1) }
                        }
                    }
                    .projectCard(padding: 4)
                    Text(app.T("Trong bao lâu", "For how long")).font(.subheadline.weight(.bold)).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        ForEach([7, 14, 30].filter { $0 <= ProjectLimits.shared.disputeGrantMaxDays }, id: \.self) { d in
                            Button { days = d } label: {
                                Text(app.T("\(d) ngày", "\(d) days")).font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(days == d ? app.palette.paper : app.palette.ink)
                                    .background(days == d ? app.palette.ink : app.palette.blockInset, in: Capsule())
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityAddTraits(days == d ? .isSelected : [])
                            .accessibilityIdentifier("project.grant.days.\(d)")
                        }
                    }
                    if !error.isEmpty {
                        Text(error).font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                            .accessibilityIdentifier("project.grant.error")
                    }
                    Button {
                        guard let member else { return }
                        Task {
                            app.projectNotice = ""
                            if await app.extendProjectDisputeGrant(userID: member, claimID: claim.claimId, days: days) {
                                let who = app.projectPersonName(member)
                                close()
                                app.projectNotice = app.T("\(who) xử lý được khoản hoàn này trong \(days) ngày.",
                                                          "\(who) can handle this refund for \(days) days.")
                            } else { error = app.projectNotice; app.projectNotice = "" }
                        }
                    } label: {
                        Text(app.T("Giao khoản hoàn này", "Hand over this refund")).font(.body.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(app.palette.paper).background(member != nil ? app.palette.ink : app.palette.ink3, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(member == nil || app.projectBusy)
                    .accessibilityIdentifier("project.grant.submit")
                }
                .padding(.bottom, 24)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.grant")
    }
}

/// Name and amount on one line; at accessibility text sizes the amount drops under the name so neither is cut off.
private struct ProjectNameAmount: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let amount: Int

    var body: some View {
        let big = dynamicTypeSize.isAccessibilitySize
        (big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
            Text(name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if !big { Spacer(minLength: 6) }
            Text(EventMarket.formatMoney(amount, currency: "VND")).font(.body.weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

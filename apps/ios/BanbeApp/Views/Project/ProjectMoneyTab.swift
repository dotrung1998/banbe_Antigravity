import SwiftUI

/// Money & door (v6 prototype). The Host sees the numbers (confirmed, awaiting a check, refund asks, checked in) and
/// goes straight to the existing screens that act on them: Verifications, its refund section and Attendance. Payout and
/// cancelling stay where they are, with the Host. Everyone else sees the v6 lock card and who has access; a member the
/// Host has granted money or check-in sees that it starts once banbe turns team access on (phases 9a–9c).
struct ProjectMoneyTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snap: ProjectSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.projectMoneyAccess { host }
            else if app.projectPaymentsAccess || app.projectRefundsAccess || app.projectDoorAccess {
                VStack(alignment: .leading, spacing: 28) {
                    if app.projectPaymentsAccess { ProjectPaymentsList() }
                    if app.projectRefundsAccess { ProjectRefundsList() }
                    if app.projectDoorAccess { ProjectDoorList() }
                }
            } else { lock }
        }
        .task {
            await app.loadProjectMoney(); await app.loadProjectPayments(); await app.loadProjectRefunds(); await app.loadProjectDoor()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.moneyTab")
    }

    // MARK: Host

    @ViewBuilder
    private var host: some View {
        let m = app.projectMoney
        stats(m)
        if app.projectRefundsHostAccess { ProjectHostRefunds(snap: snap) }
        ProjectSectionHeader(title: app.T("Việc cần làm", "Act on it"))
        VStack(spacing: 0) {
            action(icon: "checkmark.seal", title: app.T("Kiểm tra thanh toán", "Check payments"),
                   detail: (m?.awaiting ?? 0) > 0 ? app.T("\(m!.awaiting) khách chờ bạn xác nhận", m!.awaiting == 1 ? "1 guest waiting for you" : "\(m!.awaiting) guests waiting for you")
                                                  : app.T("Không ai đang chờ", "Nobody is waiting"),
                   hot: (m?.awaiting ?? 0) > 0, id: "project.money.verify") {
                if !app.projectDemoBlocksLink() { app.openVerifications(back: .eventProject) }
            }
            divider
            action(icon: "arrow.uturn.backward.circle", title: app.T("Hoàn tiền", "Refunds"),
                   detail: refundDetail(m), hot: (m?.refunds ?? 0) > 0, id: "project.money.refunds") {
                if !app.projectDemoBlocksLink() { app.openVerificationsRefunds(back: .eventProject) }
            }
            divider
            action(icon: "qrcode.viewfinder", title: app.T("Check-in ở cửa", "Door check-in"),
                   detail: m.map { app.T("\($0.checkedIn)/\($0.seats) chỗ đã vào", "\($0.checkedIn)/\($0.seats) seats in") } ?? "",
                   hot: false, id: "project.money.door") {
                if !app.projectDemoBlocksLink() { app.openAttendance(snap.event?.id ?? app.projectEventID, back: .eventProject) }
            }
        }
        .projectCard(padding: 4)
        teamAccess
        Label(app.T("Tài khoản nhận tiền và huỷ sự kiện luôn do bạn làm, không giao cho đội.",
                    "The payout account and cancelling the event stay with you. They're never handed to the team."),
              systemImage: "lock")
            .font(.footnote).foregroundStyle(app.palette.ink2)
            .padding(.top, 14)
            .accessibilityIdentifier("project.money.hostOnly")
    }

    private var divider: some View { Rectangle().fill(app.palette.divider).frame(height: 1) }

    private func refundDetail(_ m: ProjectMoneySummary?) -> String {
        guard let m, m.refunds > 0 else { return app.T("Không có yêu cầu hoàn tiền", "No refund requests") }
        var s = app.T("\(m.refunds) yêu cầu đang mở", m.refunds == 1 ? "1 open request" : "\(m.refunds) open requests")
        if m.refundsOverdue > 0 { s += app.T(" · \(m.refundsOverdue) quá hạn", " · \(m.refundsOverdue) overdue") }
        return s
    }

    private func stats(_ m: ProjectMoneySummary?) -> some View {
        let currencyAmount = m.map { EventMarket.formatMoney($0.confirmedAmount, currency: "VND") } ?? "—"
        let awaiting = stat(m.map { "\($0.awaiting)" } ?? "—", app.T("Chờ xác nhận", "Awaiting"), hot: (m?.awaiting ?? 0) > 0, id: "project.money.awaiting")
        let refunds = stat(m.map { "\($0.refunds)" } ?? "—", app.T("Xin hoàn", "Refund asks"), hot: (m?.refunds ?? 0) > 0, id: "project.money.refundCount")
        // Large text: one tile per line, so a label never breaks mid-word.
        let pair = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(spacing: 8) {
            stat(currencyAmount, app.T("Đã xác nhận", "Confirmed"), hot: false, id: "project.money.confirmed")
            pair { awaiting; refunds }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.money.stats")
    }

    private func stat(_ value: String, _ label: String, hot: Bool, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(hot ? BanbeTheme.alert : app.palette.ink)
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hot ? BanbeTheme.alert.opacity(0.10) : app.palette.block, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func action(icon: String, title: String, detail: String, hot: Bool, id: String, run: @escaping () -> Void) -> some View {
        let big = dynamicTypeSize.isAccessibilitySize
        return Button(action: run) {
            // Large text: the icon goes above and the chevron away, so the words get the whole width.
            (big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(app.palette.clay)
                    .frame(width: 28, alignment: .leading).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.footnote).foregroundStyle(hot ? BanbeTheme.alert : app.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !big {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink3).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    /// Who on the team holds money or check-in access, and that it isn't live until banbe turns it on.
    @ViewBuilder
    private var teamAccess: some View {
        let holders = (snap.members ?? []).filter { $0.capMoney || $0.capCheckin }
        ProjectSectionHeader(title: app.T("Quyền của đội", "Team access"))
        VStack(alignment: .leading, spacing: 10) {
            if holders.isEmpty {
                Text(app.T("Chưa ai trong đội có quyền tiền hoặc check-in. Cấp ở thẻ Đội.",
                           "Nobody on the team has money or check-in access. Grant it on the Team tab."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2)
            } else {
                ForEach(holders) { m in
                    HStack(spacing: 10) {
                        ProjectAvatar(name: app.projectPersonName(m.userId), size: 32)
                        Text(app.projectPersonName(m.userId)).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        if m.capMoney { ProjectCapTag(icon: "wallet.pass", text: app.T("Tiền", "Money")) }
                        if m.capCheckin { ProjectCapTag(icon: "qrcode", text: "Check-in") }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Text(delegationLine).font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .projectCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.money.team")
    }

    private var delegationLine: String {
        app.T("Hiện chỉ bạn làm được các việc này. Quyền của đội có hiệu lực khi banbe bật tính năng giao quyền tiền và check-in.",
              "For now only you can do these. Team access takes effect once banbe turns on team money and check-in.")
    }

    // MARK: lock (v6)

    @ViewBuilder
    private var lock: some View {
        let me = snap.me
        let granted = me.map { $0.capMoney || $0.capCheckin } ?? false
        let holders = (snap.hosts ?? []).map(\.userId) + (snap.members ?? []).filter { $0.capMoney || $0.capCheckin }.map(\.userId)
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(app.palette.clay).accessibilityHidden(true)
            Text(granted ? app.T("Quyền của bạn chưa bật", "Your access isn't on yet") : app.T("Bạn chưa có quyền ở mục này", "You don't have access here"))
                .font(BanbeTheme.display(19)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                // On the title: the card is the tab's only child, so an id on the card merges into the tab's own.
                .accessibilityIdentifier(granted ? "project.money.lockGranted" : "project.money.lock")
            Text(granted
                 ? app.T("Chủ sự kiện đã cấp cho bạn quyền \(grantedList(me!)). Quyền này có hiệu lực khi banbe bật tính năng giao quyền cho đội.",
                         "The Host gave you \(grantedList(me!)) access. It starts working once banbe turns on team access.")
                 : app.T("Tiền, hoàn tiền và check-in chỉ dành cho người được Chủ sự kiện cấp quyền.",
                         "Money, refunds and check-in are for people the Host has given access."))
                .font(.subheadline).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: -8) {
                ForEach(Array(holders.prefix(6).enumerated()), id: \.offset) { _, uid in
                    ProjectAvatar(name: app.projectPersonName(uid), size: 34).overlay(Circle().strokeBorder(app.palette.block, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
            Text(holders.map { app.projectPersonName($0) }.joined(separator: ", "))
                .font(.footnote).foregroundStyle(app.palette.ink3).multilineTextAlignment(.center)
                .accessibilityLabel(app.T("Người có quyền: ", "People with access: ") + holders.map { app.projectPersonName($0) }.joined(separator: ", "))
        }
        .padding(.vertical, 28).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .projectCard()
        .accessibilityElement(children: .contain)
    }

    private func grantedList(_ me: ProjectMe) -> String {
        [me.capMoney ? app.T("tiền", "money") : nil, me.capCheckin ? "check-in" : nil].compactMap { $0 }
            .joined(separator: app.T(" và ", " and "))
    }
}

/// Phase 9a (migration 212, switch project_delegate_checkin): the door for a team member with check-in access. Names and
/// check-in state only: no amounts, codes or birth dates reach this list. Checking a party in from here admits everyone
/// in it who isn't in yet; each check-in is recorded for the Host (event_money_audit).
struct ProjectDoorList: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""

    var body: some View {
        let guests = app.projectDoor ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = q.isEmpty ? guests : guests.filter { $0.names.joined(separator: " ").lowercased().contains(q) }
        let inside = guests.reduce(0) { $0 + min($1.inside, $1.party) }
        let total = guests.reduce(0) { $0 + $1.party }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Check-in ở cửa", "Door check-in")).font(BanbeTheme.display(20)).accessibilityAddTraits(.isHeader)
                    // On the title: the list is the tab's only child, so an id on it merges into the tab's own.
                    .accessibilityIdentifier("project.door")
                Text(app.T("\(inside)/\(total) người đã vào", "\(inside) of \(total) people in")).font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.palette.ink2)
                    .accessibilityIdentifier("project.door.count")
                Text(app.T("Chỉ có tên khách. Tiền và hoàn tiền vẫn do Chủ sự kiện làm. Mỗi lần check-in đều được ghi lại cho Chủ sự kiện.",
                           "Names only. Money and refunds stay with the Host. Every check-in is recorded for the Host."))
                    .font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
            }
            TextField(app.T("Tìm tên khách", "Search guests"), text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("project.door.search")
            if app.projectDoor == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if shown.isEmpty {
                Text(guests.isEmpty ? app.T("Chưa có khách đã xác nhận.", "No confirmed guests yet.") : app.T("Không có tên nào khớp.", "No names match."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ProjectRowsCard(items: shown) { g in row(g) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.door.list")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ g: ProjectDoorGuest) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(g.names.joined(separator: ", ")).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(app.T("\(g.party) người · \(min(g.inside, g.party)) đã vào", g.party == 1 ? "1 person · \(min(g.inside, 1)) in" : "\(g.party) people · \(min(g.inside, g.party)) in"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if g.allIn {
                Label(app.T("Đã vào", "In"), systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.palette.ink2)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("project.door.in.\(g.bookingId)")
            } else {
                Button { Task { await app.checkInProjectGuest(g.bookingId) } } label: {
                    Text(app.T("Check-in", "Check in")).font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(app.projectBusy)
                .accessibilityLabel(app.T("Check-in cho \(g.names.joined(separator: ", "))", "Check in \(g.names.joined(separator: ", "))"))
                .accessibilityIdentifier("project.door.checkin.\(g.bookingId)")
            }
        }
        .padding(.vertical, 8)
    }
}

/// Phase 9b (migration 214, switch project_delegate_payments): payments waiting for a check, for a team member with money
/// access. Amounts and references, the transfer proof of the one booking being checked (view only, each open recorded),
/// and "Money received". "Can't find it" and rejecting stay with the Host; invoices and receipts are never shown here.
struct ProjectPaymentsList: View {
    @EnvironmentObject private var app: AppState
    @State private var proof: ProofItem?

    struct ProofItem: Identifiable { let id: String; let name: String; let url: URL? }

    var body: some View {
        let view = app.projectPayments
        let rows = view?.awaiting ?? []
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Thanh toán cần kiểm tra", "Payments to check")).font(BanbeTheme.display(20)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("project.payments")
                if let view {
                    Text(app.T("Đã xác nhận: ", "Confirmed: ") + EventMarket.formatMoney(view.confirmedAmount ?? 0, currency: "VND")
                         + app.T(" · \(view.confirmedSeats ?? 0) chỗ", " · \(view.confirmedSeats ?? 0) seats"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.ink2)
                        .accessibilityIdentifier("project.payments.confirmed")
                }
                Text(app.T("Kiểm tra tài khoản nhận tiền trước khi bấm. “Không thấy tiền” và từ chối vẫn do Chủ sự kiện làm. Mỗi lần xác nhận và mở ảnh đều được ghi lại.",
                           "Check the receiving account before you tap. “Can't find it” and rejecting stay with the Host. Every confirmation and every proof you open is recorded."))
                    .font(.footnote).foregroundStyle(app.palette.ink3).fixedSize(horizontal: false, vertical: true)
            }
            if view == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if rows.isEmpty {
                Text(app.T("Không có khoản nào đang chờ.", "Nothing is waiting for a check.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .accessibilityIdentifier("project.payments.empty")
            } else {
                ProjectRowsCard(items: rows) { r in row(r) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.payments.list")
            }
        }
        .sheet(item: $proof) { item in ProjectProofSheet(name: item.name, url: item.url) { proof = nil } }
    }

    private func row(_ r: ProjectAwaitingPayment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).font(.body.weight(.semibold))
                Spacer(minLength: 6)
                Text(EventMarket.formatMoney(r.amount, currency: "VND")).font(.body.weight(.bold).monospacedDigit())
            }
            Text([app.T("\(r.qty) chỗ", r.qty == 1 ? "1 seat" : "\(r.qty) seats"), r.paymentRef.map { app.T("Mã \($0)", "Ref \($0)") }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.footnote).foregroundStyle(app.palette.ink2)
            HStack(spacing: 8) {
                if r.hasProof {
                    Button {
                        Task { let url = await app.openProjectProof(r.bookingId); proof = ProofItem(id: r.bookingId, name: r.name, url: url) }
                    } label: {
                        Label(app.T("Xem ảnh chuyển khoản", "View transfer proof"), systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(app.palette.blockInset, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("project.payments.proof.\(r.bookingId)")
                }
                Spacer(minLength: 0)
                Button { Task { await app.confirmProjectPayment(r.bookingId) } } label: {
                    Text(app.T("Đã nhận tiền", "Money received")).font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(app.projectBusy)
                .accessibilityLabel(app.T("Đã nhận tiền của \(r.name)", "Money received from \(r.name)"))
                .accessibilityIdentifier("project.payments.confirm.\(r.bookingId)")
            }
        }
        .padding(.vertical, 10)
    }
}

/// The transfer proof, view only: no share, save or copy controls (a screenshot is always possible; the open is logged).
struct ProjectProofSheet: View {
    @EnvironmentObject private var app: AppState
    let name: String
    let url: URL?
    let close: () -> Void

    var body: some View {
        CardSheet(title: app.T("Ảnh chuyển khoản", "Transfer proof"), closeID: "project.proof.close", fullHeight: true, onClose: close) {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.headline)
                Group {
                    if let url {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFit()
                            case .failure: Text(app.T("Không tải được ảnh.", "Couldn't load the image.")).foregroundStyle(app.palette.ink2)
                            default: ProgressView()
                            }
                        }
                    } else {
                        Text(app.T("Chưa có ảnh để hiển thị.", "No image to show.")).foregroundStyle(app.palette.ink2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                .background(app.palette.blockInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("project.proof.image")
                Text(app.T("Chỉ xem. Lần mở này đã được ghi lại cho Chủ sự kiện, và liên kết đóng sau \(ProjectLimits.shared.proofUrlSeconds) giây.",
                           "View only. This open was recorded for the Host, and the link closes after \(ProjectLimits.shared.proofUrlSeconds) seconds."))
                    .font(.footnote).foregroundStyle(app.palette.ink3)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.proof")
    }
}

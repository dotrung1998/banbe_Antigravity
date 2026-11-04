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
            if app.projectMoneyAccess { host } else { lock }
        }
        .task { await app.loadProjectMoney() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.moneyTab")
    }

    // MARK: Host

    @ViewBuilder
    private var host: some View {
        let m = app.projectMoney
        stats(m)
        ProjectSectionHeader(title: app.T("Việc cần làm", "Act on it"))
        VStack(spacing: 0) {
            action(icon: "checkmark.seal", title: app.T("Kiểm tra thanh toán", "Check payments"),
                   detail: (m?.awaiting ?? 0) > 0 ? app.T("\(m!.awaiting) khách chờ bạn xác nhận", m!.awaiting == 1 ? "1 guest waiting for you" : "\(m!.awaiting) guests waiting for you")
                                                  : app.T("Không ai đang chờ", "Nobody is waiting"),
                   hot: (m?.awaiting ?? 0) > 0, id: "project.money.verify") {
                app.openVerifications(back: .eventProject)
            }
            divider
            action(icon: "arrow.uturn.backward.circle", title: app.T("Hoàn tiền", "Refunds"),
                   detail: refundDetail(m), hot: (m?.refunds ?? 0) > 0, id: "project.money.refunds") {
                app.openVerificationsRefunds(back: .eventProject)
            }
            divider
            action(icon: "qrcode.viewfinder", title: app.T("Check-in ở cửa", "Door check-in"),
                   detail: m.map { app.T("\($0.checkedIn)/\($0.seats) chỗ đã vào", "\($0.checkedIn)/\($0.seats) seats in") } ?? "",
                   hot: false, id: "project.money.door") {
                app.openAttendance(snap.event?.id ?? app.projectEventID, back: .eventProject)
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

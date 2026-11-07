import SwiftUI

/// Team (v6 prototype): the people in the project with their private working role, lane and money / check-in access,
/// the invite button (Host and Managers), the live invites they can still cancel, "Who can do what", and the note
/// that these roles are private and separate from the host's public Team page.
struct ProjectTeamTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    let snap: ProjectSnapshot

    private var me: String? { app.userID?.uuidString.lowercased() }
    private var canInvite: Bool { app.projectCan("invite.create", .init(role: "helper")) }
    private var qrInvites: Bool { FeatureFlags.isOn(app.projectFlags, "project_qr_invite") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            members
            if canInvite {
                Button { openSheet(.invite) } label: {
                    Label(qrInvites ? app.T("Mời bằng mã QR", "Invite by QR") : app.T("Mời thành viên", "Invite someone"),
                          systemImage: qrInvites ? "qrcode" : "link")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(app.palette.blockInset, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.top, 12)
                .accessibilityIdentifier("project.team.invite")
                liveInvites
            } else {
                Text(app.T("Chỉ Chủ sự kiện và Quản lý mời được người.", "Only the Host and Managers can invite people."))
                    .font(.footnote).foregroundStyle(app.palette.ink2).padding(.top, 12)
            }
            ProjectSectionHeader(title: app.T("Ai làm được gì", "Who can do what"))
            ProjectRoleMatrixView()
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").foregroundStyle(app.palette.clay).accessibilityHidden(true)
                Text(app.T("Vai trò làm việc là riêng tư trong dự án. Nó khác với vai trò công khai ở trang Team của chủ sự kiện và không thay đổi trang đó.",
                           "Working roles are private to the project. They are separate from the public role on the host’s Team page and don’t change it."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.top, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("project.team.privacy")
        }
        .task { await app.loadProjectInvites() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.team")
    }

    // MARK: members

    private var members: some View {
        let hosts = snap.hosts ?? []
        let list = snap.members ?? []
        return VStack(spacing: 0) {
            ForEach(Array(hosts.enumerated()), id: \.element.id) { i, h in
                row(userID: h.userId, role: "host", laneID: nil, money: true, checkin: true, memberID: nil)
                if i < hosts.count - 1 || !list.isEmpty { divider }
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                row(userID: m.userId, role: m.role, laneID: m.laneId, money: m.capMoney, checkin: m.capCheckin, memberID: m.memberId)
                if i < list.count - 1 { divider }
            }
        }
        .projectCard(padding: 4)
    }

    private var divider: some View { Rectangle().fill(app.palette.divider).frame(height: 1) }

    @ViewBuilder
    private func row(userID: String, role: String, laneID: String?, money: Bool, checkin: Bool, memberID: String?) -> some View {
        let name = app.projectPersonName(userID)
        let isMe = userID.lowercased() == me
        let lane = laneID.flatMap { id in snap.lanes?.first { $0.id == id }?.name }
        let open = (snap.tasks ?? []).filter { $0.assigneeId?.lowercased() == userID.lowercased() && $0.status != "done" }.count
        let content = HStack(spacing: 12) {
            ProjectAvatar(name: name, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.body.weight(.semibold))
                    if isMe {
                        Text(app.T("bạn", "you")).font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(app.palette.blockInset, in: Capsule())
                    }
                }
                Text([app.projectRoleName(role), lane].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                if role != "host" && (money || checkin) {
                    HStack(spacing: 6) {
                        if money { ProjectCapTag(icon: "wallet.pass", text: app.T("Tiền", "Money")) }
                        if checkin { ProjectCapTag(icon: "qrcode", text: "Check-in") }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(open)").font(.headline.monospacedDigit())
                Text(app.T("việc mở", "open")).font(.caption).foregroundStyle(app.palette.ink2)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let memberID {
            Button { openSheet(.member(memberID)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(app.T("Mở thành viên", "Opens this member"))
                .accessibilityIdentifier("project.member.\(memberID)")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("project.member.host")
        }
    }

    // MARK: invites

    @ViewBuilder
    private var liveInvites: some View {
        if !app.projectInvites.isEmpty {
            ProjectCountHeader(title: app.T("Lời mời còn hiệu lực", "Live invites"), count: app.projectInvites.count)
            VStack(spacing: 0) {
                ForEach(Array(app.projectInvites.enumerated()), id: \.element.id) { i, inv in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inv.shortCode).font(.system(.body, design: .monospaced).weight(.bold))
                            Text([app.projectRoleName(inv.role), inv.laneId.flatMap { id in snap.lanes?.first { $0.id == id }?.name },
                                  app.projectInviteExpiry(inv.expiresAt)].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(app.palette.ink2)
                        }
                        Spacer(minLength: 6)
                        Button(app.T("Huỷ", "Cancel")) { Task { await app.revokeProjectInvite(inv.id) } }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel(app.T("Huỷ lời mời \(inv.shortCode)", "Cancel invite \(inv.shortCode)"))
                            .accessibilityIdentifier("project.invite.revoke.\(inv.id)")
                    }
                    .padding(.vertical, 6)
                    if i < app.projectInvites.count - 1 { divider }
                }
            }
            .projectCard(padding: 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project.team.invites")
        }
    }
}

struct ProjectAvatar: View {
    @EnvironmentObject private var app: AppState
    let name: String
    var size: CGFloat = 42

    var body: some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .bold))
            .frame(width: size, height: size)
            .background(app.palette.clayBg, in: Circle())
            .foregroundStyle(app.palette.clay)
            .accessibilityHidden(true)
    }
}

struct ProjectCapTag: View {
    @EnvironmentObject private var app: AppState
    let icon: String
    let text: String
    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.bold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(app.palette.ink2)
            .background(app.palette.blockInset, in: Capsule())
    }
}

/// "Who can do what": a five-column table, or one block per row at the largest text sizes.
struct ProjectRoleMatrixView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize { stacked } else { table }
            Text(app.T("• chỉ trong hạng mục của mình · + Chủ sự kiện cấp được · ✎ đề xuất, Chủ sự kiện duyệt",
                       "• only in their own lane · + the Host can grant it · ✎ proposes, the Host approves"))
                .font(.caption).foregroundStyle(app.palette.ink3).padding(.top, 10)
            Text(app.T("Quyền tiền và check-in cho thành viên đội chỉ có hiệu lực khi banbe bật tính năng này.",
                       "Money and check-in access for team members only takes effect once banbe turns it on."))
                .font(.caption).foregroundStyle(app.palette.ink3).padding(.top, 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(GeometryReader { g in
            Color.clear.preference(key: ProjectMatrixBottomKey.self, value: g.frame(in: .named(ProjectLaneNav.space)).maxY)
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.team.matrix")
    }

    private var shortNames: [String] { ProjectRoleMatrixView.shortNames(app) }
    private var mine: Int? { ProjectRoleMatrixView.myColumn(app) }

    static func shortNames(_ app: AppState) -> [String] {
        [app.T("Chủ", "Host"), app.T("QL", "Mgr"), app.T("TC", "Fin"), app.T("THM", "Lead"), app.T("HT", "Help")]
    }

    /// The column of the viewer's own role (Host, Manager, Finance, Lane lead, Helper), drawn bold and tinted.
    static func myColumn(_ app: AppState) -> Int? {
        if app.projectSnapshot?.isHost == true { return 0 }
        switch app.projectSnapshot?.me?.role {
        case "manager": return 1
        case "finance": return 2
        case "lane_lead": return 3
        case "helper": return 4
        default: return nil
        }
    }

    /// Column names; the viewer's own role is an ink pill. Also used for the copy the hub pins on top while scrolling.
    static func header(_ app: AppState, mine: Int?) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(shortNames(app).enumerated()), id: \.offset) { i, n in
                Text(n).font(.caption2.weight(i == mine ? .heavy : .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(i == mine ? app.palette.paper : app.palette.ink3)
                    .frame(width: 34, height: 22)
                    .background(i == mine ? app.palette.ink : .clear, in: Capsule())
            }
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 4, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical)
                ForEach(Array(shortNames.enumerated()), id: \.offset) { i, n in
                    Text(n).font(.caption2.weight(i == mine ? .heavy : .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(i == mine ? app.palette.paper : app.palette.ink3)
                        .frame(width: 34, height: 22)
                        .background(i == mine ? app.palette.ink : .clear, in: Capsule())
                }
            }
            .background(GeometryReader { g in
                Color.clear.preference(key: ProjectMatrixHeaderKey.self, value: g.frame(in: .named(ProjectLaneNav.space)).minY)
            })
            .accessibilityHidden(true)
            ForEach(ProjectRoleMatrix.rows) { r in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow(alignment: .center) {
                    Text(app.T(r.vi, r.en)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 7)
                    ForEach(Array(r.cells.enumerated()), id: \.offset) { i, c in
                        Text(symbol(c)).font(i == mine ? .body.weight(.heavy) : .footnote.weight(.bold))
                            .foregroundStyle(c == .no ? app.palette.ink3 : i == mine ? app.palette.clay : app.palette.ink)
                            .frame(width: 34).frame(maxHeight: .infinity)
                            .background(i == mine ? app.palette.clayBg.opacity(0.55) : .clear)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowLabel(r))
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProjectRoleMatrix.rows) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T(r.vi, r.en)).font(.body.weight(.semibold))
                    Text(cellsText(r)).font(.subheadline).foregroundStyle(app.palette.ink2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func symbol(_ c: ProjectRoleMatrix.Cell) -> String {
        switch c {
        case .yes: return "✓"
        case .no: return "–"
        case .lane: return "•"
        case .grant: return "+"
        case .propose: return "✎"
        }
    }

    private func word(_ c: ProjectRoleMatrix.Cell) -> String {
        switch c {
        case .yes: return app.T("có", "yes")
        case .no: return app.T("không", "no")
        case .lane: return app.T("chỉ hạng mục của mình", "own lane only")
        case .grant: return app.T("nếu Chủ sự kiện cấp", "if the Host grants it")
        case .propose: return app.T("đề xuất", "proposes")
        }
    }

    private func cellsText(_ r: ProjectRoleMatrix.Row) -> String {
        zip(ProjectRoleMatrix.columns, r.cells).map { "\(app.projectRoleName($0)): \(word($1))" }.joined(separator: ", ")
    }

    private func rowLabel(_ r: ProjectRoleMatrix.Row) -> String { app.T(r.vi, r.en) + ". " + cellsText(r) }
}

extension AppState {
    /// "Expires in 31 h" / "expired" for an invite.
    func projectInviteExpiry(_ iso: String?) -> String? {
        guard let at = ProjectDates.parse(iso) else { return nil }
        let hours = Int(ceil(at.timeIntervalSince(projectNow) / 3600))
        if hours <= 0 { return T("đã hết hạn", "expired") }
        return T("còn \(hours) giờ", hours == 1 ? "1 hour left" : "\(hours) hours left")
    }
}


/// Top of the role table's header row / bottom of the table in the hub's scroll view: while the header has scrolled away
/// but the table is still on screen, the hub pins a copy of the header. Optional so other views don't overwrite it.
struct ProjectMatrixHeaderKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}
struct ProjectMatrixBottomKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

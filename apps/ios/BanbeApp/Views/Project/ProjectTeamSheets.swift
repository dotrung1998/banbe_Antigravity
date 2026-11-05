import SwiftUI
import UIKit

/// A member (v6 "member" sheet). The Host changes the role, the lane of a lane lead and the two sensitive accesses,
/// and can remove the person; everyone else sees it read only. Finance always holds both accesses.
struct ProjectMemberSheet: View {
    @EnvironmentObject private var app: AppState
    let memberID: String
    let close: () -> Void

    @State private var role = "helper"
    @State private var laneID: String?
    @State private var capMoney = false
    @State private var capCheckin = false
    @State private var loaded = false
    @State private var removing = false
    @State private var reason = ""

    private var member: ProjectMember? { app.projectSnapshot?.members?.first { $0.memberId == memberID } }
    private var lanes: [ProjectLane] { (app.projectSnapshot?.lanes ?? []).sorted { $0.position < $1.position } }
    private var host: Bool { app.projectCan("member.manage") }
    private var finance: Bool { role == "finance" }
    private var dirty: Bool {
        guard let m = member else { return false }
        return role != m.role || (role == "lane_lead" && laneID != m.laneId) || (!finance && (capMoney != m.capMoney || capCheckin != m.capCheckin))
    }

    var body: some View {
        CardSheet(title: member.map { app.projectPersonName($0.userId) } ?? app.T("Thành viên", "Member"), closeID: "project.sheet.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let m = member {
                        if removing { removeForm(m) } else { content(m) }
                    } else {
                        Text(app.T("Người này không còn trong dự án.", "This person is no longer in the project.")).foregroundStyle(app.palette.ink2)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: load)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.memberSheet")
    }

    private func load() {
        guard !loaded, let m = member else { return }
        loaded = true
        role = m.role; laneID = m.laneId; capMoney = m.capMoney; capCheckin = m.capCheckin
    }

    @ViewBuilder
    private func content(_ m: ProjectMember) -> some View {
        HStack(spacing: 14) {
            ProjectAvatar(name: app.projectPersonName(m.userId), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.projectRoleName(role)).font(.body.weight(.bold))
                Text(app.projectRoleNote(role)).font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        if host {
            VStack(alignment: .leading, spacing: 8) {
                ProjectFieldLabel(text: app.T("Vai trò", "Role"))
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(ProjectPermissions.roles, id: \.self) { r in
                        ProjectChip(title: app.projectRoleName(r), selected: role == r, id: "project.member.role.\(r)") {
                            role = r
                            if r == "lane_lead", laneID == nil { laneID = lanes.first?.id }
                        }
                    }
                }
            }
            if role == "lane_lead" {
                VStack(alignment: .leading, spacing: 8) {
                    ProjectFieldLabel(text: app.T("Hạng mục phụ trách", "Lane owned"))
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(lanes) { l in ProjectChip(title: l.name, selected: laneID == l.id, id: "project.member.lane.\(l.id)") { laneID = l.id } }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            ProjectFieldLabel(text: app.T("Quyền nhạy cảm", "Sensitive access"))
            capRow(icon: "wallet.pass", title: app.T("Tiền & hoàn tiền", "Money & refunds"),
                   note: app.T("Xem số tiền, xác nhận thanh toán, xử lý hoàn tiền.", "See amounts, confirm payments, handle refunds."),
                   isOn: finance ? .constant(true) : $capMoney, id: "project.member.capMoney")
            capRow(icon: "qrcode", title: "Check-in",
                   note: app.T("Quét vé và đánh dấu khách vào cửa. Không thấy số tiền.", "Scan tickets and tick guests in. Sees no amounts."),
                   isOn: finance ? .constant(true) : $capCheckin, id: "project.member.capCheckin")
            Text(finance ? app.T("Tài chính & cổng luôn có hai quyền này.", "Finance & door always has both.")
                         : host ? app.T("Chỉ có hiệu lực khi banbe bật quyền tiền và check-in cho đội.",
                                        "Takes effect once banbe turns on team money and check-in.")
                                : app.T("Chỉ Chủ sự kiện đổi được quyền.", "Only the Host can change access."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
        if host {
            InkButton(title: app.T("Lưu thay đổi", "Save changes"),
                      enabled: dirty && (role != "lane_lead" || laneID != nil) && !app.projectBusy, cornerRadius: 999) {
                Task {
                    if await app.setProjectMember(memberID, role: role, laneID: laneID, capMoney: finance || capMoney, capCheckin: finance || capCheckin) {
                        close()
                    }
                }
            }
            .accessibilityIdentifier("project.member.save")
            Button(role: .destructive) { removing = true } label: {
                Label(app.T("Xoá khỏi dự án", "Remove from project"), systemImage: "person.badge.minus").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("project.member.remove")
        }
    }

    private func capRow(icon: String, title: String, note: String, isOn: Binding<Bool>, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(app.palette.clay).frame(width: 28).accessibilityHidden(true)
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(note).font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!host || finance)
            .accessibilityIdentifier(id)
        }
    }

    @ViewBuilder
    private func removeForm(_ m: ProjectMember) -> some View {
        Text(app.T("Xoá \(app.projectPersonName(m.userId)) khỏi dự án?", "Remove \(app.projectPersonName(m.userId)) from the project?"))
            .font(BanbeTheme.display(18))
        Text(app.T("Việc đang giao cho họ thành chưa giao. Họ cần lời mời mới để vào lại.",
                   "Their open tasks become unassigned. They'd need a new invite to come back."))
            .font(.subheadline).foregroundStyle(app.palette.ink2)
        if app.projectSnapshot?.project?.channels.isEmpty == false {
            Label(app.T("Ai có liên kết kênh của đội vẫn vào được kênh đó. Hãy cân nhắc đổi liên kết.",
                        "Anyone with a team channel link can still join it. Consider making new links."), systemImage: "link")
                .font(.subheadline).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("project.member.channelNudge")
        }
        ProjectReasonField(reason: $reason, picks: [app.T("Không tham gia nữa", "No longer helping"), app.T("Thêm nhầm người", "Added by mistake")])
        Button(role: .destructive) {
            Task { if await app.removeProjectMember(memberID, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
        } label: {
            Text(app.T("Xoá khỏi dự án", "Remove from project")).font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
        .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
        .accessibilityIdentifier("project.member.confirmRemove")
        Button(app.T("Không xoá", "Keep them")) { removing = false }.frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Invite someone (v6 invite sheet): preset the role (and the lane for a lane lead), get a code that expires in 48 hours,
/// then copy or share the link. A Manager presets Lane lead or Helper only.
/// With switch `project_qr_invite` (phase 4b) the sheet also shows a QR of the join link and a "Single use only" toggle
/// (off = up to 20 people): the invite is minted as soon as the sheet opens and again 400 ms after the role, lane or
/// toggle last changed, cancelling the one it replaces. The QR carries only the link; the role stays on the server.
struct ProjectInviteSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void

    @State private var role = "helper"
    @State private var laneID: String?
    @State private var singleUse = true
    @State private var invite: ProjectInvite?
    @State private var minting = false
    @State private var copied = false

    private var host: Bool { app.projectSnapshot?.isHost == true }
    private var qr: Bool { FeatureFlags.isOn(app.projectFlags, "project_qr_invite") }
    private var roles: [String] { host ? ProjectPermissions.invitableByHost : ProjectPermissions.invitableByManager }
    private var lanes: [ProjectLane] { (app.projectSnapshot?.lanes ?? []).sorted { $0.position < $1.position } }
    private var ready: Bool { role != "lane_lead" || laneID != nil }
    /// What the current invite was made for; a change mints a new one (QR mode).
    private var mintKey: String { "\(role)|\(laneID ?? "")|\(singleUse)" }

    var body: some View {
        CardSheet(title: app.T("Mời thành viên", "Invite someone"), closeID: "project.sheet.close", fullHeight: true, onClose: close) {
          ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(app.T("Người được mời nhận vai bạn đặt sẵn. Họ chỉ thấy dự án này, không thấy các sự kiện khác của bạn.",
                               "Invitees get the role you preset. They see this project only, not your other events."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        ProjectFieldLabel(text: app.T("Vai trò", "Role"))
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(roles, id: \.self) { r in
                                ProjectChip(title: app.projectRoleName(r), selected: role == r, id: "project.invite.role.\(r)") {
                                    role = r
                                    if !qr { invite = nil }
                                    if r == "lane_lead", laneID == nil { laneID = lanes.first?.id }
                                }
                            }
                        }
                        Text(app.projectRoleNote(role)).font(.footnote).foregroundStyle(app.palette.ink2)
                    }
                    if role == "lane_lead" {
                        VStack(alignment: .leading, spacing: 8) {
                            ProjectFieldLabel(text: app.T("Hạng mục", "Lane"))
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(lanes) { l in
                                    ProjectChip(title: l.name, selected: laneID == l.id, id: "project.invite.lane.\(l.id)") {
                                        laneID = l.id
                                        if !qr { invite = nil }
                                    }
                                }
                            }
                        }
                    }
                    if !host {
                        Text(app.T("Quản lý chỉ mời được Trưởng hạng mục và Hỗ trợ. Quản lý và Tài chính & cổng do Chủ sự kiện mời.",
                                   "Managers can invite Lane leads and Helpers only. Manager and Finance & door invites come from the Host."))
                            .font(.footnote).foregroundStyle(app.palette.ink3)
                            .accessibilityIdentifier("project.invite.managerNote")
                    }
                    if qr {
                        qrCard.id("code")
                    } else if let invite {
                        codeCard(invite).id("code")
                    } else {
                        InkButton(title: app.T("Tạo mã mời", "Create invite code"), enabled: ready && !app.projectBusy, cornerRadius: 999) {
                            Task {
                                if let inv = await app.createProjectInvite(role: role, laneID: laneID, maxUses: 1) {
                                    Haptics.success()
                                    invite = inv
                                    copied = false
                                }
                            }
                        }
                        .accessibilityIdentifier("project.invite.create")
                    }
                }
                .padding(.bottom, 24)
            }
            // The sheet opens at half height: bring the new code and its Copy / Share buttons into view.
            .onChange(of: invite?.id) { _, id in
                guard id != nil, !qr else { return }
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo("code", anchor: .top) }
            }
          }
        }
        .task(id: mintKey) { await mintForQR() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.inviteSheet")
    }

    /// QR mode: wait 400 ms for the choices to settle, mint, then cancel the invite this one replaces.
    private func mintForQR() async {
        guard qr, ready else { return }
        if invite != nil { try? await Task.sleep(nanoseconds: 400_000_000) }
        guard !Task.isCancelled else { return }
        minting = true
        let previous = invite
        let made = await app.createProjectInvite(role: role, laneID: laneID, maxUses: singleUse ? 1 : ProjectLimits.shared.inviteMaxUses)
        minting = false
        guard let made else { return }
        if Task.isCancelled {
            // The choices changed while this one was being made: it was never shown, so it goes straight away.
            await app.revokeProjectInvite(made.id)
            return
        }
        invite = made
        copied = false
        if let previous { await app.revokeProjectInvite(previous.id) }
    }

    @ViewBuilder
    private var qrCard: some View {
        let max = ProjectLimits.shared.inviteMaxUses
        VStack(spacing: 10) {
            ZStack {
                if let inv = invite, let link = ProjectInviteLink.joinURL(token: inv.token) {
                    QRCodeImage(value: link, size: 210)
                        .opacity(minting ? 0.35 : 1)
                        .accessibilityLabel(app.T("Mã QR mời vào đội", "Team invite QR code"))
                        .accessibilityIdentifier("project.invite.qr")
                } else {
                    Color.white.frame(width: 210, height: 210)
                }
                if minting { ProgressView().tint(.black) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let inv = invite {
                Text(inv.shortCode).font(.system(size: 22, weight: .heavy, design: .monospaced)).tracking(2)
                    .foregroundStyle(.black)
                    .accessibilityLabel(inv.shortCode.map { String($0) }.joined(separator: " "))
                    .accessibilityIdentifier("project.invite.code")
            }
            Text(app.T("Hết hạn sau \(ProjectLimits.shared.inviteHours) giờ · ", "Expires in \(ProjectLimits.shared.inviteHours) hours · ")
                 + (singleUse ? app.T("dùng một lần", "single use") : app.T("tối đa \(max) người", "up to \(max) people")))
                .font(.footnote).foregroundStyle(Color.black.opacity(0.65))
                .accessibilityIdentifier("project.invite.uses")
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        Toggle(isOn: $singleUse) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.T("Chỉ dùng một lần", "Single use only")).font(.body.weight(.semibold))
                Text(app.T("Tắt để tối đa \(max) người quét cùng một mã, ví dụ khi dán ở buổi họp đội.",
                           "Turn off to let up to \(max) people scan the same code, for example at a team meeting."))
                    .font(.footnote).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("project.invite.singleUse")
        if let inv = invite { shareButtons(inv) }
        Text(app.T("Mã QR chỉ chứa mã mời. Vai trò do banbe giữ, nên sửa liên kết không đổi được vai trò. Đổi lựa chọn sẽ tạo mã mới và huỷ mã cũ.",
                   "The QR holds only the invite code. banbe keeps the role, so editing the link can't change it. Changing a choice makes a new code and cancels the old one."))
            .font(.footnote).foregroundStyle(app.palette.ink3)
    }

    private func codeCard(_ inv: ProjectInvite) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 6) {
                Text(app.T("Mã mời (hết hạn sau \(ProjectLimits.shared.inviteHours) giờ, dùng một lần)",
                           "Invite code (expires in \(ProjectLimits.shared.inviteHours) hours, single use)"))
                    .font(.footnote).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                Text(inv.shortCode).font(.system(size: 30, weight: .heavy, design: .monospaced)).tracking(3)
                    .textSelection(.enabled)
                    .accessibilityLabel(inv.shortCode.map { String($0) }.joined(separator: " "))
                    .accessibilityIdentifier("project.invite.code")
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            shareButtons(inv)
            Text(app.T("Đổi vai trò sẽ tạo mã mới. Mã cũ vẫn dùng được cho tới khi hết hạn hoặc bạn huỷ ở thẻ Đội.",
                       "Changing the role makes a new code. The old one still works until it expires or you cancel it on the Team tab."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
    }

    private func shareButtons(_ inv: ProjectInvite) -> some View {
        let link = ProjectInviteLink.joinURL(token: inv.token) ?? ""
        return HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = link
                Haptics.light()
                copied = true
            } label: {
                Label(copied ? app.T("Đã sao chép", "Copied") : app.T("Sao chép liên kết", "Copy link"), systemImage: copied ? "checkmark" : "link")
                    .font(.body.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("project.invite.copy")
            ShareLink(item: app.projectInviteShareText(inv)) {
                Label(app.T("Chia sẻ", "Share"), systemImage: "square.and.arrow.up").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50).background(app.palette.blockInset, in: Capsule())
            }
            .accessibilityIdentifier("project.invite.share")
        }
    }
}

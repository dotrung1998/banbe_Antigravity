import SwiftUI

/// "Join a team" (note 76 phase 4): what an invite link or a typed BB-XXXX code points at, then Join. The server says
/// which event, which role (and lane) and whether the invite still works; the link itself never sets the role.
/// Signed out, the code is kept on the device and the screen asks to log in first.
struct ProjectJoinView: View {
    @EnvironmentObject private var app: AppState
    @FocusState private var focused: Bool
    @State private var scanning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { app.screen = app.projectJoinBack } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).background(app.palette.block, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Quay lại", "Back"))
                .accessibilityIdentifier("project.join.back")
                Text(app.T("Vào đội sự kiện", "Join a team")).font(.headline).frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    codeField
                    if !app.projectJoinError.isEmpty {
                        Label(app.projectJoinError, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(BanbeTheme.alert)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("project.join.error")
                    }
                    if app.userID == nil { signInCard }
                    if app.projectJoinLoading && app.projectJoinPeek == nil { ProgressView().frame(maxWidth: .infinity) }
                    if let peek = app.projectJoinPeek { card(peek) }
                    Text(app.T("Bạn chỉ thấy dự án của sự kiện này: việc, chủ đề và lịch chạy của đội. Vai trò do người mời đặt sẵn.",
                               "You'll only see this event's team project: its tasks, topics and run-of-show. Your role is set by whoever invited you."))
                        .font(.footnote).foregroundStyle(app.palette.ink3)
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .sheet(isPresented: $scanning) {
            ProjectInviteScanSheet { value in
                scanning = false
                app.projectJoinCode = value
                check()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.join")
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Mã mời hoặc liên kết", "Invite code or link"))
            HStack(spacing: 8) {
                TextField("BB-XXXX", text: $app.projectJoinCode)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { check() }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(app.T("Mã mời", "Invite code"))
                    .accessibilityIdentifier("project.join.code")
                Button(app.T("Kiểm tra", "Check")) { check() }
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    .background(app.palette.blockInset, in: Capsule())
                    .disabled(app.projectJoinCode.trimmingCharacters(in: .whitespaces).isEmpty || app.projectJoinLoading)
                    .accessibilityIdentifier("project.join.check")
            }
            Button { scanning = true } label: {
                Label(app.T("Quét mã QR", "Scan a QR code"), systemImage: "qrcode.viewfinder")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(app.palette.blockInset, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 4)
            .accessibilityIdentifier("project.join.scan")
        }
    }

    /// Signed out: the code is already kept on this device; logging in brings the person straight back here.
    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(app.T("Đăng nhập để xem và nhận lời mời. Mã của bạn được giữ lại.", "Log in to see and accept this invite. Your code is kept for you."))
                .font(.body).fixedSize(horizontal: false, vertical: true)
            InkButton(title: app.T("Đăng nhập để vào đội", "Log in to join"), enabled: true, cornerRadius: 999) { check() }
                .accessibilityIdentifier("project.join.signIn")
        }
        .projectCard()
    }

    private func check() {
        focused = false
        if app.userID == nil {
            UserDefaults.standard.set(app.projectJoinCode.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppState.pendingProjectInviteKey)
            app.promptSignIn(.joinProject, returnTo: .projectJoin, backTo: app.projectJoinBack, resume: .joinProject)
            return
        }
        Task { await app.peekProjectInvite() }
    }

    @ViewBuilder
    private func card(_ p: ProjectInvitePeek) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.eventName ?? "").font(BanbeTheme.display(22)).fixedSize(horizontal: false, vertical: true)
                Text([p.organizerName, eventDay(p)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(app.palette.ink2)
            }
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key").foregroundStyle(app.palette.clay).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Vai trò: ", "Role: ") + app.projectRoleName(p.role) + (p.laneName.map { " · \($0)" } ?? ""))
                        .font(.body.weight(.semibold))
                    Text(app.projectRoleNote(p.role ?? "helper")).font(.footnote).foregroundStyle(app.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if p.state == "ok" {
                if let left = app.projectInviteExpiry(p.expiresAt) {
                    Text(app.T("Lời mời \(left).", "Invite: \(left).")).font(.footnote).foregroundStyle(app.palette.ink3)
                }
                InkButton(title: app.T("Vào đội", "Join the team"), enabled: !app.projectJoinLoading, cornerRadius: 999) {
                    Task { await app.joinProject() }
                }
                .accessibilityIdentifier("project.join.confirm")
            } else {
                Text(stateText(p)).font(.subheadline).foregroundStyle(p.state == "already_member" || p.state == "is_host" ? app.palette.ink : BanbeTheme.alert)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project.join.state")
                if (p.state == "already_member" || p.state == "is_host"), let id = p.eventId {
                    InkButton(title: app.T("Mở dự án", "Open project"), enabled: true, cornerRadius: 999) {
                        Task { await app.openProject(eventID: id, back: app.projectJoinBack) }
                    }
                    .accessibilityIdentifier("project.join.open")
                }
            }
        }
        .projectCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.join.card")
    }

    private func eventDay(_ p: ProjectInvitePeek) -> String? {
        guard let day = p.eventDate else { return nil }
        let tz = p.tz.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let date = ProjectPresentation.localDay(day, tz: tz) else { return day }
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: app.T("vi_VN", "en_US"))
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: date)
    }

    private func stateText(_ p: ProjectInvitePeek) -> String {
        switch p.state {
        case "revoked": return app.projectErrorText("INVITE_REVOKED")
        case "expired": return app.projectErrorText("INVITE_EXPIRED")
        case "used": return app.projectErrorText("INVITE_USED")
        case "event_closed": return app.T("Sự kiện đã huỷ, bị gỡ hoặc dự án đã đóng.", "The event was cancelled or removed, or the project has closed.")
        case "is_host": return app.projectErrorText("IS_HOST")
        case "already_member": return app.projectErrorText("ALREADY_MEMBER")
        default: return app.projectErrorText(nil)
        }
    }
}

/// The invitee's camera (phase 4b): reads a team invite QR and hands back the link. Only the full join link counts
/// (`ProjectInviteLink.joinLink`); any other QR, a ticket included, gets a plain "not a team invite" line.
struct ProjectInviteScanSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let onInvite: (String) -> Void
    @State private var wrong = false
    @State private var done = false

    var body: some View {
        CardSheet(title: app.T("Quét mã mời", "Scan an invite"), closeID: "project.scan.close", fullHeight: true, onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 14) {
                CameraPreview { code in read(code) }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel(app.T("Máy ảnh", "Camera"))
                    .accessibilityIdentifier("project.scan.camera")
                Text(wrong ? app.T("Mã QR này không phải lời mời vào đội trên banbe.", "That QR isn't a banbe team invite.")
                           : app.T("Hướng máy ảnh vào mã QR mời mà Chủ sự kiện hoặc Quản lý đưa cho bạn.",
                                   "Point the camera at the invite QR the Host or a Manager showed you."))
                    .font(.subheadline)
                    .foregroundStyle(wrong ? BanbeTheme.alert : app.palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project.scan.hint")
            }
        }
        .task {
            #if DEBUG
            if let value = UITestFixture.projectScan {
                try? await Task.sleep(nanoseconds: 600_000_000)
                read(value)
            }
            #endif
        }
    }

    /// The camera fires for every frame the QR is visible: act once.
    private func read(_ code: String) {
        guard !done else { return }
        if ProjectInviteLink.joinLink(code) != nil {
            done = true
            Haptics.success()
            onInvite(code)
        } else if !wrong {
            wrong = true
            Haptics.error()
        }
    }
}

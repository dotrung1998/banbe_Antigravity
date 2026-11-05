import SwiftUI

/// Team channels (note 76): up to 5 outside links (Zoom, Meet, Zalo…) for real conversation, since the hub itself has
/// no free chat. Members open them; the Host edits them; a Manager proposes a new one for the Host to approve.
struct ProjectChannelsCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.openProjectSheet) private var openSheet
    let snap: ProjectSnapshot

    private var channels: [ProjectChannels.Channel] { ProjectChannels.ordered(snap.project?.channels ?? []) }
    private var canEdit: Bool { app.projectCan("channels.edit") }
    private var canPropose: Bool { app.projectCan("change.propose") }

    var body: some View {
        if channels.isEmpty {
            if canEdit || canPropose { emptyState }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.T("Kênh trao đổi", "Team channels")).font(.body.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if canEdit || canPropose {
                        Button(canEdit ? app.T("Sửa", "Edit") : app.T("Đề xuất kênh", "Suggest a channel")) { openSheet(.channels) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.clay)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("project.channels.edit")
                    }
                }
                ForEach(Array(channels.enumerated()), id: \.element.url) { i, c in
                    Button { if let url = URL(string: c.url) { openURL(url) } } label: { row(c) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("project.channel.\(i)")
                    if i < channels.count - 1 { Rectangle().fill(app.palette.divider).frame(height: 1) }
                }
                Text(app.T("Mở bên ngoài banbe. banbe không thấy các tin nhắn đó.", "Opens outside banbe. banbe doesn't see those messages."))
                    .font(.footnote).foregroundStyle(app.palette.ink3).padding(.top, 8)
            }
            .projectCard(padding: 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project.channels")
        }
    }

    private func row(_ c: ProjectChannels.Channel) -> some View {
        // Large text: the glyph goes and "Open" moves under the name, so names never break letter by letter.
        let ax = dynamicTypeSize.isAccessibilitySize
        return HStack(spacing: 12) {
            if !ax {
                Image(systemName: ProjectChannelGlyph.symbol(c.platform)).font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38).background(app.palette.blockInset, in: Circle()).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.label.isEmpty ? app.T("Liên kết", "Link") : c.label).font(.body.weight(.semibold))
                    if c.primary {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(app.palette.honey)
                            .accessibilityLabel(app.T("Kênh chính", "Main channel"))
                    }
                }
                Text(ProjectChannels.host(of: c.url) ?? "").font(.footnote).foregroundStyle(app.palette.ink2)
                if ax { openLabel }
            }
            Spacer(minLength: 8)
            if !ax { openLabel }
        }
        .padding(.vertical, ax ? 8 : 0)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(app.T("Mở bên ngoài banbe", "Opens outside banbe"))
    }

    private var openLabel: some View {
        Label(app.T("Mở", "Open"), systemImage: "arrow.up.right").labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.clay)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 18)).foregroundStyle(app.palette.clay).accessibilityHidden(true)
            Text(canEdit ? app.T("Thêm liên kết Zoom, Meet hoặc nhóm chat để đội trao đổi lâu hơn.", "Add a Zoom, Meet or group-chat link for longer talks.")
                         : app.T("Đề xuất một kênh trao đổi cho đội.", "Suggest a chat channel for the team."))
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(canEdit ? app.T("Thêm kênh", "Add channel") : app.T("Đề xuất", "Suggest")) { openSheet(.channels) }
                .font(.subheadline.weight(.bold)).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
                .accessibilityIdentifier("project.channels.add")
        }
        .projectCard(padding: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.channels.empty")
    }
}

enum ProjectChannelGlyph {
    static func symbol(_ platform: String) -> String {
        switch platform {
        case "zoom", "meet", "teams": return "video"
        case "link": return "link"
        default: return "bubble.left.and.bubble.right"
        }
    }
}

/// Edit the list (Host, one Save = one write) or propose one new channel (Manager).
struct ProjectChannelsSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void

    @State private var list: [ProjectChannels.Channel] = []
    @State private var url = ""
    @State private var label = ""
    @State private var platform = ""
    @State private var why = ""
    @State private var formError = ""
    @State private var loaded = false

    private var hostMode: Bool { app.projectCan("channels.edit") }
    private var original: [ProjectChannels.Channel] { app.projectSnapshot?.project?.channels ?? [] }

    var body: some View {
        CardSheet(title: hostMode ? app.T("Kênh trao đổi", "Team channels") : app.T("Đề xuất kênh", "Suggest a channel"),
                  closeID: "project.sheet.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if hostMode { editor } else { proposal }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear { if !loaded { list = original; loaded = true } }
    }

    // MARK: Host

    @ViewBuilder
    private var editor: some View {
        ForEach(Array(list.enumerated()), id: \.element.url) { i, c in
            HStack(spacing: 6) {
                Image(systemName: ProjectChannelGlyph.symbol(c.platform)).frame(width: 30).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.label.isEmpty ? app.T("Liên kết", "Link") : c.label).font(.body.weight(.semibold))
                    Text(ProjectChannels.host(of: c.url) ?? "").font(.footnote).foregroundStyle(app.palette.ink2)
                }
                Spacer(minLength: 4)
                iconButton(c.primary ? "star.fill" : "star", label: c.primary ? app.T("Bỏ kênh chính", "Unstar") : app.T("Đặt làm kênh chính", "Make main channel"),
                           tint: c.primary ? app.palette.honey : app.palette.ink2) {
                    for j in list.indices { list[j].primary = (j == i) ? !c.primary : false }
                }
                iconButton("arrow.up", label: app.T("Lên", "Move up"), tint: app.palette.ink2, enabled: i > 0) { list.swapAt(i, i - 1) }
                iconButton("arrow.down", label: app.T("Xuống", "Move down"), tint: app.palette.ink2, enabled: i < list.count - 1) { list.swapAt(i, i + 1) }
                iconButton("trash", label: app.T("Gỡ", "Remove"), tint: BanbeTheme.alert) { list.remove(at: i) }
            }
            .accessibilityElement(children: .contain)
        }
        if list.count < 5 {
            addForm
        }
        Text(app.T("\(list.count)/5 kênh. Ai có liên kết đều vào được: hãy dùng mật khẩu hoặc phòng chờ của cuộc họp.",
                   "\(list.count)/5 channels. Anyone with a link can join it: use the meeting's own passcode or waiting room."))
            .font(.footnote).foregroundStyle(app.palette.ink3)
        InkButton(title: app.T("Lưu", "Save"), enabled: list != original && !app.projectBusy, cornerRadius: 999) {
            switch ProjectChannels.sanitize(list.map { ($0.platform, $0.label, $0.url, $0.primary) }) {
            case .success(let clean):
                Task { if await app.saveProjectChannels(clean) { close() } }
            case .failure:
                formError = app.projectErrorText("CHANNELS_INVALID")
            }
        }
        .accessibilityIdentifier("project.channels.save")
    }

    @ViewBuilder
    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProjectFieldLabel(text: app.T("Thêm kênh", "Add a channel"))
            ProjectTextField(label: app.T("Liên kết (https)", "Link (https)"), text: $url, limit: 300, placeholder: "https://", id: "project.channel.url")
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: url) { _, v in
                    formError = ""
                    if let p = ProjectChannels.detectPlatform(v) {
                        platform = p
                        if label.isEmpty || ProjectChannels.names.values.contains(label) { label = ProjectChannels.names[p] ?? "" }
                    }
                }
            ProjectTextField(label: app.T("Tên hiển thị", "Label"), text: $label, limit: 30,
                             placeholder: app.T("Ví dụ: Họp hằng tuần", "e.g. Weekly call"), id: "project.channel.label")
            if !platform.isEmpty {
                Text(app.T("Nền tảng: ", "Platform: ") + (ProjectChannels.names[platform] ?? app.T("Liên kết", "Link")))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
            }
            if !formError.isEmpty { Text(formError).font(.footnote).foregroundStyle(BanbeTheme.alert) }
            Button {
                switch ProjectChannels.validate(platform: platform, label: label, url: url, primary: false) {
                case .success(let c):
                    if list.contains(where: { $0.url.lowercased() == c.url.lowercased() }) {
                        formError = app.T("Liên kết này đã có.", "This link is already there.")
                    } else {
                        list.append(c); url = ""; label = ""; platform = ""
                    }
                case .failure(let f):
                    formError = f == .label ? app.T("Tên hiển thị tối đa 30 ký tự.", "A label is at most 30 characters.")
                        : app.T("Dùng một liên kết https đầy đủ.", "Use a full https link.")
                }
            } label: {
                Label(app.T("Thêm vào danh sách", "Add to the list"), systemImage: "plus").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48).background(app.palette.blockInset, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("project.channel.add")
        }
        .projectCard()
    }

    // MARK: Manager

    @ViewBuilder
    private var proposal: some View {
        Text(app.T("Chủ sự kiện sẽ duyệt. Kênh chỉ hiện cho đội sau khi được duyệt.", "The Host reviews it. The channel appears for the team once approved."))
            .font(.subheadline).padding(14)
            .background(app.palette.clayBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(app.palette.clay)
        ProjectTextField(label: app.T("Liên kết (https)", "Link (https)"), text: $url, limit: 300, placeholder: "https://", id: "project.channel.url")
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .onChange(of: url) { _, v in if let p = ProjectChannels.detectPlatform(v) { platform = p; if label.isEmpty { label = ProjectChannels.names[p] ?? "" } } }
        ProjectTextField(label: app.T("Tên hiển thị", "Label"), text: $label, limit: 30, id: "project.channel.label")
        ProjectTextField(label: app.T("Vì sao cần?", "Why is it needed?"), text: $why, limit: 140, axis: .vertical, id: "project.channel.why")
        if !formError.isEmpty { Text(formError).font(.footnote).foregroundStyle(BanbeTheme.alert) }
        InkButton(title: app.T("Gửi đề xuất", "Send proposal"), enabled: ProjectReasonField.valid(why) && !url.isEmpty && !app.projectBusy, cornerRadius: 999) {
            switch ProjectChannels.validate(platform: platform, label: label, url: url, primary: false) {
            case .success(let c):
                Task { if await app.proposeProjectChange(kind: "channel_add", channel: c, why: why.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
            case .failure:
                formError = app.T("Dùng một liên kết https đầy đủ.", "Use a full https link.")
            }
        }
        .accessibilityIdentifier("project.channel.propose")
    }

    private func iconButton(_ icon: String, label: String, tint: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

import SwiftUI

/// One post (v6 "thread" sheet): vote bars for a proposal, "Mark as seen" for an update or decision, up to 10 short
/// replies for a question or proposal, then Decide / Resolve and the author's Edit / Delete while nobody has responded.
struct ProjectPostSheet: View {
    @EnvironmentObject private var app: AppState
    let postID: String
    let close: () -> Void

    @State private var detail: ProjectPostDetail?
    @State private var reply = ""
    @State private var mode: Mode = .view
    @State private var reason = ""
    @State private var editTitle = ""
    @State private var editBody = ""

    enum Mode { case view, edit, delete }

    private var post: ProjectPost? { app.projectSnapshot?.posts?.first { $0.id == postID } ?? detail?.post }

    var body: some View {
        CardSheet(title: post.map { app.projectPostTypeName($0.type) } ?? app.T("Bài", "Post"), closeID: "project.sheet.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let post {
                        switch mode {
                        case .view: content(post)
                        case .edit: editForm(post)
                        case .delete: deleteForm(post)
                        }
                    } else {
                        Text(app.T("Bài này không còn nữa.", "This post is gone.")).font(.body).foregroundStyle(app.palette.ink2)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .task { await reload() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.thread")
    }

    private func reload() async { detail = await app.loadProjectPost(postID) }

    private func target(_ p: ProjectPost) -> ProjectPermissions.Target {
        .init(laneId: p.laneId, authorId: p.authorId, addresseeId: p.addresseeId, type: p.type, state: p.state, quiet: p.quiet)
    }

    // MARK: view

    @ViewBuilder
    private func content(_ p: ProjectPost) -> some View {
        let open = p.state == "open"
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                if let lane = app.projectSnapshot?.lanes?.first(where: { $0.id == p.laneId })?.name {
                    Text(lane).font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(app.palette.clay).background(app.palette.clayBg, in: Capsule())
                }
                if !open { ProjectStateTag(state: p.state) }
                if p.editedAt != nil {
                    Text(app.T("đã sửa", "edited")).font(.caption.italic()).foregroundStyle(app.palette.ink3)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("project.post.edited")
                }
            }
            Text(p.title).font(BanbeTheme.display(20)).fixedSize(horizontal: false, vertical: true)
            if !p.body.isEmpty { Text(p.body).font(.body).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true) }
            Text(app.projectPersonName(p.authorId) + (p.addresseeId.map { " → " + app.projectPersonName($0) } ?? ""))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
        if p.type == "proposal" { options(p, open: open) }
        if p.type == "update" || p.type == "decision" { seen(p) }
        replies(p, open: open)
        actions(p, open: open)
        authorTools(p)
    }

    @ViewBuilder
    private func options(_ p: ProjectPost, open: Bool) -> some View {
        let votes = p.votes ?? []
        let total = max(votes.reduce(0, +), 1)
        let canVote = open && app.projectCan("post.vote") && !app.projectBusy
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((p.options ?? []).enumerated()), id: \.offset) { i, option in
                let n = votes.indices.contains(i) ? votes[i] : 0
                let mine = p.myVote == i
                Button {
                    Haptics.selection()
                    Task { if await app.voteProjectPost(p.id, option: i) { await reload() } }
                } label: {
                    HStack(spacing: 10) {
                        if mine { Image(systemName: "checkmark.circle.fill").foregroundStyle(app.palette.clay).accessibilityHidden(true) }
                        Text(option).font(.body.weight(mine ? .bold : .semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Text("\(n)").font(.body.weight(.bold).monospacedDigit())
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(alignment: .leading) {
                        GeometryReader { g in
                            Rectangle().fill(mine ? app.palette.clayBg : app.palette.blockInset)
                                .frame(width: g.size.width * CGFloat(n) / CGFloat(total))
                        }
                    }
                    .background(app.palette.field)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(mine ? app.palette.clay : .clear, lineWidth: 1.5))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canVote)
                .accessibilityLabel(option)
                .accessibilityValue(app.T("\(n) phiếu", n == 1 ? "1 vote" : "\(n) votes") + (mine ? app.T(", phiếu của bạn", ", your vote") : ""))
                .accessibilityAddTraits(mine ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("project.post.option.\(i)")
            }
            Text(open ? app.T("Mỗi người một phiếu. Bấm lại để rút phiếu, bấm lựa chọn khác để đổi.",
                              "One vote each. Tap again to take it back, or tap another option to switch.")
                      : app.T("Đã chốt. Không bỏ phiếu được nữa.", "Settled. Voting is closed."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
    }

    @ViewBuilder
    private func seen(_ p: ProjectPost) -> some View {
        let names = (detail?.seenBy ?? []).map { app.projectPersonName($0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(names.isEmpty ? app.T("Chưa ai xem", "Nobody has seen it yet") : names.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(2)
                Spacer(minLength: 6)
                Text(app.T("\(p.seenCount)/\(app.projectHeadcount) đã xem", "\(p.seenCount)/\(app.projectHeadcount) seen"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
            }
            if p.seenByMe {
                Label(app.T("Bạn đã xem", "You've seen this"), systemImage: "eye")
                    .font(.body.weight(.semibold)).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(app.palette.blockInset, in: Capsule())
                    .accessibilityIdentifier("project.post.seenDone")
            } else if app.projectCan("post.seen") {
                InkButton(title: app.T("Đã xem", "Mark as seen"), enabled: !app.projectBusy, cornerRadius: 999) {
                    Task { if await app.markProjectPostSeen(p.id) { await reload() } }
                }
                .accessibilityIdentifier("project.post.seen")
            }
        }
    }

    @ViewBuilder
    private func replies(_ p: ProjectPost, open: Bool) -> some View {
        let list = detail?.replies ?? []
        let max = ProjectLimits.shared.repliesMax
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(list) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.projectPersonName(r.authorId)).font(.caption.weight(.bold)).foregroundStyle(app.palette.ink3)
                        Text(r.body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.blockInset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project.post.replies")
        }
        if (p.type == "question" || p.type == "proposal") && open && app.projectCan("post.reply") {
            if p.repliesCount >= max {
                Text(app.T("Đủ \(max) phản hồi. Hãy chốt hoặc đóng bài.", "\(max) replies reached. Settle or close the post."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ProjectTextField(label: app.T("Phản hồi", "Reply"), text: $reply, limit: ProjectLimits.shared.replyMax,
                                         placeholder: app.T("Một dòng ngắn…", "One short line…"), id: "project.post.reply")
                        Button {
                            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                if await app.replyProjectPost(p.id, body: text) { reply = ""; await reload() }
                            }
                        } label: {
                            Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .semibold))
                                .frame(width: 50, height: 50)
                                .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Circle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.projectBusy)
                        .opacity(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                        .accessibilityLabel(app.T("Gửi phản hồi", "Send reply"))
                        .accessibilityIdentifier("project.post.send")
                    }
                    Text(app.T("Đã dùng \(p.repliesCount)/\(max) phản hồi", "\(p.repliesCount)/\(max) replies used"))
                        .font(.footnote).foregroundStyle(app.palette.ink3)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ p: ProjectPost, open: Bool) -> some View {
        if open && p.type == "proposal" && app.projectCan("post.decision", .init(laneId: p.laneId)) {
            InkButton(title: app.T("Chốt phương án dẫn đầu", "Decide on the leading option"), enabled: !app.projectBusy, cornerRadius: 999) {
                Task { if await app.decideProjectProposal(p.id) { close() } }
            }
            .accessibilityIdentifier("project.post.decide")
            Text(app.T("Bài đề xuất khoá lại và một Quyết định được ghi vào nhật ký. Hoà phiếu thì chọn lựa chọn đầu tiên.",
                       "The proposal locks and a Decision goes into the log. A tie picks the first option."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        } else if open && p.type == "question" && app.projectCan("post.resolve", target(p)) {
            Button {
                Task { if await app.resolveProjectPost(p.id) { await reload() } }
            } label: {
                Label(app.T("Đánh dấu đã giải quyết", "Mark as resolved"), systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(app.palette.blockInset, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(app.projectBusy)
            .accessibilityIdentifier("project.post.resolve")
        }
    }

    @ViewBuilder
    private func authorTools(_ p: ProjectPost) -> some View {
        let canEdit = app.projectCan("post.edit", target(p))
        let canDelete = app.projectCan("post.delete", target(p))
        if canEdit || canDelete {
            HStack(spacing: 10) {
                if canEdit {
                    Button {
                        editTitle = p.title; editBody = p.body; mode = .edit
                    } label: {
                        Label(app.T("Sửa bài", "Edit"), systemImage: "pencil").font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50).background(app.palette.blockInset, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("project.post.edit")
                }
                if canDelete {
                    Button { reason = ""; mode = .delete } label: {
                        Label(app.T("Xoá bài", "Delete"), systemImage: "trash").font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("project.post.delete")
                }
            }
        }
        if mine(p.authorId) && !canEdit && p.state == "open" && p.type != "decision" {
            Text(app.T("Đã có người phản hồi nên bạn không sửa được nữa. Nhờ Quản lý nếu cần xoá.",
                       "Others have responded, so you can't edit it now. Ask a Manager if it must go."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
    }

    private func mine(_ id: String?) -> Bool { id != nil && id?.lowercased() == app.userID?.uuidString.lowercased() }

    // MARK: edit / delete

    @ViewBuilder
    private func editForm(_ p: ProjectPost) -> some View {
        let l = ProjectLimits.shared
        ProjectTextField(label: app.T("Tiêu đề", "Title"), text: $editTitle, limit: l.postTitleMax, id: "project.postEdit.title")
        ProjectTextField(label: app.T("Chi tiết", "Details"), text: $editBody, limit: l.postBodyMax, axis: .vertical, id: "project.postEdit.body")
        let t = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        InkButton(title: app.T("Lưu", "Save"), enabled: (l.postTitleMin...l.postTitleMax).contains(t.count) && !app.projectBusy, cornerRadius: 999) {
            Task {
                if await app.editProjectPost(p.id, title: t, body: editBody.trimmingCharacters(in: .whitespacesAndNewlines)) { mode = .view }
            }
        }
        .accessibilityIdentifier("project.postEdit.save")
        Text(app.T("Bài sẽ hiện nhãn “đã sửa”. Chỉ sửa được khi chưa ai phản hồi, bỏ phiếu hay xem.",
                   "The post shows an “edited” label. It can be edited only before anyone replies, votes or marks it seen."))
            .font(.footnote).foregroundStyle(app.palette.ink3)
        Button(app.T("Huỷ", "Cancel")) { mode = .view }.frame(maxWidth: .infinity, minHeight: 44)
    }

    @ViewBuilder
    private func deleteForm(_ p: ProjectPost) -> some View {
        Text(p.title).font(BanbeTheme.display(18))
        ProjectReasonField(reason: $reason, picks: [app.T("Đăng nhầm", "Posted by mistake"), app.T("Trùng bài", "Duplicate"),
                                                    app.T("Không còn đúng", "No longer true")])
        Button(role: .destructive) {
            Task { if await app.deleteProjectPost(p.id, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) { close() } }
        } label: {
            Text(app.T("Xoá bài", "Delete post")).font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(BanbeTheme.alert).background(BanbeTheme.alert.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!ProjectReasonField.valid(reason) || app.projectBusy)
        .opacity(ProjectReasonField.valid(reason) ? 1 : 0.4)
        .accessibilityIdentifier("project.post.confirmDelete")
        Text(app.T("Bài bị xoá vào thùng rác 7 ngày.", "Deleted posts stay in the trash for 7 days.")).font(.footnote).foregroundStyle(app.palette.ink3)
        Button(app.T("Không xoá", "Keep it")) { mode = .view }.frame(maxWidth: .infinity, minHeight: 44)
    }
}

// MARK: - compose

/// "New post" (v6 compose): step 1 picks one of the four types (the ones this role can't post are dimmed, with why),
/// step 2 is the form for that type. One write on Post.
struct ProjectComposeSheet: View {
    @EnvironmentObject private var app: AppState
    let close: () -> Void

    @State private var type: String?
    @State private var laneID = ""
    @State private var title = ""
    @State private var details = ""
    @State private var options = ["", ""]
    @State private var addressee: String?
    @State private var hasDeadline = true
    @State private var deadline = Date()

    private let types = ["proposal", "question", "update", "decision"]
    private var tz: TimeZone { app.projectSnapshot?.event?.timeZone ?? .current }
    private var me: String? { app.userID?.uuidString.lowercased() }
    private var snap: ProjectSnapshot? { app.projectSnapshot }

    var body: some View {
        CardSheet(title: type.map { app.projectPostTypeName($0) } ?? app.T("Bạn muốn đăng gì?", "What do you want to post?"),
                  closeID: "project.sheet.close", fullHeight: true, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let type { form(type) } else { picker }
                }
                .padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.compose")
    }

    private func allowed(_ t: String) -> Bool { app.projectCan("post.\(t)") }

    /// A lane lead settles decisions in their own lane only.
    private var lanes: [ProjectLane] {
        let all = (snap?.lanes ?? []).sorted { $0.position < $1.position }
        if type == "decision", snap?.isHost != true, snap?.me?.role == "lane_lead" { return all.filter { $0.id == snap?.me?.laneId } }
        return all
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(types, id: \.self) { t in
                let ok = allowed(t)
                Button {
                    type = t
                    laneID = lanes.first?.id ?? ""
                    if let d = Calendar.current.date(byAdding: .day, value: 2, to: app.projectNow) { deadline = d }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: app.projectPostIcon(t)).font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(app.palette.clay).frame(width: 40, height: 40)
                            .background(app.palette.clayBg, in: Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.projectPostTypeName(t)).font(.body.weight(.bold))
                            Text(ok ? app.projectPostTypeHint(t) : notAllowedText(t)).font(.subheadline).foregroundStyle(app.palette.ink2)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.block, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!ok)
                .opacity(ok ? 1 : 0.5)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("project.compose.type.\(t)")
            }
            smallTalk
        }
    }

    private func notAllowedText(_ t: String) -> String {
        t == "proposal" ? app.T("Hỗ trợ không đăng đề xuất. Hãy hỏi Trưởng hạng mục.", "Helpers don't post proposals. Ask your lane lead.")
                        : app.T("Chốt quyết định do Chủ sự kiện, Quản lý hoặc Trưởng hạng mục làm.", "Decisions come from the Host, a Manager or a lane lead.")
    }

    /// v6: "for small talk, meet in person or use your chat app", pointing at the team's own channel when there is one.
    @ViewBuilder
    private var smallTalk: some View {
        let channels = snap?.project?.channels ?? []
        let primary = channels.first { $0.primary } ?? channels.first
        VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Muốn nói chuyện bâng quơ? Gặp trực tiếp hoặc dùng kênh của đội. Ở đây chỉ dành cho việc cần chốt.",
                       "For small talk, meet in person or use the team channel. This is for things that need settling."))
                .font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            if let primary, let url = URL(string: primary.url) {
                Link(destination: url) {
                    Label(primary.label.isEmpty ? app.T("Mở kênh của đội", "Open the team channel") : primary.label, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(app.palette.blockInset, in: Capsule())
                }
                .accessibilityIdentifier("project.compose.channel")
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private func form(_ t: String) -> some View {
        let l = ProjectLimits.shared
        VStack(alignment: .leading, spacing: 8) {
            ProjectFieldLabel(text: app.T("Hạng mục", "Lane"))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(lanes) { lane in ProjectChip(title: lane.name, selected: laneID == lane.id, id: "project.compose.lane.\(lane.id)") { laneID = lane.id } }
            }
        }
        ProjectTextField(label: app.T("Tiêu đề", "Title"), text: $title, limit: l.postTitleMax,
                         placeholder: app.T("Nói gọn trong một câu", "Say it in one line"), id: "project.compose.title")
        ProjectTextField(label: app.T("Chi tiết", "Details"), text: $details, limit: l.postBodyMax,
                         placeholder: app.T("Chỉ thông tin người khác cần để quyết định", "Only what others need to decide"), axis: .vertical,
                         id: "project.compose.body")
        if t == "proposal" {
            VStack(alignment: .leading, spacing: 8) {
                ProjectFieldLabel(text: app.T("Lựa chọn (\(l.proposalOptionsMin)–\(l.proposalOptionsMax))", "Options (\(l.proposalOptionsMin)–\(l.proposalOptionsMax))"))
                ForEach(options.indices, id: \.self) { i in
                    ProjectTextField(label: app.T("Lựa chọn \(i + 1)", "Option \(i + 1)"), text: $options[i], limit: l.proposalOptionMax,
                                     id: "project.compose.option.\(i)")
                }
                if options.count < l.proposalOptionsMax {
                    Button { options.append("") } label: {
                        Label(app.T("Thêm lựa chọn", "Add option"), systemImage: "plus").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44).background(app.palette.blockInset, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("project.compose.addOption")
                }
                Toggle(app.T("Hạn bỏ phiếu", "Vote by"), isOn: $hasDeadline).font(.body.weight(.semibold))
                    .accessibilityIdentifier("project.compose.hasDeadline")
                if hasDeadline {
                    DatePicker(app.T("Hạn", "Deadline"), selection: $deadline, in: app.projectNow..., displayedComponents: .date)
                        .environment(\.timeZone, tz)
                }
            }
        }
        if t == "question" {
            VStack(alignment: .leading, spacing: 8) {
                ProjectFieldLabel(text: app.T("Hỏi ai", "Ask whom"))
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(app.projectPeopleIDs.filter { $0.lowercased() != me }, id: \.self) { uid in
                        ProjectChip(title: app.projectPersonName(uid), selected: addressee?.lowercased() == uid.lowercased(),
                                    id: "project.compose.to.\(uid)") { addressee = uid }
                    }
                }
            }
        }
        if t == "decision" {
            Text(app.T("Quyết định khoá ngay và vào nhật ký. Mọi người chỉ bấm “Đã xem”.", "A decision locks at once and goes into the log. People just tap “Seen”."))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
        InkButton(title: app.T("Đăng", "Post"), enabled: ready(t) && !app.projectBusy, cornerRadius: 999,
                  disabledReason: readyReason(t)) {
            Task {
                let opts = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                let ok = await app.createProjectPost(type: t, laneID: laneID, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     body: details.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     options: t == "proposal" ? opts : nil, addresseeID: t == "question" ? addressee : nil,
                                                     deadline: t == "proposal" && hasDeadline ? ProjectPresentation.ymd(deadline, tz: tz) : nil)
                if ok { close() }
            }
        }
        .accessibilityIdentifier("project.compose.post")
        Button(app.T("Đổi loại bài", "Change type")) { type = nil }.frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityIdentifier("project.compose.back")
    }

    private func ready(_ t: String) -> Bool { readyReason(t) == nil && !laneID.isEmpty }

    private func readyReason(_ t: String) -> String? {
        let l = ProjectLimits.shared
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < l.postTitleMin {
            return app.T("Tiêu đề ít nhất \(l.postTitleMin) ký tự.", "A title needs at least \(l.postTitleMin) characters.")
        }
        if t == "proposal", options.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count < l.proposalOptionsMin {
            return app.T("Cần ít nhất \(l.proposalOptionsMin) lựa chọn.", "Add at least \(l.proposalOptionsMin) options.")
        }
        if t == "question", addressee == nil { return app.T("Hãy chọn người để hỏi.", "Pick who to ask.") }
        return nil
    }
}

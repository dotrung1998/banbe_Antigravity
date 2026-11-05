import SwiftUI

/// Tasks (v6 prototype): lane proposals (the Host reviews; a Manager sees their own), All | Mine, add or propose a lane,
/// then every lane with its tasks. The "Add task / lane" button floats over the list (ProjectHubView).
struct ProjectTasksTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.projectScrollTo) private var scrollTo
    let snap: ProjectSnapshot
    /// All | Mine, owned by the hub so the lane navigator shows the same lanes and counts as the list.
    @Binding var mineOnly: Bool
    /// The lane just added or approved: scrolled to and briefly highlighted (it lands at the bottom of the list).
    @State private var newLane: String?

    var body: some View {
        let me = app.userID?.uuidString.lowercased()
        let tasks = (snap.tasks ?? []).filter { !mineOnly || $0.assigneeId?.lowercased() == me }
        VStack(alignment: .leading, spacing: 0) {
            proposals
            let seg = GlassSegmentedControl(segments: [
                GlassSegment(id: "all", label: app.T("Tất cả", "All"), identifier: "project.tasks.all"),
                GlassSegment(id: "mine", label: app.T("Của tôi", "Mine"), identifier: "project.tasks.mine"),
            ], selection: mineOnly ? "mine" : "all", height: 44, showsIcons: false) { mineOnly = $0 == "mine" }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    seg
                } else {
                    HStack(spacing: 10) { seg.frame(maxWidth: 200); Spacer(minLength: 0) }
                }
            }
            .padding(.bottom, 4)
            ForEach((snap.lanes ?? []).sorted { $0.position < $1.position }) { lane in
                let laneTasks = ProjectPresentation.byDue(tasks.filter { $0.laneId == lane.id })
                if !(mineOnly && laneTasks.isEmpty) { laneSection(lane, laneTasks) }
            }
            // End of the lanes: tells the lane navigator when the list is scrolled to the bottom.
            Color.clear.frame(height: 1).background(GeometryReader { g in
                Color.clear.preference(key: ProjectLaneTopKey.self, value: [ProjectLaneNav.endKey: g.frame(in: .named(ProjectLaneNav.space)).minY])
            })
            if (snap.lanes ?? []).isEmpty {
                Text(app.T("Chưa có hạng mục nào.", "No lanes yet.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                    .projectCard().padding(.top, 14)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.tasksTab")
        .onChange(of: snap.lanes?.count ?? 0) { old, new in
            guard new > old, let lane = (snap.lanes ?? []).max(by: { $0.position < $1.position }) else { return }
            mineOnly = false
            newLane = lane.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { scrollTo("project.lane.\(lane.id)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { withAnimation(.easeOut(duration: 0.4)) { newLane = nil } }
        }
    }

    // MARK: proposals

    @ViewBuilder
    private var proposals: some View {
        let all = (snap.changeRequests ?? [])
        let pending = all.filter { $0.status == "pending" }
        if snap.isHost == true, !pending.isEmpty {
            laneLabel(app.T("Đề xuất chờ duyệt", "Proposals to review"), count: "\(pending.count)")
            ForEach(pending) { r in reviewCard(r) }
        } else if snap.me?.role == "manager", !all.isEmpty {
            laneLabel(app.T("Đề xuất của bạn", "Your proposals"), count: "\(all.count)")
            ForEach(all) { r in ownProposalCard(r) }
        }
    }

    private func reviewCard(_ r: ProjectChangeRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(app.projectChangeTitle(r)).font(BanbeTheme.display(17)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                tag(app.T("Chờ duyệt", "Pending"), fg: app.palette.honey, bg: app.palette.honeyBg)
            }
            Text(r.why).font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
            Text(app.T("Đề xuất bởi \(app.projectPersonName(r.proposedBy))", "Proposed by \(app.projectPersonName(r.proposedBy))"))
                .font(.footnote).foregroundStyle(app.palette.ink3)
            AnyLayout(dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))) {
                Button { openSheet(.declineChange(r.id)) } label: {
                    Label(app.T("Từ chối", "Decline"), systemImage: "xmark").font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44).background(app.palette.blockInset, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("project.proposal.decline.\(r.id)")
                Button { Task { await app.reviewProjectChange(r.id, approve: true, reason: nil) } } label: {
                    Label(app.T("Duyệt", "Approve"), systemImage: "checkmark").font(.body.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(app.projectBusy)
                .accessibilityIdentifier("project.proposal.approve.\(r.id)")
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(app.palette.clayBg, lineWidth: 1.5))
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    private func ownProposalCard(_ r: ProjectChangeRequest) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch r.status {
            case "approved": return (app.T("Đã duyệt", "Approved"), app.palette.paper, app.palette.ink)
            case "declined": return (app.T("Bị từ chối", "Declined"), BanbeTheme.alert, BanbeTheme.alert.opacity(0.14))
            default: return (app.T("Chờ duyệt", "Pending"), app.palette.honey, app.palette.honeyBg)
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.projectChangeTitle(r)).font(.body.weight(.semibold))
                Spacer()
                tag(label, fg: fg, bg: bg)
            }
            if let reason = r.decisionReason, !reason.isEmpty {
                Text("“\(reason)”").font(.subheadline).foregroundStyle(app.palette.ink2)
            } else if r.status == "pending" {
                Text(app.T("Chủ sự kiện sẽ trả lời kèm lý do.", "The Host will reply with a reason.")).font(.footnote).foregroundStyle(app.palette.ink3)
            }
        }
        .projectCard(padding: 14)
        .padding(.bottom, 10)
    }

    // MARK: lanes

    private func laneSection(_ lane: ProjectLane, _ tasks: [ProjectTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: ProjectLanePresets.icon(for: lane.name)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(app.palette.clay).accessibilityHidden(true)
                Text(lane.name.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(app.palette.ink3)
                    .accessibilityAddTraits(.isHeader)
                if app.projectCan("lane.manage") {
                    Button { openSheet(.manageLane(lane.id)) } label: {
                        Image(systemName: "pencil").font(.system(size: 14, weight: .semibold)).foregroundStyle(app.palette.ink2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(app.T("Sửa hạng mục \(lane.name)", "Edit lane \(lane.name)"))
                    .accessibilityIdentifier("project.lane.edit.\(lane.id)")
                }
                Spacer()
                Text("\(tasks.filter { $0.status == "done" }.count)/\(tasks.count)").font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(app.palette.ink3)
            }
            .frame(minHeight: 44)
            if tasks.isEmpty {
                Text(app.T("Chưa có việc trong hạng mục này.", "No tasks in this lane yet.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity).projectCard()
            } else {
                ProjectRowsCard(items: tasks) { t in ProjectTaskRow(task: t, showLane: false) { openSheet(.task(t.id)) } }
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, newLane == lane.id ? 8 : 0)
        .padding(.bottom, newLane == lane.id ? 8 : 0)
        .background(newLane == lane.id ? app.palette.clayBg.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(GeometryReader { g in
            Color.clear.preference(key: ProjectLaneTopKey.self, value: [lane.id: g.frame(in: .named(ProjectLaneNav.space)).minY])
        })
        .id("project.lane.\(lane.id)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.lane.\(lane.id)")
    }

    private func laneLabel(_ title: String, count: String) -> some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
            Spacer()
            Text(count).font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(app.palette.ink3)
        .padding(.bottom, 6)
    }

    private func tag(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text).font(.caption.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(fg).background(bg, in: Capsule())
    }
}

extension AppState {
    /// "Lane: Marketing", "Channel: Zoom · Weekly call", "Rename lane to …" in plain words.
    func projectChangeTitle(_ r: ProjectChangeRequest) -> String {
        let lane = r.laneId.flatMap { id in projectSnapshot?.lanes?.first { $0.id == id }?.name } ?? ""
        switch r.kind {
        case "lane_add": return T("Hạng mục mới: \(r.payload.name ?? "")", "New lane: \(r.payload.name ?? "")")
        case "lane_rename": return T("Đổi tên “\(lane)” thành “\(r.payload.name ?? "")”", "Rename “\(lane)” to “\(r.payload.name ?? "")”")
        case "lane_archive": return T("Lưu trữ hạng mục “\(lane)”", "Archive lane “\(lane)”")
        case "channel_add": return T("Kênh mới: \(r.payload.channel?.label ?? "")", "New channel: \(r.payload.channel?.label ?? "")")
        case "channel_edit": return T("Sửa kênh: \(r.payload.channel?.label ?? "")", "Edit channel: \(r.payload.channel?.label ?? "")")
        default: return T("Gỡ một kênh", "Remove a channel")
        }
    }
}


/// Where each lane's heading sits in the hub's scroll view (Tasks), so the navigator knows which lane is on screen.
struct ProjectLaneTopKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

/// Lane navigator over the Tasks list (2026-11-05): one chip per lane with its icon and done/total. Tap to jump; the lane
/// you're looking at is filled and kept in view as you scroll.
struct ProjectLaneNav: View {
    static let space = "projectScroll"
    static let endKey = "__end"

    /// The lane being looked at: the last heading above a reading line. The line sits near the top (60 pt) for most of
    /// the list, and over the last stretch of scrolling slides down the screen, so lanes too short to reach the top still
    /// each become current in order before the end (they used to be skipped). A list that fits on screen keeps its first lane.
    static func current(_ tops: [String: CGFloat], viewport: CGFloat) -> String? {
        var lanes = tops; let end = lanes.removeValue(forKey: endKey)
        guard !lanes.isEmpty else { return nil }
        var line: CGFloat = 60
        if let end, viewport > 0, (lanes.values.min() ?? 0) <= 60 {
            // The hub pads 110 pt under the list, so the end marker rests at viewport - 111 when scrolled to the bottom.
            let remaining = max(0, end - (viewport - 111))
            let span = viewport * 0.6
            let t = min(1, max(0, 1 - remaining / span))
            line = 60 + t * max(0, viewport - 60 - 120)
        }
        return lanes.filter { $0.value <= line }.max { $0.value < $1.value }?.key ?? lanes.min { $0.value < $1.value }?.key
    }

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let lanes: [ProjectLane]
    let tasks: [ProjectTask]
    let current: String?
    let jump: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lanes.sorted { $0.position < $1.position }) { lane in chip(lane).id(lane.id) }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
            }
            .onChange(of: current) { _, id in
                guard let id else { return }
                if reduceMotion { proxy.scrollTo(id, anchor: .center) }
                else { withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .background(app.palette.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.divider).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Đi tới hạng mục", "Jump to lane"))
        .accessibilityIdentifier("project.laneNav")
    }

    private func chip(_ lane: ProjectLane) -> some View {
        let on = lane.id == current
        let mine = tasks.filter { $0.laneId == lane.id }
        let done = mine.filter { $0.status == "done" }.count
        return Button {
            Haptics.selection()
            jump(lane.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: ProjectLanePresets.icon(for: lane.name)).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? app.palette.paper : app.palette.clay)
                Text(lane.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(done)/\(mine.count)").font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(on ? app.palette.paper.opacity(0.7) : app.palette.ink3)
            }
            .padding(.horizontal, 12).frame(minHeight: 38)
            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
            .background(on ? app.palette.ink : app.palette.block, in: Capsule())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: on)
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityLabel(app.T("\(lane.name), xong \(done) trên \(mine.count)", "\(lane.name), \(done) of \(mine.count) done"))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("project.laneNav.\(lane.id)")
    }
}

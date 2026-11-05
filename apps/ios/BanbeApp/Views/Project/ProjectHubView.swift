import SwiftUI

/// Event Project Hub (note 76, switch `event_project_hub`): one event's private team workspace. Layout from the v6
/// prototype: a bar (back, event name, more), the six-tab row (five visible at rest), and one scrolling body per tab.
/// Pull to refresh asks with the project's version, so an unchanged project costs one tiny request.
struct ProjectHubView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: ProjectSheet?
    /// Tasks: the lane at the top of the list right now (drives the lane navigator's highlight).
    @State private var currentLane: String?
    /// A tapped lane keeps the highlight until the person scrolls by hand: through the jump animation (`laneJumpUntil`),
    /// then while its heading stays where the jump left it (`laneTapY`). Needed because the last lanes can't reach the top.
    @State private var laneTapped: String?
    @State private var laneJumpUntil = Date.distantPast
    @State private var laneTapY: CGFloat?
    @State private var scrollHeight: CGFloat = 0

    /// Phase 5: live sync (the 15 s run-of-show poll) is on only on the event day, on Day-of, with the app in front.
    private var live: Bool { app.projectLiveSyncOn(scenePhaseActive: scenePhase == .active) }

    var body: some View {
        VStack(spacing: 0) {
            if app.projectDemo != nil { demoBanner }
            topBar
            if let snap = app.projectSnapshot {
                ProjectTabBar(tabs: tabs(snap), selection: app.projectTab) { app.projectTab = $0 }
                Rectangle().fill(app.palette.divider).frame(height: 1)
                ZStack(alignment: .bottomTrailing) {
                  ScrollViewReader { proxy in
                   VStack(spacing: 0) {
                    if app.projectTab == "tasks", (snap.lanes ?? []).count > 1 {
                        ProjectLaneNav(lanes: snap.lanes ?? [], tasks: snap.tasks ?? [], current: currentLane ?? (snap.lanes ?? []).min { $0.position < $1.position }?.id) { id in
                            currentLane = id
                            laneTapped = id; laneTapY = nil
                            laneJumpUntil = Date().addingTimeInterval(0.6)
                            withAnimation(.snappy(duration: 0.4)) { proxy.scrollTo("project.lane.\(id)", anchor: .top) }
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            banners(snap)
                            tabBody(snap)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 110)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .refreshable { await app.refreshProject() }
                    .coordinateSpace(name: ProjectLaneNav.space)
                    .background(GeometryReader { g in Color.clear.onAppear { scrollHeight = g.size.height }
                        .onChange(of: g.size.height) { _, h in scrollHeight = h } })
                    .onPreferenceChange(ProjectLaneTopKey.self) { tops in
                        if let tapped = laneTapped {
                            if Date() < laneJumpUntil { return }
                            guard let y = tops[tapped] else { laneTapped = nil; return }
                            if let base = laneTapY {
                                if abs(y - base) < 8 { return }   // still where the jump left it
                                laneTapped = nil; laneTapY = nil  // the person scrolled: follow the list again
                            } else { laneTapY = y; return }
                        }
                        let id = ProjectLaneNav.current(tops, viewport: scrollHeight)
                        if id != currentLane { currentLane = id }
                    }
                    .environment(\.projectScrollTo, ProjectScrollTo { id in
                        withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                    })
                   }
                  }
                    if app.projectTab == "tasks", canAddTask(snap) || canLane { addTaskButton(snap) }
                    if app.projectTab == "topics", app.projectCan("post.question") { newPostButton }
                }
            } else if app.projectLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                failed
            }
        }
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper.ignoresSafeArea())
        .sheet(item: $sheet) { ProjectSheetHost(sheet: $0) { sheet = nil }.projectDemoLinks(app) }
        // Phase 6: the Host's money numbers drive the Money tab's dot, so they load with the project.
        .task(id: app.projectSnapshot?.isHost) { await app.loadProjectMoney() }
        .task(id: live) {
            // One small request every 15 s, mostly answered {unchanged}; stops the moment `live` turns false.
            guard live else { return }
            while !Task.isCancelled {
                await app.pollProjectRos()
                try? await Task.sleep(nanoseconds: UInt64(ProjectLimits.shared.pollSeconds) * 1_000_000_000)
            }
        }
        .environment(\.openProjectSheet, OpenProjectSheet { sheet = $0 })
        .projectDemoLinks(app)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.hub")
    }

    // MARK: demo (migration 216)

    /// Always on top while the admin demo is open, so nobody mistakes the sample for a real project.
    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "theatermasks").accessibilityHidden(true)
            Text(app.T("Bản demo · dữ liệu mẫu · không lưu gì", "Demo · sample data · nothing is saved"))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("project.demoBanner")
            Button { app.endProjectDemo() } label: {
                Text(app.T("Thoát demo", "Exit demo"))
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(app.palette.paper.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project.demoExit")
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 4)
        .background(app.palette.honeyBg)
        .accessibilityElement(children: .contain)
    }

    // MARK: bar

    private var topBar: some View {
        HStack(spacing: 8) {
            circleButton("chevron.left", label: app.T("Quay lại", "Back"), id: "project.back") { app.backFromProject() }
            Text(app.projectSnapshot?.event?.name ?? app.T("Dự án", "Project"))
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Menu {
                Button { Task { await app.refreshProject(full: true) } } label: { Label(app.T("Tải lại", "Refresh"), systemImage: "arrow.clockwise") }
                if app.projectCan("trash.restore") {
                    Button { sheet = .trash } label: { Label(app.T("Thùng rác", "Trash"), systemImage: "trash") }
                }
                if app.projectSnapshot?.me != nil && app.projectSnapshot?.project?.readOnly == false {
                    Button(role: .destructive) { sheet = .leave } label: {
                        Label(app.T("Rời dự án", "Leave project"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(app.palette.block, in: Circle())
            }
            .accessibilityLabel(app.T("Thêm", "More"))
            .accessibilityIdentifier("project.more")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func circleButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(app.palette.block, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: tabs

    private func tabs(_ snap: ProjectSnapshot) -> [ProjectTab] {
        let me = app.userID?.uuidString
        let awaitingPosts = ProjectPresentation.awaiting(snap, me: me).contains { $0.kind != .laneReview }
        let pendingReview = snap.isHost == true && (snap.changeRequests ?? []).contains { $0.status == "pending" }
        return [
            ProjectTab(id: "overview", label: app.T("Tổng quan", "Overview"), icon: "house.fill"),
            ProjectTab(id: "tasks", label: app.T("Việc", "Tasks"), icon: "checkmark", dot: pendingReview),
            ProjectTab(id: "topics", label: app.T("Chủ đề", "Topics"), icon: "checkmark.square", dot: awaitingPosts),
            ProjectTab(id: "team", label: app.T("Đội", "Team"), icon: "person.2"),
            ProjectTab(id: "money", label: app.T("Tiền & cổng", "Money & door"), icon: "creditcard", dot: app.projectMoney?.needsHost == true),
            ProjectTab(id: "dayof", label: app.T("Ngày G", "Day-of"), icon: "calendar"),
        ]
    }

    @ViewBuilder
    private func tabBody(_ snap: ProjectSnapshot) -> some View {
        switch app.projectTab {
        case "tasks": ProjectTasksTab(snap: snap)
        case "team": ProjectTeamTab(snap: snap)
        case "topics": ProjectTopicsTab(snap: snap)
        case "money": ProjectMoneyTab(snap: snap)
        case "dayof": ProjectDayOfTab(snap: snap, live: live)
        default: ProjectOverviewTab(snap: snap)
        }
    }

    // MARK: banners

    @ViewBuilder
    private func banners(_ snap: ProjectSnapshot) -> some View {
        if !app.projectNotice.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BanbeTheme.alert).accessibilityHidden(true)
                Text(app.projectNotice).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { app.projectNotice = "" } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 44, height: 44) }
                    .accessibilityLabel(app.T("Đóng", "Dismiss"))
            }
            .padding(.leading, 14)
            .background(BanbeTheme.alert.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project.notice")
        }
        if snap.project?.readOnly == true {
            Label(app.T("Dự án đã chuyển sang chỉ xem (30 ngày sau sự kiện).", "This project is read-only now (30 days after the event)."),
                  systemImage: "lock")
                .font(.subheadline)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 12)
                .accessibilityIdentifier("project.readOnly")
        }
    }

    // MARK: add task

    private func canAddTask(_ snap: ProjectSnapshot) -> Bool {
        let lead = snap.me?.role == "lane_lead" ? snap.me?.laneId : nil
        return app.projectCan("task.manage", .init(laneId: lead)) && !(snap.lanes ?? []).isEmpty
    }

    /// Adding a lane, or proposing one (a Manager), is allowed.
    private var canLane: Bool { app.projectCan("lane.manage") || app.projectCan("change.propose") }

    /// "Add task / lane": one button, then a choice. Each choice says why when it's at its limit.
    private func addTaskButton(_ snap: ProjectSnapshot) -> some View {
        let lead = snap.me?.role == "lane_lead" ? snap.me?.laneId : nil
        let taskFull = app.projectTaskLimitText(laneID: lead)
        let lanesFull = (snap.lanes ?? []).count >= ProjectLimits.shared.lanesMax
        return Menu {
            if canAddTask(snap) {
                Button { sheet = .newTask(laneID: lead) } label: {
                    Label(app.T("Việc mới", "New task"), systemImage: "checkmark.circle")
                    if let taskFull { Text(taskFull) }
                }
                .disabled(taskFull != nil)
                .accessibilityIdentifier("project.addTask.task")
            }
            if canLane {
                Button { sheet = .newLane } label: {
                    Label(app.projectCan("lane.manage") ? app.T("Hạng mục mới", "New lane") : app.T("Đề xuất hạng mục", "Propose a lane"),
                          systemImage: "square.grid.2x2")
                    Text(lanesFull ? app.T("Đã đủ \(ProjectLimits.shared.lanesMax) hạng mục", "\(ProjectLimits.shared.lanesMax) lanes, the most allowed")
                                   : app.T("\((snap.lanes ?? []).count)/\(ProjectLimits.shared.lanesMax) hạng mục", "\((snap.lanes ?? []).count)/\(ProjectLimits.shared.lanesMax) lanes"))
                }
                .disabled(lanesFull)
                .accessibilityIdentifier("project.addTask.lane")
            }
        } label: {
            Label(app.T("Thêm việc / hạng mục", "Add task / lane"), systemImage: "plus")
                .font(.body.weight(.bold))
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .foregroundStyle(app.palette.paper)
                .background(app.palette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .menuOrder(.fixed)
        .padding(.trailing, 18).padding(.bottom, 22)
        .accessibilityIdentifier("project.addTask")
    }

    private var newPostButton: some View {
        Button { sheet = .compose } label: {
            Label(app.T("Bài mới", "New post"), systemImage: "plus")
                .font(.body.weight(.bold))
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .foregroundStyle(app.palette.paper)
                .background(app.palette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.trailing, 18).padding(.bottom, 22)
        .accessibilityIdentifier("project.newPost")
    }

    private var failed: some View {
        VStack(spacing: 14) {
            Text(app.projectError.isEmpty ? app.T("Chưa tải được dự án.", "Couldn't load the project.") : app.projectError)
                .font(.body).multilineTextAlignment(.center)
            Button(app.T("Thử lại", "Try again")) { Task { await app.refreshProject(full: true) } }
                .font(.body.weight(.semibold)).frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("project.failed")
    }
}

extension View {
    /// In the admin demo, links to outside apps (team channels, the call link) would leave the sample: the hub shows
    /// "Not available in the demo" instead. Outside the demo links open as usual.
    func projectDemoLinks(_ app: AppState) -> some View {
        modifier(ProjectDemoLinks(app: app))
    }
}

private struct ProjectDemoLinks: ViewModifier {
    @ObservedObject var app: AppState
    func body(content: Content) -> some View {
        if app.projectDemo != nil {
            content.environment(\.openURL, OpenURLAction { _ in _ = app.projectDemoBlocksLink(); return .handled })
        } else {
            content
        }
    }
}

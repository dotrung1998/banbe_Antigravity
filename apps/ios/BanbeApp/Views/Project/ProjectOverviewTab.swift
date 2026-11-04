import SwiftUI

/// Overview (v6 prototype): proposals waiting on the Host, team channels, readiness with each lane's progress, what
/// needs attention (blocked, then late), what is coming up, and the decision log.
struct ProjectOverviewTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snap: ProjectSnapshot

    private var tasks: [ProjectTask] { snap.tasks ?? [] }
    private var tz: TimeZone { snap.event?.timeZone ?? .current }

    var body: some View {
        let pending = (snap.changeRequests ?? []).filter { $0.status == "pending" }
        VStack(alignment: .leading, spacing: 0) {
            if snap.isHost == true, !pending.isEmpty { proposalsBanner(pending.count) }
            ProjectChannelsCard(snap: snap).padding(.bottom, 14)
            readinessCard
            let attention = ProjectPresentation.attention(tasks, now: app.projectNow, tz: tz)
            if !attention.isEmpty {
                ProjectSectionHeader(title: app.T("Cần chú ý", "Needs attention"))
                ProjectRowsCard(items: attention) { t in ProjectTaskRow(task: t) { openSheet(.task(t.id)) } }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.overview.attention")
            }
            let coming = ProjectPresentation.comingUp(tasks)
            ProjectSectionHeader(title: app.T("Hạn sắp tới", "Coming up"), actionTitle: app.T("Tất cả", "All"),
                                 actionID: "project.overview.allTasks") { app.projectTab = "tasks" }
            if coming.isEmpty {
                Text(app.T("Không còn việc nào đang mở.", "No open tasks left.")).font(.subheadline).foregroundStyle(app.palette.ink2).projectCard()
            } else {
                ProjectRowsCard(items: coming) { t in ProjectTaskRow(task: t) { openSheet(.task(t.id)) } }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.overview.comingUp")
            }
            let decisions = ProjectPresentation.decisions(snap.posts ?? [])
            if !decisions.isEmpty {
                ProjectSectionHeader(title: app.T("Nhật ký quyết định", "Decision log"))
                ProjectRowsCard(items: decisions) { p in decisionRow(p) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.overview")
    }

    private func proposalsBanner(_ n: Int) -> some View {
        let text = Text(app.T("\(n) đề xuất hạng mục chờ duyệt", n == 1 ? "1 lane proposal to review" : "\(n) lane proposals to review"))
            .font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        let review = Button(app.T("Xem", "Review")) { app.projectTab = "tasks" }
            .font(.body.weight(.bold))
            .padding(.horizontal, 18).frame(minHeight: 44)
            .foregroundStyle(app.palette.paper).background(app.palette.ink, in: Capsule())
            .accessibilityIdentifier("project.overview.review")
        let flag = Image(systemName: "flag").font(.system(size: 16, weight: .semibold)).foregroundStyle(app.palette.clay)
            .frame(width: 40, height: 40).background(app.palette.clayBg, in: Circle()).accessibilityHidden(true)
        // Large text: stacked, so the words never break letter by letter beside the button.
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { text; review }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) { flag; text; Spacer(minLength: 8); review }
            }
        }
        .padding(14)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(app.palette.clayBg, lineWidth: 1.5))
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.overview.proposals")
    }

    private var readinessCard: some View {
        let r = ProjectPresentation.readiness(tasks)
        let lanes = ProjectPresentation.laneProgress(snap.lanes ?? [], tasks)
        let days = ProjectPresentation.daysToGo(snap.event, now: app.projectNow)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProjectRing(percent: r.percent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Mức sẵn sàng", "Readiness")).font(BanbeTheme.display(18))
                    Text(app.T("\(r.done) trên \(r.total) việc xong", "\(r.done) of \(r.total) tasks done"))
                        .font(.subheadline).foregroundStyle(app.palette.ink2)
                    if let days, days >= 0 {
                        Text(days == 0 ? app.T("Hôm nay là ngày diễn ra", "The event is today")
                                       : app.T("Còn \(days) ngày", days == 1 ? "1 day to go" : "\(days) days to go"))
                            .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.clay)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(lanes) { l in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(l.name).font(.subheadline)
                        Spacer()
                        Text("\(l.done)/\(l.total)").font(.footnote.monospacedDigit()).foregroundStyle(app.palette.ink2)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(app.palette.blockInset)
                            Capsule().fill(app.palette.clay).frame(width: l.total == 0 ? 0 : g.size.width * CGFloat(l.done) / CGFloat(l.total))
                        }
                    }
                    .frame(height: 8)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(l.name), " + app.T("\(l.done) trên \(l.total) việc xong", "\(l.done) of \(l.total) tasks done"))
            }
        }
        .projectCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.overview.readiness")
    }

    private func decisionRow(_ p: ProjectPost) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(app.palette.ink2)
                .frame(width: 36, height: 36).background(app.palette.blockInset, in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text([snap.lanes?.first { $0.id == p.laneId }?.name, app.projectPersonName(p.authorId)].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// The readiness ring (clay on the inset fill).
struct ProjectRing: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(app.palette.blockInset, lineWidth: 7)
            Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(app.palette.clay, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: percent)
            Text("\(percent)%").font(.subheadline.weight(.bold).monospacedDigit())
        }
        .frame(width: 64, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Sẵn sàng \(percent) phần trăm", "\(percent) percent ready"))
    }
}

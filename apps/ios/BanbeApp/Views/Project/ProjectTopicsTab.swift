import SwiftUI

/// Topics (v6 prototype): a structured channel with four post types and no free chat. A collapsible rules card, lane
/// filter chips, "Waiting on you" (questions to me, votes I owe, updates I haven't seen), then every post newest first,
/// 20 at a time. The "New post" button lives in ProjectHubView.
struct ProjectTopicsTab: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    let snap: ProjectSnapshot
    @State private var rulesOpen = false
    @State private var laneFilter: String?
    @State private var loadingOlder = false

    private var lanes: [ProjectLane] { (snap.lanes ?? []).sorted { $0.position < $1.position } }
    private var waitingIDs: [String] {
        ProjectPresentation.awaiting(snap, me: app.userID?.uuidString).filter { $0.kind != .laneReview }.map(\.id)
    }

    var body: some View {
        let posts = snap.posts ?? []
        let shown = posts.filter { laneFilter == nil || $0.laneId == laneFilter }
        let waiting = laneFilter == nil ? waitingIDs.compactMap { id in posts.first { $0.id == id } } : []
        let rest = shown.filter { p in !waiting.contains { $0.id == p.id } }
        VStack(alignment: .leading, spacing: 0) {
            rulesCard
            laneChips.padding(.top, 12)
            if !waiting.isEmpty {
                ProjectCountHeader(title: app.T("Chờ bạn", "Waiting on you"), count: waiting.count)
                VStack(spacing: 10) { ForEach(waiting) { ProjectPostCard(post: $0) } }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project.topics.waiting")
            }
            ProjectCountHeader(title: app.T("Tất cả bài", "All posts"), count: shown.count)
            if rest.isEmpty {
                Text(shown.isEmpty ? app.T("Chưa có bài.", "No posts yet.") : app.T("Mọi bài đều ở mục Chờ bạn.", "Every post is in Waiting on you."))
                    .font(.subheadline).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                VStack(spacing: 10) { ForEach(rest) { ProjectPostCard(post: $0) } }
            }
            if posts.count >= 20 && !app.projectPostsExhausted {
                Button {
                    loadingOlder = true
                    Task { await app.loadOlderProjectPosts(); loadingOlder = false }
                } label: {
                    HStack(spacing: 8) {
                        if loadingOlder { ProgressView() }
                        Text(app.T("Xem bài cũ hơn", "Show older posts")).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(loadingOlder)
                .padding(.top, 10)
                .accessibilityIdentifier("project.topics.older")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.topicsTab")
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { rulesOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").font(.system(size: 19, weight: .semibold)).foregroundStyle(app.palette.clay)
                        .accessibilityHidden(true)
                    Text(app.T("Kênh có cấu trúc, không chat tự do", "Structured channel, no free chat"))
                        .font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: rulesOpen ? "minus" : "plus").font(.footnote.weight(.bold)).foregroundStyle(app.palette.ink2)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(rulesOpen ? app.T("Đang mở", "Expanded") : app.T("Đang đóng", "Collapsed"))
            .accessibilityIdentifier("project.topics.rules")
            if rulesOpen {
                let l = ProjectLimits.shared
                VStack(alignment: .leading, spacing: 8) {
                    rule(app.T("4 loại bài: Đề xuất, Câu hỏi, Cập nhật, Quyết định.", "4 post types: Proposal, Question, Update, Decision."))
                    rule(app.T("Bài tối đa \(l.postBodyMax) ký tự, phản hồi \(l.replyMax) ký tự, \(l.repliesMax) phản hồi mỗi bài.",
                               "Posts up to \(l.postBodyMax) characters, replies \(l.replyMax), at most \(l.repliesMax) replies per post."))
                    rule(app.T("Giải quyết xong thì bài khoá lại. Phiếu và “Đã xem” là bộ đếm, không phải tin nhắn.",
                               "Settled posts lock. Votes and “Seen” are counters, not messages."))
                    rule(app.T("Không báo từng bài: gom vào bản tin lúc \(l.digestHour):00 theo giờ của bạn. Chỉ việc bị chặn mới báo ngay.",
                               "No alert for each post: they're bundled into a \(l.digestHour):00 digest on your own clock. Only a blocked task alerts at once."))
                    rule(app.T("Kéo xuống để tải bài mới.", "Pull down to load new posts."))
                    if snap.project?.channels.isEmpty == false {
                        rule(app.T("Muốn trò chuyện thêm? Dùng kênh của đội ở Tổng quan.", "Want to talk it through? Use the team channels on Overview."))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project.topics.rulesBody")
            }
        }
        .projectCard(padding: 6)
    }

    private func rule(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(app.palette.clay).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(app.palette.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var laneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ProjectChip(title: app.T("Tất cả", "All"), selected: laneFilter == nil, id: "project.topics.lane.all") { laneFilter = nil }
                ForEach(lanes) { l in
                    ProjectChip(title: l.name, selected: laneFilter == l.id, id: "project.topics.lane.\(l.id)",
                                icon: ProjectLanePresets.icon(for: l.name)) { laneFilter = l.id }
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// "TITLE · 3" above a list.
struct ProjectCountHeader: View {
    @EnvironmentObject private var app: AppState
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(count)").font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(app.palette.ink3)
        .padding(.top, 20).padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

/// One post in a list: type tag (+ state), title, lane · author, and the counter line for its type.
struct ProjectPostCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    let post: ProjectPost

    var body: some View {
        Button { openSheet(.post(post.id)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProjectTypeTag(type: post.type)
                    Spacer(minLength: 4)
                    if post.state != "open" { ProjectStateTag(state: post.state) }
                }
                Text(post.title).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text([laneName, app.projectPersonName(post.authorId)].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                Text(app.projectPostMeta(post)).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(app.T("Mở bài", "Opens the post"))
        .accessibilityIdentifier("project.post.\(post.id)")
    }

    private var laneName: String? { app.projectSnapshot?.lanes?.first { $0.id == post.laneId }?.name }
}

/// Post type at a glance (2026-11-05): each type has its own hue and filled icon, so Proposal / Question / Update /
/// Decision read apart without reading the word. Decision is solid ink: it is the final, locked kind.
struct ProjectTypeTag: View {
    @EnvironmentObject private var app: AppState
    let type: String
    var body: some View {
        let tint = app.projectPostTint(type)
        HStack(spacing: 5) {
            Image(systemName: app.projectPostIcon(type, filled: true)).font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
            Text(app.projectPostTypeName(type).uppercased()).font(.caption2.weight(.heavy)).tracking(0.6)
        }
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(tint.fg)
        .background(tint.bg, in: Capsule())
    }
}

extension AppState {
    /// Text and fill for a post type's tag; tested for >= 4.5:1 in both themes.
    func projectPostTint(_ type: String) -> (fg: Color, bg: Color) {
        switch type {
        case "proposal": return (palette.honey, palette.honeyBg)
        case "question": return isDark ? (Color(hex: 0x8CC7D4), Color(hex: 0x1E3238)) : (Color(hex: 0x2F6B7A), Color(hex: 0xDCEBEE))
        case "update": return isDark ? (Color(hex: 0xA9C487), Color(hex: 0x27311C)) : (Color(hex: 0x4E6A30), Color(hex: 0xE2E9D4))
        default: return (palette.paper, palette.ink)
        }
    }
}

struct ProjectStateTag: View {
    @EnvironmentObject private var app: AppState
    let state: String
    var body: some View {
        Label(state == "locked" ? app.T("Đã khoá", "Locked") : app.T("Đã giải quyết", "Resolved"), systemImage: "lock.fill")
            .font(.caption.weight(.bold)).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(app.palette.ink2)
            .background(app.palette.blockInset, in: Capsule())
    }
}

extension AppState {
    /// The counter line under a post: votes for a proposal, replies for a question, "seen" for the rest.
    func projectPostMeta(_ p: ProjectPost) -> String {
        let people = projectHeadcount
        switch p.type {
        case "proposal":
            let voted = (p.votes ?? []).reduce(0, +)
            var parts = [T("\(voted)/\(people) đã bỏ phiếu", "\(voted)/\(people) voted")]
            if let d = p.deadline, let due = projectDueText(d) { parts.append(T("Hạn \(due)", "Vote by \(due)")) }
            return parts.joined(separator: " · ")
        case "question":
            return [T("Hỏi \(projectPersonName(p.addresseeId))", "To \(projectPersonName(p.addresseeId))"),
                    T("\(p.repliesCount)/\(ProjectLimits.shared.repliesMax) phản hồi", "\(p.repliesCount)/\(ProjectLimits.shared.repliesMax) replies")]
                .joined(separator: " · ")
        default:
            return T("\(p.seenCount)/\(people) đã xem", "\(p.seenCount)/\(people) seen")
        }
    }
}

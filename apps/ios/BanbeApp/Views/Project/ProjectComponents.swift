import SwiftUI

/// Small shared pieces of the Event Project Hub (note 76). Colours stay on existing tokens: the v6 prototype's green
/// "done" has no token in this app, so done = a filled ink check, doing = honey, blocked = alert, to do = an ink3 ring.

struct ProjectSectionHeader: View {
    @EnvironmentObject private var app: AppState
    let title: String
    var actionTitle: String? = nil
    var actionID: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(BanbeTheme.display(20)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.palette.clay)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(actionID ?? "project.section.action")
            }
        }
        .padding(.top, 22).padding(.bottom, 8)
    }
}

extension View {
    /// A block on paper (the app's card fill), 16pt padding unless rows bring their own.
    func projectCard(padding: CGFloat = 16) -> some View {
        modifier(ProjectCardModifier(padding: padding))
    }
}

private struct ProjectCardModifier: ViewModifier {
    @EnvironmentObject private var app: AppState
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16).padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.block, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ProjectStatusCircle: View {
    @EnvironmentObject private var app: AppState
    let status: String

    var body: some View {
        ZStack {
            switch status {
            case "done":
                Circle().fill(app.palette.ink)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(app.palette.paper)
            case "doing":
                Circle().fill(app.palette.honeyBg)
                Circle().strokeBorder(app.palette.honey, lineWidth: 2)
            case "blocked":
                Circle().fill(BanbeTheme.alert.opacity(0.14))
                Circle().strokeBorder(BanbeTheme.alert, lineWidth: 2)
            default:
                Circle().strokeBorder(app.palette.ink3, lineWidth: 2)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

struct ProjectStatusTag: View {
    @EnvironmentObject private var app: AppState
    let status: String

    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch status {
            case "done": return (app.palette.paper, app.palette.ink)
            case "doing": return (app.palette.honey, app.palette.honeyBg)
            case "blocked": return (BanbeTheme.alert, BanbeTheme.alert.opacity(0.14))
            default: return (app.palette.ink2, app.palette.blockInset)
            }
        }()
        Text(app.projectStatusName(status))
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }
}

/// A choice chip (lane, person, status). 40pt tall; ink when selected.
struct ProjectChip: View {
    @EnvironmentObject private var app: AppState
    let title: String
    let selected: Bool
    var enabled = true
    var id: String? = nil
    var icon: String? = nil
    var count: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)).accessibilityHidden(true) }
                Text(title)
                if let count {
                    Text("\(count)").font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(selected ? app.palette.paper.opacity(0.7) : app.palette.ink3)
                }
            }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .background(selected ? app.palette.ink : app.palette.blockInset, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id ?? "project.chip")
    }
}

/// One task: a 44pt tick target, the title, "lane · person · due", and the status tag. Tapping the row opens it.
struct ProjectTaskRow: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let task: ProjectTask
    var showLane = true
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await app.toggleProjectTaskDone(task) }
            } label: {
                ProjectStatusCircle(status: task.status).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == "done" ? app.T("Bỏ đánh dấu xong", "Mark not done") : app.T("Đánh dấu xong", "Mark done"))
            .accessibilityValue(app.projectStatusName(task.status))
            .accessibilityIdentifier("project.task.tick.\(task.id)")
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(.body.weight(.semibold))
                            .strikethrough(task.status == "done", color: app.palette.ink3)
                            .foregroundStyle(task.status == "done" ? app.palette.ink2 : app.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(meta).font(.footnote).foregroundStyle(late ? BanbeTheme.alert : app.palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        // Large text: the tag moves under the title instead of squeezing it.
                        if dynamicTypeSize.isAccessibilitySize { ProjectStatusTag(status: task.status).padding(.top, 4) }
                    }
                    Spacer(minLength: 6)
                    if !dynamicTypeSize.isAccessibilitySize { ProjectStatusTag(status: task.status) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(app.T("Mở việc", "Opens the task"))
            .accessibilityIdentifier("project.task.\(task.id)")
        }
        .padding(.vertical, 6)
    }

    private var late: Bool {
        guard task.status != "done", let tz = app.projectSnapshot?.event?.timeZone else { return false }
        return (ProjectPresentation.dayDelta(task.dueDate, now: app.projectNow, tz: tz) ?? 0) < 0
    }

    private var meta: String {
        var parts: [String] = []
        if showLane, let lane = app.projectSnapshot?.lanes?.first(where: { $0.id == task.laneId }) { parts.append(lane.name) }
        parts.append(app.projectPersonName(task.assigneeId))
        if let due = app.projectDueText(task.dueDate) { parts.append(due) }
        return parts.joined(separator: " · ")
    }
}

/// A list of rows inside one card, with hairlines between them.
struct ProjectRowsCard<Item: Identifiable, Row: View>: View {
    @EnvironmentObject private var app: AppState
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                row(item)
                if i < items.count - 1 { Rectangle().fill(app.palette.divider).frame(height: 1) }
            }
        }
        .projectCard(padding: 4)
    }
}

extension AppState {
    func projectStatusName(_ status: String) -> String {
        switch status {
        case "done": return T("Xong", "Done")
        case "doing": return T("Đang làm", "Doing")
        case "blocked": return T("Bị chặn", "Blocked")
        default: return T("Cần làm", "To do")
        }
    }

    /// The row tick: done ↔ to do, only for someone allowed to change this task's status.
    func toggleProjectTaskDone(_ task: ProjectTask) async {
        guard projectCan("task.status", .init(laneId: task.laneId, assigneeId: task.assigneeId)) else {
            projectNotice = T("Chỉ người phụ trách, Trưởng hạng mục, Quản lý hoặc Chủ sự kiện đổi được việc này.",
                              "Only the assignee, the lane lead, a Manager or the Host can change this task.")
            return
        }
        Haptics.light()
        await setProjectTaskStatus(task.id, task.status == "done" ? "todo" : "done")
    }
}


/// Ready-made lanes with their icons (2026-11-05). The icon is derived from the lane's name on the client (Vietnamese or
/// English, any case), so no column or migration is needed; a custom name gets the generic grid icon.
enum ProjectLanePresets {
    struct Preset: Identifiable { let vi: String; let en: String; let icon: String; var id: String { en } }

    static let all: [Preset] = [
        // Place and set-up
        Preset(vi: "Địa điểm", en: "Venue", icon: "mappin.and.ellipse"),
        Preset(vi: "Bàn ghế & bố trí", en: "Seating & layout", icon: "chair"),
        Preset(vi: "Trang trí", en: "Decor", icon: "sparkles"),
        Preset(vi: "Hoa", en: "Flowers", icon: "camera.macro"),
        Preset(vi: "Âm thanh & ánh sáng", en: "Sound & light", icon: "speaker.wave.2"),
        Preset(vi: "Sân khấu", en: "Stage", icon: "theatermasks"),
        Preset(vi: "Điện & thiết bị", en: "Power & equipment", icon: "powerplug"),
        Preset(vi: "Giấy phép", en: "Permits", icon: "doc.text"),
        Preset(vi: "An toàn", en: "Safety", icon: "cross.case"),
        // Food and drink
        Preset(vi: "Thực đơn & đồ uống", en: "Food & drinks", icon: "fork.knife"),
        Preset(vi: "Bếp", en: "Kitchen", icon: "frying.pan"),
        Preset(vi: "Quầy bar", en: "Bar", icon: "wineglass"),
        Preset(vi: "Cà phê & trà", en: "Coffee & tea", icon: "cup.and.saucer"),
        Preset(vi: "Bánh & tráng miệng", en: "Cake & dessert", icon: "birthday.cake"),
        // Programme
        Preset(vi: "Chương trình", en: "Programme", icon: "list.bullet.rectangle"),
        Preset(vi: "Nghệ sĩ & diễn giả", en: "Artists & speakers", icon: "music.mic"),
        Preset(vi: "DJ & nhạc", en: "DJ & music", icon: "music.note"),
        Preset(vi: "Workshop", en: "Workshop", icon: "paintpalette"),
        Preset(vi: "Trò chơi & hoạt động", en: "Games & activities", icon: "gamecontroller"),
        Preset(vi: "Trẻ em", en: "Kids", icon: "figure.and.child.holdinghands"),
        // People
        Preset(vi: "Khách mời", en: "Guests", icon: "person.2"),
        Preset(vi: "Vé & cổng", en: "Tickets & door", icon: "ticket"),
        Preset(vi: "Tình nguyện viên", en: "Volunteers", icon: "hand.raised"),
        Preset(vi: "Nhà tài trợ", en: "Sponsors", icon: "star"),
        Preset(vi: "Đối tác", en: "Partners", icon: "person.2.wave.2"),
        Preset(vi: "Nhà cung cấp", en: "Suppliers", icon: "shippingbox"),
        // Getting the word out
        Preset(vi: "Truyền thông", en: "Marketing", icon: "megaphone"),
        Preset(vi: "Mạng xã hội", en: "Social media", icon: "bubble.left.and.bubble.right"),
        Preset(vi: "Thiết kế", en: "Design", icon: "pencil.and.ruler"),
        Preset(vi: "Chụp ảnh & quay phim", en: "Photo & video", icon: "camera"),
        Preset(vi: "Báo chí", en: "Press", icon: "newspaper"),
        // Money and running it
        Preset(vi: "Ngân sách", en: "Budget", icon: "banknote"),
        Preset(vi: "Hậu cần", en: "Logistics", icon: "car"),
        Preset(vi: "Đi lại & chỗ ở", en: "Travel & stay", icon: "bed.double"),
        Preset(vi: "Quà tặng", en: "Gifts & merch", icon: "gift"),
        Preset(vi: "Dọn dẹp", en: "Clean-up", icon: "trash"),
    ]
    static let customIcon = "square.grid.2x2"

    static func key(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func preset(named name: String) -> Preset? { let k = key(name); return all.first { key($0.vi) == k || key($0.en) == k } }
    static func icon(for name: String) -> String { preset(named: name)?.icon ?? customIcon }
    /// Presets whose Vietnamese or English name contains the query (accent- and case-insensitive).
    static func search(_ query: String) -> [Preset] {
        let q = key(query); guard !q.isEmpty else { return all }
        return all.filter { key($0.vi).contains(q) || key($0.en).contains(q) }
    }
}


/// A quiet tip that helps people keep a project small (lane and task sheets). `firm` turns it honey when near a limit.
struct ProjectGuidance: View {
    @EnvironmentObject private var app: AppState
    let text: String
    let firm: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: firm ? "exclamationmark.circle.fill" : "lightbulb")
                .font(.system(size: 15, weight: .semibold)).padding(.top, 1).accessibilityHidden(true)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(firm ? app.palette.honey : app.palette.ink2)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(firm ? app.palette.honeyBg : app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project.guidance")
    }
}

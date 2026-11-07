import SwiftUI

/// The Day-of time grid (v6 "Calendar"): hour lines on the left, one block per run-of-show item placed by `RosLayout`
/// (the shared, fixture-tested port of the prototype's layoutDay), and the now line. An unticked item stretches along
/// the clock, the next one is squeezed (never under 10 minutes), later ones stay put, overlaps are flagged; ticking
/// freezes the end. Colours stay on tokens: active = clay, overrun = alert, squeezed = honey, done = inset (the
/// prototype's moss has no token). "Now" is the device clock (a UI fixture pins it), redrawn every 30 seconds.
struct ProjectRosGrid: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openProjectSheet) private var openSheet
    @Environment(\.projectScrollTo) private var scrollTo
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snap: ProjectSnapshot

    private let gutter: CGFloat = 52
    private var ppm: CGFloat { dynamicTypeSize.isAccessibilitySize ? 2.6 : 1.9 }
    private var editor: Bool { app.projectCan("ros.edit") }

    /// Every item placed "now", by id.
    static func placed(_ items: [ProjectRosItem], now: Date) -> [String: RosLayout.Placed] {
        Dictionary(uniqueKeysWithValues: layout(items, now: now).items.map { ($0.id, $0) })
    }

    static func layout(_ items: [ProjectRosItem], now: Date) -> RosLayout.Result {
        func ms(_ d: Date) -> Int { Int((d.timeIntervalSince1970 * 1000).rounded()) }
        let input = items.compactMap { r -> RosLayout.Item? in
            guard let s = ProjectDates.parse(r.startsAt), let e = ProjectDates.parse(r.endsAt) else { return nil }
            return RosLayout.Item(id: r.id, startsAt: ms(s), endsAt: ms(e), doneAt: ProjectDates.parse(r.doneAt).map(ms))
        }
        return RosLayout.layout(input, now: ms(now))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content(now: app.projectNow)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let items = snap.ros ?? []
        let result = Self.layout(items, now: now)
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let axis = result.axis, nowMs >= axis.start, nowMs <= axis.end {
                    Button { scrollTo("project.ros.now") } label: {
                        Label(app.T("Về giờ hiện tại", "Jump to now"), systemImage: "scope").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 44).background(app.palette.blockInset, in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("project.ros.jumpNow")
                }
                Spacer(minLength: 0)
            }
            legend
            if !result.chips.isEmpty {
                Text(app.T("Lệch so với kế hoạch", "Versus the plan")).font(BanbeTheme.display(18)).accessibilityAddTraits(.isHeader)
                // Large text: one chip per line so each can wrap (a flow row gives them unlimited width).
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(FlowLayout(spacing: 8, lineSpacing: 8))
                layout {
                    ForEach(Array(result.chips.enumerated()), id: \.offset) { _, c in chip(c, items: items) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project.ros.chips")
            }
            if let axis = result.axis {
                grid(result, axis: axis, items: items, nowMs: nowMs)
            } else {
                Text(app.T("Chưa có mốc nào.", "No items yet.")).font(.subheadline).foregroundStyle(app.palette.ink2)
                    .padding(.vertical, 18).frame(maxWidth: .infinity).projectCard()
            }
            Text(app.T("Việc chưa tick sẽ kéo dài theo giờ; chỉ việc ngay sau bị rút ngắn (tối thiểu 10 phút), các việc sau giữ nguyên. Tick xong thì chốt giờ kết thúc.",
                       "An unticked item stretches along the clock; only the very next one is squeezed (10 minutes at least), later ones stay put. Ticking it freezes its end.")
                 + (editor ? app.T(" Chạm vào khối để sửa.", " Tap a block to edit it.") : ""))
                .font(.footnote).foregroundStyle(app.palette.ink3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.ros.grid")
    }

    private var legend: some View {
        FlowLayout(spacing: 12, lineSpacing: 6) {
            legendItem(BanbeTheme.alert, app.T("Kéo dài", "Overrun"))
            legendItem(app.palette.honey, app.T("Bị rút", "Squeezed"))
            legendItem(app.palette.clay, app.T("Đang diễn ra", "Now"))
            legendItem(app.palette.ink3, app.T("Xong", "Done"))
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(app.palette.ink2)
        }
    }

    private func chip(_ c: RosLayout.Chip, items: [ProjectRosItem]) -> some View {
        let title = items.first { $0.id == c.id }?.title ?? ""
        let (text, tone): (String, ProjectRosBadge.Tone) = {
            switch c.kind {
            case .overrun: return (app.T("\(title) +\(c.minutes)′", "\(title) +\(c.minutes) min"), .alert)
            case .squeezed: return (app.T("\(title) −\(c.minutes)′", "\(title) −\(c.minutes) min"), .honey)
            case .overlap: return (app.T("\(title): chồng giờ", "\(title): overlaps"), .alert)
            }
        }()
        return ProjectRosBadge(text: text, tone: tone, wraps: true)
    }

    // MARK: grid

    private func y(_ ms: Int, _ axis: RosLayout.Axis) -> CGFloat { CGFloat(ms - axis.start) / 60_000 * ppm }

    @ViewBuilder
    private func grid(_ result: RosLayout.Result, axis: RosLayout.Axis, items: [ProjectRosItem], nowMs: Int) -> some View {
        let height = y(axis.end, axis)
        // Half-hour steps, labelled on the whole hours of the event's zone (the axis is already on a half hour).
        let hours = stride(from: axis.start, through: axis.end, by: 1_800_000).filter(isWholeHour)
        ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { h in
                HStack(spacing: 6) {
                    Text(app.projectClock(Date(timeIntervalSince1970: Double(h) / 1000)))
                        .font(.caption.monospacedDigit()).foregroundStyle(app.palette.ink3)
                        .lineLimit(1).fixedSize()
                        .frame(width: gutter - 6, alignment: .leading)
                    Rectangle().fill(app.palette.divider).frame(height: 1)
                }
                .offset(y: y(h, axis) - 8)
                .accessibilityHidden(true)
            }
            ForEach(result.items, id: \.id) { p in
                if let item = items.first(where: { $0.id == p.id }) {
                    block(p, item: item)
                        .frame(height: max(30, y(p.end, axis) - y(p.start, axis) - 3))
                        .padding(.leading, gutter)
                        .offset(y: y(p.start, axis))
                }
            }
            if nowMs >= axis.start && nowMs <= axis.end {
                nowLine(nowMs).offset(y: y(nowMs, axis) - 11)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(.top, 10)
        // A time grid is spatial: past this size labels can't fit their slots. The List view keeps full Dynamic Type,
        // and every block reads its whole content to VoiceOver.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func isWholeHour(_ ms: Int) -> Bool {
        let tz = snap.event?.timeZone ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.minute, from: Date(timeIntervalSince1970: Double(ms) / 1000)) == 0
    }

    private func nowLine(_ nowMs: Int) -> some View {
        HStack(spacing: 0) {
            Text(app.projectClock(Date(timeIntervalSince1970: Double(nowMs) / 1000)))
                .font(.caption.weight(.heavy).monospacedDigit()).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(app.palette.clay, in: RoundedRectangle(cornerRadius: 7))
            Circle().fill(app.palette.clay).frame(width: 10, height: 10)
            Rectangle().fill(app.palette.clay).frame(height: 2.5)
        }
        .frame(height: 22)
        .allowsHitTesting(false)
        .id("project.ros.now")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Bây giờ", "Now") + " " + app.projectClock(Date(timeIntervalSince1970: Double(nowMs) / 1000)))
        .accessibilityIdentifier("project.ros.nowLine")
    }

    private func block(_ p: RosLayout.Placed, item: ProjectRosItem) -> some View {
        let late = p.overrun
        let edge: Color = p.done ? app.palette.ink3 : p.active ? app.palette.clay : late ? BanbeTheme.alert : p.squeezed ? app.palette.honey : app.palette.ink3
        let fill: Color = p.done ? app.palette.blockInset : p.active ? app.palette.clayBg : late ? BanbeTheme.alert.opacity(0.12)
            : p.squeezed ? app.palette.honeyBg : app.palette.block
        let start = Date(timeIntervalSince1970: Double(p.start) / 1000)
        let end = Date(timeIntervalSince1970: Double(p.end) / 1000)
        let times = "\(app.projectClock(start))–\(app.projectClock(end))"
        return HStack(alignment: .top, spacing: 6) {
            Button {
                if editor { openSheet(.rosItem(item.id)) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.bold)).lineLimit(1)
                        .strikethrough(p.done, color: app.palette.ink3)
                    HStack(spacing: 6) {
                        Text("\(times) · \(app.projectPersonName(item.ownerId))").font(.caption.monospacedDigit())
                            .foregroundStyle(app.palette.ink2).lineLimit(1)
                        if late { ProjectRosBadge(text: "+\(p.overrunMin)′", tone: .alert) }
                        else if p.overlap { ProjectRosBadge(text: app.T("chồng giờ", "overlap"), tone: .alert) }
                        else if p.squeezed { ProjectRosBadge(text: "−\(p.squeezedMin)′", tone: .honey) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(blockLabel(p, item: item, times: times))
            .accessibilityHint(editor ? app.T("Mở để sửa", "Opens it to edit") : "")
            .accessibilityIdentifier("project.ros.block.\(item.id)")
            ProjectRosTick(item: item).frame(width: 36, height: 36)
        }
        .padding(.leading, 11).padding(.trailing, 4).padding(.vertical, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14).fill(edge).frame(width: 5)
        }
        .overlay {
            if p.overlap {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BanbeTheme.alert, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func blockLabel(_ p: RosLayout.Placed, item: ProjectRosItem, times: String) -> String {
        var parts = [item.title, times, app.projectPersonName(item.ownerId)]
        if p.done { parts.append(app.T("xong", "done")) }
        else if p.active { parts.append(app.T("đang diễn ra", "happening now")) }
        if p.overrun { parts.append(app.T("trễ \(p.overrunMin) phút", "\(p.overrunMin) minutes over")) }
        if p.squeezed { parts.append(app.T("bị rút \(p.squeezedMin) phút", "squeezed by \(p.squeezedMin) minutes")) }
        if p.overlap { parts.append(app.T("chồng giờ", "overlaps")) }
        return parts.joined(separator: ", ")
    }
}

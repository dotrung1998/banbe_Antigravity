import SwiftUI

/// One tab of the Event Project Hub (note 76).
struct ProjectTab: Identifiable, Equatable {
    let id: String
    let label: String
    let icon: String
    var dot = false
}

/// The hub's tab row (v6 prototype): icon over label, EXACTLY five slots visible at rest whatever the screen width
/// (`containerRelativeFrame(count: 5)`, iOS 17), the row scrolls sideways for more, a right-edge fade and chevron say
/// "more this way" until the last tab is in view, and the selected tab is always scrolled into view. Adding tabs later
/// keeps the five-slot rule. VoiceOver reads every tab ("Tasks, tab 2 of 6") whether or not it is on screen.
struct ProjectTabBar: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tabs: [ProjectTab]
    let selection: String
    let onSelect: (String) -> Void

    /// The tab at the leading edge (`.scrollPosition(id:)`, iOS 17; view-aligned, so always a whole tab).
    @State private var leadingID: String?

    /// At the end once the leading tab plus the five visible slots reach the last tab.
    private var atEnd: Bool {
        let i = leadingID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? 0
        return i + 5 >= tabs.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { i, tab in
                        tabButton(tab, index: i)
                            .containerRelativeFrame(.horizontal, count: 5, spacing: 4)
                            .id(tab.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 10, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $leadingID, anchor: .leading)
            .overlay(alignment: .trailing) { edgeHint }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, id in
                if reduceMotion { proxy.scrollTo(id, anchor: .center) }
                else { withAnimation(.snappy(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .padding(.vertical, 6)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.tabs")
    }

    private func tabButton(_ tab: ProjectTab, index: Int) -> some View {
        let on = tab.id == selection
        return Button {
            Haptics.selection()
            onSelect(tab.id)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
                // Always one line that shrinks to fit, so every tab is the same height ("Money & door" used to wrap and
                // stand taller than the rest).
                Text(tab.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
            .padding(.horizontal, 2)
            .foregroundStyle(on ? app.palette.paper : app.palette.ink)
            .background(on ? app.palette.ink : app.palette.block, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if tab.dot {
                    Circle().fill(BanbeTheme.alert).frame(width: 9, height: 9).padding(6).accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityLabel(app.T("\(tab.label), thẻ \(index + 1) trên \(tabs.count)", "\(tab.label), tab \(index + 1) of \(tabs.count)")
                            + (tab.dot ? app.T(", cần chú ý", ", needs attention") : ""))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("project.tab.\(tab.id)")
    }

    /// Fade + chevron at the right edge while more tabs are off screen (decoration: VoiceOver already lists every tab).
    private var edgeHint: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: [app.palette.paper.opacity(0), app.palette.paper], startPoint: .leading, endPoint: .trailing)
                .frame(width: 22)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(app.palette.ink3)
                .padding(.trailing, 2)
        }
        .frame(maxHeight: .infinity)
        .opacity(atEnd ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: atEnd)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            #if DEBUG
            // UI tests only: the hint itself is hidden from VoiceOver, so a fixture run exposes its state here.
            if UITestFixture.isActive {
                Text(atEnd ? "atEnd" : "more").font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier(atEnd ? "project.tabs.atEnd" : "project.tabs.more")
            }
            #endif
        }
    }
}

import SwiftUI

/// One tab of a `GlassSegmentedControl`.
struct GlassSegment: Identifiable, Equatable {
    let id: String
    let label: String
    var icon: String? = nil
    var badge: Int = 0
    var badgeID: String? = nil
    /// Spoken label when it differs from `label` (e.g. includes the badge count).
    var spokenLabel: String? = nil
    let identifier: String
}

/// The segmented control used by Account's tabs, Schedule's My schedule / Discover and the Month
/// view: a track with ONE glass bubble that sits under the selected tab and can be PICKED UP and
/// dragged across the tabs (it follows the finger, stretches slightly, then settles on the
/// nearest tab when released) — the iOS 26 segmented-control feel, with the system glass bubble
/// (`nativeGlass`, so it follows the iPhone's Liquid Glass / Reduce Transparency settings).
/// A tap on a tab selects it too. VoiceOver gets one button per tab with the selected trait.
struct GlassSegmentedControl: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let segments: [GlassSegment]
    let selection: String
    var height: CGFloat = 48
    var showsIcons: Bool = true
    /// Frame of the control in the "rootGesture" space, so a parent's own horizontal swipe can
    /// ignore drags that start on the bubble (they belong to the bubble).
    var frame: Binding<CGRect>? = nil
    let onSelect: (String) -> Void

    @State private var dragX: CGFloat?
    @State private var lastHaptic = -1

    private var index: Int { segments.firstIndex { $0.id == selection } ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let n = max(segments.count, 1)
            let w = geo.size.width / CGFloat(n)
            let hover = dragX.map { min(max(Int($0 / w), 0), n - 1) }
            let shown = hover ?? index
            let thumbX: CGFloat = dragX.map { min(max($0 - w / 2, 0), geo.size.width - w) } ?? CGFloat(index) * w
            ZStack(alignment: .leading) {
                Capsule().fill(app.palette.field)
                // The bubble.
                Color.clear
                    .frame(width: max(w - 6, 0), height: max(geo.size.height - 6, 0))
                    .nativeGlass(Capsule(), interactive: true)
                    .overlay(Capsule().stroke(app.palette.ink.opacity(0.14), lineWidth: 1))
                    .scaleEffect(dragX == nil ? 1 : 1.08)
                    .offset(x: thumbX + 3)
                    .animation(dragX == nil && !reduceMotion ? .snappy(duration: 0.26) : nil, value: thumbX)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: dragX == nil)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                        segmentLabel(seg, selected: i == shown)
                            .frame(width: w, height: geo.size.height)
                    }
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragX = v.location.x
                        let i = min(max(Int(v.location.x / w), 0), n - 1)
                        if i != lastHaptic { if lastHaptic != -1 { Haptics.selection() }; lastHaptic = i }
                    }
                    .onEnded { v in
                        let i = min(max(Int(v.location.x / w), 0), n - 1)
                        lastHaptic = -1
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) { dragX = nil }
                        if segments.indices.contains(i), segments[i].id != selection { onSelect(segments[i].id) }
                    }
            )
            .background {
                if let frame {
                    Color.clear
                        .onAppear { frame.wrappedValue = geo.frame(in: .named("rootGesture")) }
                        .onChange(of: geo.frame(in: .named("rootGesture"))) { _, f in frame.wrappedValue = f }
                }
            }
        }
        .frame(height: height)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
    }

    private func segmentLabel(_ seg: GlassSegment, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if showsIcons, let icon = seg.icon {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
            }
            Text(seg.label)
                .font(.system(.subheadline, design: .rounded).weight(selected ? .bold : .semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
            if seg.badge > 0 {
                Text(AccountBadges.format(seg.badge))
                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(BanbeTheme.alert, in: Capsule())
                    .foregroundStyle(BanbeTheme.onAlert)
                    .accessibilityIdentifier(seg.badgeID ?? "\(seg.identifier).badge")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seg.spokenLabel ?? seg.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(seg.id) }
        .accessibilityIdentifier(seg.identifier)
    }
}

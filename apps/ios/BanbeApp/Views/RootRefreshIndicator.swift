import SwiftUI

/// Refresh-indicator fix pass (2026-09-27, follow-up A) — replaces the
/// system spinner `.refreshable{}` draws (no public API recolors or
/// reshapes `UIRefreshControl`'s own spinner, so it genuinely can't be
/// reskinned in place — this ticket's own escape hatch for exactly that
/// case) with a thin stroke segment traveling around the OUTLINE of the
/// tab actually being refreshed, via `.trim(from:to:)` on that icon's own
/// real path (`RootTabOutline`, BottomTabBar.swift) — never a generic
/// circle, never a filled icon. Before release, the stroke just grows with
/// pull distance (no travel, `progress` 0...1); once the real reload is
/// running, a fixed-length segment travels the outline continuously until
/// it resolves. Reduce Motion drops the travel loop entirely — a static
/// outline plus this view's own `accessibilityLabel` is what announces
/// progress instead.
struct RootRefreshIndicator: View {
    let screen: Screen
    let progress: CGFloat
    let refreshing: Bool
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = 0
    private let size: CGFloat = 26
    private let segment: CGFloat = 0.26

    var body: some View {
        let outline = RootTabOutline.path(for: screen, size: size)
        ZStack {
            outline.stroke(app.palette.rule, lineWidth: 2.2)
            if refreshing && !reduceMotion {
                outline.trim(from: primaryRange.0, to: primaryRange.1)
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                if let wrap = wrapRange {
                    outline.trim(from: wrap.0, to: wrap.1)
                        .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            } else {
                outline.trim(from: 0, to: refreshing ? 1 : min(1, max(0, progress)))
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .onChange(of: refreshing) { _, isRefreshing in
            guard isRefreshing, !reduceMotion else { return }
            travel = 0
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                travel = 1
            }
        }
        .accessibilityElement()
        .accessibilityLabel(refreshing ? app.T("Đang làm mới", "Refreshing") : "")
    }

    private var primaryRange: (CGFloat, CGFloat) {
        let start = travel.truncatingRemainder(dividingBy: 1)
        return (start, min(1, start + segment))
    }
    private var wrapRange: (CGFloat, CGFloat)? {
        let start = travel.truncatingRemainder(dividingBy: 1)
        let overflow = start + segment - 1
        guard overflow > 0 else { return nil }
        return (0, overflow)
    }
}

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
    /// Chip diameter, shared with `RootPullIndicatorHost`'s positioning maths.
    static let chipSize: CGFloat = 40
    private let size: CGFloat = 24
    private let segment: CGFloat = 0.26

    private var p: CGFloat { refreshing ? 1 : min(1, max(0, progress)) }
    private var ready: Bool { progress >= 1 || refreshing }

    var body: some View {
        let outline = RootTabOutline.path(for: screen, size: size)
        ZStack {
            Circle().fill(app.palette.paper.opacity(0.96))
            Circle().strokeBorder(app.palette.rule, lineWidth: 0.75)
            outline.stroke(app.palette.rule, lineWidth: 2).frame(width: size, height: size)
            if refreshing && !reduceMotion {
                // Continuous loop derived from the clock, so it needs no state and stops cleanly.
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate / 0.9
                    let start = CGFloat(t - floor(t))
                    ZStack {
                        outline.trim(from: start, to: min(1, start + segment))
                            .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        if start + segment > 1 {
                            outline.trim(from: 0, to: start + segment - 1)
                                .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        }
                    }
                }
                .frame(width: size, height: size)
            } else {
                outline.trim(from: 0, to: p)
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: Self.chipSize, height: Self.chipSize)
        .shadow(color: .black.opacity(0.14), radius: 8, y: 2)
        // Pull: 0.6 -> 1 and fade in with progress; a small pop when the ring completes.
        .scaleEffect(reduceMotion ? 1 : (0.6 + 0.4 * p) * (ready && !refreshing ? 1.08 : 1))
        .opacity(p)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.6), value: ready)
        .onChange(of: progress >= 1) { _, isReady in
            if isReady && !refreshing { Haptics.light() }
        }
        .accessibilityElement()
        .accessibilityLabel(refreshing ? app.T("Đang làm mới", "Refreshing") : "")
        .accessibilityHidden(!refreshing)
    }
}

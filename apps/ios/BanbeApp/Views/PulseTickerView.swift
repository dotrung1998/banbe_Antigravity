import SwiftUI

/// Banbe Pulse as one slim line at the top of Home (note 51), replacing the big Pulse tile that used to sit in the
/// story row and left a tall empty band whenever there were no stories. A "✦ Pulse" chip (same gradient as the old
/// ring), then today's top events scrolling past like a news ticker, then a chevron. Tapping anywhere opens the
/// Pulse viewer, exactly like the old tile did. Web twin: src/components/home/PulseTicker.jsx.
///
/// - Data is the daily Banbe Pulse ranking (already loaded for the "Popular" sort): never invented. With no ranking
///   yet the line is a static invitation, not an empty box.
/// - Motion is a pure function of the clock (offset = elapsed × speed, wrapped over one copy of the text), so it can
///   never drift, stack animations, or jump when the view re-appears. It is paused while the app is not active and
///   replaced by one static, truncated line under Reduce Motion.
struct PulseTickerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()

    private var items: [PulseTicker.Item] { PulseTicker.items(from: app.pulseDaily) }

    private static let chipColors: [Color] = [
        Color(red: 0.85, green: 0.66, blue: 0.62), // dusty rose
        Color(red: 0.80, green: 0.66, blue: 0.42), // warm sand
        Color(red: 0.66, green: 0.69, blue: 0.56), // sage
    ]

    var body: some View {
        SwipeSafeButton {
            Haptics.light()
            app.openPulseViewer()
        } label: {
            HStack(spacing: 10) {
                chip
                track
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)).opacity(0.5)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 5).padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
            .foregroundStyle(app.palette.ink)
            .background { Color.clear.nativeGlassCapsule(interactive: true) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.pulseTicker")
        .accessibilityValue("\(items.count)")
        .onAppear { startedAt = Date() }
    }

    private var label: String {
        items.isEmpty
            ? app.T("Banbe Pulse. Xem điều gì đang hot. Mở", "Banbe Pulse. See what's trending. Open")
            : app.T("Banbe Pulse. Top sự kiện: \(items.map(\.name).joined(separator: ", ")). Mở",
                    "Banbe Pulse. Top events: \(items.map(\.name).joined(separator: ", ")). Open")
    }

    private var chip: some View {
        Text("✦ Pulse")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .white.opacity(0.45), radius: 3)
            .padding(.horizontal, 11).frame(height: 28)
            .background(LinearGradient(colors: Self.chipColors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .accessibilityHidden(true)
    }

    /// The track is an empty, fixed-height, full-width box and the text is an OVERLAY on it: the scrolling strip is
    /// much wider than the box, and as an overlay its width can never leak into the layout (the capsule once ran off
    /// the screen's right edge). Clipped to the box and faded at both ends.
    private var track: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(alignment: .leading) { trackContent }
            .clipped()
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.93), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
    }

    @ViewBuilder
    private var trackContent: some View {
        if items.isEmpty {
            Text(app.T("Xem điều gì đang hot tuần này", "See what's trending this week"))
                .font(.system(size: 13.5)).opacity(0.7).lineLimit(1)
                .accessibilityIdentifier("home.pulseTicker.empty")
        } else if reduceMotion {
            Text(items.map { "\($0.rank) \($0.name)" }.joined(separator: "   ·   "))
                .font(.system(size: 13.5, weight: .medium)).lineLimit(1)
        } else {
            MarqueeStrip(startedAt: startedAt, paused: scenePhase != .active,
                         secondsPerPass: PulseTicker.seconds(for: items)) { strip }
        }
    }

    /// One copy of the text: "1 Name   2 Name   3 Name".
    private var strip: some View {
        HStack(spacing: 22) {
            ForEach(items) { it in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(it.rank)").font(.system(size: 12, weight: .bold)).monospacedDigit().opacity(0.55)
                    Text(it.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1).fixedSize()
                }
            }
        }
    }
}

/// Scrolls `content` right-to-left forever. Two copies side by side, shifted by (elapsed × speed) modulo one copy's
/// width plus the gap, so the loop is seamless. The speed is set so one pass takes `secondsPerPass`.
private struct MarqueeStrip<Content: View>: View {
    let startedAt: Date
    let paused: Bool
    let secondsPerPass: Double
    @ViewBuilder let content: () -> Content
    @State private var contentWidth: CGFloat = 0
    private let gap: CGFloat = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { tl in
            let run = max(contentWidth + gap, 1)
            // Speed in points per second so a pass over one copy lasts `secondsPerPass`.
            let speed = run / max(secondsPerPass, 1)
            let elapsed = tl.date.timeIntervalSince(startedAt)
            let offset = -CGFloat((elapsed * Double(speed)).truncatingRemainder(dividingBy: Double(run)))
            HStack(spacing: gap) {
                content().fixedSize()
                content().fixedSize().accessibilityHidden(true)
            }
            .offset(x: offset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(alignment: .leading) {
            // Measures one copy (hidden, never laid out for the user).
            content().fixedSize()
                .background(GeometryReader { Color.clear.preference(key: MarqueeWidthKey.self, value: $0.size.width) })
                .hidden()
        }
        .onPreferenceChange(MarqueeWidthKey.self) { contentWidth = $0 }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

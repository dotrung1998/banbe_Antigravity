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
        let its = items
        SwipeSafeButton {
            Haptics.light()
            app.openPulseViewer()
        } label: {
            HStack(spacing: 10) {
                chip
                track(its)
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
        .accessibilityLabel(label(its))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.pulseTicker")
        .accessibilityValue("\(its.count)")
        .onAppear { startedAt = Date() }
    }

    private func label(_ items: [PulseTicker.Item]) -> String {
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
    private func track(_ items: [PulseTicker.Item]) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay(alignment: .leading) { trackContent(items) }
            .clipped()
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.93), .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
    }

    @ViewBuilder
    private func trackContent(_ items: [PulseTicker.Item]) -> some View {
        if items.isEmpty {
            Text(app.T("Xem điều gì đang hot tuần này", "See what's trending this week"))
                .font(.system(size: 13.5)).opacity(0.7).lineLimit(1)
                .accessibilityIdentifier("home.pulseTicker.empty")
        } else if reduceMotion {
            Text(items.map { "\($0.rank) \($0.name)" }.joined(separator: "   ·   "))
                .font(.system(size: 13.5, weight: .medium)).lineLimit(1)
        } else {
            MarqueeStrip(startedAt: startedAt, paused: scenePhase != .active,
                         secondsPerPass: PulseTicker.seconds(for: items),
                         ink: app.palette.ink, renderKey: items.map(\.name).joined(separator: "\u{1}")) { strip(items) }
        }
    }

    /// One copy of the text: "1 Name   2 Name   3 Name".
    private func strip(_ items: [PulseTicker.Item]) -> some View {
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

/// Scrolls `content` right-to-left forever. Two copies side by side, shifted by (elapsed x speed) modulo one copy's
/// width plus the gap, so the loop is seamless. The speed is set so one pass takes `secondsPerPass`.
///
/// Measured (2026-11-11): the previous TimelineView version re-ran the whole Home view graph and display-list pass
/// ~30x per second for as long as it was mounted (a LazyVStack keeps it mounted after the first scroll to it): 8% of
/// the main thread while Home sat idle, 12% of it during a scripted scroll, on the simulator. The strip is now drawn
/// once into a bitmap and moved by a Core Animation translation, which the render server runs with no main-thread work.
private struct MarqueeStrip<Content: View>: View {
    let startedAt: Date
    let paused: Bool
    let secondsPerPass: Double
    let ink: Color
    /// Anything that changes what the bitmap shows other than the colour (the text itself).
    let renderKey: String
    @ViewBuilder let content: () -> Content
    @State private var bitmap: UIImage?
    @State private var renderedFor = ""
    @Environment(\.displayScale) private var displayScale
    private let gap: CGFloat = 28

    var body: some View {
        let key = "\(renderKey)|\(UIColor(ink).cgColor.components ?? [])|\(displayScale)"
        MarqueeLayerView(image: bitmap, scale: displayScale, gap: gap, secondsPerPass: secondsPerPass,
                         startedAt: startedAt, paused: paused)
            .frame(width: bitmap.map { $0.size.width } ?? 0, height: bitmap.map { $0.size.height } ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { render(key) }
            .onChange(of: key) { _, k in render(k) }
    }

    private func render(_ key: String) {
        guard renderedFor != key else { return }
        renderedFor = key
        let r = ImageRenderer(content: HStack(spacing: gap) {
            content().fixedSize()
            content().fixedSize()
        }.foregroundStyle(ink))
        r.scale = displayScale
        bitmap = r.uiImage
    }
}

/// A UIView whose only layer shows the two-copy bitmap and slides it left by one copy + gap per pass.
private struct MarqueeLayerView: UIViewRepresentable {
    let image: UIImage?
    let scale: CGFloat
    let gap: CGFloat
    let secondsPerPass: Double
    let startedAt: Date
    let paused: Bool

    func makeUIView(context: Context) -> Strip {
        let v = Strip()
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        return v
    }

    func updateUIView(_ v: Strip, context: Context) {
        v.configure(image: image, scale: scale, gap: gap, secondsPerPass: secondsPerPass, startedAt: startedAt, paused: paused)
    }

    final class Strip: UIView {
        private var image: UIImage?
        private var gap: CGFloat = 0
        private var secondsPerPass: Double = 14
        private var startedAt = Date()
        private var paused = false
        private let key = "pulse.marquee"

        func configure(image: UIImage?, scale: CGFloat, gap: CGFloat, secondsPerPass: Double, startedAt: Date, paused: Bool) {
            let changed = self.image !== image || self.gap != gap || self.secondsPerPass != secondsPerPass
                || self.startedAt != startedAt || self.paused != paused
            self.image = image; self.gap = gap; self.secondsPerPass = secondsPerPass
            self.startedAt = startedAt; self.paused = paused
            layer.contents = image?.cgImage
            layer.contentsScale = scale
            if changed { restart() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { restart() }   // Core Animation drops animations of layers that left a window
        }

        private func restart() {
            layer.removeAnimation(forKey: key)
            guard !paused, let image, window != nil else { return }
            // One pass moves the strip left by one copy + the gap. The bitmap holds two copies and one gap.
            let run = (image.size.width + gap) / 2
            guard run > 1 else { return }
            let duration = max(secondsPerPass, 1)
            let a = CABasicAnimation(keyPath: "transform.translation.x")
            a.fromValue = 0
            a.toValue = -run
            a.duration = duration
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            // The same clock-driven phase as before: where the strip is depends only on time since `startedAt`.
            a.timeOffset = max(0, Date().timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: duration)
            a.isRemovedOnCompletion = false
            layer.add(a, forKey: key)
        }
    }
}

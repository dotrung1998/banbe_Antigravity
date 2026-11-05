import SwiftUI

/// Two-knob range over `minValue...maxValue` in whole `step`s. Each knob is its own adjustable accessibility element.
/// Extracted from `PriceRangeSlider` (Home's price filter) so the Map's time bar shares one implementation (note 79).
///
/// Two ways to move a knob:
/// - `nearestKnob == false` (price): each knob has its own drag, exactly as before.
/// - `nearestKnob == true` (time bar): one drag on the whole track moves the NEAREST knob, so both stay reachable even
///   one step apart (the knobs are wider than a step there).
/// `growsOnTouch` keeps the knobs small at rest and scales the touched one up (Reduce Motion: a thicker ring instead,
/// no scale). `showsBubble` draws the touched knob's value above it as an OVERLAY with a clamped `.position`, so a
/// wide label can never widen the slider (note 57 "jumps right").
struct RangeSlider: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let minValue: Int
    let maxValue: Int
    let step: Int
    let low: Int
    let high: Int
    /// Smallest allowed distance between the knobs (0 = they may meet).
    var minGap: Int = 0
    let label: (Int) -> String
    let lowName: String
    let highName: String
    var lowID: String? = nil
    var highID: String? = nil
    var nearestKnob = false
    var growsOnTouch = false
    var showsBubble = false
    var hapticOnStep = false
    var height: CGFloat = 30
    let onChange: (Int, Int) -> Void

    /// Layout width of one knob (positions and the end padding follow it).
    static let thumb: CGFloat = 26
    private var thumb: CGFloat { Self.thumb }
    private static let restScale: CGFloat = 0.72

    private enum Knob { case low, high }
    @State private var touched: Knob?
    @State private var dragging: Knob?

    private var span: Int { max(maxValue - minValue, 1) }

    private func quantised(_ px: CGFloat, width: CGFloat) -> Int {
        let frac = Double(min(max(px, 0), width) / max(width, 1))
        let raw = Double(minValue) + frac * Double(span)
        let snapped = minValue + Int(((raw - Double(minValue)) / Double(step)).rounded()) * step
        return min(maxValue, max(minValue, snapped))
    }

    private func setLow(_ v: Int) {
        let next = min(v, high - minGap)
        guard next != low else { return }
        if hapticOnStep { Haptics.selection() }
        onChange(next, high)
    }
    private func setHigh(_ v: Int) {
        let next = max(v, low + minGap)
        guard next != high else { return }
        if hapticOnStep { Haptics.selection() }
        onChange(low, next)
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - thumb, 1)
            let x: (Int) -> CGFloat = { v in CGFloat(v - minValue) / CGFloat(span) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(app.palette.ink.opacity(0.14)).frame(height: 4).padding(.horizontal, thumb / 2)
                Capsule().fill(app.palette.ink.opacity(0.85))
                    .frame(width: max(x(high) - x(low), 0), height: 4)
                    .offset(x: thumb / 2 + x(low))
                knobView(.low)
                    .offset(x: x(low))
                    .modifier(KnobDrag(enabled: !nearestKnob) { px in
                        touched = .low
                        setLow(quantised(px - thumb / 2, width: width))
                    } onEnd: { touched = nil })
                    .accessibilityElement()
                    .accessibilityLabel(lowName)
                    .accessibilityValue(label(low))
                    .accessibilityAdjustableAction { dir in
                        setLow(dir == .increment ? low + step : max(low - step, minValue))
                    }
                    .accessibilityIdentifier(lowID ?? "")
                knobView(.high)
                    .offset(x: x(high))
                    .modifier(KnobDrag(enabled: !nearestKnob) { px in
                        touched = .high
                        setHigh(quantised(px - thumb / 2, width: width))
                    } onEnd: { touched = nil })
                    .accessibilityElement()
                    .accessibilityLabel(highName)
                    .accessibilityValue(label(high))
                    .accessibilityAdjustableAction { dir in
                        setHigh(dir == .increment ? min(high + step, maxValue) : high - step)
                    }
                    .accessibilityIdentifier(highID ?? "")
            }
            .coordinateSpace(name: "rangeSlider")
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(nearestKnob ? DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { g in
                if dragging == nil {
                    let startX = g.startLocation.x - thumb / 2
                    let lowDist = abs(startX - x(low)), highDist = abs(startX - x(high))
                    // Equal (knobs together): the side the finger is on decides.
                    dragging = lowDist < highDist ? .low : highDist < lowDist ? .high : (startX > x(low) ? .high : .low)
                    touched = dragging
                }
                let v = quantised(g.location.x - thumb / 2, width: width)
                if dragging == .low { setLow(v) } else { setHigh(v) }
            }.onEnded { _ in dragging = nil; touched = nil } : nil)
            // The bubble: an overlay, so its width never changes the layout; its centre is clamped inside the slider.
            .overlay(alignment: .topLeading) {
                if showsBubble, let k = touched {
                    let v = k == .low ? low : high
                    let w: CGFloat = 52
                    Text(label(v))
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(app.palette.paper)
                        .frame(width: w, height: 24)
                        .background(app.palette.ink, in: Capsule())
                        .position(x: min(max(thumb / 2 + x(v), w / 2), geo.size.width - w / 2), y: -16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: height)
    }

    private func knobView(_ k: Knob) -> some View {
        let active = touched == k
        let grown = !growsOnTouch || active
        let ring = growsOnTouch && reduceMotion && active
        return Circle()
            .fill(app.palette.paper)
            .overlay(Circle().strokeBorder(app.palette.ink.opacity(0.85), lineWidth: ring ? 4 : 2))
            .frame(width: thumb, height: thumb)
            .scaleEffect(reduceMotion ? 1 : (grown ? 1 : Self.restScale))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -8))
    }
}

/// A per-knob drag (price): the finger's x in the slider's named space.
private struct KnobDrag: ViewModifier {
    let enabled: Bool
    let onMove: (CGFloat) -> Void
    let onEnd: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("rangeSlider"))
                .onChanged { onMove($0.location.x) }
                .onEnded { _ in onEnd() })
        } else {
            content
        }
    }
}

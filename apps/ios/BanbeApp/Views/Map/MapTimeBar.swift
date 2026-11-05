import SwiftUI

// Map E+ (note 79, plan step 7): the day menu + two-knob hour range at the bottom of the map. It only reports choices;
// the Map recomputes what is inside the window over the rows it already has, so a knob step never touches the network.
// "All days" turns the window off (the range then sits at MapDim.rangeOff and is inert). Web twin:
// src/components/map/MapTimeBar.jsx.
struct MapTimeBar: View {
    @EnvironmentObject private var app: AppState
    let win: MapTimeWindow.Window
    let options: [MapTimeWindow.DayOption]
    let dayLabel: String
    let onDay: (String) -> Void
    let onKnob: (MapTimeWindow.Knob, Int) -> Void

    private var currentKey: String { win.on ? win.key : "all" }

    var body: some View {
        HStack(spacing: 6) {
            dayMenu
            VStack(spacing: 0) {
                RangeSlider(minValue: MapTimeWindow.rangeMin, maxValue: MapTimeWindow.rangeMax, step: MapTimeWindow.rangeStep,
                            low: win.from, high: win.to, minGap: MapTimeWindow.rangeStep,
                            label: { MapTimeWindow.hourLabel($0) },
                            lowName: app.T("Từ giờ", "From"), highName: app.T("Đến giờ", "To"),
                            lowID: "map.time.from", highID: "map.time.to",
                            nearestKnob: true, growsOnTouch: true, showsBubble: true, hapticOnStep: true, height: 28) { lo, hi in
                    if lo != win.from { onKnob(.from, lo) } else if hi != win.to { onKnob(.to, hi) }
                }
                ticks
            }
            .padding(.leading, 6).padding(.trailing, 4)
            .opacity(win.on ? 1 : MapDim.rangeOff)
            .allowsHitTesting(win.on)
            .accessibilityHidden(!win.on)
            .animation(.easeOut(duration: 0.2), value: win.on)
        }
        .padding(.leading, 8).padding(.trailing, 14)
        .frame(height: MapStack.timeHeight)
        .nativeGlassCapsule(interactive: false)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Khung giờ", "Time window"))
        .accessibilityValue(win.on ? "\(dayLabel), \(MapTimeWindow.hourLabel(win.from)) – \(MapTimeWindow.hourLabel(win.to))" : dayLabel)
        .accessibilityIdentifier("map.timeBar")
    }

    private var dayMenu: some View {
        Menu {
            ForEach(options, id: \.key) { o in
                Button {
                    Haptics.selection()
                    onDay(o.key)
                } label: {
                    if o.key == currentKey {
                        Label(o.sub.isEmpty ? o.label : "\(o.label) · \(o.sub)", systemImage: "checkmark")
                    } else {
                        Text(o.sub.isEmpty ? o.label : "\(o.label) · \(o.sub)")
                    }
                }
                .accessibilityIdentifier("map.time.day.\(o.key)")
            }
        } label: {
            HStack(spacing: 7) {
                Text(dayLabel).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
            }
            .padding(.leading, 15).padding(.trailing, 12)
            .frame(height: 42)
            .foregroundStyle(app.palette.paper)
            .background(app.palette.ink, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .fixedSize()
        .accessibilityLabel(app.T("Chọn ngày", "Pick a day"))
        .accessibilityValue(dayLabel)
        .accessibilityIdentifier("map.time.day")
    }

    /// 10 · 14 · 18 · 22 · 02 under the track (three on a narrow bar: five labels would touch).
    private var ticks: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 170
            let marks = narrow ? [10, 18, 26] : [10, 14, 18, 22, 26]
            let inner = max(geo.size.width - RangeSlider.thumb, 1)
            ForEach(marks, id: \.self) { h in
                Text(MapTimeWindow.hourLabel(h))
                    .font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(app.palette.ink3)
                    .fixedSize()
                    .position(x: RangeSlider.thumb / 2 + CGFloat(h - MapTimeWindow.rangeMin) / CGFloat(MapTimeWindow.rangeMax - MapTimeWindow.rangeMin) * inner,
                              y: 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

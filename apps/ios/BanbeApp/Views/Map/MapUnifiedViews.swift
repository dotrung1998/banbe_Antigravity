import SwiftUI

// Note 99 (switch `unified_discovery`): the Map's time chip (one chip at the start of the chip row, replacing the 58 pt
// time bar) and the "− +" zoom capsule. Pure presentation; MapExploreView owns the window and the camera. The day
// choices and the hour range are the same as MapTimeBar's (dim, never hide). Web twin: the time chip + zoom buttons in
// src/screens/MapExplore.jsx.

/// The chip: clock, the current value ("Hôm nay · 19:00–02:00" or "Mọi ngày"), chevron.
struct MapTimeChip: View {
    @EnvironmentObject private var app: AppState
    let win: MapTimeWindow.Window
    let dayLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack(spacing: 6) {
                Image(systemName: win.on && win.key == "today" ? "moon.stars" : "clock")
                    .font(.app(.footnote)).accessibilityHidden(true)
                Text(MapTimeWindow.windowSummary(win, dayLabel: dayLabel, en: app.isEN))
                Image(systemName: "chevron.down").font(.app(size: 10, weight: .bold)).opacity(0.6).accessibilityHidden(true)
            }
            .font(.app(.subheadline).weight(win.on ? .semibold : .medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(win.on ? app.palette.paper : app.palette.ink)
            .modifier(MapChipBackground(active: win.on, ink: app.palette.ink))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.T("Thời gian", "Time"))
        .accessibilityValue(MapTimeWindow.windowSummary(win, dayLabel: dayLabel, en: app.isEN))
        .accessibilityHint(app.T("Đổi ngày và khung giờ", "Change the day and hours"))
        .accessibilityAddTraits(win.on ? .isSelected : [])
        .accessibilityIdentifier("map.timeChip")
    }
}

/// The chip's pop-over: the same day choices as the time bar's menu, then the same two-knob hour range.
struct MapTimePopover: View {
    @EnvironmentObject private var app: AppState
    let win: MapTimeWindow.Window
    let options: [MapTimeWindow.DayOption]
    let onDay: (String) -> Void
    let onKnob: (MapTimeWindow.Knob, Int) -> Void

    private var currentKey: String { win.on ? win.key : "all" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.key) { o in
                Button {
                    Haptics.selection()
                    onDay(o.key)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark").font(.app(size: 13, weight: .bold))
                            .opacity(o.key == currentKey ? 1 : 0).frame(width: 16).accessibilityHidden(true)
                        Text(o.label).font(.app(size: 15, weight: o.key == currentKey ? .semibold : .regular))
                        Spacer(minLength: 8)
                        Text(o.sub).font(.app(size: 13)).foregroundStyle(app.palette.ink2)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(o.key == currentKey ? .isSelected : [])
                .accessibilityIdentifier("map.time.day.\(o.key)")
            }
            Rectangle().fill(app.palette.rule).frame(height: 1).padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(win.on ? "\(MapTimeWindow.hourLabel(win.from)) – \(MapTimeWindow.hourLabel(win.to))"
                            : app.T("Chọn một ngày để đặt giờ", "Pick a day to set the hours"))
                    .font(.app(size: 13, weight: .semibold)).monospacedDigit()
                RangeSlider(minValue: MapTimeWindow.rangeMin, maxValue: MapTimeWindow.rangeMax, step: MapTimeWindow.rangeStep,
                            low: win.from, high: win.to, minGap: MapTimeWindow.rangeStep,
                            label: { MapTimeWindow.hourLabel($0) },
                            lowName: app.T("Từ giờ", "From"), highName: app.T("Đến giờ", "To"),
                            lowID: "map.time.from", highID: "map.time.to",
                            nearestKnob: true, growsOnTouch: true, showsBubble: true, hapticOnStep: true, height: 28) { lo, hi in
                    if lo != win.from { onKnob(.from, lo) } else if hi != win.to { onKnob(.to, hi) }
                }
                .opacity(win.on ? 1 : MapDim.rangeOff)
                .allowsHitTesting(win.on)
                .accessibilityHidden(!win.on)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        .padding(.top, 8)
        .frame(width: 300)
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.timePopover")
    }
}

/// "− +": one glass capsule, 44 pt targets. − is disabled at the widest zoom.
struct MapZoomCapsule: View {
    @EnvironmentObject private var app: AppState
    let canZoomOut: Bool
    let canZoomIn: Bool
    let onZoom: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: app.T("Thu nhỏ", "Zoom out"), id: "map.zoom.out", enabled: canZoomOut) { onZoom(-1) }
            Rectangle().fill(app.palette.rule).frame(width: 1, height: 22).accessibilityHidden(true)
            button("plus", label: app.T("Phóng to", "Zoom in"), id: "map.zoom.in", enabled: canZoomIn) { onZoom(1) }
        }
        .mapSurfaceCapsule(interactive: true)
        .accessibilityElement(children: .contain)
    }

    private func button(_ system: String, label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: system).font(.app(size: 15, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(app.palette.ink)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

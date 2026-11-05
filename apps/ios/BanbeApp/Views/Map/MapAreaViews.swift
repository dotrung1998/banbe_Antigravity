import SwiftUI
import MapKit
import CoreLocation

// Map E+ (note 79, plan step 6): the neighbourhood level. Web twins: the area bubble / chips / panel in
// src/screens/MapExplore.jsx. Pure presentation; MapExploreView owns the state and the camera.

/// The bottom stack above the dock, in points. Same constants as the web (`CHIPS_BOTTOM` ... `STACK_H`), bottom to top:
/// neighbourhood chips, the time bar's slot (step 7; reserved and empty for now), then the buttons row. The room for the
/// WHOLE stack is always reserved so the reference rect never depends on zoom level, an open panel or the list.
enum MapStack {
    static let chipsBottom: CGFloat = 12
    static let chipsHeight: CGFloat = 84
    static let timeHeight: CGFloat = 58
    static let gap: CGFloat = 8
    static let buttonHeight: CGFloat = 44
    static let timeBottom: CGFloat = chipsBottom + chipsHeight + gap
    static let fabBottom: CGFloat = timeBottom + timeHeight + 10
    /// From the dock's top edge to the top of the buttons row (+ 4).
    static let height: CGFloat = fabBottom + buttonHeight + 4
    /// Gap between the shared controls and the free map band / the list.
    static let controlsGap: CGFloat = 8
    /// Room the floating dock occupies at the bottom (its window always draws over the app).
    static var dockClear: CGFloat { BottomTabBar.contentClearance }
    /// Dock + stack: what the reference rect leaves out at the bottom (the attribution reserve is added by the caller).
    static var reserved: CGFloat { dockClear + height }
}

/// The open neighbourhood: the area keys it lists (a stack tap may span several) and the label it shows.
struct MapAreaPanelState: Equatable {
    var keys: [String]
    var label: String?
}

/// One annotation on the map: a city / pin / cluster / stack group, or a neighbourhood bubble.
enum MapMarker: Identifiable {
    case group(MapDiscovery.Group)
    case area(MapDiscovery.AreaGroup)

    var id: String {
        switch self {
        case .group(let g): return g.id
        case .area(let a): return "area:" + a.id
        }
    }
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .group(let g): return CLLocationCoordinate2D(latitude: g.lat, longitude: g.lng)
        case .area(let a): return CLLocationCoordinate2D(latitude: a.lat, longitude: a.lng)
        }
    }
}

/// The bottom edge (screen coordinates) of the shared controls. The list's top and the reference rect follow it.
struct MapControlsBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A chip over the map: glass at rest, ink when on.
struct MapChipBackground: ViewModifier {
    let active: Bool
    let ink: Color
    func body(content: Content) -> some View {
        if active {
            content.background(ink, in: Capsule())
        } else {
            content.nativeGlassCapsule(interactive: false)
        }
    }
}

/// Neighbourhood bubble: the count in an ink pill, the area's name under it. Several keys = bubbles that overlap at this
/// zoom, merged ("N areas"); a tap zooms in instead of opening a panel.
struct MapAreaBubble: View {
    /// Passed in, not an environment object: a MapKit annotation's content does not inherit the environment.
    let app: AppState
    let group: MapDiscovery.AreaGroup
    let onTap: () -> Void

    private var single: Bool { group.keys.count == 1 }
    private var name: String {
        single ? ((group.labels.first ?? nil) ?? app.T("Khu khác", "Other areas"))
               : app.T("\(group.keys.count) khu", "\(group.keys.count) areas")
    }

    var body: some View {
        let n = group.ids.count
        VStack(spacing: 2) {
            Text("\(n)")
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(minWidth: 52, minHeight: 52)
                .foregroundStyle(app.palette.paper)
                .background(app.palette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .frame(maxWidth: 132)
                .foregroundStyle(app.palette.ink)
                .background(app.palette.paper, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(single ? app.T("\(name), \(n) sự kiện, mở khu này", "\(name), \(n) event\(n == 1 ? "" : "s"), open this area")
                                   : app.T("\(name), \(n) sự kiện, phóng to", "\(name), \(n) event\(n == 1 ? "" : "s"), zoom in"))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue("\(n)")
        .accessibilityIdentifier("map.areaBubble.\(group.keys.joined(separator: "+"))")
        .onTapGesture(perform: onTap)
    }
}

/// A neighbourhood chip in the row above the buttons: name, event count, the categories present as line icons.
struct MapAreaChip: View {
    @EnvironmentObject private var app: AppState
    let name: String
    let count: Int
    let cats: [String]
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(app.T("\(count) sự kiện", count == 1 ? "1 event" : "\(count) events"))
                    .font(.system(size: 12)).foregroundStyle(app.palette.ink2).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(Array(cats.prefix(5)), id: \.self) { c in
                        Image(systemName: CategoryGlyph.symbol(c)).font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundStyle(app.palette.ink2)
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minWidth: 108, maxWidth: 190, alignment: .leading)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("\(name), \(count) sự kiện, mở khu này", "\(name), \(count) event\(count == 1 ? "" : "s"), open this area"))
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.areaChip.\(key)")
    }
}

/// The neighbourhood panel: its events over the lower ~46 % of the screen, not draggable. The title carries the count
/// ("Quận 1 · 3"), "All areas" goes back. The accessibility escape gesture closes it like the back button.
struct MapAreaPanelView<Rows: View>: View {
    @EnvironmentObject private var app: AppState
    let title: String
    let count: Int
    let height: CGFloat
    /// Scrolls this row id to the top once (a stack tap).
    let scrollTo: String?
    let backTitle: String
    let emptyText: String
    let onBack: () -> Void
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("\(title) · \(count)")
                    .font(BanbeTheme.display(22))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityValue("\(count)")
                    .accessibilityIdentifier("map.areaPanel.title")
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                        Text(backTitle).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .background(app.palette.surface2, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.areaPanel.back")
            }
            .padding(.horizontal, 16).padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if count == 0 {
                            Text(emptyText)
                                .font(.subheadline).foregroundStyle(app.palette.ink2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                        rows()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24 + 34)
                }
                .task(id: scrollTo) {
                    guard let scrollTo else { return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    proxy.scrollTo(scrollTo, anchor: .top)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Sự kiện trong khu này", "Events in this area"))
        .accessibilityAction(.escape, onBack)
        .accessibilityIdentifier("map.areaPanel")
    }
}

import SwiftUI

// Map E+ (note 79, plan step 6): the shared controls over the map AND over the list. The search row itself is the
// persistent search bar (Views/PersistentSearchBar.swift, hosted in RootView): this keeps its 44pt of room, then the
// chip row the Map passes in. Their measured bottom edge is the list's top and the reference rect's top. Web twin:
// the `map-top` block in src/screens/MapExplore.jsx.
struct MapTopControls<Chips: View>: View {
    @EnvironmentObject private var app: AppState
    @ViewBuilder let chips: () -> Chips

    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: 44).allowsHitTesting(false)
            chips().opacity(app.searchBarAtHome ? 0 : 1)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 8)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: MapControlsBottomKey.self, value: proxy.frame(in: .global).maxY)
        })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.top")
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

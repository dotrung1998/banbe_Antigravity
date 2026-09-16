import SwiftUI
import MapKit
import CoreLocation

/// Map + list explore screen (.claude/notes/11-realtime-map.md). Full-screen
/// native MapKit behind a native `.sheet` bottom sheet (`.presentationDetents`
/// gives drag-to-resize/snap for free on iOS 17+, this project's deployment
/// target) — no custom gesture code needed here, unlike the web build of the
/// same screen.
struct MapExploreView: View {
    @EnvironmentObject var app: AppState
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var lastQueriedRegion: MKCoordinateRegion?
    @State private var boundsChanged = false
    @State private var catFilter = "all"
    @State private var openNowOnly = false
    @State private var sortByDistance = false
    @State private var initialCenterSet = false
    // Defaults to the "tall" snap point (covers most of the screen, leaving
    // a small map strip visible at top) per the ticket's layout spec — not
    // the smallest detent, and not a binary toggle: `.presentationDetents`
    // gives all three snap points (tall/mid/peek) standard drag-to-resize
    // behavior for free.
    @State private var sheetDetent: PresentationDetent = .fraction(0.72)
    @State private var awaitingRecenterAfterGrant = false

    // The pin/list-row currently showing the compact in-map preview card —
    // nil when nothing is selected. Not a second data source: just an id
    // into the same `visibleEvents` this screen already loads/filters.
    @State private var selectedId: String?
    // Non-nil only for the brief overshoot phase of the selection "pop" —
    // see `selectEvent(_:)`.
    @State private var poppingId: String?

    private let categories: [(key: String, vi: String, en: String, glyph: String)] = [
        ("all", "Tất cả", "All", "▪︎"),
        ("supper", "Supper club", "Supper club", "🍽️"),
        ("fashion", "Thời trang", "Fashion", "👗"),
        ("gallery", "Phòng tranh", "Gallery", "🖼️"),
        ("music", "Nhạc", "Music", "🎵"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                ForEach(visibleEvents) { ev in
                    Annotation(ev.name, coordinate: CLLocationCoordinate2D(latitude: ev.lat ?? 0, longitude: ev.lng ?? 0)) {
                        pin(for: ev)
                    }
                }
            }
            .mapControls { }
            .onMapCameraChange { context in
                if lastQueriedRegion == nil { lastQueriedRegion = context.region; return }
                boundsChanged = true
            }
            // A tap that lands on the map background (a pin's own
            // `.onTapGesture` in `pin(for:)` claims taps on the pin itself
            // first) clears the selected-event card. This is a plain tap
            // gesture layered alongside Map's own built-in pan/pinch/rotate
            // recognizers, not a replacement for them — both coexist the
            // same way this pattern already does for MapKit elsewhere.
            .onTapGesture { selectedId = nil }
            .ignoresSafeArea()

            HStack {
                Button { app.goBack() } label: {
                    Text(app.T("← Đóng", "← Close"))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .accessibilityIdentifier("map.back")

                Spacer()

                Button(action: tapCompass) {
                    Text("🧭")
                        .font(.system(size: 17))
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                        .opacity(compassOpacity)
                }
                .accessibilityIdentifier("map.compass")
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Deliberately NOT a third child of the HStack above. It used to
            // sit between two Spacers there ([Close] Spacer [SearchHere]
            // Spacer [Compass]), which centers it in the space left over
            // AFTER Close/Compass's own widths — not the screen's true
            // center. Close ("← Đóng"/"← Close", a text button) and Compass
            // (a fixed 38pt circle) are different widths, so that leftover
            // space was never symmetric, and the button sat visibly off
            // toward whichever side had the narrower neighbor. Placing it
            // as this ZStack's own top-level child instead means it's
            // centered by the ZStack's own `alignment: .top` (center-x,
            // top-y) against the full screen width, independent of the
            // other buttons' widths, safe-area insets, or sheet state — no
            // hardcoded offset needed.
            if boundsChanged {
                Button(action: searchHere) {
                    Text(app.T("Tìm ở đây", "Search here"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .accessibilityIdentifier("map.searchHere")
                .foregroundStyle(app.palette.ink)
                .padding(.top, 8)
            }

            // Compact in-map preview — never a full-screen modal. Anchored
            // just above the sheet's OWN current fraction (sheetFraction,
            // derived from sheetDetent below), so it automatically sits in
            // a sensible spot at every detent: near the top third in the
            // tall/0.72 detent (well clear of the sheet's own filter/list
            // controls), and a thin strip just above the small 0.12 peek
            // detent (without covering the map) — one rule, not two
            // special-cased layouts.
            if let ev = selectedEvent {
                VStack {
                    Spacer()
                    selectedCard(ev)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, UIScreen.main.bounds.height * sheetFraction)
            }
        }
        .onChange(of: visibleEvents.map(\.id)) { _, ids in
            // The selected event must honor every active filter this
            // screen has, exactly like the pins/list it was picked from —
            // if a poll refresh or a filter change makes it fall out of
            // `visibleEvents` (cancelled, sold out and filtered by "Còn
            // chỗ", recategorized, or just no longer in the current bbox),
            // the selection clears itself instead of the card going stale.
            // No second query: this only ever reads the same
            // `visibleEvents` the map/list already render.
            if let id = selectedId, !ids.contains(id) { selectedId = nil }
        }
        .sheet(isPresented: .constant(true)) {
            sheetContent
                .presentationDetents([.fraction(0.12), .fraction(0.45), .fraction(0.72)], selection: $sheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
        }
        .task {
            await app.loadMapEvents()
            centerOnDensityHotspot()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            Task { await app.loadMapEvents(bounds: lastQueriedRegion.map(boundsOf)) }
        }
        .onChange(of: app.userCoords) { _, newValue in
            // Only recenters when the compass button itself triggered the
            // permission grant (below) — a background coords refresh must
            // never move the map on its own; the compass is the only way
            // this screen ever centers on the user.
            guard awaitingRecenterAfterGrant, newValue != nil else { return }
            awaitingRecenterAfterGrant = false
            recenterOnUser()
        }
    }

    // MARK: - Density-hotspot initial center

    /// Never the user's own GPS position on first load — centers on wherever
    /// events are actually clustered instead (grid-binning, same algorithm
    /// as src/lib/densityHotspot.js — see .claude/notes/11-realtime-map.md).
    private func centerOnDensityHotspot() {
        guard !initialCenterSet else { return }
        initialCenterSet = true
        let points = app.mapEvents.compactMap { ev -> CLLocationCoordinate2D? in
            guard let lat = ev.lat, let lng = ev.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        let center = densityHotspot(points) ?? CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
        cameraPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
    }

    // MARK: - Pin/list selection: camera zoom + compact in-map preview card

    private var selectedEvent: MapEventRow? {
        guard let selectedId else { return nil }
        return visibleEvents.first { $0.id == selectedId }
    }

    /// How much of the screen the bottom sheet currently covers, read back
    /// from `sheetDetent` (a `PresentationDetent` doesn't expose its own
    /// fraction, but it IS `Equatable`, so comparing against the same three
    /// literal fractions `sheetContent` declares works directly).
    private var sheetFraction: Double {
        if sheetDetent == .fraction(0.12) { return 0.12 }
        if sheetDetent == .fraction(0.45) { return 0.45 }
        return 0.72
    }

    /// Reuses the same `visibleEvents` this screen already loads/filters —
    /// selecting is just remembering an id, never a second query. Zooms
    /// the camera toward the event with a sensible offset so the pin
    /// doesn't end up hidden under the sheet or the preview card that's
    /// about to appear just above it (there's no pixel-padding primitive
    /// on SwiftUI's `Map` the way MapLibre GL's `flyTo({padding})` has on
    /// web, so this approximates it by shifting the target region's center
    /// toward the visible strip above the sheet, not the screen's raw
    /// geometric center).
    private func selectEvent(_ ev: MapEventRow) {
        guard let lat = ev.lat, let lng = ev.lng else { return }
        let isNewSelection = selectedId != ev.id
        selectedId = ev.id

        let zoomSpan = 0.01
        let visibleFraction = 1 - sheetFraction
        // Aim for roughly the upper third of the visible (non-sheet) strip
        // rather than its exact middle, leaving room for the preview card
        // that sits just above the sheet.
        let desiredScreenFraction = visibleFraction * 0.38
        let latShift = zoomSpan * (0.5 - desiredScreenFraction)
        withAnimation(.easeInOut(duration: 0.55)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat - latShift, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: zoomSpan, longitudeDelta: zoomSpan)
            ))
        }

        guard isNewSelection else { return }
        // A brief overshoot-then-settle "pop", same easing convention this
        // app already uses for its entrance animations — plays once per
        // actual selection change only (guarded by `isNewSelection` above),
        // never replayed by a poll refresh while the same pin stays
        // selected.
        withAnimation(.easeOut(duration: 0.16)) { poppingId = ev.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.2)) { poppingId = nil }
        }
    }

    @ViewBuilder
    private func selectedCard(_ ev: MapEventRow) -> some View {
        let cosmetic = EventCatalog.find(ev.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                if let path = cosmetic?.img {
                    CatalogPhoto(path: path, height: 64, width: 64, cornerRadius: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top) {
                        Text(ev.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Spacer()
                        Button { selectedId = nil } label: {
                            Text("×").font(.system(size: 18)).foregroundStyle(app.palette.ink.opacity(0.5))
                        }
                        .accessibilityIdentifier("map.card.close")
                    }
                    Text([cosmetic?.when, ev.area].compactMap { $0 }.joined(separator: " ▪︎ "))
                        .font(.system(size: 11)).opacity(0.65).lineLimit(1)
                    HStack {
                        if let price = cosmetic?.price {
                            Text(price).font(.system(size: 13, weight: .semibold))
                        }
                        Spacer()
                        Text(isSoldOut(ev) ? app.T("Hết chỗ", "Sold out") : app.T("Còn chỗ", "Available"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSoldOut(ev) ? BanbeTheme.alert : app.palette.ink)
                    }
                }
            }
            Button(action: { app.goEvent(ev.id) }) {
                Text(app.T("Xem chi tiết", "View details"))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(app.palette.paper)
            }
            .accessibilityIdentifier("map.card.cta")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("map.selectedCard")
    }

    /// Live `seats_remaining` is this screen's own established
    /// "real-time-ish" signal (already used for the low-seats pin dot) —
    /// reused for sold-out too, falling back to the static catalogue's
    /// flag only when a row has no seats_remaining of its own to check.
    private func isSoldOut(_ ev: MapEventRow) -> Bool {
        if let seats = ev.seatsRemaining { return seats <= 0 }
        return EventCatalog.find(ev.id)?.soldOut ?? false
    }

    // MARK: - Compass button (granted / denied / permanently-denied)

    /// Same 0.16 disabled-button opacity token this app already uses
    /// elsewhere (Components.swift's InkButton) — never a new value.
    private var compassOpacity: Double {
        app.locationAuthStatus == .authorizedWhenInUse || app.locationAuthStatus == .authorizedAlways ? 1 : 0.16
    }

    /// Tapping the dimmed compass button always re-prompts rather than
    /// silently failing: `.notDetermined` shows the OS dialog; a real
    /// "permanently denied" (user said no already, so CoreLocation will
    /// never show that dialog again) deep-links to Settings instead, per
    /// CLLocationManager's own permanently-denied semantics.
    private func tapCompass() {
        if app.locationAuthStatus == .authorizedWhenInUse || app.locationAuthStatus == .authorizedAlways {
            recenterOnUser()
        } else if isPermanentlyDenied {
            LocationService.openSettings()
        } else {
            awaitingRecenterAfterGrant = true
            app.allowLocation() // triggers the OS permission dialog via LocationService.request()
        }
    }

    private var isPermanentlyDenied: Bool {
        app.locationAuthStatus == .denied || app.locationAuthStatus == .restricted
    }

    private func recenterOnUser() {
        guard let coords = app.userCoords else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        ))
    }

    // MARK: - Search here (bbox re-query, tap only — never on every pan/zoom)

    private func searchHere() {
        guard let region = lastQueriedRegion else { return }
        boundsChanged = false
        Task { await app.loadMapEvents(bounds: boundsOf(region)) }
    }

    private func boundsOf(_ region: MKCoordinateRegion) -> (south: Double, north: Double, west: Double, east: Double) {
        let south = region.center.latitude - region.span.latitudeDelta / 2
        let north = region.center.latitude + region.span.latitudeDelta / 2
        let west = region.center.longitude - region.span.longitudeDelta / 2
        let east = region.center.longitude + region.span.longitudeDelta / 2
        return (south, north, west, east)
    }

    // MARK: - Pins

    @ViewBuilder
    private func pin(for ev: MapEventRow) -> some View {
        let isSelected = ev.id == selectedId
        let isPopping = ev.id == poppingId
        ZStack(alignment: .topTrailing) {
            Text(categories.first { $0.key == ev.catKey }?.glyph ?? "▪︎")
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(app.palette.paper, in: Circle())
                .overlay(Circle().stroke(app.palette.ink, lineWidth: isSelected ? 2.5 : 1.5))
                .shadow(radius: isSelected ? 5 : 3)
            if let seats = ev.seatsRemaining, seats <= 5 {
                Circle().fill(Color(red: 0.6, green: 0.24, blue: 0.18)).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 1.5))
            }
        }
        // Selected pin sits slightly larger and settles there; the brief
        // overshoot past that (isPopping) plays once per actual selection
        // change, guarded in selectEvent(_:) — never replayed by a poll
        // refresh while the same pin stays selected.
        .scaleEffect(isPopping ? 1.32 : (isSelected ? 1.15 : 1))
        .zIndex(isSelected ? 1 : 0)
        .accessibilityIdentifier("map.pin.\(ev.id)")
        .onTapGesture { selectEvent(ev) }
    }

    // MARK: - List

    private var visibleEvents: [MapEventRow] {
        var list = app.mapEvents.filter { $0.lat != nil && $0.lng != nil }
        if catFilter != "all" { list = list.filter { $0.catKey == catFilter } }
        if openNowOnly { list = list.filter { ($0.seatsRemaining ?? 0) > 0 } }
        if sortByDistance, let coords = app.userCoords {
            list.sort { distanceKm(coords, $0) ?? .greatestFiniteMagnitude < distanceKm(coords, $1) ?? .greatestFiniteMagnitude }
        }
        return list
    }

    private func distanceKm(_ from: Coordinates, _ ev: MapEventRow) -> Double? {
        guard let lat = ev.lat, let lng = ev.lng else { return nil }
        let dLat = (lat - from.lat) * .pi / 180
        let dLng = (lng - from.lng) * .pi / 180
        let lat1 = from.lat * .pi / 180
        let lat2 = lat * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.key) { cat in
                        Text("\(cat.glyph) \(app.T(cat.vi, cat.en))")
                            .font(.system(size: 12, weight: catFilter == cat.key ? .bold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .onTapGesture { catFilter = cat.key }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)

            HStack(spacing: 8) {
                Text(app.T("Còn chỗ", "Open now"))
                    .font(.system(size: 11, weight: openNowOnly ? .bold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .onTapGesture { openNowOnly.toggle() }
                if app.locationAuthStatus == .authorizedWhenInUse || app.locationAuthStatus == .authorizedAlways {
                    Text(app.T("Gần bạn", "Nearby"))
                        .font(.system(size: 11, weight: sortByDistance ? .bold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                        .onTapGesture { sortByDistance.toggle() }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List(visibleEvents) { ev in
                HStack(spacing: 12) {
                    // Same left-side thumbnail every other event card in
                    // this app uses (CatalogPhoto -> RemoteImage ->
                    // PhotoLoader) — was missing here entirely (bug 1,
                    // 11-realtime-map.md). The map screen's own rows only
                    // carry the live DB columns (no `img`), so the cosmetic
                    // photo path is joined back from the bundled catalogue
                    // by id, same as the price/img join the web build does
                    // in MapExplore.jsx's fetchLiveEvents().
                    if let path = EventCatalog.find(ev.id)?.img {
                        CatalogPhoto(path: path, height: 52, width: 52, cornerRadius: 10)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.name).font(.system(size: 14, weight: .semibold))
                        Text(ev.area + (sortByDistance ? distanceSuffix(ev) : ""))
                            .font(.system(size: 11)).opacity(0.6)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selectEvent(ev) }
                .onAppear {
                    if ev.id == visibleEvents.last?.id { Task { await app.loadMapEvents(bounds: lastQueriedRegion.map(boundsOf)) } }
                }
            }
            .listStyle(.plain)
        }
        .foregroundStyle(app.palette.ink)
    }

    private func distanceSuffix(_ ev: MapEventRow) -> String {
        guard let coords = app.userCoords, let km = distanceKm(coords, ev) else { return "" }
        return String(format: " ▪︎ %.1f km", km)
    }
}

/// Same grid-binning approach as src/lib/densityHotspot.js: round each
/// event's lat/lng to a coarse grid cell, count events per cell, return the
/// densest cell's own centroid (mean position of its actual members).
func densityHotspot(_ points: [CLLocationCoordinate2D], cellDegrees: Double = 0.02) -> CLLocationCoordinate2D? {
    guard !points.isEmpty else { return nil }
    struct Bin { var sumLat = 0.0; var sumLng = 0.0; var count = 0 }
    var bins: [String: Bin] = [:]
    for p in points {
        let key = "\(Int((p.latitude / cellDegrees).rounded())):\(Int((p.longitude / cellDegrees).rounded()))"
        var bin = bins[key] ?? Bin()
        bin.sumLat += p.latitude
        bin.sumLng += p.longitude
        bin.count += 1
        bins[key] = bin
    }
    guard let best = bins.values.max(by: { $0.count < $1.count }) else { return nil }
    return CLLocationCoordinate2D(latitude: best.sumLat / Double(best.count), longitude: best.sumLng / Double(best.count))
}

import SwiftUI
import Combine
import MapKit
import CoreLocation

/// Task 2a (11-realtime-map.md follow-up): a minimal left-to-right,
/// top-to-bottom wrapping layout — the category filter row no longer
/// requires horizontal scrolling to discover every option; every chip is
/// visible up front, wrapping onto as many rows as needed. `Layout` was
/// introduced in iOS 16, well within this project's iOS 17 deployment
/// target (`project.yml:4-5`), so no third-party dependency was pulled in
/// for what's otherwise a well-known, small amount of layout math.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + lineSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? lineWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Map explore screen, Map E+ layout (note 79, plan step 6; web twin src/screens/MapExplore.jsx). A full-screen native
/// MapKit map with the shared controls (back, search, filters, chips) over it, the bottom stack above the dock
/// (neighbourhood chips, then my location + "List · N"), a neighbourhood panel and a list layer. The old system
/// `.sheet` with three detents is gone (a custom drag on it failed on a real device, note 06).
struct MapExploreView: View {
    @EnvironmentObject var app: AppState
    @State private var cameraPosition: MapCameraPosition
    /// Map redesign phase 2: the committed search area (Lib/MapDiscovery.swift). It changes only when the camera settles
    /// after geographic navigation, never because the list or the panel opened, a highlight was revealed or data refreshed.
    @State private var committedBounds: MapDiscovery.Bounds?
    /// Reason of the camera move in progress; none at settle time means the user moved the map.
    @State private var pendingReason: (reason: MapDiscovery.Reason, at: Date)?
    @State private var settleTask: Task<Void, Never>?
    /// True once this screen has framed (or restored) its camera; MapKit's earlier callbacks can report a bogus region
    /// (seen over Europe before the first centring, 1a33c4b) and must never become the area.
    @State private var framed: Bool
    /// The map's full size and the top safe area (the Map ignores the safe area), for the reference rect.
    @State private var mapSize: CGSize = .zero
    @State private var safeTop: CGFloat = 0
    /// Bottom edge of the shared controls in screen coordinates (0 until measured): the list's top and the reference
    /// rect's top inset follow it (a Dynamic Type change moves it).
    @State private var controlsBottom: CGFloat = 0
    /// The whole public set again every 60 s (was 5 s: every row re-downloaded a dozen times a minute, Supabase
    /// egress, note 40). Kept in @State so it is made once per screen (built inline, every redraw restarted it).
    @State private var pollTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// Map redesign phase 3: ONE filter object in Home's shape (date, cats, seatsLeft, price, free, almostFull,
    /// typeFilters), judged by the same `HomeDiscovery.apply` Home uses, each event in its own venue time zone.
    /// Seeded from a return snapshot, else Home's hand-off, else nothing. Moving the map never changes it.
    @State private var filters: HomeDiscovery.Filters
    @State private var filterSheetOpen = false
    /// "area" while the map is framed on the picked area (destination), else "map" ("Vùng bản đồ / Map area").
    @State private var areaContext: String
    @State private var framedByArea = false
    /// The category row is single-choice.
    private var catFilter: String {
        get { filters.cats.first ?? "all" }
        nonmutating set { filters.cats = newValue == "all" ? [] : [newValue]; filters.typeFilters = [] }
    }
    private var openNowOnly: Bool {
        get { filters.seatsLeft }
        nonmutating set { filters.seatsLeft = newValue }
    }
    @State private var sortByDistance: Bool
    // Home quick event search (2026-09-27): see `visibleEvents`'s own doc comment. `startFocusedOnSearch` is read once,
    // at construction (mirrors `hadRestoredState`'s own one-shot capture), so a later unrelated re-render can't
    // re-focus the field out from under the user.
    @State private var searchQuery: String
    // For You (34/35 notes): local to Map, never touches Home's `app.filterForYou`.
    // Matching is `app.mapForYouMatches` (same ForYou.rank + same area rule as Home).
    @State private var forYouOn: Bool
    @StateObject private var forYouAlert = ForYouAlertModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Location hierarchy (migration 112): Map's own presentation of the shared location picker (selection itself is
    // `app.area`, shared with Home).
    @State private var locationPickerOpen = false
    // Map search-focus fix (2026-09-28, fifth pass): plain `@State`, not `@FocusState`. See `FocusableTextField`'s own
    // doc comment (Components.swift) for the confirmed reason: `@FocusState` cannot deliver programmatic focus to this
    // field on a real device, while `FocusableTextField`'s direct `becomeFirstResponder()` can.
    @State private var searchFieldFocused = false
    private let startFocusedOnSearch: Bool
    /// Note 50: Search's "See on map": the query a fresh open starts with (one-shot, like the focus intent).
    private let seedQuery: String?
    @State private var awaitingRecenterAfterGrant = false

    /// Map E+ (note 79): only a highlight now (restored from Event Detail, "Open in Map"). A pin opens Event Detail
    /// directly; there is no selection card.
    @State private var selectedId: String?
    /// Captured once at construction time so `.task` knows whether to skip density-hotspot centering.
    private let hadRestoredState: Bool
    /// Edge-swipe race: true only for the non-interactive "peeked at" copy RootView renders underneath an in-progress
    /// edge swipe, never for the real instance. Skips every side effect (loading, clearing the snapshot, polling,
    /// centering).
    private let isPreview: Bool
    /// False while this instance is only the tab-swipe neighbour (RootView's `rootScreensToRender`): it must not hide
    /// the dock yet.
    private let isActive: Bool
    /// Unique per instance, so a torn-down copy never releases the dock another instance hid.
    @State private var dockToken = "mapExplore.dock." + UUID().uuidString
    /// Last camera settle; a camera change right after one is MapKit finishing that move, not the user's.
    @State private var lastSettleAt = Date.distantPast
    /// City and neighbourhood of each loaded event (cities.json, `areaKey`), recomputed only when the loaded rows change.
    @State private var cityOfEvent: [String: String] = [:]
    @State private var areaOfEvent: [String: MapDiscovery.AreaKey] = [:]
    /// The city the map was flown to (search or area picker), while it is still the framed destination.
    @State private var cityContextID: String?
    /// Map v6: recent searches (UserDefaults `banbe.map.recentSearches.v1`, max 5), shown before typing.
    @State private var recentSearches: [String] = MapRecentSearches.load()
    /// The ACTUAL current camera, updated on every settle, so a snapshot saves where the map really is.
    @State private var currentCameraRegion: MKCoordinateRegion?

    // Map E+ (note 79): the list layer and the neighbourhood panel.
    /// The list is a layer over the full-screen map. `listMounted` outlives `listOpen` by the closing slide so the rows
    /// do not vanish under it; rows exist only while it is open (no photo loads for a closed list).
    @State private var listOpen: Bool
    @State private var listMounted: Bool
    /// The list's scroll offset, kept across closes (reset when the area changes).
    @State private var listOffset: CGFloat
    @State private var listUnmountTask: Task<Void, Never>?
    /// The open neighbourhood and the view it was opened from (the panel's back button returns there).
    @State private var areaPanel: MapAreaPanelState?
    @State private var preAreaRegion: MKCoordinateRegion?
    /// Zooming out closes the panel, but not while its own opening flight is still in progress.
    @State private var areaOpenedAt = Date.distantPast
    @State private var areaScrollTo: String?
    /// False once a confirmed close (button or edge swipe) starts: the layers fade while RootView navigates.
    @State private var uiPresented = true

    /// Seeds every local `@State` directly from a saved snapshot (or plain defaults) INSIDE `init`, rather than
    /// restoring them a moment later inside `.task`: `.task` runs after the very first frame, so a return to the map
    /// used to flash the default camera / filters for one frame before snapping to the restored ones.
    init(restored: MapExploreState?, isPreview: Bool = false, startFocusedOnSearch: Bool = false, isActive: Bool = true, seedQuery: String? = nil, entry: (filters: HomeDiscovery.Filters, forYou: Bool)? = nil) {
        hadRestoredState = restored != nil
        self.seedQuery = seedQuery
        self.isPreview = isPreview
        self.isActive = isActive
        self.startFocusedOnSearch = startFocusedOnSearch
        _listOpen = State(initialValue: restored?.listOpen ?? false)
        _listMounted = State(initialValue: restored?.listOpen ?? false)
        _listOffset = State(initialValue: CGFloat(restored?.listOffset ?? 0))
        if let restored {
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: restored.cameraCenterLat, longitude: restored.cameraCenterLng),
                span: MKCoordinateSpan(latitudeDelta: restored.cameraSpanLat, longitudeDelta: restored.cameraSpanLng)
            )))
            _filters = State(initialValue: restored.filters ?? {
                var f = HomeDiscovery.Filters()
                f.cats = restored.catFilter == "all" ? [] : [restored.catFilter]
                f.seatsLeft = restored.openNowOnly
                return f
            }())
            _areaContext = State(initialValue: restored.areaContext)
            _cityContextID = State(initialValue: restored.cityContextID)
            _forYouOn = State(initialValue: restored.forYou)
            _searchQuery = State(initialValue: restored.searchQuery)
            _sortByDistance = State(initialValue: restored.sortByDistance)
            _selectedId = State(initialValue: restored.selectedId)
            _areaPanel = State(initialValue: restored.areaPanelKeys.map { MapAreaPanelState(keys: $0, label: restored.areaPanelLabel) })
            _preAreaRegion = State(initialValue: restored.preAreaRegion.map {
                MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: $0.centerLat, longitude: $0.centerLng),
                                   span: MKCoordinateSpan(latitudeDelta: $0.spanLat, longitudeDelta: $0.spanLng))
            })
            // The restored camera is already framed. A return from Event Detail brings its committed area back as-is
            // (the first settle is a 'restore', never a new area); "Open in Map" has a camera but no area yet, so its
            // first settle commits the area around that camera ('initial').
            _framed = State(initialValue: true)
            _committedBounds = State(initialValue: restored.committedBounds)
            _pendingReason = State(initialValue: (restored.committedBounds == nil ? .initial : .restore, Date()))
        } else {
            _cameraPosition = State(initialValue: .automatic)
            // Home's hand-off (filters + For You); the dock tab passes none.
            _filters = State(initialValue: entry?.filters ?? HomeDiscovery.Filters())
            _areaContext = State(initialValue: "map")
            _forYouOn = State(initialValue: entry?.forYou ?? false)
            _searchQuery = State(initialValue: seedQuery ?? "")
            _sortByDistance = State(initialValue: false)
            _selectedId = State(initialValue: nil)
            _framed = State(initialValue: false)
        }
    }

    @State private var categorySheetOpen = false
    /// Bounded mode: set once the loaded set turned out incomplete (see `.onChange(of: committedBounds)`).
    @State private var boundedMode = false
    private var boundedArea: MapDiscovery.Bounds? {
        guard boundedMode, let committedBounds else { return nil }
        return MapDiscovery.padBounds(committedBounds, factor: 1.5)
    }

    // MARK: - Layout

    /// The shared controls' bottom edge, with a stand-in until the first measurement.
    private var controlsBottomResolved: CGFloat { controlsBottom > 0 ? controlsBottom : safeTop + 124 }
    /// Top of the free map band, and of the list: just under the shared controls.
    private var freeTop: CGFloat { controlsBottomResolved + MapStack.controlsGap }
    /// The area panel's height: about 46 % of the screen, not draggable.
    private var panelHeight: CGFloat { max(260, (mapSize.height > 0 ? mapSize.height : UIScreen.main.bounds.height) * 0.46) }

    private var panelSpring: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88) }

    var body: some View {
        ZStack(alignment: .top) {
            // Pins are exactly the results (committed area + filters): the same list and count the list shows.
            // Markers by zoom level (note 79): city bubbles, neighbourhood bubbles, then price pins / clusters / stacks.
            // They always add up to the count.
            Map(position: $cameraPosition) {
                ForEach(markers) { m in
                    Annotation(markerTitle(m), coordinate: m.coordinate) {
                        marker(for: m)
                    }
                    // Names are drawn by the pin itself, only at street level (note 73).
                    .annotationTitles(.hidden)
                }
            }
            .mapControls { }
            // `.onEnd` (the default made explicit): the list stays still while a gesture runs; the area is committed
            // once the camera settles (MapDiscovery.Reason).
            .onMapCameraChange(frequency: .onEnd) { context in
                currentCameraRegion = context.region
                cameraSettled(context.rect)
                lastSettleAt = Date()
                closePanelIfZoomedOut()
            }
            // A tap that lands on the map background (a marker's own tap gesture claims taps on the marker itself
            // first) clears the highlight. A plain tap gesture layered alongside Map's own pan/pinch/rotate recognizers.
            .onTapGesture { selectedId = nil }
            .ignoresSafeArea()

            layers
                .opacity(uiPresented ? 1 : 0)
                // Task 1 (11-realtime-map.md follow-up): the layers shrink away as the user edge-swipes Map Explore
                // closed toward Home, tracking RootView's own progress (0 at rest, 1 at full commit).
                .scaleEffect(1 - 0.15 * app.mapCloseSwipeProgress, anchor: .bottom)
                .offset(y: 70 * app.mapCloseSwipeProgress)
        }
        // The map's full size and top safe area (the Map itself ignores the safe area) for the reference rect.
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { measure(proxy) }
                .onChange(of: proxy.size) { _, _ in measure(proxy) }
        })
        .onPreferenceChange(MapControlsBottomKey.self) { y in
            guard y > 0, abs(y - controlsBottom) > 0.5 else { return }
            controlsBottom = y
        }
        // Map redesign phase 2: a highlight lives only while its event is a result (area + filters, plus listed
        // no-location matches). Guarded until data and an area exist, so a restored one is never cleared before its
        // rows arrive.
        .onChange(of: selectableIDs) { _, ids in
            guard !app.mapEventsLoading, committedBounds != nil else { return }
            let next = MapDiscovery.selectionAfter(selectedId, results: ids)
            if next != selectedId { selectedId = next }
        }
        // Announce the settled count (never every camera frame) for VoiceOver.
        .onChange(of: visibleEvents.count) { _, n in
            guard committedBounds != nil else { return }
            UIAccessibility.post(notification: .announcement, argument: resultCountText(n))
        }
        .onChange(of: isActive) { _, _ in syncDock() }
        // Dock on demand (note 79): the dock shows except while a neighbourhood panel is open. Released whenever this
        // screen leaves, so the dock never stays hidden elsewhere.
        .onAppear { syncDock() }
        .onChange(of: areaPanel) { _, _ in syncDock() }
        .onChange(of: listOpen) { _, open in
            listUnmountTask?.cancel()
            if open {
                listMounted = true
            } else {
                // Keep the rows through the closing slide.
                listUnmountTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled else { return }
                    listMounted = false
                }
            }
        }
        // A new area is a new list: its old scroll offset means nothing there.
        .onChange(of: committedBounds) { _, _ in listOffset = 0 }
        // City and neighbourhood of each loaded event, for the bubbles, the chips, city search counts and the area picker.
        .task(id: app.mapEvents.map(\.id)) {
            var cities: [String: String] = [:]
            var areas: [String: MapDiscovery.AreaKey] = [:]
            for ev in app.mapEvents {
                if let id = MapDiscovery.cityFor(.init(city: ev.city, stateProvince: ev.stateProvince, countryCode: ev.countryCode,
                                                       lat: ev.lat, lng: ev.lng), cities: MapDiscovery.cities) {
                    cities[ev.id] = id
                }
                areas[ev.id] = MapDiscovery.areaKey(areaPlace(ev), cities: MapDiscovery.cities)
            }
            if cities != cityOfEvent { cityOfEvent = cities }
            if areas != areaOfEvent { areaOfEvent = areas }
        }
        .onChange(of: app.area) { _, _ in
            // Area picker = a DESTINATION (phase 3): fly to that area's mapped events and commit it once; every
            // filter stays. "Everywhere" or an area with no mapped events leaves the camera where it is (no guessed
            // geometry, never the whole inventory) and the chip reads "Map area".
            guard !isPreview else { return }
            goToPickedArea()
        }
        .onChange(of: app.mapCloseConfirmed) { _, confirmed in
            // A confirmed close (swipe past the threshold, or the back button) fades the layers while RootView
            // navigates; both go through the one shared `AppState.confirmMapExploreClose()`.
            guard confirmed else { return }
            withAnimation(.easeOut(duration: 0.22)) { uiPresented = false }
        }
        .task {
            // Edge-swipe race: the non-interactive "peeked at" copy RootView renders during an edge-swipe drag must
            // never run any of this (a mid-drag, possibly aborted preview racing the real instance to load data and
            // clear the one-shot snapshot).
            guard !isPreview else { return }
            // The restore itself happens in `init`. This only decides whether density-hotspot centering should run at
            // all (never for a restored instance: re-running it would discard where the user had the map) and clears
            // the snapshot now that this instance has consumed it.
            await app.loadMapEvents()
            if hadRestoredState {
                app.mapExploreState = nil
            } else {
                frameFirstOpen()
                // The one-shot FAB intent is consumed unconditionally once this fresh-open branch runs at all.
                if startFocusedOnSearch { app.mapExploreFocusSearch = false }
                if seedQuery != nil { app.mapExploreSeedQuery = nil }
                app.mapExploreEntry = nil // the Home hand-off is read once
            }
        }
        .onChange(of: app.mapCloseSwipeCancelled) { _, cancelled in
            // An interrupted left-edge swipe never navigates anywhere: the progress springs back by itself.
            guard cancelled else { return }
            app.mapCloseSwipeCancelled = false // one-shot pulse, consume immediately
            uiPresented = true
        }
        .onDisappear {
            listUnmountTask?.cancel()
            app.cancelRootPull()
            BottomTabBarOverlay.shared.setSheetOpen(dockToken, false)
        }
        // Bounded mode (phase 4): only when the public set is larger than the cap. Each committed area then loads its
        // own events (padded x1.5, exact count, newest load wins); the "Showing N of M" line stays honest. With the
        // set complete (production today) this never runs and panning stays network-free.
        .onChange(of: committedBounds) { _, area in
            guard !isPreview, area != nil, boundedMode || app.mapEvents.count < app.mapEventsTotal else { return }
            boundedMode = true
            Task { await app.loadMapEvents(bounds: boundedArea) }
        }
        // Freshness: the whole set again (or this area's, in bounded mode). Camera, area, filters, highlight and list
        // stay put.
        .onReceive(pollTimer) { _ in
            guard !isPreview else { return }
            Task { await app.loadMapEvents(bounds: boundedArea) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard !isPreview else { return }
            Task { await app.loadMapEvents(bounds: boundedArea) }
        }
        .onChange(of: app.userCoords) { _, newValue in
            // Only recenters when the location button itself triggered the permission grant (below): a background
            // coords refresh must never move the map on its own.
            guard awaitingRecenterAfterGrant, newValue != nil else { return }
            awaitingRecenterAfterGrant = false
            recenterOnUser()
        }
        .sheet(isPresented: $filterSheetOpen) {
            // Home's sheet as a draft over THIS map area: Close discards, Apply commits atomically.
            HomeFilterSheet(items: sheetItems, now: nowMinute, onClose: { filterSheetOpen = false },
                            mapFilters: filters, onApplyMap: { filters = $0 })
                .environmentObject(app)
        }
        .sheet(isPresented: $categorySheetOpen) {
            HomeCategorySheet(counts: categoryCountMap, selected: catFilter == "all" ? [] : [catFilter]) { key in
                catFilter = catFilter == key ? "all" : key
            }
            .environmentObject(app)
        }
        // The area picker is an overlay over the whole screen (not a second nested sheet), so the map stays in place
        // underneath it.
        .overlay {
            if locationPickerOpen {
                LocationPickerSheet(isPresented: $locationPickerOpen, topContent: AnyView(areaPickerCities))
                    .environmentObject(app)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: locationPickerOpen)
    }

    // MARK: - The layers over the map

    /// Back to front: the settled count (for VoiceOver and tests), the bottom stack, the neighbourhood panel, the list
    /// layer, the search panel, and the shared controls on top of all of them (the list's veil sits behind them).
    @ViewBuilder
    private var layers: some View {
        ZStack(alignment: .top) {
            // The settled result count for THIS map area: the same list the markers come from. Announced politely and
            // always present, so it is also what tests read (web `map-result-count`, screen-reader only).
            Text(committedBounds != nil && !(app.mapEventsLoading && app.mapEvents.isEmpty)
                 ? resultCountText(visibleEvents.count) : app.T("Đang tải sự kiện…", "Loading events…"))
                .font(.system(size: 1)).foregroundStyle(Color.clear)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityIdentifier("map.resultCount")
            #if DEBUG
            // Test hook (the web's `__mapExploreMapForTests`): the camera zoom on the 512 px basis, so UI tests can tell a
            // pinch that zoomed from one that did not. Not in release builds.
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("map.debug.zoom")
                .accessibilityValue(String(format: "%.2f", cameraZoom))
            // A clear pad in the free band between the shared controls and the area panel (touches pass through to the
            // map): a UI-test pinch started on it keeps both fingers on the map, away from the controls and the panel.
            Color.clear.frame(width: 260, height: 200).allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 230)
                .accessibilityIdentifier("map.debug.pinchPad")
            #endif

            bottomStack
            areaPanelLayer

            MapListOverlay(isOpen: $listOpen, top: freeTop, background: app.palette.paper,
                           closeTitle: app.T("Bản đồ", "Map"), bottomInset: MapStack.dockClear + 12) { probe in
                if listMounted { resultsList(probe) } else { Color.clear }
            }

            if searchFieldFocused { searchPanel }

            topControls
        }
    }

    private var topControls: some View {
        MapTopControls(query: $searchQuery, focused: $searchFieldFocused, filterBadge: sheetFilterCount,
                       autofocus: startFocusedOnSearch && !hadRestoredState,
                       onBack: { closeMap() },
                       onFilters: { searchFieldFocused = false; filterSheetOpen = true },
                       onSubmit: { rememberSearch() },
                       onCancel: { searchFieldFocused = false }) {
            chipRow
        }
    }

    /// The bottom stack above the dock, bottom to top: neighbourhood chips, the time bar's slot (reserved, built in
    /// step 7), then my location + "List · N". The room for the WHOLE stack is always reserved (`MapStack.reserved`
    /// feeds the reference rect), so what the stack shows never changes the results.
    private var bottomStack: some View {
        ZStack(alignment: .bottom) {
            if showAreaChips {
                areaChipsRow
                    .padding(.bottom, MapStack.dockClear + MapStack.chipsBottom)
            }
            if showEmptyCard {
                emptyCard
                    .padding(.bottom, MapStack.dockClear + MapStack.fabBottom + MapStack.buttonHeight + 8)
            }
            if !listOpen && areaPanel == nil {
                buttonsRow
                    .padding(.bottom, MapStack.dockClear + MapStack.fabBottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    private var buttonsRow: some View {
        HStack(spacing: 8) {
            Button(action: tapCompass) {
                Text("🧭")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .nativeGlass(Circle(), interactive: true)
                    .opacity(compassOpacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Vị trí của tôi", "My location"))
            .accessibilityIdentifier("map.compass")

            let n = visibleEvents.count
            Button {
                Haptics.selection()
                openList()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold)).accessibilityHidden(true)
                    Text(app.T("Danh sách", "List") + " · \(n)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: MapStack.buttonHeight)
                .foregroundStyle(app.palette.paper)
                .background(app.palette.ink, in: Capsule())
                .shadow(color: .black.opacity(0.28), radius: 7, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Danh sách, \(n) sự kiện", n == 1 ? "List, 1 event" : "List, \(n) events"))
            .accessibilityValue("\(n)")
            .accessibilityIdentifier("map.listButton")
        }
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Neighbourhood chips: one per neighbourhood with results, most events first. Hidden at city level and while the
    /// list, the panel or the search is open (their room stays reserved).
    private var showAreaChips: Bool {
        areaPanel == nil && !listOpen && !searchFieldFocused && MapDiscovery.markerLevel(zoom: cameraZoom) != .city && !areaChipItems.isEmpty
    }

    private struct AreaChipItem: Identifiable {
        var group: MapDiscovery.AreaGroup
        var cats: [String]
        var id: String { group.keys[0] }
    }

    private var areaChipItems: [AreaChipItem] {
        let located = visibleEvents.compactMap { ev -> (MapEventRow, MapDiscovery.GroupPoint)? in
            guard let lat = ev.lat, let lng = ev.lng else { return nil }
            return (ev, MapDiscovery.GroupPoint(id: ev.id, lat: lat, lng: lng))
        }
        let byID = Dictionary(located.map { ($0.0.id, $0.0) }, uniquingKeysWith: { a, _ in a })
        // Never merged (unlike the bubbles): mergePx 0.
        return MapDiscovery.areaGroups(located.map(\.1), zoom: 12, areaOf: { areaInfo($0.id) }, mergePx: 0)
            .sorted { a, b in
                a.ids.count != b.ids.count ? a.ids.count > b.ids.count
                    : ((a.labels.first ?? nil) ?? "~").localizedCompare((b.labels.first ?? nil) ?? "~") == .orderedAscending
            }
            .map { g in
                var cats: [String] = []
                for id in g.ids {
                    if let ev = byID[id], let c = ev.catKeys.first ?? effectiveCatKey(ev), !cats.contains(c) { cats.append(c) }
                }
                return AreaChipItem(group: g, cats: cats)
            }
    }

    private var areaChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(areaChipItems) { item in
                    let g = item.group
                    MapAreaChip(name: (g.labels.first ?? nil) ?? app.T("Khu khác", "Other areas"), count: g.ids.count, cats: item.cats,
                                key: g.keys[0]) {
                        Haptics.selection()
                        openAreaPanel(keys: g.keys, label: (g.labels.first ?? nil), bounds: g.bounds)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
        .rootSwipeExclusion("mapAreaChips")
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.T("Khu vực", "Areas"))
    }

    /// Closed list: the same empty-state messages float above the buttons (one place at a time).
    private var showEmptyCard: Bool {
        !listOpen && !searchFieldFocused && areaPanel == nil && hasEmptyState
    }

    private var hasEmptyState: Bool {
        (forYouActive && visibleEvents.isEmpty) || (visibleEvents.isEmpty && noLocationMatches.isEmpty)
    }

    private var emptyCard: some View {
        ScrollView { emptyState }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.4)
            .fixedSize(horizontal: false, vertical: true)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 9, y: 3)
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
    }

    // MARK: - The neighbourhood panel

    private var panelEvents: [MapEventRow] {
        guard let panel = areaPanel else { return [] }
        return visibleEvents.filter { panel.keys.contains(areaInfo($0.id).key) }
    }

    @ViewBuilder
    private var areaPanelLayer: some View {
        if let panel = areaPanel {
            let rows = panelEvents
            MapAreaPanelView(title: panel.label ?? app.T("Khu khác", "Other areas"), count: rows.count, height: panelHeight,
                             scrollTo: areaScrollTo,
                             backTitle: app.T("Tất cả khu", "All areas"),
                             emptyText: app.T("Không còn sự kiện ở khu này với bộ lọc hiện tại.", "No events left in this area with the current filters."),
                             onBack: { closeAreaPanel(goBack: true) }) {
                ForEach(rows) { ev in
                    compactRow(ev, idPrefix: "map.areaItem").id(ev.id)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
        }
    }

    /// Open a neighbourhood: fly so its events fill the free band above the panel (at pin level) and list them in the
    /// panel. `reveal` (a stack tap, already zoomed in) only centres that point above the panel, without zooming.
    /// The flight is a 'reveal' (never commits), so opening the panel never changes the committed area or the count;
    /// the web twin commits it as a 'cluster' move, but a fitted area is inside the committed one either way.
    private func openAreaPanel(keys: [String], label: String?, bounds: MapDiscovery.Bounds?,
                               reveal: (lat: Double, lng: Double)? = nil, scrollTo: String? = nil) {
        if areaPanel == nil { preAreaRegion = currentCameraRegion }
        areaOpenedAt = Date()
        areaScrollTo = scrollTo
        searchFieldFocused = false
        withAnimation(panelSpring) {
            areaPanel = MapAreaPanelState(keys: keys, label: label)
            listOpen = false
        }
        let pad = MapDiscovery.Padding(top: freeTop + 16, bottom: panelHeight + 16, left: 48, right: 48)
        let duration = reduceMotion ? 0 : 0.7
        if let reveal {
            let z = cameraZoom
            let point = MapDiscovery.Bounds(north: reveal.lat, south: reveal.lat, east: reveal.lng, west: reveal.lng)
            moveCamera(.reveal, to: fitRegion(point, padding: pad, maxZoom: z, minZoom: z), duration: duration)
        } else if let bounds {
            moveCamera(.reveal, to: fitRegion(bounds, padding: pad, maxZoom: 17, minZoom: MapDiscovery.areaZoom + 0.5), duration: duration)
        }
    }

    /// "All areas", the accessibility escape: close the panel and, with `goBack`, return to the view it was opened
    /// from (one commit once it settles).
    private func closeAreaPanel(goBack: Bool) {
        let view = preAreaRegion
        preAreaRegion = nil
        areaScrollTo = nil
        withAnimation(panelSpring) { areaPanel = nil }
        if goBack, let view { moveCamera(.cluster, to: view, duration: reduceMotion ? 0 : 0.7) }
    }

    /// The user zooming out of the neighbourhood closes its panel; the view stays where it is. Not while the opening
    /// flight is still going.
    private func closePanelIfZoomedOut() {
        guard areaPanel != nil, Date().timeIntervalSince(areaOpenedAt) > 1.5,
              MapDiscovery.areaPanelCloses(zoom: cameraZoom) else { return }
        preAreaRegion = nil
        withAnimation(panelSpring) { areaPanel = nil }
    }

    /// A stack tap: the events at one place may name slightly different areas (free text), so the panel lists all of
    /// them, scrolled to the tapped one.
    private func openAreaForEvent(_ ev: MapEventRow) {
        guard let lat = ev.lat, let lng = ev.lng else { return }
        let first = areaInfo(ev.id)
        let stackKeys = stackIDs(of: ev).map { areaInfo($0).key }
        var keys: [String] = []
        for k in [first.key] + stackKeys where !keys.contains(k) { keys.append(k) }
        openAreaPanel(keys: keys, label: first.label, bounds: nil, reveal: (lat, lng), scrollTo: ev.id)
    }

    private func areaPlace(_ ev: MapEventRow) -> MapDiscovery.AreaPlace {
        .init(area: ev.area, neighborhood: ev.neighborhood, city: ev.city, stateProvince: ev.stateProvince,
              countryCode: ev.countryCode, lat: ev.lat, lng: ev.lng)
    }

    private func areaInfo(_ id: String) -> MapDiscovery.AreaKey {
        areaOfEvent[id] ?? MapDiscovery.AreaKey(key: "-|~", label: nil, cityId: nil)
    }

    // MARK: - Dock + camera

    /// The dock shows except while the neighbourhood panel is open.
    private var dockHidden: Bool { isActive && !isPreview && !MapLayout.dockVisible(panelOpen: areaPanel != nil) }

    private func syncDock() {
        guard !isPreview else { return }
        BottomTabBarOverlay.shared.setSheetOpen(dockToken, dockHidden)
    }

    private func openList() {
        searchFieldFocused = false
        withAnimation(panelSpring) { listOpen = true }
    }

    // MARK: - Camera reasons → committed area (Lib/MapDiscovery.swift)

    /// Every programmatic move goes through here with its reason; a settle with no fresh reason is the user's.
    private func moveCamera(_ reason: MapDiscovery.Reason, to region: MKCoordinateRegion, duration: Double = 0.55) {
        pendingReason = (reason, Date())
        if reduceMotion || duration == 0 {
            cameraPosition = .region(region)
        } else {
            withAnimation(.easeInOut(duration: duration)) { cameraPosition = .region(region) }
        }
    }


    private func measure(_ proxy: GeometryProxy) {
        safeTop = proxy.safeAreaInsets.top
        mapSize = CGSize(width: proxy.size.width,
                         height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
    }


    /// The camera settled: commit a new area only for geographic navigation, once, after quick settles stop.
    private func cameraSettled(_ rect: MKMapRect) {
        guard framed, !isPreview else { return } // MapKit's pre-framing callbacks can report a bogus region
        let pending = pendingReason
        let window: TimeInterval = (pending?.reason.commits ?? false) ? 4 : 1.5
        let fresh = pending.map { Date().timeIntervalSince($0.at) < window } ?? false
        let reason: MapDiscovery.Reason = fresh ? pending!.reason : .user
        // A layout-only reason stays in force for its short window (a reveal can end in two settles); a navigation
        // reason is used once; extra settles just re-arm the single commit.
        if !fresh || reason.commits { pendingReason = nil }
        settleTask?.cancel()
        guard reason.commits else { return }
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            commitArea(rect, reason: reason)
        }
    }


    /// The reference rect (below the shared controls, above the always-reserved bottom stack) of the settled camera
    /// becomes the area. It never depends on the zoom level, an open panel or the list.
    private func commitArea(_ rect: MKMapRect, reason: MapDiscovery.Reason) {
        let nw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
        let se = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        let full = MapDiscovery.Bounds(north: nw.latitude, south: se.latitude, east: se.longitude, west: nw.longitude)
        let w = Double(max(1, mapSize.width)), h = Double(max(1, mapSize.height))
        let ref = MapDiscovery.referenceRect(width: w, height: h, topInset: Double(freeTop),
                                            bottomInset: Double(MapStack.reserved) + Self.legalReserve)
        committedBounds = MapDiscovery.boundsForRect(full, width: w, height: h, rect: ref)
        // The chip names the picked area only while the map is still framed on it; any other navigation makes the
        // context "Map area" (Home's selected area itself is never changed by panning).
        if reason == .destination, cityContextID != nil {
            areaContext = "city"
        } else {
            cityContextID = nil
            areaContext = (reason == .destination || (reason == .initial && framedByArea)) ? "area" : "map"
        }
    }

    /// Side margin of a fit: half the widest pin (category icon + price, note 73) plus a gap, so an edge event's pin is
    /// never cut by the screen edge (MapKit leaves a marker that hangs off the edge out of the accessibility tree).
    private static let markerSidePadding: Double = 64
    /// The strip kept for the Apple Maps legal label, above the bottom stack.
    private static let legalReserve: Double = 26

    /// A camera region that fits `bounds` into `padding` (px from each edge of the full map), between `minZoom` and
    /// `maxZoom` on the 512 px basis `MapDiscovery` and `cameraZoom` share.
    private func fitRegion(_ bounds: MapDiscovery.Bounds, padding: MapDiscovery.Padding, maxZoom: Double, minZoom: Double = 2) -> MKCoordinateRegion {
        let w = Double(max(320, mapSize.width)), h = Double(max(560, mapSize.height == 0 ? UIScreen.main.bounds.height : mapSize.height))
        let cam = MapDiscovery.fitCamera(bounds, width: w, height: h, padding: padding, maxZoom: maxZoom, minZoom: minZoom)
        let view = MapDiscovery.viewBounds(center: cam.center, zoom: cam.zoom, width: w, height: h)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: cam.center.lat, longitude: cam.center.lng),
                                  span: MKCoordinateSpan(latitudeDelta: view.north - view.south, longitudeDelta: view.east - view.west))
    }

    /// A camera region that fits `bounds` into the free band: below the shared controls, above the bottom stack.
    private func fittedRegion(_ bounds: MapDiscovery.Bounds, maxZoom: Double = 14) -> MKCoordinateRegion {
        let pad = MapDiscovery.Padding(top: Double(freeTop) + 16, bottom: Double(MapStack.reserved) + Self.legalReserve + 16,
                                       left: Self.markerSidePadding, right: Self.markerSidePadding)
        return fitRegion(bounds, padding: pad, maxZoom: maxZoom)
    }

    /// First open: frame what is relevant above the mid sheet — the selected area's events, else events within 50 km
    /// of a located viewer, else the densest city of events. Never the viewer's GPS on its own, never the whole
    /// inventory. No events at all: Ho Chi Minh City, and the empty state says so.
    private func frameFirstOpen() {
        guard !framed else { return }
        framed = true
        let located = app.mapEvents.filter { $0.lat != nil && $0.lng != nil }
        let pts = located.map { MapDiscovery.Point(lat: $0.lat!, lng: $0.lng!) }
        let areaIdx = app.area != LocationHierarchy.allID ? located.indices.filter { app.matchesArea(located[$0]) } : []
        let me = (app.located == true) ? app.userCoords.map { MapDiscovery.Point(lat: $0.lat, lng: $0.lng) } : nil
        let nearMe = MapDiscovery.pointsNear(pts, center: me, radiusKm: 50)
        let hotspot = densityHotspot(pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) })
            .map { MapDiscovery.Point(lat: $0.latitude, lng: $0.longitude) }
        framedByArea = !areaIdx.isEmpty
        let frame = !areaIdx.isEmpty ? areaIdx : (!nearMe.isEmpty ? nearMe : MapDiscovery.pointsNear(pts, center: hotspot, radiusKm: 25))
        if let box = MapDiscovery.boundsOfPoints(frame.map { pts[$0] }) {
            // Map E+: a fresh open is the neighbourhood level (one bubble per area), never a street-level close-up.
            moveCamera(.initial, to: fittedRegion(box, maxZoom: MapDiscovery.areaZoom - 0.6), duration: 0)
        } else {
            moveCamera(.initial, to: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
                                                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)), duration: 0)
        }
    }

    /// "Show nearest": the closest matching events (same filters) anywhere, framed above the mid sheet — explicit
    /// navigation that commits its area once. Never automatic, never presented as "here".
    private func showNearest() {
        let pts = matchingAnywhere.compactMap { ev in ev.lat.flatMap { lat in ev.lng.map { MapDiscovery.Point(lat: lat, lng: $0) } } }
        let c = currentCameraRegion?.center ?? CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009)
        guard let first = MapDiscovery.nearestPoint(pts, from: .init(lat: c.latitude, lng: c.longitude)),
              let box = MapDiscovery.boundsOfPoints(MapDiscovery.pointsNear(pts, center: pts[first], radiusKm: 25).map { pts[$0] })
        else { return }
        moveCamera(.nearest, to: fittedRegion(box), duration: 0.8)
    }

    /// Area picked on the Map = a destination: fit that area's mapped events above the mid sheet ('destination').
    private func goToPickedArea() {
        cityContextID = nil
        guard app.area != LocationHierarchy.allID else { areaContext = "map"; return }
        // Map v6 (note 74): a city node flies to the city's box (≥ city zoom, like a city search row), with or
        // without events; any other node to its events.
        if let last = LocationHierarchy.segments(ofID: app.area).last, last.kind == .city,
           let city = MapDiscovery.cities.first(where: { $0.vi == last.raw }) {
            moveCamera(.destination, to: cityRegion(city), duration: 0.8)
            return
        }
        let pts = app.mapEvents.filter { $0.lat != nil && $0.lng != nil && app.matchesArea($0) }
            .map { MapDiscovery.Point(lat: $0.lat!, lng: $0.lng!) }
        guard let box = MapDiscovery.boundsOfPoints(pts) else { areaContext = "map"; return }
        moveCamera(.destination, to: fittedRegion(box), duration: 0.8)
    }

    /// Badge: filters set in the sheet or the time chips (the category row and Seats left show their own state).
    private var sheetFilterCount: Int {
        var f = filters
        f.cats = []; f.seatsLeft = false
        return HomeDiscovery.activeFilterCount(f)
    }

    /// The sheet's market: events IN THE MAP AREA after search + For You, before Home's filters — so its pill counts
    /// and "Show N" are exactly what the list shows after Apply.
    private var sheetItems: [HomeDiscovery.Item] {
        guard let committedBounds else { return [] }
        return searchedEvents.filter { MapDiscovery.inBounds(lat: $0.lat, lng: $0.lng, committedBounds) }.map(discoveryItem)
    }

    /// Matching events outside this area — explains why the Map can show fewer than Home.
    private var outsideCount: Int { matchingAnywhere.count - visibleEvents.filter { $0.lat != nil && $0.lng != nil }.count }

    private func clearFilters() {
        filters = HomeDiscovery.Filters(); searchQuery = ""; forYouOn = false
    }

    private var filtersActive: Bool {
        HomeDiscovery.activeFilterCount(filters) > 0 || !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || forYouActive
    }

    private func resultCountText(_ n: Int) -> String {
        app.T("\(n) sự kiện trong vùng bản đồ", n == 1 ? "1 event in this map area" : "\(n) events in this map area")
    }


    // MARK: - Retained navigation state across Event Detail

    /// Snapshots everything this view owns right before handing off to the full-screen Event Detail screen (or Edit
    /// preferences), so returning restores it instead of re-initializing from scratch. Saved onto `AppState` (not kept
    /// only here) because RootView recreates this whole view the instant `screen` changes away from `.mapExplore`.
    /// Map E+: also whether the list is open (and where it is scrolled) and the open neighbourhood panel with the view
    /// it was opened from.
    private func saveSnapshot() {
        // `currentCameraRegion` (updated on EVERY settle) is where the map really is.
        let region = currentCameraRegion
        app.mapExploreState = MapExploreState(
            cameraCenterLat: region?.center.latitude ?? 10.7769,
            cameraCenterLng: region?.center.longitude ?? 106.7009,
            cameraSpanLat: region?.span.latitudeDelta ?? 0.05,
            cameraSpanLng: region?.span.longitudeDelta ?? 0.05,
            sheetFraction: 0.45,   // the sheet is gone (note 79); the field stays for older snapshots
            catFilter: catFilter,
            openNowOnly: openNowOnly,
            sortByDistance: sortByDistance,
            selectedId: selectedId,
            forYou: forYouActive,
            searchQuery: searchQuery,
            committedBounds: committedBounds,
            filters: filters,
            areaContext: areaContext,
            cityContextID: cityContextID,
            listOpen: listOpen,
            listOffset: Double(listOffset),
            areaPanelKeys: areaPanel?.keys,
            areaPanelLabel: areaPanel?.label,
            preAreaRegion: preAreaRegion.map {
                MapExploreState.SavedRegion(centerLat: $0.center.latitude, centerLng: $0.center.longitude,
                                            spanLat: $0.span.latitudeDelta, spanLng: $0.span.longitudeDelta)
            }
        )
    }

    private func editPreferences() {
        saveSnapshot()
        Haptics.selection()
        app.openEventPreferences(returnTo: .mapExplore)
    }

    private func openEventDetail(_ id: String) {
        // Map E+ (note 79): a pin or a row opens Event Detail directly. The event stays highlighted for the return.
        selectedId = id
        searchFieldFocused = false
        rememberSearch()
        saveSnapshot()
        // Search-result-selection fix pass (2026-09-28) — a belt-and-
        // suspenders clear alongside the `!hadRestoredState` guard on the
        // focus probe above (that guard's own doc comment has the full
        // trace): this is the exact moment a navigation-away can leave
        // `app.mapExploreFocusSearch` stale `true` (set by the FAB, never
        // reached its own clearing point because the user tapped into
        // Event Detail first). Clearing it here, unconditionally, means
        // the very next `MapExploreView` this app ever constructs —
        // restored or not — starts from a known-clean flag rather than
        // relying solely on the restored-instance guard to mask it.
        app.mapExploreFocusSearch = false
        app.goEvent(id)
    }

    /// An explicit exit (as opposed to "on my way to Event Detail, be right
    /// back") clears the snapshot — reopening the map later from Home
    /// should start fresh, not silently resume an unrelated past session.
    ///
    /// Task 1 (11-realtime-map.md follow-up): now just calls
    /// `AppState.confirmMapExploreClose()` — the ONE shared confirm path a
    /// completed left-edge swipe (`RootView`'s `edgeSwipe` commit branch)
    /// also calls directly. Not a second, parallel implementation that
    /// happens to produce the same visual: literally the same function
    /// owns the fast sheet-dismiss animation, the snapshot clear, and the
    /// actual navigation for both triggers now.
    private func closeMap() {
        app.confirmMapExploreClose()
    }

    // MARK: - Compass button (granted / denied / permanently-denied)

    /// Same 0.16 disabled-button opacity token this app already uses
    /// elsewhere (Components.swift's InkButton) — never a new value.
    private var compassOpacity: Double {
        locationGranted ? 1 : 0.16
    }

    /// Task 3 (11-realtime-map.md follow-up): whether location permission
    /// is already granted, independent of "Gần bạn"'s own on/off state —
    /// used to show each list row's distance in km by default once true.
    private var locationGranted: Bool {
        app.locationAuthStatus == .authorizedWhenInUse || app.locationAuthStatus == .authorizedAlways
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

    /// Explicit geographic navigation: one new search area once it settles.
    private func recenterOnUser() {
        guard let coords = app.userCoords else { return }
        moveCamera(.recenter, to: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        ))
    }


    // MARK: - Markers

    /// What the highlight and the list can point at: the results, plus listed no-location matches.
    private var selectableIDs: [String] { (visibleEvents + noLocationMatches).map(\.id) }

    /// Markers are exactly the results (committed area + filters), grouped for display only, by zoom level (note 79):
    /// city bubbles below `cityZoom`, one bubble per neighbourhood below `areaZoom`, then price pins / clusters /
    /// same-place stacks. Every result is in exactly one marker, so they always add up to the count. A highlighted
    /// event is pulled out of its cluster at pin level so it stays visible; at the same place it stays in its stack.
    private var markers: [MapMarker] {
        let located = visibleEvents.compactMap { ev -> MapDiscovery.GroupPoint? in
            guard let lat = ev.lat, let lng = ev.lng else { return nil }
            return MapDiscovery.GroupPoint(id: ev.id, lat: lat, lng: lng)
        }
        let zoom = cameraZoom
        let level = MapDiscovery.markerLevel(zoom: zoom)
        let sel = level == .pin ? located.first { $0.id == selectedId } : nil
        let selStacked = sel.map { MapDiscovery.sameSpotIDs(located, lat: $0.lat, lng: $0.lng).count > 1 } ?? false
        let groupable = (sel != nil && !selStacked) ? located.filter { $0.id != selectedId } : located
        var out: [MapMarker]
        switch level {
        case .city:
            let cities = cityOfEvent
            out = MapDiscovery.cityGroups(groupable, zoom: zoom, cityOf: { cities[$0.id] }, cities: MapDiscovery.cities).map(MapMarker.group)
        case .area:
            out = MapDiscovery.areaGroups(groupable, zoom: zoom, areaOf: { areaInfo($0.id) }).map(MapMarker.area)
        case .pin:
            out = MapDiscovery.clusterPins(groupable, zoom: zoom).map(MapMarker.group)
        }
        if let sel, !selStacked {
            out.append(.group(.init(kind: .pin, ids: [sel.id], lat: sel.lat, lng: sel.lng, bounds: nil)))
        }
        return out
    }

    private func markerTitle(_ m: MapMarker) -> String {
        if case .group(let g) = m, g.kind == .pin { return eventsByID[g.ids[0]]?.name ?? "" }
        return ""
    }

    @ViewBuilder
    private func marker(for m: MapMarker) -> some View {
        switch m {
        case .area(let a): MapAreaBubble(app: app, group: a) { tapArea(a) }
        case .group(let g): groupMarker(g)
        }
    }

    @ViewBuilder
    private func groupMarker(_ g: MapDiscovery.Group) -> some View {
        if g.kind == .pin, let ev = eventsByID[g.ids[0]] {
            pin(for: ev)
        } else if g.kind == .city, let city = MapDiscovery.city(g.cityId) {
            cityBubble(city, count: g.ids.count)
        } else {
            let n = g.ids.count
            let isSelected = selectedId.map(g.ids.contains) ?? false
            let stack = g.kind == .stack
            Text(stack ? "\(n) ≡" : "\(n)")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, stack ? 10 : 6)
                .frame(minWidth: stack ? 30 : 36, minHeight: stack ? 30 : 36)
                .foregroundStyle(isSelected ? app.palette.paper : app.palette.ink)
                .background(isSelected ? app.palette.ink : app.palette.paper, in: Capsule())
                .overlay(Capsule().stroke(app.palette.ink, lineWidth: stack ? 1.5 : 2))
                .shadow(radius: 4)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stack ? app.T("\(n) sự kiện cùng địa điểm, mở khu này", "\(n) events at this place, open this area")
                                          : app.T("\(n) sự kiện ở đây, phóng to", "\(n) events here, zoom in"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("map.\(g.kind.rawValue).\(g.ids[0])")
                .accessibilityValue("\(n)")
                .onTapGesture {
                    // A stack cannot be split by zooming: it opens its area's panel, scrolled to its first event.
                    if stack, let first = eventsByID[g.ids[0]] { Haptics.selection(); openAreaForEvent(first) } else { zoomTo(bounds: g.bounds) }
                }
        }
    }

    /// A neighbourhood bubble: one area opens its panel; several (overlapping at this zoom) zoom in to tell them apart.
    private func tapArea(_ a: MapDiscovery.AreaGroup) {
        Haptics.selection()
        if a.keys.count == 1 {
            openAreaPanel(keys: a.keys, label: a.labels.first ?? nil, bounds: a.bounds)
        } else {
            zoomTo(bounds: a.bounds)
        }
    }

    /// Results at the same place as `ev` (itself included, list order) — the card's ‹ 1/3 › switcher.
    private func stackIDs(of ev: MapEventRow) -> [String] {
        guard let lat = ev.lat, let lng = ev.lng else { return [ev.id] }
        let pts = visibleEvents.compactMap { e in e.lat.flatMap { la in e.lng.map { MapDiscovery.GroupPoint(id: e.id, lat: la, lng: $0) } } }
        return MapDiscovery.sameSpotIDs(pts, lat: lat, lng: lng)
    }

    private var eventsByID: [String: MapEventRow] {
        Dictionary(visibleEvents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A region's zoom on the same 512 px basis as `cameraZoom` (with `fittedRegion`'s width).
    private func zoom(of region: MKCoordinateRegion) -> Double {
        log2(360 * Double(max(320, mapSize.width)) / (512 * max(1e-9, region.span.longitudeDelta)))
    }

    /// The camera's zoom on a 512 px world basis (as the shared clustering expects): world width / map width.
    private var cameraZoom: Double {
        guard let span = currentCameraRegion?.span.longitudeDelta, span > 0 else { return 12 }
        return log2(360 * Double(max(1, mapSize.width)) / (512 * span))
    }

    /// Zoomed out (note 73 §5): "TP.HCM  5" — the city's short name and its result count in an ink badge. Tap = fly to
    /// the city's bounds (a destination, one new area).
    private func cityBubble(_ city: MapDiscovery.City, count n: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text(app.T(city.short.vi, city.short.en)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text("\(n)").font(.system(size: 12, weight: .bold)).monospacedDigit()
                .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                .background(app.palette.ink, in: Capsule())
                .foregroundStyle(app.palette.paper)
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .frame(minHeight: 32)
        .foregroundStyle(app.palette.ink)
        .background(app.palette.paper, in: Capsule())
        .overlay(Capsule().stroke(app.palette.ink, lineWidth: 1.5))
        .shadow(radius: 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("\(city.vi), \(n) sự kiện, đến đó", "\(city.en), \(n) events, go there"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("map.cityBubble.\(city.id)")
        .accessibilityValue("\(n)")
        .onTapGesture { goToCity(city.id) }
    }

    /// A city picked from search, the area picker or a bubble: clear the query, fit the city's bounds above the mid
    /// sheet ('destination', commits once — works with 0 events too), sheet to mid.
    /// A big city's whole box fits below city zoom (HCMC ≈ 8.3), which would just show its bubble again: land at
    /// least half a level above `cityZoom`, around the city centre, so its pins / clusters show.
    private func cityRegion(_ city: MapDiscovery.City) -> MKCoordinateRegion {
        let region = fittedRegion(city.bounds)
        let minZoom = MapDiscovery.cityZoom + 0.5
        guard zoom(of: region) < minZoom else { return region }
        let c = MapDiscovery.Bounds(north: city.center.lat, south: city.center.lat, east: city.center.lng, west: city.center.lng)
        return fittedRegion(c, maxZoom: minZoom)
    }


    /// A city picked from search, the area picker or a bubble: clear the query, fit the city's bounds in the free band
    /// ('destination', commits once, works with 0 events too). The list and the panel step aside so the map is seen.
    private func goToCity(_ id: String) {
        guard let city = MapDiscovery.city(id) else { return }
        Haptics.selection()
        rememberSearch()
        searchFieldFocused = false
        searchQuery = ""
        cityContextID = id
        locationPickerOpen = false
        if listOpen || areaPanel != nil {
            preAreaRegion = nil
            withAnimation(panelSpring) { listOpen = false; areaPanel = nil }
        }
        moveCamera(.destination, to: cityRegion(city), duration: 0.8)
    }

    /// Tap a cluster or a merged neighbourhood bubble: zoom in to fit its events (at least one level), explicit
    /// navigation, one new area.
    private func zoomTo(bounds: MapDiscovery.Bounds?) {
        guard let box = bounds else { return }
        var region = fittedRegion(box, maxZoom: 18)
        if let span = currentCameraRegion?.span, region.span.longitudeDelta > span.longitudeDelta / 2 {
            region.span = MKCoordinateSpan(latitudeDelta: span.latitudeDelta / 2, longitudeDelta: span.longitudeDelta / 2)
        }
        moveCamera(.cluster, to: region, duration: 0.6)
    }

    /// Price pin: the event's price per ticket in its own currency ("Free" when 0); selected = ink fill.
    @ViewBuilder
    private func pin(for ev: MapEventRow) -> some View {
        let isSelected = ev.id == selectedId
        let label = ev.priceVnd > 0 ? EventMarket.formatMoneyShort(ev.priceVnd, currency: ev.rowCurrency) : app.T("Miễn phí", "Free")
        // Map v5 (note 73 §2): the category row's own line icon + the price, so the row reads as the pins' legend.
        let catKey = ev.catKeys.first ?? effectiveCatKey(ev) ?? ""
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if !catKey.isEmpty {
                    Image(systemName: CategoryGlyph.symbol(catKey)).font(.system(size: 11, weight: .semibold))
                }
                Text(label)
            }
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: 30, minHeight: 30)
                .foregroundStyle(isSelected ? app.palette.paper : app.palette.ink)
                .background(isSelected ? app.palette.ink : app.palette.paper, in: Capsule())
                .overlay(Capsule().stroke(app.palette.ink, lineWidth: 1.5))
                .shadow(radius: isSelected ? 5 : 3)
            if seatFacts(ev)?.almostFull == true {
                Circle().fill(Color(red: 0.6, green: 0.24, blue: 0.18)).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 1.5))
                    .offset(x: 3, y: -3)
            }
        }
        // Street level (zoom ≥ 15): the event name under the pin, one line, truncated; drawn as an overlay so the pin
        // keeps its anchor.
        .overlay(alignment: .bottom) {
            if cameraZoom >= 15 {
                Text(ev.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(app.palette.ink)
                    .shadow(color: app.palette.paper, radius: 1.5)
                    .shadow(color: app.palette.paper, radius: 1.5)
                    .alignmentGuide(.bottom) { d in d[.top] - 3 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // Selected pin sits slightly larger and settles there; the brief overshoot past that (isPopping) plays once
        // per actual selection change, guarded in selectEvent(_:) — never replayed by a refresh.
        .scaleEffect(isSelected ? 1.1 : 1)
        .zIndex(isSelected ? 1 : 0)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ev.name), \(label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("map.pin.\(ev.id)")
        .onTapGesture { Haptics.selection(); openEventDetail(ev.id) }
    }

    // MARK: - Results

    /// THE results: inside the committed map area, every filter applied. Pins, list and count all come from this.
    private var visibleEvents: [MapEventRow] {
        areaBase.filter { inCategory($0, catFilter) }
    }

    /// Inside the committed area, every filter except the category (for the category counts).
    private var areaBase: [MapEventRow] {
        guard let committedBounds else { return [] }
        return baseEvents.filter { MapDiscovery.inBounds(lat: $0.lat, lng: $0.lng, committedBounds) }
    }

    /// Matching events with no map location yet: listed apart, never counted as "in this area".
    private var noLocationMatches: [MapEventRow] {
        baseEvents.filter { ($0.lat == nil || $0.lng == nil) && inCategory($0, catFilter) }
    }

    /// Matching events anywhere (for "Show nearest" when this area has none).
    private var matchingAnywhere: [MapEventRow] {
        baseEvents.filter { $0.lat != nil && $0.lng != nil && inCategory($0, catFilter) }
    }

    /// Whether the area has any event at all (so an empty list can say "filters hide them" vs "nothing here").
    private var anyInArea: Bool {
        guard let committedBounds else { return false }
        return app.mapEvents.contains { MapDiscovery.inBounds(lat: $0.lat, lng: $0.lng, committedBounds) }
    }

    /// A Map event in Home's discovery-item shape, so both run the same `HomeDiscovery.apply` predicate (date in the
    /// venue's own zone, seats from real fill, price per ticket in one currency, type chips).
    private func discoveryItem(_ ev: MapEventRow) -> HomeDiscovery.Item {
        let fill = app.eventFill[ev.id]
        return HomeDiscovery.Item(key: ev.id, startsAt: ev.startsAt, priceVnd: ev.priceVnd, catKeys: ev.catKeys,
                                  booked: fill?.booked, capacity: fill?.capacity, soldOut: false, currency: ev.rowCurrency,
                                  details: ev.details?.values ?? [:], tz: ev.timeZoneID)
    }

    /// The minute the time filters are judged at (like Home), never per frame.
    private var nowMinute: Date { Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60) }

    /// Every filter except the category (so each category chip can say what tapping it would show).
    private var baseEvents: [MapEventRow] {
        let searched = searchedEvents
        var others = filters
        others.cats = []
        let keep = Set(HomeDiscovery.apply(searched.map(discoveryItem), others, now: nowMinute).map(\.key))
        return searched.filter { keep.contains($0.id) }
    }

    /// Search + For You (the two filters outside Home's filter object), before geography and Home's filters. The area
    /// picker is a destination for the map now (phase 3), not an extra filter.
    private var searchedEvents: [MapEventRow] {
        var list = app.mapEvents
        // For You — the SAME match set drives pins and this list.
        if forYouActive {
            let order = forYouOrder
            list = list.filter { order[$0.id] != nil }
        }
        // Home quick event search (2026-09-27) — a by-name/area/keywords
        // text filter, ANDed with the filters above; never a second search
        // index (same `app.mapEvents` this screen already loads).
        // Search-matcher fix (Issue 2) — now matches the SAME canonical
        // search document the category chip's own coverage is built from
        // (`SearchMatch.buildDoc`, mirrors web's `src/lib/search.js`):
        // category label/key + aliases, area, city, organizer name,
        // description/intro, and `keywords` as a supplement — never
        // dependent on `keywords` alone. Normalized (case + Vietnamese-
        // accent-insensitive, đ/d folded), multi-token AND, substring.
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list = list.filter { SearchMatch.matches(doc: SearchMatch.buildDoc(for: $0), query: searchQuery) }
        }
        if forYouActive {
            let order = forYouOrder
            list.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
        }
        return list
    }

    /// A stale `forYouOn` (signed out / account switch / prefs cleared) must never filter anything.
    private var hasForYouPrefs: Bool { !(app.eventPrefs?.isEmpty ?? true) }
    private var forYouActive: Bool { forYouOn && hasForYouPrefs }
    private var forYouOrder: [String: Int] {
        Dictionary(app.mapForYouMatches.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // BUG 2 (2026-09-22 tenth follow-up) — was its own hand-duplicated
    // haversine copy; now delegates to the ONE shared coordinate-pair
    // primitive (`CatalogEvent.swift`) the story card and `CatalogEvent`'s
    // own `haversineKm(from:to:)` both use, so this list row's km can
    // never numerically drift from either of those.
    private func distanceKm(_ from: Coordinates, _ ev: MapEventRow) -> Double? {
        guard let lat = ev.lat, let lng = ev.lng else { return nil }
        return haversineKm(from: from, toCoords: Coordinates(lat: lat, lng: lng))
    }

    /// Bug 4 follow-up (category filter mismatch audit): mirrors web's own
    /// `fetchLiveEvents()` fallback (`row.cat_key || cosmetic?.catKey`) —
    /// iOS's `visibleEvents` used to compare `$0.catKey` directly with no
    /// such fallback. The live seeded demo data's own `cat_key` column was
    /// confirmed (by reading migration 020) to already match `categories`'
    /// keys exactly, so this wasn't reproducible against that dataset — but
    /// any row whose own `cat_key` column ever comes back nil/empty (a
    /// gap web already covers) would silently and permanently fail every
    /// non-"all" filter comparison while still showing fine under "Tất cả"
    /// (no filter applied) — the exact shape of the reported symptom.
    private func effectiveCatKey(_ ev: MapEventRow) -> String? {
        ev.catKey ?? EventCatalog.find(ev.id)?.catKey
    }

    /// Primary or second category (details.cat2), like Home's catKeys.
    private func inCategory(_ ev: MapEventRow, _ key: String) -> Bool {
        if key == "all" { return true }
        let keys = ev.catKeys.isEmpty ? [effectiveCatKey(ev)].compactMap { $0 } : ev.catKeys
        return keys.contains(key)
    }

    /// What tapping each category would show in this map area, with every other active filter applied.
    private var categoryCountMap: [String: Int] {
        let base = areaBase
        return Dictionary(uniqueKeysWithValues: HomeDiscovery.categories.map { c in (c.key, base.filter { inCategory($0, c.key) }.count) })
    }

    /// Real seat fill (get_public_event_fill) or nil when banbe has none; never the stale `seats_remaining`.
    private func seatFacts(_ ev: MapEventRow) -> HomeDiscovery.FillBadge? {
        guard let fill = app.eventFill[ev.id] else { return nil }
        return HomeDiscovery.fillBadge(booked: fill.booked, capacity: fill.capacity)
    }

    /// "Th 4, 05.03 · 19:00" in the venue's own zone (events.tz), never the viewer's clock.
    private func eventWhen(_ ev: MapEventRow) -> String {
        app.discoveryWhenLabel(ev.startsAt, timeZone: EventMarket.timeZone(ev.timeZoneID))
    }

    /// Price per ticket in the event's own currency; 0 is genuinely free.
    /// Price per ticket as the amount + an outlined ticket icon (owner 2026-11-01: "/ ticket" kept getting cut off).
    /// Never truncated: the row's left column gives way instead. VoiceOver still hears "/ ticket".
    private func priceView(_ ev: MapEventRow, font: Font) -> some View {
        HStack(spacing: 4) {
            if ev.priceVnd > 0 {
                Text(EventMarket.formatMoney(ev.priceVnd, currency: ev.rowCurrency))
                Image(systemName: "ticket").fontWeight(.regular).foregroundStyle(app.palette.ink)
            } else {
                Text(app.T("Miễn phí", "Free"))
            }
        }
        .font(font).lineLimit(1).fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(priceLine(ev))
    }

    private func priceLine(_ ev: MapEventRow) -> String {
        ev.priceVnd > 0
            ? "\(EventMarket.formatMoney(ev.priceVnd, currency: ev.rowCurrency)) \(app.T("/ vé", "/ ticket"))"
            : app.T("Miễn phí", "Free")
    }

    /// Distance only when it helps choose (≤ 50 km, Event Detail's rule); a viewer abroad saw "9662.0 km".
    private func nearDistance(_ ev: MapEventRow) -> String? {
        guard app.located == true, let coords = app.userCoords, let km = distanceKm(coords, ev) else { return nil }
        return EventDetailPresentation.distanceLabel(km: km, en: app.isEN)
    }

    @ViewBuilder
    private func seatPill(_ ev: MapEventRow, id: String) -> some View {
        if let f = seatFacts(ev) {
            if f.soldOut {
                Text(app.T("Hết chỗ", "Sold out")).font(.footnote.weight(.semibold)).foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier(id)
            } else if f.almostFull, let left = f.left {
                Text(app.T("Còn \(left) chỗ", "\(left) left")).font(.footnote.weight(.semibold))
                    .accessibilityIdentifier(id)
            }
        }
    }

    /// Solid chip on the opaque sheet (glass stays on the map controls). 36pt tall, inside a 44pt hit area.
    private func chip<Label: View>(active: Bool, muted: Bool = false, id: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .font(.subheadline.weight(active ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(active ? app.palette.ink : app.palette.surface2, in: Capsule())
                .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                .opacity(muted ? 0.55 : 1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    // MARK: - Active filter summary (peek strip + compact sticky header; MapDiscovery.activeFilterSummary)

    /// The folded header line: the picked category first (owner 2026-11-01), then the other filters; one count.
    private var filterSummary: (tokens: [MapDiscovery.SummaryToken], count: Int) {
        let s = MapDiscovery.activeFilterSummary(filters, forYou: forYouActive, query: searchQuery)
        guard catFilter != "all", !s.tokens.contains(.cat(catFilter)) else { return s }
        return ([.cat(catFilter)] + s.tokens, s.count + 1)
    }

    /// The city the map is centred on (smallest cities.json box holding the centre), for the map pill and full list.
    private var mapCityName: String? {
        guard let c = currentCameraRegion?.center else { return nil }
        let hit = MapDiscovery.cities
            .filter { c.latitude <= $0.bounds.north && c.latitude >= $0.bounds.south && c.longitude <= $0.bounds.east && c.longitude >= $0.bounds.west }
            .min { ($0.bounds.north - $0.bounds.south) * ($0.bounds.east - $0.bounds.west) < ($1.bounds.north - $1.bounds.south) * ($1.bounds.east - $1.bounds.west) }
        return hit.map { app.T($0.vi, $0.en) }
    }

    /// A non-empty query that led somewhere (an event, a city, or Search on the keyboard) becomes a recent search.
    private func rememberSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        recentSearches = MapRecentSearches.add(q)
    }

    /// Before typing: never a blank search — recent searches, cities (with counts) and quick filters.
    private var searchSuggestions: some View {
        let counts = cityCounts
        let cities = MapDiscovery.cities.filter { counts[$0.id, default: 0] > 0 || ["vn-hcm", "vn-hanoi", "vn-danang"].contains($0.id) }
            .enumerated().sorted { a, b in
                let ca = counts[a.element.id, default: 0], cb = counts[b.element.id, default: 0]
                return ca != cb ? ca > cb : a.offset < b.offset
            }.map(\.element)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        suggestionHeader(app.T("Gần đây", "Recent"))
                        ForEach(Array(recentSearches.enumerated()), id: \.offset) { i, q in
                            Button { searchQuery = q } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(app.palette.ink2)
                                        .accessibilityHidden(true)
                                    Text(q).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("map.search.recent.\(i)")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    suggestionHeader(app.T("Thành phố", "Cities"))
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(cities) { c in
                            let n = counts[c.id, default: 0]
                            chip(active: false, id: "map.search.city.\(c.id)") { goToCity(c.id) } label: {
                                Image(systemName: "mappin").font(.caption).accessibilityHidden(true)
                                Text(app.T(c.vi, c.en))
                                if n > 0 { Text("\(n)").monospacedDigit().opacity(0.6) }
                            }
                            .accessibilityLabel("\(app.T(c.vi, c.en)), \(cityCountText(n))")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    suggestionHeader(app.T("Lọc nhanh", "Quick filters"))
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        if hasForYouPrefs {
                            chip(active: forYouActive, id: "map.search.quick.foryou") {
                                searchFieldFocused = false; forYouOn.toggle()
                            } label: { Text(app.T("Dành cho bạn", "For You")) }
                        }
                        chip(active: openNowOnly, id: "map.search.quick.seatsLeft") {
                            searchFieldFocused = false; openNowOnly.toggle()
                        } label: { Text(app.T("Còn chỗ", "Seats left")) }
                        chip(active: sheetFilterCount > 0, id: "map.search.allFilters") {
                            searchFieldFocused = false; filterSheetOpen = true
                        } label: {
                            Image(systemName: "slider.horizontal.3").font(.footnote).accessibilityHidden(true)
                            Text(app.T("Tất cả bộ lọc", "All filters"))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("map.search.suggestions")
    }

    private func suggestionHeader(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
            .accessibilityAddTraits(.isHeader)
    }


    // MARK: - Shared controls: search panel and chips

    /// Focused search (note 74 §8, note 79): while empty, a panel under the shared controls with Recent / Cities / Quick
    /// filters; while typing, matching cities and a "Show N events" button that opens the list. The field itself stays
    /// mounted in the controls (the iOS focus rule), Cancel puts the keyboard away.
    private var searchPanel: some View {
        let typing = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 0) {
            if typing { typingResults } else { searchSuggestions }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        .padding(.top, controlsBottomResolved)
        .ignoresSafeArea()
    }

    private var typingResults: some View {
        let cities = cityMatches
        let n = visibleEvents.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !cities.isEmpty {
                    suggestionHeader(app.T("Thành phố", "Cities"))
                    ForEach(cities, id: \.id) { hit in cityRow(hit) }
                }
                Button {
                    rememberSearch()
                    Haptics.selection()
                    openList()
                } label: {
                    Text(app.T("Xem \(n) sự kiện", n == 1 ? "Show 1 event" : "Show \(n) events"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(app.palette.ink, in: Capsule())
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("map.search.showList")
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// For You pinned at the leading edge (never scrolls); only the other chips scroll: the area picker, Seats left
    /// (real fill only, so hidden until banbe has any), the categories with counts, "All categories".
    private var chipRow: some View {
        let showSeats = openNowOnly || app.mapEvents.contains(where: { app.eventFill[$0.id] != nil })
        let counts = categoryCountMap
        return HStack(spacing: 8) {
            if hasForYouPrefs {
                forYouChip
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.leading, 16)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // The geographic context: the city flown to, the picked area while framed on it, else "Map area".
                        glassChip(active: false, id: "map.area") { searchFieldFocused = false; locationPickerOpen = true } label: {
                            Text("\(areaChipLabel) ▾")
                        }
                        .id("map.chip.area")
                        if showSeats {
                            glassChip(active: openNowOnly, id: "map.openNow") { Haptics.selection(); openNowOnly.toggle() } label: {
                                Text(app.T("Còn chỗ", "Seats left"))
                            }
                        }
                        // Home's definitions and line icons, in a fixed order so the row never reshuffles; each count is
                        // what tapping it would show with every other filter kept; a picked one stays even at 0.
                        ForEach(orderedCategories, id: \.key) { cat in
                            let active = catFilter == cat.key
                            let n = counts[cat.key] ?? 0
                            glassChip(active: active, muted: n == 0 && !active, id: "map.cat.\(cat.key)") {
                                if !(active && cat.key == "all") {
                                    Haptics.selection()
                                    catFilter = active ? "all" : cat.key
                                }
                            } label: {
                                Image(systemName: CategoryGlyph.symbol(cat.key)).font(.footnote).accessibilityHidden(true)
                                Text(app.T(cat.vi, cat.en))
                                Text("\(n)").monospacedDigit().opacity(active ? 0.85 : 0.6)
                            }
                            .accessibilityLabel(app.T("\(cat.vi), \(n) sự kiện", "\(cat.en), \(n) events"))
                        }
                        glassChip(active: false, id: "map.cat.showAll") { searchFieldFocused = false; categorySheetOpen = true } label: {
                            Text(app.T("Tất cả danh mục", "All categories"))
                        }
                    }
                    .padding(.leading, hasForYouPrefs ? 0 : 16).padding(.trailing, 16)
                    .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.75), value: catFilter)
                }
                // The picked category moves to the front: scroll back there so it is never left off-screen.
                .onChange(of: catFilter) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("map.chip.area", anchor: .leading) }
                }
            }
            .rootSwipeExclusion("mapChips")
        }
    }

    /// A chip over the map: glass at rest, ink when on. 36 pt tall inside a 44 pt hit area.
    private func glassChip<Label: View>(active: Bool, muted: Bool = false, id: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .font(.subheadline.weight(active ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                .modifier(MapChipBackground(active: active, ink: app.palette.ink))
                .opacity(muted ? 0.55 : 1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// The geographic context: the city flown to, the picked area while the map is framed on it, else "Map area".
    private var areaChipLabel: String {
        if areaContext == "city", let c = MapDiscovery.city(cityContextID) { return app.T(c.vi, c.en) }
        if areaContext == "area" && app.area != LocationHierarchy.allID { return app.currentAreaLabel }
        return app.T("Vùng bản đồ", "Map area")
    }

    /// "All", then the picked category, then the rest in their fixed order.
    private var orderedCategories: [(key: String, vi: String, en: String)] {
        let all = HomeDiscovery.categories
        let rank: (String) -> Int = { $0 == "all" ? 0 : $0 == catFilter ? 1 : 2 }
        return all.enumerated().sorted { (rank($0.element.key), $0.offset) < (rank($1.element.key), $1.offset) }.map(\.element)
    }

    /// Large photo cards / compact list at full height (note 74), the same two-icon control and look as Home's.
    private var layoutSwitch: some View {
        HStack(spacing: 2) {
            ForEach([("large", app.T("Thẻ lớn", "Large cards"), "rectangle.grid.1x2"),
                     ("compact", app.T("Danh sách gọn", "Compact list"), "list.bullet")], id: \.0) { mode, label, icon in
                let on = app.mapListLayout == mode
                Button {
                    Haptics.selection()
                    app.mapListLayout = mode
                } label: {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 30)
                        .background(on ? app.palette.paper : Color.clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(app.palette.rule.opacity(on ? 1 : 0), lineWidth: 1))
                        .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 1.5, y: 1)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("map.layout.\(mode)")
            }
        }
        .padding(.horizontal, 2)
        .background(app.palette.ink.opacity(0.06), in: Capsule().inset(by: 7))
    }

    // MARK: - Cities (note 73 §5)

    /// Loaded map events per city (cities.json), for the search rows and the area picker.
    private var cityCounts: [String: Int] {
        cityOfEvent.values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private var cityMatches: [MapDiscovery.CityHit] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        return MapDiscovery.searchCities(q, cities: MapDiscovery.cities, counts: cityCounts)
    }

    private func cityCountText(_ n: Int) -> String {
        n > 0 ? app.T("\(n) sự kiện", n == 1 ? "1 event" : "\(n) events")
              : app.T("Chưa có sự kiện · vẫn có thể đến", "No events yet · you can still go")
    }

    private func cityRow(_ hit: MapDiscovery.CityHit) -> some View {
        let city = MapDiscovery.city(hit.id)
        return Button { goToCity(hit.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 22)).foregroundStyle(app.palette.clay)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.map { app.T($0.vi, $0.en) } ?? hit.id).font(.body.weight(.semibold)).lineLimit(1)
                    Text(cityCountText(hit.count)).font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(app.T("Đến", "Go")).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .background(app.palette.surface2, in: Capsule())
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map.city.\(hit.id)")
    }

    /// Area picker's "Cities" section: cities with at least one loaded event, plus the main cities of the viewer's
    /// country (VN unless located in the US). Picking one is the same destination move as a city search row.
    private var areaPickerCities: some View {
        let counts = cityCounts
        let us = app.located == true && (app.userCoords.map { $0.lng < -30 } ?? false)
        let main: Set<String> = us ? ["us-nyc", "us-la", "us-sf"] : ["vn-hcm", "vn-hanoi", "vn-danang"]
        let list = MapDiscovery.cities.filter { counts[$0.id, default: 0] > 0 || main.contains($0.id) }
            .enumerated().sorted { a, b in
                let ca = counts[a.element.id, default: 0], cb = counts[b.element.id, default: 0]
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map(\.element)
        return VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Thành phố", "Cities")).font(.system(size: 11.5, weight: .semibold))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(list) { c in
                    let n = counts[c.id, default: 0]
                    Button { goToCity(c.id) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                            Text(app.T(c.vi, c.en)).lineLimit(1)
                            if n > 0 { Text("\(n)").monospacedDigit().opacity(0.6) }
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(app.palette.surface2, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(app.T(c.vi, c.en)), \(cityCountText(n))")
                    .accessibilityIdentifier("map.areaCity.\(c.id)")
                }
            }
        }
        .padding(.top, 6).padding(.bottom, 4)
    }


    // MARK: - The list layer

    /// Every result, then (apart, never counted as "in this area") matching events with no map location.
    private var listEvents: [MapEventRow] { visibleEvents + noLocationMatches }

    private func resultsList(_ probe: ListTopPullProbe) -> some View {
        let located = visibleEvents
        let noLoc = noLocationMatches
        return List {
            // Top anchor: the pull-down probe (the list's own pan recognizer, never a SwiftUI drag, note 06) and the
            // scroll keeper that restores the offset the list was closed at.
            Color.clear.frame(height: 1)
                .background(probe)
                .background(ScaffoldScrollProbe(restoreOffsetY: listOffset > 1 ? listOffset : nil,
                                                onOffset: { y in if listOpen { listOffset = y } },
                                                onChange: { _, _ in }))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)

            listHeader
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Typed a city name: "Cities" first, tap = fly there (even with no events yet). The search panel shows
            // the same rows while the field is focused, so never both.
            let cities = searchFieldFocused ? [] : cityMatches
            if !cities.isEmpty {
                Text(app.T("Thành phố", "Cities"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityAddTraits(.isHeader)
                ForEach(cities, id: \.id) { hit in
                    cityRow(hit)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(located) { ev in listRow(ev) }

            if !noLoc.isEmpty {
                Text(app.T("Chưa có vị trí trên bản đồ (\(noLoc.count))", "No map location yet (\(noLoc.count))"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("map.noLocation.heading")
                ForEach(noLoc) { ev in listRow(ev) }
            }

            emptyState
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .environment(\.defaultMinListRowHeight, 0)
        // Large cards' photos load while the list is open only (a closed list loads nothing, note 22).
        .task(id: listOpen ? listEvents.prefix(8).map(\.id) : []) { if listOpen { prefetchLargeCardPhotos() } }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // The dock (its own window) always draws over the app: the last row clears it and the floating Map button.
        .contentMargins(.bottom, MapStack.dockClear + 16 + 72, for: .scrollContent)
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("map.list")
    }

    /// The count heading, the Large / Compact switch and the status notices (updating, refresh failed + Retry,
    /// incomplete set, "+N outside this area"). The city the map is on heads the list (the map is under it).
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let city = mapCityName {
                Label(city.uppercased(), systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11.5, weight: .bold)).tracking(0.8)
                    .foregroundStyle(app.palette.clay)
                    .padding(.top, 4)
                    .accessibilityLabel(app.T("Đang xem \(city)", "Showing \(city)"))
                    .accessibilityIdentifier("map.sheet.city")
            }
            HStack(spacing: 8) {
                Text(committedBounds != nil && !(app.mapEventsLoading && app.mapEvents.isEmpty)
                     ? resultCountText(visibleEvents.count) : app.T("Đang tải sự kiện…", "Loading events…"))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("map.list.count")
                layoutSwitch
            }
            if app.mapEventsLoading && !app.mapEvents.isEmpty {
                Text(app.T("Đang cập nhật…", "Updating…")).font(.footnote).foregroundStyle(app.palette.ink2)
            }
            if outsideCount > 0 && !visibleEvents.isEmpty {
                Text(app.T("+\(outsideCount) sự kiện khớp nằm ngoài vùng này",
                           "+\(outsideCount) matching event\(outsideCount == 1 ? "" : "s") outside this area"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                    .accessibilityIdentifier("map.outsideCount")
            }
            // A failed refresh keeps the last good results and says so; Retry reloads the whole set.
            if app.mapEventsLoadFailed && !app.mapEvents.isEmpty {
                HStack(spacing: 6) {
                    Text(app.T("Chưa cập nhật được.", "Couldn't update.")).font(.footnote).foregroundStyle(app.palette.ink2)
                    Button { Task { await app.loadMapEvents(bounds: boundedArea) } } label: {
                        Text(app.T("Thử lại", "Retry")).font(.footnote.weight(.semibold)).underline().frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.refreshRetry")
                }
            }
            if app.mapEvents.count < app.mapEventsTotal {
                Text(app.T("Đang hiện \(app.mapEvents.count)/\(app.mapEventsTotal) sự kiện · phóng to để xem kỹ hơn",
                           "Showing \(app.mapEvents.count) of \(app.mapEventsTotal) events · zoom in for more"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                    .accessibilityIdentifier("map.incomplete")
            }
            if forYouActive {
                Button { editPreferences() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                        Text(app.T("Chỉnh sở thích của bạn", "Edit preferences"))
                            .font(.system(size: 12.5, weight: .semibold)).underline()
                    }
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.foryou.editPrefs")
            }
        }
    }

    /// A result row: Home's large photo card (with its pager) or a compact row. A tap opens Event Detail directly.
    @ViewBuilder
    private func listRow(_ ev: MapEventRow) -> some View {
        if app.mapListLayout == "large" {
            largeCard(ev)
        } else {
            compactRow(ev, idPrefix: "map.listItem")
                .id(ev.id)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private func prefetchLargeCardPhotos() {
        let lists: [[String]] = listEvents.prefix(8).map { ev in
            if let e = app.feed.first(where: { $0.key == ev.id }) { return app.cardImages(e) }
            return (app.mapEventPhotoURLs[ev.id] ?? app.mapEventCoverURLs[ev.id].map { [$0] } ?? []).map(\.absoluteString)
        }
        CardPhotoPrefetch.run(lists)
    }

    /// Large card in the list: Home's own discovery card for the event (date / fill badges, Save, price, meta, the type
    /// line, owner 2026-11-01: the Map showed less than Home), with a tap that opens Event Detail. An event Home's feed
    /// does not hold yet keeps the Map's simpler card.
    @ViewBuilder
    private func largeCard(_ ev: MapEventRow) -> some View {
        if let e = app.feed.first(where: { $0.key == ev.id }) {
            // The Map's own gallery (cover first) is the fuller set when Home's has fewer photos for the event.
            var model = app.discoveryCardModel(e, item: app.discoveryItem(for: e))
            let _ = { if let g = app.mapEventPhotoURLs[ev.id], g.count > model.imgs.count { model.imgs = g.map(\.absoluteString) } }()
            DiscoveryCard(model: model, context: "map",
                          onTap: { openEventDetail(ev.id) }, outerPadding: false)
                // No identifier here: a parent's id replaces the card's own (`card.<key>`, the photo pager's) ones.
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            mapLargeCard(ev)
        }
    }

    private func mapLargeCard(_ ev: MapEventRow) -> some View {
        var paths = (app.mapEventPhotoURLs[ev.id] ?? app.mapEventCoverURLs[ev.id].map { [$0] } ?? []).map(\.absoluteString)
        if paths.isEmpty, let demo = EventCatalog.find(ev.id), demo.key == ev.id, !demo.img.isEmpty { paths = [demo.img] }
        let catKey = ev.catKeys.first ?? effectiveCatKey(ev) ?? ""
        let cat = HomeDiscovery.categories.first { $0.key == catKey }
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    PhotoPager(eventID: ev.id, paths: paths, context: "map", cornerRadius: BanbeTheme.Radius.card,
                               photoIdentifier: "map.card.photo.\(ev.id)")
                        .zoomSource(ev.id)
                }
                .overlay(alignment: .topLeading) {
                    let when = eventWhen(ev)
                    if !when.isEmpty {
                        PhotoChip(text: when, background: app.palette.paper.opacity(0.62), foreground: app.palette.ink)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ev.name).font(BanbeTheme.display(18)).lineLimit(1)
                Spacer(minLength: 0)
                priceView(ev, font: .system(size: 15, weight: .bold))
            }
            .padding(.top, 10)
            Text([ev.area, nearDistance(ev)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12.5)).opacity(0.68).lineLimit(1)
                .padding(.top, 3)
            HStack(spacing: 6) {
                if let cat {
                    Image(systemName: CategoryGlyph.symbol(cat.key)).font(.caption).accessibilityHidden(true)
                    Text(app.T(cat.vi, cat.en)).font(.system(size: 12.5))
                }
                Spacer(minLength: 0)
                seatPill(ev, id: "map.card.seats.\(ev.id)")
            }
            .opacity(0.85)
            .padding(.top, 3)
        }
        .padding(12)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: BanbeTheme.Radius.card, style: .continuous))
        .foregroundStyle(app.palette.ink)
        .contentShape(Rectangle())
        .onTapGesture { openEventDetail(ev.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAction { openEventDetail(ev.id) }
        .accessibilityIdentifier("map.card.\(ev.id)")
        .id(ev.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }


    /// Compact row (the list's Compact layout and the neighbourhood panel): small photo, name, venue date · time, area
    /// (plus a distance only when it helps choose, <= 50 km), price + real seat state. A tap opens Event Detail.
    private func compactRow(_ ev: MapEventRow, idPrefix: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // The event's own resolved photo first; the bundled demo catalogue only for a real demo id.
            if let url = app.mapEventCoverURLs[ev.id] {
                CatalogPhoto(path: url.absoluteString, height: 56, width: 56, cornerRadius: 12)
            } else if let path = EventCatalog.find(ev.id)?.img {
                CatalogPhoto(path: path, height: 56, width: 56, cornerRadius: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(eventWhen(ev))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                    .accessibilityIdentifier("\(idPrefix).when.\(ev.id)")
                Text([ev.area, nearDistance(ev)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                // An honest "no map location" state, never a silently-omitted row or an invented pin.
                if ev.lat == nil || ev.lng == nil {
                    Text(app.T("Chưa có vị trí trên bản đồ", "No map location yet"))
                        .font(.system(size: 10.5)).opacity(0.55)
                        .accessibilityIdentifier("\(idPrefix).noLocation.\(ev.id)")
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                priceView(ev, font: .subheadline.weight(.semibold))
                    .accessibilityIdentifier("\(idPrefix).price.\(ev.id)")
                seatPill(ev, id: "\(idPrefix).seats.\(ev.id)")
            }
        }
        .padding(.vertical, 7)
        .background(selectedId == ev.id ? app.palette.ink.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { openEventDetail(ev.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openEventDetail(ev.id) }
        .accessibilityIdentifier("\(idPrefix).\(ev.id)")
    }

    /// Gold-star chip. No recenter, no detent change, no refetch on toggle.
    private var forYouChip: some View {
        let gold = Color(red: 0.80, green: 0.62, blue: 0.16)
        let active = forYouActive
        return Button {
            Haptics.selection()
            if !forYouOn { forYouAlert.acknowledge(loadedIDs: app.mapForYouMatches.map(\.key)) }
            forYouOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(active ? app.palette.paper : gold)
                Text(app.T("Dành cho bạn", "For You"))
                    .font(.system(size: 11, weight: active ? .bold : .regular))
                    .lineLimit(1)
                if forYouAlert.hasPending {
                    Text(app.T("Mới", "New"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color(red: 0.478, green: 0.322, blue: 0)))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(active ? app.palette.paper : app.palette.ink)
            .frame(minHeight: 36)
            .background(active ? app.palette.ink : app.palette.surface2, in: Capsule())
            .overlay(Capsule().stroke(active ? app.palette.ink : gold.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .modifier(ForYouAttentionEffect(animating: forYouAlert.animating, reduceMotion: reduceMotion, token: forYouAlert.replayToken))
        .accessibilityIdentifier("map.filter.foryou")
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityLabel(forYouAlert.hasPending && !active
            ? app.T("Dành cho bạn, có gợi ý mới", "For You, new recommendations")
            : app.T("Dành cho bạn", "For You"))
        .onAppear { forYouAlert.attach(userID: app.userID?.uuidString); forYouAlert.replay() }   // glow on arrival, like Home
        .onChange(of: app.userID) { _, id in forYouAlert.attach(userID: id?.uuidString) }
    }

    private func emptyAction(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(app.palette.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// Loading / empty states while the list has nothing to show (For You's own, then the general ones).
    @ViewBuilder
    private var emptyState: some View {
        if forYouActive && visibleEvents.isEmpty {
            VStack(spacing: 10) {
                if app.mapEventsLoading || app.eventPrefs == nil {
                    ProgressView()
                    Text(app.T("Đang tìm sự kiện hợp với bạn…", "Finding events for you…"))
                        .font(.system(size: 13)).opacity(0.6)
                        .accessibilityIdentifier("map.foryou.loading")
                } else {
                    Text(app.mapForYouMatches.isEmpty
                         ? app.T("Chưa có sự kiện nào hợp với sở thích của bạn trong khu vực/vùng bản đồ này.",
                                 "No events match your preferences in this area or map view yet.")
                         : app.T("Các sự kiện hợp với bạn không khớp bộ lọc hiện tại.",
                                 "Your For You matches don't fit the current filters."))
                        .font(.system(size: 13)).opacity(0.7).multilineTextAlignment(.center)
                        .accessibilityIdentifier("map.foryou.empty")
                    Button { editPreferences() } label: {
                        Text(app.T("Chỉnh sở thích của bạn", "Edit preferences"))
                            .font(.system(size: 13, weight: .semibold)).underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.foryou.emptyEdit")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        } else if visibleEvents.isEmpty && noLocationMatches.isEmpty {
            // Each empty state says WHY, and never silently widens the area or loosens filters: first load · failed
            // first load · filters hide the events that are here · nothing in this part of the map.
            VStack(spacing: 10) {
                if app.mapEventsLoading && app.mapEvents.isEmpty {
                    ProgressView()
                    Text(app.T("Đang tải sự kiện…", "Loading events…")).font(.subheadline).foregroundStyle(app.palette.ink2)
                } else if app.mapEventsLoadFailed && app.mapEvents.isEmpty {
                    Image(systemName: "wifi.exclamationmark").font(.title3).foregroundStyle(app.palette.ink2)
                    Text(app.T("Chưa tải được sự kiện. Kiểm tra kết nối mạng rồi thử lại.",
                               "Couldn't load events. Check your connection and try again."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                    emptyAction(app.T("Thử lại", "Try again"), id: "map.retry") { Task { await app.loadMapEvents(bounds: boundedArea) } }
                } else if committedBounds != nil && anyInArea && filtersActive {
                    Text(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                         ? app.T("Có sự kiện trong vùng này nhưng bộ lọc đang ẩn chúng.", "There are events in this area, but your filters hide them.")
                         : app.T("Không có sự kiện nào trong vùng này khớp với \"\(searchQuery)\".", "No events in this area match \"\(searchQuery)\"."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                    emptyAction(app.T("Xoá bộ lọc", "Clear filters"), id: "map.clearFilters") { clearFilters() }
                } else if committedBounds != nil {
                    Text(app.T("Không có sự kiện nào trong vùng bản đồ này.", "No events in this part of the map."))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).multilineTextAlignment(.center)
                    if !matchingAnywhere.isEmpty {
                        emptyAction(app.T("Xem sự kiện gần nhất", "Show nearest events"), id: "map.showNearest") { showNearest() }
                    }
                    // Filters on and nothing here: offer to clear them (owner 2026-11-01), never a dead end.
                    if filtersActive {
                        emptyAction(app.T("Xoá \(filterSummary.count) bộ lọc", filterSummary.count == 1 ? "Clear 1 filter" : "Clear \(filterSummary.count) filters"),
                                    id: "map.clearFiltersEmpty") { clearFilters() }
                    }
                }
            }
            .accessibilityIdentifier("map.emptyState")
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
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

/// Map v6 (note 74): the Map's recent searches, newest first, at most five (device-local, like the Search screen's).
enum MapRecentSearches {
    static let key = "banbe.map.recentSearches.v1"

    static func load() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    @discardableResult
    static func add(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return load() }
        var list = load().filter { $0.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        list.insert(q, at: 0)
        list = Array(list.prefix(5))
        UserDefaults.standard.set(list, forKey: key)
        return list
    }
}

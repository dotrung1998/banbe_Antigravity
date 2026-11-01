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

/// Map + list explore screen (.claude/notes/11-realtime-map.md). Full-screen
/// native MapKit behind a native `.sheet` bottom sheet (`.presentationDetents`
/// gives drag-to-resize/snap for free on iOS 17+, this project's deployment
/// target) — no custom gesture code needed here, unlike the web build of the
/// same screen.
struct MapExploreView: View {
    @EnvironmentObject var app: AppState
    @State private var cameraPosition: MapCameraPosition
    /// Map redesign phase 2: the committed search area (Lib/MapDiscovery.swift). It changes only when the camera
    /// settles after geographic navigation — never because the sheet moved, a selection was revealed or data refreshed.
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
    /// The whole public set again every 60 s (was 5 s: every row re-downloaded a dozen times a minute — Supabase
    /// egress, note 40). Kept in @State so it is made once per screen (built inline, every redraw restarted it).
    @State private var pollTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    /// Map redesign phase 3: ONE filter object in Home's shape (date, cats, seatsLeft, price, free, almostFull,
    /// typeFilters), judged by the same `HomeDiscovery.apply` Home uses — each event in its own venue time zone.
    /// Seeded from a return snapshot, else Home's hand-off, else nothing. Moving the map never changes it.
    @State private var filters: HomeDiscovery.Filters
    @State private var filterSheetOpen = false
    /// "area" while the map is framed on the picked area (destination), else "map" ("Vùng bản đồ / Map area").
    @State private var areaContext: String
    @State private var framedByArea = false
    /// The category row is single-choice (the Map sheet hides categories, as Home's does in Simple Shell).
    private var catFilter: String {
        get { filters.cats.first ?? "all" }
        nonmutating set { filters.cats = newValue == "all" ? [] : [newValue]; filters.typeFilters = [] }
    }
    private var openNowOnly: Bool {
        get { filters.seatsLeft }
        nonmutating set { filters.seatsLeft = newValue }
    }
    @State private var sortByDistance: Bool
    // Home quick event search (2026-09-27) — see `visibleEvents`'s own
    // doc comment. `startFocusedOnSearch` is read once, at construction
    // (mirrors `hadRestoredState`'s own one-shot capture), so a later
    // unrelated re-render can't re-focus the field out from under the user.
    @State private var searchQuery: String
    // For You (34/35 notes) — local to Map, never touches Home's `app.filterForYou`.
    // Matching is `app.mapForYouMatches` (same ForYou.rank + same area rule as Home).
    @State private var forYouOn: Bool
    @StateObject private var forYouAlert = ForYouAlertModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Location hierarchy (migration 112) — Map's own presentation of the
    // shared location picker (selection itself is `app.area`, shared with
    // Home).
    @State private var locationPickerOpen = false
    // Map search-focus fix (2026-09-28, fifth pass) — plain `@State`, not
    // `@FocusState`. See `FocusableTextField`'s own doc comment
    // (Components.swift) for the confirmed reason: `@FocusState` itself
    // cannot deliver programmatic focus to this field on a real device, by
    // any mechanism tried, while `FocusableTextField`'s direct
    // `becomeFirstResponder()`/`resignFirstResponder()` — the exact plain
    // UIKit mechanism a manual tap already proven to work — reads and
    // writes this same plain `Bool` two-way instead.
    @State private var searchFieldFocused = false
    private let startFocusedOnSearch: Bool
    /// Note 50 — Search's "See on map": the query a fresh open starts with (one-shot, like the focus intent).
    private let seedQuery: String?
    // Defaults to the "tall" snap point (covers most of the screen, leaving
    // a small map strip visible at top) per the ticket's layout spec — not
    // the smallest detent, and not a binary toggle: `.presentationDetents`
    // gives all three snap points (tall/mid/peek) standard drag-to-resize
    // behavior for free.
    @State private var sheetDetent: PresentationDetent
    @State private var awaitingRecenterAfterGrant = false

    // The pin/list-row currently showing the compact in-map preview card —
    // nil when nothing is selected. Not a second data source: just an id
    // into the same `visibleEvents` this screen already loads/filters.
    @State private var selectedId: String?
    // Non-nil only for the brief overshoot phase of the selection "pop" —
    // see `selectEvent(_:)`.
    @State private var poppingId: String?
    // Bug 2 follow-up: true only when this instance was constructed with a
    // saved snapshot AND that snapshot had a selection — drives a single
    // scroll-to-row once the list has rows to scroll to (see `init` below).
    @State private var pendingScrollToRestoredSelection: Bool
    // Bug 2 follow-up: captured once at construction time so `.task` below
    // knows whether to skip density-hotspot centering — reading
    // `app.mapExploreState` itself in `.task` would already be too late,
    // and clearing it (an @Published var) doesn't retroactively un-restore
    // the @State values that already seeded from it in `init`.
    private let hadRestoredState: Bool
    // Follow-up (edge-swipe race): true only for the non-interactive
    // "peeked at" copy RootView renders underneath an in-progress edge
    // swipe (see that call site's comment) — never for the real, on-screen
    // instance. Skips every side effect below (`app.loadMapEvents()`,
    // clearing `app.mapExploreState`, the 5s poll, density-hotspot
    // centering) so a mid-drag preview — including one the user aborts —
    // can never race the real instance for the one-shot snapshot.
    private let isPreview: Bool
    // Sheet-reveal-timing fix (2026-09-29) — this instance is mounted
    // EARLY, the moment it becomes the tab-swipe neighbor (RootView's own
    // `rootScreensToRender` doc comment: deliberately real/mounted, not an
    // `isPreview` throwaway, so its data starts loading right away) — but
    // that used to mean its own `.sheet` auto-presented (see `sheetPresented`
    // init below) and animated up WHILE the swipe was still mid-drag, well
    // before the screen transition itself had finished — the reported "the
    // sheet list appears immediately... before the swipe to the map is
    // fully completed." `isActive` is `false` for exactly that not-yet-
    // committed window (and for the non-interactive edge-swipe-back peek
    // copy) and only becomes `true` once RootView's `s == app.screen`
    // really flips — same SwiftUI-preserved instance throughout, per
    // `rootScreensToRender`'s own identity-preserving `ForEach`, so
    // `.onChange(of: isActive)` below fires exactly once, exactly when the
    // transition genuinely finishes.
    private let isActive: Bool
    // Restore-only "bubble" spring: 0 right after a restored construction
    // (sheet content starts very slightly scaled down/offset), animated to
    // 1 exactly once in `.task` below via an interpolating spring (a touch
    // of overshoot, then settle) — never touched again afterward, so a
    // later poll/filter change can't replay it. A fresh (non-restored) open
    // starts straight at 1: only a genuine restore gets the bubble.
    @State private var restoreBubbleProgress: CGFloat
    // Map v5 (note 73): the three detents. Peek is a fixed HEIGHT that fits the grabber + three short lines (result
    // count, the active filter summary, "+N outside this area"); the reference rect (note 72) sits above it at every
    // detent, so results never change with the sheet. The floating selected card is gone: selection lives in the sheet.
    // Map v6 (note 74): peek also holds a row of quick chips (search button, For You, Tonight, Weekend, top
    // categories, All filters), so it is a little taller; "tall" is now FULL height, its top just under the
    // Close / compass row (stored as 0.72 in snapshots, as before).
    static let peekHeight: CGFloat = 152
    /// Screen-only on purpose: reading the key window's safe area here touched UIKit layout during the first body
    /// pass, which re-entered this lazy static and trapped in `dispatch_once` (every Map launch crashed). Top inset:
    /// Face ID phones (≥ 800 pt tall) ~62 pt, home-button phones 20 pt.
    static let fullHeight: CGFloat = {
        let screen = UIScreen.main.bounds.height
        let top: CGFloat = screen >= 800 ? 62 : 20
        return max(400, screen - top - CGFloat(topControlsHeight) + 4)
    }()
    static let peekDetent: PresentationDetent = .height(peekHeight)
    static let midDetent: PresentationDetent = .fraction(0.45)
    static let tallDetent: PresentationDetent = .height(fullHeight)
    /// Unique per instance, so a torn-down copy never releases the dock another instance hid.
    @State private var dockToken = "mapExplore.dock." + UUID().uuidString
    /// Sticky filters (note 73 §3): the list is scrolled past its first row, so the header is one compact line.
    @State private var listScrolled = false
    /// Bumped to scroll the list back to its top (row tap = select, compact line tap).
    @State private var listTopToken = 0
    /// Last camera settle; a camera change right after one is MapKit finishing that move, not the user's.
    @State private var lastSettleAt = Date.distantPast
    /// City of each loaded event (cities.json), recomputed only when the loaded rows change.
    @State private var cityOfEvent: [String: String] = [:]
    /// The city the map was flown to (search or area picker), while it is still the framed destination.
    @State private var cityContextID: String?
    /// Map v6: where the sheet was when search started (peek's search button opens it at full); Cancel goes back.
    @State private var searchOrigin: PresentationDetent?
    /// Map v6: recent searches (UserDefaults `banbe.map.recentSearches.v1`, max 5), shown before typing.
    @State private var recentSearches: [String] = MapRecentSearches.load()
    // Bug 2 follow-up (deliberate restore-reveal delay): whether the sheet
    // (and, by extension, the preview card — see `body`) is actually
    // presented. A FRESH open shows it immediately; a RESTORED instance (or
    // one recovering from an interrupted close-swipe — task 2 follow-up)
    // starts with this `false` and only flips `true` once
    // `postDismissRevealTask` (below) fires, after the outgoing
    // animation/gesture has fully finished PLUS the ticket's explicit
    // additional pause — never early, never behind whatever's still
    // animating away.
    @State private var sheetPresented: Bool
    // Bug 2 follow-up: holds the cancellable delayed-reveal task so a
    // second navigation (or a fast repeated back gesture) can't reveal
    // stale UI after the user has already left this instance — cancelled
    // in `.onDisappear`.
    @State private var postDismissRevealTask: Task<Void, Never>?
    /// How long Event Detail's own outgoing animation takes — matches
    /// `RootView.swift`'s screen-transition duration (`.animation(.easeInOut
    /// (duration: 0.28), value: app.screen)` for the explicit back button;
    /// the edge-swipe commit's own `asyncAfter(deadline: .now() + 0.22)` is
    /// close enough that waiting for the slightly longer of the two is the
    /// safe choice — waiting too little would reveal the sheet while Event
    /// Detail is still visibly sliding away, exactly the bug being fixed).
    /// Also reused (task 2 follow-up) as the "let the interrupted-swipe's
    /// own spring-back settle first" wait before an interrupted close-swipe
    /// recovers, for the exact same reason.
    private let eventDetailDismissDuration: TimeInterval = 0.28
    /// The ticket's own explicit, additional pause AFTER that animation —
    /// deliberate, not incidental. Task 3 follow-up: shortened from the
    /// original 1.0s to 0.5s (ticket's explicit request to halve every
    /// "slow, deliberate" delay this feature uses) — this single constant
    /// now backs BOTH the Event-Detail-return reveal and the interrupted-
    /// close-swipe reveal (task 2 follow-up), so there is only one place to
    /// tune this going forward, not two that could drift apart.
    private let postDismissRevealDelay: TimeInterval = 0.5
    // The ACTUAL current camera, updated on every settle, so a snapshot saves where the map really is (including after
    // a selection reveal), and reveals keep the current zoom.
    @State private var currentCameraRegion: MKCoordinateRegion?

    /// Seeds every local `@State` directly from a saved snapshot (or plain
    /// defaults) INSIDE `init`, rather than restoring them a moment later
    /// inside `.task`. Root cause of the "abrupt pop-in" reported in bug 2's
    /// follow-up: `.task` runs only after the very first frame has already
    /// been drawn with `.automatic`/`"all"`/`.fraction(0.72)` etc., so a
    /// return-to-map visibly flashed the *default* camera/filters/detent for
    /// one frame before snapping to the *restored* ones a moment later — a
    /// real, visible "reinitialize then jump" rather than a smooth restore.
    /// Seeding here means the very first frame RootView draws for this view
    /// already shows the restored state, including the sheet's own initial
    /// `.presentationDetents` selection — the sheet's native slide-up-from-
    /// bottom presentation animation then plays directly TO the saved
    /// detent, not to the default one first.
    init(restored: MapExploreState?, isPreview: Bool = false, startFocusedOnSearch: Bool = false, isActive: Bool = true, seedQuery: String? = nil, entry: (filters: HomeDiscovery.Filters, forYou: Bool)? = nil) {
        hadRestoredState = restored != nil
        self.seedQuery = seedQuery
        self.isPreview = isPreview
        self.isActive = isActive
        self.startFocusedOnSearch = startFocusedOnSearch
        restoreBubbleProgress = restored != nil ? 0 : 1
        // Bug 2 follow-up: a fresh open has nothing to wait for — reveal
        // immediately, as before. A restored instance starts hidden; `.task`
        // reveals it only after `eventDetailDismissDuration +
        // postDismissRevealDelay` has elapsed. Sheet-reveal-timing fix
        // (2026-09-29): NOT active yet (a live tab-swipe neighbor, or the
        // non-interactive edge-swipe-back peek) also starts hidden,
        // regardless of `restored` — `.onChange(of: isActive)` below reveals
        // it the moment that changes, never early.
        _sheetPresented = State(initialValue: restored == nil && isActive)
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
            _sheetDetent = State(initialValue: MapExploreView.detent(for: restored.sheetFraction))
            _selectedId = State(initialValue: restored.selectedId)
            // The restored camera is already framed. A return from Event Detail brings its committed area back as-is
            // (the first settle is a 'restore', never a new area); "Open in Map" has a camera but no area yet, so its
            // first settle commits the area around that camera ('initial').
            _framed = State(initialValue: true)
            _committedBounds = State(initialValue: restored.committedBounds)
            _pendingReason = State(initialValue: (restored.committedBounds == nil ? .initial : .restore, Date()))
            _pendingScrollToRestoredSelection = State(initialValue: restored.selectedId != nil)
        } else {
            _cameraPosition = State(initialValue: .automatic)
            // Home's hand-off (filters + For You); the dock tab passes none.
            _filters = State(initialValue: entry?.filters ?? HomeDiscovery.Filters())
            _areaContext = State(initialValue: "map")
            _forYouOn = State(initialValue: entry?.forYou ?? false)
            _searchQuery = State(initialValue: seedQuery ?? "")
            _sortByDistance = State(initialValue: false)
            // Layout A (map first, card peek): a fresh open starts at mid, so the map keeps more than half the screen.
            _sheetDetent = State(initialValue: MapExploreView.midDetent)
            _selectedId = State(initialValue: nil)
            _framed = State(initialValue: false)
            _pendingScrollToRestoredSelection = State(initialValue: false)
        }
    }

    @State private var categorySheetOpen = false
    /// Bounded mode: set once the loaded set turned out incomplete (see `.onChange(of: committedBounds)`).
    @State private var boundedMode = false
    private var boundedArea: MapDiscovery.Bounds? {
        guard boundedMode, let committedBounds else { return nil }
        return MapDiscovery.padBounds(committedBounds, factor: 1.5)
    }
    /// Body-text line height, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var searchFieldHeight: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            // Sweep finding (11-realtime-map.md follow-up): this used to
            // read `visibleEvents` (the LIST-filtered set) — meaning
            // changing the category filter could make a SELECTED event's
            // own pin vanish from the map while its card kept floating
            // above the sheet, referencing a pin no longer shown anywhere.
            // Web's own pins have always drawn from the full, unfiltered
            // set regardless of category (only its LIST panel is
            // filtered) — `mapEventsWithCoordinates` brings iOS to the
            // same baseline `selectedEvent` (below) now also uses, so a
            // selection's pin and its card stay consistent with each other
            // through any filter change.
            // Pins are exactly the results (committed area + filters): the same list and count the sheet shows.
            // Phase 4: results grouped for display (price pins, clusters, same-place stacks); they always add up to
            // the count.
            Map(position: $cameraPosition) {
                ForEach(markerGroups) { g in
                    Annotation(g.kind == .pin ? (eventsByID[g.ids[0]]?.name ?? "") : "",
                               coordinate: CLLocationCoordinate2D(latitude: g.lat, longitude: g.lng)) {
                        marker(for: g)
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
            }
            .onMapCameraChange(frequency: .continuous) { _ in cameraMoving() }
            // A tap that lands on the map background (a pin's own
            // `.onTapGesture` in `pin(for:)` claims taps on the pin itself
            // first) clears the selected-event card. This is a plain tap
            // gesture layered alongside Map's own built-in pan/pinch/rotate
            // recognizers, not a replacement for them — both coexist the
            // same way this pattern already does for MapKit elsewhere.
            .onTapGesture { selectedId = nil }
            .ignoresSafeArea()

            // Follow-up (11-realtime-map.md, bug 2): "← Đóng" used to read
            // `font(.system(size: 13, ...))` + `.padding(.horizontal, 12)`
            // — one point larger and two points narrower than "Tìm ở đây"
            // (below, size 12 / horizontal 14) — now matched exactly, so
            // both pills render at the identical intrinsic height (same
            // font size, same 8pt vertical padding both had already).
            // `alignment: .top` on this HStack is the other half of the
            // fix: by default an `HStack` vertically CENTERS its children
            // within the row's own height, and the row's height here is
            // driven by the 38pt-tall compass circle — even with matching
            // font/padding, "← Đóng" would still render centered a few
            // points below the row's top edge (roughly `(38 - ownHeight) /
            // 2`), which is exactly what made it sit lower than "Tìm ở
            // đây" (an independent ZStack child, top-anchored on its own,
            // with no taller sibling to be centered against). Top-aligning
            // this HStack instead means "← Đóng" sits flush at the same
            // top edge as "Tìm ở đây", matching both its position and its
            // size. Both already shared the same `.regularMaterial`
            // background and `app.palette.ink` foreground — no color token
            // actually differed in code, but the differing capsule SIZE
            // made the same translucent material sample a different amount
            // of blurred backdrop, reading as a perceptibly different tint;
            // matching size resolves that as a side effect, without
            // introducing any new color value for either button.
            HStack(alignment: .top) {
                Button { closeMap() } label: {
                    Text(app.T("← Đóng", "← Close"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .nativeGlassCapsule(interactive: true)
                }
                .accessibilityIdentifier("map.back")

                Spacer()

                Button(action: tapCompass) {
                    Text("🧭")
                        .font(.system(size: 17))
                        .frame(width: 38, height: 38)
                        .nativeGlass(Circle(), interactive: true)
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
            // No "Tìm ở đây / Search here": the whole public set is loaded, so the results follow the map by
            // themselves once it settles.

            // Map v5 (note 73): no floating selected card over the map any more. The selection is the first row of
            // the sheet's list (`selectedRow`), so the map above stays clear.
        }
        // The map's full size and top safe area (the Map itself ignores the safe area) for the reference rect.
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { measure(proxy) }
                .onChange(of: proxy.size) { _, _ in measure(proxy) }
        })
        // Map redesign phase 2 (reverses the earlier "selection survives filters" rule, by the owner's spec): the
        // selection lives only while its event is a result (area + filters, plus listed no-location matches). A pan
        // that leaves it outside, or a filter that excludes it, clears it; no other event is opened in its place.
        // Guarded until data and an area exist, so a restored selection is never cleared before its rows arrive.
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
        // Sheet-reveal-timing fix (2026-09-29) — see `isActive`'s own doc
        // comment. Fires exactly once, exactly when a tab-swipe that
        // brought this screen into view actually finishes (RootView flips
        // `app.screen` to it) — never early/mid-drag. Guards
        // `!sheetPresented` so this can't fight the OTHER, unrelated
        // places that already manage `sheetPresented` for their own timing
        // (restore-reveal, close-swipe cancel/confirm).
        .onChange(of: isActive) { _, active in
            guard active, !sheetPresented else { return }
            withAnimation(.easeOut(duration: 0.26)) { sheetPresented = true }
        }
        .onChange(of: sheetDetent) { _, detent in
            // Re-applies the region shift (never a re-zoom or the selection pop) when the sheet grows back over a
            // selected pin. Dropping to peek never moves the camera: that is usually the user's own pan in progress.
            if detent != Self.peekDetent, let ev = selectedEvent { reapplyCameraOffset(for: ev) }
        }
        // Dock on demand (note 73 §1): the floating dock shows only at tall; at peek and mid the map and the sheet
        // get the whole width. Released whenever this screen leaves, so the dock never stays hidden elsewhere.
        .onAppear { syncDock() }
        .onChange(of: dockHidden) { _, _ in syncDock() }
        // City of each loaded event, for city search counts, the area picker and the zoomed-out bubbles.
        .task(id: app.mapEvents.map(\.id)) {
            var out: [String: String] = [:]
            for ev in app.mapEvents {
                if let id = MapDiscovery.cityFor(.init(city: ev.city, stateProvince: ev.stateProvince, countryCode: ev.countryCode,
                                                       lat: ev.lat, lng: ev.lng), cities: MapDiscovery.cities) {
                    out[ev.id] = id
                }
            }
            if out != cityOfEvent { cityOfEvent = out }
        }
        .onChange(of: filters) { _, _ in
            // Filters never move the camera (the old category → density-hotspot flight is gone): the area changes
            // only through the map. B2: a genuine filter change still snaps the sheet to MID. `.onChange` never fires
            // for the value `init` seeded.
            guard !isPreview else { return }
            withAnimation(.easeOut(duration: 0.28)) { sheetDetent = Self.midDetent }
        }
        .onChange(of: app.area) { _, _ in
            // Area picker = a DESTINATION (phase 3): fly to that area's mapped events and commit it once; every
            // filter stays. "Everywhere" or an area with no mapped events leaves the camera where it is (no guessed
            // geometry, never the whole inventory) and the chip reads "Map area".
            guard !isPreview else { return }
            goToPickedArea()
        }
        .onChange(of: app.mapCloseConfirmed) { _, confirmed in
            // Follow-up bug 1 (11-realtime-map.md): a confirmed close used
            // to rely ENTIRELY on the `.scaleEffect`/`.offset` transform
            // below (driven by `app.mapCloseSwipeProgress`) to fake a
            // "collapse" — but shrinking the CONTENT that way, while the
            // sheet stayed technically `isPresented: true` the whole time,
            // let `.presentationDetents` interpret the shrinking content as
            // a resize request and re-snap through each of its three fixed
            // detents (tall → mid → peek) on the way down, instead of one
            // continuous motion to fully closed. Flipping `sheetPresented`
            // to `false` here triggers the REAL, system-native sheet
            // dismiss — categorically a different transition from a detent
            // change, guaranteed to animate straight from wherever the
            // sheet currently is to fully off-screen, never re-snapping to
            // a named detent along the way. The `.scaleEffect`/`.offset`
            // transform is untouched and keeps playing underneath/alongside
            // this as a purely decorative flourish on the content.
            guard confirmed else { return }
            withAnimation(.easeOut(duration: 0.22)) { sheetPresented = false }
        }
        .sheet(isPresented: $sheetPresented) {
            sheetContent
                // The area picker is an overlay INSIDE this sheet (not a
                // second nested sheet), so the event list stays in place
                // underneath it instead of being covered.
                .overlay {
                    if locationPickerOpen {
                        LocationPickerSheet(isPresented: $locationPickerOpen, topContent: AnyView(areaPickerCities))
                            .environmentObject(app)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: locationPickerOpen)
                .onChange(of: locationPickerOpen) { _, open in
                    // Give the card room if the sheet is peeked/collapsed.
                    if open && sheetDetent != Self.tallDetent {
                        withAnimation(.easeOut(duration: 0.28)) { sheetDetent = Self.tallDetent }
                    }
                }
                // ANIMATION REQUIREMENT (11-realtime-map.md follow-up): a
                // soft "bubble" settle layered ON TOP of the system's own
                // slide-up-from-bottom sheet presentation — SwiftUI doesn't
                // expose control over that presentation's own physics, so
                // this doesn't try to replace it, only adds a subtle extra
                // overshoot-then-settle via a genuine `.interpolatingSpring`
                // driven by `restoreBubbleProgress`. That value starts at 0
                // ONLY when this instance was constructed from a restored
                // snapshot (`init`) and animates to 1 exactly once, in
                // `postDismissRevealTask` below (fired at the same moment
                // `sheetPresented` itself flips true) — never touched by
                // polling or filter changes, so it can only ever play on an
                // actual restore/return, never while just staying on the
                // screen. A fresh (non-restored) open starts at 1 already,
                // so this has no effect there at all.
                .scaleEffect(0.965 + 0.035 * restoreBubbleProgress, anchor: .top)
                .offset(y: (1 - restoreBubbleProgress) * 18)
                // Task 1 (11-realtime-map.md follow-up): the sheet visibly
                // shrinks/bubbles down as the user edge-swipes Map Explore
                // closed toward Home, tracking `app.mapCloseSwipeProgress`
                // — RootView's own edge-swipe progress, mirrored (not
                // re-tracked) into `AppState` — LIVE (0 at rest, 1 at full
                // commit). No `.animation(value:)` here on purpose: the
                // live-drag phase must track the finger with zero lag, and
                // the two ENDED outcomes deliberately animate at different
                // speeds — a confirmed close (swipe past the threshold, or
                // the "← Đóng" button, `closeMap()` below) is fast/snappy
                // (both now call the one shared `AppState.confirmMapExploreClose()`,
                // 0.22s); an interrupted swipe (released early) instead
                // hides the sheet and hands off to the SAME delayed-reveal
                // recovery Event Detail returns use (`RootView.cancelMapCloseSwipe()`
                // → `app.mapCloseSwipeCancelled` → this view's own
                // `.onChange(of: app.mapCloseSwipeCancelled)`, below) — this
                // view has no say in which of the two the swipe took; it
                // purely inherits whichever transaction last wrote this
                // value.
                .scaleEffect(1 - 0.15 * app.mapCloseSwipeProgress, anchor: .bottom)
                .offset(y: 70 * app.mapCloseSwipeProgress)
                // Map v6 (note 74): from peek one upward drag lands at FULL (mid is left out of the set while at peek);
                // everywhere else all three. A tap on the peek strip still goes to mid.
                .presentationDetents(sheetDetent == Self.peekDetent ? [Self.peekDetent, Self.tallDetent]
                                                                    : [Self.peekDetent, Self.midDetent, Self.tallDetent],
                                     selection: $sheetDetent)
                // Opaque content surface: without this the system sheet is glass at partial detents and the list
                // sat on the map (device report). Glass stays on the map controls and the dock.
                .presentationBackground(app.palette.paper)
                // Follow-up bug 4 (11-realtime-map.md): reverted back to the
                // SYSTEM's own visible drag indicator. The prior pass's
                // custom `dragHandle` (a `DragGesture` on a small capsule,
                // with the system indicator hidden) still failed on a real
                // device: dragging over the filter row resized the sheet,
                // and dragging the custom handle itself did nothing.
                // `.presentationDragIndicator(.hidden)` only hides the
                // drawn affordance — the system's own resize gesture
                // recognizer is a UIKit-level recognizer attached to the
                // sheet's presenting view controller, entirely OUTSIDE
                // SwiftUI's own gesture graph; a SwiftUI `.highPriorityGesture`
                // has no authority over it, and once hidden, that
                // recognizer's resize-eligible area is no longer scoped to
                // a small reserved strip — it can activate from anywhere
                // `.presentationContentInteraction(.scrolls)` doesn't
                // consider "scrollable" (a horizontal-only filter row
                // included), which is exactly the reported symptom. Using
                // the system's OWN visible grabber sidesteps this entirely:
                // there is no second, hidden recognizer to compete with —
                // dragging it is guaranteed to resize the sheet, and
                // dragging content elsewhere is guaranteed not to, because
                // it's the same one, singular, Apple-implemented mechanism
                // this trick has always relied on. `dragHandle` (the custom
                // capsule + its gesture) is removed entirely — see below.
                .presentationDragIndicator(.visible)
                // Kept — still needed so the List scrolls normally at MID
                // instead of being claimed by the (now visible, but still
                // reserved-to-its-own-strip) system resize recognizer.
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
        }
        .task {
            // Follow-up (edge-swipe race): the non-interactive "peeked at"
            // copy RootView renders during an edge-swipe drag must never
            // run any of this — see `isPreview`'s own doc comment for the
            // confirmed bug this caused (a mid-drag, possibly-aborted
            // preview racing the real instance to load data and clear the
            // one-shot snapshot).
            guard !isPreview else { return }
            // Bug 2: the actual restore now happens in `init` (see its own
            // comment) — by the time this runs, `cameraPosition`/filters/
            // `sheetDetent`/`selectedId` are already correct. This only
            // decides whether density-hotspot centering should run at all
            // (never for a restored instance — re-running it would discard
            // exactly where the user had the map) and clears the snapshot
            // now that this instance has fully consumed it.
            await app.loadMapEvents()
            if hadRestoredState {
                app.mapExploreState = nil
                // Bug 2 follow-up: the sheet/card must not reveal until
                // Event Detail's own dismissal animation has fully finished
                // AND the ticket's explicit additional delay has elapsed —
                // never early, never behind the outgoing screen.
                scheduleSheetReveal(after: eventDetailDismissDuration + postDismissRevealDelay)
            } else {
                frameFirstOpen()
                // The one-shot FAB intent is consumed unconditionally once
                // this fresh-open branch runs at all (not by a callback
                // that fires only once focus actually lands) — the next
                // `MapExploreView` this app constructs (a later dock-tab
                // open, another restore) never reads a stale `true` left
                // over from this one.
                if startFocusedOnSearch { app.mapExploreFocusSearch = false }
                if seedQuery != nil { app.mapExploreSeedQuery = nil }
                app.mapExploreEntry = nil // the Home hand-off is read once
            }
        }
        .onChange(of: app.mapCloseSwipeCancelled) { _, cancelled in
            // Task 2 (11-realtime-map.md follow-up): an interrupted
            // left-edge swipe never navigates anywhere (RootView's own
            // gesture code already guarantees that — see its own comment)
            // — it hands off here instead, treating the interruption
            // exactly like a return from Event Detail: hide the sheet/card
            // immediately, then reveal them again after the same delay,
            // reusing `scheduleSheetReveal(after:)` verbatim rather than a
            // second recovery path.
            guard cancelled else { return }
            app.mapCloseSwipeCancelled = false // one-shot pulse — consume immediately
            guard !isPreview else { return }
            postDismissRevealTask?.cancel()
            sheetPresented = false
            restoreBubbleProgress = 0
            scheduleSheetReveal(after: eventDetailDismissDuration + postDismissRevealDelay)
        }
        .onDisappear {
            // Bug 2 follow-up: guards the delayed reveal above — cancelling
            // here means a torn-down instance (the user left again before
            // the delay elapsed) can never fire `sheetPresented = true`
            // onto whatever's on screen now.
            postDismissRevealTask?.cancel()
            app.cancelRootPull()
            BottomTabBarOverlay.shared.setSheetOpen(dockToken, false)
        }
        // Bounded mode (phase 4): only when the public set is larger than the cap. Each committed area then loads its
        // own events (padded ×1.5, exact count, newest load wins); the "Showing N of M" line stays honest. With the
        // set complete (production today) this never runs and panning stays network-free.
        .onChange(of: committedBounds) { _, area in
            guard !isPreview, area != nil, boundedMode || app.mapEvents.count < app.mapEventsTotal else { return }
            boundedMode = true
            Task { await app.loadMapEvents(bounds: boundedArea) }
        }
        // Freshness: the whole set again (or this area's, in bounded mode). Camera, area, filters, selection and list
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
            // Only recenters when the compass button itself triggered the
            // permission grant (below) — a background coords refresh must
            // never move the map on its own; the compass is the only way
            // this screen ever centers on the user.
            guard awaitingRecenterAfterGrant, newValue != nil else { return }
            awaitingRecenterAfterGrant = false
            recenterOnUser()
        }
    }

    // MARK: - Dock on demand + camera reveal

    private var dockHidden: Bool { isActive && !isPreview && sheetDetent != Self.tallDetent }

    private func syncDock() {
        guard !isPreview else { return }
        BottomTabBarOverlay.shared.setSheetOpen(dockToken, dockHidden)
    }

    /// The share of the map's height a detent covers (peek is a fixed height).
    private func sheetCover(_ detent: PresentationDetent) -> Double {
        if detent == Self.peekDetent {
            let h = Double(mapSize.height > 0 ? mapSize.height : UIScreen.main.bounds.height)
            return Double(Self.peekHeight) / max(1, h)
        }
        if detent == Self.midDetent { return 0.45 }
        let h = Double(mapSize.height > 0 ? mapSize.height : UIScreen.main.bounds.height)
        return min(0.95, Double(Self.fullHeight) / max(1, h))
    }

    private func reapplyCameraOffset(for ev: MapEventRow) {
        reveal(ev, duration: 0.3)
    }

    /// A REVEAL: bring the pin to the middle of the free map strip (below the top controls, above the sheet) at the
    /// CURRENT zoom. Marked 'reveal', so it never redefines the search area, the list or the count. No card to clear
    /// any more (note 73), so only the sheet top matters.
    private func reveal(_ ev: MapEventRow, duration: Double, detent: PresentationDetent? = nil) {
        guard let lat = ev.lat, let lng = ev.lng else { return }
        let span = currentCameraRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        let h = Double(mapSize.height > 0 ? mapSize.height : UIScreen.main.bounds.height)
        let top = (Double(safeTop) + Self.topControlsHeight) / max(1, h)
        let desiredScreenFraction = (top + (1 - sheetCover(detent ?? sheetDetent))) / 2
        let latShift = span.latitudeDelta * (0.5 - desiredScreenFraction)
        moveCamera(.reveal, to: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat - latShift, longitude: lng), span: span),
                   duration: duration)
    }

    /// Pan → peek (note 73 §4): the user's own drag or pinch drops the sheet from mid to peek as it starts. Any move
    /// with a fresh programmatic reason (reveal, restore, cluster, destination…) never does; tall stays tall.
    private func cameraMoving() {
        guard framed, !isPreview, sheetPresented, sheetDetent == Self.midDetent,
              Date().timeIntervalSince(lastSettleAt) > 0.3 else { return }
        if let p = pendingReason, Date().timeIntervalSince(p.at) < (p.reason.commits ? 4 : 1.5) { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { sheetDetent = Self.peekDetent }
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

    /// The reference rect (below the top controls, above the PEEK sheet) of the settled camera becomes the area.
    private func commitArea(_ rect: MKMapRect, reason: MapDiscovery.Reason) {
        let nw = MKMapPoint(x: rect.minX, y: rect.minY).coordinate
        let se = MKMapPoint(x: rect.maxX, y: rect.maxY).coordinate
        let full = MapDiscovery.Bounds(north: nw.latitude, south: se.latitude, east: se.longitude, west: nw.longitude)
        let w = Double(max(1, mapSize.width)), h = Double(max(1, mapSize.height))
        let ref = MapDiscovery.referenceRect(width: w, height: h, topInset: Double(safeTop) + Self.topControlsHeight,
                                            bottomInset: Double(Self.peekHeight) + Self.legalReserve)
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

    /// Back/compass row (8 top padding + 38 control + 12 gap) and the strip kept for the Apple Maps legal label.
    private static let topControlsHeight: Double = 58
    /// Side margin of a fit: half the widest pin (category icon + price, note 73) plus a gap, so an edge event's pin is
    /// never cut by the screen edge. At 40 the wider v5 pins hung off the edge and MapKit left them out of the
    /// accessibility tree (MapViewportUITests counted 4 markers for 5 results).
    private static let markerSidePadding: Double = 64
    private static let legalReserve: Double = 26

    /// A camera region that fits `bounds` into the free area above the MID sheet (below the top controls).
    private func fittedRegion(_ bounds: MapDiscovery.Bounds, maxZoom: Double = 14) -> MKCoordinateRegion {
        let w = Double(max(320, mapSize.width)), h = Double(max(560, mapSize.height == 0 ? UIScreen.main.bounds.height : mapSize.height))
        let pad = MapDiscovery.Padding(top: Double(safeTop) + Self.topControlsHeight + 16, bottom: h * 0.45 + Self.legalReserve + 16,
                                       left: Self.markerSidePadding, right: Self.markerSidePadding)
        let cam = MapDiscovery.fitCamera(bounds, width: w, height: h, padding: pad, maxZoom: maxZoom)
        let view = MapDiscovery.viewBounds(center: cam.center, zoom: cam.zoom, width: w, height: h)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: cam.center.lat, longitude: cam.center.lng),
                                  span: MKCoordinateSpan(latitudeDelta: view.north - view.south, longitudeDelta: view.east - view.west))
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
            moveCamera(.initial, to: fittedRegion(box), duration: 0)
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

    // MARK: - Bug 2: retained navigation state across Event Detail

    /// One of the three literal `.presentationDetents` fractions, read back
    /// from a stored `Double` — `static` so `init` can call it before `self`
    /// is fully initialized.
    /// Peek is stored as 0.12 (its old fraction) so saved snapshots keep their meaning.
    private static func detent(for fraction: Double) -> PresentationDetent {
        if fraction == 0.12 { return peekDetent }
        if fraction == 0.45 { return midDetent }
        return tallDetent
    }

    /// Snapshots everything this view owns right before handing off to the
    /// full-screen Event Detail screen, so returning restores it instead of
    /// re-initializing from scratch. Saved onto `AppState` (not kept only
    /// here) because RootView recreates this whole view the instant
    /// `screen` changes away from `.mapExplore`.
    /// Snapshot of everything this screen owns, shared by Event Detail and Edit preferences.
    private func saveSnapshot() {
        // Bug 3 follow-up: `currentCameraRegion` (updated on EVERY camera
        // callback), not `lastQueriedRegion` (frozen after its first call —
        // see `onMapCameraChange`'s own comment). Reading the frozen value
        // here was the confirmed root cause of the saved snapshot's camera
        // reflecting wherever the map was when this instance was first
        // constructed, rather than wherever `selectEvent(_:)` had since
        // flown it to — on restore, that stale region could easily read as
        // "centered on the wrong place" (e.g. a hotspot/user-adjacent
        // region from earlier in this same session), not the selected
        // event.
        let region = currentCameraRegion
        app.mapExploreState = MapExploreState(
            cameraCenterLat: region?.center.latitude ?? 10.7769,
            cameraCenterLng: region?.center.longitude ?? 106.7009,
            cameraSpanLat: region?.span.latitudeDelta ?? 0.05,
            cameraSpanLng: region?.span.longitudeDelta ?? 0.05,
            sheetFraction: sheetFraction,
            catFilter: catFilter,
            openNowOnly: openNowOnly,
            sortByDistance: sortByDistance,
            selectedId: selectedId,
            forYou: forYouActive,
            searchQuery: searchQuery,
            committedBounds: committedBounds,
            filters: filters,
            areaContext: areaContext,
            cityContextID: cityContextID
        )
    }

    private func editPreferences() {
        saveSnapshot()
        Haptics.selection()
        app.openEventPreferences(returnTo: .mapExplore)
    }

    private func openEventDetail(_ id: String) {
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

    /// Task 2 (11-realtime-map.md follow-up): schedules the delayed sheet
    /// reveal — shared verbatim between a genuine restore from Event
    /// Detail (`.task`'s `hadRestoredState` branch) and an interrupted
    /// close-swipe's recovery (`.onChange(of: app.mapCloseSwipeCancelled)`),
    /// per the ticket's explicit "reuse that exact same restore path, not
    /// a new one." Held in `postDismissRevealTask` so `.onDisappear` (or a
    /// second call to this same method) can cancel a still-pending one —
    /// if the user leaves this instance again (or interrupts a second
    /// swipe) before the delay completes, it must never reveal stale UI
    /// onto whatever's on screen by then.
    private func scheduleSheetReveal(after delay: TimeInterval) {
        postDismissRevealTask?.cancel()
        postDismissRevealTask = Task {
            let delayNanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            // Tab-swipe/isActive race fix (2026-09-29) — this used to
            // reveal unconditionally once its own timer elapsed, regardless
            // of whether this instance was even the genuinely active
            // screen yet. A restored snapshot left over from an earlier
            // Event-Detail visit, combined with this view ALSO being
            // mounted early as a tab-swipe NEIGHBOR (deliberately, to
            // preload data — see `isActive`'s own doc comment), meant this
            // timer could fire mid-drag, or even after an aborted swipe
            // sprang back to the previous screen, popping the sheet up in
            // a state totally disconnected from the actual screen
            // transition — the reported "sheet overlaps the previous
            // screen"/"jumbled" glitch. If not active yet, do nothing here
            // — `isActive`'s own `.onChange` handler reveals it once the
            // transition genuinely finishes instead. Never regresses the
            // ordinary "return from Event Detail" case this was built for:
            // `isActive` defaults/settles `true` immediately whenever this
            // view isn't a tab-swipe neighbor at all.
            guard isActive else { return }
            sheetPresented = true
            // ANIMATION REQUIREMENT: the restore-only "bubble" spring —
            // fires at the exact same moment the sheet/card reveal, for
            // both the callers of this method.
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 14)) {
                restoreBubbleProgress = 1
            }
        }
    }

    // MARK: - Pin/list selection: camera zoom + compact in-map preview card

    /// The selection, only while it is one of the results (area + filters) or a listed no-location match.
    private var selectedEvent: MapEventRow? {
        guard let selectedId, selectableIDs.contains(selectedId) else { return nil }
        return app.mapEvents.first { $0.id == selectedId }
    }

    private var selectableIDs: [String] { (visibleEvents + noLocationMatches).map(\.id) }

    /// How much of the screen the bottom sheet currently covers, read back
    /// from `sheetDetent` (a `PresentationDetent` doesn't expose its own
    /// fraction, but it IS `Equatable`, so comparing against the same three
    /// literal fractions `sheetContent` declares works directly).
    private var sheetFraction: Double {
        if sheetDetent == Self.peekDetent { return 0.12 }
        if sheetDetent == Self.midDetent { return 0.45 }
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
        let isNewSelection = selectedId != ev.id
        selectedId = ev.id

        // Search-result-selection fix pass (2026-09-28) — a `List` row's
        // own tap gesture never sends `.focused($searchFieldFocused)` any
        // "tap outside" signal the way surrounding chrome normally would,
        // so picking a result while the keyboard was up left it up
        // indefinitely. Resigning here, at the single shared selection
        // path (pins and list rows both call this), covers every way a
        // result can be picked.
        if searchFieldFocused { searchFieldFocused = false }
        rememberSearch()

        // Map v5 (note 73 §2): the selection is the first row of the sheet, so the sheet always settles at MID (from
        // peek, so the row is visible; from tall, so the pin is), the list scrolls back to its top, and the pin is
        // revealed above the mid sheet at the current zoom (never a new search area).
        if sheetDetent != Self.midDetent {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheetDetent = Self.midDetent }
        }
        listTopToken += 1
        reveal(ev, duration: 0.55, detent: Self.midDetent)

        guard isNewSelection, ev.lat != nil else { return }
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

    /// The public event link Event Detail's Share uses (/api/photo-share?eid=, Open Graph preview).
    private func shareURL(_ ev: MapEventRow) -> URL? {
        ev.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            .flatMap { URL(string: "\(AppConfig.publicWebOrigin)/api/photo-share?eid=\($0)") }
    }

    /// Map v5 (note 73 §2): the selected event as the FIRST row of the sheet's list (replaces the floating card):
    /// bigger photo, title, venue date · time · area, price + seat pill, ✕, then 44 pt pills (Directions · View details
    /// · Share). Same-place stacks keep the ‹ 1/3 › switcher here.
    @ViewBuilder
    private func selectedRow(_ ev: MapEventRow) -> some View {
        let cosmetic = EventCatalog.find(ev.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // The event's own photo first; the bundled catalogue only for a real demo id (see loadMapEvents).
                if let url = app.mapEventCoverURLs[ev.id] {
                    CatalogPhoto(path: url.absoluteString, height: 80, width: 80, cornerRadius: 12).zoomSource(ev.id)
                } else if let path = cosmetic?.img {
                    CatalogPhoto(path: path, height: 80, width: 80, cornerRadius: 12).zoomSource(ev.id)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(ev.name).font(.body.weight(.bold)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { selectedId = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(app.palette.ink2)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, -12).padding(.trailing, -12)
                        .accessibilityLabel(app.T("Bỏ chọn", "Clear selection"))
                        .accessibilityIdentifier("map.selectedRow.close")
                    }
                    // Venue date · time, the same source Event Detail reads (starts_at in events.tz), then the area.
                    Text([eventWhen(ev), ev.area].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(priceLine(ev)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        // Real fill only; no fill row means no seat claim at all.
                        seatPill(ev, id: "map.selectedRow.seats")
                        Spacer(minLength: 0)
                        // Several events at this same place: step through them here (zooming can never split a stack).
                        let stackIDs = stackIDs(of: ev)
                        if stackIDs.count > 1, let i = stackIDs.firstIndex(of: ev.id) {
                            HStack(spacing: 0) {
                                Button { selectedId = stackIDs[(i - 1 + stackIDs.count) % stackIDs.count] } label: {
                                    Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel(app.T("Sự kiện trước ở đây", "Previous event here"))
                                .accessibilityIdentifier("map.selectedRow.stackPrev")
                                Text("\(i + 1)/\(stackIDs.count)").font(.footnote).foregroundStyle(app.palette.ink2)
                                    .accessibilityIdentifier("map.selectedRow.stack")
                                Button { selectedId = stackIDs[(i + 1) % stackIDs.count] } label: {
                                    Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .accessibilityLabel(app.T("Sự kiện tiếp theo ở đây", "Next event here"))
                                .accessibilityIdentifier("map.selectedRow.stackNext")
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, -12)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                // Directions: the same public venue link Event Detail opens; only with a map location.
                if let url = ev.mapsURL {
                    Link(destination: url) {
                        Label(app.T("Chỉ đường", "Directions"), systemImage: "location.north.line")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(app.palette.clayBg, in: Capsule())
                            .foregroundStyle(app.palette.clay)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.selectedRow.directions")
                }
                Button(action: { openEventDetail(ev.id) }) {
                    Text(app.T("Xem chi tiết", "View details"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(app.palette.ink, in: Capsule())
                        .foregroundStyle(app.palette.paper)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.selectedRow.details")
                if let url = shareURL(ev) {
                    ShareLink(item: url, subject: Text(ev.name)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(app.palette.surface2, in: Circle())
                            .foregroundStyle(app.palette.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Chia sẻ", "Share"))
                    .accessibilityIdentifier("map.selectedRow.share")
                }
            }
        }
        .padding(12)
        .background(app.palette.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.ink.opacity(0.85), lineWidth: 1.5))
        .foregroundStyle(app.palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.selectedRow")
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

    // MARK: - Pins

    /// Markers are exactly the results (committed area + filters), grouped for display only (phase 4): each result is
    /// in one price pin, cluster or same-place stack. A selected event is pulled out of its cluster so it stays
    /// visible; at the same place it stays in its stack (the card steps through it).
    private var markerGroups: [MapDiscovery.Group] {
        let located = visibleEvents.compactMap { ev -> MapDiscovery.GroupPoint? in
            guard let lat = ev.lat, let lng = ev.lng else { return nil }
            return MapDiscovery.GroupPoint(id: ev.id, lat: lat, lng: lng)
        }
        let sel = located.first { $0.id == selectedId }
        let selStacked = sel.map { MapDiscovery.sameSpotIDs(located, lat: $0.lat, lng: $0.lng).count > 1 } ?? false
        let groupable = (sel != nil && !selStacked) ? located.filter { $0.id != selectedId } : located
        // Map v5: zoomed out below city level, one bubble per city (the rest still cluster); every result in one marker.
        let cities = cityOfEvent
        var groups = MapDiscovery.cityGroups(groupable, zoom: cameraZoom, cityOf: { cities[$0.id] }, cities: MapDiscovery.cities)
        if let sel, !selStacked {
            groups.append(.init(kind: .pin, ids: [sel.id], lat: sel.lat, lng: sel.lng, bounds: nil))
        }
        return groups
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

    @ViewBuilder
    private func marker(for g: MapDiscovery.Group) -> some View {
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
                .accessibilityLabel(stack ? app.T("\(n) sự kiện cùng địa điểm", "\(n) events at this place")
                                          : app.T("\(n) sự kiện ở đây, phóng to", "\(n) events here, zoom in"))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("map.\(g.kind.rawValue).\(g.ids[0])")
                .accessibilityValue("\(n)")
                .onTapGesture {
                    if stack, let first = eventsByID[g.ids[0]] { selectEvent(first) } else { zoomToCluster(g) }
                }
        }
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

    private func goToCity(_ id: String) {
        guard let city = MapDiscovery.city(id) else { return }
        Haptics.selection()
        rememberSearch()
        searchFieldFocused = false
        searchQuery = ""
        cityContextID = id
        locationPickerOpen = false
        moveCamera(.destination, to: cityRegion(city), duration: 0.8)
        if sheetDetent != Self.midDetent {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheetDetent = Self.midDetent }
        }
    }

    /// Tap a cluster: zoom in to fit its events (at least one level) — explicit navigation, one new area.
    private func zoomToCluster(_ g: MapDiscovery.Group) {
        guard let box = g.bounds else { return }
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
        let isPopping = ev.id == poppingId
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
        .scaleEffect(isPopping ? 1.2 : (isSelected ? 1.1 : 1))
        .zIndex(isSelected ? 1 : 0)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ev.name), \(label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("map.pin.\(ev.id)")
        .onTapGesture { selectEvent(ev) }
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

    /// Map v5 (note 73): peek = a strip that says how many events are in view and what is filtered (tap = mid); mid
    /// and tall = a fixed filter header (compact once the list scrolls) above the scrolling list.
    private var sheetContent: some View {
        VStack(spacing: 0) {
            if sheetDetent == Self.peekDetent {
                peekStrip
            } else {
                filterHeader
                if searchFieldFocused && searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchSuggestions
                } else {
                    countBlock
                    resultsList
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .onChange(of: searchFieldFocused) { _, focused in
            // Focus from a tap on the field at mid / full: Cancel returns to that same position.
            if focused, searchOrigin == nil { searchOrigin = sheetDetent }
            if !focused { searchOrigin = nil }
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
    }

    // MARK: - Active filter summary (peek strip + compact sticky header; MapDiscovery.activeFilterSummary)

    private var filterSummary: (tokens: [MapDiscovery.SummaryToken], count: Int) {
        MapDiscovery.activeFilterSummary(filters, forYou: forYouActive, query: searchQuery)
    }

    private func summaryLabel(_ t: MapDiscovery.SummaryToken) -> String {
        switch t {
        case .query(let q): return "\"\(q)\""
        case .cat(let key):
            return HomeDiscovery.categories.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
        case .forYou: return app.T("Dành cho bạn", "For You")
        case .date(let key):
            if key.hasPrefix("on:") {
                let parts = key.dropFirst(3).split(separator: "-")
                return parts.count == 3 ? "\(parts[2])/\(parts[1])" : app.T("Chọn ngày", "Pick a date")
            }
            return HomeDiscovery.dateLabels[key].map { app.T($0.vi, $0.en) } ?? key
        case .free: return app.T("Miễn phí", "Free")
        case .price(let lo, let hi, let currency):
            func money(_ v: Int) -> String { EventMarket.formatMoneyShort(v, currency: currency) }
            switch (lo, hi) {
            case let (a?, b?): return "\(money(a))–\(money(b))"
            case let (a?, nil): return "≥ \(money(a))"
            case let (nil, b?): return "≤ \(money(b))"
            default: return ""
            }
        case .seatsLeft: return app.T("Còn chỗ", "Seats left")
        case .almostFull: return app.T("Sắp hết chỗ", "Almost full")
        case .types(let n): return app.T("+\(n) bộ lọc", n == 1 ? "+1 filter" : "+\(n) filters")
        }
    }

    private func summaryText(_ s: (tokens: [MapDiscovery.SummaryToken], count: Int)) -> String {
        s.tokens.map(summaryLabel).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Peek (notes 73 §4 + 74): "N events in this map area" + the one-line filter summary (+ Clear) — tap = mid —
    /// then a row of quick chips: search (opens the search at full, keyboard up), For You, Tonight, Weekend, the top
    /// categories with counts, All filters. A chip applies at once and opens the list at mid.
    private var peekStrip: some View {
        let summary = filterSummary
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                resultCountLine
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease").font(.footnote).foregroundStyle(app.palette.ink2)
                        .accessibilityHidden(true)
                    Text(summary.count > 0 ? summaryText(summary) : app.T("Chưa lọc", "No filters"))
                        .font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(1)
                        .accessibilityIdentifier("map.peekSummary")
                    if summary.count > 0 {
                        Button { Haptics.selection(); clearFilters() } label: {
                            Text(app.T("Xoá", "Clear")).font(.footnote.weight(.semibold)).foregroundStyle(app.palette.clay)
                                .padding(.horizontal, 6).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -12)
                        .accessibilityIdentifier("map.peekSummary.clear")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { showMid() }
            peekChips
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: app.T("Mở danh sách", "Show the list")) { showMid() }
        .accessibilityIdentifier("map.peek")
    }

    /// The most useful categories in this map area right now (most results first, at most three, none at 0).
    private var topCategories: [(key: String, vi: String, en: String, n: Int)] {
        let counts = categoryCountMap
        return HomeDiscovery.categories.filter { $0.key != "all" }
            .map { (key: $0.key, vi: $0.vi, en: $0.en, n: counts[$0.key] ?? 0) }
            .filter { $0.n > 0 || catFilter == $0.key }
            .enumerated().sorted { a, b in a.element.n != b.element.n ? a.element.n > b.element.n : a.offset < b.offset }
            .prefix(3).map(\.element)
    }

    private var peekChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { openSearch() } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(app.palette.ink, in: Circle())
                        .foregroundStyle(app.palette.paper)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Tìm kiếm", "Search"))
                .accessibilityIdentifier("map.peek.search")
                if hasForYouPrefs {
                    chip(active: forYouActive, id: "map.peek.chip.foryou") {
                        Haptics.selection(); forYouOn.toggle(); showMid()
                    } label: {
                        Image(systemName: "star.fill").font(.caption2).accessibilityHidden(true)
                        Text(app.T("Dành cho bạn", "For You"))
                    }
                }
                ForEach([("tonight", "Tối nay", "Tonight"), ("weekend", "Cuối tuần", "Weekend")], id: \.0) { opt in
                    chip(active: filters.date == opt.0, id: "map.peek.chip.\(opt.0)") {
                        Haptics.selection()
                        filters.date = filters.date == opt.0 ? "any" : opt.0
                        showMid()
                    } label: {
                        Text(app.T(opt.1, opt.2))
                    }
                }
                ForEach(topCategories, id: \.key) { cat in
                    chip(active: catFilter == cat.key, id: "map.peek.chip.\(cat.key)") {
                        Haptics.selection()
                        catFilter = catFilter == cat.key ? "all" : cat.key
                        showMid()
                    } label: {
                        Image(systemName: CategoryGlyph.symbol(cat.key)).font(.footnote).accessibilityHidden(true)
                        Text(app.T(cat.vi, cat.en))
                        Text("\(cat.n)").monospacedDigit().opacity(0.6)
                    }
                    .accessibilityLabel(app.T("\(cat.vi), \(cat.n) sự kiện", "\(cat.en), \(cat.n) events"))
                }
                chip(active: sheetFilterCount > 0, id: "map.peek.allFilters") { filterSheetOpen = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.footnote).accessibilityHidden(true)
                    Text(app.T("Tất cả bộ lọc", "All filters") + (sheetFilterCount > 0 ? " · \(sheetFilterCount)" : ""))
                }
            }
            .padding(.horizontal, 16)
        }
        .rootSwipeExclusion("mapPeekChips")
    }

    // MARK: - Search (note 74 §8)

    /// Peek's search button: the sheet to FULL (the keyboard covers the lower ~40 %, so mid would hide the results)
    /// with the field focused; Cancel goes back to where it came from.
    private func openSearch() {
        Haptics.selection()
        searchOrigin = sheetDetent
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheetDetent = Self.tallDetent }
        // The field mounts with the full-sheet content; focus it once it is there.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { searchFieldFocused = true }
    }

    private func cancelSearch() {
        let back = searchOrigin
        searchOrigin = nil
        searchFieldFocused = false
        if let back, back != sheetDetent {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheetDetent = back }
        }
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
                        ForEach([("tonight", "Tối nay", "Tonight"), ("weekend", "Cuối tuần", "Weekend")], id: \.0) { opt in
                            chip(active: filters.date == opt.0, id: "map.search.quick.\(opt.0)") {
                                searchFieldFocused = false
                                filters.date = filters.date == opt.0 ? "any" : opt.0
                            } label: { Text(app.T(opt.1, opt.2)) }
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

    private func showMid() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { sheetDetent = Self.midDetent }
    }

    // MARK: - Sticky header (note 73 §3)

    /// Search + categories + chips stay above the list. Once the list scrolls past its first row they fold into ONE
    /// line saying what is filtered; with nothing filtered only the search field stays.
    @ViewBuilder
    private var filterHeader: some View {
        let summary = filterSummary
        let compact = listScrolled
        VStack(spacing: 0) {
            if !(compact && summary.count > 0) { searchRow }
            if compact {
                if summary.count > 0 { compactSummaryLine(summary) }
            } else {
                categoryRow
                chipRow
                if forYouActive {
                    Button { editPreferences() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .semibold))
                            Text(app.T("Chỉnh sở thích của bạn", "Edit preferences"))
                                .font(.system(size: 12.5, weight: .semibold)).underline()
                        }
                        .padding(.horizontal, 16).padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.foryou.editPrefs")
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: compact)
    }

    private func compactSummaryLine(_ summary: (tokens: [MapDiscovery.SummaryToken], count: Int)) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.selection()
                listScrolled = false
                listTopToken += 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(summaryText(summary)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(summary.count)").font(.caption.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                        .background(app.palette.ink, in: Capsule())
                        .foregroundStyle(app.palette.paper)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.T("Bộ lọc: \(summaryText(summary)). Mở bộ lọc", "Filters: \(summaryText(summary)). Show filters"))
            .accessibilityIdentifier("map.filterSummary")
            Button { Haptics.selection(); clearFilters() } label: {
                Text(app.T("Xoá", "Clear")).font(.subheadline.weight(.semibold)).foregroundStyle(app.palette.clay)
                    .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.filterSummary.clear")
        }
        .padding(.horizontal, 12)
        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private var searchField: some View {
        // Map search-focus fix (2026-09-28, fifth pass) — `FocusableTextField` (Components.swift), not SwiftUI's own
        // `TextField` + `@FocusState`: `@FocusState` never delivered programmatic focus to this field on a real device,
        // while the wrapped `UITextField`'s `becomeFirstResponder()` does. Autofocused on arrival from Home's search
        // (`startFocusedOnSearch`).
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).opacity(0.55)
            FocusableTextField(
                text: $searchQuery,
                isFirstResponder: $searchFieldFocused,
                // The matcher covers name, category, area, host and description (Search.swift); cities come from
                // cities.json (note 73).
                placeholder: app.T("Tìm tên, loại, khu vực, thành phố…", "Search name, type, area, city…"),
                font: .preferredFont(forTextStyle: .body),
                onSubmit: { rememberSearch() }
            )
            // A UITextField has no intrinsic height cap here; a min height let it fill the sheet.
            .frame(height: searchFieldHeight)
            .accessibilityIdentifier("map.searchInput")
            .onAppear {
                if startFocusedOnSearch && !hadRestoredState {
                    searchFieldFocused = true
                }
            }
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).opacity(0.5)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.trailing, -12)
                .accessibilityLabel(app.T("Xoá tìm kiếm", "Clear search"))
                .accessibilityIdentifier("map.searchClear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        // Solid field on the opaque sheet (was .thinMaterial over the map).
        .background(app.palette.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField
            // Map v6: Cancel while typing = keyboard down + back to where the sheet was.
            if searchFieldFocused {
                Button(app.T("Huỷ", "Cancel")) { cancelSearch() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.palette.ink)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.search.cancel")
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }

    /// Categories: Home's definitions (eventTypeProfiles.json) and line icons — the same icons the pins carry — in a
    /// fixed order so the row never reshuffles. Each count is what tapping it would show with every other filter kept;
    /// a selected category stays even at 0. "All categories" opens Home's A–Z sheet.
    private var categoryRow: some View {
        let counts = categoryCountMap
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeDiscovery.categories, id: \.key) { cat in
                    let active = catFilter == cat.key
                    let n = counts[cat.key] ?? 0
                    chip(active: active, muted: n == 0 && !active, id: "map.cat.\(cat.key)") {
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
                chip(active: false, id: "map.cat.showAll") { categorySheetOpen = true } label: {
                    Text(app.T("Tất cả danh mục", "All categories"))
                }
            }
            .padding(.horizontal, 16)
        }
        .rootSwipeExclusion("mapCategories")
    }

    /// The geographic context: the city flown to, the picked area while the map is framed on it, else "Map area".
    private var areaChipLabel: String {
        if areaContext == "city", let c = MapDiscovery.city(cityContextID) { return app.T(c.vi, c.en) }
        if areaContext == "area" && app.area != LocationHierarchy.allID { return app.currentAreaLabel }
        return app.T("Vùng bản đồ", "Map area")
    }

    /// For You pinned at the leading edge (never scrolls); only the other chips scroll.
    private var chipRow: some View {
        HStack(spacing: 8) {
            if hasForYouPrefs {
                forYouChip
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.leading, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(active: false, id: "map.area") { locationPickerOpen = true } label: {
                        Text("\(areaChipLabel) ▾")
                    }
                    // Time quick chips apply at once, judged in each event's own venue time zone (HomeDiscovery).
                    ForEach([("tonight", "Tối nay", "Tonight"), ("weekend", "Cuối tuần", "Weekend")], id: \.0) { opt in
                        chip(active: filters.date == opt.0, id: "map.\(opt.0)") {
                            Haptics.selection()
                            filters.date = filters.date == opt.0 ? "any" : opt.0
                        } label: {
                            Text(app.T(opt.1, opt.2))
                        }
                    }
                    // Seats left: real fill only, so hidden until banbe has any.
                    if openNowOnly || app.mapEvents.contains(where: { app.eventFill[$0.id] != nil }) {
                        chip(active: openNowOnly, id: "map.openNow") { Haptics.selection(); openNowOnly.toggle() } label: {
                            Text(app.T("Còn chỗ", "Seats left"))
                        }
                    }
                    // Everything else (any date, price per ticket, almost full, type chips) in Home's sheet, as a draft.
                    chip(active: sheetFilterCount > 0, id: "map.filters") { filterSheetOpen = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.footnote).accessibilityHidden(true)
                        Text(app.T("Bộ lọc", "Filters") + (sheetFilterCount > 0 ? " · \(sheetFilterCount)" : ""))
                    }
                }
                .padding(.leading, hasForYouPrefs ? 0 : 16)
                .padding(.trailing, 16)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Count + notices

    /// The settled result count for THIS map area (the list the pins come from) + the retry notice.
    private var resultCountLine: some View { resultCountRow(showLayout: false) }

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

    private var largeLayout: Bool { sheetDetent == Self.tallDetent && app.mapListLayout == "large" }

    private func resultCountRow(showLayout: Bool) -> some View {
        HStack(spacing: 8) {
            Text(committedBounds != nil && !(app.mapEventsLoading && app.mapEvents.isEmpty)
                 ? resultCountText(visibleEvents.count) : app.T("Đang tải sự kiện…", "Loading events…"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityIdentifier("map.resultCount")
            if app.mapEventsLoadFailed && !app.mapEvents.isEmpty {
                Button { Task { await app.loadMapEvents(bounds: boundedArea) } } label: {
                    Text(app.T("Chưa cập nhật được · Thử lại", "Couldn't update · Retry")).font(.footnote).underline()
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.palette.ink2)
                .accessibilityIdentifier("map.refreshRetry")
            }
            Spacer(minLength: 0)
            if showLayout { layoutSwitch }
        }
    }

    @ViewBuilder
    private var outsideLine: some View {
        if outsideCount > 0 && !visibleEvents.isEmpty {
            Text(app.T("+\(outsideCount) sự kiện khớp nằm ngoài vùng này",
                       "+\(outsideCount) matching event\(outsideCount == 1 ? "" : "s") outside this area"))
                .font(.footnote).foregroundStyle(app.palette.ink2).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("map.outsideCount")
        }
    }

    private var countBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            resultCountRow(showLayout: sheetDetent == Self.tallDetent).padding(.top, 6)
            outsideLine
            if app.mapEvents.count < app.mapEventsTotal {
                Text(app.T("Đang hiện \(app.mapEvents.count)/\(app.mapEventsTotal) sự kiện · phóng to để xem kỹ hơn",
                           "Showing \(app.mapEvents.count) of \(app.mapEventsTotal) events · zoom in for more"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("map.incomplete")
            }
        }
        .padding(.horizontal, 16)
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

    // MARK: - The list

    /// The list rows: the results minus the selected event (it is the first row on its own).
    private var listEvents: [MapEventRow] {
        let all = visibleEvents + noLocationMatches
        guard let id = selectedEvent?.id else { return all }
        return all.filter { $0.id != id }
    }

    /// Collapse the header once the list is past its first row; only when there is enough content left to stay
    /// scrolled after the header shrinks (otherwise the list would bounce back and the header flicker).
    private func listScrollChanged(offset: CGFloat, contentHeight: CGFloat, viewport: CGFloat) {
        if !listScrolled, offset > 64, contentHeight - viewport > 64 + 160 {
            listScrolled = true
        } else if listScrolled, offset < 8 {
            listScrolled = false
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            List {
                // Top anchor: scroll target for "back to top", and the probe that reports the list's offset (sticky
                // header) and drives the custom pull-to-refresh — same `ScaffoldScrollProbe` root screens use.
                Color.clear.frame(height: 1)
                    .id("map.listTop")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityHidden(true)
                    .background(ScaffoldScrollProbe(
                        onChange: { _, _ in },
                        onPullPhase: { phase, translationY in
                            switch phase {
                            case .began: app.beginRootPull()
                            case .changed: app.updateRootPull(translationY)
                            case .ended:
                                // The same whole-set refresh: camera, area, filters and selection stay put.
                                app.endRootPull(trigger: { await app.loadMapEvents(bounds: boundedArea) })
                            case .cancelled: app.cancelRootPull()
                            }
                        },
                        onScrollMetrics: { offset, contentHeight, viewport in
                            listScrollChanged(offset: offset, contentHeight: contentHeight, viewport: viewport)
                        }
                    ))

                // Typed a city name: "Cities" first — tap = fly there (even with no events yet).
                let cities = cityMatches
                if !cities.isEmpty {
                    Text(app.T("Thành phố", "Cities"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(app.palette.ink2)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(cities, id: \.id) { hit in
                        cityRow(hit).listRowBackground(Color.clear)
                    }
                }

                // The selection, first; then the rest of the area under it.
                if let ev = selectedEvent {
                    selectedRow(ev)
                        .id("map.selected.\(ev.id)")
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    let more = listEvents.filter { $0.lat != nil && $0.lng != nil }.count
                    if more > 0 {
                        Text(app.T("\(more) sự kiện khác trong vùng bản đồ", "\(more) more in this map area"))
                            .font(.footnote).foregroundStyle(app.palette.ink2)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("map.selectedRow.more")
                    }
                }

                ForEach(listEvents) { ev in
                    if largeLayout { largeCard(ev) } else { eventRow(ev) }
                }

                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .environment(\.defaultMinListRowHeight, 0)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The floating dock (its own window) shows only at tall (note 73 §1); the last row clears it then.
            .contentMargins(.bottom, dockHidden ? 16 : BottomTabBar.contentClearance, for: .scrollContent)
            // Pull-to-refresh hold fix (2026-09-29) — see `AppState.rootPullContentOffset`'s own doc comment.
            .offset(y: app.rootPullContentOffset)
            .onChange(of: selectableIDs) { _, ids in
                // A restored selection is the first row now: once its data exists, bring the list to the top.
                guard pendingScrollToRestoredSelection, let id = selectedId, ids.contains(id) else { return }
                pendingScrollToRestoredSelection = false
                proxy.scrollTo("map.listTop", anchor: .top)
            }
            .onChange(of: listTopToken) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo("map.listTop", anchor: .top) }
            }
            .overlay(alignment: .top) {
                if app.rootPullProgress > 0 || app.rootRefreshing {
                    RootRefreshIndicator(screen: .mapExplore, progress: app.rootPullProgress, refreshing: app.rootRefreshing)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Mid = cards (photo + three lines); tall = a denser list (small photo, two lines). Tap = select (the row moves to
    /// the top as the selected row, the pin is revealed).
    /// Large card at full height (note 74): Home's discovery card look — the photo pager on top (16:10, swipe
    /// sideways, never switches tabs), then name + price, venue time · area, category. Tap = select.
    private func largeCard(_ ev: MapEventRow) -> some View {
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
                Text(priceLine(ev)).font(.system(size: 15, weight: .bold)).lineLimit(1).fixedSize()
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
        .onTapGesture { selectEvent(ev) }
        .accessibilityElement(children: .contain)
        .accessibilityAction { selectEvent(ev) }
        .accessibilityIdentifier("map.card.\(ev.id)")
        .id(ev.id)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func eventRow(_ ev: MapEventRow) -> some View {
        let dense = sheetDetent == Self.tallDetent
        let thumb: CGFloat = dense ? 44 : 64
        return HStack(alignment: dense ? .center : .top, spacing: 12) {
            // The event's own resolved photo first; the bundled demo catalogue only for a real demo id.
            if let url = app.mapEventCoverURLs[ev.id] {
                CatalogPhoto(path: url.absoluteString, height: thumb, width: thumb, cornerRadius: 12).zoomSource(ev.id)
            } else if let path = EventCatalog.find(ev.id)?.img {
                CatalogPhoto(path: path, height: thumb, width: thumb, cornerRadius: 12).zoomSource(ev.id)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.name).font(.body.weight(.semibold)).lineLimit(2)
                // Venue date · time (the event's own zone), then the area, plus a distance only when it helps choose
                // (≤ 50 km); a viewer abroad saw "9662.0 km" on every row.
                Text([eventWhen(ev), dense ? ev.area : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                    .accessibilityIdentifier("map.list.when.\(ev.id)")
                if !dense {
                    Text([ev.area, nearDistance(ev)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                }
                // An honest "no map location" state, never a silently-omitted row or an invented pin.
                if ev.lat == nil || ev.lng == nil {
                    Text(app.T("Chưa có vị trí trên bản đồ", "No map location yet"))
                        .font(.system(size: 10.5)).opacity(0.55)
                        .accessibilityIdentifier("map.list.noLocation.\(ev.id)")
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(priceLine(ev)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    .accessibilityIdentifier("map.list.price.\(ev.id)")
                seatPill(ev, id: "map.list.seats.\(ev.id)")
            }
        }
        .padding(.vertical, dense ? 2 : 6)
        .id(ev.id)
        .contentShape(Rectangle())
        .onTapGesture { selectEvent(ev) }
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isButton)
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

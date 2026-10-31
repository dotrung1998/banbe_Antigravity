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
    // Follow-up (over-correction): the prior pass replaced the card's
    // "upper" anchor with a fully measured (PreferenceKey-based) position,
    // which over-corrected — the card ended up far too low, covering the
    // list/filter area instead of just clearing the top controls. Reverted
    // to the simpler two-state fraction anchor from the pass before that
    // (`0.72` for tall/mid, `0.12` for peek), with exactly ONE small, named,
    // fixed nudge applied only to the "upper" case — see `cardTopNudge`.
    private static let upperAnchorFraction: Double = 0.72
    private static let peekAnchorFraction: Double = 0.12
    /// The one named constant for "just enough to clear the top controls" —
    /// deliberately a small, fixed pixel amount, not a re-measured system:
    /// the prior measured approach is what over-corrected in the first
    /// place. Not guaranteed to clear every possible device/dynamic-type
    /// combination (a fixed value can't be, by definition) — an explicit,
    /// accepted trade-off per this ticket's own request for "one named
    /// layout constant... not scattered hardcoded offsets," not a silently
    /// reintroduced regression.
    private let cardTopNudge: CGFloat = 24
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
            _sheetDetent = State(initialValue: .fraction(0.45))
            _selectedId = State(initialValue: nil)
            _framed = State(initialValue: false)
            _pendingScrollToRestoredSelection = State(initialValue: false)
        }
    }

    /// Pin glyphs only (price pins replace these later); the chips use Home's categories and line icons.
    private static let pinGlyph: [String: String] = [
        "supper": "🍽️", "fashion": "👗", "gallery": "🖼️", "music": "🎵", "popup": "🛍️",
    ]
    @State private var categorySheetOpen = false
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
            Map(position: $cameraPosition) {
                ForEach(visibleEvents.filter { $0.lat != nil && $0.lng != nil }) { ev in
                    Annotation(ev.name, coordinate: CLLocationCoordinate2D(latitude: ev.lat ?? 0, longitude: ev.lng ?? 0)) {
                        pin(for: ev)
                    }
                }
            }
            .mapControls { }
            // `.onEnd` (the default made explicit): the list stays still while a gesture runs; the area is committed
            // once the camera settles (MapDiscovery.Reason).
            .onMapCameraChange(frequency: .onEnd) { context in
                currentCameraRegion = context.region
                cameraSettled(context.rect)
            }
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

            // Compact in-map preview — never a full-screen modal. Bug 2
            // follow-up: only shown once `sheetPresented` is true — a
            // restored instance keeps this (and the sheet) hidden until the
            // deliberate post-dismiss delay in `.task` reveals both
            // together, so the card never pops in ahead of/behind the
            // outgoing Event Detail screen.
            //
            // Follow-up (over-correction revert): "upper" is back to the
            // simple two-state fraction anchor (`cardBottomPadding` below),
            // with one small fixed `cardTopNudge` — the prior pass's fully
            // measured position over-corrected (the card ended up too low,
            // covering the list/filter area). "Peek" is unaffected.
            if let ev = selectedEvent, sheetPresented {
                VStack {
                    Spacer()
                    selectedCard(ev)
                        .id(ev.id)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, cardBottomPadding)
                .animation(.easeOut(duration: 0.28), value: cardBottomPadding)
            }
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
        .onChange(of: sheetDetent) { _, _ in
            // Bug 1 (camera half): re-applies the region shift (not a full
            // re-center/zoom, so this never replays the selection pop)
            // whenever the sheet's detent itself changes while something
            // stays selected — e.g. selecting at tall, then switching to
            // peek afterward.
            if let ev = selectedEvent { reapplyCameraOffset(for: ev) }
        }
        .onChange(of: filters) { _, _ in
            // Filters never move the camera (the old category → density-hotspot flight is gone): the area changes
            // only through the map. B2: a genuine filter change still snaps the sheet to MID. `.onChange` never fires
            // for the value `init` seeded.
            guard !isPreview else { return }
            withAnimation(.easeOut(duration: 0.28)) { sheetDetent = .fraction(0.45) }
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
                        LocationPickerSheet(isPresented: $locationPickerOpen)
                            .environmentObject(app)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: locationPickerOpen)
                .onChange(of: locationPickerOpen) { _, open in
                    // Give the card room if the sheet is peeked/collapsed.
                    if open && sheetDetent != .fraction(0.72) {
                        withAnimation(.easeOut(duration: 0.28)) { sheetDetent = .fraction(0.72) }
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
                .presentationDetents([.fraction(0.12), .fraction(0.45), .fraction(0.72)], selection: $sheetDetent)
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
        }
        // Freshness: the whole public set again (never a box). Camera, area, filters, selection and list stay put.
        .onReceive(pollTimer) { _ in
            guard !isPreview else { return }
            Task { await app.loadMapEvents() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            guard !isPreview else { return }
            Task { await app.loadMapEvents() }
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

    // MARK: - Bug 1: card's two-state vertical anchor

    /// Deliberately NOT the continuously-varying `sheetFraction` — only two
    /// resting positions exist for the card: "upper" (tall AND mid) and
    /// "peek" (bottom-anchored). Reverted from the prior pass's fully
    /// measured position (which over-corrected — see `cardTopNudge`'s own
    /// comment) back to this simple two-fraction anchor, nudged down by
    /// exactly one small, named, fixed amount.
    private var cardBottomPadding: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        if sheetDetent == .fraction(0.12) { return screenHeight * Self.peekAnchorFraction } // peek: unchanged
        return screenHeight * Self.upperAnchorFraction - cardTopNudge
    }

    private func reapplyCameraOffset(for ev: MapEventRow) {
        reveal(ev, duration: 0.3)
    }

    /// A REVEAL: bring the pin into the free map strip above the card at the CURRENT zoom (it used to zoom to 0.01°).
    /// Marked 'reveal', so it never redefines the search area, the list or the count.
    private func reveal(_ ev: MapEventRow, duration: Double) {
        guard let lat = ev.lat, let lng = ev.lng else { return }
        let span = currentCameraRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        // Aim for roughly the upper third of the visible (non-sheet) strip, leaving room for the card above the sheet.
        let desiredScreenFraction = (1 - sheetFraction) * 0.38
        let latShift = span.latitudeDelta * (0.5 - desiredScreenFraction)
        moveCamera(.reveal, to: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat - latShift, longitude: lng), span: span),
                   duration: duration)
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
                                            bottomInset: h * 0.12 + Self.legalReserve)
        committedBounds = MapDiscovery.boundsForRect(full, width: w, height: h, rect: ref)
        // The chip names the picked area only while the map is still framed on it; any other navigation makes the
        // context "Map area" (Home's selected area itself is never changed by panning).
        areaContext = (reason == .destination || (reason == .initial && framedByArea)) ? "area" : "map"
    }

    /// Back/compass row (8 top padding + 38 control + 12 gap) and the strip kept for the Apple Maps legal label.
    private static let topControlsHeight: Double = 58
    private static let legalReserve: Double = 26

    /// A camera region that fits `bounds` into the free area above the MID sheet (below the top controls).
    private func fittedRegion(_ bounds: MapDiscovery.Bounds) -> MKCoordinateRegion {
        let w = Double(max(320, mapSize.width)), h = Double(max(560, mapSize.height == 0 ? UIScreen.main.bounds.height : mapSize.height))
        let pad = MapDiscovery.Padding(top: Double(safeTop) + Self.topControlsHeight + 16, bottom: h * 0.45 + Self.legalReserve + 16,
                                       left: 40, right: 40)
        let cam = MapDiscovery.fitCamera(bounds, width: w, height: h, padding: pad, maxZoom: 14)
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
        guard app.area != LocationHierarchy.allID else { areaContext = "map"; return }
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
    private static func detent(for fraction: Double) -> PresentationDetent {
        if fraction == 0.12 { return .fraction(0.12) }
        if fraction == 0.45 { return .fraction(0.45) }
        return .fraction(0.72)
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
            areaContext: areaContext
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
        let isNewSelection = selectedId != ev.id
        selectedId = ev.id

        // Search-result-selection fix pass (2026-09-28) — a `List` row's
        // own tap gesture never sends `.focused($searchFieldFocused)` any
        // "tap outside" signal the way surrounding chrome normally would,
        // so picking a result while the keyboard was up left it up
        // indefinitely. Resigning here, at the single shared selection
        // path (pins and list rows both call this), covers every way a
        // result can be picked.
        let wasSearching = searchFieldFocused
        if wasSearching { searchFieldFocused = false }

        // Task 6 (2026-09-21 follow-up) — selecting an event at the tallest
        // detent (0.72 = the sheet itself occupies 72% of the screen, the
        // least visible map) used to leave it there, squeezing the map
        // into a sliver right when its own pin/info card most needs room
        // to be seen. Drops to mid (0.45) only from tall; already being at
        // mid/peek (more map visible than tall) is left alone.
        //
        // Search-result-selection fix pass (2026-09-28) — EXCEPT while
        // actively searching (`wasSearching`): a result picked with the
        // keyboard open always settles at MID/Level 2, even from PEEK,
        // matching this ticket's own "move the Map list sheet to its
        // existing MID/Level 2 snap" — the keyboard just closed (above),
        // so PEEK (0.12) would otherwise leave almost the whole screen
        // sitting on a mostly-empty map for a moment. Outside of search,
        // a plain pin/row tap with the keyboard never open keeps the
        // original tall-only behavior — no reason to force a bigger sheet
        // than the user already chose.
        if wasSearching {
            if sheetDetent != .fraction(0.45) {
                withAnimation { sheetDetent = .fraction(0.45) }
            }
        } else if sheetDetent == .fraction(0.72) {
            withAnimation { sheetDetent = .fraction(0.45) }
        }

        // A reveal at the current zoom (never a new search area); an event without coordinates just gets its card.
        reveal(ev, duration: 0.55)

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

    @ViewBuilder
    private func selectedCard(_ ev: MapEventRow) -> some View {
        // 2026-09-25 fix pass (Task 0 audit) — `cosmetic?.when` below used
        // to be the static catalogue's own frozen date verbatim. `ev` here
        // is already a real `events` row from THIS screen's own live query
        // (`loadMapEvents`, already filtered `status = 'live'`), so it can
        // drive the same `Countdown.liveEventOverrides` merge every other
        // screen uses directly — no separate reformatting.
        let cosmetic = EventCatalog.find(ev.id)
        VStack(alignment: .leading, spacing: 10) {
            // Task 4 (11-realtime-map.md follow-up): tapping anywhere in
            // this non-CTA area re-flies the camera back to the selected
            // event — reuses `selectEvent(_:)` verbatim (the exact same
            // fly/zoom logic used when the event was first selected) rather
            // than a new camera animation; since `ev` is already the
            // selection, `isNewSelection` is false inside it, so the pop
            // animation correctly doesn't replay, only the camera flies
            // back. The "×" close button (below, its own `Button`) and the
            // CTA button (a sibling, not a descendant, of this HStack)
            // handle/consume their own taps first, per SwiftUI's normal
            // Button-vs-ancestor-gesture precedence — this never fires for
            // either.
            HStack(alignment: .top, spacing: 10) {
                // Real-cover-photo fix (2026-10-19) — see loadMapEvents'
                // own comment (AppState+Data.swift): `cosmetic?.img` here
                // always resolved to the FIRST demo catalogue event's photo
                // for any real event, since `EventCatalog.find` never
                // returns nil. `app.mapEventCoverURLs` is this event's own
                // resolved `cover_image`/first-`event_photos` URL, checked
                // first; `cosmetic?.img` remains only for an actual demo
                // catalogue event (id genuinely matches a bundled entry).
                if let url = app.mapEventCoverURLs[ev.id] {
                    CatalogPhoto(path: url.absoluteString, height: 64, width: 64, cornerRadius: 10).zoomSource(ev.id)
                } else if let path = cosmetic?.img {
                    CatalogPhoto(path: path, height: 64, width: 64, cornerRadius: 10).zoomSource(ev.id)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top) {
                        Text(ev.name).font(.body.weight(.bold)).lineLimit(2)
                        Spacer()
                        Button { selectedId = nil } label: {
                            Text("×").font(.title3).foregroundStyle(app.palette.ink2)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.top, -12).padding(.trailing, -12)
                        .accessibilityLabel(app.T("Bỏ chọn", "Clear selection"))
                        .accessibilityIdentifier("map.card.close")
                    }
                    // Venue date · time, the same source Event Detail reads (starts_at in events.tz).
                    Text([eventWhen(ev), ev.area].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                    HStack {
                        // Map price bug fix (2026-09-29) — same root cause
                        // as web's identical fix (MapExplore.jsx): this was
                        // ALWAYS `cosmetic?.price` (the static demo
                        // catalogue's own price string), never `ev.priceVnd`
                        // (already decoded on `MapEventRow` — see that
                        // struct's own `cover_image` fix comment from the
                        // previous pass) — for any real event this showed
                        // the FIRST demo catalogue event's price
                        // ("900.000₫") regardless of the real event's own
                        // price, including a genuinely free (0 VND) one.
                        // `> 0`, never a bare truthiness check, so a real 0
                        // correctly reads as "Miễn phí"/Free, not "missing".
                        Text(priceLine(ev)).font(.subheadline.weight(.semibold))
                        Spacer()
                        // Real fill only; no fill row means no seat claim at all.
                        seatPill(ev, id: "map.card.seats")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectEvent(ev) }
            .accessibilityIdentifier("map.card.recenter")
            HStack(spacing: 8) {
                // Directions: the same public venue link Event Detail opens; only with a map location. Separate from
                // "View details" so selecting never opens anything by itself.
                if let url = ev.mapsURL {
                    Link(destination: url) {
                        Label(app.T("Chỉ đường", "Directions"), systemImage: "location.north.line")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(app.palette.clayBg, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(app.palette.clay)
                    }
                    .accessibilityIdentifier("map.card.directions")
                }
                Button(action: { openEventDetail(ev.id) }) {
                    Text(app.T("Xem chi tiết", "View details"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(app.palette.paper)
                }
                .accessibilityIdentifier("map.card.cta")
            }
        }
        .padding(12)
        // Content surface: opaque for readability over the map (was .regularMaterial).
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .foregroundStyle(app.palette.ink)
        .accessibilityIdentifier("map.selectedCard")
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

    /// A pin is a result (committed area + filters): the same list and count the sheet shows. Out-of-filter events
    /// no longer get passive dots, so nothing on the map disagrees with the list.
    @ViewBuilder
    private func pin(for ev: MapEventRow) -> some View {
        let isSelected = ev.id == selectedId
        let isPopping = ev.id == poppingId
        ZStack(alignment: .topTrailing) {
            Text(Self.pinGlyph[ev.catKey ?? ""] ?? "▪︎")
                .font(.system(size: 14))
                .frame(width: 30, height: 30)
                .background(app.palette.paper, in: Circle())
                .overlay(Circle().stroke(app.palette.ink, lineWidth: isSelected ? 2.5 : 1.5))
                .shadow(radius: isSelected ? 5 : 3)
            if seatFacts(ev)?.almostFull == true {
                Circle().fill(Color(red: 0.6, green: 0.24, blue: 0.18)).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(app.palette.paper, lineWidth: 1.5))
            }
        }
        // Selected pin sits slightly larger and settles there; the brief overshoot past that (isPopping) plays once
        // per actual selection change, guarded in selectEvent(_:) — never replayed by a refresh.
        .scaleEffect(isPopping ? 1.32 : (isSelected ? 1.15 : 1))
        .zIndex(isSelected ? 1 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ev.name)
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

    private var sheetContent: some View {
        VStack(spacing: 0) {
            // Home quick event search (2026-09-27) — a plain text filter,
            // ANDed with the category/open-now/nearby controls below;
            // reuses this screen's own existing list/filter/event-detail
            // routing rather than a second search surface. Autofocused on
            // arrival from Home's search button (`startFocusedOnSearch`).
            //
            // Map search-focus fix (2026-09-28, fifth pass) — `FocusableTextField`
            // (Components.swift), not SwiftUI's own `TextField` +
            // `@FocusState` — see that type's own doc comment for the full,
            // CONFIRMED trace of why: a temporary on-screen marker reading
            // `@FocusState` directly proved it never became `true` on a
            // real device via any of four different mechanisms tried
            // (including a bare synchronous `.onAppear` write with zero
            // indirection), while a manual tap on the same field always
            // worked. This wraps the real `UITextField` and drives the
            // exact plain UIKit mechanism that manual tap already proven
            // to succeed at.
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).opacity(0.55)
                FocusableTextField(
                    text: $searchQuery,
                    isFirstResponder: $searchFieldFocused,
                    // The matcher covers name, category, area, host and description (Search.swift), not just names.
                    placeholder: app.T("Tìm theo tên, loại, khu vực, người tổ chức…", "Search name, type, area, host…"),
                    font: .preferredFont(forTextStyle: .body)
                )
                // Confirmed-fix follow-up (2026-09-28) — a plain
                // `UITextField`'s own default intrinsic height is taller
                // than the SwiftUI `TextField` it replaced (which sized
                // itself compactly off the 14pt font alone), so the row
                // grew visibly taller than every other control in this
                // same `HStack` once swapped in. Pinned back to that
                // original compact height explicitly, rather than relying
                // on `UITextField`'s own default sizing.
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
            // `.padding(.top, 8)` opens a small, deliberate gap above this
            // row — this file's own established ad-hoc spacing scale
            // (8/10/12/14/16, per .claude/notes/06-design-tokens.md)
            // already uses exactly this 8pt increment as its row-to-row gap
            // (see the FlowLayout/"Còn chỗ" rows just below) — so the
            // search field no longer sits flush against the sheet's own
            // system drag indicator.
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            // Categories: Home's definitions (eventTypeProfiles.json) and line icons, in a fixed order so the row
            // never reshuffles. Each count is what tapping it would show with every other filter kept; a selected
            // category stays even at 0. "All categories" opens Home's A–Z sheet.
            let counts = categoryCountMap
            ScrollView(.horizontal, showsIndicators: false) {
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
            .sheet(isPresented: $filterSheetOpen) {
                // Home's sheet as a draft over THIS map area: Close discards, Apply commits atomically.
                HomeFilterSheet(items: sheetItems, now: nowMinute, onClose: { filterSheetOpen = false },
                                mapFilters: filters, onApplyMap: { filters = $0 })
                    .environmentObject(app)
            }
            .sheet(isPresented: $categorySheetOpen) {
                HomeCategorySheet(counts: counts, selected: catFilter == "all" ? [] : [catFilter]) { key in
                    catFilter = catFilter == key ? "all" : key
                }
                .environmentObject(app)
            }

            // For You pinned at the leading edge (never scrolls); only the other chips scroll.
            HStack(spacing: 8) {
            if hasForYouPrefs {
                forYouChip
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .padding(.leading, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                // The geographic context: the picked area while the map is framed on it, else "Map area".
                chip(active: false, id: "map.area") { locationPickerOpen = true } label: {
                    Text("\(areaContext == "area" && app.area != LocationHierarchy.allID ? app.currentAreaLabel : app.T("Vùng bản đồ", "Map area")) ▾")
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
                // Seats left: real fill only, so hidden until banbe has any. The old English "Open now" read like
                // opening hours; events have seats, not hours.
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

            // The settled result count for THIS map area (the list the pins come from) + honest status notices.
            HStack(spacing: 8) {
                Text(committedBounds != nil && !(app.mapEventsLoading && app.mapEvents.isEmpty)
                     ? resultCountText(visibleEvents.count) : app.T("Đang tải sự kiện…", "Loading events…"))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("map.resultCount")
                if app.mapEventsLoadFailed && !app.mapEvents.isEmpty {
                    Button { Task { await app.loadMapEvents() } } label: {
                        Text(app.T("Chưa cập nhật được · Thử lại", "Couldn't update · Retry")).font(.footnote).underline()
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink2)
                    .accessibilityIdentifier("map.refreshRetry")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 6)
            if outsideCount > 0 && !visibleEvents.isEmpty {
                Text(app.T("+\(outsideCount) sự kiện khớp nằm ngoài vùng này",
                           "+\(outsideCount) matching event\(outsideCount == 1 ? "" : "s") outside this area"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("map.outsideCount")
            }
            if app.mapEvents.count < app.mapEventsTotal {
                Text(app.T("Đang hiện \(app.mapEvents.count)/\(app.mapEventsTotal) sự kiện · phóng to để xem kỹ hơn",
                           "Showing \(app.mapEvents.count) of \(app.mapEventsTotal) events · zoom in for more"))
                    .font(.footnote).foregroundStyle(app.palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("map.incomplete")
            }

            ScrollViewReader { proxy in
                List(visibleEvents + noLocationMatches) { ev in
                    // Mid = cards (photo + three lines); tall = a denser list (small photo, two lines).
                    let dense = sheetDetent == .fraction(0.72)
                    let thumb: CGFloat = dense ? 44 : 64
                    HStack(alignment: dense ? .center : .top, spacing: 12) {
                        // Same left-side thumbnail every other event card in
                        // this app uses (CatalogPhoto -> RemoteImage ->
                        // PhotoLoader) — was missing here entirely (bug 1,
                        // 11-realtime-map.md). The map screen's own rows only
                        // carry the live DB columns (no `img`), so the cosmetic
                        // photo path is joined back from the bundled catalogue
                        // by id, same as the price/img join the web build does
                        // in MapExplore.jsx's fetchLiveEvents().
                        // Real-cover-photo fix (2026-10-19) — same root
                        // cause/fix as `selectedCard` above: prefer this
                        // event's own resolved real photo before ever
                        // falling back to the static demo catalogue join.
                        if let url = app.mapEventCoverURLs[ev.id] {
                            CatalogPhoto(path: url.absoluteString, height: thumb, width: thumb, cornerRadius: 12).zoomSource(ev.id)
                        } else if let path = EventCatalog.find(ev.id)?.img {
                            CatalogPhoto(path: path, height: thumb, width: thumb, cornerRadius: 12).zoomSource(ev.id)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.name).font(.body.weight(.semibold)).lineLimit(2)
                            // Venue date · time (the event's own zone), then the area, plus a distance only when it
                            // helps choose (≤ 50 km); a viewer abroad saw "9662.0 km" on every row.
                            Text([eventWhen(ev), dense ? ev.area : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                                .accessibilityIdentifier("map.list.when.\(ev.id)")
                            if !dense {
                                Text([ev.area, nearDistance(ev)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(app.palette.ink2).lineLimit(1)
                            }
                            // Stage 3 — an honest "no map location" state
                            // for an event with no (or not-yet-confirmed)
                            // coordinates, never a silently-omitted row or
                            // an invented pin.
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
                    .listRowBackground(ev.id == selectedId ? app.palette.ink.opacity(0.05) : Color.clear)
                    .accessibilityAddTraits(ev.id == selectedId ? [.isButton, .isSelected] : .isButton)
                    // Refresh-indicator fix pass (2026-09-27, follow-up A)
                    // — same `ScaffoldScrollProbe` ScreenScaffold's own
                    // root screens use, anchored to this FIRST row (a real
                    // UITableView cell, so walking up from here reliably
                    // finds the List's own underlying UIScrollView) instead
                    // of the plain `.refreshable{}` this used to have (its
                    // system spinner can't be reskinned — see
                    // RootRefreshIndicator's own comment). Reuses the exact
                    // SAME refetch the removed `.refreshable` called.
                    .background(
                        ev.id == (visibleEvents + noLocationMatches).first?.id
                            ? AnyView(ScaffoldScrollProbe(
                                onChange: { _, _ in },
                                onPullPhase: { phase, translationY in
                                    switch phase {
                                    case .began: app.beginRootPull()
                                    case .changed: app.updateRootPull(translationY)
                                    case .ended:
                                        // The same whole-set refresh: camera, area, filters and selection stay put.
                                        app.endRootPull(trigger: { await app.loadMapEvents() })
                                    case .cancelled: app.cancelRootPull()
                                    }
                                }
                              ))
                            : AnyView(EmptyView())
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // The floating dock (its own window) sits over the sheet's bottom: the last row must clear it.
                .contentMargins(.bottom, BottomTabBar.contentClearance, for: .scrollContent)
                .overlay { forYouEmptyState }
                // Pull-to-refresh hold fix (2026-09-29) — see
                // `AppState.rootPullContentOffset`'s own doc comment.
                .offset(y: app.rootPullContentOffset)
                .onChange(of: selectableIDs) { _, ids in
                    // Bug 2 (best-effort list-scroll restore): SwiftUI's
                    // List has no pixel scrollTop to round-trip the way a
                    // web scroll container does, so this restores by
                    // scrolling the previously-selected row back into view
                    // instead, once its data actually exists to scroll to.
                    guard pendingScrollToRestoredSelection, let id = selectedId, ids.contains(id) else { return }
                    pendingScrollToRestoredSelection = false
                    proxy.scrollTo(id, anchor: .top)
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
        .foregroundStyle(app.palette.ink)
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
    private var forYouEmptyState: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    emptyAction(app.T("Thử lại", "Try again"), id: "map.retry") { Task { await app.loadMapEvents() } }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

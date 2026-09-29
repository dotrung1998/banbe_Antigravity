import SwiftUI
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
    @State private var lastQueriedRegion: MKCoordinateRegion?
    @State private var boundsChanged = false
    @State private var catFilter: String
    @State private var openNowOnly: Bool
    @State private var sortByDistance: Bool
    // Home quick event search (2026-09-27) — see `visibleEvents`'s own
    // doc comment. `startFocusedOnSearch` is read once, at construction
    // (mirrors `hadRestoredState`'s own one-shot capture), so a later
    // unrelated re-render can't re-focus the field out from under the user.
    @State private var searchQuery = ""
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
    @State private var initialCenterSet: Bool
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
    // Bug 3 follow-up: `onMapCameraChange`'s callback, before this fix, only
    // ever wrote `lastQueriedRegion` ONCE (its first call — see the `body`
    // comment above `.onMapCameraChange`), then froze it forever afterward.
    // `openEventDetail(_:)` read THAT frozen value for the saved snapshot's
    // camera, so it always saved wherever the map was at construction time
    // — NOT wherever `selectEvent(_:)` had since flown the camera to. This
    // tracks the ACTUAL current camera on every callback, independently of
    // `lastQueriedRegion`'s own (intentionally-frozen-after-first-call)
    // "Search here" bookkeeping, so `openEventDetail(_:)` can read the real,
    // live position instead.
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
    init(restored: MapExploreState?, isPreview: Bool = false, startFocusedOnSearch: Bool = false, isActive: Bool = true) {
        hadRestoredState = restored != nil
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
            _catFilter = State(initialValue: restored.catFilter)
            _openNowOnly = State(initialValue: restored.openNowOnly)
            _sortByDistance = State(initialValue: restored.sortByDistance)
            _sheetDetent = State(initialValue: MapExploreView.detent(for: restored.sheetFraction))
            _selectedId = State(initialValue: restored.selectedId)
            _initialCenterSet = State(initialValue: true) // restored camera counts as already "set"
            // Root cause fix (11-realtime-map.md follow-up): seeded here,
            // synchronously, from the SAME restored region `cameraPosition`
            // uses above — see the non-restored branch's own comment for
            // why this can no longer be left to `onMapCameraChange`'s first
            // callback.
            //
            // Task 7 fix (2026-09-21 follow-up) — EXCEPT for
            // `singleEventFocus` (the "Open in Map" entry point):
            // `cameraSpanLat`/`cameraSpanLng` there is a deliberately tight
            // 0.01° single-pin view, meant only for the visual camera. Using
            // that same tight span for the DATA-LOADING bounds meant the
            // very first freshness poll (`loadMapEvents(bounds:)`) silently
            // replaced `app.mapEvents` — the full loaded dataset — with just
            // the one or two events near that tiny box, so every other pin
            // vanished a few seconds after opening, independent of any
            // filter tap (a filter tap merely made the already-collapsed
            // dataset's narrowing visible). Seeds a wide span instead — the
            // SAME 0.12° default `centerOnDensityHotspot()` uses for a
            // fresh, non-restored open — so the map still visually zooms in
            // tight on the pin (`cameraPosition`, unchanged above) while the
            // underlying query still covers the whole city.
            let queryRegionSpan = restored.singleEventFocus
                ? MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                : MKCoordinateSpan(latitudeDelta: restored.cameraSpanLat, longitudeDelta: restored.cameraSpanLng)
            _lastQueriedRegion = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: restored.cameraCenterLat, longitude: restored.cameraCenterLng),
                span: queryRegionSpan
            ))
            _pendingScrollToRestoredSelection = State(initialValue: restored.selectedId != nil)
        } else {
            _cameraPosition = State(initialValue: .automatic)
            _catFilter = State(initialValue: "all")
            _openNowOnly = State(initialValue: false)
            _sortByDistance = State(initialValue: false)
            _sheetDetent = State(initialValue: .fraction(0.72))
            _selectedId = State(initialValue: nil)
            _initialCenterSet = State(initialValue: false)
            _pendingScrollToRestoredSelection = State(initialValue: false)
        }
    }

    private let categories: [(key: String, vi: String, en: String, glyph: String)] = [
        ("all", "Tất cả", "All", "▪︎"),
        ("supper", "Supper club", "Supper club", "🍽️"),
        ("fashion", "Thời trang", "Fashion", "👗"),
        ("gallery", "Phòng tranh", "Gallery", "🖼️"),
        ("music", "Nhạc", "Music", "🎵"),
    ]

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
            Map(position: $cameraPosition) {
                ForEach(mapEventsWithCoordinates) { ev in
                    Annotation(ev.name, coordinate: CLLocationCoordinate2D(latitude: ev.lat ?? 0, longitude: ev.lng ?? 0)) {
                        pin(for: ev)
                    }
                }
            }
            .mapControls { }
            .onMapCameraChange { context in
                // Bug 3 follow-up: tracked on EVERY callback (unlike
                // `lastQueriedRegion` below, which intentionally freezes
                // after its first call for "Search here" bookkeeping) so
                // `openEventDetail(_:)` can save wherever the camera
                // actually is right now — including after `selectEvent(_:)`
                // has flown it toward a selected pin — instead of a stale
                // snapshot from whenever this view was first constructed.
                currentCameraRegion = context.region
                // Root cause fix (11-realtime-map.md follow-up): this "if
                // nil, freeze" branch is now only a defensive fallback —
                // both real init paths (`centerOnDensityHotspot()` and
                // `init(restored:)`) already seed `lastQueriedRegion`
                // synchronously and directly, from a region this view
                // itself chose, specifically because this callback's FIRST
                // invocation is not reliable enough to freeze forever: it
                // was observed reporting a region nowhere near Vietnam
                // before MapKit had caught up to `cameraPosition`, silently
                // corrupting every later bounded poll/pagination reload.
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
        .onChange(of: mapEventsWithCoordinates.map(\.id)) { _, ids in
            // Design change (11-realtime-map.md follow-up): this used to
            // key off `visibleEvents` (the LIST-filtered set) — meaning a
            // category/open-now filter change, or even re-selecting "Tất
            // cả", could silently clear an unrelated selection the instant
            // it didn't match whatever filter was now active. That
            // coupling is removed entirely, not just patched: this now
            // reads `mapEventsWithCoordinates` (the same unfiltered
            // baseline `selectedEvent` and the map's own pins use), so it
            // only ever clears the selection because the underlying event
            // is genuinely gone from the loaded data — cancelled, deleted,
            // or no longer inside whatever bounds a poll/search-here last
            // queried — never merely because it doesn't match the active
            // category/open-now filter. No second query: this still only
            // ever reads data this screen already loaded.
            //
            // Guarded on `mapEventsLoading == false`: a restored `selectedId`
            // (bug 2) is applied before `app.mapEvents` has necessarily
            // settled from its own reload, and without this guard that
            // transient "not loaded yet" state was indistinguishable from
            // "genuinely gone" — the same race the web build hit and fixed
            // the same way.
            if !app.mapEventsLoading, let id = selectedId, !ids.contains(id) { selectedId = nil }
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
        .onChange(of: catFilter) { _, _ in
            // Task 2b (11-realtime-map.md follow-up): `.onChange` never
            // fires for the value `init` seeded (only for a later, genuine
            // change), so this never re-runs on a restored/fresh mount —
            // only when the user actually taps a different category chip.
            guard !isPreview else { return }
            recenterOnFilterDensityHotspot()
            // B2 (Map filters pass, 2026-09-27) — snaps to MID on a genuine
            // filter change specifically, never on mount (same `.onChange`
            // guarantee as `recenterOnFilterDensityHotspot` above), a map
            // pan/`boundsChanged` (unrelated state), a list scroll, or the
            // 5s freshness poll (`app.loadMapEvents` never touches `catFilter`).
            withAnimation(.easeOut(duration: 0.28)) { sheetDetent = .fraction(0.45) }
        }
        .onChange(of: openNowOnly) { _, _ in
            // B2 — "Còn chỗ" excludes events the same way the category
            // chips do, so it gets the same MID-snap; it does NOT get
            // `recenterOnFilterDensityHotspot()` (that's this ticket's own
            // "do not change camera position" — the existing camera-fly
            // behavior above is pre-existing, category-filter-only
            // behavior this pass doesn't extend to a second filter).
            guard !isPreview else { return }
            withAnimation(.easeOut(duration: 0.28)) { sheetDetent = .fraction(0.45) }
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
                centerOnDensityHotspot()
                // The one-shot FAB intent is consumed unconditionally once
                // this fresh-open branch runs at all (not by a callback
                // that fires only once focus actually lands) — the next
                // `MapExploreView` this app constructs (a later dock-tab
                // open, another restore) never reads a stale `true` left
                // over from this one.
                if startFocusedOnSearch { app.mapExploreFocusSearch = false }
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
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard !isPreview else { return }
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
        guard let lat = ev.lat, let lng = ev.lng else { return }
        let zoomSpan = 0.01
        let visibleFraction = 1 - sheetFraction
        let desiredScreenFraction = visibleFraction * 0.38
        let latShift = zoomSpan * (0.5 - desiredScreenFraction)
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat - latShift, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: zoomSpan, longitudeDelta: zoomSpan)
            ))
        }
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
    private func openEventDetail(_ id: String) {
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
        let region = currentCameraRegion ?? lastQueriedRegion
        app.mapExploreState = MapExploreState(
            cameraCenterLat: region?.center.latitude ?? 10.7769,
            cameraCenterLng: region?.center.longitude ?? 106.7009,
            cameraSpanLat: region?.span.latitudeDelta ?? 0.05,
            cameraSpanLng: region?.span.longitudeDelta ?? 0.05,
            sheetFraction: sheetFraction,
            catFilter: catFilter,
            openNowOnly: openNowOnly,
            sortByDistance: sortByDistance,
            selectedId: selectedId
        )
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
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12))
        cameraPosition = .region(region)
        // Root cause fix (11-realtime-map.md follow-up): seeded here,
        // synchronously and directly from the SAME region `cameraPosition`
        // above just got — not left for `onMapCameraChange`'s own "freeze on
        // first callback" branch (still below, now just a defensive
        // fallback) to capture. That first callback is not guaranteed to
        // reflect this region yet — MapKit's `Map(position:)` was observed,
        // on a fresh load, reporting an initial callback centered nowhere
        // near Vietnam (e.g. ~51°N/10°E) before it had caught up to the
        // `cameraPosition` this method sets — and since `lastQueriedRegion`
        // is a permanent one-time freeze (by design, for "Search here"
        // bookkeeping), that bogus region then fed every future poll/
        // pagination reload's bounds query FOREVER, each legitimately
        // returning zero rows for a real region that far from Vietnam. That
        // silently wiped `app.mapEvents` to empty the next time any bounded
        // reload happened to fire — which a category filter change (via
        // `recenterOnFilterDensityHotspot()`'s own camera move, below) was
        // often what finally nudged MapKit into emitting that first
        // unreliable callback, making it look like "changing the filter
        // clears everything" when the actual defect was here, in camera-
        // bounds tracking, unrelated to the selection/filter decoupling
        // fixed earlier in this same file.
        lastQueriedRegion = region
    }

    /// Task 2b (11-realtime-map.md follow-up): reuses the EXACT SAME
    /// `densityHotspot(_:)` free function `centerOnDensityHotspot()` above
    /// calls at initial load — scoped here to `visibleEvents` (which
    /// already reflects the just-changed `catFilter`, plus whichever other
    /// filters/bounds are active) instead of every loaded event, so the
    /// camera moves to wherever THIS filter's own results are most
    /// concentrated, not wherever the previous filter's were. No `initialCenterSet`
    /// guard here — unlike the initial-load call, this is meant to re-run
    /// every time the category actually changes.
    private func recenterOnFilterDensityHotspot() {
        let points = visibleEvents.compactMap { ev -> CLLocationCoordinate2D? in
            guard let lat = ev.lat, let lng = ev.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        // No matching events for this filter — leave the camera exactly
        // where it was rather than snapping to a meaningless fallback.
        guard let center = densityHotspot(points) else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)))
        }
    }

    // MARK: - Pin/list selection: camera zoom + compact in-map preview card

    /// Design change (11-realtime-map.md follow-up): reads
    /// `mapEventsWithCoordinates` (the full, unfiltered baseline — see its
    /// own doc comment) instead of `visibleEvents` (the LIST-filtered set)
    /// — a selection now persists through any category/open-now filter
    /// change instead of clearing the instant it stops matching whatever
    /// filter is active.
    private var selectedEvent: MapEventRow? {
        guard let selectedId else { return nil }
        return mapEventsWithCoordinates.first { $0.id == selectedId }
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
        // 2026-09-25 fix pass (Task 0 audit) — `cosmetic?.when` below used
        // to be the static catalogue's own frozen date verbatim. `ev` here
        // is already a real `events` row from THIS screen's own live query
        // (`loadMapEvents`, already filtered `status = 'live'`), so it can
        // drive the same `Countdown.liveEventOverrides` merge every other
        // screen uses directly — no separate reformatting.
        let cosmetic = EventCatalog.find(ev.id)
        let liveStatus = LiveEventStatus(status: ev.status, startsAt: ev.startsAt, cancelledAt: nil, cancelReason: nil)
        let cosmeticLive = cosmetic.map { $0.applyingLiveStatus(liveStatus) } ?? cosmetic
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
                    CatalogPhoto(path: url.absoluteString, height: 64, width: 64, cornerRadius: 10)
                } else if let path = cosmetic?.img {
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
                    Text([cosmeticLive?.when, ev.area].compactMap { $0 }.joined(separator: " ▪︎ "))
                        .font(.system(size: 11)).opacity(0.65).lineLimit(1)
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
                        Text(ev.priceVnd > 0 ? EventLabels.vnd(ev.priceVnd) : app.T("Miễn phí", "Free"))
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(isSoldOut(ev) ? app.T("Hết chỗ", "Sold out") : app.T("Còn chỗ", "Available"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSoldOut(ev) ? BanbeTheme.alert : app.palette.ink)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selectEvent(ev) }
            .accessibilityIdentifier("map.card.recenter")
            Button(action: { openEventDetail(ev.id) }) {
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

    // B1 (Map filters pass, 2026-09-27) — three of these four ARE an
    // existing app color (Home's own Pulse-ring gradient stops); one
    // additional muted tone in the same dusty/desaturated family was added
    // for the 4th non-"all" category, since that trio only has 3 colors —
    // see web's `CAT_DOT_COLOR` (MapExplore.jsx) for the identical values/
    // reasoning; kept in sync by hand (this app has no shared cross-
    // platform color-constant file to import from).
    private static let categoryDotColor: [String: Color] = [
        "all": .primary,
        "supper": Color(red: 0.906, green: 0.788, blue: 0.761),
        "fashion": Color(red: 0.890, green: 0.812, blue: 0.651),
        "gallery": Color(red: 0.784, green: 0.796, blue: 0.698),
        "music": Color(red: 0.718, green: 0.651, blue: 0.780),
    ]

    @ViewBuilder
    private func pin(for ev: MapEventRow) -> some View {
        // B1 — a geolocated event that doesn't currently match the active
        // filters (`visibleIdSet`, derived from the SAME `visibleEvents`
        // the list panel shows) gets a small, passive, non-interactive dot
        // in its own category's color instead of the normal clickable
        // pin — never rendered as "another selectable matching pin."
        // Selection itself is untouched: `selectedEvent`/`mapEventsWithCoordinates`
        // (this pin ForEach's own data source) deliberately stay on the
        // FULL unfiltered set (see that property's own doc comment), so a
        // selection whose pin just became a dot still keeps its card.
        if !visibleIdSet.contains(ev.id) {
            Circle()
                .fill(Self.categoryDotColor[ev.catKey ?? "all"] ?? Self.categoryDotColor["all"]!)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(app.palette.paper, lineWidth: 1))
                .opacity(0.85)
                .allowsHitTesting(false)
                .accessibilityIdentifier("map.dot.\(ev.id)")
        } else {
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
    }

    /// B1 — the ONE filtered event-id set the list panel (`visibleEvents`)
    /// and the map's own pins (`pin(for:)`) both key off, so they can
    /// never disagree about which events currently match the active
    /// filters.
    private var visibleIdSet: Set<String> {
        Set(visibleEvents.map(\.id))
    }

    /// Sweep finding (11-realtime-map.md follow-up): the full, unfiltered
    /// set of loaded events that have coordinates to place on the map at
    /// all — the SAME baseline the map's own pins (`body`, above) and
    /// `selectedEvent`/its clearing effect now use. Only for PINS —
    /// `visibleEvents` (the LIST panel, below) deliberately does NOT start
    /// from this any more (Stage 3): a location-less event still belongs
    /// in the list, just never gets a pin here.
    private var mapEventsWithCoordinates: [MapEventRow] {
        app.mapEvents.filter { $0.lat != nil && $0.lng != nil }
    }

    // MARK: - List

    // Stage 3 (2026-09-27 nav/discovery pass) — this used to start from
    // `mapEventsWithCoordinates` (the PIN-only, coordinate-filtered set),
    // so an event missing coordinates was silently dropped from the LIST
    // too, not just denied a pin — the exact "silently omit them from all
    // discovery" this ticket warns against. Now starts from the raw,
    // unfiltered `app.mapEvents`: an event without a location still
    // belongs in the list (see the "no map location" row tag below),
    // just never gets a marker on the map itself.
    private var visibleEvents: [MapEventRow] {
        var list = app.mapEvents
        if catFilter != "all" { list = list.filter { effectiveCatKey($0) == catFilter } }
        if openNowOnly { list = list.filter { ($0.seatsRemaining ?? 0) > 0 } }
        // Home quick event search (2026-09-27) — a by-name/area/keywords
        // text filter, ANDed with the filters above; never a second search
        // index (same `app.mapEvents` this screen already loads). Keyword-
        // search fix (migration 108) — mirrors web's identical MapExplore.jsx
        // change: also matches an event's own `keywords`, not just its
        // literal name/district.
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                || $0.area.lowercased().contains(q)
                || ($0.keywords ?? []).contains { $0.lowercased().contains(q) }
            }
        }
        if sortByDistance, let coords = app.userCoords {
            list.sort { distanceKm(coords, $0) ?? .greatestFiniteMagnitude < distanceKm(coords, $1) ?? .greatestFiniteMagnitude }
        }
        return list
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
                    placeholder: app.T("Tìm sự kiện theo tên…", "Search events by name…"),
                    font: .systemFont(ofSize: 14)
                )
                // Confirmed-fix follow-up (2026-09-28) — a plain
                // `UITextField`'s own default intrinsic height is taller
                // than the SwiftUI `TextField` it replaced (which sized
                // itself compactly off the 14pt font alone), so the row
                // grew visibly taller than every other control in this
                // same `HStack` once swapped in. Pinned back to that
                // original compact height explicitly, rather than relying
                // on `UITextField`'s own default sizing.
                .frame(height: 20)
                .accessibilityIdentifier("map.searchInput")
                .onAppear {
                    if startFocusedOnSearch && !hadRestoredState {
                        searchFieldFocused = true
                    }
                }
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).opacity(0.45)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.searchClear")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            // `.padding(.top, 8)` opens a small, deliberate gap above this
            // row — this file's own established ad-hoc spacing scale
            // (8/10/12/14/16, per .claude/notes/06-design-tokens.md)
            // already uses exactly this 8pt increment as its row-to-row gap
            // (see the FlowLayout/"Còn chỗ" rows just below) — so the
            // search field no longer sits flush against the sheet's own
            // system drag indicator.
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            // Task 2a (11-realtime-map.md follow-up): every category is
            // visible up front now — wraps onto as many rows as needed
            // instead of requiring the user to discover horizontal
            // scrolling (`FlowLayout`, below).
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(categories, id: \.key) { cat in
                    Text("\(cat.glyph) \(app.T(cat.vi, cat.en))")
                        .font(.system(size: 12, weight: catFilter == cat.key ? .bold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .onTapGesture { catFilter = cat.key }
                }
            }
            .padding(.horizontal, 16)
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

            ScrollViewReader { proxy in
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
                        // Real-cover-photo fix (2026-10-19) — same root
                        // cause/fix as `selectedCard` above: prefer this
                        // event's own resolved real photo before ever
                        // falling back to the static demo catalogue join.
                        if let url = app.mapEventCoverURLs[ev.id] {
                            CatalogPhoto(path: url.absoluteString, height: 52, width: 52, cornerRadius: 10)
                        } else if let path = EventCatalog.find(ev.id)?.img {
                            CatalogPhoto(path: path, height: 52, width: 52, cornerRadius: 10)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.name).font(.system(size: 14, weight: .semibold))
                            // Task 3 (11-realtime-map.md follow-up): shown
                            // whenever location permission is already
                            // granted, independent of "Gần bạn" — that chip
                            // still only controls SORTING/filtering by
                            // distance, unchanged; this is purely about
                            // whether the km figure is DISPLAYED at all.
                            Text(ev.area + (sortByDistance || locationGranted ? distanceSuffix(ev) : ""))
                                .font(.system(size: 11)).opacity(0.6)
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
                        Spacer()
                    }
                    .id(ev.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectEvent(ev) }
                    .onAppear {
                        if ev.id == visibleEvents.last?.id { Task { await app.loadMapEvents(bounds: lastQueriedRegion.map(boundsOf)) } }
                    }
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
                        ev.id == visibleEvents.first?.id
                            ? AnyView(ScaffoldScrollProbe(
                                onChange: { _ in },
                                onPullPhase: { phase, translationY in
                                    switch phase {
                                    case .began: app.beginRootPull()
                                    case .changed: app.updateRootPull(translationY)
                                    case .ended:
                                        app.endRootPull(trigger: {
                                            guard let region = lastQueriedRegion else { return }
                                            boundsChanged = false
                                            await app.loadMapEvents(bounds: boundsOf(region))
                                        })
                                    case .cancelled: app.cancelRootPull()
                                    }
                                }
                              ))
                            : AnyView(EmptyView())
                    )
                }
                .listStyle(.plain)
                .onChange(of: visibleEvents.map(\.id)) { _, ids in
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

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
    // presented. A FRESH open shows it immediately; a RESTORED instance
    // starts with this `false` and only flips `true` once
    // `postDismissRevealTask` (below) fires, after Event Detail's own
    // dismissal animation has fully finished PLUS the ticket's explicit
    // additional 1.0s pause — never early, never behind the outgoing
    // Event Detail screen.
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
    private let eventDetailDismissDuration: TimeInterval = 0.28
    /// The ticket's own explicit, additional pause AFTER that animation —
    /// deliberate, not incidental.
    private let postDismissRevealDelay: TimeInterval = 1.0
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
    init(restored: MapExploreState?, isPreview: Bool = false) {
        hadRestoredState = restored != nil
        self.isPreview = isPreview
        restoreBubbleProgress = restored != nil ? 0 : 1
        // Bug 2 follow-up: a fresh open has nothing to wait for — reveal
        // immediately, as before. A restored instance starts hidden; `.task`
        // reveals it only after `eventDetailDismissDuration +
        // postDismissRevealDelay` has elapsed.
        _sheetPresented = State(initialValue: restored == nil)
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
            Map(position: $cameraPosition) {
                ForEach(visibleEvents) { ev in
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
                Button { closeMap() } label: {
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
        .onChange(of: visibleEvents.map(\.id)) { _, ids in
            // The selected event must honor every active filter this
            // screen has, exactly like the pins/list it was picked from —
            // if a poll refresh or a filter change makes it fall out of
            // `visibleEvents` (cancelled, sold out and filtered by "Còn
            // chỗ", recategorized, or just no longer in the current bbox),
            // the selection clears itself instead of the card going stale.
            // No second query: this only ever reads the same
            // `visibleEvents` the map/list already render.
            //
            // Guarded on `mapEventsLoading == false`: a restored `selectedId`
            // (bug 2) is applied before `app.mapEvents` has necessarily
            // settled from its own reload, and without this guard that
            // transient "not loaded yet" state was indistinguishable from
            // "genuinely filtered out" — the same race the web build hit
            // and fixed the same way.
            if !app.mapEventsLoading, let id = selectedId, !ids.contains(id) { selectedId = nil }
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
                // commit), and springs back up with the same character if
                // the swipe is released without committing, since
                // `app.mapCloseSwipeProgress` itself is what animates back
                // to 0 in that case (see `RootView.swift`'s own gesture
                // handlers). The explicit "← Đóng" button drives the exact
                // same published value for the same visual — see
                // `closeMap()`.
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
                // AND the ticket's explicit additional 1.0s has elapsed —
                // never early, never behind the outgoing screen. Held in
                // `postDismissRevealTask` so `.onDisappear` can cancel it:
                // if the user leaves this instance again before the delay
                // completes (a second navigation, or a fast repeated
                // gesture), it must never reveal stale UI onto whatever
                // screen is now showing instead.
                postDismissRevealTask = Task {
                    let delayNanoseconds = UInt64((eventDetailDismissDuration + postDismissRevealDelay) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    guard !Task.isCancelled else { return }
                    sheetPresented = true
                    // ANIMATION REQUIREMENT: the one and only place
                    // `restoreBubbleProgress` is ever written after `init` —
                    // fires at the exact same moment the sheet/card reveal.
                    withAnimation(.interpolatingSpring(stiffness: 180, damping: 14)) {
                        restoreBubbleProgress = 1
                    }
                }
            } else {
                centerOnDensityHotspot()
            }
        }
        .onDisappear {
            // Bug 2 follow-up: guards the delayed reveal above — cancelling
            // here means a torn-down instance (the user left again before
            // the 1.28s elapsed) can never fire `sheetPresented = true`
            // onto whatever's on screen now.
            postDismissRevealTask?.cancel()
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
        app.goEvent(id)
    }

    /// An explicit exit (as opposed to "on my way to Event Detail, be right
    /// back") clears the snapshot — reopening the map later from Home
    /// should start fresh, not silently resume an unrelated past session.
    ///
    /// Task 1 (11-realtime-map.md follow-up): mirrors RootView's own
    /// edge-swipe-commit timing (animate the shared progress to 1, THEN —
    /// after that animation's own duration — actually switch screens and
    /// reset the value) so the button gives the exact same shrink/bubble
    /// visual as the swipe gesture, from the one shared signal, rather than
    /// a second, button-specific animation.
    private func closeMap() {
        withAnimation(.easeOut(duration: 0.22)) { app.mapCloseSwipeProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            app.mapExploreState = nil
            app.mapCloseSwipeProgress = 0
            app.goBack()
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
        if catFilter != "all" { list = list.filter { effectiveCatKey($0) == catFilter } }
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
                        if let path = EventCatalog.find(ev.id)?.img {
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
                        }
                        Spacer()
                    }
                    .id(ev.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectEvent(ev) }
                    .onAppear {
                        if ev.id == visibleEvents.last?.id { Task { await app.loadMapEvents(bounds: lastQueriedRegion.map(boundsOf)) } }
                    }
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

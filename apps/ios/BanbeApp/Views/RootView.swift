import SwiftUI
import UIKit

/// Top-level screen switch and sheet host — the iOS equivalent of the
/// SCREENS map and sheet layer in src/App.jsx. One screen shows at a time,
/// with explicit back targets, exactly as the web app does it.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    // Live-follows the finger while an edge swipe is in progress, the same
    // way UIKit's interactivePopGestureRecognizer drags the current view
    // along with the touch instead of just reacting once the gesture ends.
    // A plain @State (not @GestureState) so every touch update can apply
    // with NO implicit animation — layering a spring on top of an already
    // continuous, per-frame gesture value is what was making the drag feel
    // laggy, since it was smoothing toward a target that kept moving.
    @State private var dragTranslation: CGFloat = 0
    @State private var isCommittingBack = false
    @State private var isDragTracking = false

    // Stage 2 (2026-09-27 nav/discovery pass) — root-tab swipe: a
    // left/right horizontal drag on a root screen (BottomTabBar.
    // visibleScreens) moves to the adjacent tab in dock order, exactly as
    // tapping that tab does. `nil` until a drag crosses the start
    // threshold and picks a direction; only "horizontal" ever drives
    // `tabSwipeTranslation`, so a vertical scroll is left entirely to each
    // screen's own ScrollView (this gesture is `.simultaneousGesture`, not
    // `.highPriorityGesture` — it never blocks that scroll from also
    // recognizing the same touch).
    @State private var tabSwipeTranslation: CGFloat = 0
    @State private var tabSwipeDirection: String?
    // Root-tab-swipe fix pass (2026-09-27, follow-up B) — real cause of
    // "destination screen blank/partly missing during the drag, then
    // slides in AGAIN from the left after release": only `app.screen`'s
    // own view was ever rendered/offset here, so a drag revealed nothing
    // behind it, and committing (`BottomTabBar.goto`) changed `app.screen`,
    // which is exactly the value `.animation(value: app.screen)` below
    // watches — replaying the FULL insertion `.transition` on a screen
    // that had already been dragged into place. Non-nil for exactly the
    // 0.22s settle window between a committed tab-swipe and the actual
    // `app.screen` flip — `tabSwipeNeighbor` (below) stays pinned to this
    // target through that whole window so the real destination view (see
    // `rootScreensToRender`) doesn't get dropped and re-added mid-settle.
    @State private var tabSwipeCommittingTarget: Screen?

    // How far in from the leading edge a swipe can originate — matches the
    // HIG's own edge-swipe affordance width. `edgeSwipe` below is attached
    // only to a strip this wide (see the `Color.clear` in `body` carrying
    // `.highPriorityGesture(edgeSwipe)`), not the whole screen — attaching
    // it everywhere (`.simultaneousGesture` on the full ZStack, the
    // previous approach) put it in constant arbitration with every screen's
    // own ScrollView for every touch on screen, which is exactly what made
    // a normal-speed partial swipe sometimes get swallowed by the scroll
    // view's pan recognizer instead — only a slow drag, or one dragged
    // nearly the full width, gave this gesture enough of a window to still
    // win that arbitration. Bounding its hit-testing region to a thin edge
    // strip means a touch that starts outside it is never routed to this
    // recognizer at all, so there's nothing left to arbitrate against the
    // ScrollView beneath it.
    private let edgeSwipeZoneWidth: CGFloat = 20

    private var dragProgress: CGFloat {
        guard !isCommittingBack else { return 1 }
        let width = UIScreen.main.bounds.width
        return width > 0 ? min(1, dragTranslation / width) : 0
    }

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if !isDragTracking {
                    guard app.canSwipeBack else { return }
                    isDragTracking = true
                }
                guard isDragTracking else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = max(0, value.translation.width)
                    // Task 1 (11-realtime-map.md follow-up): mirrors this
                    // gesture's own live progress into
                    // `app.mapCloseSwipeProgress` — see that property's own
                    // doc comment — so `MapExploreView`'s sheet can track
                    // the Map-Explore-closing-to-Home drag directly,
                    // without a second, independent tracker anywhere else.
                    // Scoped to `.mapExplore` specifically: that's the only
                    // screen for which the CURRENT, foreground instance
                    // being dragged away is ever a `MapExploreView` at all
                    // (the Event-Detail-to-Map-Explore swipe reveals
                    // MapExploreView as the non-interactive `isPreview`
                    // BACKDROP underneath, a different, already-handled
                    // case — see that flag's own doc comment).
                    if app.screen == .mapExplore { app.mapCloseSwipeProgress = dragProgress }
                }
            }
            .onEnded { value in
                defer { isDragTracking = false }
                guard isDragTracking, abs(value.translation.height) < 80 else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { dragTranslation = 0 }
                    cancelMapCloseSwipe()
                    return
                }
                // A firm flick commits even if it hasn't crossed the
                // halfway mark yet — matches how forgiving the system
                // gesture is about a fast, short swipe.
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.35
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    withAnimation(.easeOut(duration: 0.22)) { isCommittingBack = true }
                    // Task 1 (11-realtime-map.md follow-up): a completed
                    // edge-swipe now calls the EXACT SAME shared confirm
                    // path the "← Đóng" button calls — not a second,
                    // parallel implementation. `AppState.confirmMapExploreClose()`
                    // owns the fast sheet-dismiss animation, the snapshot
                    // clear, and (0.22s later) the actual `goBack()` —
                    // see the `.onChange(of: isCommittingBack)` handler
                    // below for why this view's own generic reset must NOT
                    // also call `goBack()` for this specific screen.
                    app.confirmMapExploreClose()
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { dragTranslation = 0 }
                    cancelMapCloseSwipe()
                }
            }
    }

    /// Task 2 (11-realtime-map.md follow-up): an interrupted swipe must
    /// NOT navigate anywhere (it never did — `isCommittingBack` never
    /// becomes `true` on this path, so `goBack()` is never reached) — it
    /// only needs to undo the LIVE-drag visual feedback and hand off to
    /// `MapExploreView`'s own hide-then-reveal recovery, which reuses the
    /// exact same delayed-reveal mechanism as returning from Event Detail
    /// (`AppState.mapCloseSwipeCancelled`, observed by that view — see its
    /// own doc comment). `mapCloseSwipeProgress` is reset unanimated, not
    /// sprung back over ~1s the way the prior pass did: it drives a
    /// content transform that's about to be hidden entirely (`sheetPresented
    /// = false`) anyway, so animating it here would be invisible work.
    private func cancelMapCloseSwipe() {
        guard app.screen == .mapExplore else { return }
        app.mapCloseSwipeProgress = 0
        app.mapCloseSwipeCancelled = true
    }

    private var isPeeking: Bool { isDragTracking || isCommittingBack }

    // Stage 2 — same 70pt commit distance as the web equivalent
    // (App.jsx's Shell, SWIPE_COMMIT_PX).
    private let tabSwipeCommitDistance: CGFloat = 70

    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard BottomTabBar.visibleScreens.contains(app.screen) else { return }
                if tabSwipeDirection == nil {
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) < 10 && abs(dy) < 10 { return }
                    if abs(dy) >= abs(dx) {
                        tabSwipeDirection = "vertical"
                        return
                    }
                    let width = UIScreen.main.bounds.width
                    let startX = value.startLocation.x
                    // Reserves the SAME leading-edge strip edgeSwipeBack
                    // already owns (edgeSwipeZoneWidth), on every root
                    // screen — never just Map — and, for Map specifically,
                    // a narrow strip near the trailing edge is the ONLY
                    // place this engages at all (map panning owns the rest
                    // of the canvas), mirroring the web equivalent's own
                    // EDGE_RESERVE_PX/Map-specific narrowing exactly.
                    if startX < edgeSwipeZoneWidth {
                        tabSwipeDirection = "vertical"
                        return
                    }
                    if app.screen == .mapExplore && startX < width - edgeSwipeZoneWidth {
                        tabSwipeDirection = "vertical"
                        return
                    }
                    tabSwipeDirection = "horizontal"
                }
                guard tabSwipeDirection == "horizontal" else { return }
                let idx = BottomTabBar.dockOrder.firstIndex(of: app.screen)
                let canNext = idx != nil && idx! < BottomTabBar.dockOrder.count - 1
                let canPrev = (idx ?? 0) > 0
                var dx = value.translation.width
                if dx < 0 && !canNext { dx *= 0.25 }
                if dx > 0 && !canPrev { dx *= 0.25 }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { tabSwipeTranslation = dx }
            }
            .onEnded { value in
                guard tabSwipeDirection == "horizontal" else {
                    tabSwipeDirection = nil
                    return
                }
                let idx = BottomTabBar.dockOrder.firstIndex(of: app.screen)
                let dx = value.translation.width
                let width = UIScreen.main.bounds.width
                if dx <= -tabSwipeCommitDistance, let idx, idx < BottomTabBar.dockOrder.count - 1 {
                    commitTabSwipe(to: BottomTabBar.dockOrder[idx + 1], settleTranslation: -width)
                } else if dx >= tabSwipeCommitDistance, let idx, idx > 0 {
                    commitTabSwipe(to: BottomTabBar.dockOrder[idx - 1], settleTranslation: width)
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { tabSwipeTranslation = 0 }
                    tabSwipeDirection = nil
                }
            }
    }

    /// Settles the CURRENT and NEIGHBOR views (both already mounted — see
    /// `rootScreensToRender`) the rest of the way to their final positions
    /// over one real animation, then — only once that finishes — actually
    /// flips `app.screen` and resets all the swipe state in a single
    /// unanimated transaction. That ordering is the whole fix: the
    /// destination view's identity (`tabSwipeCommittingTarget`, mirrored by
    /// `rootScreensToRender`'s own `id`-stable `ForEach`) never disappears
    /// and reappears, so SwiftUI never treats it as a fresh insertion and
    /// never replays its own insertion `.transition` — the "slides in AGAIN"
    /// bug this fixes. Mirrors `RootView`'s own `isCommittingBack`/
    /// `.onChange(of: isCommittingBack)` handler exactly, the proven
    /// pattern already established here for edge-swipe-back.
    private func commitTabSwipe(to screen: Screen, settleTranslation: CGFloat) {
        tabSwipeCommittingTarget = screen
        withAnimation(.easeOut(duration: 0.22)) { tabSwipeTranslation = settleTranslation }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                BottomTabBar.goto(screen, app: app)
                tabSwipeTranslation = 0
                tabSwipeDirection = nil
                tabSwipeCommittingTarget = nil
            }
        }
    }

    /// The real adjacent screen while a horizontal tab-swipe drag is live,
    /// OR the real destination while a committed swipe is still settling
    /// (see `commitTabSwipe`) — `nil` the rest of the time, in which case
    /// `rootScreensToRender` renders exactly `[app.screen]`, identical to
    /// this file's previous single-screen behavior for every other
    /// navigation (edge-swipe-back, a plain dock tap, any push/pop).
    private var tabSwipeNeighbor: Screen? {
        if let target = tabSwipeCommittingTarget { return target }
        guard tabSwipeDirection == "horizontal" else { return nil }
        guard let idx = BottomTabBar.dockOrder.firstIndex(of: app.screen) else { return nil }
        if tabSwipeTranslation < 0, idx < BottomTabBar.dockOrder.count - 1 { return BottomTabBar.dockOrder[idx + 1] }
        if tabSwipeTranslation > 0, idx > 0 { return BottomTabBar.dockOrder[idx - 1] }
        return nil
    }

    /// `[app.screen]` normally; `[app.screen, neighbor]` while a horizontal
    /// tab-swipe is live or settling — both real, fully mounted screens
    /// (never a throwaway/`isPreview` copy: the ticket's own "start its
    /// existing loader early" ask means the neighbor's normal `.task`/
    /// `.onAppear` should fire the instant it's revealed, not be suppressed).
    /// `ForEach(id: \.self)` is what actually preserves the neighbor's
    /// identity across the commit above: it's present in this array both
    /// right before AND right after `app.screen` flips to it, so SwiftUI
    /// never tears it down in between.
    private var rootScreensToRender: [Screen] {
        guard BottomTabBar.visibleScreens.contains(app.screen), let neighbor = tabSwipeNeighbor else { return [app.screen] }
        return [app.screen, neighbor]
    }

    private func offsetForRootScreen(_ screen: Screen) -> CGFloat {
        if screen == app.screen {
            return (isCommittingBack ? UIScreen.main.bounds.width : dragTranslation) + tabSwipeTranslation
        }
        // The tab-swipe neighbor only (edge-swipe-back's own peek is a
        // separate, mutually-exclusive mechanism — see this gesture's own
        // doc comment) — positioned exactly one screen-width away in the
        // direction it's coming from, sliding to 0 as `tabSwipeTranslation`
        // follows the finger, one shared coordinate system with the
        // current screen above.
        let width = UIScreen.main.bounds.width
        guard let idx = BottomTabBar.dockOrder.firstIndex(of: app.screen),
              let neighborIdx = BottomTabBar.dockOrder.firstIndex(of: screen) else { return tabSwipeTranslation }
        let sign: CGFloat = neighborIdx > idx ? 1 : -1
        return tabSwipeTranslation + sign * width
    }

    /// BUG 1 fix (2026-09-22 tenth follow-up) — true whenever the
    /// currently-showing screen is an Event Detail reached FROM a story
    /// (`app.eventBackIsStory`, set/cleared by
    /// `goEventFromStory()`/`backFromEvent()`/`goEvent()` — see
    /// AppState.swift). While true, the retained `app.storyViewer` (no
    /// longer nulled out on this path — see `goEventFromStory()`'s own
    /// comment) is the genuine underlay to reveal during an edge-swipe,
    /// not the generic `backTargetScreen` preview copy.
    /// BUG 3 fix (2026-09-22 fifteenth follow-up) — real bug, confirmed by
    /// reading: `goOrganizer()` (AppState.swift) is a plain `screen =
    /// .organizer`, and never touches `eventBackIsStory` — correct, since
    /// Organizer's own back (`backToEvent()`) unconditionally returns to
    /// `.event` regardless of how Event Detail itself was reached, so
    /// there's no NEW back-target state needed here (matches this ticket's
    /// own "use existing back-target/patterns" instruction). But this
    /// computed property used to check ONLY `screen == .event`, so the
    /// instant Organizer opened (`screen` becomes `.organizer`,
    /// `eventBackIsStory` stays true — it's never cleared going into
    /// Organizer), it evaluated false — flipping the retained StoryViewer
    /// back to full zIndex/hit-testing/`isSuspended: false` (RESUMING its
    /// timer) directly on top of Organizer, exactly the reported "tapping
    /// Organizer/Visit makes StoryViewer appear instead." Widened to also
    /// cover `.organizer` reached from that same story-originated Event
    /// Detail — StoryViewer now stays suspended/hidden underneath BOTH
    /// screens, only resurfacing once `backFromEvent()` actually clears
    /// `eventBackIsStory` and leaves the `.event`/`.organizer` cluster
    /// entirely.
    private var storyUnderlaysEvent: Bool {
        (app.screen == .event || app.screen == .organizer) && app.eventBackIsStory
    }
    /// BUG 3 fix (2026-09-22 fifteenth follow-up) — narrower than
    /// `storyUnderlaysEvent` above ON PURPOSE: this ONLY gates the generic
    /// `backTargetScreen` peek block below, which must still fire normally
    /// for an Organizer -> Event Detail edge-swipe (backTargetScreen for
    /// `.organizer` is `.event`, a real screen worth peeking at — see
    /// AppState.swift's own `backTargetScreen`). Widening `storyUnderlaysEvent`
    /// itself to include `.organizer` would have also suppressed THAT peek
    /// (since it's gated on `!storyUnderlaysEvent`), leaving an
    /// Organizer-edge-swipe reveal nothing at all instead of Event Detail.
    /// Only `.event`'s OWN backTargetScreen (`eventBackScreen`, typically
    /// Home) is actually redundant/wrong to peek at when the real underlay
    /// is the retained story.
    private var eventDetailFromStory: Bool { app.screen == .event && app.eventBackIsStory }

    /// A sliver of parallax on the revealed screen — it drifts in from
    /// slightly off-frame rather than sitting flush at 0, the same subtle
    /// depth cue UIKit's pop transition gives the view underneath.
    private var peekOffset: CGFloat {
        -(1 - dragProgress) * UIScreen.main.bounds.width * 0.28
    }

    var body: some View {
        ZStack {
            // BUG 2 fix (2026-09-22 fourteenth follow-up) — real root cause
            // of the white-blank-instead-of-story reveal: this background
            // had NO explicit zIndex, defaulting to 0 — the SAME implicit
            // value as `screenView(for: app.screen)` below. The retained
            // `StoryViewerView` below is intentionally kept at `.zIndex(-1)`
            // while suspended (so Event Detail's own slide-away offset
            // progressively reveals it, not a snap to front — see that
            // zIndex's own comment). But -1 is LOWER than this background's
            // implicit 0, so as Event Detail slid away, what actually got
            // uncovered was this opaque paper/white background sitting
            // ABOVE StoryViewerView, not StoryViewerView itself — the
            // reported white blank. Pinning this explicitly below -1
            // guarantees it can never again outrank a retained, suspended
            // underlay that intentionally sits at a negative zIndex.
            app.palette.paper.ignoresSafeArea()
                .zIndex(-2)

            // The screen a swipe-back would land on, revealed underneath as
            // it drags instead of leaving blank paper — this is what was
            // missing: dragging used to uncover empty space because nothing
            // was actually rendered behind the current screen.
            if isPeeking {
                // `isPreview: true` — follow-up bug 1/2 (11-realtime-map.md):
                // this was the actual confirmed root cause of "edge-swipe
                // back to Map Explore returns to a broken/reloaded state."
                // Before this flag existed, this peeked-at copy was a FULL
                // `MapExploreView(restored:)` instance — including its own
                // `.task`, which awaits `app.loadMapEvents()` and then
                // clears `app.mapExploreState` once it resolves. That ran
                // for every edge-swipe drag the user started, including ones
                // that never committed (sprang back to Event Detail) — a
                // second, independent load/clear race against whichever
                // instance the ACTUAL navigation later creates. A user who
                // merely touched-and-released near the edge, then tapped
                // "‹ Bản đồ" afterward, could already have had their
                // snapshot silently wiped by this throwaway preview's own
                // `.task` before the real return ever happened. `isPreview`
                // stops this copy from running any of that side-effecting
                // work — it only needs to render, from whatever `app.mapEvents`/
                // `app.mapExploreState` already hold, a static visual
                // backdrop (`.allowsHitTesting(false)` below already makes
                // it non-interactive).
                // BUG 1 fix (2026-09-22 tenth follow-up) — when the screen
                // underneath is an Event Detail opened FROM a story, the
                // genuine underlay is the retained `app.storyViewer`
                // (rendered separately below, at full opacity/zIndex
                // during a peek), not a throwaway preview of
                // `backTargetScreen` (Home) — showing both would be
                // visually redundant, and the whole point of this fix is
                // that Home must never be what appears here at all.
                // BUG 3 fix (2026-09-22 fifteenth follow-up) — `eventDetailFromStory`
                // (narrower than `storyUnderlaysEvent`, see its own comment)
                // so an Organizer -> Event Detail edge-swipe still peeks at
                // real Event Detail content here, not nothing.
                if !eventDetailFromStory {
                    screenView(for: app.backTargetScreen, isPreview: true)
                        .offset(x: peekOffset)
                        .overlay(Color.black.opacity((1 - dragProgress) * 0.1))
                        .allowsHitTesting(false)
                }
            }

            // Root-tab-swipe fix pass (2026-09-27, follow-up B) — was a
            // single `screenView(for: app.screen)`. `rootScreensToRender`
            // is `[app.screen]` for every navigation except a live/settling
            // horizontal tab-swipe, where it's briefly `[app.screen,
            // neighbor]` — see that property's own doc comment for why
            // this, combined with `ForEach`'s identity-preserving diffing,
            // is what actually fixes both the blank-neighbor and the
            // double-slide-in bugs.
            ForEach(rootScreensToRender, id: \.self) { s in
                screenView(for: s)
                // Only the CURRENT screen plays the push/pop cross-fade —
                // the neighbor is positioned manually (offsetForRootScreen)
                // and must never independently fade/slide in on its own.
                .transition(s == app.screen ? .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity.combined(with: .move(edge: .trailing))
                ) : .identity)
                .offset(x: offsetForRootScreen(s))
                .allowsHitTesting(s == app.screen)
                .zIndex(s == app.screen ? 1 : 0)
            }
            // Every screen change — swiped back, tapped back, or pushed
            // forward — cross-fades with a slight horizontal drift instead
            // of a hard cut, which is most of what made it feel unlike a
            // native push/pop. Suppressed for a committing tab-swipe too
            // (its own settle animation already handles the motion, and
            // `commitTabSwipe`'s later transaction disables animation
            // entirely for the actual `app.screen` flip) — the same
            // reasoning `isCommittingBack`/`dragTranslation` already apply
            // to edge-swipe-back here.
            .animation(isCommittingBack || dragTranslation > 0 || tabSwipeCommittingTarget != nil ? nil : .easeInOut(duration: 0.28), value: app.screen)
            .simultaneousGesture(tabSwipeGesture)
            // Depth cue on the dragged edge, same as UIKit's pop shadow.
            .shadow(color: .black.opacity(dragProgress * 0.16), radius: 16, x: -6, y: 0)
            // Belt-and-suspenders once a drag is already tracking: keeps a
            // screen's own ScrollView from also visibly jiggling/scrolling
            // while it's being dragged sideways. `edgeSwipeZone` below is
            // what actually keeps the two gestures from arbitrating over the
            // same touch in the first place.
            .scrollDisabled(isDragTracking || isCommittingBack)

            // The swipe-back gesture itself, confined to a thin strip along
            // the leading edge rather than attached to the whole screen —
            // see `edgeSwipeZoneWidth`'s comment for why. `highPriorityGesture`
            // (not `simultaneousGesture`) so that, within this strip, it wins
            // outright over whatever's underneath the instant it recognizes;
            // a touch that never moves past `minimumDistance` (an ordinary
            // tap — e.g. a back-button link whose hit area happens to graze
            // this strip) never recognizes at all, so it still reaches
            // whatever's underneath normally.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: edgeSwipeZoneWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .highPriorityGesture(edgeSwipe)

            // Names the current screen for UI tests, the same way the web
            // screens carry a data-screen-label attribute for Playwright.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("screen.\(app.screen.rawValue)")

            if app.areaAsking { AreaSheetView() }
            if app.askingLocation { LocationSheetView() }
            if app.reasonPrompt != nil { ReasonSheetView() }
            if let photo = app.photoViewer { PhotoViewerView(item: photo) }
            if app.chatPhotoViewer != nil { ChatPhotoViewerView() }
            // BUG 1 fix (2026-09-22 tenth follow-up) — `app.storyViewer`
            // now stays retained (non-nil) the whole time Event Detail is
            // showing after being opened FROM a story (see
            // AppState.goEventFromStory()'s own comment), so this can no
            // longer be a plain `if app.storyViewer != nil { StoryViewerView() }`
            // — that would render it ON TOP of Event Detail at rest, not
            // just during the edge-swipe peek. `isSuspended` pauses its
            // internal timer/gesture and drops it BELOW Event Detail in
            // z-order and out of hit-testing while `storyUnderlaysEvent`
            // and not peeking; the moment a peek starts (or the swipe
            // fully completes and `screen` leaves `.event`), it's exactly
            // the same single retained instance becoming visible again —
            // never a second `StoryViewerView` instance.
            if app.storyViewer != nil {
                // `isSuspended` pauses the story's own timer/progress for
                // the WHOLE time Event Detail is the nominal top screen —
                // including while peeking (a cancelled peek must not have
                // silently burned through story time the user only ever
                // glanced at); the zIndex/hit-testing below are the
                // separate VISUAL concern of when it's actually revealed.
                // BUG 1 fix (2026-09-22 thirteenth follow-up) — this used to
                // read `storyUnderlaysEvent && !isPeeking`, flipping zIndex
                // to 27 (ABOVE Event Detail) the instant a drag merely
                // started (`isDragTracking` goes true almost immediately,
                // `minimumDistance: 4`). That put StoryViewer on TOP of
                // Event Detail at full opacity/position from the first
                // pixel of travel — a snap, not a reveal — instead of
                // letting Event Detail's own already-continuous
                // `dragTranslation` offset (below, in `body`) progressively
                // uncover it. StoryViewer must stay BEHIND (zIndex -1, same
                // relative order as the generic `backTargetScreen` peek)
                // for the WHOLE time `storyUnderlaysEvent` is true —
                // through the drag AND through `isCommittingBack`'s slide-
                // off — only rising to zIndex 27 once `app.screen` actually
                // leaves `.event` (which naturally flips `storyUnderlaysEvent`
                // false once `goBack()` fires in the `isCommittingBack`
                // handler below).
                // BUG 2 fix (2026-09-22 fifteenth follow-up) — StoryViewerView's
                // own root already calls `.ignoresSafeArea()` on its black
                // backdrop, but that alone doesn't guarantee THIS instance
                // (embedded as a RootView ZStack sibling) is ever actually
                // PROPOSED the full device bounds rather than the safe-area-
                // reduced layout bounds every other ZStack sibling here
                // implicitly works within — the reported "gaps at top/
                // bottom, a sliver of Home visible behind it" is exactly
                // that shortfall. Forcing it here, at the outermost point
                // this view is placed into RootView's layout, is the same
                // pattern the root `app.palette.paper` background above
                // already uses and removes any ambiguity about what's
                // proposing what size to it.
                StoryViewerView(isSuspended: storyUnderlaysEvent)
                    .ignoresSafeArea()
                    .zIndex(storyUnderlaysEvent ? -1 : 27)
                    .allowsHitTesting(!storyUnderlaysEvent)
            }
            if app.loading { loadingOverlay }

            if !app.toasts.isEmpty {
                ToastOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // TASK C (2026-10-03 fix pass) — the floating pill FAB that
            // used to live here (CreateEventFabView) is gone; its
            // replacement (DockCreateButtonView) now lives inside
            // BottomTabBarOverlay's own separate window, next to the dock
            // itself, per this ticket's own "work with the existing
            // overlay, don't add another competing floating UIWindow"
            // instruction — see that file's doc comment.
            //
            // TASK 1 (2026-10-05 fix pass) — the tray THAT BUTTON opens
            // (DockCreateTrayView) lives here instead, in this main
            // window's own ZStack — see that view's own doc comment for
            // why (it needs to dim/cover the real screen, which the dock's
            // small band-sized overlay window cannot do).
            if app.dockCreateTrayOpen { DockCreateTrayView().zIndex(28) }

            // BUG 3 follow-up (this session's real-device report on
            // 80c1ac3): BottomTabBar used to render HERE, as a ZStack
            // sibling with an explicit `.zIndex(10)` — correctly ordered
            // against MapExploreView's native `Map()` view (a real ZStack
            // sibling), but with zero effect against MapExploreView's
            // filter/list sheet, which is a genuine `.sheet()` presentation
            // layered by UIKit above this ENTIRE ZStack's content, not a
            // ZStack sibling at all. See BottomTabBarOverlay.swift's own
            // doc comment for the full investigation and why the fix is a
            // separate always-on-top UIWindow instead — attached below via
            // `.onAppear`, rendering the bar independently of this ZStack
            // (and therefore independently of whatever's presented modally
            // over it) for every screen in `BottomTabBar.visibleScreens`.
            // One known trade-off: the overlay doesn't know about
            // `isPeeking` (a plain `@State` local to this view), so unlike
            // before, the bar stays tappable for the brief moment an
            // edge-swipe-back is peeking at the previous screen — a narrow
            // edge case, not the one this fix targets.

            // Face ID app-lock sits above everything — see FaceIDLockView.
            // Task 2: splash must show BEFORE the Face ID prompt, not
            // simultaneously over it — held off while app.screen == .splash.
            if auth.isLocked && app.screen != .splash { FaceIDLockView() }
        }
        .animation(.easeInOut(duration: 0.2), value: app.areaAsking)
        .animation(.easeInOut(duration: 0.2), value: app.askingLocation)
        .animation(.easeInOut(duration: 0.2), value: app.photoViewer)
        // The screen switch above is a plain ZStack, not a NavigationStack,
        // so it never got the system's edge-swipe-to-go-back for free — the
        // `edgeSwipeZone` strip above reproduces it, tracking the finger
        // live rather than jumping only once the gesture ends.
        .onChange(of: isCommittingBack) { _, committing in
            guard committing else { return }
            // Let the slide-off animation actually play before switching
            // screens, then reset instantly — the incoming screen is a
            // different view entirely, so there's nothing to visibly snap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // By the time this runs, the peeked-at screen is already
                // sitting exactly where the real one is about to appear —
                // so this swap must be completely unanimated. Without
                // forcing that here, isCommittingBack flips to false in the
                // same tick app.screen changes, which un-suppresses the
                // .animation(value: app.screen) below and replays its
                // slide-in transition on top of a screen that's already in
                // place, reading as a jerk back into position.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    // Task 1 (11-realtime-map.md follow-up): Map Explore's
                    // own confirmed close now navigates through the SHARED
                    // `AppState.confirmMapExploreClose()` (called directly
                    // from the commit branch above), which already owns
                    // its own `goBack()`/snapshot-clear/progress-reset
                    // timing on its own, independently-scheduled 0.22s
                    // timer. Calling `goBack()` again here for that same
                    // screen would double-navigate — every OTHER screen's
                    // swipe-back still goes through this generic path
                    // exactly as before, unaffected.
                    if app.screen != .mapExplore { app.goBack() }
                    isCommittingBack = false
                    // The offset formula falls back to dragTranslation once
                    // isCommittingBack flips back off — leaving it at the
                    // drag's last value pushed the newly-arrived screen off
                    // to the right instead of resetting to 0.
                    dragTranslation = 0
                }
            }
        }
        .preferredColorScheme(app.theme == "dark" ? .dark : .light)
        // BottomTabBarOverlay.swift: the bar now lives in its own always-
        // on-top UIWindow instead of this ZStack — attach it once a
        // UIWindowScene actually exists. Idempotent (guards on `window ==
        // nil` internally), so re-running this on every appearance of
        // RootView (there's only ever one, but harmless either way) is fine.
        .onAppear {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene {
                BottomTabBarOverlay.shared.attach(to: scene, appState: app)
            }
        }
        .fullScreenCover(isPresented: $app.scanningQr) { QRScannerView() }
        // TASK E (2026-10-01 UX foundation pass) — Banbe Pulse.
        .fullScreenCover(isPresented: $app.pulseOpen) { PulseViewerView() }
        // The session is owned by AuthViewModel (it also drives the Face ID
        // lock); AppState mirrors it into the profile/bookings/notifications
        // the screens read.
        .task(id: auth.session?.user.id) { await app.applySession(auth.session) }
        .onChange(of: auth.session?.user.id) { _, _ in
            // Signing in from a gated screen returns to whatever asked for it.
            if auth.session != nil && app.screen == .login { app.screen = app.authReturnScreen }
        }
        // Task 1 — no guest browsing of any screen: the single, centralized
        // enforcement point, rather than auditing every `screen = .x`
        // call site in this large app individually. Catches cases the
        // targeted fixes (finishOnboarding, dismissSplash, signOut) don't
        // — e.g. goHome()'s plain `screen = .home`, callable from
        // anywhere, has no auth check of its own.
        .onChange(of: app.screen) { oldScreen, newScreen in
            if !app.isSignedIn && !AppState.guestAllowedScreens.contains(newScreen) {
                app.authMandatory = true
                app.authReturnScreen = newScreen
                app.authBackScreen = newScreen
                app.screen = .login
            }
            // BUG 1 fix (2026-09-22 tenth follow-up) — `app.storyViewer`
            // now stays retained across an Event Detail opened from a
            // story (see AppState.goEventFromStory()'s own comment)
            // instead of being cleared up front, so any OTHER way the
            // screen leaves `.event` — a "Reserve"/"other events" tap,
            // anything that isn't `backFromEvent()`'s own sanctioned
            // return-to-story path — must explicitly discard it here, or
            // it would linger and pop back up (full zIndex/interactive)
            // over whatever screen this navigation actually lands on.
            // `backFromEvent()`/`goEvent()` already clear
            // `eventBackIsStory` THEMSELVES as part of the very same
            // state update that changes `screen` — so by the time this
            // fires, `eventBackIsStory` being STILL true is exactly the
            // signal that this wasn't that sanctioned path.
            // `.organizer` is explicitly exempted — `backToEvent()`
            // returns straight to `.event` from there, and
            // `eventBackScreen` itself already treats `.organizer` as
            // "still within this event's own neighborhood" (see
            // `goEvent()`'s own condition) — an Organizer round-trip must
            // not lose the story context either.
            if oldScreen == .event, newScreen != .event, newScreen != .organizer, app.eventBackIsStory {
                app.eventBackIsStory = false
                app.closeStoryViewer()
            }
            // Every screen change starts the bottom tab bar back at full
            // size, matching src/App.jsx Shell's own per-screen reset.
            app.bottomBarCollapsed = false
            // BUG follow-up (a5fd823 real-device report: Reserve/View
            // Ticket unresponsive on Event Detail) — see
            // BottomTabBarOverlay.updateVisibility()'s own doc comment for
            // the full root cause. Must run on every screen change, not
            // just once at attach time, since the overlay window persists
            // for the app's lifetime and otherwise keeps intercepting
            // touches in its band on screens the bar was never meant to
            // show on.
            BottomTabBarOverlay.shared.updateVisibility(for: newScreen)
        }
        // Task 1 (2026-09-22 follow-up, 07-notifications.md) — StoryViewer
        // opens over Home/Profile WITHOUT a `Screen` change (it's an
        // overlay, not a navigation), so the `.onChange(of: app.screen)`
        // above never sees it. A separate, dedicated flag on the overlay
        // (not folded into `forcedHidden`) so this and InboxView's own
        // screen-local sheet check can't stomp on each other.
        .onChange(of: app.storyViewer) { _, viewer in
            BottomTabBarOverlay.shared.setStoryViewerOpen(viewer != nil)
        }
        // TASK E (2026-10-01 UX foundation pass) — same reasoning as
        // storyViewer above.
        .onChange(of: app.pulseOpen) { _, open in
            BottomTabBarOverlay.shared.setPulseViewerOpen(open)
        }
        // TASK 3 (2026-09-22 seventeenth follow-up) — same "separate
        // UIWindow, isHidden not zIndex" reasoning as `setForcedHidden`'s
        // own doc comment: a `.sheet()`/`.confirmationDialog()` presented
        // from a screen-local view (e.g. NotificationsView's "•••" action
        // sheet) sits INSIDE the main window's view hierarchy, which this
        // overlay's separate always-on-top UIWindow still renders above
        // regardless of any SwiftUI zIndex on the sheet's own content —
        // only actually hiding the overlay window (`isHidden = true`) stops
        // it from covering/intercepting taps meant for the sheet. A
        // DEDICATED overlay flag (`setModalActionSheetPresented`, not a
        // reuse of `setForcedHidden`) — see BottomTabBarOverlay.swift's own
        // comment on `modalActionSheetPresented` for why sharing one flag
        // between this and InboxView's unrelated settings-sheet calls would
        // let either caller's "false" clobber the other's still-active
        // "true". Routed through this single `app.modalActionSheetPresented`
        // published flag so any screen-local modal (not just Notifications')
        // can reuse it by toggling one bool, without its own RootView wiring.
        .onChange(of: app.modalActionSheetPresented) { _, presented in
            BottomTabBarOverlay.shared.setModalActionSheetPresented(presented)
        }
        // iPhone fix pass (2026-09-26) — see BottomTabBarOverlay.swift's
        // own `areaSheetOpen` comment: the "Khu vực" sheet is hand-rolled
        // SwiftUI content inside the main window, so this separate
        // always-on-top dock window needs its own explicit signal to hide,
        // same as StoryViewer/Pulse above.
        .onChange(of: app.areaAsking) { _, open in
            BottomTabBarOverlay.shared.setAreaSheetOpen(open)
        }
    }

    /// The SCREENS map, factored out so both the current screen and the
    /// peeked-at previous one (during a swipe) can render from the same
    /// switch instead of keeping two copies in sync. `isPreview` only ever
    /// matters to the `.mapExplore` case (see its own call site's comment)
    /// — every other screen ignores it, so this stays a one-line addition
    /// rather than a second switch to keep in sync.
    @ViewBuilder
    private func screenView(for screen: Screen, isPreview: Bool = false) -> some View {
        switch screen {
        case .splash: SplashView()
        case .langPick: LangPickView()
        case .themePick: ThemePickView()
        case .policy: PolicyView()
        // `MapExploreView.init(restored:)` reads `app.mapExploreState`
        // (11-realtime-map.md, bug 2) directly at construction time — not
        // in a later `.task` — so the very first frame this switch draws
        // already shows the restored camera/detent/filters/selection
        // instead of flashing the defaults for a frame first.
        case .mapExplore: MapExploreView(restored: app.mapExploreState, isPreview: isPreview)
        case .home: HomeView()
        case .profile: AccountView()
        // TASK 2 (2026-09-22 twenty-first follow-up) — see InboxView's own
        // `isPreview` doc comment (MessagingViews.swift): forces the peeked
        // copy to the active thread list, never a duplicated Archived view.
        case .inbox: InboxView(isPreview: isPreview)
        case .event: EventDetailView()
        case .organizer: OrganizerView()
        case .reserve: ReserveView()
        case .confirmed: ConfirmedView()
        case .refunded: RefundedView()
        case .login: LoginView()
        case .chat: ChatView()
        case .dashboard: DashboardView()
        case .hostIntro: HostIntroView()
        case .create: CreateEventView()
        case .attendance: AttendanceView()
        case .preferences: PreferencesView()
        case .editName: EditNameView()
        case .notifications: NotificationsView()
        case .eventList: EventListView()
        case .security: SecurityView()
        case .paymentDetails: PaymentDetailsView()
        case .billing: BillingView()
        case .payout: PayoutView()
        case .documents: DocumentsView()
        case .documentView: DocumentViewerView()
        case .verifications: VerificationsView()
        case .disputes: AdminDashboardView()
        case .adminEvents: AdminEventsView()
        case .refundAccounts: RefundAccountsView()
        case .myRefunds: MyRefundsView()
        case .editProfile: EditProfileView()
        case .publicProfile: PublicProfileView()
        case .organizerProfile: OrganizerProfileView()
        case .reports: ReportsView()
        case .organizerTeam: OrganizerTeamView()
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            app.palette.paper.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 14) {
                // src/screens/Loading.jsx tumbles the mark while it waits.
                BanbeLogo(kind: .mark, width: 54, height: 54)
                ProgressView()
                Text(app.T("Đang giữ chỗ cho bạn…", "Holding your seat…"))
                    .font(.system(size: 13))
                    .foregroundStyle(app.palette.ink)
            }
        }
    }
}

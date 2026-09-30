import SwiftUI
import UIKit
import PhotosUI

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
    // Overlapping-headers fix (2026-09-29 follow-up, real-device report) —
    // the delayed `app.goBack()` in `.onChange(of: isCommittingBack)` below
    // used to fire against whatever `app.screen` happened to be 0.22s
    // later, not the screen this swipe actually started on. A specific
    // notification row (`organizer_invite_response`, the only
    // `openNotification` branch that writes `screen =` synchronously with
    // no `Task` indirection) could race a fast edge-swipe-back and change
    // `app.screen` out from under it mid-gesture, so `goBack()` then
    // navigated from the WRONG screen — producing two different "current
    // screen" computations mid-swipe and the reported header overlap.
    // Captured once, when the drag first crosses its own start threshold.
    @State private var swipeStartScreen: Screen?

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
    // iPhone fix pass (2026-09-27), Item 1 — the real tap-race root cause:
    // `commitTabSwipe` used to unconditionally overwrite `app.screen` (and
    // reset the swipe state) from its own 0.22s-delayed `asyncAfter`
    // closure, with nothing checking whether some OTHER navigation had
    // already happened in the meantime. Reproduction: swipe from Home to
    // Inbox (starts a commit targeting `.inbox`, whose settle callback is
    // now pending), then — before that 0.22s elapses — tap Account in the
    // dock. The tap's own `app.goProfile()` sets `screen = .profile`
    // immediately and synchronously; the STALE swipe-settle callback still
    // fires 0.22s later and calls `BottomTabBar.goto(.inbox, ...)` (the
    // target it captured back when the swipe committed), silently
    // stomping the newer tap and bouncing the user back to Inbox. Same
    // token idiom `BottomTabBarOverlay.visibilityToken` already uses for
    // exactly this "a newer thing may have superseded this stale delayed
    // callback" shape: bumped on EVERY `app.screen` change, from wherever
    // it comes from (a dock tap, a swipe commit, any other navigation) —
    // see the `.onChange(of: app.screen)` below — so `commitTabSwipe`'s own
    // delayed closure can tell whether it's still the most recent
    // navigation before touching `app.screen` again.
    @State private var navGeneration: Int = 0

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
                    swipeStartScreen = app.screen
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
                    // Row-swipe-vs-tab-swipe fix pass (2026-09-28, third
                    // follow-up) — this used to also treat a touch starting
                    // inside a live Inbox row as "vertical" (hands off), via
                    // frames InboxView published. That whole detection layer
                    // is gone: Inbox rows no longer have a competing swipe
                    // gesture of their own (Star/Archive moved to a tap-only
                    // "…" menu — see `InboxRow`'s own doc comment), so there
                    // is nothing left on Inbox for this gesture to defer to.
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
        // iPhone fix pass (2026-09-27), Item 1 — captured BEFORE the settle
        // delay starts; see `navGeneration`'s own doc comment above for why.
        let expectedGeneration = navGeneration
        withAnimation(.easeOut(duration: 0.22)) { tabSwipeTranslation = settleTranslation }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // A newer navigation (a dock tap, another swipe, anything
                // that changed `app.screen`) already happened while this
                // settle was in flight — that navigation's own destination
                // must win, so this stale commit only cleans up its own
                // local visual state and never touches `app.screen` again.
                if navGeneration == expectedGeneration {
                    BottomTabBar.goto(screen, app: app)
                }
                tabSwipeTranslation = 0
                tabSwipeDirection = nil
                tabSwipeCommittingTarget = nil
            }
        }
    }

    /// Interactive-back fix pass (2026-09-27) — extracted so `body` can
    /// attach `tabSwipeGesture` conditionally (root dock screens only)
    /// instead of unconditionally; see that call site's own doc comment.
    ///
    /// iPhone fix pass (2026-09-27, post-ec06c78) — Issues 1 & 2's real,
    /// shared root cause: the ForEach below gives its CURRENT screen an
    /// explicit `.zIndex(1)` (needed only to keep it above its own tab-swipe
    /// NEIGHBOR while both are briefly mounted — see `rootScreensToRender`).
    /// `.zIndex()` in SwiftUI orders ALL views sharing the same enclosing
    /// stacking context, and `ForEach`/`Group`/`if` are transparent
    /// view-builder constructs, not containers — so this zIndex was never
    /// actually scoped to "current vs. neighbor" the way it looked; it
    /// compared against EVERY OTHER sibling in RootView's own outer ZStack
    /// too. Those other siblings (the leading-edge `edgeSwipe` strip,
    /// `PhotoViewerView`, `ChatPhotoViewerView`, the loading overlay,
    /// `ToastOverlay`) have no zIndex of their own — an implicit 0 — so the
    /// CURRENT screen's explicit 1 silently outranked all of them: the
    /// current screen's own full-bleed content sat ABOVE the edge-swipe
    /// strip's hit-testing region (swallowing the touch before the
    /// `.highPriorityGesture` strip could ever see it — Issue 1, "nothing
    /// moves"), and above `PhotoViewerView` too (rendered, but hidden
    /// behind the current screen the whole time — Issue 2, "viewer doesn't
    /// appear... flashes... previous page slides over it": the SECOND that
    /// screen changes and briefly stops being `app.screen`, its zIndex
    /// drops to 0, revealing the still-mounted viewer for one frame, before
    /// the INCOMING screen becomes `app.screen` and claims zIndex 1 right
    /// back over it). Wrapping the ForEach in its own literal `ZStack` gives
    /// it a real, separate stacking context: the 0/1 comparison stays
    /// contained to current-vs-neighbor exactly as intended, and this
    /// wrapper `ZStack` itself carries no explicit zIndex, so it (and
    /// everything inside it) reverts to ordinary declaration-order z-order
    /// against RootView's OTHER siblings — restoring the edge-swipe strip's
    /// and every overlay's rightful place above it.
    private var rootScreenStack: some View {
        ZStack {
            ForEach(rootScreensToRender, id: \.self) { s in
                screenView(for: s, isActive: s == app.screen)
                // Only the CURRENT screen plays the push/pop cross-fade — the
                // neighbor is positioned manually (offsetForRootScreen) and
                // must never independently fade/slide in on its own.
                .transition(s == app.screen ? .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .leading)),
                    removal: .opacity.combined(with: .move(edge: .trailing))
                ) : .identity)
                .offset(x: offsetForRootScreen(s))
                // Accidental-tap-during-swipe fix (2026-09-29) — this used to
                // stay `true` for the CURRENT screen through an entire, slow
                // edge-swipe-back or tab-swipe drag, so a deliberate swipe
                // that happened to end (finger lift) over a button/row still
                // fired that row's own tap — the exact "accidentally
                // triggers items on the home screen or notifications"
                // report. Once a drag has committed to an actual swipe
                // gesture (tab-swipe locked "horizontal", or an edge-swipe-
                // back drag/settle in progress), the screen being dragged
                // away stops accepting touches for the rest of that
                // gesture — an ordinary tap (never crosses either
                // gesture's own recognition threshold) is completely
                // unaffected.
                .allowsHitTesting(s == app.screen && !isScreenLevelSwipeActive)
                .zIndex(s == app.screen ? 1 : 0)
            }
        }
    }

    /// Single shared source of truth for "is a screen-level swipe (tab-
    /// swipe or edge-swipe-back) currently in progress or still settling,"
    /// used for both this screen's own hit-testing/scroll-disabling AND
    /// (mirrored into `AppState.isRootSwipeActive`) for `SwipeSafeButton`
    /// elsewhere in the app — one definition, not two that could drift
    /// apart.
    private var isScreenLevelSwipeActive: Bool {
        tabSwipeDirection == "horizontal" || isDragTracking || isCommittingBack
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
                    screenView(for: app.backTargetScreen, isPreview: true, isActive: false)
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
            // Interactive-back fix pass (2026-09-27) — root cause of "slow
            // leading-edge swipe on a PUSHED screen (EventDetail, a Map
            // detail sheet, CreateEvent, PublicProfile, Reports, …) no
            // longer reveals the real previous screen": `tabSwipeGesture`
            // used to attach via `.simultaneousGesture` UNCONDITIONALLY,
            // for every screen. Its own `onChanged` already no-ops for a
            // non-root screen (the `BottomTabBar.visibleScreens.contains`
            // guard at its top), but a merely-inactive gesture RECOGNIZER
            // still competes for the touch during SwiftUI's own gesture
            // arbitration — two simultaneous DragGesture recognizers
            // overlapping the SAME leading-edge strip (this one at
            // `minimumDistance: 8`, `edgeSwipe` below at `minimumDistance:
            // 4`) is exactly what made a slow, partial drag there
            // unreliable, even though `edgeSwipe` is `.highPriorityGesture`
            // — that only orders recognition relative to gestures on this
            // same view; the tab-swipe recognizer was somewhere else in
            // the hierarchy entirely. The real fix is to never even attach
            // it outside a root dock screen, not just to make its callback
            // a no-op there.
            // Stuck-`app.isRootSwipeActive` fix (2026-09-29, fourth pass —
            // reproduces on an ORDINARY single swipe-back, not a race) —
            // `.onChange(of: isScreenLevelSwipeActive)` (the ONE place that
            // mirrors this out to `app.isRootSwipeActive`, which every
            // `SwipeSafeButton` app-wide reads), `.animation(value:
            // app.screen)`, and `.scrollDisabled(...)` USED to live on
            // `rootScreenStack` itself, INSIDE the `if/else` below. A plain
            // SwiftUI `if/else` in a ViewBuilder compiles to
            // `_ConditionalContent`, so switching branches — e.g. exactly
            // when `app.screen` crosses from a non-dock screen (Event
            // Detail) to a dock screen (Home) at the end of a swipe-back —
            // is a full identity change: SwiftUI tears down the previous
            // branch's `rootScreenStack` instance, `.onChange` handler and
            // all, and mounts a brand-new one for the other branch.
            // `.onChange` never fires for a view's own initial value, so
            // the reset-to-false this same transition was supposed to
            // trigger never happens — `app.isRootSwipeActive` is stuck
            // `true` forever, silently no-op'ing every `SwipeSafeButton`
            // anywhere on the newly-arrived screen (the dock is a separate
            // always-on-top `UIWindow` and never reads this, so it alone
            // kept working). Fixed by hoisting these three modifiers OUT of
            // `rootScreenStack` and onto this `Group` instead — the `Group`
            // itself has stable identity across the branch switch (only
            // ITS content changes), so its own `.onChange` keeps observing
            // continuously right through this transition.
            Group {
                if BottomTabBar.visibleScreens.contains(app.screen) {
                    rootScreenStack.simultaneousGesture(tabSwipeGesture)
                } else {
                    rootScreenStack
                }
            }
            .onChange(of: isScreenLevelSwipeActive) { _, active in
                if active { app.isRootSwipeActive = true } else { app.isRootSwipeActive = false }
            }
            .animation(isCommittingBack || dragTranslation > 0 || tabSwipeCommittingTarget != nil ? nil : .easeInOut(duration: 0.28), value: app.screen)
            .scrollDisabled(isScreenLevelSwipeActive)
            // Depth cue on the dragged edge, same as UIKit's pop shadow.
            .shadow(color: .black.opacity(dragProgress * 0.16), radius: 16, x: -6, y: 0)

            // The swipe-back gesture itself, confined to a thin strip along
            // the leading edge rather than attached to the whole screen —
            // see `edgeSwipeZoneWidth`'s comment for why. `highPriorityGesture`
            // (not `simultaneousGesture`) so that, within this strip, it wins
            // outright over whatever's underneath the instant it recognizes;
            // a touch that never moves past `minimumDistance` (an ordinary
            // tap — e.g. a back-button link whose hit area happens to graze
            // this strip) never recognizes at all, so it still reaches
            // whatever's underneath normally.
            //
            // Review-sheet-swipe-back fix (2026-09-29 follow-up) — this
            // strip used to be attached UNCONDITIONALLY, relying only on
            // `edgeSwipe`'s own internal `canSwipeBack` check to no-op.
            // Exactly the class of bug this file's own tabSwipeGesture
            // comment above already documents: a merely-inactive gesture
            // RECOGNIZER still wins arbitration for any touch starting in
            // this strip, so `CreateEventReviewSheet`'s own local
            // swipe-back gesture (see its doc comment) never even saw a
            // touch that started at the actual screen edge — it just did
            // nothing, which read as "swipe-back stopped working
            // entirely." Not attaching this gesture at all while
            // `canSwipeBack` is false lets that touch fall through to
            // whatever's really underneath, same fix shape as
            // `tabSwipeGesture`'s own conditional attach just above.
            // Reverted (2026-09-29 follow-up, third pass) — tried always
            // mounting this strip and gating `.allowsHitTesting` on
            // `app.canSwipeBack` instead, to keep an in-flight gesture's
            // hosting view stable across a screen change (see git history
            // for that attempt's own reasoning). Real-device result: WORSE,
            // not better — broadly unresponsive buttons across Home,
            // Notifications, and Messages, not just the edge strip. That
            // matches this file's OWN documented finding for
            // `tabSwipeGesture` above: a merely-ATTACHED, inactive gesture
            // recognizer still competes for touches during SwiftUI's
            // arbitration, `allowsHitTesting` or not — it isn't scoped to
            // just this view's own narrow bounds the way plain hit-testing
            // is. Back to the proven conditional-mount shape (never attach
            // the recognizer at all while `canSwipeBack` is false); the
            // orphaned-gesture stuck-flag risk this was trying to close is
            // instead covered by the `.onChange(of: app.screen)` fallback
            // reset above (`isDragTracking = false`, etc.) — a plain @State
            // reset, not a gesture-attachment change, so it can't reintroduce
            // this or the `CreateEventReviewSheet` arbitration bug.
            if app.canSwipeBack {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: edgeSwipeZoneWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .highPriorityGesture(edgeSwipe)
            }

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
            // A/2 (iOS/Map UX pass, 2026-09-27) — Pulse used to be a
            // `.fullScreenCover` (see the removed call below this ZStack) —
            // a wholly separate UIKit presentation layer, which is exactly
            // why its own dismiss gestures could never actually reveal
            // Home continuously underneath (there's no "underneath" inside
            // a cover presentation) and always ended in a second, unrelated
            // system slide-down. Now a plain ZStack sibling, exactly like
            // `PhotoViewerView` above — Home (still `app.screen`, still
            // mounted) sits directly beneath it, so PulseViewerView's own
            // drag-driven `.offset(x:)` reveals the real thing, not a
            // snapshot. `.transition(.identity)`: PulseViewerView owns its
            // ONE dismiss animation entirely itself (see that file's
            // `commitDismiss()`) — this conditional must never layer a
            // second SwiftUI transition on top of it.
            if app.pulseOpen {
                PulseViewerView()
                    .transition(.identity)
                    .zIndex(26)
            }

            if app.loading { loadingOverlay }

            // Pulse teaser pass (2026-09-27) — always in the tree (now just
            // the sequence's state machine/timers on a zero-size invisible
            // view — the visible bubble is drawn by `HomeView.storyRow`, in
            // the ring's own scrolling space; see
            // `PulseTeaserBubbleView`'s own doc comment), never gated on
            // `app.pulseOpen`/`app.screen` here, since it needs to keep
            // observing `app.screen`'s own changes itself to know when to
            // suspend/resume.
            PulseTeaserBubbleView().zIndex(29)

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
            // TASK 1 real-device follow-up — the tray THAT BUTTON opens
            // lives here instead, in this main window's own ZStack (see
            // that view's own doc comment for why: it needs to dim/cover
            // the real screen, which the dock's small band-sized overlay
            // window cannot do). A native SwiftUI `Menu` was tried
            // directly inside that overlay window instead and reverted —
            // see DockCreateButtonView's own doc comment for the
            // real-device clipping bug that caused.
            if app.dockCreateMenuOpen { DockCreateTrayView().zIndex(28) }

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
                    // Only navigate back from the screen this swipe actually
                    // started on — if something else already changed
                    // `app.screen` mid-gesture (see the doc comment on
                    // `swipeStartScreen`), that navigation already happened
                    // and calling `goBack()` here would send the user
                    // somewhere unrelated to either screen.
                    if app.screen != .mapExplore, app.screen == swipeStartScreen { app.goBack() }
                    swipeStartScreen = nil
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
        // TASK E (2026-10-01 UX foundation pass) — Banbe Pulse. No longer a
        // `.fullScreenCover` — see the `if app.pulseOpen { PulseViewerView() }`
        // ZStack sibling above, and that view's own `commitDismiss()` doc
        // comment for the real, confirmed bug this fixes.
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
            // iPhone fix pass (2026-09-27), Item 1 — see `navGeneration`'s
            // own doc comment (top of this file): every real screen change,
            // from any source, invalidates any older in-flight
            // `commitTabSwipe` settle so it can never overwrite this one.
            navGeneration += 1
            // Real-device follow-up — these three are meant to be
            // transient, one-shot triggers (see RootView's own centralized
            // `.photosPicker`/`.fullScreenCover` comment above), but
            // nothing previously cleared them on a genuine screen change.
            // A stray/leftover `true` (e.g. an accidental tap on a
            // clipped/off-screen control — see DockCreateButtonView's own
            // real-device clipping bug) would otherwise keep presenting a
            // full-screen camera/picker cover OVER whatever screen this
            // navigation actually lands on, since these are attached
            // globally, not scoped to one screen.
            if oldScreen != newScreen {
                app.storyLibraryPickerOpen = false
                app.storyCameraOpen = false
            }
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
            // Stuck-Home-interaction fix (2026-09-29 follow-up, real-device
            // report: event cards AND the search FAB both permanently
            // unresponsive after a swipe-back, fixed only by reloading the
            // screen) — `isDragTracking` resets ONLY inside `edgeSwipe`'s
            // own `onEnded` (see `swipeStartScreen`'s doc comment above),
            // which can never fire if the leading-edge swipe-strip — mounted
            // only while `app.canSwipeBack` is true for the CURRENT screen
            // — is torn out of the hierarchy mid-recognition: e.g. a second
            // swipe attempt starts on that strip just before the FIRST
            // swipe's already-scheduled `goBack()` flips `app.screen` out
            // from under it. With no fallback, `isDragTracking` (and
            // therefore `app.isRootSwipeActive`, which every
            // `SwipeSafeButton` on the newly-arrived screen checks on every
            // press) was stuck `true` forever. A genuine screen change is
            // proof any legitimate gesture's job is already done, so it's
            // safe to force these back to their rest state here regardless
            // of how they got left.
            isDragTracking = false
            isCommittingBack = false
            dragTranslation = 0
            swipeStartScreen = nil
            // Same fallback for `tabSwipeGesture` (2026-09-29 follow-up,
            // "all screens have the same problem" — not just Home/edge-
            // swipe-back) — `tabSwipeDirection`'s only resets are inside
            // its OWN `onChanged`/`onEnded`, and it's attached
            // conditionally too (`BottomTabBar.visibleScreens.contains
            // (app.screen)`, further down in this body) for its own
            // documented, unrelated reason (a merely-attached, inactive
            // recognizer still wins gesture arbitration on non-dock
            // screens). The exact same orphaning shape applies: if
            // `app.screen` changes to a non-dock screen (e.g. a
            // notification's own tap handler navigating straight to
            // `.dashboard`) while a horizontal tab-swipe is mid-drag on a
            // dock screen, this gesture's hosting modifier is removed
            // before its `onEnded` fires, and `tabSwipeDirection` stuck at
            // "horizontal" keeps `isScreenLevelSwipeActive`/
            // `app.isRootSwipeActive` stuck true just the same — on
            // WHATEVER screen is current at the time, not just Home.
            tabSwipeDirection = nil
            tabSwipeTranslation = 0
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
        // TASK 1 (dock "+" native-menu pass) — story creation's photo/
        // camera picker + Retake/Use-photo preview, centralized here
        // (used to be attached to AccountView only, with its three
        // trigger flags as local @State there). Both AccountView's own
        // "Đăng story" menu and the dock "+" menu (DockCreateButtonView,
        // a different view entirely, in BottomTabBarOverlay's separate
        // window) now just flip these AppState flags — ONE presenter,
        // reachable from any screen, no second upload pipeline. See the
        // "PhotosPicker inside Menu swallowing taps" comment this reuses
        // (AccountView.swift) — the picker's presentation still can't live
        // directly inside a Menu row, so it's attached at this root level.
        .photosPicker(isPresented: $app.storyLibraryPickerOpen, selection: $app.storyPhotoItem, matching: .images)
        .onChange(of: app.storyPhotoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                await MainActor.run { app.storyCreatePreviewImage = image }
                app.storyPhotoItem = nil
            }
        }
        .fullScreenCover(isPresented: $app.storyCameraOpen) {
            CameraPicker { image in
                app.storyCameraOpen = false
                app.storyCreatePreviewImage = image
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(get: { app.storyCreatePreviewImage != nil }, set: { if !$0 { app.storyCreatePreviewImage = nil } })) {
            StoryCreatePreviewView()
        }
        // Same reasoning as AccountView's own removed `syncDockHidden()`:
        // BottomTabBarOverlay is a separate always-on-top UIWindow that
        // sits above a `.photosPicker`/`.fullScreenCover` presentation
        // unless explicitly told to hide.
        .onChange(of: app.storyLibraryPickerOpen) { _, _ in syncStoryDockHidden() }
        .onChange(of: app.storyCameraOpen) { _, _ in syncStoryDockHidden() }
        .onChange(of: app.storyCreatePreviewImage != nil) { _, _ in syncStoryDockHidden() }
    }

    private func syncStoryDockHidden() {
        BottomTabBarOverlay.shared.setForcedHidden(app.storyLibraryPickerOpen || app.storyCameraOpen || app.storyCreatePreviewImage != nil)
    }

    /// The SCREENS map, factored out so both the current screen and the
    /// peeked-at previous one (during a swipe) can render from the same
    /// switch instead of keeping two copies in sync. `isPreview` only ever
    /// matters to the `.mapExplore` case (see its own call site's comment)
    /// — every other screen ignores it, so this stays a one-line addition
    /// rather than a second switch to keep in sync. `isActive` similarly
    /// only matters to `.mapExplore` (see `MapExploreView`'s own doc
    /// comment on its `isActive` parameter) — sheet-reveal-timing fix,
    /// 2026-09-29.
    @ViewBuilder
    private func screenView(for screen: Screen, isPreview: Bool = false, isActive: Bool = true) -> some View {
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
        case .mapExplore: MapExploreView(restored: app.mapExploreState, isPreview: isPreview, startFocusedOnSearch: app.mapExploreFocusSearch, isActive: isActive)
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
        case .accountGroup: AccountGroupView()
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            app.palette.paper.opacity(0.9).ignoresSafeArea()
            // TASK 2 (loading GIF placement pass) — was `spacing: 14`; the
            // GIF's own rotating bounds sat close enough to the label below
            // that they could visually cover it. `BanbeTheme.LoadingVisual.
            // reservationGap` reserves real layout space for that gap (a
            // real VStack spacing value, not a non-reflowing offset), so
            // this label position is guaranteed clear.
            VStack(spacing: BanbeTheme.LoadingVisual.reservationGap) {
                // A4 (Pulse/loading UX pass, 2026-09-27) — the shared
                // Banbe loading GIF while a seat-reservation request is
                // pending, replacing the plain mark+spinner this used
                // before (BanbeLoadingVisual honors Reduce Motion itself).
                BanbeLoadingVisual(size: 64)
                Text(app.T("Đang giữ chỗ cho bạn…", "Holding your seat…"))
                    .font(.system(size: 13))
                    .foregroundStyle(app.palette.ink)
            }
        }
    }
}

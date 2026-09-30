import SwiftUI
import UIKit

/// BUG 3 follow-up (80c1ac3 real-device report): MapExploreView's filter/
/// list sheet is a genuine `.sheet(isPresented:)` / `UISheetPresentationController`
/// presentation (`MapExploreView.swift:442-513` — `.presentationDetents`,
/// `.presentationBackgroundInteraction(.enabled)`, `.interactiveDismissDisabled()`),
/// confirmed by reading that file, not assumed. The web equivalent
/// (`MapExplore.jsx`'s `sheetRef` div) is a plain in-DOM element with its
/// own z-index; iOS's is not a ZStack sibling at all — a presented sheet is
/// layered by UIKit ABOVE the entire presenting view controller's content,
/// in an entirely different presentation layer. That's why 80c1ac3's
/// `.zIndex(10)` (correctly placed at RootView's ZStack call site, fixing
/// the bar's ordering against the native `Map()` view) had no effect here:
/// `.zIndex()` only orders ZStack siblings, and the sheet isn't one.
///
/// Restructuring the sheet into a custom, hand-rolled in-hierarchy view
/// (matching the web architecture) was rejected as too invasive — and
/// worse, already tried once at smaller scale and reverted: see
/// MapExploreView.swift:483-506, where a prior pass's custom drag handle
/// for JUST the resize gesture broke on a real device (dragging the filter
/// row resized the sheet instead of scrolling it) and was reverted back to
/// the system's own drag indicator. `MapExploreView` also leans on native-
/// sheet-only behavior with no custom equivalent — `.presentationBackgroundInteraction(.enabled)`
/// (pan/zoom the map while the sheet is up) and three
/// `.presentationDetents` snap fractions with free drag-to-resize physics
/// (see that struct's own top comment: "no custom gesture code needed
/// here, unlike the web build of the same screen" — a deliberate choice).
///
/// So: the tab bar is hosted in a SECOND `UIWindow` at a higher
/// `windowLevel` than the app's main window — a genuinely separate
/// compositing layer, so it renders above anything happening inside the
/// main window, including a `.sheet()` at any detent, with no dependency
/// on SwiftUI ZStack ordering at all.
///
/// 5f449d9 follow-up (real-device regression: NO tab bar button was
/// tappable anymore) — root cause confirmed by reasoning about
/// `UIHostingController`'s hit-testing model, not guessed: 5f449d9 made
/// this a FULL-SCREEN transparent window with a `PassthroughWindow.hitTest`
/// override that compared the hit view's identity against
/// `rootViewController?.view`, on the assumption that a tap on real content
/// (a button, the capsule background) would resolve to some deeper, more
/// specific `UIView`. That assumption holds for plain UIKit content, where
/// each control genuinely is a distinct `UIView` in the hit-test tree — it
/// does NOT hold here. `BottomTabBar`'s content (Capsule, HStack of icons,
/// `.gesture(scrubGesture)`) is plain SwiftUI with no `UIViewRepresentable`/
/// `List`/`ScrollView`/text field anywhere in it — none of which SwiftUI
/// backs with distinct child `UIView`s for hit-testing. SwiftUI instead
/// renders and hit-tests this entire subtree internally and dispatches to
/// the right button/gesture itself, once UIKit hands the touch to the ONE
/// `UIView` the whole hosting controller is backed by. So `super.hitTest`
/// resolved to `rootViewController.view` for EVERY point in the window —
/// including taps squarely on a real tab bar icon — making the `===`
/// comparison true universally and `hitTest` return `nil` for literally
/// every touch. There was never a "deeper view" for a real tap to resolve
/// to, so the passthrough check could never distinguish "empty space" from
/// "the bar itself."
///
/// Fix (the ticket's own "preferred, most robust" option): stopped trying
/// to distinguish empty-vs-real-content via view identity at all, and
/// instead made passthrough a property of the WINDOW'S OWN BOUNDS. This
/// window is now sized to a small band that comfortably contains the bar
/// at its full resting size, not the whole screen — a touch outside that
/// band is never even offered to this window by UIKit's normal window-
/// hit-testing (which considers window frames), so it reaches the app's
/// main window underneath automatically, no custom `hitTest` override
/// needed at all. A touch inside the band always resolves to the hosting
/// view (per the same SwiftUI hosting behavior above) and is handled by
/// SwiftUI's own internal dispatch completely normally, exactly like any
/// other SwiftUI screen. `PassthroughWindow` and its `hitTest` override
/// are gone entirely — there is nothing left for them to do.
///
/// a5fd823 follow-up (real-device regression: Reserve/View Ticket on Event
/// Detail visible but not tappable) — root cause confirmed by reading, not
/// guessed: this window's `isHidden` was set to `false` exactly once, at
/// `attach()`, and never touched again. `BottomTabBarOverlayRoot`'s own
/// `if BottomTabBar.visibleScreens.contains(app.screen)` only controls
/// what SwiftUI DRAWS inside the window — it does nothing to the WINDOW
/// ITSELF, which stays a real, always-present, always-`isHidden == false`
/// UIWindow sitting at `.normal + 1` for the app's entire lifetime. A
/// plain `UIWindow` with no `hitTest` override claims every touch within
/// its rectangular frame regardless of what its content is currently
/// showing (an empty SwiftUI view still leaves a real, hit-testable
/// backing `UIView` filling the window) — so on Event Detail, which was
/// never in `visibleScreens` and therefore never drew the bar there, this
/// window was STILL silently swallowing every touch inside its band,
/// including ones meant for `EventDetailView`'s own `actionBar`
/// (Reserve/View Ticket), which sits in that exact same bottom-of-screen
/// region. Fixed by explicitly hiding the window itself (not just its
/// content) on every screen `visibleScreens` doesn't include — see
/// `updateVisibility(for:)`, called once at `attach()` and again on every
/// `RootView` screen change (`RootView.swift`'s `.onChange(of: app.screen)`).
/// `isHidden = true` removes a `UIWindow` from hit-testing entirely, not
/// just from rendering.
///
/// Also tightened the band itself (independent of the visibility fix
/// above, and worth keeping even with it): the previous 440×160 band was
/// deliberately padded well beyond the bar's actual visible footprint,
/// which meant that even on a screen where the bar DOES show (MapExplore
/// in particular), genuinely empty margin inside the band — above/below/
/// beside the pill, not actually covered by any real bar content — still
/// silently absorbed touches meant for whatever's underneath (the map
/// sheet's own list content, e.g. at its tallest detent, where the list
/// scrolls all the way down to the physical bottom edge). The band now
/// tracks `BottomTabBar`'s real constants directly instead of a rough,
/// independently-chosen guess.
/// BUG FIX (dock-jump-on-tray-open pass, real-device regression) — this
/// window used to GROW from a small dock band to the full screen while the
/// "+" tray was open, then shrink back after close (see
/// `BottomTabBarOverlay.setDockCreateTrayOpen`'s git history). That resize
/// is the actual root cause of the reported jump on both open AND close:
/// `BottomTabBarOverlayRoot`'s SwiftUI content is laid out fresh against
/// whatever size THIS window currently reports, and on a real device
/// `DockRow`'s computed screen position was not perfectly invariant across
/// that resize (open) or across the delayed shrink racing the tray's own
/// closing `withAnimation` transaction (close, the worse of the two
/// symptoms) — exactly the class of timing/geometry dependency this ticket
/// asks to eliminate structurally, not paper over with an offset.
///
/// Fixed per this ticket's own preferred option: the window's frame is now
/// set ONCE, at `attach()`, to the full screen, and NEVER changes again for
/// any reason — there is no more resize for `setDockCreateTrayOpen` to
/// sequence, so there is nothing left that can race or over/undershoot.
/// `DockRow`'s container is therefore byte-for-byte identical in every
/// state, tray open or closed, before/during/after any transition.
///
/// Pass-through hit-testing (this window must not start swallowing every
/// touch on every screen just because its frame now covers all of it — see
/// a5fd823's own doc comment above for why a tight hit-testable band
/// matters) is done geometrically instead of by resizing: `hitTest` only
/// forwards a touch into this window's content when the point falls inside
/// `passthroughRect` (the same small dock-band rectangle the window itself
/// used to BE), or anywhere at all while `trayOpen` is true (the tray's own
/// full-bleed scrim legitimately needs to catch a tap anywhere to dismiss).
/// This is a coordinate-based check, unrelated to the view-IDENTITY-based
/// `hitTest` override 5f449d9 already tried and reverted (see this file's
/// own top-of-file doc comment) — that one failed because SwiftUI backs an
/// entire subtree with a single `UIView`, making "is this the root view"
/// always true for every touch. Comparing a POINT against a RECT has no
/// such ambiguity and needs no knowledge of SwiftUI's internal view tree.
private final class DockOverlayWindow: UIWindow {
    var passthroughRect: CGRect = .zero
    var trayOpen = false
    // Notification banner fix pass (2026-09-30 third) — ADDITIVE alongside
    // `passthroughRect`/`trayOpen`, never replacing either's own meaning.
    // `ToastOverlay` now renders inside this same always-on-top window (see
    // `BottomTabBarOverlayRoot` below, the same fix already applied to the
    // dock create tray) so a banner is visible/tappable above MapExplore's
    // native `.sheet()` too — but this window still geometrically rejects
    // every touch outside its known content by default, so the toast's own
    // on-screen frame (reported up via `ToastFramePreferenceKey`) must be
    // forwarded here the same way the dock band's own rect already is.
    // `.zero` (no toast currently shown) contains no point, so this is a
    // pure no-op whenever there's nothing to tap.
    var toastRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard trayOpen || passthroughRect.contains(point) || toastRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
final class BottomTabBarOverlay {
    static let shared = BottomTabBarOverlay()
    private var window: DockOverlayWindow?
    private var currentScreen: Screen = .home
    // Inbox.jsx bug 2 fix (2026-09-21 follow-up): the Inbox settings sheet
    // (and its "Give feedback" flow) are hand-rolled SwiftUI content INSIDE
    // the main window's own view hierarchy — this window's own doc comment
    // above already establishes that ANY content in the main window,
    // including a real `.sheet()`/`.fullScreenCover()`, sits below this
    // separate always-on-top window regardless of screen. `.inbox` staying
    // in `visibleScreens` the whole time means `updateVisibility(for:)`
    // alone never hides it for a same-screen sheet. Rather than inventing a
    // second mechanism, this reuses the exact same `isHidden`-sync idea
    // a5fd823 established, with one more input ORed in.
    private var forcedHidden = false
    // Task 1 (2026-09-22 follow-up, 07-notifications.md) — a fullscreen
    // StoryViewer session must hide this overlay window too, on every
    // screen it can be reached from (Home, Profile, and any future
    // entry point) — a SEPARATE flag from `forcedHidden` (not folded into
    // the same bool) so RootView's own global `app.storyViewer` check and
    // InboxView's screen-local sheet check can never stomp on each other's
    // intent by racing a single shared setter.
    private var storyViewerOpen = false
    private var pulseViewerOpen = false
    // TASK 3 (2026-09-22 seventeenth follow-up) — a SEPARATE flag from
    // `forcedHidden`, same reasoning as `storyViewerOpen` just above: a
    // screen-local modal action sheet (starting with NotificationsView's
    // own "•••" menu) is routed through `AppState.modalActionSheetPresented`
    // → RootView's own `.onChange` → `setModalActionSheetPresented(_:)`
    // below, independent of whatever InboxView's own `setForcedHidden(_:)`
    // calls are doing for its unrelated settings/feedback sheet — sharing
    // one flag between two independent callers would let either one's
    // "false" silently clobber the other's still-active "true".
    private var modalActionSheetPresented = false
    // iPhone fix pass (2026-09-26) — the "Khu vực" region-filter sheet
    // (AreaSheetView) is hand-rolled SwiftUI content inside the main
    // window's own view hierarchy (BottomSheet, same file as
    // AreaSheetView) — like every other case above, this separate
    // always-on-top window paints straight through it without an explicit
    // flag. A dedicated flag, not a reuse of `forcedHidden`/
    // `modalActionSheetPresented` — same "independent callers, independent
    // flags" reasoning as `storyViewerOpen`/`pulseViewerOpen` above; this
    // is driven by `app.areaAsking` alone, never by InboxView's or
    // NotificationsView's own sheets.
    private var areaSheetOpen = false
    // FIX PASS (2026-09-30, Map-sheet layering) — the dock "+" tray
    // (`DockCreateTrayView`) now renders inside THIS window (moved out of
    // RootView's main-window ZStack, where it rendered under MapExplore's
    // native filter/list `.sheet()` — see RootView.swift's removed call
    // site for the full root-cause writeup). Unlike every flag above, this
    // one does NOT feed `applyVisibility()` — the tray only ever opens while
    // the dock itself is already visible (you have to tap the dock's own
    // "+" to open it), so the window is already shown. As of the
    // dock-jump-on-tray-open fix pass this flag no longer resizes anything
    // (see `DockOverlayWindow`'s own doc comment) — it only widens this
    // window's OWN pass-through hit-test region to the full screen for as
    // long as the tray's scrim needs to catch a tap anywhere to dismiss.
    private var dockCreateTrayOpen = false
    private var sceneBounds: CGRect = .zero
    // TASK 1 (2026-09-22 twenty-first follow-up) — this window's own
    // `isHidden` used to be set synchronously, in lockstep with these
    // flags, which is the actual root cause of the abrupt appear/disappear
    // this ticket reports: `applyVisibility()` flipped `isHidden` the same
    // frame the flags changed, with no transition at all — content either
    // was or wasn't there, nothing animated. `lastShown`/`visibilityToken`
    // let `applyVisibility()` instead animate `appState.dockVisible` first
    // (SwiftUI's own `.animation(_:value:)` on `BottomTabBarOverlayRoot`
    // handles the actual offset/opacity spring) and only touch the window's
    // `isHidden`/`isUserInteractionEnabled` before/after that animation, per
    // this ticket's own requirement 5. The token guards against a rapid
    // show/hide/show flicker leaving a stale delayed callback fighting a
    // newer one.
    private weak var appState: AppState?
    private var lastShown = true
    private var visibilityToken = 0
    private static let transitionDuration: TimeInterval = 0.32
    // `fileprivate`, not `private` — `BottomTabBarOverlayRoot` (this same
    // file, a different type) reads this too, so both the window-hide
    // timing above and the content's own `.animation(_:value:)` use the
    // exact same spring, not two independently-tuned speeds.
    fileprivate static let transitionAnimation = Animation.spring(response: 0.38, dampingFraction: 0.82)

    // Tracks BottomTabBar's own layout constants directly (barWidth/
    // barHeight/bottomOffset there) rather than an independently-chosen,
    // much more generous guess — see this type's own doc comment for why
    // that generosity was itself part of the a5fd823 regression. Still a
    // little larger than the bar's exact footprint (shadow radius 14, the
    // scrub gesture's highlight blur, the device's home-indicator safe
    // area), just not padded by 80-90pt of genuinely dead margin anymore.
    private static var bandWidth: CGFloat { BottomTabBar.barWidth + BottomTabBar.barHorizontalPadding * 2 + 24 }
    private static var bandHeight: CGFloat { BottomTabBar.barHeight + BottomTabBar.bottomOffset + 34 + 24 }

    /// Called from RootView's `.onAppear` once a `UIWindowScene` and the
    /// shared `AppState` are both available. Idempotent — RootView can
    /// call this on every appearance without creating duplicate windows.
    func attach(to scene: UIWindowScene, appState: AppState) {
        self.appState = appState
        guard window == nil else { return }
        let hosting = UIHostingController(rootView: BottomTabBarOverlayRoot().environmentObject(appState))
        hosting.view.backgroundColor = .clear

        // `scene.screen.bounds` is the full PHYSICAL DISPLAY size, not
        // necessarily this scene's own current viewport — identical on
        // iPhone (no windowed multitasking) but can be larger than the
        // scene's real bounds on iPad Split View/Slide Over. This window
        // is anchored to `scene` specifically (`UIWindow(windowScene:)`),
        // so it should size itself off the SAME geometry the scene's own
        // (SwiftUI-managed) main window actually occupies —
        // `scene.coordinateSpace.bounds` reflects that; `scene.screen.bounds`
        // does not. Behaviorally a no-op on iPhone, correct on iPad.
        let screenBounds = scene.coordinateSpace.bounds
        sceneBounds = screenBounds

        // Always full-screen (of the scene's own viewport), and never
        // resized again — see `DockOverlayWindow`'s own doc comment for
        // why. `passthroughRect` is what keeps this window from swallowing
        // touches outside the small dock band while the tray is closed.
        let win = DockOverlayWindow(windowScene: scene)
        win.frame = screenBounds
        win.passthroughRect = bandFrame(in: screenBounds)
        win.backgroundColor = .clear
        win.rootViewController = hosting
        // .normal + 1: above the app's own main window (and therefore
        // above any `.sheet()`/`UIPresentationController` content inside
        // it, at any detent) but well below system-owned levels like
        // `.alert` or the keyboard, which must still be able to cover it.
        win.windowLevel = .normal + 1
        window = win
        updateVisibility(for: appState.screen)
    }

    /// See this type's own doc comment for the full a5fd823 regression
    /// this fixes. `isHidden` (not `isUserInteractionEnabled`) specifically
    /// — a hidden `UIWindow` is removed from `UIApplication`'s hit-testing
    /// pass entirely, not merely told to ignore touches once reached.
    func updateVisibility(for screen: Screen) {
        currentScreen = screen
        applyVisibility()
    }

    /// Inbox.jsx bug 2 fix (2026-09-21 follow-up) — a screen-local view
    /// (InboxView) calls this directly around its own settings-sheet/
    /// feedback-flow presentation, since neither one is a `Screen` change
    /// `updateVisibility(for:)` would otherwise see.
    func setForcedHidden(_ hidden: Bool) {
        forcedHidden = hidden
        applyVisibility()
    }

    /// Task 1 (2026-09-22 follow-up) — called from RootView's
    /// `.onChange(of: app.storyViewer)`, independent of any screen change
    /// (Home/Profile stay the same `Screen` the whole time a story is
    /// open, so `updateVisibility(for:)` alone would never see this).
    func setStoryViewerOpen(_ open: Bool) {
        storyViewerOpen = open
        applyVisibility()
    }

    /// TASK E (2026-10-01 UX foundation pass) — PulseViewerView presents as
    /// a `.fullScreenCover`, which (like StoryViewerView above) sits inside
    /// the main window's own view hierarchy — this overlay's separate
    /// always-on-top UIWindow would still paint above it without this.
    func setPulseViewerOpen(_ open: Bool) {
        pulseViewerOpen = open
        applyVisibility()
    }

    /// TASK 3 (2026-09-22 seventeenth follow-up) — called from RootView's
    /// `.onChange(of: app.modalActionSheetPresented)`. See that flag's own
    /// doc comment (AppState.swift) and `modalActionSheetPresented`'s own
    /// comment just above for why this is a dedicated flag, not a reuse of
    /// `setForcedHidden`.
    func setModalActionSheetPresented(_ presented: Bool) {
        modalActionSheetPresented = presented
        applyVisibility()
    }

    /// iPhone fix pass (2026-09-26) — called from RootView's
    /// `.onChange(of: app.areaAsking)`, independent of any screen change
    /// (Home stays `.home` the whole time the sheet is open).
    func setAreaSheetOpen(_ open: Bool) {
        areaSheetOpen = open
        applyVisibility()
    }

    private func bandFrame(in bounds: CGRect) -> CGRect {
        let width = min(Self.bandWidth, bounds.width)
        return CGRect(
            x: (bounds.width - width) / 2,
            y: bounds.height - Self.bandHeight,
            width: width,
            height: Self.bandHeight
        )
    }

    /// FIX PASS (2026-09-30, Map-sheet layering) — called from RootView's
    /// `.onChange(of: app.dockCreateMenuOpen)`. The tray is hosted in THIS
    /// window — the one thing in this app already proven to paint above a
    /// `.sheet()` at any detent — which is what puts it above MapExplore's
    /// native filter/list sheet.
    ///
    /// dock-jump-on-tray-open fix pass: this used to also grow/shrink the
    /// window's own frame between a small band and the full screen (see git
    /// history), which was the actual root cause of the dock visibly moving
    /// on both open and close. The window is now permanently full-screen
    /// (`attach()`) and this method only widens/narrows its pass-through
    /// hit-test region (`DockOverlayWindow.trayOpen`) — an instantaneous,
    /// non-animated flag flip, never a frame/layout change, so there is
    /// nothing left for any transaction/animation to race. No delay is
    /// needed on close either: since the window's SIZE never changes, there
    /// is no more "premature shrink clipping the exit animation" failure
    /// mode the old delay existed to prevent, and therefore no stale
    /// delayed-callback/token bookkeeping needed for rapid open/close taps.
    ///
    /// Deliberately touches nothing about MapExploreView itself — no
    /// camera/filter/search/selection/detent state, no sheet dismissal.
    func setDockCreateTrayOpen(_ open: Bool) {
        guard dockCreateTrayOpen != open else { return }
        dockCreateTrayOpen = open
        window?.trayOpen = open
    }

    /// Notification banner fix pass (2026-09-30 third) — additive sibling to
    /// `setDockCreateTrayOpen` above, same idea applied to the toast banner
    /// instead of the tray: `ToastOverlay` (mounted in
    /// `BottomTabBarOverlayRoot` below) reports its own on-screen frame via
    /// `ToastFramePreferenceKey`; that frame is forwarded here so
    /// `DockOverlayWindow.hitTest` can let a tap on the banner itself
    /// through. `.zero` when no toast is shown restores the window to
    /// exactly its pre-existing pass-through behavior — nothing else about
    /// `applyVisibility()`/`forcedHidden`/`storyViewerOpen`/etc. is touched.
    fileprivate func setToastRect(_ rect: CGRect) {
        window?.toastRect = rect
    }

    private func applyVisibility() {
        let shouldShow = !(forcedHidden || storyViewerOpen || pulseViewerOpen || modalActionSheetPresented || areaSheetOpen)
            && BottomTabBar.visibleScreens.contains(currentScreen)
        guard shouldShow != lastShown else { return }
        lastShown = shouldShow
        visibilityToken += 1
        let token = visibilityToken

        if shouldShow {
            // Requirement 5 — unhide the window FIRST (content is already
            // sitting in its off-screen/faded state from the last hide, or
            // the fresh `dockVisible = true` default on first launch), then
            // animate into place.
            window?.isHidden = false
            window?.isUserInteractionEnabled = false
            withAnimation(Self.transitionAnimation) { appState?.dockVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionDuration) { [weak self] in
                guard let self, self.visibilityToken == token else { return }
                self.window?.isUserInteractionEnabled = true
            }
        } else {
            // Requirement 5 — animate the content out first; only flip
            // `isHidden` once that animation has actually finished, not
            // before. `isUserInteractionEnabled = false` immediately so the
            // exiting/already-hidden dock never swallows a touch meant for
            // whatever's underneath while it's still fading out.
            window?.isUserInteractionEnabled = false
            withAnimation(Self.transitionAnimation) { appState?.dockVisible = false }
            // TASK 1 real-device follow-up — every case this ticket lists
            // ("hide/reconcile dock on other sheets, Pulse, story viewer,
            // QR and auth screens") already funnels through THIS branch —
            // it's exactly when `shouldShow` above goes false. Closing the
            // tray here, once, covers all of them instead of duplicating
            // the same check at each individual call site. An orphaned
            // open tray with its dock/button now hidden underneath (e.g.
            // Pulse opening while the tray was up) would otherwise leave
            // an invisible scrim still intercepting taps.
            appState?.dockCreateMenuOpen = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionDuration) { [weak self] in
                guard let self, self.visibilityToken == token else { return }
                self.window?.isHidden = true
            }
        }
    }
}

/// Mirrors RootView's own `BottomTabBar.visibleScreens.contains(app.screen)`
/// gate exactly, so the bar shows/hides on the same screens it always has —
/// this view has its own copy of `AppState` injected (a separate UIWindow
/// means a separate SwiftUI environment; it doesn't automatically inherit
/// WindowGroup's).
///
/// BUG FIX (dock-centered-instead-of-bottom regression) — the previous
/// version of this doc comment claimed "this ZStack's own bounds are
/// simply the physical screen's bounds" once `DockOverlayWindow` became
/// permanently full-screen. That was wrong, and is the actual root cause
/// of the dock rendering vertically centered (screenshot: sitting mid-Home,
/// covering content) instead of at the bottom with the tray closed. A
/// `UIHostingController`'s root view being told its HOSTING VIEW now spans
/// the full screen does not itself make the ROOT SwiftUI VIEW report a
/// full-screen size — without a `.frame(maxWidth: .infinity, maxHeight:
/// .infinity)` somewhere in this tree, this `ZStack` reports only its
/// INTRINSIC size (DockRow's own fixed height, per that view's own doc
/// comment, `BottomTabBar.swift`), and SwiftUI centers a root view that
/// doesn't fill its container within the full available bounds — so the
/// whole (small) dock box floated at screen-center, not the bottom.
/// `alignment: .bottom` on this `ZStack` only ever governed placement
/// INSIDE that too-small box; it never made the box itself span the full
/// window. Fixed below: the trailing `.frame(maxWidth: .infinity,
/// maxHeight: .infinity, alignment: .bottom)` makes this view actually
/// claim the full, constant (never-resized, per `DockOverlayWindow`)
/// window bounds, with `alignment: .bottom` on THAT outer frame placing
/// the (still intrinsically-sized) dock content flush against the real
/// physical bottom edge — invariant across "+"/"x", since the window's
/// size never changes and now neither does this view's own reported size.
private struct BottomTabBarOverlayRoot: View {
    @EnvironmentObject var app: AppState

    // TASK 1 (2026-09-22 twenty-first follow-up) — always mounted now (was
    // a plain `if visibleScreens.contains(app.screen) { ... }`, which
    // inserted/removed the bar with no transition at all — the actual root
    // cause of the abrupt reappearance this ticket reports). The window
    // itself is hidden/shown by `BottomTabBarOverlay.applyVisibility()`
    // AFTER this offset/opacity animation completes (requirement 5), so
    // keeping this content always present is what gives that animation
    // something to animate between.
    var body: some View {
        // TASK 1 (2026-10-05 fix pass) — the dock and the create-"+" button
        // used to be two independent ZStack children, each positioning
        // itself (BottomTabBar centered via its own frame math,
        // DockCreateButtonView pinned bottom-trailing with its own padding)
        // — the real cause of the two overlapping on a real device. DockRow
        // (BottomTabBar.swift) now lays both out together as one HStack
        // with a shared outer margin/gap, still inside this exact same
        // window/visibility lifecycle (see DockCreateButtonView's own doc
        // comment for why that lives here instead of a second floating
        // UIWindow) — only the internal composition changed.
        // BUG FIX (dock-jump-on-tray-open pass) — `alignment: .bottom` here
        // (was the ZStack default, `.center`) combined with DockRow no
        // longer requesting `maxHeight: .infinity` (see its own doc
        // comment, BottomTabBar.swift) was this ticket's FIRST attempt at a
        // fix — keeping DockRow's own intrinsic height flush against this
        // ZStack's bottom edge. That alone still weren't sufficient on a
        // real device (the window itself still resized between a band and
        // the full screen at the time). Superseded, not replaced, by
        // `DockOverlayWindow` now being permanently full-screen (see that
        // type's own doc comment) — this `alignment: .bottom` is still
        // correct and still needed, just against a container that no
        // longer ever changes size in the first place.
        ZStack(alignment: .bottom) {
            DockRow()
                .offset(y: app.dockVisible ? 0 : 40)
                .opacity(app.dockVisible ? 1 : 0)
                .allowsHitTesting(app.dockVisible)
                .animation(BottomTabBarOverlay.transitionAnimation, value: app.dockVisible)

            // FIX PASS (2026-09-30, Map-sheet layering) — moved here from
            // RootView's main-window ZStack (was zIndex 28 there, which
            // could never out-layer MapExplore's native `.sheet()`). This
            // window is always full-screen (`DockOverlayWindow`), so the
            // tray's own full-bleed scrim/drag-to-dismiss and the dock/
            // button beside it just work, with no resize involved anymore.
            if app.dockCreateMenuOpen { DockCreateTrayView() }

            // Notification banner fix pass (2026-09-30 third) — moved here
            // from RootView's main-window ZStack (same root cause as the
            // tray above: rendered beneath MapExplore's native `.sheet()`
            // there). `.frame(..., alignment: .top)` makes this child claim
            // the whole window and self-align to the top, exactly like
            // DockRow above claims it and self-aligns to the bottom — same
            // technique, opposite edge. Its own `ToastFramePreferenceKey`
            // report is read below and forwarded to the window's
            // `toastRect` so a tap on the banner itself isn't swallowed by
            // this window's default pass-through gating.
            if !app.toasts.isEmpty {
                ToastOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // BUG FIX (dock-centered-instead-of-bottom regression) — see this
        // type's own doc comment above for the full root cause. This is the
        // missing "claim the full window" step: without it, the ZStack
        // above reports only its intrinsic (DockRow-height) size and gets
        // centered in the full-screen `DockOverlayWindow` instead of
        // sitting at its bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onPreferenceChange(ToastFramePreferenceKey.self) { rect in
            BottomTabBarOverlay.shared.setToastRect(rect)
        }
    }
}

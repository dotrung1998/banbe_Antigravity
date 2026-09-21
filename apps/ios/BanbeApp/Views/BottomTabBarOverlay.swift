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
@MainActor
final class BottomTabBarOverlay {
    static let shared = BottomTabBarOverlay()
    private var window: UIWindow?
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
        guard window == nil else { return }
        let hosting = UIHostingController(rootView: BottomTabBarOverlayRoot().environmentObject(appState))
        hosting.view.backgroundColor = .clear

        let screenBounds = scene.screen.bounds
        let width = min(Self.bandWidth, screenBounds.width)
        let frame = CGRect(
            x: (screenBounds.width - width) / 2,
            y: screenBounds.height - Self.bandHeight,
            width: width,
            height: Self.bandHeight
        )

        let win = UIWindow(windowScene: scene)
        win.frame = frame
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

    private func applyVisibility() {
        window?.isHidden = forcedHidden || storyViewerOpen || !BottomTabBar.visibleScreens.contains(currentScreen)
    }
}

/// Mirrors RootView's own `BottomTabBar.visibleScreens.contains(app.screen)`
/// gate exactly, so the bar shows/hides on the same screens it always has —
/// this view has its own copy of `AppState` injected (a separate UIWindow
/// means a separate SwiftUI environment; it doesn't automatically inherit
/// WindowGroup's). Aligned to the bottom of THIS window's own (much
/// smaller) bounds, which is anchored to the same physical bottom edge of
/// the screen as the main window, so it lands in the same place.
private struct BottomTabBarOverlayRoot: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if BottomTabBar.visibleScreens.contains(app.screen) {
            BottomTabBar()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

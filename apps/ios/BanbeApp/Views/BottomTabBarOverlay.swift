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
@MainActor
final class BottomTabBarOverlay {
    static let shared = BottomTabBarOverlay()
    private var window: UIWindow?

    // Comfortably contains BottomTabBar at its full resting size —
    // `.frame(maxWidth: 320)` + 28pt horizontal padding each side (376),
    // plus headroom for its shadow (radius 14) and the scrub gesture's
    // highlight blur; `barHeight` (72) + its own bottom padding (2), plus
    // the same shadow/blur headroom and the device's home-indicator safe
    // area. Deliberately generous rather than pixel-exact — this band is
    // the ONLY part of the screen a touch can be silently absorbed by
    // empty space within it (see doc comment above), so it trades a little
    // extra unreachable margin at the very bottom of the screen for not
    // needing to keep it in lockstep, pixel-for-pixel, with BottomTabBar's
    // own layout constants.
    private static let bandWidth: CGFloat = 400
    private static let bandHeight: CGFloat = 160

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
        win.isHidden = false
        window = win
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

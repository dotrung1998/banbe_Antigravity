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
/// Instead: the tab bar is hosted in a SECOND, transparent `UIWindow` at a
/// higher `windowLevel` than the app's main window — a genuinely separate
/// compositing layer, so it renders above anything happening inside the
/// main window, including a `.sheet()` at any detent, with no dependency
/// on SwiftUI ZStack ordering at all. This is the standard technique for
/// an always-on-top SwiftUI overlay (the same approach toast/paywall/debug
/// overlay libraries use).
///
/// `RootView` no longer renders `BottomTabBar()` itself — this overlay is
/// now the single place the bar renders, for every screen it was already
/// showing on, not just MapExplore, so there's only ever one live instance.
@MainActor
final class BottomTabBarOverlay {
    static let shared = BottomTabBarOverlay()
    private var window: PassthroughWindow?

    /// Called from RootView's `.onAppear` once a `UIWindowScene` and the
    /// shared `AppState` are both available. Idempotent — RootView can
    /// call this on every appearance without creating duplicate windows.
    func attach(to scene: UIWindowScene, appState: AppState) {
        guard window == nil else { return }
        let hosting = UIHostingController(rootView: BottomTabBarOverlayRoot().environmentObject(appState))
        hosting.view.backgroundColor = .clear
        let win = PassthroughWindow(windowScene: scene)
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
/// WindowGroup's).
private struct BottomTabBarOverlayRoot: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if BottomTabBar.visibleScreens.contains(app.screen) {
            BottomTabBar()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Lets a touch pass through to the real app window underneath for every
/// point EXCEPT the bar's own actual rendered content. Without this
/// override, this window would silently swallow every touch on screen —
/// its root view claims every point within its bounds by default, which
/// would make the entire app underneath untappable. `hitView ===
/// rootViewController?.view` is true exactly when the touch landed on
/// empty/transparent space (no SwiftUI content at that point wanted it);
/// anything more specific (the bar's material background, an icon, the
/// scrub gesture's hit area) resolves to a deeper view and is let through
/// to be handled normally.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event) else { return nil }
        return hitView === rootViewController?.view ? nil : hitView
    }
}

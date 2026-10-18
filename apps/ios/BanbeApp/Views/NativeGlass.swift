import SwiftUI

// ONE place that decides how a "glass" surface is drawn in the app (note 45).
//
// Every glass button, chip, capsule and floating panel goes through
// `nativeGlass(...)`:
//  - iOS 26+: Apple's own `glassEffect` (Liquid Glass). It follows the system
//    Liquid Glass setting (Clear / Tinted in Settings > Display & Brightness)
//    and Reduce Transparency by itself.
//  - Earlier iOS: the matching system `Material`, which follows Reduce
//    Transparency by itself.
// There is deliberately NO in-app transparency/blur setting any more and no
// hand-tuned fill/opacity on top of the system effect: what the person chose
// in iOS Settings is what they get everywhere.

extension View {
    /// A native glass surface behind `self`, clipped to `shape`.
    /// - Parameters:
    ///   - interactive: press/touch response (buttons and chips).
    ///   - tint: optional semantic tint (a selected chip, an admin accent).
    ///   - fallback: the system material used before iOS 26.
    func nativeGlass<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil,
                               fallback: Material = .thinMaterial) -> some View {
        modifier(NativeGlassModifier(shape: shape, interactive: interactive, tint: tint, fallback: fallback))
    }

    /// Capsule shorthand — the common case (header buttons, filter chips).
    func nativeGlassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        nativeGlass(Capsule(), interactive: interactive, tint: tint)
    }

    /// Floating card/panel (area picker, scanner controls, Pulse panel).
    func nativeGlassPanel(cornerRadius: CGFloat = 26) -> some View {
        nativeGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), fallback: .regularMaterial)
    }
}

private struct NativeGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let fallback: Material

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background {
                ZStack {
                    shape.fill(fallback)
                    if let tint { shape.fill(tint.opacity(0.9)) }
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

// MARK: - Root-gesture exclusion + dock hiding (shared by Schedule and Account)

/// Registers a region as a "horizontal swipe belongs to this control" zone for
/// RootView's root-tab swipe — the same mechanism as Home's filter strips
/// (`rootGestureExclusionZones`), but written straight into AppState so a screen
/// other than Home can use it. Replaces any stale zones left by another screen on
/// appear and removes its own on disappear.
private struct RootSwipeExclusionModifier: ViewModifier {
    @EnvironmentObject private var app: AppState
    let id: String
    let enabled: Bool
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame = geo.frame(in: .named("rootGesture")); apply() }
                        .onChange(of: geo.frame(in: .named("rootGesture"))) { _, f in frame = f; apply() }
                }
            }
            .onChange(of: enabled) { _, _ in apply() }
            .onDisappear {
                var zones = app.rootGestureExclusionZones
                zones[id] = nil
                app.rootGestureExclusionZones = zones
            }
    }

    private func apply() {
        guard frame != .zero else { return }
        var zones = app.rootGestureExclusionZones
        if enabled { zones[id] = frame } else { zones[id] = nil }
        if zones != app.rootGestureExclusionZones { app.rootGestureExclusionZones = zones }
    }
}

/// Claims every touch that lands on this view for the view itself: the root
/// dock-tab swipe sees the claim from touch-down, before it classifies the
/// drag. `@GestureState` resets on its own when the touch ends or is
/// cancelled, so the claim can never get stuck.
private struct ClaimsRootSwipeModifier: ViewModifier {
    @EnvironmentObject private var app: AppState
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .updating($touching) { _, state, _ in state = true }
            )
            .onChange(of: touching) { _, t in app.rootSwipeClaimedByControl = t }
            .onDisappear { app.rootSwipeClaimedByControl = false }
    }
}

extension View {
    /// Use on controls with their own horizontal drag that are NOT inside a
    /// ScrollView (a zero-distance drag on scroll content can block scrolling).
    func claimsRootSwipe() -> some View { modifier(ClaimsRootSwipeModifier()) }

    /// A horizontal swipe that starts on this view does not switch dock tabs.
    func rootSwipeExclusion(_ id: String, enabled: Bool = true) -> some View {
        modifier(RootSwipeExclusionModifier(id: id, enabled: enabled))
    }
}

/// Hides the always-on-top dock while this view is on screen (put it inside a
/// sheet's content: sheets render in the main window, under the dock's own).
private struct HidesDockModifier: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .onAppear { BottomTabBarOverlay.shared.setSheetOpen(id, true) }
            .onDisappear { BottomTabBarOverlay.shared.setSheetOpen(id, false) }
    }
}

extension View {
    func hidesDock(_ id: String) -> some View { modifier(HidesDockModifier(id: id)) }
}

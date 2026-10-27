import SwiftUI

/// First Home after a sign-in (note 64): regions rise in top to bottom, header 0 → summary 1 → feed 2 → dock 3.
/// Web twin: `[data-reveal]` + useSignInReveal. Everything stays rendered and accessible; only opacity/offset move.
/// One shot: `app.justSignedIn` is set by completeSignInHandoff and cleared by `finishSignInReveal()`, so ordinary
/// navigation and restored sessions never replay it. Reduce Motion: all regions fade together.
struct RevealRegion: ViewModifier {
    let order: Int
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hidden = false

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && !reduceMotion ? 12 : 0)
            .task(id: app.justSignedIn) {
                guard app.justSignedIn, !UITestFixture.isActive else { hidden = false; return }
                hidden = true
                let delay = reduceMotion ? 0 : Double(order) * 0.08
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.42).delay(delay)) {
                    hidden = false
                }
            }
    }
}

extension View {
    func revealRegion(_ order: Int) -> some View { modifier(RevealRegion(order: order)) }
}

extension AppState {
    /// Ends the one-shot reveal after its last region has landed; the v3 tour may start from here.
    func finishSignInReveal(reduceMotion: Bool) async {
        guard justSignedIn else { return }
        try? await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.22 : 0.72) * 1_000_000_000))
        guard justSignedIn else { return }
        justSignedIn = false
        signInRevealDidFinish()
    }
}

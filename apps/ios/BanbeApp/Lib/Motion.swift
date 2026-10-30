import SwiftUI

/// One Reduce Motion switch for every animation (note 66). Views read
/// `@Environment(\.accessibilityReduceMotion)` and pass it in; with Reduce Motion on the change happens
/// instantly (or as a plain fade where the caller asks for `fade`) instead of moving or tweening.
enum Motion {
    /// `animation` normally, nil (instant) under Reduce Motion. For `.animation(_:value:)`.
    static func animation(_ animation: Animation, reduce: Bool) -> Animation? {
        reduce ? nil : animation
    }

    /// `animation` normally, a short opacity-friendly ease under Reduce Motion. For `withAnimation`.
    static func fade(_ animation: Animation, reduce: Bool) -> Animation {
        reduce ? .easeInOut(duration: 0.15) : animation
    }

    /// A transition that only fades under Reduce Motion.
    static func transition(_ transition: AnyTransition, reduce: Bool) -> AnyTransition {
        reduce ? .opacity : transition
    }
}

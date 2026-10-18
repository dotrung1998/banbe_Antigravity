import SwiftUI

// Signed-out public entry (WelcomeView) + auth route intent + the one motion
// helper public entry and Login share. Pure and unit-tested
// (BanbeAppTests/PublicEntryTests.swift). Note 44.
//
// Routing contract:
// - Signed in            → never sees public entry (existing restore rules).
// - Signed out, launch   → `.welcome` (after first-device language/theme).
// - Signed out, sign-out → `.welcome` (not straight into Login).
// - Welcome "Log in"     → Login in log-in mode, no intermediate pages.
// - Welcome "Get started"→ Login in sign-up mode.
// - A protected screen while signed out → Login directly (existing guard),
//   with Back to `.welcome` so there is always a way out.

/// Which tab Login opens on, set by whoever routes there.
enum AuthEntryIntent: Equatable {
    case login, signup

    var mode: AuthMode { self == .login ? .login : .signup }
}

/// The optional "See how banbe works" story — never required, never replayed
/// automatically. Page 0 is the single welcome screen.
struct PublicStoryState: Equatable {
    static let pageCount = 2
    /// nil = the welcome screen; 0..<pageCount = an optional story page.
    var page: Int?
    /// Last move direction, for the transition.
    var forward = true

    var isOnStory: Bool { page != nil }
    var isLastPage: Bool { page == Self.pageCount - 1 }

    mutating func open() { page = 0; forward = true }
    mutating func next() {
        guard let p = page else { return }
        forward = true
        page = min(p + 1, Self.pageCount - 1)
    }
    /// Back from the first story page returns to the welcome screen.
    mutating func back() {
        guard let p = page else { return }
        forward = false
        page = p == 0 ? nil : p - 1
    }
    mutating func close() { forward = false; page = nil }
}

/// Device-local "has seen the optional story" marker (not per account: it is
/// about this device's signed-out experience, never about personalization).
enum PublicStoryMarker {
    static let key = "banbe.publicStory.seen.v1"
    static func hasSeen(_ d: UserDefaults = .standard) -> Bool { d.bool(forKey: key) }
    static func markSeen(_ d: UserDefaults = .standard) { d.set(true, forKey: key) }
}

/// Where the app goes after splash / language / theme, for the auth part only.
enum PublicEntryRouting {
    /// `restored` is the (signed-in-only) restorable screen, if any.
    static func destination(isSignedIn: Bool, restored: Screen?) -> Screen {
        isSignedIn ? (restored ?? .home) : .welcome
    }

    struct Redirect: Equatable {
        let returnTo: Screen
        let backTo: Screen
    }

    /// The protected-screen guard: a signed-out move to a protected screen
    /// goes to Login, returning to that screen after sign-in. Back returns to
    /// the guest-browsable screen the person came from (note 48), else the
    /// public welcome screen. nil = allowed as is.
    static func protectedRedirect(isSignedIn: Bool, target: Screen, guestAllowed: Set<Screen>,
                                  from origin: Screen? = nil, browsable: Set<Screen> = []) -> Redirect? {
        guard !isSignedIn, !guestAllowed.contains(target) else { return nil }
        let back = origin.flatMap { browsable.contains($0) ? $0 : nil } ?? .welcome
        return Redirect(returnTo: target, backTo: back)
    }
}

// MARK: - Motion

/// One direction-aware motion for public entry and auth. Restrained: a short
/// horizontal nudge plus fade, no bounce, never blocks input. Reduce Motion
/// swaps it for a quick cross-fade.
enum AuthMotion {
    enum Style: Equatable {
        case slide(insertionFrom: Edge, distance: CGFloat)
        case fade
    }

    static let duration: Double = 0.2
    static let reducedDuration: Double = 0.12
    static let distance: CGFloat = 28

    static func style(forward: Bool, reduceMotion: Bool) -> Style {
        reduceMotion ? .fade : .slide(insertionFrom: forward ? .trailing : .leading, distance: distance)
    }

    static func transition(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        switch style(forward: forward, reduceMotion: reduceMotion) {
        case .fade:
            return .opacity
        case .slide(let edge, let d):
            let inX = edge == .trailing ? d : -d
            return .asymmetric(insertion: .offset(x: inX).combined(with: .opacity),
                               removal: .offset(x: -inX).combined(with: .opacity))
        }
    }

    static func animation(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? reducedDuration : duration)
    }
}

import Foundation

/// Simple Shell Home view (note 66 follow-up, plan item 1). Which half of Home is showing ("Going out" or
/// "Hosting") is a session-only choice (`AppState.homeView`), separate from organizer mode: tapping Going out only
/// changes the view, organizer mode stays on (owner decision 2026-10-31). Hosting can only show while organizer mode
/// is on, whatever the stored view says. Web twin: src/lib/homeMode.js; shared cases: tests/fixtures/home-mode.json.
enum HomeViewMode: String, Equatable {
    case goer
    case host
}

enum HomeMode {
    /// The view Home renders: host only when organizer mode is on AND the session chose Hosting.
    static func effectiveHomeView(organizerMode: Bool, homeView: HomeViewMode) -> HomeViewMode {
        organizerMode && homeView == .host ? .host : .goer
    }

    /// String form for the shared fixture (`"goer"` / `"host"`; anything else counts as goer).
    static func effectiveHomeView(organizerMode: Bool, homeView: String?) -> String {
        effectiveHomeView(organizerMode: organizerMode, homeView: HomeViewMode(rawValue: homeView ?? "") ?? .goer).rawValue
    }

    /// `homeView` after a profile sync or an organizer-mode change: coming on (off before) opens Hosting, staying on
    /// keeps what the person picked, off is always Going out. `stored` (session restore only): the last view the person
    /// picked on this device, so a relaunch reopens Going out if that is where they left Home.
    static func viewAfterSync(prevOrganizerMode: Bool, prevHomeView: HomeViewMode, organizerMode: Bool,
                              stored: HomeViewMode? = nil) -> HomeViewMode {
        if !organizerMode { return .goer }
        if !prevOrganizerMode { return stored ?? .host }
        return prevHomeView
    }

    /// The last Home view the person picked on this device (web twin: localStorage `banbe.homeView`). Written only on
    /// an explicit pick, cleared on sign-out.
    private static let storeKey = "banbe.homeView"
    static var stored: HomeViewMode? {
        get { UserDefaults.standard.string(forKey: storeKey).flatMap(HomeViewMode.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: storeKey) }
    }

    /// The Hosting segment is locked (lock glyph, opens the Start hosting invitation) while organizer mode is off.
    static func hostSegmentLocked(organizerMode: Bool) -> Bool { !organizerMode }

    enum StartHostingStep: String { case signIn, invite, land }

    /// What "Start hosting" does first: sign in (guest), the invitation (organizer mode off) or land (already on).
    static func startHostingStep(signedIn: Bool, organizerMode: Bool) -> StartHostingStep {
        guard signedIn else { return .signIn }
        return organizerMode ? .land : .invite
    }

    /// The locked segment's VoiceOver label and hint (read together as the shared fixture's `lockedLabel`).
    static func lockedLabel(_ T: (String, String) -> String) -> String { T("Tổ chức, đã khoá", "Hosting, locked") }
    static func lockedHint(_ T: (String, String) -> String) -> String {
        T("Chạm hai lần để bắt đầu tổ chức", "Double-tap to start hosting")
    }
}

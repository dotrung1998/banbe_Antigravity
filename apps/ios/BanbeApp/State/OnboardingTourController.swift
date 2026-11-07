import SwiftUI

/// Onboarding Version 3 tour state (note 64). Web twin: src/components/tour/OnboardingTour.jsx.
///
/// Its own ObservableObject (not AppState) so target frames updating every layout pass only re-render the overlay.
/// AppState mirrors one bool, `tourActive`, which RootView/the dock window use to shield the real app.
@MainActor
final class OnboardingTourController: ObservableObject {
    static let shared = OnboardingTourController()

    @Published private(set) var steps: [TourStep] = []
    @Published private(set) var index = 0
    @Published private(set) var missing: Set<Int> = []
    @Published private(set) var replay = false
    @Published private(set) var frames: [String: CGRect] = [:]
    /// Bumped when the current step wants its target scrolled into view (Home's first event card).
    @Published private(set) var scrollRequest = 0
    private var direction = 1
    private var latest: [String: CGRect] = [:]

    var active: Bool { !steps.isEmpty }
    var current: TourStep? { steps.indices.contains(index) ? steps[index] : nil }

    func report(_ id: String, _ rect: CGRect?) {
        latest[id] = rect
        guard active, frames[id] != rect else { return }
        frames[id] = rect
    }

    func begin(steps: [TourStep], replay: Bool) {
        self.replay = replay
        missing = []
        index = 0
        direction = 1
        frames = latest
        self.steps = steps
        requestScrollIfNeeded()
    }

    func reset() {
        steps = []
        missing = []
        frames = [:]
    }

    func goTo(_ i: Int) {
        guard steps.indices.contains(i), !missing.contains(i) else { return }
        direction = i >= index ? 1 : -1
        index = i
        requestScrollIfNeeded()
    }

    /// Returns false when there is no next step (the caller finishes).
    func next() -> Bool {
        var i = index + 1
        while i < steps.count && missing.contains(i) { i += 1 }
        guard i < steps.count else { return false }
        direction = 1
        index = i
        requestScrollIfNeeded()
        return true
    }

    func back() {
        var i = index - 1
        while i >= 0 && missing.contains(i) { i -= 1 }
        guard i >= 0 else { return }
        direction = -1
        index = i
        requestScrollIfNeeded()
    }

    var isFirst: Bool { var i = index - 1; while i >= 0 && missing.contains(i) { i -= 1 }; return i < 0 }
    var isLast: Bool { var i = index + 1; while i < steps.count && missing.contains(i) { i += 1 }; return i >= steps.count }

    /// The current target never showed up: skip it in the direction of travel. Returns false when nothing is left.
    func skipMissing() -> Bool {
        missing.insert(index)
        var i = index + direction
        while i >= 0 && i < steps.count && missing.contains(i) { i += direction }
        if i < 0 { i = index + 1; while i < steps.count && missing.contains(i) { i += 1 } }
        guard i >= 0 && i < steps.count else { return false }
        index = i
        requestScrollIfNeeded()
        return true
    }

    private func requestScrollIfNeeded() {
        if current?.target == "tour.home.eventCard" { scrollRequest += 1 }
    }
}

extension AppState {
    /// First-run entry: the sign-in reveal ended, or personalization landed on Home. Re-checks everything itself.
    func maybeStartOnboardingTour() {
        guard onboardingVersion == 3, let uid = userID, !tourActive,
              !UserDefaults.standard.bool(forKey: OnboardingTourContent.doneKey(uid)),
              screen == .home, !needsSettingsOnboarding, !needsPreferencesOnboarding, !onboardingFlowActive
        else { return }
        startOnboardingTour(replay: false)
    }

    /// Help & Legal replay: a fresh tour that never reads or writes the first-run marker.
    func replayOnboardingTour() {
        screen = .home
        startOnboardingTour(replay: true)
    }

    func signInRevealDidFinish() { maybeStartOnboardingTour() }

    private func startOnboardingTour(replay: Bool) {
        let steps = OnboardingTourContent.eligible(organizerMode: organizerMode, simpleShell: simpleShellEnabled)
        guard !steps.isEmpty else { return }
        Analytics.paused = true
        tourActive = true
        OnboardingTourController.shared.begin(steps: steps, replay: replay)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// Finish or Skip: Home, scrolled to the top; the marker only for a first run.
    func endOnboardingTour(completed: Bool) {
        let tour = OnboardingTourController.shared
        guard tour.active else { return }
        if completed, !tour.replay, let uid = userID {
            UserDefaults.standard.set(true, forKey: OnboardingTourContent.doneKey(uid))
        }
        tour.reset()
        tourActive = false
        Analytics.paused = false
        screen = .home
        resetHomeScrollToTop()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// Something more important took over (gate, personalization, sign-out, a deep link): stop without the marker.
    func abortOnboardingTour() {
        guard OnboardingTourController.shared.active else { return }
        OnboardingTourController.shared.reset()
        tourActive = false
        Analytics.paused = false
    }

    /// Moves to the screen the current step lives on. Never touches the highlighted control.
    func showTourStepScreen() {
        guard let step = OnboardingTourController.shared.current else { return }
        let target: Screen = step.screen == "profile" ? .profile : .home
        if screen != target { screen = target }
    }
}

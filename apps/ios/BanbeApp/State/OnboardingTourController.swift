import SwiftUI

/// Tour state (note 64), forward only in short chapters since onboarding v5 (note 80). Web twin (still the 8-step
/// jumpable version): src/components/tour/OnboardingTour.jsx.
///
/// Its own ObservableObject (not AppState) so target frames updating every layout pass only re-render the overlay.
/// AppState mirrors one bool, `tourActive`, which RootView/the dock window use to shield the real app.
@MainActor
final class OnboardingTourController: ObservableObject {
    static let shared = OnboardingTourController()

    enum Phase: Equatable {
        /// A step's card over its highlighted control.
        case step
        /// The sheet between chapters: the only place to stop, apart from End tour.
        case chapterDone
        /// The closing sheet after the last chapter.
        case finished
    }

    struct ChapterRun: Identifiable, Equatable {
        let id: String
        let name: (vi: String, en: String)
        /// Indices into `steps`.
        let range: Range<Int>

        static func == (a: ChapterRun, b: ChapterRun) -> Bool { a.id == b.id && a.range == b.range }
    }

    @Published private(set) var steps: [TourStep] = []
    @Published private(set) var chapters: [ChapterRun] = []
    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .step
    @Published private(set) var missing: Set<Int> = []
    @Published private(set) var replay = false
    @Published private(set) var frames: [String: CGRect] = [:]
    /// Bumped when the current step wants its target scrolled into view (Home's first event card).
    @Published private(set) var scrollRequest = 0
    private var latest: [String: CGRect] = [:]

    var active: Bool { !steps.isEmpty }
    var current: TourStep? { steps.indices.contains(index) ? steps[index] : nil }
    var chapterIndex: Int { chapters.firstIndex { $0.range.contains(index) } ?? 0 }
    var chapter: ChapterRun? { chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil }
    var isLastInChapter: Bool { nextIndexInChapter() == nil }
    var doIt: TourDoIt? { current.flatMap { OnboardingTourContent.doIt[$0.id] } }

    func report(_ id: String, _ rect: CGRect?) {
        latest[id] = rect
        guard active, frames[id] != rect else { return }
        frames[id] = rect
    }

    func begin(plan: [(chapter: TourChapter, steps: [TourStep])], replay: Bool) {
        var all: [TourStep] = []
        var runs: [ChapterRun] = []
        for (c, s) in plan where !s.isEmpty {
            runs.append(ChapterRun(id: c.id, name: c.name, range: all.count..<(all.count + s.count)))
            all += s
        }
        self.replay = replay
        missing = []
        index = 0
        phase = .step
        frames = latest
        chapters = runs
        steps = all
        requestScrollIfNeeded()
    }

    func reset() {
        steps = []
        chapters = []
        missing = []
        frames = [:]
        phase = .step
    }

    /// Next step in this chapter, else the chapter break, else the closing sheet. Never goes back.
    func next() {
        guard phase == .step else { return }
        if let i = nextIndexInChapter() {
            index = i
            requestScrollIfNeeded()
        } else {
            phase = chapterIndex + 1 < chapters.count ? .chapterDone : .finished
        }
    }

    /// "Continue" on the chapter break.
    func continueToNextChapter() {
        guard phase == .chapterDone, chapters.indices.contains(chapterIndex + 1) else { return }
        index = chapters[chapterIndex + 1].range.lowerBound
        phase = .step
        requestScrollIfNeeded()
    }

    /// The current target never showed up: skip it, forward only.
    func skipMissing() {
        missing.insert(index)
        next()
    }

    /// Steps shown so far, for the read-only progress bar (missing ones count as passed).
    var position: Int { index + 1 }

    private func nextIndexInChapter() -> Int? {
        guard let c = chapter else { return nil }
        var i = index + 1
        while i < c.range.upperBound && missing.contains(i) { i += 1 }
        return i < c.range.upperBound ? i : nil
    }

    private func requestScrollIfNeeded() {
        if current?.target == "tour.home.eventCard" { scrollRequest += 1 }
    }
}

extension AppState {
    /// First-run entry when no recap offered the tour (the sign-in reveal ended): only while Version 3 is on.
    func maybeStartOnboardingTour() {
        guard onboardingVersion == 3, let uid = userID, !tourActive,
              !UserDefaults.standard.bool(forKey: OnboardingTourContent.doneKey(uid)),
              screen == .home, !needsSettingsOnboarding, !needsPreferencesOnboarding, !onboardingFlowActive
        else { return }
        startOnboardingTour(replay: false)
    }

    /// The onboarding recap's "Start the tour" (note 80): the person asked for it, so no version switch applies.
    func startOnboardingTourFromRecap() {
        guard userID != nil, !tourActive, !onboardingFlowActive else { return }
        screen = .home
        startOnboardingTour(replay: false)
    }

    /// The recap's "Skip, go to Home": the tour never starts by itself afterwards (Help & Legal still replays it).
    func markOnboardingTourSeen() {
        guard let uid = userID else { return }
        UserDefaults.standard.set(true, forKey: OnboardingTourContent.doneKey(uid))
    }

    /// Help & Legal replay: a fresh tour that never reads or writes the first-run marker.
    func replayOnboardingTour() {
        screen = .home
        startOnboardingTour(replay: true)
    }

    func signInRevealDidFinish() { maybeStartOnboardingTour() }

    private func startOnboardingTour(replay: Bool) {
        var plan = OnboardingTourContent.plan(organizerMode: organizerMode, simpleShell: simpleShellEnabled)
        // Guest preview: Home steps only (Account needs a login).
        if onboardingPreview {
            plan = plan.map { ($0.chapter, $0.steps.filter { $0.screen == "home" }) }.filter { !$0.1.isEmpty }
        }
        guard !plan.isEmpty else { return }
        Analytics.paused = true
        tourActive = true
        OnboardingTourController.shared.begin(plan: plan, replay: replay)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// Note 80 guest first run: the recap's answer. Nothing was written to a server; the device only remembers it ran.
    func finishOnboardingPreview(startTour: Bool) {
        Analytics.paused = false
        GuestOnboarding.markSeen()
        guard startTour else {
            onboardingPreview = false
            browseAsGuest()
            return
        }
        // The overlay leaves (preview flag stays on for the tour, which ends back at Welcome).
        screen = .home
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.startOnboardingTour(replay: true)
        }
    }

    /// Finish, End tour or "Finish for now": Home, scrolled to the top; the marker only for a first run.
    func endOnboardingTour(completed: Bool) {
        let tour = OnboardingTourController.shared
        guard tour.active else { return }
        if completed, !tour.replay, let uid = userID {
            UserDefaults.standard.set(true, forKey: OnboardingTourContent.doneKey(uid))
        }
        tour.reset()
        tourActive = false
        Analytics.paused = false
        if onboardingPreview {
            onboardingPreview = false
        }
        screen = .home
        resetHomeScrollToTop()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    /// Something more important took over (gate, personalization, sign-out, a deep link): stop without the marker.
    func abortOnboardingTour() {
        guard OnboardingTourController.shared.active else { return }
        onboardingPreview = false
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

    /// A "do it" step's tap: runs what the highlighted control does, from here, then moves on.
    func performTourDoIt() {
        let tour = OnboardingTourController.shared
        guard tour.phase == .step, let step = tour.current, tour.doIt != nil else { return }
        switch step.id {
        case "home.forYou":
            Haptics.selection()
            if !filterForYou { toggleHomeFilter("forYou") }
        default:
            break
        }
        tour.next()
    }
}

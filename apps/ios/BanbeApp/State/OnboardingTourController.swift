import SwiftUI

/// Tour state (note 64), forward only in short chapters since onboarding v5 (note 80). Web twin (jumpable steps there): src/components/tour/OnboardingTour.jsx.
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
    /// What the current step wants Home scrolled to (a `home.tour.*` id, or "event" for the first event card).
    private(set) var scrollTarget: String = "event"
    /// Asks Home to show one hero tab (For You on the first step, Tonight on the "do it" tap). Home listens with `onReceive`.
    @Published private(set) var heroTabRequest: HomeHeroTab?
    private var latest: [String: CGRect] = [:]

    var active: Bool { !steps.isEmpty }
    var current: TourStep? { steps.indices.contains(index) ? steps[index] : nil }
    var chapterIndex: Int { chapters.firstIndex { $0.range.contains(index) } ?? 0 }
    var chapter: ChapterRun? { chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil }
    var isLastInChapter: Bool { nextIndexInChapter() == nil }
    var doIt: TourDoIt? { current.flatMap { OnboardingTourContent.doIt[$0.id] } }

    /// True from the moment a step starts until its screen is shown, scrolled and measured (stable). The overlay draws
    /// no cut-out and no card meanwhile, so nothing points at a control that is still moving.
    @Published private(set) var settling = true
    private var owners: [String: UUID] = [:]

    func setSettling(_ value: Bool) { if settling != value { settling = value } }

    /// `owner` is the publishing view instance: a disappearing view only clears a frame it published itself.
    func report(_ id: String, _ rect: CGRect?, owner: UUID) {
        if let rect {
            owners[id] = owner
            latest[id] = rect
            guard active, frames[id] != rect else { return }
            frames[id] = rect
        } else {
            guard owners[id] == nil || owners[id] == owner else { return }
            owners[id] = nil
            latest[id] = nil
            guard active, frames[id] != nil else { return }
            frames[id] = nil
        }
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
        settling = true
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
            settling = true
            index = i
            requestScrollIfNeeded()
        } else {
            phase = chapterIndex + 1 < chapters.count ? .chapterDone : .finished
        }
    }

    /// "Continue" on the chapter break.
    func continueToNextChapter() {
        guard phase == .chapterDone, chapters.indices.contains(chapterIndex + 1) else { return }
        settling = true
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

    func requestHeroTab(_ tab: HomeHeroTab) { heroTabRequest = tab }

    private func requestScrollIfNeeded() {
        guard let target = current?.target else { return }
        switch target {
        case "tour.home.eventCard": scrollTarget = "event"
        case "tour.home.browse": scrollTarget = "home.tour.browse"
        case "tour.home.filters": scrollTarget = "home.tour.filters"
        case "tour.home.forYou", "tour.home.tonight", "tour.home.rail", "tour.home.search", "tour.home.hosting",
             "tour.host.hero", "tour.host.quick": scrollTarget = "home.tour.hero"
        default: return
        }
        scrollRequest += 1
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
        switch step.screen {
        case "inbox":
            // Same entry the dock uses; the tour only ever runs signed in here (guest previews drop these steps).
            if screen != .inbox { goInbox() }
        case "profile":
            if screen != .profile { resetAccountScrollMemory(); goProfile() }
            // The Personal tab holds the tiles and Settings the account steps point at (web does the same).
            if accountTab != "personal", AccountTabs.tabs(isAdmin: isAdmin, hostMode: organizerMode).contains("personal") {
                accountTab = "personal"
            }
        default:
            if screen != .home { screen = .home }
            if organizerMode { homeView = step.id.hasPrefix("host.") ? .host : .goer }
            // Step 1 always starts from For You, whatever tab Home was left on (web does the same).
            if step.id == "home.forYou" { OnboardingTourController.shared.requestHeroTab(.foryou) }
        }
    }

    /// Account opens at its top for the tour: no saved offset or anchor may pull it elsewhere while a step is measured.
    func resetAccountScrollMemory() {
        accountScrollOffsetByTab = [:]
        accountScrollAnchorIDByTab = [:]
    }

    /// Scrolls Account's content: `relative` moves from where it is now (positive = further down), otherwise to an offset.
    func requestAccountTourScroll(_ y: CGFloat, relative: Bool) {
        accountTourScrollRequest = ScaffoldScrollRequest(token: (accountTourScrollRequest?.token ?? 0) + 1, y: y,
                                                         animated: !UIAccessibility.isReduceMotionEnabled, relative: relative)
    }

    /// Home twin of `requestAccountTourScroll`.
    func requestHomeTourScroll(_ y: CGFloat, relative: Bool) {
        homeTourScrollRequest = ScaffoldScrollRequest(token: (homeTourScrollRequest?.token ?? 0) + 1, y: y,
                                                      animated: !UIAccessibility.isReduceMotionEnabled, relative: relative)
    }

    /// A "do it" step's tap: runs what the highlighted control does, from here, then moves on.
    func performTourDoIt() {
        let tour = OnboardingTourController.shared
        guard tour.phase == .step, let step = tour.current, tour.doIt != nil else { return }
        Haptics.selection()
        // Guest previews have no Activity or Account to open; the step just moves on.
        let signedIn = isSignedIn && !onboardingPreview
        switch step.id {
        case "dock.activity":
            if signedIn { goInbox() }
        case "dock.account":
            if signedIn { resetAccountScrollMemory(); goProfile() }
        case "host.tab":
            if organizerMode { homeView = .host }
        default:
            // The highlight covers the whole tab row, so the tap shows Tonight (web picks the tab under the finger).
            if step.id == "home.tonight" { OnboardingTourController.shared.requestHeroTab(.tonight) }
        }
        tour.next()
    }
}

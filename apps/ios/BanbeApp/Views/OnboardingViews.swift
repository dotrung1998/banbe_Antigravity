import SwiftUI
import PhotosUI
import UIKit

/// Port of src/screens/Splash.jsx — the logomotion animation and the
/// tagline; tapping (or waiting) moves on to the language picker.
///
/// Completion-gating fix (2026-09-30) — the AUTOMATIC advance (and,
/// through it, the FaceID lock prompt/login/home destination
/// `dismissSplash` routes to) now waits for BOTH the logomotion animation
/// to report one real completed cycle (`animationComplete`, via
/// `LogomotionView`'s new `onComplete`) AND session/bootstrap readiness
/// (`auth.sessionChecked` — see that property's own doc comment for the
/// real race this closes). A bounded fallback timer (`fallbackFired`)
/// covers a WebView load failure/missing asset so a broken animation can
/// never hang the splash forever — it proceeds exactly as if completion
/// had fired normally. Reduce Motion skips waiting on the animation
/// signal entirely (the html/js itself also skips playing it — see
/// `logomotion2309.html`'s `prefersReducedMotion()` — this is belt-and-
/// suspenders for the native side of the same rule).
/// Tap-to-dismiss is deliberately NOT gated on any of this — it's an
/// explicit user action, and this app's existing product behavior already
/// lets an impatient tap skip the whole splash instantly; only the
/// unattended/automatic path and whatever it gates (FaceID, in
/// `RootView.swift`) must wait for real completion.
/// Cold-launch only by construction, not something this fix needs to
/// re-derive: `AppState.init()` sets `screen = .splash` exactly once, at
/// app launch, and nothing else ever re-assigns `.splash` — returning from
/// background never remounts this view or replays the animation.
///
/// 1.0s completed-motion dwell (2026-09-30, second pass) — on the NORMAL
/// (non-Reduce-Motion) path only, once the real `animationComplete` signal
/// fires, a single cancellable `Task.sleep` dwell timer starts at that
/// exact moment (not view mount, not session readiness). The animation's
/// own completed final frame is already held on screen by the prior fix
/// (the JS ticker removes itself), so nothing else is needed to avoid a
/// blank screen during the dwell. Automatic advance then requires the
/// dwell AND session readiness both — whichever finishes later gates the
/// transition (`readyToAdvance` below composes them with `&&`, same as it
/// already composed `sessionChecked`). The bounded `fallbackFired` path
/// (broken WebView/iframe load) intentionally skips the dwell — it is not
/// a real completion, waiting an extra second on top of an already-broken
/// load serves nobody. Reduce Motion skips the dwell entirely, matching
/// its existing "complete immediately" behavior; the dwell Task is never
/// started for that path even though the shared HTML/JS may still fire
/// `animationComplete` immediately under Reduce Motion too (belt-and-
/// suspenders, same reasoning as the native `reduceMotion` OR below).
struct SplashView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var animationComplete = false
    @State private var fallbackFired = false
    @State private var dismissed = false
    @State private var dwellElapsed = false
    @State private var dwellTask: Task<Void, Never>? = nil
    @State private var greetingShown = false

    /// Vietnamese names put the given name last ("Nguyễn Văn An" → An), English first (same rule as onboarding).
    private var greeting: String {
        guard auth.session != nil else { return app.T("Chào mừng bạn đến với banbe", "Welcome to banbe") }
        let parts = (app.user?.displayName ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = app.isEN ? parts.first : parts.last, !name.isEmpty else {
            return app.T("Chào mừng bạn trở lại", "Welcome back")
        }
        return app.T("Chào mừng trở lại, \(name)", "Welcome back, \(name)")
    }

    private static let logomotionAspect: CGFloat = 800.0 / 1288.0
    // A few seconds past the real ~ (totalFrames / 24fps) authored
    // duration (a handful of seconds at 24fps per `lib.properties.fps` /
    // `exportRoot.totalFrames`, logomotion2309.js) — long enough that a
    // healthy load/play never hits it, short enough that a genuinely
    // broken WebView load doesn't strand the user on the splash screen.
    private static let fallbackTimeout: UInt64 = 6_000_000_000
    // Hold the completed launch motion on screen for three extra seconds
    // before advancing (was 1s; +2s requested), normal (non-Reduce-Motion)
    // path only.
    private static let dwellDuration: UInt64 = 5_000_000_000

    /// Both real signals this screen waits on for the AUTOMATIC path.
    /// Reduce Motion and the bounded fallback both count as "ready"
    /// immediately (no dwell); real completion additionally needs the
    /// 1s dwell to have elapsed. Session bootstrap readiness always gates
    /// on top, same as before this pass.
    private var readyToAdvance: Bool {
        let motionReady = reduceMotion || fallbackFired || dwellElapsed
        return motionReady && auth.sessionChecked && accountDataReady
    }

    /// A signed-in launch also waits for `applySession` to finish loading
    /// the account's data, so the splash (and the Face ID prompt that
    /// follows it) never beats the app's own loading. Signed-out launches
    /// have nothing to load. `fallbackFired` bounds the wait.
    private var accountDataReady: Bool {
        guard let uid = auth.session?.user.id else { return true }
        switch auth.gate {
        case .unknown: return fallbackFired       // gate not decided yet
        case .blocked, .unavailable: return true  // nothing to load until it clears
        case .ready: return fallbackFired || app.appliedSessionUID == uid
        }
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                LogomotionView(onComplete: { animationComplete = true })
                    .frame(width: 280, height: 280 * Self.logomotionAspect)
                // Owner, 2026-10-24: a greeting under the motion. Signed in: "Welcome back, <given name>" (the name
                // fades in once the account has loaded); signed out: a general welcome. Web twin: Splash.jsx.
                Text(greeting)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(app.palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18).padding(.horizontal, 32)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.4), value: greeting)
                    .opacity(greetingShown ? 1 : 0)
                    .offset(y: greetingShown || reduceMotion ? 0 : 10)
                    .accessibilityIdentifier("splash.greeting")
                Text(app.T("bạn mới mỗi tuần", "new friends every week"))
                    .font(.system(size: 14))
                    .foregroundStyle(app.palette.ink.opacity(0.75))
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance(force: true) }
        .onChange(of: animationComplete) { _, newValue in
            if newValue && !reduceMotion { startDwellTimer() }
            advance(force: false)
        }
        .onChange(of: auth.sessionChecked) { _, _ in advance(force: false) }
        .onChange(of: app.appliedSessionUID) { _, _ in advance(force: false) }
        .task {
            try? await Task.sleep(nanoseconds: Self.fallbackTimeout)
            fallbackFired = true
            advance(force: false)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: 1.0).delay(0.6)) { greetingShown = true }
        }
        .onDisappear { dwellTask?.cancel() }
    }

    /// Starts the single named 1.0s dwell timer, cancelling any prior one
    /// first (defensive — `animationComplete` only ever flips false->true
    /// once per `LogomotionView`'s own guarded bridge, but this keeps the
    /// invariant explicit rather than assumed).
    private func startDwellTimer() {
        dwellTask?.cancel()
        dwellTask = Task {
            try? await Task.sleep(nanoseconds: Self.dwellDuration)
            guard !Task.isCancelled else { return }
            dwellElapsed = true
            advance(force: false)
        }
    }

    /// `force: true` is the explicit-tap path (always dismisses, no
    /// gating — unchanged relationship to the completion/dwell gate). It
    /// also cancels an in-flight dwell timer since the screen is going
    /// away. `force: false` is every automatic call site — only actually
    /// advances once `readyToAdvance` is true; harmless to call
    /// speculatively (from either `onChange`) before that.
    private func advance(force: Bool) {
        guard app.screen == .splash, !dismissed else { return }
        guard force || readyToAdvance else { return }
        dismissed = true
        dwellTask?.cancel()
        app.dismissSplash(isSignedIn: auth.isSignedIn)
    }
}

/// Port of src/screens/LangPick.jsx.
struct LangPickView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Same mark, at the same 44pt, as src/screens/LangPick.jsx.
                BanbeLogo(kind: .mark, width: 44, height: 44)
                    .padding(.bottom, 26)

                Text("Chọn ngôn ngữ")
                    .font(BanbeTheme.display(27))
                Text("Choose your language")
                    .font(.system(size: 19))
                    .opacity(0.52)
                    .padding(.top, 5)

                VStack(spacing: 10) {
                    choice(title: "Tiếng Việt", subtitle: "Mặc định", active: app.lang == "vi") {
                        app.pickLang("vi")
                    }
                    .accessibilityIdentifier("lang.vi")
                    choice(title: "English", subtitle: "Switch anytime", active: app.lang == "en") {
                        app.pickLang("en")
                    }
                    .accessibilityIdentifier("lang.en")
                }
                .padding(.top, 28)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text("›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/ThemePick.jsx — the light/dark choice, previewed
/// live, then "Continue" into the feed.
struct ThemePickView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.T("Hiển thị", "Appearance")).font(.system(size: 11.5))
                Text(app.T("Bạn thích nền sáng hay tối?", "Light or dark?"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 8)
                Text(app.T("Bạn có thể đổi lại bất cứ lúc nào trong Tài khoản.",
                           "You can change this anytime in your account."))
                    .font(.system(size: 13.5))
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    choice(title: app.T("Sáng", "Light"), subtitle: app.T("Nền giấy ấm", "Warm paper"),
                           active: app.theme == "light") { app.pickTheme("light") }
                        .accessibilityIdentifier("theme.light")
                    choice(title: app.T("Tối", "Dark"), subtitle: app.T("Nền mực dịu mắt", "Soft ink background"),
                           active: app.theme == "dark") { app.pickTheme("dark") }
                        .accessibilityIdentifier("theme.dark")
                }
                .padding(.top, 28)

                InkButton(title: app.T("Tiếp tục", "Continue")) { app.finishOnboarding(isSignedIn: auth.isSignedIn) }
                    .accessibilityIdentifier("onboarding.continue")
                    .padding(.top, 26)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 80)
        }
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(19))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text(active ? "✓" : "›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(18)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/CreateEvent.jsx — the organizer profile fields, the
/// event fields, category pickers and the submit that calls
/// create_event_draft.
/// A single staged gallery tile — either one of the event's ALREADY-
/// uploaded `event_photos` rows (when editing an owned event) or a
/// freshly-picked local image, unified so remove/reorder/cover-pick work
/// the same way on both (mirrors web's CreateEvent.jsx `items` list).
struct StagedGalleryItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case existing(photoID: UUID, storagePath: String)
        case new(image: UIImage)
        static func == (a: Kind, b: Kind) -> Bool {
            switch (a, b) {
            case (.existing(let x, _), .existing(let y, _)): return x == y
            case (.new(let x), .new(let y)): return x === y
            default: return false
            }
        }
    }
    let id: String
    var kind: Kind
    var url: URL? // only for .existing, resolved once at seed time

    var image: UIImage? { if case .new(let img) = kind { return img }; return nil }
}

/// Port of src/screens/CreateEvent.jsx — the organizer profile fields, the
/// event fields, category pickers and the submit that calls
/// create_event_draft.
struct CreateEventView: View {
    @EnvironmentObject var app: AppState

    private let categories = EventTypes.categoryDefs() // src/data/eventTypeProfiles.json
    private let maxPhotos = 8
    private let minPhotos = 3

    @State private var galleryItems: [StagedGalleryItem] = []
    @State private var coverItemID: String?
    @State private var pickerItems: [PhotosPickerItem] = []
    /// Address-autocomplete fix pass (2026-09-28) — debounce for the
    /// location search box, same 500ms/4-char-minimum convention web's
    /// own `createLocType` (BanBeContext.jsx) uses. Cancelling the previous
    /// `Task` on every keystroke is this view's equivalent of web's
    /// `clearTimeout` — `Task.sleep` throws `CancellationError` when
    /// cancelled, which the `try?` below simply treats as "never fired."
    @State private var createAddressSearchTask: Task<Void, Never>?
    @State private var photoError = ""
    @State private var seededForEventID: String?
    @State private var seededExistingIDs: Set<UUID> = []
    @State private var dateTimeSheetOpen = false
    // "Review before submitting" step (task 1) — a plain local bool, same
    // reasoning as web's `reviewOpen` (CreateEvent.jsx): every field it
    // shows already lives in `app.create*`/this view's own `galleryItems`/
    // `coverItemID` state, so dismissing it loses nothing.
    @State private var reviewOpen = false
    // TASK 3 (event creation validation pass) — the post-submission
    // chooser; opened only by a real submitCreateEvent() success (see the
    // review sheet's own onConfirm above), never merely because the
    // request finished. `successChoiceMade` distinguishes an explicit
    // button tap from a swipe-to-dismiss/backdrop-tap on the native
    // `.confirmationDialog` — both must land on the SAME "unambiguous
    // success" default (pending events) per this ticket's own instruction.
    @State private var successChooserOpen = false
    @State private var successChoiceMade = false
    /// Note 48: field errors stay quiet until the host asks to review (or
    /// taps "what's missing"), instead of shouting from the first render.
    @State private var attemptedReview = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var draftsSheetOpen = false
    @State private var draftFullAlert = false
    @State private var draftSavedOpen = false
    /// Note 48: Create event is a 5-step flow, one section per page. Note 53: it always opens on step 1 (Host),
    /// even when Host is already ticked from the organizer profile, so the host can check it.
    @State private var currentStep: Section = .host
    /// Note 53: which Create field has the keyboard (ids from Lib/CreateFieldGuide.swift). Drives the focus border,
    /// keeps the field above the keyboard, and lets a recipe Fix focus a field directly.
    @FocusState private var focusedField: String?
    /// Note 53: the field a Fix / Review-with-gaps pointed at (halo + "👇" tip for ~4.5s).
    @State private var attnField: String?
    @State private var attnHint: String?
    @State private var attnToken = 0
    @State private var attnClearTask: Task<Void, Never>?
    /// Note 53: steps slide in from the side you're moving towards, instead of a lone cross-fade.
    @State private var stepForward = true
    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .offset(x: stepForward ? 28 : -28).combined(with: .opacity), removal: .opacity)
    }
    /// Note 50 — "recipe for success": get_host_benchmarks for the primary category + city (nil = tips only,
    /// never numbers) and the platform-wide audience count for the category.
    @State private var benchmarks: HostBenchmarks?
    @State private var audienceDemand: Int?
    @State private var recipeOpen = false

    private var removedExistingIDs: [UUID] {
        let kept = Set(galleryItems.compactMap { if case .existing(let id, _) = $0.kind { return id }; return nil })
        return seededExistingIDs.filter { !kept.contains($0) }
    }
    private var newImagesInOrder: [UIImage] { galleryItems.compactMap(\.image) }
    private var coverNewIndex: Int? {
        guard let coverItemID, let item = galleryItems.first(where: { $0.id == coverItemID }),
              case .new(let image) = item.kind else { return nil }
        return newImagesInOrder.firstIndex(where: { $0 === image })
    }
    private var existingCoverPath: String? {
        guard let coverItemID, let item = galleryItems.first(where: { $0.id == coverItemID }),
              case .existing(_, let path) = item.kind else { return nil }
        return path
    }

    // TASK 3 (event creation validation pass) — these five are genuinely
    // required (not decorative asterisks): each blocks the "Xem lại"/
    // "Review" button below via `enabled:`, mirroring the SAME "hint text
    // always visible while invalid" convention this screen's own
    // `!app.createLocConfirmed` hint already uses (not a tap-triggered
    // banner — `InkButton(enabled: false)` is a real disabled button, a
    // tap on it does nothing to react to). `galleryItems` already excludes
    // removed items (removeGalleryItem splices them out) and only ever
    // holds locally-staged/already-uploaded ones — nothing "failed/
    // in-progress" to separately exclude before a real upload attempt.
    private var descValid: Bool { !app.createDesc.trimmingCharacters(in: .whitespaces).isEmpty }
    private var dateTimeValid: Bool { app.createEventDate != nil && app.createEventTime != nil }
    private var seatsValid: Bool { Int(app.createSeats) ?? 0 > 0 }
    private var catsValid: Bool { !app.createCats.isEmpty }
    private var includedValid: Bool { app.createIncludedItems.contains { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var photosValid: Bool { galleryItems.count >= minPhotos && galleryItems.count <= maxPhotos }
    private var hasCreateFieldErrors: Bool { !descValid || !dateTimeValid || !seatsValid || !catsValid || !includedValid || !photosValid }
    private var nameValid: Bool { !app.createName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canOpenReview: Bool { nameValid && app.createLocConfirmed && !hasCreateFieldErrors }

    /// Note 48 progress sections, in on-screen order.
    private enum Section: Int, CaseIterable { case host, basics, whenWhere, tickets, photos
        var anchor: String { "create.section.\(rawValue)" }
    }
    private var sectionTitles: [String] {
        [app.T("Host", "Host"), app.T("Cơ bản", "Basics"), app.T("Thời gian & nơi", "When & where"),
         app.T("Vé", "Tickets"), app.T("Ảnh", "Photos")]
    }
    /// One calculation (Lib/CreateProgress.swift) behind the ring, "N steps left", "Still needed here" and the
    /// Review summary, so they can never disagree.
    private var progress: CreateProgress.Result {
        CreateProgress.compute(missing: missingFields, required: EventTypes.requiredFields(typeProfile ?? .generic("")))
    }
    /// Event type profiles (switch event_type_profiles, migration 203): the first picked category shapes the form.
    /// Off, or a type with no profile: everything behaves exactly as before.
    private var typeProfile: EventTypeProfile? {
        guard app.eventTypesEnabled, let key = app.createCats.first else { return nil }
        return EventTypes.profile(key)
    }
    private var langCode: String { app.isEN ? "en" : "vi" }
    private func sectionDone(_ section: Section) -> Bool { progress.steps[section.rawValue].done }
    private var firstIncompleteSection: Section? { Section.allCases.first { !sectionDone($0) } }
    /// A dollar amount must read like 12.50; an empty field means free.
    private var priceValid: Bool { app.createPrice.trimmingCharacters(in: .whitespaces).isEmpty || priceDigits != nil }

    // MARK: Recipe for success (note 50)

    private var bench: HostBenchmarks? { EventRecipe.hasBenchmarks(benchmarks) ? benchmarks : nil }
    private var primaryCat: String { app.createCats.first ?? "" }
    private var benchmarkKey: String { "\(primaryCat)|\(app.createCity.lowercased())|\(app.createCurrency)|\(app.isSignedIn)|\(app.createSent)" }
    private var draftPriceVnd: Int { priceDigits ?? 0 }
    private var draftKeywords: [String] {
        app.createKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// The picked date + wall-clock time at the venue (`app.createEventTimeZone`) as one instant.
    private var draftStartsAt: Date? { app.createStartsAt }
    private func venueInstant(day: Date, time: Date) -> Date? {
        let cal = EventMarket.calendar(app.createEventTimeZone)
        let dc = cal.dateComponents([.year, .month, .day], from: day)
        let tc = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(year: dc.year, month: dc.month, day: dc.day, hour: tc.hour, minute: tc.minute))
    }
    /// UTC offset (minutes) of the event's zone at `date` — benchmark slots are bucketed in each event's own zone.
    private func venueOffsetMin(_ date: Date?) -> Int {
        app.createEventTimeZone.secondsFromGMT(for: date ?? Date()) / 60
    }
    private var recipe: [EventRecipe.Check] {
        EventRecipe.checks(EventRecipe.Draft(
            name: app.createName, description: app.createDesc, intro: app.createIntro,
            includedCount: app.createIncludedItems.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }.count,
            keywords: draftKeywords, priceVnd: draftPriceVnd, seats: seatsBinding, startsAt: draftStartsAt,
            photos: galleryItems.count, chatGreeting: app.createChatGreeting + app.createChatGreetingEn,
            offsetMin: venueOffsetMin(draftStartsAt)
        ), benchmarks: bench, goal: app.createHostGoal, now: Date())
    }
    private func recipeCheck(_ id: String) -> EventRecipe.Check? { recipe.first { $0.id == id } }
    private var createCatLabel: String {
        app.createCats.compactMap { key in categories.first(where: { $0.key == key }).map { app.T($0.vi, $0.en) } }
            .joined(separator: " ▪︎ ")
    }
    private func openRecipe() {
        Analytics.track(.recipeOpened)
        recipeOpen = true
    }
    private func fixIngredient(_ c: EventRecipe.Check) {
        Analytics.track(.recipeFixTapped(ingredient: c.id))
        if CreateFieldGuide.step(of: c.fix.field) != nil {
            guideTo(c.fix.field, hint: EventRecipe.copy(c, app.T, currency: app.createCurrency).title)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false }
            goTo(Section(rawValue: c.fix.step) ?? .basics)
        }
    }

    /// Note 53: take the host to the exact field — open its step, centre it, point at it with the For You halo and
    /// a "👇" tip, and (for a typing field) focus it so the keyboard opens. Used by a recipe Fix and by Review with
    /// gaps. Waits for the sheet/overlay to finish closing first: focus can't move while a sheet is still up.
    private func guideTo(_ field: String, hint: String?) {
        guard let index = CreateFieldGuide.step(of: field), let section = Section(rawValue: index) else { return }
        focusedField = nil
        recipeOpen = false
        withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false }
        if currentStep != section {
            stepForward = section.rawValue >= currentStep.rawValue
            withAnimation(.easeInOut(duration: 0.22)) { currentStep = section }
        }
        attnClearTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            attnHint = hint
            attnField = field
        }
        attnToken += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.3)) { scrollProxy?.scrollTo(CreateFieldGuide.anchor(field), anchor: .center) }
            if CreateFieldGuide.isTextField(field) { focusedField = field }
        }
        attnClearTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { attnField = nil; attnHint = nil }
        }
    }

    /// Note 53: wraps a Create field as a "take me there" target — its scroll anchor, the halo while it's the
    /// target, and the "👇" tip floating above it (out of the layout, so nothing moves while the host types).
    /// Type-erased on purpose (see `hostStepView`): keeps each field's view value small on the stack.
    private func guided<Content: View>(_ field: String, cornerRadius: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> AnyView {
        AnyView(content()
            .id(CreateFieldGuide.anchor(field))
            .attentionHalo(active: attnField == field, token: attnToken, cornerRadius: cornerRadius)
            .overlay(alignment: .topLeading) {
                if attnField == field, let attnHint {
                    Text("👇 " + attnHint)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(app.palette.paper)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
                        .fixedSize(horizontal: false, vertical: true)
                        // A zero-height frame at the wrapper's top edge, bottom-aligned: the tip grows UPWARD from
                        // 12pt above the field instead of covering its label.
                        .frame(height: 0, alignment: .bottomLeading)
                        .offset(y: -12)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                        .accessibilityIdentifier("create.coach")
                }
            })
    }

    /// Every required field still missing, keyed by its CreateFieldGuide id.
    private var missingFields: [String: Bool] {
        ["hostName": app.orgRegName.trimmingCharacters(in: .whitespaces).isEmpty, "name": !nameValid, "description": !descValid,
         "categories": !catsValid, "included": !includedValid, "location": !app.createLocConfirmed, "date": !dateTimeValid,
         "price": !priceValid, "seats": !seatsValid, "photos": !photosValid]
    }
    private func missingLabel(_ field: String) -> String {
        CreateProgress.label(field, minPhotos: minPhotos) { app.T($0, $1) }
    }
    /// A tap on a "Still needed" chip lands on that field (same guide as a recipe Fix).
    private func goToMissing(_ field: String) {
        Analytics.track(.createEventStillNeededTapped(field: field))
        guideTo(field, hint: app.T("Còn thiếu: ", "Still needed: ") + missingLabel(field))
    }
    /// Fill rate of the benchmark cell a date quick pick would land in (with the current time, else 19:00).
    private func slotFill(day: Date, time: Date?) -> Double? {
        guard let bench, let t = time ?? SmartDefaults.timeOfDay("19:00", timeZone: app.createEventTimeZone),
              let at = venueInstant(day: day, time: t) else { return nil }
        let (dow, slot) = EventRecipe.localParts(at, offsetMin: venueOffsetMin(at))
        return bench.slots?.first { $0.dow == dow && $0.slot == slot }?.medianFill
    }

    /// Something the host typed or picked would be lost by leaving.
    private var hasUnsavedInput: Bool {
        guard app.createEditEventId == nil, !app.createSent else { return false }
        let typed = [app.createName, app.createDesc, app.createLoc, app.createIntro, app.createKeywords]
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let touchedDefaults = app.createAppliedDefaults != nil && !app.createDraftMatchesAppliedDefaults
        return typed || !galleryItems.isEmpty || touchedDefaults
    }

    private func seedGalleryIfNeeded() {
        guard let editID = app.createEditEventId else {
            if seededForEventID != nil { galleryItems = []; coverItemID = nil; seededExistingIDs = [] }
            seededForEventID = nil
            return
        }
        guard seededForEventID != editID, !app.eventPhotosLoading else { return }
        seededForEventID = editID
        let cover = app.myOrgEventSummaries.first(where: { $0.id == editID })?.coverImage
        // Strict invite-only events (migration 113) — loadEventPhotos
        // already resolves each row's display URL (public getPublicURL or
        // a private-bucket signed URL), so this no longer needs its own
        // synchronous (and, for a private path, simply wrong) getPublicURL
        // call.
        let seeded: [StagedGalleryItem] = app.eventPhotos.map { photo in
            StagedGalleryItem(id: photo.id.uuidString, kind: .existing(photoID: photo.id, storagePath: photo.storagePath), url: app.eventPhotoURLs[photo.id])
        }
        galleryItems = seeded
        seededExistingIDs = Set(app.eventPhotos.map(\.id))
        let coverItem = seeded.first { if case .existing(_, let path) = $0.kind { return path == cover }; return false }
        coverItemID = (coverItem ?? seeded.first)?.id
    }

    private func removeGalleryItem(_ item: StagedGalleryItem) {
        galleryItems.removeAll { $0.id == item.id }
        if coverItemID == item.id { coverItemID = galleryItems.first?.id }
    }

    /// Photo-management cleanup (task 1, screenshot 1 follow-up) — a clean
    /// vertical list, one row per photo, replacing the old 4-column
    /// `LazyVGrid` where remove/cover controls were tiny overlapping
    /// buttons stacked on the thumbnail itself (matches web's identical
    /// redesign, CreateEvent.jsx). Same underlying actions as before
    /// (remove, set-cover, and now up/down reorder using the SAME array-
    /// swap `galleryItems` already supported nothing new is invented here)
    /// — just laid out so nothing overlaps the photo or another control.
    @ViewBuilder
    private func gallerySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    Text(app.T("Hình ảnh", "Photos")).font(.system(size: 11.5))
                    Text("*").font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
                }
                Spacer()
                Text("\(galleryItems.count)/\(maxPhotos) (\(app.T("tối thiểu \(minPhotos)", "min \(minPhotos)")))").font(.system(size: 10.5))
            }
            if let photos = recipeCheck("photos") {
                RecipeInsight(check: photos, line: photos.source == .data
                              ? app.T("Sự kiện kín chỗ thường có \(photos.target ?? 0)+ ảnh.", "Events that filled well had \(photos.target ?? 0)+ photos.")
                              : app.T("Mẹo: \(photos.target ?? 0)+ ảnh cho khách thấy không khí.", "Tip: \(photos.target ?? 0)+ photos show guests the vibe."),
                              identifier: "create.photosInsight")
            }
            VStack(spacing: 8) {
                ForEach(Array(galleryItems.enumerated()), id: \.element.id) { index, item in
                    let isCover = item.id == coverItemID
                    HStack(spacing: 10) {
                        Group {
                            if let image = item.image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottom) {
                            if isCover {
                                Text(app.T("Ảnh bìa", "Cover"))
                                    .font(.system(size: 8.5, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                                    .background(app.palette.ink)
                                    .foregroundStyle(app.palette.paper)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.T("Ảnh \(index + 1)", "Photo \(index + 1)"))
                                .font(.system(size: 11.5)).opacity(0.65)
                            Button { coverItemID = item.id } label: {
                                Text(isCover ? app.T("Đang là ảnh bìa", "Currently the cover") : app.T("Đặt làm ảnh bìa", "Set as cover"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(isCover ? app.palette.ink : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(isCover ? .clear : app.palette.rule, lineWidth: 1))
                                    .foregroundStyle(isCover ? app.palette.paper : app.palette.ink)
                            }
                            .buttonStyle(.plain)
                            .disabled(isCover)
                        }
                        Spacer(minLength: 0)

                        VStack(spacing: 4) {
                            Button {
                                guard index > 0 else { return }
                                Haptics.selection()
                                galleryItems.swapAt(index - 1, index)
                            } label: {
                                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(app.palette.rule))
                            }
                            .buttonStyle(.plain)
                            .opacity(index == 0 ? 0.3 : 1)
                            .disabled(index == 0)

                            Button {
                                guard index < galleryItems.count - 1 else { return }
                                Haptics.selection()
                                galleryItems.swapAt(index, index + 1)
                            } label: {
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(app.palette.rule))
                            }
                            .buttonStyle(.plain)
                            .opacity(index == galleryItems.count - 1 ? 0.3 : 1)
                            .disabled(index == galleryItems.count - 1)
                        }
                        .foregroundStyle(app.palette.ink)

                        Button { removeGalleryItem(item) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BanbeTheme.alert)
                                .frame(width: 26, height: 26)
                                .background(BanbeTheme.alert.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if galleryItems.count < maxPhotos {
                    let addTitle = app.T("Thêm ảnh", "Add photo")
                    let inkColor = app.palette.ink
                    let paperColor = app.palette.paper
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: maxPhotos - galleryItems.count, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(addTitle).font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(inkColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(paperColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(inkColor, style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                }
            }
            if !photoError.isEmpty {
                Text(photoError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            } else if !photosValid && !app.createSent && attemptedReview {
                Text(app.T("Cần tối thiểu \(minPhotos) và tối đa \(maxPhotos) ảnh khả dụng.", "Minimum \(minPhotos), maximum \(maxPhotos) available photos."))
                    .font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .padding(.top, 22)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                var accepted: [StagedGalleryItem] = []
                for pickerItem in newItems {
                    guard let data = try? await pickerItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        await MainActor.run { photoError = app.T("Không thể đọc một trong các ảnh đã chọn.", "Couldn't read one of the selected photos.") }
                        continue
                    }
                    if data.count > 50 * 1024 * 1024 {
                        await MainActor.run { photoError = app.T("Mỗi ảnh tối đa 50MB.", "Each photo must be under 50MB.") }
                        continue
                    }
                    // Baked upright once here, so every preview (Private tab, the Event Detail
                    // preview's hero and strip) shows it the way the uploaded copy will look.
                    accepted.append(StagedGalleryItem(id: UUID().uuidString, kind: .new(image: image.normalizedUp()), url: nil))
                }
                await MainActor.run {
                    if !accepted.isEmpty {
                        photoError = ""
                        galleryItems.append(contentsOf: accepted)
                        if coverItemID == nil { coverItemID = galleryItems.first?.id }
                    }
                    pickerItems = []
                }
            }
        }
    }

    @ViewBuilder
    private func greetingEditor() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FormFieldLabel(icon: "bubble.left", text: app.T("Lời nhắn mở đầu", "Opening message"),
                           trailing: app.T("Tuỳ chọn", "Optional"))
            Text(app.T("Hiện ở đầu cuộc trò chuyện khi khách nhấn \"Nhắn cho bạn\". Để trống để dùng lời chào mặc định. Chỉ để hiển thị, không lưu như tin nhắn.",
                        "Shown at the top of the chat when a guest taps \"Message\" you. Leave blank for a default greeting. Display only, not stored as a message."))
                .font(.system(size: 12.5)).opacity(0.7)
            greetingField(label: app.T("Tiếng Việt", "Vietnamese"), text: $app.createChatGreeting, id: "create.chatGreeting", focusID: "greeting")
            greetingField(label: app.T("Tiếng Anh", "English"), text: $app.createChatGreetingEn, id: "create.chatGreetingEn", focusID: "greetingEn")
                .id(CreateFieldGuide.anchor("greetingEn"))
        }
        .foregroundStyle(app.palette.ink)
    }

    @ViewBuilder
    private func greetingField(label: String, text: Binding<String>, id: String, focusID: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(text.wrappedValue.count)/500").font(.system(size: 11)).monospacedDigit().opacity(0.6)
            }
            TextField("", text: text, axis: .vertical)
                .lineLimit(3...8)
                .focused($focusedField, equals: focusID)
                .roundedFormEditor(app: app, minHeight: 80, focused: focusedField == focusID)
                .accessibilityIdentifier(id)
                .onChange(of: text.wrappedValue) { _, newValue in
                    if newValue.count > 500 { text.wrappedValue = String(newValue.prefix(500)) }
                }
        }
    }

    @ViewBuilder
    private func introEditor() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                FormFieldLabel(icon: "doc.text", text: app.T("Giới thiệu sự kiện", "Event introduction"),
                               trailing: "\(app.createIntro.count)/4000")
                    // Note 53: the counter warms up near the limit (honey) and turns alert at it.
                    .foregroundStyle(app.createIntro.count >= 4000 ? BanbeTheme.alert
                                     : app.createIntro.count >= 3800 ? app.palette.honey : app.palette.ink.opacity(0.8))
            }
            Text(app.T("Một đoạn giới thiệu dài hơn, hấp dẫn. Tách dòng trống giữa các đoạn. Không phải quảng cáo giả, không phải \"Bao gồm\".",
                        "A longer, attractive write-up. Leave a blank line between paragraphs. Not fabricated marketing copy, not the same as \"Included\"."))
                .font(.system(size: 12.5)).opacity(0.7)
            // Note 53: a growing TextField instead of a TextEditor. A TextEditor scrolls inside itself, so the
            // screen's own scroll view (which is what moves things above the keyboard) only ever saw its top
            // edge and left the lines being typed under the keyboard. This one grows with the text (up to 12
            // lines, then scrolls inside), and the focus handler centres it above the keyboard.
            TextField(app.T("Một buổi tối ấm cúng cho mười bốn người lạ…", "A cozy evening for fourteen strangers…"),
                      text: $app.createIntro, axis: .vertical)
                .lineLimit(5...12)
                .focused($focusedField, equals: "intro")
                .roundedFormEditor(app: app, minHeight: 130, focused: focusedField == "intro")
                .accessibilityIdentifier("create.intro")
                .onChange(of: app.createIntro) { _, newValue in
                    if newValue.count > 4000 { app.createIntro = String(newValue.prefix(4000)) }
                }
        }
        .foregroundStyle(app.palette.ink)
    }

    // "Bao gồm" item-editing parity fix (2026-09-29) — iOS's CreateEventView
    // previously had no editing UI for this field at all, unlike web's
    // CreateEvent.jsx (`addCreateIncludedItem`/`removeCreateIncludedItem`/
    // `setCreateIncludedItem`) — a real, reported gap: a host filling this
    // in on iOS had nowhere to put it, and the review screen correctly
    // showed nothing because there was genuinely nothing to show. Up to 3
    // items, same as the server-side cap (migration 087).
    @ViewBuilder
    private func includedItemsEditor() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FormFieldLabel(icon: "checklist", text: typeProfile?.wizard?.includedTitle?.text(langCode) ?? app.T("Bao gồm", "Included"),
                           required: EventTypes.requiredFields(typeProfile ?? .generic("")).contains("included"),
                           trailing: "\(app.createIncludedItems.count)/3")
            ForEach(Array(app.createIncludedItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            typeProfile?.wizard?.includedPlaceholder?.text(langCode) ?? app.T("Tên (vd. 5 món)", "Label (e.g. 5 courses)"),
                            text: Binding(get: { item.label }, set: { app.setCreateIncludedItemLabel(index, $0) })
                        )
                        .focused($focusedField, equals: "included.\(index).label")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityIdentifier("create.included.\(index).label")
                        Divider()
                        TextField(
                            app.T("Mô tả (không bắt buộc)", "Detail (optional)"),
                            text: Binding(get: { item.detail }, set: { app.setCreateIncludedItemDetail(index, $0) })
                        )
                        .focused($focusedField, equals: "included.\(index).detail")
                        .font(.system(size: 15))
                        .opacity(0.85)
                        .accessibilityIdentifier("create.included.\(index).detail")
                    }
                    Button {
                        app.removeCreateIncludedItem(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(app.palette.ink.opacity(0.35))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -10)
                    .accessibilityLabel(app.T("Xoá mục", "Remove item"))
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 14)
                .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            }
            if app.createIncludedItems.count < 3 {
                Button { app.addCreateIncludedItem() } label: {
                    Label(app.T("Thêm mục", "Add item"), systemImage: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(app.palette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("create.included.add")
            }
            if !includedValid && !app.createSent && attemptedReview {
                Text(app.T("Hãy thêm ít nhất một mục Bao gồm.", "Please add at least one Included item."))
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 8)
    }

    // Address-autocomplete fix pass (2026-09-28) — replaces the old
    // single-shot "type free text, tap Confirm, get ONE geocode result"
    // flow (mirrors web's identical BanBeContext.jsx/CreateEvent.jsx
    // change, same pass). Publishing now REQUIRES a real, selected
    // address — there is no more "Skip".
    @ViewBuilder
    private func locationConfirmSection() -> some View {
        if app.createAddressSearching {
            Text(app.T("Đang tìm địa chỉ…", "Searching addresses…"))
                .font(.system(size: 11)).opacity(0.6).foregroundStyle(app.palette.ink)
        }
        if !app.createAddressSearchError.isEmpty {
            HStack(spacing: 8) {
                Text(app.createAddressSearchError).font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                Spacer(minLength: 0)
                Button(app.T("Thử lại", "Retry")) { Task { await app.retryCreateAddressSearch() } }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink)
            }
        }
        if !app.createAddressSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(app.createAddressSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        app.selectCreateAddressSuggestion(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.addressLine + (suggestion.isVenue ? " " + app.T("(địa điểm)", "(venue)") : ""))
                                .font(.system(size: 13, weight: .semibold))
                            Text([suggestion.district, suggestion.city, suggestion.postalCode].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.system(size: 11.5)).opacity(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink)
                    if index < app.createAddressSuggestions.count - 1 {
                        Divider().overlay(app.palette.rule)
                    }
                }
                // These suggestions come from MapKit (MKLocalSearch), i.e. Apple Maps data. (Web's list is
                // OpenStreetMap Nominatim and says so itself.)
                Text(app.T("Kết quả từ Apple Maps", "Results from Apple Maps"))
                    .font(.system(size: 9.5)).opacity(0.45)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        if app.createLocConfirmed {
            VStack(alignment: .leading, spacing: 6) {
                Text("✓ " + app.createLocLabel).font(.system(size: 11.5)).opacity(0.85)
                Text(app.T("Sẽ hiện ghim trên bản đồ tại toạ độ này.", "Will show a map pin at this exact point."))
                    .font(.system(size: 10.5)).opacity(0.6)
                Button(app.T("Đổi địa chỉ", "Change address")) { app.clearCreateAddressSelection() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(app.palette.ink.opacity(0.75))
            }
            .padding(10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(app.palette.ink)
        } else {
            Text(app.T("Chọn một địa chỉ gợi ý ở trên (cần thiết để đăng sự kiện).", "Pick a suggested address above (required to publish)."))
                .font(.system(size: 11)).opacity(0.6).foregroundStyle(app.palette.ink)
        }
    }

    // Labels read the picked date/time in the event's own zone (Vietnam unless the venue is in the US).
    private var dateLabelFormatter: DateFormatter { app.createFormatter("dd.MM.yyyy") }
    private var timeLabelFormatter: DateFormatter { app.createFormatter("HH:mm") }

    /// "Tomorrow, Sat 25 Oct" style (the video's "Tomorrow, Fri 25 Mar").
    private func friendlyDateLabel(_ date: Date) -> String {
        let cal = EventMarket.calendar(app.createEventTimeZone)
        let f = DateFormatter()
        f.timeZone = app.createEventTimeZone
        f.locale = Locale(identifier: app.isEN ? "en_GB" : "vi_VN")
        f.dateFormat = app.isEN ? "EEE d MMM" : "EEEE, d/M"
        let base = f.string(from: date)
        if cal.isDateInToday(date) { return app.T("Hôm nay, ", "Today, ") + base }
        if cal.isDateInTomorrow(date) { return app.T("Ngày mai, ", "Tomorrow, ") + base }
        return base
    }

    /// "Vietnam time", or the venue's zone for a US address (migration 195), e.g. "Venue time (PDT)".
    private var zoneTrailingLabel: String {
        let tz = app.createEventTimeZone
        guard tz.identifier != EventMarket.vnTimeZoneID else { return app.T("Giờ Việt Nam", "Vietnam time") }
        let abbr = tz.abbreviation(for: app.createStartsAt ?? Date()) ?? tz.identifier
        return app.T("Giờ tại nơi tổ chức (\(abbr))", "Venue time (\(abbr))")
    }

    @ViewBuilder
    private func dateTimeRow() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FormFieldLabel(icon: "calendar", text: app.T("Ngày & giờ", "Date & time"), required: true,
                           trailing: zoneTrailingLabel)
            Button {
                dateTimeSheetOpen = true
            } label: {
                HStack(spacing: 10) {
                    if let date = app.createEventDate, let time = app.createEventTime {
                        Text(friendlyDateLabel(date))
                            .font(.system(size: 16, weight: .semibold))
                        Text(timeLabelFormatter.string(from: time))
                            .font(.system(size: 16))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(app.palette.ink.opacity(0.07), in: Capsule())
                    } else {
                        Text(app.T("Chọn ngày & giờ", "Pick date & time")).font(.system(size: 16)).opacity(0.5)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).opacity(0.5)
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 16).padding(.vertical, 15)
                .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create.dateTime")
            if !dateTimeValid && !app.createSent && attemptedReview {
                Text(app.T("Hãy chọn ngày và giờ diễn ra.", "Please pick a date and time."))
                    .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
            }
        }
        .sheet(isPresented: $dateTimeSheetOpen) {
            EventDateTimeSheet(date: $app.createEventDate, time: $app.createEventTime,
                               slotFill: bench == nil ? nil : { day, time in slotFill(day: day, time: time) },
                               timeZone: app.createEventTimeZone)
                .environmentObject(app)
        }
    }

    #if DEBUG
    /// `-uiFixtureReview YES` (with `shell.create`): two synthetic photos — the cover stored sideways with EXIF
    /// orientation `.right`, like a portrait phone shot — and a confirmed place, then straight into Review.
    private func openFixtureReviewIfAsked() {
        guard UITestFixture.opensReview, galleryItems.isEmpty else { return }
        func swatch(_ color: UIColor, _ size: CGSize) -> UIImage {
            UIGraphicsImageRenderer(size: size).image { ctx in
                color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.18))
            }
        }
        let raw = swatch(UIColor(red: 0.61, green: 0.36, blue: 0.23, alpha: 1), CGSize(width: 800, height: 600))
        let sideways = UIImage(cgImage: raw.cgImage!, scale: 1, orientation: .right)
        galleryItems = [
            StagedGalleryItem(id: "fx-1", kind: .new(image: sideways.normalizedUp()), url: nil),
            StagedGalleryItem(id: "fx-2", kind: .new(image: swatch(UIColor(red: 0.28, green: 0.35, blue: 0.2, alpha: 1), CGSize(width: 600, height: 800))), url: nil),
        ]
        coverItemID = "fx-1"
        app.createDistrict = "Quận 3"
        app.createLocLabel = "Quận 3, Hồ Chí Minh"
        app.createLat = 10.78; app.createLng = 106.69
        app.createLocConfirmed = true
        reviewOpen = true
    }
    #endif

    var body: some View {
        // Swipe-to-back "blank white space" fix (2026-09-29) — this used
        // to present CreateEventReviewSheet via `.fullScreenCover`, which
        // replaces the ENTIRE window content: nothing from this screen
        // exists behind it to reveal while dragging, only whatever blank
        // color the system shows there. Now an ordinary ZStack overlay
        // instead — CreateEventView's own form (below) stays mounted and
        // live underneath at all times, exactly like web's identical
        // `{reviewOpen && <ReviewStep/>}` sibling-overlay pattern
        // (CreateEvent.jsx) — so dragging the review sheet to the right
        // reveals the REAL, live create-event form underneath, not a
        // placeholder.
        ZStack(alignment: .leading) {
            createFormBody
            if reviewOpen {
                CreateEventReviewSheet(
                    categories: categories,
                    galleryItems: galleryItems,
                    coverItemID: coverItemID,
                    recipe: recipe,
                    onFixRecipe: fixIngredient,
                    dateLabel: {
                        if let date = app.createEventDate, let time = app.createEventTime {
                            return "\(dateLabelFormatter.string(from: date)) ▪︎ \(timeLabelFormatter.string(from: time))"
                        }
                        return app.T("Chưa chọn", "Not set")
                    }(),
                    onBack: { withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false } },
                    onConfirm: {
                        // TASK 3 (event creation validation pass) —
                        // defense-in-depth: this sheet's own fields are
                        // read-only display, but re-check here too rather
                        // than trust nothing changed since Review opened.
                        guard !app.createName.trimmingCharacters(in: .whitespaces).isEmpty,
                              app.createLocConfirmed, !hasCreateFieldErrors else {
                            withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = false }
                            return false
                        }
                        // Keyword-search fix (migration 108) — same
                        // default-to-category-label(s) fallback web's
                        // identical `createCatLabel` provides, computed
                        // here (not duplicated in AppState) since
                        // `categories` already lives on this view.
                        let picked = app.createCats.isEmpty ? ["supper"] : app.createCats
                        let defaultKeywordsLabel = picked.compactMap { key in categories.first(where: { $0.key == key }).map { app.T($0.vi, $0.en) } }.joined(separator: " ▪︎ ")
                        // TASK 3 (event creation validation pass) — only a
                        // REAL RPC-confirmed success opens the post-
                        // submission chooser; a failure leaves Review open
                        // with data intact and app.createError already
                        // showing, never the chooser.
                        let good = EventRecipe.score(recipe).good
                        Analytics.track(.submitRecipeScore(bucket: good >= 9 ? "9-10" : good >= 7 ? "7-8" : good >= 4 ? "4-6" : "0-3"))
                        let ok = await app.submitCreateEvent(
                            newImages: newImagesInOrder, coverNewIndex: coverNewIndex,
                            removeExistingPhotoIDs: removedExistingIDs, existingCoverPath: existingCoverPath,
                            defaultKeywordsLabel: defaultKeywordsLabel, showsLoader: false
                        )
                        if ok, let id = app.createDraftID { app.deleteEventDraft(id) }
                        return ok
                    },
                    // Note 64: present-modal class. The chooser opens once the ✓ ("Sent for review") has drawn.
                    // Review stays under the chooser (closing it first flashed the form again); whichever choice
                    // is made then leaves it in one step.
                    onConfirmed: {
                        successChoiceMade = false
                        successChooserOpen = true
                    }
                )
                .environmentObject(app)
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .onAppear { app.loadEventDrafts() }
        // After "Save draft": what next, in the same card style as "Event submitted!".
        .overlay {
            if draftSavedOpen {
                DraftSavedCard(
                    onExit: {
                        draftSavedOpen = false
                        // Everything is in the draft: leaving needs no Undo toast.
                        app.createDraftStash.hasUnsavedInput = false
                        app.createBack()
                    },
                    onNew: {
                        draftSavedOpen = false
                        galleryItems = []; coverItemID = nil; photoError = ""
                        seededForEventID = nil; seededExistingIDs = []
                        attemptedReview = false
                        currentStep = .host
                        app.goCreate()
                    },
                    onViewDrafts: { draftSavedOpen = false; draftsSheetOpen = true },
                    onDismiss: { draftSavedOpen = false }
                )
                .transition(.identity)
                .zIndex(30)
            }
        }
        .sheet(isPresented: $draftsSheetOpen) {
            EventDraftsSheet(onOpen: openDraft).environmentObject(app)
        }
        .alert(app.T("Đã đủ 5 bản nháp", "You have 5 drafts"), isPresented: $draftFullAlert) {
            Button(app.T("Xem bản nháp", "Manage drafts")) { draftsSheetOpen = true }
            Button(app.T("Đóng", "OK"), role: .cancel) {}
        } message: {
            Text(app.T("Xoá một bản nháp để lưu bản mới.", "Delete one to save another."))
        }
        .onChange(of: reviewOpen) { _, open in app.isCreateReviewOpen = open }
        .onDisappear { app.isCreateReviewOpen = false }
        // Undo after leaving (AppState.createBack): keep AppState's copy of this view's own draft
        // state current, and restore it once when Undo brings the person back.
        .onAppear {
            guard app.createRestorePending else { return }
            app.createRestorePending = false
            let stash = app.createDraftStash
            galleryItems = stash.items
            coverItemID = stash.coverItemID
            currentStep = Section(rawValue: stash.step) ?? .host
        }
        .onChange(of: hasUnsavedInput, initial: true) { _, has in app.createDraftStash.hasUnsavedInput = has }
        .onChange(of: galleryItems) { _, items in app.createDraftStash.items = items }
        .onChange(of: coverItemID) { _, id in app.createDraftStash.coverItemID = id }
        .onChange(of: currentStep) { _, step in app.createDraftStash.step = step.rawValue }
        // TASK 3 (event creation validation pass) — the post-submission chooser. Was a native
        // `.confirmationDialog`, which iOS 26 draws as a narrow popover that wrapped the explanation
        // awkwardly; now a full-width card (SubmittedChooserCard below): what happens next as a short
        // list, one icon per choice, springing in with a bounce.
        .overlay {
            if successChooserOpen {
                SubmittedChooserCard(
                    onCreateAnother: {
                        successChoiceMade = true
                        successChooserOpen = false
                        reviewOpen = false
                        galleryItems = []
                        coverItemID = nil
                        photoError = ""
                        seededForEventID = nil
                        seededExistingIDs = []
                        app.goCreate()
                    },
                    onPending: { successChoiceMade = true; successChooserOpen = false; app.goDashboard() },
                    onHome: { successChoiceMade = true; successChooserOpen = false; app.goHome() },
                    onAccount: { successChoiceMade = true; successChooserOpen = false; app.goProfile() },
                    // Backdrop tap: same "unambiguous success" pending-events default as before.
                    onDismiss: { successChooserOpen = false }
                )
                .transition(.identity)
                .zIndex(30)
            }
        }
        // Swipe-to-dismiss/backdrop-tap on the sheet flips this binding to
        // false WITHOUT any button firing — same "unambiguous success"
        // pending-events default as the explicit Cancel row above.
        .onChange(of: successChooserOpen) { _, open in
            if open { Haptics.success() }
            if !open && !successChoiceMade { app.goDashboard() }
        }
        // Note 53: submitting is the peak of creating an event (peak-end rule) — confetti behind the chooser.
        .overlay(alignment: .top) {
            if successChooserOpen { ConfettiBurst().padding(.top, 220) }
        }
    }

    private var createFormBody: some View {
        ScrollViewReader { proxy in
            createFormScroll
                // Goal gradient (note 48): a sticky, tappable section bar;
                // "Host" is already ticked when an organizer profile exists.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !app.createSent {
                        VStack(spacing: 10) {
                            StepProgress(steps: sectionTitles,
                                         current: currentStep.rawValue,
                                         completed: Section.allCases.map(sectionDone),
                                         message: createProgressMessage,
                                         identifier: "create.progress",
                                         onSelect: { index in
                                             if let section = Section(rawValue: index) { goTo(section) }
                                         })
                            // Note 50: "Recipe 7/10 · See tips" — informational, never blocks a step or submit.
                            // Note 53: on every step, so the bar never changes height and arrives with the page.
                            RecipeMeter(checks: recipe, onOpen: openRecipe)
                        }
                        .padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 10)
                        .background(app.palette.paper)
                    }
                }
                .onAppear {
                    scrollProxy = proxy
                    #if DEBUG
                    openFixtureReviewIfAsked()
                    #endif
                }
                // Note 53: the field being typed in never sits under the keyboard. Once the keyboard has come up,
                // centre the focused field in what's left of the screen.
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guard focusedField == field else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(CreateFieldGuide.anchor(field), anchor: .center) }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $recipeOpen) {
            RecipeSheet(checks: recipe, hasData: bench != nil, n: bench?.n, onFix: fixIngredient,
                        onClose: { recipeOpen = false })
                .environmentObject(app)
        }
        // One get_host_benchmarks per category+city change (debounced while picking, cached per session),
        // best-effort: nil keeps the recipe on general tips, with no numbers.
        .task(id: benchmarkKey) {
            guard app.isSignedIn, !app.createSent else { benchmarks = nil; audienceDemand = nil; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let cat = primaryCat
            benchmarks = await app.hostBenchmarks(cat: cat, city: app.createCity, currency: app.createCurrency)
            audienceDemand = cat.isEmpty ? nil : await app.audienceDemand(cat: cat)
        }
    }

    /// Note 53: one step per function, type-erased. Inlined, all five steps (plus every guided field) were ONE view
    /// value of ~20 KB; in a Debug build SwiftUI's unspecialised generic inits (VStack/TupleView/Group...) each keep
    /// copies of it on the stack, which overflowed the iPhone's 1 MB main-thread stack (EXC_BAD_ACCESS in the stack
    /// guard, device crash logs 2026-10-20; the simulator's larger stack hid it). Measured after erasure: each step
    /// is 0.6-2 KB and the form itself holds only AnyView boxes.
    private var hostStepView: AnyView {
        AnyView(Group {
                group(app.T("Hồ sơ người tổ chức", "Organizer profile")) {
                    // Note 53: Host opens first even when it's already filled in; say so, so it reads as "check
                    // this" rather than "do this again".
                    if sectionDone(.host) {
                        Label(app.T("Đã điền từ hồ sơ người tổ chức của bạn. Kiểm tra lại rồi tiếp tục.",
                                    "Filled from your organizer profile. Check it and continue."),
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5)).opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("create.hostPrefilled")
                    }
                    guided("hostName") {
                        BanbeField(label: app.T("Tên", "Name"), placeholder: "Bếp Nhỏ", text: $app.orgRegName, icon: "person.crop.circle",
                                   focus: $focusedField, focusID: "hostName")
                    }
                    BanbeField(label: "Instagram", placeholder: "@bepnho.saigon", text: $app.orgRegIg, icon: "at",
                               focus: $focusedField, focusID: "hostIg")
                        .id(CreateFieldGuide.anchor("hostIg"))
                    BanbeField(label: app.T("Giới thiệu", "About"),
                               placeholder: app.T("Mình nấu cho người lạ từ 2021…", "I cook for strangers since 2021…"),
                               text: $app.orgRegDesc, icon: "text.quote", focus: $focusedField, focusID: "hostAbout")
                        .id(CreateFieldGuide.anchor("hostAbout"))
                }
        })
    }
    /// Type-erased step (see `hostStepView`).
    private var basicsStepView: AnyView {
        AnyView(Group {
                group(app.T("Cơ bản", "Basics")) {
                    guided("name") {
                        BanbeField(label: app.T("Tên sự kiện", "Event name"),
                                   placeholder: app.T("Tên sự kiện của bạn", "Your event name"), text: $app.createName,
                                   required: true, icon: "sparkles",
                                   state: !nameValid && !app.createSent && attemptedReview ? .error(app.T("Hãy đặt tên cho sự kiện.", "Please give your event a name.")) : .normal,
                                   focus: $focusedField, focusID: "name")
                    }
                    goalPicker()
                    guided("description") {
                        BanbeField(label: app.T("Mô tả", "Description"),
                                   placeholder: app.T("Buổi này có gì?", "What happens?"), text: $app.createDesc,
                                   required: true, icon: "text.alignleft",
                                   state: !descValid && !app.createSent && attemptedReview ? .error(app.T("Hãy nhập mô tả.", "Please enter a description.")) : .normal,
                                   focus: $focusedField, focusID: "description")
                    }
                    guided("intro") { introEditor() }
                    guided("greeting") { greetingEditor() }
                    guided("categories") { VStack(alignment: .leading, spacing: 16) {
                    FormFieldLabel(icon: "square.grid.2x2", text: app.T("Hạng mục", "Categories"), required: true,
                                   trailing: app.T("Tối đa 2", "Up to 2"))
                        .padding(.top, 8)
                    FlowRow(spacing: 8) {
                        ForEach(categories, id: \.key) { category in
                            let active = app.createCats.contains(category.key)
                            Button { app.pickCreateCategory(category.key) } label: {
                                Label(app.T(category.vi, category.en), systemImage: categoryIcon(category.key))
                                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(active ? app.palette.ink : app.palette.paper, in: Capsule())
                                    .overlay(Capsule().stroke(active ? .clear : app.palette.rule, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !catsValid && !app.createSent && attemptedReview {
                        Text(app.T("Hãy chọn ít nhất một danh mục.", "Please pick at least one category."))
                            .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    }
                    } }
                    // Note 50: only when the server answered with a real (floored, ≥10) count.
                    if let demand = audienceDemand, let cat = categories.first(where: { $0.key == primaryCat }) {
                        Text(app.T("\(demand)+ người trên banbe thích \(cat.vi).", "\(demand)+ people on banbe are into \(cat.en)."))
                            .font(.system(size: 12, weight: .semibold)).opacity(0.85)
                            .accessibilityIdentifier("create.audienceDemand")
                    }

                    // Keyword-search fix (migration 108) — so this event
                    // actually surfaces in Map's search box for terms
                    // beyond its literal name/district. Left blank,
                    // submission defaults it to the category label(s)
                    // picked just above (never silently empty).
                    guided("keywords") { VStack(alignment: .leading, spacing: 5) {
                        FormFieldLabel(icon: "magnifyingglass", text: app.T("Từ khoá tìm kiếm", "Search keywords"))
                            .padding(.top, 8)
                        TextField(
                            app.T("vd. tiệc tối, rượu vang, ẩm thực Việt", "e.g. supper club, wine, Vietnamese food"),
                            text: $app.createKeywords
                        )
                        .focused($focusedField, equals: "keywords")
                        .roundedFormField(app: app, focused: focusedField == "keywords")
                        Text(app.T(
                            "Cách nhau bằng dấu phẩy. Để trống sẽ tự dùng danh mục đã chọn ở trên.",
                            "Comma-separated. Left blank, the category picked above is used instead."
                        ))
                        .font(.system(size: 11)).opacity(0.75)
                        keywordSuggestions()
                    }
                    .foregroundStyle(app.palette.ink) }

                    guided("included") { includedItemsEditor() }
                    if let typeProfile, let key = app.createCats.first, !(typeProfile.wizard?.details ?? []).isEmpty {
                        TypeDetailsEditor(profile: typeProfile, typeKey: key)
                    }
                }
        })
    }
    /// Type-erased step (see `hostStepView`).
    private var whenWhereStepView: AnyView {
        AnyView(Group {
                group(app.T("Thời gian & địa điểm", "When & where")) {
                    guided("location") { BanbeField(
                        label: app.T("Địa điểm", "Location"),
                        placeholder: app.T("12 Nguyễn Văn Đậu, hoặc tên địa điểm…", "12 Nguyễn Văn Đậu, or a venue name…"),
                        text: $app.createLoc,
                        required: true,
                        icon: "mappin.and.ellipse",
                        state: !app.createLocConfirmed && !app.createSent && attemptedReview
                            ? .error(app.T("Hãy chọn một địa chỉ gợi ý.", "Pick one of the suggested addresses.")) : .normal,
                        focus: $focusedField, focusID: "location"
                    ) }
                    .onChange(of: app.createLoc) { _, newValue in
                        createAddressSearchTask?.cancel()
                        // A stale confirmation/point for a since-edited
                        // address is worse than none — see
                        // createLocConfirmed's own doc comment.
                        app.createLat = nil
                        app.createLng = nil
                        app.createLocLabel = ""
                        app.createAddressLine = ""
                        app.createDistrict = ""
                        app.createCity = ""
                        app.createPostalCode = ""
                        app.createCountryCode = nil
                        app.createStateProvince = nil
                        app.createNeighborhood = nil
                        app.createPlaceTimeZoneID = nil
                        app.createLocConfirmed = false
                        app.createAddressSuggestions = []
                        app.createAddressSearchError = ""
                        let query = newValue.trimmingCharacters(in: .whitespaces)
                        guard query.count >= 4 else { app.createAddressSearching = false; return }
                        createAddressSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            guard !Task.isCancelled else { return }
                            await app.searchCreateAddress(query)
                        }
                    }
                    Text(app.T(
                        "Gõ số nhà + tên đường (hoặc tên địa điểm nếu không có số nhà) rồi chọn một gợi ý. Cần thiết để đăng sự kiện.",
                        "Type a house number + street (or a venue name if there is no house number), then pick a suggestion. Required to publish."
                    ))
                    .font(.system(size: 11)).opacity(0.75).foregroundStyle(app.palette.ink)
                    locationConfirmSection()
                    guided("date") { dateTimeRow() }
                    timingInsights()
                }
        })
    }
    /// Type-erased step (see `hostStepView`).
    private var ticketsStepView: AnyView {
        AnyView(Group {
                group(app.T("Vé & ai được đặt", "Tickets & who can book")) {
                    ticketsSection()
                    if !seatsValid && !app.createSent && attemptedReview {
                        Text(app.T("Hãy nhập số chỗ lớn hơn 0.", "Please enter a number of seats greater than 0."))
                            .font(.system(size: 11)).foregroundStyle(BanbeTheme.alert)
                    }

                    // Strict invite-only events (migration 113) — a peer of
                    // every other field here, not a separate "advanced"
                    // section: it changes who can even discover the event.
                    // Deliberately separate from approval mode (not exposed
                    // in this form) and admin review — private is not
                    // auto-approved, per set_event_visibility's own comment.
                    VStack(alignment: .leading, spacing: 6) {
                        FormFieldLabel(icon: "lock", text: app.T("Quyền riêng tư", "Privacy")).padding(.top, 12)
                        HStack(spacing: 8) {
                            ForEach([("public", "Công khai", "Public"), ("invite", "Chỉ mời", "Invite-only")], id: \.0) { key, vi, en in
                                let active = app.createVisibility == key
                                Button { app.createVisibility = key } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: key == "public" ? "globe.asia.australia" : "envelope.badge").font(.system(size: 20))
                                        Text(app.T(vi, en)).font(.system(size: 15, weight: active ? .semibold : .regular))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 76)
                                    .background(active ? app.palette.ink : app.palette.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .foregroundStyle(active ? app.palette.paper : app.palette.ink)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? .clear : app.palette.rule))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("create-visibility-\(key)")
                            }
                        }
                        Text(app.createVisibility == "invite"
                             ? app.T("Chỉ người được mời mới thấy và đặt được sự kiện này. Bạn vẫn cần được banbe duyệt.", "Only invited people can see or book this event. It still needs banbe approval.")
                             : app.T("Ai cũng có thể tìm thấy và đặt sự kiện này.", "Anyone can discover and book this event."))
                            .font(.system(size: 11)).opacity(0.6).foregroundStyle(app.palette.ink)
                    }

                    ReservationCriteriaPicker()
                }
        })
    }
    /// Type-erased step (see `hostStepView`).
    private var photosStepView: AnyView {
        AnyView(Group {
                guided("photos") { gallerySection() }
                    .padding(.top, 22)
                    .transition(stepTransition)
        })
    }

    private func draftPill(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(app.palette.field, in: Capsule())
                .overlay(Capsule().stroke(app.palette.rule))
                .foregroundStyle(app.palette.ink)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityIdentifier(id)
    }

    /// Saves the open form as a draft (or updates the one it came from). Photos and the step are this view's own state.
    private func saveDraftTapped() {
        let photos = galleryItems.compactMap(\.image)
        let cover = galleryItems.first { $0.id == coverItemID }?.image
        let coverIndex = cover.flatMap { c in photos.firstIndex { $0 === c } } ?? 0
        if app.saveEventDraft(photos: photos, coverIndex: coverIndex, step: currentStep.rawValue) {
            Haptics.success()
            draftSavedOpen = true
        } else {
            draftFullAlert = true
        }
    }

    private func openDraft(_ d: HostEventDraft) {
        let images = EventDraftStore.photos(of: d)
        app.applyEventDraft(d)
        galleryItems = images.map { StagedGalleryItem(id: UUID().uuidString, kind: .new(image: $0)) }
        coverItemID = galleryItems.indices.contains(d.coverIndex) ? galleryItems[d.coverIndex].id : galleryItems.first?.id
        seededForEventID = nil; seededExistingIDs = []
        currentStep = Section(rawValue: d.step) ?? .host
        draftsSheetOpen = false
    }

    private var createFormScroll: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Stage 1 fix — this used to name a fixed destination,
                // which stopped being true once createBack started
                // returning to the REAL originating tab (see
                // createOriginScreen's own comment) instead of always
                // landing on Dashboard/HostIntro.
                HStack(spacing: 8) {
                    BackLink(label: app.T("Quay lại", "Back")) {
                        // Leaves straight away; with input, Home shows an Undo toast (AppState.createBack),
                        // which replaced the "Discard this event?" question.
                        app.createBack()
                    }
                    Spacer(minLength: 0)
                    if app.createEditEventId == nil {
                        if !app.eventDrafts.isEmpty {
                            draftPill(app.T("Bản nháp (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts))",
                                            "Drafts (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts))"),
                                      icon: "tray.full", id: "create.drafts") { draftsSheetOpen = true }
                        }
                        draftPill(app.T("Lưu nháp", "Save draft"), icon: "square.and.arrow.down", id: "create.saveDraft") { saveDraftTapped() }
                    }
                }

                Text(app.T("Dành cho người tổ chức", "For organizers"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 14)
                Text(app.createEditEventId != nil
                     ? app.T("Chỉnh sửa và gửi lại", "Correct and resubmit")
                     : app.T("Tạo sự kiện, hoàn toàn miễn phí", "Create an event, completely free"))
                    .font(BanbeTheme.display(26))
                    .padding(.top, 8)
                if let editID = app.createEditEventId,
                   let reason = app.myOrgEventSummaries.first(where: { $0.id == editID })?.rejectionReason,
                   !reason.isEmpty {
                    Text(app.T("Bị từ chối: ", "Rejected: ") + reason)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(10)
                        .background(BanbeTheme.alert.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.top, 10)
                }

                if currentStep == .whenWhere || currentStep == .tickets { defaultsNotice() }

                stepNavHeader()

                if currentStep == .host { hostStepView.transition(stepTransition) }
                if currentStep == .basics { basicsStepView.transition(stepTransition) }
                if currentStep == .whenWhere { whenWhereStepView.transition(stepTransition) }
                if currentStep == .tickets { ticketsStepView.transition(stepTransition) }
                if currentStep == .photos { photosStepView.transition(stepTransition) }

                if currentStep != .photos {
                    stepNavFooter()
                }

                // TASK 3 (event creation validation pass) — the "Download
                // the Excel template" entry (a `ShareLink` to the bundled
                // .xlsx, generated by scripts/generate-template.js) is
                // removed per this ticket's own instruction. iOS never had
                // an upload/parse side to this feature at all (see this
                // block's own prior doc comment: no ZIP/XML capability),
                // so there is no "unrelated import functionality" left
                // here to preserve — the whole feature is gone on iOS,
                // matching what actually remains once the entry point is
                // removed (web keeps its own upload/parse path, unaffected).

                // No SLA is actually monitored server-side — the previous
                // "duyệt sự kiện đầu tiên trong 48 giờ"/"reviews your first
                // event within 48 hours" copy promised a turnaround time
                // nothing enforced. Accurate instead of reassuring.
                // "Review before submitting" step (task 1) — this button now
                // only OPENS the review sheet; only that sheet's own
                // "Xác nhận và gửi" ever actually calls submitCreateEvent.
                if currentStep == .photos || app.createSent {
                if !app.createSent {
                    Button { goTo(.tickets) } label: {
                        Label(app.T("Quay lại: Vé", "Back: Tickets"), systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .accessibilityIdentifier("create.step.back")
                }
                InkButton(title: app.createSent
                          ? app.T("Đã gửi, đang chờ Banbe duyệt", "Submitted, waiting for Banbe to review")
                          : app.T("Xem lại sự kiện của bạn", "Review your event"),
                          enabled: !app.createSent && !app.loading,
                          cornerRadius: 999) {
                    // Note 48: tapping with gaps reveals what's missing and
                    // scrolls to it, instead of a silent disabled button.
                    guard canOpenReview else {
                        attemptedReview = true
                        // Note 53: land on the first missing FIELD (glowing, focused), not just its step.
                        if let field = progress.firstMissing {
                            guideTo(field, hint: app.T("Còn thiếu: ", "Still needed: ") + missingLabel(field))
                        } else if let first = firstIncompleteSection { goTo(first) }
                        return
                    }
                    // Keyboard-stays-up fix (2026-09-29) — opening the review
                    // used to rely on `.fullScreenCover` implicitly resigning
                    // first responder (a new modal context takes it away for
                    // free); now that it's a plain overlay in the SAME view
                    // hierarchy (see `body`'s own doc comment), nothing does
                    // that automatically, so any focused text field stayed
                    // focused — and the keyboard visible — underneath it.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.easeInOut(duration: 0.25)) { reviewOpen = true }
                }
                .padding(.top, 26)

                if !progress.missing.isEmpty, !app.createSent {
                    MissingChips(lead: app.T("Còn thiếu:", "Still needed:"), fields: progress.missing, label: missingLabel,
                                 goToPrefix: app.T("Đi tới: ", "Go to: "), alertTone: attemptedReview, onPick: goToMissing)
                        .padding(.top, 8)
                        .accessibilityIdentifier("create.missingSummary")
                }
                }

                if !app.createError.isEmpty {
                    Text(app.createError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
                if !app.createMediaError.isEmpty {
                    Text(app.createMediaError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 12)
                }
                Text(app.T("Hoàn toàn miễn phí: không phí đăng, không phí giao dịch, không phí ẩn.", "Completely free: no listing fee, no transaction fee, no hidden fees."))
                    .font(.system(size: 11)).multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .task(id: app.createEditEventId) {
            guard let editID = app.createEditEventId else { seedGalleryIfNeeded(); return }
            await app.loadEventPhotos(eventID: editID)
        }
        .onChange(of: app.eventPhotos) { _, _ in seedGalleryIfNeeded() }
        .onAppear { seedGalleryIfNeeded(); stageSeedCoverIfNeeded() }
        .onChange(of: app.createSeedCoverImage) { _, _ in stageSeedCoverIfNeeded() }
    }

    /// L3 "Run it again" (AppState.runItAgain): the original event's cover becomes this new draft's first photo, as an
    /// ordinary staged photo the host can remove or replace. Used once, and only on an empty new draft.
    private func stageSeedCoverIfNeeded() {
        guard let image = app.createSeedCoverImage else { return }
        app.createSeedCoverImage = nil
        guard app.createEditEventId == nil, galleryItems.isEmpty else { return }
        let item = StagedGalleryItem(id: UUID().uuidString, kind: .new(image: image.normalizedUp()), url: nil)
        galleryItems = [item]
        coverItemID = item.id
    }

    private func categoryIcon(_ key: String) -> String {
        switch key {
        case "supper": return "fork.knife"
        case "fashion": return "tshirt"
        case "gallery": return "photo.artframe"
        case "music": return "music.note"
        case "popup": return "storefront"
        default: return "sparkles"
        }
    }

    /// Encouraging line for the step bar, by how many steps are done.
    private var createProgressMessage: String {
        let done = progress.doneCount
        let left = progress.stepsLeft
        switch done {
        case 0: return app.T("Bắt đầu thôi! ✨", "Let's get started! ✨")
        case Section.allCases.count: return app.T("Xong hết rồi, xem lại nhé! 🎉", "All set, time to review! 🎉")
        default: return left == 1 ? app.T("Sắp xong rồi, còn 1 bước 🔥", "Almost there, 1 step left 🔥")
                                   : app.T("Bạn đang làm rất tốt, còn \(left) bước 🔥", "You're doing great, \(left) steps left 🔥")
        }
    }

    private func goTo(_ section: Section) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        stepForward = section.rawValue >= currentStep.rawValue
        withAnimation(.easeInOut(duration: 0.22)) { currentStep = section }
        DispatchQueue.main.async { scrollProxy?.scrollTo("create.top", anchor: .top) }
    }

    /// Top-of-page anchor for step changes.
    private func stepNavHeader() -> some View {
        Color.clear.frame(height: 0).id("create.top")
    }

    /// What's still missing on THIS step (shown above Next; never blocks it).
    private var currentStepGaps: [String] { progress.steps[currentStep.rawValue].missing }

    /// Back / Next under each step. Next is never blocked: hosts can fill in
    /// any order and come back (finished steps show a check in the bar).
    private func stepNavFooter() -> some View {
        let next = Section(rawValue: currentStep.rawValue + 1)
        let prev = Section(rawValue: currentStep.rawValue - 1)
        return VStack(spacing: 10) {
            if !currentStepGaps.isEmpty {
                MissingChips(lead: app.T("Còn thiếu ở bước này:", "Still needed here:"), fields: currentStepGaps, label: missingLabel,
                             goToPrefix: app.T("Đi tới: ", "Go to: "), alertTone: false, onPick: goToMissing)
                    .accessibilityIdentifier("create.step.gaps")
            }
            HStack(spacing: 10) {
                if let prev {
                    Button { goTo(prev) } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 54, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 999).stroke(app.palette.rule, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Quay lại: ", "Back: ") + sectionTitles[prev.rawValue])
                    .accessibilityIdentifier("create.step.back")
                }
                if let next {
                    InkButton(title: currentStep == .host && sectionDone(.host)
                              ? app.T("Ổn rồi · Tiếp: ", "Looks good · Next: ") + sectionTitles[next.rawValue]
                              : app.T("Tiếp: ", "Next: ") + sectionTitles[next.rawValue], cornerRadius: 999) {
                        goTo(next)
                    }
                    .accessibilityIdentifier("create.step.next")
                }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 24)
    }

    /// Note 48: what was pre-filled, and a one-tap way out of it.
    @ViewBuilder
    private func defaultsNotice() -> some View {
        if app.createEditEventId == nil, !app.createSent, app.createAppliedDefaults != nil {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.createDefaultsSource.map {
                        app.T("Đã điền sẵn thời gian và giá từ \"\($0)\". Đổi bất cứ gì bạn muốn.",
                              "Time and price are pre-filled from \"\($0)\". Change anything you like.")
                    } ?? app.T("Đã chọn sẵn Thứ Bảy tới lúc 19:00. Đổi bất cứ lúc nào bạn muốn.",
                               "We picked next Saturday at 19:00. Change it any time."))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(app.T("Bắt đầu trống", "Start blank")) {
                        withAnimation { app.clearCreateDefaults() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                    .underline()
                    .accessibilityIdentifier("create.startBlank")
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(app.palette.ink)
            .padding(12)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("create.defaultsNotice")
        }
    }

    private var seatsBinding: Int { Int(app.createSeats.filter(\.isNumber)) ?? 0 }
    /// The typed price in minor units of `app.createCurrency` (nil when it isn't a price, e.g. "12.345" in USD).
    private var priceDigits: Int? {
        app.createPrice.trimmingCharacters(in: .whitespaces).isEmpty ? nil : app.createPriceAmount
    }
    private var currency: String { app.createCurrency }
    /// What a quick pick / the slider writes into the price field (VND keeps its plain digits, USD "12.50").
    private func priceText(_ v: Int) -> String {
        currency == "USD" ? EventMarket.priceInputText(v, currency: "USD") : String(v)
    }

    /// Contrast hint (note 48, honest anchoring): prices of similar live
    /// events in the same category AND currency, never shown with too few samples.
    private var similarPriceHint: String? {
        let cats = Set(app.createCats)
        guard !cats.isEmpty else { return nil }
        let prices = app.discoveryEvents.filter { cats.contains($0.catKey) && $0.currency == currency }.map(\.priceVnd)
        guard let range = SmartDefaults.similarPriceRange(prices) else { return nil }
        let lo = EventMarket.formatMoney(range.lowerBound, currency: currency), hi = EventMarket.formatMoney(range.upperBound, currency: currency)
        return app.T("Sự kiện tương tự: \(lo)–\(hi)", "Similar events: \(lo)–\(hi)")
    }

    /// Benchmarks first ("Typical: 280k₫–380k₫ (13 similar events)"), then the loaded-events hint, then free.
    private var priceHint: String {
        if let p = bench?.price, p.p25 != nil {
            let band = "\(EventRecipe.formatMoneyShort(p.p25, currency: currency))–\(EventRecipe.formatMoneyShort(p.p75, currency: currency))"
            return app.T("Thường gặp: \(band) (\(p.n ?? 0) sự kiện tương tự). Để trống là miễn phí.",
                         "Typical: \(band) (\(p.n ?? 0) similar events). Leave empty for a free event.")
        }
        return similarPriceHint ?? app.T("Để trống là miễn phí.", "Leave empty for a free event.")
    }

    /// A big, bordered quick-pick tile (the video's 6:00 / 6:30 / 7:00 buttons). `sub` = that option's
    /// outcome before it's chosen (note 50).
    private func pickTile(_ title: String, sub: String? = nil, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let sub {
                    Text(sub).font(.system(size: 10.5, weight: .medium)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .background(selected ? app.palette.ink : app.palette.paper,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(app.palette.rule, lineWidth: selected ? 0 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(id)
    }

    /// Optional per-event goal (note 50). Weights the recipe; stored host-only (migration 186), never shown to guests.
    private func goalPicker() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FormFieldLabel(icon: "target", text: app.T("Điều quan trọng nhất với sự kiện này?", "What matters most for this event?"),
                           trailing: app.T("Tuỳ chọn", "Optional"))
            FlowRow(spacing: 8) {
                ForEach(EventRecipe.hostGoals, id: \.self) { goal in
                    let label = EventRecipe.goalLabels[goal] ?? (goal, goal)
                    ChoiceChip(title: app.T(label.vi, label.en), selected: app.createHostGoal == goal,
                               identifier: "create.goal.\(goal)") {
                        app.createHostGoal = app.createHostGoal == goal ? nil : goal
                    }
                }
            }
            Text(app.T("Chỉ bạn thấy. Giúp banbe đưa gợi ý phù hợp hơn.", "Only you see this. It tunes the tips below to what you want."))
                .font(.system(size: 11)).opacity(0.75)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.goal")
    }

    /// Keywords other hosts in this slice actually use (only from benchmarks; none on a cold start).
    @ViewBuilder
    private func keywordSuggestions() -> some View {
        // With event types on: the type's own seeds + the area + what other hosts use (also on a cold start),
        // each dismissible. Off: only what other hosts use, as before.
        let benchmark = recipeCheck("keywords")?.suggestions ?? []
        let ideas = app.eventTypesEnabled
            ? EventTypes.keywordSuggestions(typeProfile ?? .generic(""), lang: langCode,
                                            area: app.createNeighborhood ?? app.createDistrict, benchmark: benchmark,
                                            typed: draftKeywords, dismissed: app.createKwDismissed)
            : benchmark
        if !ideas.isEmpty {
            FlowRow(spacing: 6) {
                Text(app.eventTypesEnabled ? app.T("Gợi ý:", "Ideas:") : app.T("Host khác hay dùng:", "Other hosts use:"))
                    .font(.system(size: 11)).opacity(0.75)
                    .frame(minHeight: 32)
                ForEach(ideas, id: \.self) { word in
                    HStack(spacing: 0) {
                        Button {
                            Haptics.selection()
                            app.createKeywords = (draftKeywords + [word]).joined(separator: ", ")
                        } label: {
                            Text("+ \(word)").font(.system(size: 12.5))
                                .padding(.leading, 10).padding(.trailing, app.eventTypesEnabled ? 4 : 10).frame(minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.T("Thêm từ khoá \(word)", "Add keyword \(word)"))
                        if app.eventTypesEnabled {
                            Button { app.createKwDismissed.append(word) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).opacity(0.5)
                                    .frame(width: 32, height: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(app.T("Bỏ gợi ý \(word)", "Dismiss \(word)"))
                        }
                    }
                    .overlay(Capsule().strokeBorder(app.palette.rule, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("create.keywordSuggestions")
        }
    }

    /// Day/time: this slot's fill when the benchmark cell exists, else the general tip; lead time only when
    /// it's short. At most one line each, details behind "Why?".
    @ViewBuilder
    private func timingInsights() -> some View {
        if let timing = recipeCheck("timing"), timing.status != .missing {
            RecipeInsight(check: timing, line: timing.source == .data ? {
                let label = EventRecipe.slotLabel(dow: timing.dow ?? 0, slot: timing.slot ?? "", app.T)
                return app.T("\(label) thường kín \(EventRecipe.pct(timing.ownFill)).", "\(label) usually fills \(EventRecipe.pct(timing.ownFill)).")
            }() : nil, identifier: "create.timingInsight")
        }
        if let lead = recipeCheck("lead"), lead.status == .improve {
            let days = max(lead.days ?? 0, 0)
            RecipeInsight(check: lead, line: app.T("Còn \(days) ngày. Sự kiện kín chỗ thường đăng trước ~\(lead.target ?? 0) ngày.",
                                                   "\(days) days to go. Events that fill are usually posted ~\(lead.target ?? 0) days ahead."),
                          identifier: "create.leadInsight")
        }
    }

    /// "~10 guests · ~3M₫ if it fills like similar events" — never an invented rate: without data it's the
    /// honest full-house figure. Always "before any fees".
    @ViewBuilder
    private func outcomeLine() -> some View {
        if let o = EventRecipe.estimateOutcome(priceVnd: draftPriceVnd, seats: seatsBinding, medianFill: bench?.fill?.medianFill) {
            let money = draftPriceVnd > 0 ? " · " + (o.basis == "similar" ? "~" : "") + EventRecipe.formatMoneyShort(o.revenueVnd, currency: currency) : ""
            let head = o.basis == "similar" ? app.T("~\(o.guests) khách", "~\(o.guests) guests") + money
                                             : app.T("\(o.guests) khách", "\(o.guests) guests") + money
            let basis = o.basis == "similar"
                ? app.T("nếu kín như sự kiện tương tự (~\(EventRecipe.pct(o.fill)))", "if it fills like similar events (~\(EventRecipe.pct(o.fill)))")
                : app.T("nếu bán hết chỗ", "if every seat sells")
            let tail = draftPriceVnd > 0 ? app.T(", trước mọi khoản phí.", ", before any fees.") : "."
            (Text(head).bold() + Text(" " + basis + tail).foregroundColor(app.palette.ink.opacity(0.7)))
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
                .accessibilityIdentifier("create.outcome")
                .accessibilityValue(o.basis)
        }
    }

    /// Price as quick picks + free entry; seats as a stepper with quick picks.
    @ViewBuilder
    private func ticketsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FormFieldLabel(icon: "tag", text: app.T("Giá vé", "Price"),
                           trailing: similarPriceHint == nil ? nil : app.T("Gợi ý", "Suggested"))
            if let market = bench?.price {
                PriceMarketView(price: market, mine: draftPriceVnd, catLabel: createCatLabel, currency: currency) { app.createPrice = priceText($0) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(EventMarket.priceQuickPicks(currency: currency), id: \.self) { value in
                    // The option's outcome BEFORE it's chosen ("typical", "premium"), like a filter pill's count.
                    let pos = value > 0 ? EventRecipe.pricePosition(value, bench?.price).flatMap { bench?.price == nil ? nil : EventRecipe.positionLabels[$0] } : nil
                    pickTile(value == 0 ? app.T("Miễn phí", "Free") : EventMarket.formatMoney(value, currency: currency),
                             sub: pos.map { app.T($0.vi, $0.en) },
                             selected: !app.createPrice.isEmpty && priceDigits == value,
                             id: "create.price.\(value)") { app.createPrice = priceText(value) }
                }
            }
            guided("price") {
                // USD takes cents ("12.50"), so the keypad needs a decimal point there (migration 195).
                BanbeField(label: nil,
                           placeholder: currency == "USD" ? app.T("Giá khác (USD), vd. 12.50", "Other price (USD), e.g. 12.50")
                                                          : app.T("Giá khác, vd. 450.000", "Other price, e.g. 450,000"),
                           text: $app.createPrice, keyboard: currency == "USD" ? .decimalPad : .numberPad, icon: "tag",
                           focus: $focusedField, focusID: "price")
                    .accessibilityLabel(app.T("Giá vé", "Price"))
            }
            Text(priceHint)
                .font(.system(size: 12)).opacity(0.7)
                .accessibilityIdentifier("create.priceHint")

            FormFieldLabel(icon: "person.2", text: app.T("Số chỗ", "Seats"), required: true)
                .padding(.top, 12)
            guided("seats") { HStack {
                CountStepper(value: max(seatsBinding, 0), range: 0...SmartDefaults.seatRange.upperBound,
                             unit: app.T("chỗ", "seats"), identifier: "create.seatsStepper") { newValue in
                    app.createSeats = newValue == 0 ? "" : String(newValue)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach([10, 20, 30, 50], id: \.self) { n in
                    pickTile("\(n)", selected: seatsBinding == n, id: "create.seats.\(n)") { app.createSeats = String(n) }
                }
            }
            RecipeInsight(check: recipeCheck("seats"), line: recipeCheck("seats")?.typicalGuests.map {
                app.T("Sự kiện tương tự thường đón ~\(EventRecipe.num($0)) khách.", "Similar events usually welcome ~\(EventRecipe.num($0)) guests.")
            }, identifier: "create.seatsInsight")
            outcomeLine()
        }
        .foregroundStyle(app.palette.ink)
        .id(Section.tickets.anchor)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(.title3, design: .rounded).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(18)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 22)
        .transition(stepTransition)
    }
}

/// "Review before submitting" step (task 1) — TWO tabs (2026-09-29
/// follow-up, matching web's identical CreateEvent.jsx `ReviewStep`
/// change): "Nội bộ" (private/host) shows EXACTLY the fields that will be
/// sent (title, gallery order + cover marker, description/intro, full
/// resolved address, date/time, capacity, price, category, included
/// items) — the original content of this screen; "Xem trước công khai"
/// (public preview) renders the SAME draft data shaped the way a normal
/// viewer would see it on the real Event Detail page (`EventDetailView`)
/// once approved — same "district ▪︎ live km ▪︎ long date ▪︎ time"
/// where-line format (via the shared `app.stripKm`/`app.trStatus`), same
/// price-or-"Miễn phí" rule, same cover/gallery. Both tabs share one
/// back/confirm footer; only the explicit "Xác nhận và gửi" tap (available
/// from either tab) calls `submitCreateEvent`. A `.fullScreenCover`, not a
/// second screen in the nav stack — there is no back-stack state to
/// reconcile.
private struct CreateEventReviewSheet: View {
    @EnvironmentObject var app: AppState
    let categories: [(key: String, vi: String, en: String)]
    let galleryItems: [StagedGalleryItem]
    let coverItemID: String?
    /// Note 50 — the full recipe checklist above Submit; informational, never blocking.
    let recipe: [EventRecipe.Check]
    let onFixRecipe: (EventRecipe.Check) -> Void
    let dateLabel: String
    // Swipe-to-back "blank white space" fix (2026-09-29) — this sheet is no
    // longer a `.fullScreenCover` (see `CreateEventView.body`'s own doc
    // comment), so there's no system presentation left to call
    // `@Environment(\.dismiss)` on; the parent instead owns `reviewOpen`
    // and hands down this closure, exactly like web's `ReviewStep(onBack)`.
    let onBack: () -> Void
    /// True only when the RPC really accepted the event.
    let onConfirm: () async -> Bool
    var onConfirmed: () -> Void = {}
    private enum Tab { case privateTab, publicTab }
    @State private var tab: Tab = .privateTab
    // `swipeAxisLocked` is decided once per gesture, the first time its
    // translation is unambiguous either way, and never re-decided mid-
    // gesture — a genuine up/down swipe is locked out entirely (offset
    // stays exactly 0, no diagonal drift) rather than only mostly ignored,
    // which is what "steady" means here: one axis moves, or none does.
    @State private var swipeBackOffset: CGFloat = 0
    @State private var swipeAxisLocked: Bool?
    // Vertical-scroll lock fix (2026-09-29 follow-up) — once a drag is
    // confirmed horizontal, the ScrollView below is disabled for the rest
    // of that gesture, so moving a finger up/down mid-swipe can no longer
    // also scroll the content underneath at the same time (the two
    // gestures fighting each other was the reported "issues").
    @State private var scrollLockedForSwipe = false

    private var categoryLabel: String {
        let picked = app.createCats.isEmpty ? ["supper"] : app.createCats
        return picked.compactMap { key in categories.first(where: { $0.key == key }).map { app.T($0.vi, $0.en) } }.joined(separator: " ▪︎ ")
    }
    private var addressLabel: String {
        if !app.createLocLabel.isEmpty { return app.createLocLabel }
        let parts = [app.createAddressLine, app.createDistrict, app.createCity].filter { !$0.isEmpty }
        return parts.isEmpty ? app.T("Chưa xác nhận địa chỉ", "Address not confirmed") : parts.joined(separator: ", ")
    }
    // "Bao gồm" review parity fix (2026-09-29) — CreateEventView now has a
    // real editing UI for this (`includedItemsEditor()`), so the review
    // step shows exactly what was entered, same trimmed/non-empty-label
    // filter `submitCreateEvent`'s own validation applies.
    private var reviewIncludedItems: [IncludedItem] {
        app.createIncludedItems
            .map { IncludedItem(label: $0.label.trimmingCharacters(in: .whitespaces), detail: $0.detail.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.label.isEmpty }
    }

    private var publicPriceVnd: Int { app.createPriceAmount ?? 0 }
    // The real instant at the venue; `fromDraft` formats it in the event's own zone (migration 195), so the
    // preview shows the wall-clock digits the host picked regardless of the device's zone.
    private var mergedStartsAt: Date? { app.createStartsAt }
    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).opacity(0.6)
            Text(value).font(.system(size: 13.5)).lineLimit(nil)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider().overlay(app.palette.rule) }
    }

    /// The draft as the real Event Detail renders it (Public preview).
    private var draftEvent: CatalogEvent {
        let catKey = app.createCats.first ?? "supper"
        let name = app.createName.trimmingCharacters(in: .whitespaces)
        return CatalogEvent.fromDraft(EventDraft(
            name: name.isEmpty ? app.T("(Chưa đặt tên)", "(Untitled)") : name,
            catKey: catKey,
            catLabel: categories.first(where: { $0.key == catKey })?.vi ?? "",
            area: app.createDistrict,
            lat: app.createLat, lng: app.createLng,
            startsAt: mergedStartsAt,
            priceVnd: publicPriceVnd,
            seats: Int(app.createSeats.filter(\.isNumber)),
            description: app.createDesc.trimmingCharacters(in: .whitespacesAndNewlines),
            intro: app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines),
            includedItems: reviewIncludedItems,
            inviteOnly: app.createVisibility == "invite",
            organizerName: app.orgRegName.trimmingCharacters(in: .whitespaces),
            currency: app.createCurrency,
            timeZoneID: app.createEventTimeZoneID,
            details: reviewTypeDetails
        ))
    }

    // Event type facts exactly as guests will see them, and the answers kept for another type that will NOT be
    // published (switching the category never throws them away silently).
    private var reviewPrimaryType: String { app.createCats.first ?? "supper" }
    private var reviewTypeDetails: EventDetails {
        guard app.eventTypesEnabled else { return [:] }
        return EventTypes.clean(EventTypes.profile(reviewPrimaryType), app.createDetails[reviewPrimaryType] ?? [:])
    }
    private var reviewTypeFacts: [EventTypes.Fact] {
        guard app.eventTypesEnabled else { return [] }
        return EventTypes.detailFacts(EventTypes.profile(reviewPrimaryType), reviewTypeDetails, lang: app.isEN ? "en" : "vi")
    }
    private var reviewDroppedTypes: [String] {
        app.eventTypesEnabled ? EventTypes.droppedDetailTypes(primary: reviewPrimaryType, draft: app.createDetails) : []
    }
    private func typeName(_ key: String) -> String {
        categories.first { $0.key == key }.map { app.T($0.vi, $0.en) } ?? key
    }

    /// Cover first, then the rest — the hero, then the photo strip.
    private var previewPhotos: [EventDetailPreview.Photo] {
        let cover = galleryItems.first(where: { $0.id == coverItemID }) ?? galleryItems.first
        let ordered = (cover.map { [$0] } ?? []) + galleryItems.filter { $0.id != cover?.id }
        return ordered.compactMap { item in
            if let image = item.image { return .local(id: item.id, image: image) }
            if let url = item.url { return .remote(id: item.id, url: url.absoluteString) }
            return nil
        }
    }

    /// Confirm & submit (+ any submit error). AsyncSuccessButton refuses a second tap while pending, on top of
    /// `AppState.submitCreateEventInFlight`'s own synchronous guard. Note 64: the ✓ says "Sent for review", never
    /// "live": banbe still has to approve the event.
    private var confirmBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncSuccessButton(
                title: app.createSent
                    ? app.T("Đã gửi, đang chờ Banbe duyệt", "Submitted, waiting for Banbe to review")
                    : app.T("Xác nhận và gửi", "Confirm & submit"),
                enabled: !app.createSent,
                pendingLabel: app.T("Đang gửi…", "Submitting…"),
                successLabel: app.T("Đã gửi để duyệt", "Sent for review"),
                identifier: "create.review.confirm",
                run: { await onConfirm() ? .success : .failure(app.createError) },
                onSuccessAnimationComplete: onConfirmed
            )

            if !app.createError.isEmpty {
                Text(app.createError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
            }
        }
    }

    /// Small section heading for the Private tab (event name / recipe / details / included / photos).
    private func reviewHeading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.6)
            .opacity(0.6)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func tabButton(_ target: Tab, _ label: String) -> some View {
        Button { tab = target } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tab == target ? app.palette.ink : Color.clear, in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .foregroundStyle(tab == target ? app.palette.paper : app.palette.ink)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        // Real-device follow-up — this outer ZStack (added so Included/
        // Organizer/photo-viewer overlays could sit above the main
        // content) has NO explicit size of its own; without it, a ZStack
        // sizes itself to the UNION of its children and centers each one
        // within that — since organizerPreviewScreen's OWN inner content
        // doesn't force full width the same way the main VStack below
        // does, the whole thing could resolve narrower than the screen
        // and get center-placed instead of pinned left, reading as
        // "shifted right" (the real-device report). An explicit
        // full-bleed frame removes the ambiguity entirely.
        ZStack {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại chỉnh sửa", "Back to edit")) { onBack() }
                    .padding(.top, 16)

                Text(app.T("Xem lại trước khi gửi", "Review before submitting"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 14)

                HStack(spacing: 6) {
                    tabButton(.privateTab, app.T("Nội bộ (Host)", "Private (Host)"))
                    tabButton(.publicTab, app.T("Xem trước công khai", "Public preview"))
                }
                .padding(3)
                .background(app.palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 999, style: .continuous))
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 22)
            .foregroundStyle(app.palette.ink)
            // The scrolling content starts below this line, never right against the tabs (owner, 2026-10-21).
            Rectangle().fill(app.palette.rule).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if tab == .privateTab {
                        // Each block gets its own small heading, so the event name, the recipe and the details
                        // read as separate sections instead of one run of text.
                        reviewHeading(app.T("Tên sự kiện", "Event name"))
                        Text(app.createName.trimmingCharacters(in: .whitespaces).isEmpty ? app.T("(Chưa đặt tên)", "(Untitled)") : app.createName)
                            .font(BanbeTheme.display(24))
                            .padding(.top, 6)
                            .accessibilityIdentifier("create.reviewName")

                        if !recipe.isEmpty {
                            let score = EventRecipe.score(recipe)
                            reviewHeading(app.T("Công thức thành công", "Recipe for success")).padding(.top, 26)
                            VStack(alignment: .leading, spacing: 0) {
                                (Text("\(score.good)/\(score.total)").bold()
                                 + Text(" · " + app.T("không bắt buộc để gửi", "never required to submit")).foregroundColor(app.palette.ink.opacity(0.65)))
                                    .font(.system(size: 12.5))
                                    .padding(.top, 12)
                                RecipeList(checks: recipe, compact: true, onFix: onFixRecipe)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 8)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("create.reviewRecipe")
                        }

                        reviewHeading(app.T("Chi tiết sự kiện", "Event details")).padding(.top, 26)
                        VStack(alignment: .leading, spacing: 0) {
                            row(app.T("Danh mục", "Category"), categoryLabel)
                            row(app.T("Ngày & giờ", "Date & time"), dateLabel)
                            row(app.T("Địa chỉ", "Address"), addressLabel)
                            row(app.T("Số chỗ", "Capacity"), app.createSeats.isEmpty ? app.T("Chưa nhập", "Not set") : app.createSeats)
                            row(app.T("Giá vé", "Price"), (app.createPriceAmount ?? 0) > 0
                                ? EventMarket.formatMoney(app.createPriceAmount ?? 0, currency: app.createCurrency)
                                : (app.createPrice.isEmpty ? app.T("Miễn phí", "Free") : app.createPrice))
                            row(app.T("Quyền riêng tư", "Privacy"), app.createVisibility == "invite" ? app.T("Chỉ mời", "Invite-only") : app.T("Công khai", "Public"))
                            if !app.createDesc.trimmingCharacters(in: .whitespaces).isEmpty {
                                row(app.T("Mô tả", "Description"), app.createDesc.trimmingCharacters(in: .whitespaces))
                            }
                            if !app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                row(app.T("Giới thiệu sự kiện", "Event introduction"), app.createIntro.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            ForEach(reviewTypeFacts, id: \.id) { f in row(f.label, f.value) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 8)
                        .accessibilityIdentifier("create.reviewDetails")
                        if !reviewDroppedTypes.isEmpty {
                            let names = reviewDroppedTypes.map(typeName).joined(separator: ", ")
                            Text(app.T("Thông tin bạn đã nhập cho \(names) sẽ không được đăng, vì loại chính là \(typeName(reviewPrimaryType)). Chúng vẫn được giữ trong bản nháp nếu bạn đổi lại.",
                                       "What you entered for \(names) won't be published, since the main type is \(typeName(reviewPrimaryType)). It stays in this draft if you switch back."))
                                .font(.footnote)
                                .foregroundStyle(app.palette.honey)
                                .padding(.top, 10).padding(.horizontal, 2)
                                .accessibilityIdentifier("create.reviewDroppedDetails")
                        }

                        if !reviewIncludedItems.isEmpty {
                            reviewHeading(app.T("Bao gồm", "Included")).padding(.top, 26)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(reviewIncludedItems.enumerated()), id: \.offset) { index, item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.label).font(.system(size: 13.5, weight: .semibold))
                                        if !item.detail.isEmpty {
                                            Text(item.detail).font(.system(size: 12.5)).opacity(0.8)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .bottom) {
                                        if index < reviewIncludedItems.count - 1 { Divider().overlay(app.palette.rule) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.top, 8)
                        }

                        if !galleryItems.isEmpty {
                            reviewHeading(app.T("Thứ tự ảnh", "Photo order")).padding(.top, 26)
                            VStack(spacing: 8) {
                                ForEach(Array(galleryItems.enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 10) {
                                        Group {
                                            if let image = item.image {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                AsyncImage(url: item.url) { $0.resizable().scaledToFill() } placeholder: { app.palette.field }
                                            }
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        Text(item.id == coverItemID ? app.T("Ảnh bìa", "Cover photo") : app.T("Ảnh \(index + 1)", "Photo \(index + 1)"))
                                            .font(.system(size: 12.5))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(8)
                                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .scrollDisabled(scrollLockedForSwipe)

            // Confirm — the ONLY call site that actually submits, available
            // from either tab (the Public preview shows the same block).
            confirmBlock
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                .padding(.top, 10)
        }
        .background(app.palette.paper.ignoresSafeArea())
        .offset(x: swipeBackOffset)
        // `.simultaneousGesture` so the ScrollView above can still start a
        // vertical scroll on an ambiguous/actually-vertical drag — once
        // THIS gesture locks onto horizontal, `scrollLockedForSwipe`
        // disables that ScrollView outright for the rest of the gesture,
        // so a wobble up/down mid-swipe can no longer also scroll the
        // content underneath at the same time.
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .onChanged { value in
                    if swipeAxisLocked == nil {
                        swipeAxisLocked = abs(value.translation.width) > abs(value.translation.height)
                        if swipeAxisLocked == true { scrollLockedForSwipe = true }
                    }
                    guard swipeAxisLocked == true else { return }
                    swipeBackOffset = max(0, value.translation.width)
                }
                .onEnded { value in
                    let wasHorizontal = swipeAxisLocked == true
                    swipeAxisLocked = nil
                    scrollLockedForSwipe = false
                    guard wasHorizontal else { return }
                    if swipeBackOffset > 110 || value.predictedEndTranslation.width > 280 {
                        // Hand off to the parent's own `.move(edge: .trailing)`
                        // removal transition (identical motion to a plain
                        // BackLink tap) rather than compositing that
                        // transition's animated offset on top of whatever
                        // manual `swipeBackOffset` the drag left behind.
                        swipeBackOffset = 0
                        onBack()
                    } else {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.86)) { swipeBackOffset = 0 }
                    }
                }
        )

        // Public preview (owner, 2026-10-21): the REAL Event Detail, rendered from this draft in preview mode, so the
        // host sees the page guests will see (not a hand-built look-alike). Its back pill returns to the Private tab;
        // Confirm & submit sits under its inert reserve bar.
        if tab == .publicTab {
            EventDetailView(preview: EventDetailPreview(
                event: draftEvent,
                photos: previewPhotos,
                capacity: Int(app.createSeats.filter(\.isNumber)),
                backLabel: app.T("Nội bộ (Host)", "Private (Host)"),
                onBack: { withAnimation(.easeInOut(duration: 0.2)) { tab = .privateTab } },
                footer: AnyView(
                    VStack(spacing: 8) {
                        Text(app.T("Xem trước: khách sẽ thấy đúng trang này", "Preview: this is exactly what guests will see"))
                            .font(.system(size: 11.5, weight: .semibold)).opacity(0.6)
                            .accessibilityIdentifier("createEvent.preview.public")
                        confirmBlock
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 8)
                    .background(app.palette.paper)
                )
            ))
            .transition(.opacity)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Date/time picker fix (Stage B, 2026-09-26) — ONE sheet, a graphical
/// native calendar directly above a native wheel time picker, both forced
/// to the EVENT's zone via `.environment(\.timeZone, ...)` (Asia/Ho_Chi_Minh,
/// or the venue's zone for a US address — migration 195) so the digits
/// shown always match the venue's wall-clock time regardless of the device's
/// own timezone. Nothing is written back to the parent's bindings until
/// "Xong" — dismissing via "Hủy" (or a swipe) leaves the previously
/// confirmed selection untouched, which is what "reopen retains draft
/// selection" means in practice: there's no separate, discardable draft
/// state to lose, only ever the last CONFIRMED one.
struct EventDateTimeSheet: View {
    @Binding var date: Date?
    @Binding var time: Date?
    /// Note 50 — fill rate of the benchmark slot a quick pick lands in (create flow only; nil = no data).
    var slotFill: ((Date, Date?) -> Double?)? = nil
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate: Date
    @State private var draftTime: Date
    /// The event's own zone; the picked digits are wall clock there.
    private let timeZone: TimeZone
    private var calendar: Calendar { EventMarket.calendar(timeZone) }
    // Month-navigation snap-back fix (2026-09-29) — the graphical
    // DatePicker below used to take `in: Date()...` directly, which calls
    // `Date()` fresh on every `body` re-evaluation (e.g. every tick while
    // scrubbing the wheel time picker below it). SwiftUI treats that as the
    // picker's valid range genuinely changing each render, which resets its
    // internal displayed-month scroll position back to today — exactly the
    // "jumps back to the current month" bug. Frozen once at init instead,
    // so the range argument is stable for the sheet's whole lifetime.
    private let minSelectableDate: Date

    init(date: Binding<Date?>, time: Binding<Date?>, slotFill: ((Date, Date?) -> Double?)? = nil,
         timeZone: TimeZone = AppState.vietnamTimeZone) {
        self._date = date
        self._time = time
        self.slotFill = slotFill
        self.timeZone = timeZone
        let calendar = EventMarket.calendar(timeZone)
        let today = calendar.startOfDay(for: Date())
        self._draftDate = State(initialValue: date.wrappedValue ?? today)
        self._draftTime = State(initialValue: time.wrappedValue ?? Date())
        self.minSelectableDate = today
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                quickPicks
                DatePicker(
                    "", selection: $draftDate, in: minSelectableDate...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .environment(\.timeZone, timeZone)
                .padding(.horizontal, 12)

                DatePicker(
                    "", selection: $draftTime,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .environment(\.timeZone, timeZone)
                .labelsHidden()
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(app.palette.paper)
            .navigationTitle(app.T("Ngày & giờ", "Date & time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.T("Hủy", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(app.T("Xong", "Done")) {
                        date = draftDate
                        time = draftTime
                        dismiss()
                    }
                }
            }
        }
    }
}

extension EventDateTimeSheet {
    private var hhmm: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f
    }

    /// Note 48: the common choices one tap away; the full pickers stay below.
    var quickPicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(SmartDefaults.dateQuickPicks(timeZone: timeZone).enumerated()), id: \.offset) { _, pick in
                        let fill = slotFill?(pick.date, draftTime).map { EventRecipe.pct($0) }
                        ChoiceChip(title: app.T(pick.label.vi, pick.label.en) + (fill.map { app.T(" · kín \($0)", " · fills \($0)") } ?? ""),
                                   selected: calendar.isDate(draftDate, inSameDayAs: pick.date),
                                   compact: true, identifier: "dateSheet.day.\(pick.label.en)") {
                            draftDate = pick.date
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SmartDefaults.timeQuickPicks, id: \.self) { t in
                        ChoiceChip(title: t, selected: hhmm.string(from: draftTime) == t,
                                   compact: true, identifier: "dateSheet.time.\(t)") {
                            if let d = SmartDefaults.timeOfDay(t, timeZone: timeZone) { draftTime = d }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Minimal wrapping row — SwiftUI has no stock flow layout before iOS 16's
/// Layout protocol, and the category chips need to wrap.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Note 48 form style for multi-line text: large, rounded, outlined, and no
/// stray system-white background behind the TextEditor.
extension View {
    func roundedFormEditor(app: AppState, minHeight: CGFloat, focused: Bool = false, state: FieldState = .normal) -> some View {
        self
            .font(.system(size: 16))
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fieldChrome(focused: focused, state: state, cornerRadius: 14)  // note 53: focus/error border
    }

    /// Note 53: the large rounded field look (Create event) for a raw TextField — same box as `BanbeField(icon:)`.
    func roundedFormField(app: AppState, focused: Bool, state: FieldState = .normal) -> some View {
        self
            .font(.system(size: 16))
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fieldChrome(focused: focused, state: state, cornerRadius: 14)
    }
}


/// The "Event submitted!" chooser (replaces the native confirmation dialog): a wide card over a dim
/// scrim, what happens next as three short steps, then one icon per destination. Springs in with a
/// bounce (just a fade under Reduce Motion). "View pending events" is the primary choice, as it is
/// also where a backdrop tap leads.
struct SubmittedChooserCard: View {
    let onCreateAnother: () -> Void
    let onPending: () -> Void
    let onHome: () -> Void
    let onAccount: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.32 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 20)
                .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.72))
                .offset(y: reduceMotion ? 0 : (shown ? 0 : 40))
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.62)) { shown = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(app.T("🎉 Đã gửi sự kiện!", "🎉 Event submitted!"))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(app.palette.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                step("paperplane.fill", app.T("Đã gửi cho banbe", "Sent to banbe"))
                step("checkmark.seal", app.T("banbe duyệt sự kiện", "banbe reviews it"))
                step("bell.badge", app.T("Lên sóng, bạn sẽ nhận thông báo", "It goes live and we notify you"))
                step("square.and.arrow.up", app.T("Chia sẻ được ngay khi được duyệt", "Sharing opens once it's approved"))
            }
            Text(app.T("Bạn muốn làm gì tiếp theo?", "What would you like to do next?"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(app.palette.ink.opacity(0.75))
            VStack(spacing: 10) {
                Button(action: onPending) {
                    Label(app.T("Xem sự kiện đang chờ duyệt", "View pending events"), systemImage: "hourglass")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("create.submitted.pending")
                SecondaryButton(title: app.T("Tạo sự kiện khác", "Create another event"), systemImage: "plus.circle", action: onCreateAnother)
                    .accessibilityIdentifier("create.submitted.another")
                HStack(spacing: 10) {
                    SecondaryButton(title: app.T("Trang chủ", "Home"), systemImage: "house", action: onHome)
                        .accessibilityIdentifier("create.submitted.home")
                    SecondaryButton(title: app.T("Tài khoản", "Account"), systemImage: "person.crop.circle", action: onAccount)
                        .accessibilityIdentifier("create.submitted.account")
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 520)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.submitted")
        .accessibilityAddTraits(.isModal)
    }

    private func step(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(app.palette.ink)
                .frame(width: 28, height: 28)
                .background(app.palette.field, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(app.palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


/// CreateEventView's own draft state, kept by AppState for the Undo toast (see `AppState.createBack`).
struct CreateDraftStash {
    var items: [StagedGalleryItem] = []
    var coverItemID: String?
    var step = 0
    var hasUnsavedInput = false
}

struct CreateUndoOffer: Identifiable, Equatable {
    let id = UUID()
    let duration: Double
}

/// Bottom toast after leaving a new-event draft: "Draft discarded", Undo, and a bar showing the
/// time left before it goes (and the draft with it).
struct CreateUndoToast: View {
    let offer: CreateUndoOffer
    @EnvironmentObject private var app: AppState
    @State private var remaining: CGFloat = 1

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(app.T("Đã đóng bản nháp sự kiện", "Event draft closed"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button { app.undoLeaveCreate() } label: {
                    Label(app.T("Hoàn tác", "Undo"), systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(app.T("Mở lại bản nháp với thông tin bạn đã nhập", "Reopens the draft with everything you entered"))
                .accessibilityIdentifier("create.undo.button")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(app.palette.ink.opacity(0.12))
                    Capsule().fill(app.palette.ink.opacity(0.7)).frame(width: g.size.width * remaining)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.undo")
        .task(id: offer.id) {
            remaining = 1
            withAnimation(.linear(duration: offer.duration)) { remaining = 0 }
            try? await Task.sleep(nanoseconds: UInt64(offer.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            app.expireCreateUndo(offer.id)
        }
    }
}


/// "Draft saved": what next, styled like the "Event submitted!" card (SubmittedChooserCard).
struct DraftSavedCard: View {
    let onExit: () -> Void
    let onNew: () -> Void
    let onViewDrafts: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.32 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)
            card
                .padding(.horizontal, 20)
                .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.72))
                .offset(y: reduceMotion ? 0 : (shown ? 0 : 40))
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.62)) { shown = true }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(app.T("💾 Đã lưu bản nháp", "💾 Draft saved"))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                step("iphone", app.T("Lưu trên máy này, trong tài khoản của bạn", "Kept on this phone, for your account"))
                step("pencil", app.T("Tiếp tục chỉnh sửa bất cứ lúc nào", "Pick it up and edit it any time"))
                step("tray.full", app.T("Tối đa \(EventDraftStore.maxDrafts) bản nháp (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts))",
                                        "Up to \(EventDraftStore.maxDrafts) drafts (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts) used)"))
            }
            Text(app.T("Bạn muốn làm gì tiếp theo?", "What would you like to do next?"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(app.palette.ink.opacity(0.75))
            VStack(spacing: 10) {
                Button(action: onViewDrafts) {
                    Label(app.T("Xem bản nháp", "View drafts"), systemImage: "tray.full")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(app.palette.paper)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityIdentifier("create.draftSaved.view")
                SecondaryButton(title: app.T("Bắt đầu bản nháp mới", "Start a new draft"), systemImage: "square.and.pencil", action: onNew)
                    .accessibilityIdentifier("create.draftSaved.new")
                SecondaryButton(title: app.T("Thoát", "Exit"), systemImage: "arrow.uturn.backward", action: onExit)
                    .accessibilityIdentifier("create.draftSaved.exit")
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(22)
        .frame(maxWidth: 520)
        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.draftSaved")
        .accessibilityAddTraits(.isModal)
    }

    private func step(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(app.palette.field, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The host's saved drafts, laid out like the Share card sheet (paper sheet, inline title, X to close).
/// Tap a draft (or ⋯ › Edit, or swipe left › Edit) to continue it; ⋯ › Delete or swipe left › Delete removes it.
struct EventDraftsSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    let onOpen: (HostEventDraft) -> Void
    @State private var thumbs: [UUID: UIImage] = [:]
    @State private var pendingDelete: HostEventDraft?

    var body: some View {
        NavigationStack {
            List {
                Text(app.T("Bản nháp lưu trên máy này, tối đa \(EventDraftStore.maxDrafts). Chạm để tiếp tục, hoặc vuốt trái / chạm ⋯ để sửa hay xoá.",
                           "Drafts are kept on this phone, up to \(EventDraftStore.maxDrafts). Tap one to continue, or swipe left / tap ⋯ to edit or delete."))
                    .font(.system(size: 11)).opacity(0.65)
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                if app.eventDrafts.isEmpty {
                    Text(app.T("Chưa có bản nháp nào.", "No drafts yet."))
                        .font(.system(size: 13)).opacity(0.7)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(app.eventDrafts) { d in
                    row(d)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = d } label: { Label(app.T("Xoá", "Delete"), systemImage: "trash") }
                            Button { onOpen(d) } label: { Label(app.T("Sửa", "Edit"), systemImage: "pencil") }
                                .tint(app.palette.clay)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(app.palette.paper.ignoresSafeArea())
            .foregroundStyle(app.palette.ink)
            .navigationTitle(app.T("Bản nháp (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts))",
                                   "Drafts (\(app.eventDrafts.count)/\(EventDraftStore.maxDrafts))"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button(role: .close) { dismiss() }.accessibilityIdentifier("create.drafts.close")
                } else {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(app.palette.ink)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(app.T("Đóng", "Close"))
                    .accessibilityIdentifier("create.drafts.close")
                }
            } }
            .confirmationDialog(app.T("Xoá bản nháp này?", "Delete this draft?"),
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button(app.T("Xoá", "Delete"), role: .destructive) {
                    if let d = pendingDelete { app.deleteEventDraft(d.id); thumbs[d.id] = nil }
                    pendingDelete = nil
                }
                Button(app.T("Huỷ", "Cancel"), role: .cancel) { pendingDelete = nil }
            } message: {
                Text(app.T("Thông tin và ảnh trong bản nháp sẽ mất.", "Its details and photos will be gone."))
            }
        }
        .presentationDragIndicator(.visible)
        .task(id: app.eventDrafts.map(\.id)) {
            for d in app.eventDrafts where thumbs[d.id] == nil {
                if let t = EventDraftStore.coverThumbnail(of: d) { thumbs[d.id] = t }
            }
        }
    }

    private func row(_ d: HostEventDraft) -> some View {
        HStack(spacing: 12) {
            Button { onOpen(d) } label: {
                HStack(spacing: 12) {
                    Group {
                        if let t = thumbs[d.id] {
                            Image(uiImage: t).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(.system(size: 18)).opacity(0.4)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .background(app.palette.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.displayName.isEmpty ? app.T("Chưa đặt tên", "Untitled event") : d.displayName)
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(app.T("Lưu \(d.savedAt.formatted(date: .abbreviated, time: .shortened))",
                                   "Saved \(d.savedAt.formatted(date: .abbreviated, time: .shortened))"))
                            .font(.system(size: 12)).opacity(0.65)
                        Text(app.T("\(d.photoFiles.count) ảnh · bước \(d.step + 1)/5", "\(d.photoFiles.count) photos · step \(d.step + 1)/5"))
                            .font(.system(size: 12)).opacity(0.65)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("create.draft.\(d.id.uuidString)")
            Menu {
                Button { onOpen(d) } label: { Label(app.T("Sửa", "Edit"), systemImage: "pencil") }
                Button(role: .destructive) { pendingDelete = d } label: { Label(app.T("Xoá", "Delete"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(app.palette.paper, in: Circle())
                    .overlay(Circle().stroke(app.palette.rule))
            }
            .accessibilityLabel(app.T("Thao tác bản nháp", "Draft actions"))
            .accessibilityIdentifier("create.draft.menu.\(d.id.uuidString)")
        }
        .padding(12)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// "Still needed" as tappable chips: each one takes the host to that field. Wraps onto more lines at large
/// text sizes instead of clipping.
private struct MissingChips: View {
    @EnvironmentObject private var app: AppState
    let lead: String
    let fields: [String]
    let label: (String) -> String
    let goToPrefix: String
    let alertTone: Bool
    let onPick: (String) -> Void

    var body: some View {
        let tint = alertTone ? BanbeTheme.alert : app.palette.ink
        VStack(spacing: 6) {
            Text(lead)
                .font(.footnote)
                .foregroundStyle(tint.opacity(alertTone ? 1 : 0.7))
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(fields, id: \.self) { id in
                    Button { onPick(id) } label: {
                        HStack(spacing: 4) {
                            Text(label(id))
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).opacity(0.6)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .overlay(Capsule().stroke(alertTone ? BanbeTheme.alert : app.palette.rule, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goToPrefix + label(id))
                    .accessibilityIdentifier("create.missing.\(id)")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// The event type's own facts in the create form (a supper club: dietary options, BYO, dress code). All optional.
private struct TypeDetailsEditor: View {
    @EnvironmentObject private var app: AppState
    let profile: EventTypeProfile
    let typeKey: String

    private var lang: String { app.isEN ? "en" : "vi" }
    private var values: EventDetails { app.createDetails[typeKey] ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(app.T("Khách hay hỏi những điều này trước khi đặt chỗ. Không bắt buộc.", "Guests often ask about these before booking. Optional."))
                .font(.footnote).opacity(0.75)
            ForEach(profile.wizard?.details ?? [], id: \.self) { id in
                if let def = profile.detailFields?[id] { field(id, def) }
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("create.typeDetails")
    }

    @ViewBuilder
    private func field(_ id: String, _ def: EventTypeProfile.DetailField) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FormFieldLabel(icon: "sparkles", text: def.label.text(lang))
            if def.kind == "text" {
                TextField(def.placeholder?.text(lang) ?? "", text: Binding(
                    get: { if case .text(let s)? = values[id] { return s }; return "" },
                    set: { app.setCreateDetail(type: typeKey, field: id, value: .text(String($0.prefix(def.max ?? 80)))) }))
                    .roundedFormField(app: app, focused: false)
                    .accessibilityIdentifier("create.detail.\(id)")
            } else {
                FlowRow(spacing: 8) {
                    ForEach(def.options ?? [], id: \.id) { o in
                        let on = isOn(id, o.id)
                        Button {
                            Haptics.selection()
                            toggle(id, def.kind == "multi", o.id)
                        } label: {
                            Text(lang == "vi" ? o.vi : o.en)
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? app.palette.paper : app.palette.ink)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(on ? app.palette.ink : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(on ? Color.clear : app.palette.rule, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                        .accessibilityIdentifier("create.detail.\(id).\(o.id)")
                    }
                }
            }
        }
    }

    private func isOn(_ id: String, _ option: String) -> Bool {
        switch values[id] {
        case .list(let a)?: return a.contains(option)
        case .text(let s)?: return s == option
        case nil: return false
        }
    }

    private func toggle(_ id: String, _ multi: Bool, _ option: String) {
        if multi {
            var a: [String] = { if case .list(let a)? = values[id] { return a }; return [] }()
            if let i = a.firstIndex(of: option) { a.remove(at: i) } else { a.append(option) }
            app.setCreateDetail(type: typeKey, field: id, value: a.isEmpty ? nil : .list(a))
        } else {
            app.setCreateDetail(type: typeKey, field: id, value: isOn(id, option) ? nil : .text(option))
        }
    }
}

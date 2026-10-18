import SwiftUI

// Post-signup personalization, one question per screen:
// Welcome → Goals → Interests → Availability → Budget → Languages →
// save → personalized reveal (real events, real matcher) → short settings
// review (only when owed) → Home / For You.
// State machine: Lib/OnboardingFlow.swift. Every answer is optional.

// MARK: - Coordinator

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var state: OnboardingFlowState
    /// Tapped on the reveal; opened once the flow is over.
    @Published var pendingEventKey: String?
    private let uid: UUID?
    private let store: OnboardingDraftStore
    private let save: (EventPreferences?) async -> Bool
    private var saveTask: Task<Void, Never>?

    init(state: OnboardingFlowState, uid: UUID?, store: OnboardingDraftStore = .init(),
         save: @escaping (EventPreferences?) async -> Bool) {
        self.state = state
        self.uid = uid
        self.store = store
        self.save = save
    }

    func send(_ action: OnboardingAction) {
        let effects = OnboardingFlow.reduce(&state, action)
        if let uid {
            if state.needsPreferences { store.save(state, uid: uid) } else { store.clear(uid: uid) }
        }
        for effect in effects {
            switch effect {
            case .track(let event): Analytics.track(event)
            case .save(let prefs):
                saveTask?.cancel()
                saveTask = Task { [weak self] in
                    guard let self else { return }
                    let ok = await self.save(prefs)
                    guard !Task.isCancelled else { return }
                    self.send(ok ? .saveSucceeded : .saveFailed)
                }
            }
        }
    }

    deinit { saveTask?.cancel() }
}

// MARK: - Overlay (mounted by RootView)

struct EventOnboardingOverlay: View {
    @EnvironmentObject var app: AppState
    @State private var flow: OnboardingCoordinator?

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if let flow { OnboardingFlowView(flow: flow) }
        }
        .transition(.opacity)
        .task {
            guard flow == nil else { return }
            let state = OnboardingDraftStore().resume(
                uid: app.userID, needsPreferences: app.needsPreferencesOnboarding,
                needsSettings: app.needsSettingsOnboarding, region: BudgetRegion.deviceDefault())
            // Remounted (e.g. after the Face ID lock) with nothing left owed: the
            // reveal can't be rebuilt, so hand straight back to the app instead of
            // leaving an empty overlay up.
            guard state.stage != .finished else {
                app.finishOnboardingFlow(showForYou: false, openEventKey: nil,
                                         answeredPreferences: app.eventPrefs?.isEmpty == false)
                return
            }
            app.onboardingFlowActive = true
            let appState = app
            flow = OnboardingCoordinator(state: state, uid: app.userID) { [weak appState] prefs in
                await appState?.completePreferencesOnboarding(prefs) ?? false
            }
        }
    }
}

struct OnboardingFlowView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch flow.state.stage {
            case .welcome:
                OnboardingWelcomeView(flow: flow)
            case .question:
                OnboardingQuestionView(flow: flow)
            case .saving:
                OnboardingSavingView()
            case .saveFailed:
                OnboardingSaveFailedView(flow: flow)
            case .reveal:
                PersonalizedRevealView(flow: flow)
            case .settings:
                OnboardingSettingsStep { flow.send(.settingsDone) }
            case .finished:
                Color.clear
            }
        }
        .foregroundStyle(app.palette.ink)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: flow.state.stage)
        .onChange(of: flow.state.stage) { _, stage in
            guard stage == .finished else { return }
            let answered = flow.state.payload != nil
            app.finishOnboardingFlow(showForYou: answered, openEventKey: flow.pendingEventKey,
                                     answeredPreferences: answered)
        }
    }
}

// MARK: - Shared pieces

private struct OnboardingTopBar: View {
    @EnvironmentObject var app: AppState
    let step: Int
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(app.T("Quay lại", "Back"))
                .accessibilityIdentifier("onboarding.back")
                Spacer()
                Text(app.T("Câu \(step)/\(OnboardingQuestion.count)", "\(step) of \(OnboardingQuestion.count)"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .accessibilityIdentifier("onboarding.progress")
                Spacer()
                Button(action: onSkip) {
                    Text(app.T("Bỏ qua", "Skip"))
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityHint(app.T("Bỏ qua câu này", "Skips this question"))
                .accessibilityIdentifier("onboarding.skipQuestion")
            }
            .buttonStyle(.plain)
            // Goal gradient (note 48): creating the account (or, for a guest,
            // opening banbe) is step 1 and already done, so question 1 never
            // opens at 0%.
            StepProgress(steps: stepTitles,
                         current: step,
                         message: ProgressEncouragement.line(remaining: stepTitles.count - step, T: app.T),
                         identifier: "onboarding.stepProgress")
        }
    }

    private var stepTitles: [String] {
        [app.isSignedIn ? app.T("Tài khoản", "Account") : app.T("Bắt đầu", "Start")]
            + OnboardingQuestion.allCases.map(stepTitle)
    }

    private func stepTitle(_ q: OnboardingQuestion) -> String {
        switch q {
        case .goals: return app.T("Mục tiêu", "Goals")
        case .interests: return app.T("Sở thích", "Interests")
        case .availability: return app.T("Thời gian", "Time")
        case .budget: return app.T("Ngân sách", "Budget")
        case .languages: return app.T("Ngôn ngữ", "Language")
        }
    }
}

/// A full-width choice with an explicit selected state (fill + checkmark +
/// trait), never colour alone.
private struct OnboardingChoiceRow: View {
    @EnvironmentObject var app: AppState
    let title: String
    var detail: String? = nil
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(selected ? .semibold : .regular))
                    if let detail {
                        Text(detail).font(.footnote).opacity(0.75)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(selected ? app.palette.ink : app.palette.field,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(app.palette.rule, lineWidth: selected ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Welcome

private struct OnboardingWelcomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.80, green: 0.62, blue: 0.16))
                    .accessibilityHidden(true)
                Text(app.T("Tìm những buổi bạn thật sự muốn đi", "Find events you'll actually want to go to"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.welcome")
                Text(app.T("Trả lời 5 câu ngắn, banbe sẽ gắn sao ★ Dành cho bạn lên những sự kiện hợp với bạn.",
                           "Answer 5 quick questions and banbe stars ★ For You on the events that fit."))
                    .font(.body).lineSpacing(3).padding(.top, 12)

                VStack(alignment: .leading, spacing: 14) {
                    point("clock", app.T("Khoảng 1 phút. Câu nào cũng bỏ qua được.", "About a minute. Every question is optional."))
                    point("lock", app.T("Chỉ bạn thấy câu trả lời, host không bao giờ thấy.", "Only you see your answers. Hosts never do."))
                    point("slider.horizontal.3", app.T("Đổi lại bất cứ lúc nào trong Tài khoản.", "Change them any time in Account."))
                }
                .padding(.top, 28)

                InkButton(title: app.T("Bắt đầu", "Get started")) { flow.send(.start) }
                    .accessibilityIdentifier("onboarding.start")
                    .padding(.top, 36)
                Button { flow.send(.skipAll) } label: {
                    Text(app.T("Bỏ qua, xem tất cả sự kiện", "Skip, show me everything"))
                        .font(.subheadline.weight(.semibold)).underline()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding.skipAll")
            }
            .padding(.horizontal, 24).padding(.top, 56).padding(.bottom, 40)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).frame(width: 24)
        }
    }
}

// MARK: - One question

private struct OnboardingQuestionView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int {
        if case .question(let i) = flow.state.stage { return i }
        return 0
    }
    private var question: OnboardingQuestion { flow.state.currentQuestion ?? .goals }
    private var vi: Bool { !app.isEN }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTopBar(step: index + 1, onBack: { flow.send(.back) }, onSkip: { flow.send(.skipQuestion) })
                .padding(.horizontal, 16).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.question.\(question.rawValue)")
                    Text(subtitle).font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.bottom, 12)
                    if question == .budget { budgetOptions } else { multiOptions }
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
                .id(question)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                   removal: .opacity))
            }

            InkButton(title: index + 1 == OnboardingQuestion.count ? app.T("Xem gợi ý của tôi", "See my picks") : app.T("Tiếp tục", "Continue")) {
                flow.send(.next)
            }
            .accessibilityIdentifier("onboarding.next")
            .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        }
    }

    private var title: String {
        switch question {
        case .goals: return app.T("Bạn muốn gì từ một buổi đi chơi?", "What do you want from a night out?")
        case .interests: return app.T("Loại sự kiện nào hợp với bạn?", "Which kinds of events are you into?")
        case .availability: return app.T("Bạn thường rảnh khi nào?", "When are you usually free?")
        case .budget: return app.T("Mỗi buổi bạn muốn chi khoảng bao nhiêu?", "How much do you like to spend per event?")
        case .languages: return app.T("Bạn thoải mái với ngôn ngữ nào?", "Which languages are you comfortable with?")
        }
    }

    private var subtitle: String {
        switch question {
        case .goals: return app.T("Chọn bao nhiêu cũng được. Dùng để xếp gợi ý lên trước.", "Pick any. We rank matching events higher.")
        case .interests: return app.T("Chọn bao nhiêu cũng được. Gợi ý chỉ gồm những loại bạn chọn.", "Pick any. Your picks only include these kinds.")
        case .availability: return app.T("Chọn bao nhiêu cũng được. Giờ khác vẫn hiện, chỉ xếp sau.", "Pick any. Other times still show, just lower.")
        case .budget: return app.T("Chọn một mức.", "Pick one.")
        case .languages: return app.T("Không bắt buộc. Sự kiện chưa ghi ngôn ngữ nên câu này chưa dùng để lọc.",
                                      "Optional. Events don't list a language yet, so this won't filter anything for now.")
        }
    }

    private var selection: [String]? {
        switch question {
        case .goals: return flow.state.draft.goals
        case .interests: return flow.state.draft.interests
        case .availability: return flow.state.draft.availability
        case .languages: return flow.state.draft.languages
        case .budget: return nil
        }
    }

    private var multiOptions: some View {
        VStack(spacing: 10) {
            ForEach(question.options()) { o in
                OnboardingChoiceRow(title: vi ? o.vi : o.en, selected: selection?.contains(o.id) == true,
                                    identifier: "onboarding.\(question.rawValue).\(o.id)") {
                    flow.send(.toggle(question, o.id))
                }
            }
            OnboardingChoiceRow(title: app.T("Không ưu tiên", "No preference"),
                                selected: selection == [EventPrefTaxonomy.noPreference],
                                identifier: "onboarding.\(question.rawValue).no_preference") {
                flow.send(.toggle(question, EventPrefTaxonomy.noPreference))
            }
            .padding(.top, 6)
        }
    }

    private var budgetOptions: some View {
        let region = flow.state.budgetRegion
        return VStack(alignment: .leading, spacing: 10) {
            Picker(app.T("Loại tiền", "Currency"), selection: Binding(
                get: { region }, set: { flow.send(.setRegion($0)) })) {
                Text("VND").tag(BudgetRegion.vn)
                Text("USD").tag(BudgetRegion.us)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.budget.region")
            .padding(.bottom, 4)
            ForEach(EventPrefTaxonomy.budgetTiers + [EventPrefTaxonomy.noPreference], id: \.self) { tier in
                OnboardingChoiceRow(title: region.label(tier: tier, vi: vi),
                                    selected: flow.state.draft.budget?.tier == tier,
                                    identifier: "onboarding.budget.\(tier)") {
                    flow.send(.pickBudget(tier))
                }
            }
        }
    }
}

// MARK: - Saving / failure

private struct OnboardingSavingView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(app.T("Đang lưu lựa chọn của bạn…", "Saving your picks…")).font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.saving")
    }
}

private struct OnboardingSaveFailedView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).accessibilityHidden(true)
            Text(app.T("Chưa lưu được", "Couldn't save yet"))
                .font(.system(.title, design: .rounded).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.saveFailed")
            Text(app.T("Câu trả lời vẫn còn trên máy này. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).",
                       "Your answers are still on this device. Retry, or skip for now (this may come back next time you open the app)."))
                .font(.subheadline).lineSpacing(3)
            InkButton(title: app.T("Thử lại", "Retry")) { flow.send(.retrySave) }
                .accessibilityIdentifier("onboarding.retry")
                .padding(.top, 8)
            HStack {
                Button(app.T("Sửa câu trả lời", "Edit answers")) { flow.send(.back) }
                    .accessibilityIdentifier("onboarding.failed.back")
                Spacer()
                Button(app.T("Bỏ qua lúc này", "Skip for now")) {
                    // Session-only, as before: the server marker stays unset.
                    app.needsPreferencesOnboarding = false
                    flow.send(.skipForNow)
                }
                .accessibilityIdentifier("onboarding.failed.skip")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Personalized reveal

struct PersonalizedRevealView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @State private var loading = false
    @State private var tracked = false

    private var prefs: EventPreferences { app.eventPrefs ?? flow.state.draft.normalizedForSave() }
    private var matches: [ForYouMatch] { app.forYouMatches }
    private var everywhereCount: Int { ForYou.rank(app.forYouCandidates, prefs: prefs).count }
    private var areaLimited: Bool { app.area != LocationHierarchy.allID }
    private var failed: Bool { app.discoveryEventsLoadFailed && app.discoveryEvents.isEmpty }
    private var isLoading: Bool { loading || app.discoveryEventsLoading }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(app.T("Đây là những gì hợp với bạn", "Here's what fits you"))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.reveal")
                    impacts
                    results
                }
                .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24)
            }
            InkButton(title: ctaTitle, enabled: !isLoading) { flow.send(.revealContinue) }
                .accessibilityIdentifier("onboarding.reveal.continue")
                .padding(.horizontal, 24).padding(.bottom, 20).padding(.top, 8)
        }
        .task {
            if app.discoveryEvents.isEmpty && !app.discoveryEventsLoading { await reload() }
            trackOnce()
        }
    }

    private var ctaTitle: String {
        if flow.state.needsSettings { return app.T("Tiếp tục", "Continue") }
        return matches.isEmpty ? app.T("Xem tất cả sự kiện", "See all events") : app.T("Xem gợi ý cho tôi", "Show my picks")
    }

    private func reload() async {
        loading = true
        await app.loadDiscoveryEvents()
        loading = false
    }

    private func trackOnce() {
        guard !tracked, !isLoading, !failed else { return }
        tracked = true
        Analytics.track(.personalizedResultsViewed(matchBucket: AnalyticsEvent.bucket(matches.count)))
    }

    private var impacts: some View {
        let lines = PreferenceImpacts.lines(prefs, vi: !app.isEN)
        return VStack(alignment: .leading, spacing: 10) {
            Text(app.T("Câu trả lời của bạn thay đổi gì", "What your answers change"))
                .font(.subheadline.weight(.semibold))
            if lines.isEmpty {
                Text(app.T("Chưa lọc gì cả: bạn chọn \"Không ưu tiên\" nên mọi sự kiện đều hiện như bình thường.",
                           "Nothing is filtered: you chose \"No preference\", so every event shows as usual."))
                    .font(.subheadline)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Label {
                    Text(line.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: line.kind == .filter ? "line.3.horizontal.decrease.circle"
                                    : line.kind == .ranking ? "arrow.up.circle" : "bookmark.circle")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.reveal.impacts")
    }

    @ViewBuilder
    private var results: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text(app.T("Đang tìm sự kiện hợp với bạn…", "Finding events that fit…")).font(.subheadline)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding.reveal.loading")
        } else if failed {
            VStack(alignment: .leading, spacing: 10) {
                Label(app.T("Chưa tải được sự kiện. Lựa chọn của bạn đã được lưu.",
                            "Couldn't load events right now. Your answers are saved."),
                      systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .accessibilityIdentifier("onboarding.reveal.failed")
                Button(app.T("Thử lại", "Try again")) { Task { await reload(); trackOnce() } }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.reveal.retry")
            }
        } else if matches.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Hiện chưa có sự kiện sắp tới nào khớp\(areaLimited ? " ở \(app.currentAreaLabel)" : "").",
                           "No upcoming events match yet\(areaLimited ? " in \(app.currentAreaLabel)" : "")."))
                    .font(.headline)
                    .accessibilityIdentifier("onboarding.reveal.empty")
                Text(app.T("Khi có sự kiện hợp, chip ★ Dành cho bạn sẽ hiện trên trang chủ. Bạn có thể nới lựa chọn trong Tài khoản > Sở thích sự kiện.",
                           "When one does, the ★ For You chip shows up on Home. You can loosen your answers in Account > Event preferences."))
                    .font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.75))
                if areaLimited && everywhereCount > 0 {
                    Button(app.T("Xem ở mọi khu vực (\(everywhereCount))", "Look in all areas (\(everywhereCount))")) {
                        app.pickArea(LocationHierarchy.allID)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.reveal.allAreas")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.T("\(matches.count) sự kiện sắp tới hợp với bạn\(areaLimited ? " ở \(app.currentAreaLabel)" : "")",
                           "\(matches.count) upcoming event\(matches.count == 1 ? "" : "s") fit you\(areaLimited ? " in \(app.currentAreaLabel)" : "")"))
                    .font(.headline)
                    .accessibilityIdentifier("onboarding.reveal.count")
                ForEach(matches.prefix(3), id: \.key) { m in
                    if let event = app.discoveryEvents.first(where: { $0.key == m.key }) {
                        RevealEventCard(event: event) {
                            flow.pendingEventKey = event.key
                            flow.send(.revealContinue)
                        }
                    }
                }
            }
        }
    }
}

/// A compact, real event card (photo, name, when, price) — tap to open it.
private struct RevealEventCard: View {
    @EnvironmentObject var app: AppState
    let event: CatalogEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                CatalogPhoto(path: event.img, height: 72, width: 72, cornerRadius: 12)
                    .frame(width: 72)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(app.trStatus(event.when)).font(.footnote).opacity(0.75).lineLimit(1)
                    Text(app.trStatus(event.price)).font(.footnote).opacity(0.75).lineLimit(1)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "star.fill")
                    .foregroundStyle(Color(red: 0.80, green: 0.62, blue: 0.16))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(app.palette.ink)
            .padding(10)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(app.T("Mở sự kiện", "Opens the event"))
        .accessibilityIdentifier("onboarding.reveal.event")
    }
}

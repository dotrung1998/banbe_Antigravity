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

    /// Goal gradient (note 48): creating the account (or, for a guest, opening banbe) counts as the first slice,
    /// so question 1 never opens on an empty bar.
    private var fraction: CGFloat { CGFloat(step) / CGFloat(OnboardingQuestion.count + 1) }

    // Note 53: one compact line — back, a thin bar with "2/5", skip — instead of a counter, a numbered stepper
    // and an encouragement line all at once.
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(app.T("Quay lại", "Back"))
            .accessibilityIdentifier("onboarding.back")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(app.palette.ink.opacity(0.12))
                    Capsule().fill(app.palette.ink).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.35), value: step)
            .accessibilityHidden(true)
            Text("\(step)/\(OnboardingQuestion.count)")
                .font(.footnote.weight(.bold)).monospacedDigit()
                .foregroundStyle(app.palette.ink.opacity(0.7))
                .accessibilityLabel(app.T("Câu \(step)/\(OnboardingQuestion.count)", "\(step) of \(OnboardingQuestion.count)"))
                .accessibilityIdentifier("onboarding.progress")
            Button(action: onSkip) {
                Text(app.T("Bỏ qua", "Skip"))
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.8)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityHint(app.T("Bỏ qua câu này", "Skips this question"))
            .accessibilityIdentifier("onboarding.skipQuestion")
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
    }
}

/// An answer, with an explicit selected state (tint + ink outline + check + trait), never colour alone.
/// Note 53: selected is a light tint, NOT solid ink, so a picked answer can't be mistaken for the Continue button
/// under it; each answer leads with its emoji, which grows a little when picked. `tile` = the 2-column grid look.
private struct OnboardingChoiceRow: View {
    @EnvironmentObject var app: AppState
    let title: String
    var detail: String? = nil
    var emoji: String? = nil
    var tile = false
    let selected: Bool
    let identifier: String
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Group {
                if tile { tileLabel } else { rowLabel }
            }
            .foregroundStyle(app.palette.ink)
            .background(selected ? app.palette.ink.opacity(0.06) : app.palette.field, in: shape)
            .overlay(shape.stroke(selected ? app.palette.ink : .clear, lineWidth: 1.5))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.15), value: selected)
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    private var check: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? app.palette.ink : app.palette.ink.opacity(0.3))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var face: some View {
        if let emoji {
            Text(emoji)
                .font(.system(size: tile ? 32 : 22))
                .scaleEffect(selected && !reduceMotion ? 1.15 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.5), value: selected)
                .accessibilityHidden(true)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 14) {
            face
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(selected ? .bold : .medium))
                if let detail {
                    Text(detail).font(.footnote).opacity(0.75)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            check
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    private var tileLabel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                face
                Spacer(minLength: 4)
                check
            }
            Spacer(minLength: 0)
            Text(title).font(.body.weight(selected ? .bold : .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
    }
}

// MARK: - Welcome

private struct OnboardingWelcomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the entrance: the content rises in, then the three tiles land
    /// one after another, left to right (owner, 2026-10-21).
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("🌟")
                    .font(.system(size: 42))
                    .frame(width: 84, height: 84)
                    .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
                    .modifier(RiseIn(shown: appeared, delay: 0))
                Group {
                    Text(app.T("Tìm những buổi bạn thật sự muốn đi", "Find events you'll actually want to go to"))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .padding(.top, 18)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.welcome")
                    Text(app.T("5 câu ngắn, rồi banbe gắn ★ Dành cho bạn lên sự kiện hợp với bạn.",
                               "5 quick taps, then banbe stars ★ For You on the events that fit."))
                        .font(.body).lineSpacing(3).padding(.top, 10)
                        .foregroundStyle(app.palette.ink.opacity(0.8))
                }
                .modifier(RiseIn(shown: appeared, delay: 0.04))

                // Note 53: three glanceable tiles instead of three sentences.
                // All three share the tallest tile's height (the 3rd title wraps
                // to two lines and used to make that tile alone taller).
                HStack(alignment: .top, spacing: 8) {
                    point(0, "⏱️", app.T("~1 phút", "~1 minute"), app.T("Câu nào cũng bỏ qua được", "Skip any question"))
                    point(1, "🔒", app.T("Chỉ bạn thấy", "Only you see it"), app.T("Host không bao giờ thấy", "Hosts never do"))
                    point(2, "⚙️", app.T("Đổi lúc nào", "Change anytime"), app.T("Trong Tài khoản", "In Account"))
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)

                Group {
                    InkButton(title: app.T("Bắt đầu", "Get started")) { flow.send(.start) }
                        .accessibilityIdentifier("onboarding.start")
                        .padding(.top, 36)
                    Button { flow.send(.skipAll) } label: {
                        Text(app.T("Bỏ qua, xem tất cả sự kiện", "Skip, show me everything"))
                            .font(.subheadline.weight(.semibold)).opacity(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle(haptic: false))
                    .padding(.top, 8)
                    .accessibilityIdentifier("onboarding.skipAll")
                }
                .modifier(RiseIn(shown: appeared, delay: reduceMotion ? 0 : 0.3))
            }
            .padding(.horizontal, 24).padding(.top, 56).padding(.bottom, 40)
        }
        .onAppear { appeared = true }
    }

    private func point(_ index: Int, _ emoji: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 26)).frame(height: 32).accessibilityHidden(true)
            Text(title).font(.footnote.weight(.bold)).multilineTextAlignment(.center)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(sub).font(.caption).foregroundStyle(app.palette.ink.opacity(0.7)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .modifier(RiseIn(shown: appeared, delay: reduceMotion ? 0 : 0.12 + Double(index) * 0.07))
    }
}

/// Entrance for the welcome screen: fade in while rising 24pt, on a quick
/// spring. Reduce Motion keeps only the fade (no travel, no stagger).
private struct RiseIn: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                       : .spring(response: 0.42, dampingFraction: 0.86).delay(delay),
                       value: shown)
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
                    Text(hero).font(.system(size: 52)).accessibilityHidden(true)
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.question.\(question.rawValue)")
                    Text(subtitle).font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.bottom, 12)
                    if question == .budget { budgetOptions } else { multiOptions }
                    // Note 53: each tap answers with what it will do. Reserved height, so nothing jumps.
                    Text(feedback ?? " ")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .frame(minHeight: 20, alignment: .leading)
                        .padding(.top, 6)
                        .animation(nil, value: feedback)
                        .accessibilityHidden(feedback == nil)
                        .accessibilityIdentifier("onboarding.feedback")
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

    /// Note 53: one emoji per question, above its title.
    private var hero: String {
        switch question {
        case .goals: return "👋"
        case .interests: return "🎟️"
        case .availability: return "🗓️"
        case .budget: return "💸"
        case .languages: return "💬"
        }
    }

    /// Note 53: the first question greets by the given name (last word of a Vietnamese name, first in English).
    private var greetingPrefix: String {
        guard question == .goals else { return "" }
        // Only a real display name; never the email prefix or "Guest" fallback of `app.displayName`.
        let parts = (app.user?.displayName ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = vi ? parts.last : parts.first, !name.isEmpty else { return "" }
        return app.T("Chào \(name)! ", "Hi \(name)! ")
    }

    private var feedback: String? {
        if question == .budget {
            return OnboardingFeedback.line(.budget, picked: flow.state.draft.budget.map { [$0.tier] } ?? [], vi: vi)
        }
        return OnboardingFeedback.line(question, picked: selection ?? [], vi: vi)
    }

    private var title: String { greetingPrefix + baseTitle }

    private var baseTitle: String {
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
        case .goals: return app.T("Chọn bao nhiêu cũng được.", "Pick as many as you like.")
        case .interests: return app.T("Chỉ những loại bạn chọn được gắn ★.", "Only the kinds you pick get the ★.")
        case .availability: return app.T("Giờ khác vẫn hiện, chỉ xếp sau.", "Other times still show, just lower.")
        case .budget: return app.T("Chọn một mức.", "Pick one.")
        case .languages: return app.T("Không bắt buộc, chưa dùng để lọc.", "Optional, doesn't filter yet.")
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

    /// Short labels (goals, interests, times) sit in a 2-column grid of emoji tiles; languages stay as rows.
    private var usesTiles: Bool { question != .languages }

    @ViewBuilder
    private var multiOptions: some View {
        let noPref = OnboardingChoiceRow(title: app.T("Không ưu tiên", "No preference"), emoji: PrefEmoji.of(EventPrefTaxonomy.noPreference),
                                         selected: selection == [EventPrefTaxonomy.noPreference],
                                         identifier: "onboarding.\(question.rawValue).no_preference") {
            flow.send(.toggle(question, EventPrefTaxonomy.noPreference))
        }
        if usesTiles {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(question.options()) { o in
                        OnboardingChoiceRow(title: vi ? o.vi : o.en, emoji: PrefEmoji.of(o.id), tile: true,
                                            selected: selection?.contains(o.id) == true,
                                            identifier: "onboarding.\(question.rawValue).\(o.id)") {
                            flow.send(.toggle(question, o.id))
                        }
                    }
                }
                noPref
            }
        } else {
            VStack(spacing: 10) {
                ForEach(question.options()) { o in
                    OnboardingChoiceRow(title: vi ? o.vi : o.en, emoji: PrefEmoji.of(o.id), selected: selection?.contains(o.id) == true,
                                        identifier: "onboarding.\(question.rawValue).\(o.id)") {
                        flow.send(.toggle(question, o.id))
                    }
                }
                noPref.padding(.top, 6)
            }
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
                OnboardingChoiceRow(title: region.label(tier: tier, vi: vi), emoji: PrefEmoji.of(tier),
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
            // Note 53: the alternative is a secondary button, "later" is text only.
            SecondaryButton(title: app.T("Sửa câu trả lời", "Edit answers"), emoji: "✏️") { flow.send(.back) }
                .accessibilityIdentifier("onboarding.failed.back")
            Button(app.T("Bỏ qua lúc này", "Skip for now")) {
                // Session-only, as before: the server marker stays unset.
                app.needsPreferencesOnboarding = false
                flow.send(.skipForNow)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(PressableButtonStyle(haptic: false))
            .accessibilityIdentifier("onboarding.failed.skip")
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
                    // Note 53, the peak of onboarding (peak-end rule): a moment of celebration when real matches
                    // land, and the next ask (♡ Save) right on the cards below.
                    Text(celebrating ? "🎉" : "✨")
                        .font(.system(size: 44))
                        .overlay { if celebrating { ConfettiBurst() } }
                        .accessibilityHidden(true)
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
        .onChange(of: celebrating, initial: true) { _, on in if on { Haptics.success() } }
    }

    private var celebrating: Bool { !isLoading && !failed && !matches.isEmpty }

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
                    Text(line.kind == .filter ? "🎯" : line.kind == .ranking ? "⬆️" : "🔖")
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
        let saved = app.isSaved(event.key)
        HStack(spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    CatalogPhoto(path: event.img, height: 72, width: 72, cornerRadius: 12)
                        .frame(width: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        (Text("★ ").foregroundColor(Color(red: 0.80, green: 0.62, blue: 0.16)) + Text(event.name))
                            .font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(app.trStatus(event.when)).font(.footnote).opacity(0.75).lineLimit(1)
                        Text(app.trStatus(event.price)).font(.footnote).opacity(0.75).lineLimit(1)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                }
                .foregroundStyle(app.palette.ink)
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(haptic: false))
            .accessibilityElement(children: .combine)
            .accessibilityHint(app.T("Mở sự kiện", "Opens the event"))
            .accessibilityIdentifier("onboarding.reveal.event")
            // Note 53: the ask inside the peak — keep the ones you like, one tap.
            Button {
                app.toggleFavorite(event.key)  // plays its own selection haptic
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(saved ? app.palette.clay : app.palette.ink)
                    .frame(width: 44, height: 44)
                    .background(saved ? app.palette.clayBg : .clear, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(haptic: false))
            .accessibilityLabel(saved ? app.T("Bỏ lưu \(event.name)", "Unsave \(event.name)") : app.T("Lưu \(event.name)", "Save \(event.name)"))
            .accessibilityAddTraits(saved ? [.isSelected] : [])
            .accessibilityIdentifier("onboarding.reveal.save")
            .padding(.trailing, 6)
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

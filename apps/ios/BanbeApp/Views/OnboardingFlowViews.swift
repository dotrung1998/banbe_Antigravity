import SwiftUI

// Post-signup personalization, onboarding v5 (note 80; prototype docs/prototypes/banbe-onboarding-v5-standalone.html):
// Welcome → What sounds fun? → When are you usually free? → A comfortable ticket price? → save → your For You
// (never empty) → one choice per screen (only when the settings step is owed) → recap with the tour offer → Home,
// or the chaptered tour. State machine: Lib/OnboardingFlow.swift. Every answer is optional.

// MARK: - Coordinator

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published private(set) var state: OnboardingFlowState
    /// A choice screen is writing its setting (or iOS is asking).
    @Published private(set) var consentBusy = false
    private let uid: UUID?
    private let store: OnboardingDraftStore
    private let save: (EventPreferences?) async -> Bool
    private let completeSettings: () async -> Bool
    private let applyConsent: (OnboardingConsent) async -> Bool
    private var saveTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?

    init(state: OnboardingFlowState, uid: UUID?, store: OnboardingDraftStore = .init(),
         save: @escaping (EventPreferences?) async -> Bool,
         completeSettings: @escaping () async -> Bool = { true },
         applyConsent: @escaping (OnboardingConsent) async -> Bool = { _ in true }) {
        self.state = state
        self.uid = uid
        self.store = store
        self.save = save
        self.completeSettings = completeSettings
        self.applyConsent = applyConsent
    }

    func send(_ action: OnboardingAction) {
        let effects = OnboardingFlow.reduce(&state, action)
        if let uid {
            if state.needsPreferences { store.save(state, uid: uid) } else { store.clear(uid: uid) }
        }
        run(effects)
    }

    /// A flow that opens on work (only the settings marker is owed and there's nothing to ask) starts it here.
    func start() {
        if state.stage == .settingsSaving { run([.completeSettings]) }
    }

    /// A choice screen's button. Continue writes the setting (or brings up the iOS alert); Not now writes nothing,
    /// because every choice is already off. Moves on with what really happened.
    func answer(_ yes: Bool) {
        guard let kind = state.currentConsent, !consentBusy else { return }
        guard yes else {
            send(.consentAnswered(kind, false))
            return
        }
        consentBusy = true
        Task { [weak self] in
            guard let self else { return }
            let on = await self.applyConsent(kind)
            self.consentBusy = false
            self.send(.consentAnswered(kind, on))
        }
    }

    private func run(_ effects: [OnboardingEffect]) {
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
            case .completeSettings:
                settingsTask?.cancel()
                settingsTask = Task { [weak self] in
                    guard let self else { return }
                    let ok = await self.completeSettings()
                    guard !Task.isCancelled else { return }
                    self.send(ok ? .settingsSucceeded : .settingsFailed)
                }
            }
        }
    }

    deinit {
        saveTask?.cancel()
        settingsTask?.cancel()
    }
}

// MARK: - Overlay (mounted by RootView)

struct EventOnboardingOverlay: View {
    @EnvironmentObject var app: AppState
    @State private var flow: OnboardingCoordinator?
    /// Note 80: logged-out demo. Every closure below is local; no Supabase call, marker or setting is ever written.
    var preview = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if let flow { OnboardingFlowView(flow: flow) }
        }
        .transition(.opacity)
        .task {
            guard flow == nil else { return }
            if preview {
                Analytics.paused = true
                let state = OnboardingFlowState.initial(needsPreferences: true, needsSettings: true,
                                                        region: BudgetRegion.deviceDefault(), consents: [.digest, .hosting])
                let coordinator = OnboardingCoordinator(state: state, uid: nil, save: { _ in true },
                                                        completeSettings: { true }, applyConsent: { _ in true })
                flow = coordinator
                return
            }
            let consents = await app.onboardingConsents()
            let state = OnboardingDraftStore().resume(
                uid: app.userID, needsPreferences: app.needsPreferencesOnboarding,
                needsSettings: app.needsSettingsOnboarding, region: BudgetRegion.deviceDefault(), consents: consents)
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
            let coordinator = OnboardingCoordinator(
                state: state, uid: app.userID,
                save: { [weak appState] prefs in
                    guard let appState else { return false }
                    guard appState.needsPreferencesOnboarding else {
                        // "Change my answers" after the first save: the marker is already set, so a plain save.
                        // Skipping every question there keeps the answers already saved.
                        guard let prefs else { return true }
                        return await appState.saveEventPreferences(prefs)
                    }
                    return await appState.completePreferencesOnboarding(prefs)
                },
                completeSettings: { [weak appState] in await appState?.completeSettingsOnboarding() ?? false },
                applyConsent: { [weak appState] kind in await appState?.applyOnboardingConsent(kind) ?? false })
            flow = coordinator
            coordinator.start()
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
            case .consent:
                OnboardingConsentView(flow: flow)
            case .settingsSaving:
                OnboardingSavingView(title: app.T("Đang lưu lựa chọn của bạn…", "Saving your choices…"))
            case .settingsFailed:
                OnboardingSettingsFailedView(flow: flow)
            case .recap:
                OnboardingRecapView(flow: flow)
            case .finished:
                Color.clear
            }
        }
        .foregroundStyle(app.palette.ink)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: flow.state.stage)
        .onChange(of: flow.state.stage) { _, stage in
            guard stage == .finished else { return }
            if app.onboardingPreview {
                app.finishOnboardingPreview(startTour: flow.state.tourRequested)
                return
            }
            let answered = flow.state.payload != nil
            app.finishOnboardingFlow(showForYou: answered, openEventKey: nil, answeredPreferences: answered,
                                     startTour: flow.state.tourRequested)
        }
    }
}

// MARK: - Shared pieces

struct OnboardingTopBar: View {
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
struct OnboardingChoiceRow: View {
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

// MARK: - v5 pieces

/// Back (labelled with where it goes), "1 of 3", and one bar per screen. Note 80.
private struct OnboardingStepHeader: View {
    @EnvironmentObject var app: AppState
    let label: String
    let step: Int
    let total: Int
    var backTitle: String? = nil
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if let onBack, let backTitle {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            Text(backTitle).font(.subheadline.weight(.medium))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle(haptic: false))
                    .accessibilityIdentifier("onboarding.back")
                }
                Spacer(minLength: 8)
                Text(label)
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.progress")
            }
            HStack(spacing: 6) {
                ForEach(0..<max(total, 1), id: \.self) { i in
                    Capsule().fill(i <= step ? app.palette.ink : app.palette.ink.opacity(0.14)).frame(height: 3)
                }
            }
            .animation(.easeOut(duration: 0.3), value: step)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.top, 6)
    }
}

/// Small uppercase line above a title.
private struct OnboardingEyebrow: View {
    @EnvironmentObject var app: AppState
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(1.3)
            .foregroundStyle(app.palette.ink.opacity(0.62))
    }
}

/// The quiet text button under a primary action ("Skip this question", "Skip, go to Home").
private struct OnboardingLinkButton: View {
    @EnvironmentObject var app: AppState
    let title: String
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(app.palette.ink.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityIdentifier(identifier)
    }
}

private func eventCountText(_ n: Int, vi: Bool) -> String {
    vi ? "\(n) sự kiện" : "\(n) \(n == 1 ? "event" : "events")"
}

/// "A, B and C" / "A, B or C" with the type labels.
private func joinedTypeNames(_ ids: [String], vi: Bool, last: (vi: String, en: String)) -> String {
    let names = ids.map { EventPrefTaxonomy.label($0, in: EventPrefTaxonomy.interests, vi: vi) }
    guard names.count > 1 else { return names.first ?? "" }
    return names.dropLast().joined(separator: ", ") + " \(vi ? last.vi : last.en) " + names[names.count - 1]
}

// MARK: - Welcome

private struct OnboardingWelcomeView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the entrance: the photos land, then the copy rises in.
    @State private var appeared = false

    private static let night = Color(red: 22 / 255, green: 20 / 255, blue: 15 / 255)
    private var photos: [String] { Array(EventCatalog.all.prefix(3).map(\.img)) }

    var body: some View {
        ZStack {
            Self.night.ignoresSafeArea()
            if let first = photos.first {
                // The same blurred-photo backdrop as Home's header.
                CatalogPhoto(path: first, cornerRadius: 0)
                    .scaledToFill()
                    .blur(radius: 18)
                    .brightness(-0.35)
                    .scaleEffect(1.15)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    fan
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .padding(.top, 8)
                    Group {
                        Text(app.T("Những buổi nhỏ, đáng để ra ngoài.", "Small events worth going out for."))
                            .font(BanbeTheme.display(34))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("onboarding.welcome")
                        Text(app.T("Supper club, buổi nghe nhạc, triển lãm. Do host thật tổ chức, mỗi lần vài chỗ.",
                                   "Supper clubs, listening sessions, openings. Run by real hosts, a few seats at a time."))
                            .font(.body).lineSpacing(3).padding(.top, 10)
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .modifier(RiseIn(shown: appeared, delay: 0.1))
                    VStack(spacing: 8) {
                        Button { flow.send(.start) } label: {
                            Text(app.T("Bắt đầu", "Get started"))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Self.night)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.white, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle(haptic: false))
                        .accessibilityIdentifier("onboarding.start")
                        Button { flow.send(.skipAll) } label: {
                            Text(app.T("Bỏ qua, xem tất cả sự kiện", "Skip, show me everything"))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle(haptic: false))
                        .accessibilityIdentifier("onboarding.skipAll")
                        Text(app.T("3 câu hỏi, khoảng một phút", "3 questions, about a minute"))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.top, 4)
                    }
                    .padding(.top, 28)
                    .modifier(RiseIn(shown: appeared, delay: reduceMotion ? 0 : 0.25))
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { appeared = true }
    }

    /// Three real event photos, fanned like prints on a table.
    private var fan: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, path in
                let spec: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: Double) =
                    i == 0 ? (-78, -40, 148, 196, -5) : i == 1 ? (82, -52, 150, 186, 5) : (0, 58, 176, 170, -1)
                CatalogPhoto(path: path, height: spec.h, width: spec.w, cornerRadius: 14)
                    .frame(width: spec.w, height: spec.h)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .rotationEffect(.degrees(spec.r))
                    .offset(x: spec.x, y: spec.y)
                    .modifier(RiseIn(shown: appeared, delay: reduceMotion ? 0 : Double(i) * 0.08))
            }
        }
        .accessibilityHidden(true)
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
    @State private var typesOpen = false

    private var index: Int {
        if case .question(let i) = flow.state.stage { return i }
        return 0
    }
    private var question: OnboardingQuestion { flow.state.currentQuestion ?? .interests }
    private var vi: Bool { !app.isEN }
    private var draft: EventPreferences { flow.state.draft }
    private var candidates: [ForYouCandidate] { app.forYouAreaCandidates }
    /// Counts are hidden until events have loaded: a "0 events" that is really "not loaded yet" would mislead.
    private var countsReady: Bool { !app.discoveryEvents.isEmpty }
    private var picked: Bool { question.answerCount(draft) > 0 }
    private var isLast: Bool { index + 1 == OnboardingQuestion.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepHeader(label: app.T("Câu \(index + 1)/\(OnboardingQuestion.count)", "\(index + 1) of \(OnboardingQuestion.count)"),
                                 step: index, total: OnboardingQuestion.count,
                                 backTitle: index == 0 ? app.T("Chào mừng", "Welcome") : app.T("Quay lại", "Back"),
                                 onBack: { flow.send(.back) })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingEyebrow(text: app.T("Dành cho bạn", "For You"))
                    Text(title)
                        .font(BanbeTheme.display(30))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.question.\(question.rawValue)")
                    Text(subtitle)
                        .font(.subheadline).lineSpacing(2)
                        .foregroundStyle(app.palette.ink.opacity(0.72))
                        .padding(.top, 8)
                    Group {
                        switch question {
                        case .interests: interestOptions
                        case .budget: budgetOptions
                        default: availabilityOptions
                        }
                    }
                    .padding(.top, 22)
                    // Each tap answers with what it leaves. Reserved height, so nothing jumps.
                    Text(feedback ?? " ")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.78))
                        .frame(minHeight: 20, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                        .animation(nil, value: feedback)
                        .accessibilityHidden(feedback == nil)
                        .accessibilityIdentifier("onboarding.feedback")
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
                .id(question)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                   removal: .opacity))
            }

            VStack(spacing: 2) {
                InkButton(title: isLast ? app.T("Xem gợi ý của tôi", "Show my picks") : app.T("Tiếp tục", "Continue"),
                          enabled: picked) {
                    flow.send(.next)
                }
                .accessibilityIdentifier("onboarding.next")
                OnboardingLinkButton(title: app.T("Bỏ qua câu này", "Skip this question"),
                                     identifier: "onboarding.skipQuestion") { flow.send(.skipQuestion) }
            }
            .padding(.horizontal, 24).padding(.bottom, 14).padding(.top, 8)
        }
        .overlay {
            if typesOpen {
                OnboardingTypesPanel(flow: flow, counts: typeCounts, countsReady: countsReady) { typesOpen = false }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: typesOpen)
        .task {
            if app.discoveryEvents.isEmpty && !app.discoveryEventsLoading && !app.discoveryEventsLoadFailed {
                await app.loadDiscoveryEvents()
            }
        }
    }

    private var title: String {
        switch question {
        case .availability: return app.T("Bạn thường rảnh khi nào?", "When are you usually free?")
        case .budget: return app.T("Giá vé bao nhiêu thì thoải mái?", "A comfortable ticket price?")
        default: return app.T("Bạn thấy gì vui?", "What sounds fun?")
        }
    }

    private var subtitle: String {
        switch question {
        case .availability: return app.T("Chọn bao nhiêu cũng được. Giờ khác vẫn hiện, chỉ xếp sau.",
                                         "Pick any. Other times still show, just lower down.")
        case .budget: return app.T("Chọn một mức. Sự kiện đắt hơn sẽ không được gợi ý.",
                                   "Pick one. Pricier events are left out of For You.")
        default: return app.T("Chọn bao nhiêu cũng được. Đây sẽ là gợi ý Dành cho bạn trên Trang chính.",
                              "Pick any. This becomes your For You on Home.")
        }
    }

    private var typeCounts: [String: Int] { OnboardingCounts.typeCounts(candidates) }

    private func typeLabel(_ id: String) -> String {
        EventPrefTaxonomy.label(id, in: EventPrefTaxonomy.interests, vi: vi)
    }

    private var feedback: String? {
        guard picked else {
            return question == .interests
                ? app.T("Bỏ qua thì Dành cho bạn bắt đầu với những gì sắp diễn ra.", "Skip it and For You starts with what's on soon.")
                : nil
        }
        if question == .budget {
            switch draft.budget?.tier {
            case "flexible": return app.T("Đã ghi nhận. Không giới hạn giá.", "Got it. No price limit.")
            case "free": return app.T("Đã ghi nhận. Chỉ sự kiện miễn phí.", "Got it. Free events only.")
            default: return app.T("Đã ghi nhận. Sự kiện đắt hơn sẽ bị bỏ ra.", "Got it. Pricier events are left out.")
            }
        }
        guard countsReady else { return nil }
        let counts = typeCounts
        if question == .interests && !draft.declaredInterests.contains(where: { (counts[$0] ?? 0) > 0 }) {
            return app.T("Hiện chưa có buổi nào. Dành cho bạn sẽ bắt đầu với những gì sắp diễn ra, và các loại này hiện lên khi host đăng.",
                         "None on right now. For You starts with what's on soon, and these types show up as hosts post them.")
        }
        let n = OnboardingCounts.matchCount(candidates, draft)
        if n == 0 { return app.T("Chưa có gì khớp hết. Dành cho bạn sẽ thêm gợi ý gần đúng.", "Nothing fits all of that yet. For You will add close picks.") }
        if n < OnboardingCounts.minimum {
            return app.T("\(n) sự kiện khớp. Dành cho bạn sẽ thêm gợi ý gần đúng.",
                         "\(n) \(n == 1 ? "event fits" : "events fit") so far. For You will add close picks.")
        }
        return app.T("\(n) sự kiện khớp đến giờ.", "\(n) events match so far.")
    }

    // MARK: interests: live tiles + "More types"

    private var interestOptions: some View {
        let counts = typeCounts
        let tiles = OnboardingCounts.tileTypes(counts, label: typeLabel)
        let selected = draft.declaredInterests
        let extra = selected.filter { !tiles.contains($0) }
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(tiles, id: \.self) { k in
                    tile(emoji: PrefEmoji.of(k), title: typeLabel(k), detail: eventCountText(counts[k] ?? 0, vi: vi),
                         selected: selected.contains(k), identifier: "onboarding.interests.\(k)") {
                        flow.send(.toggle(.interests, k))
                    }
                }
                tile(emoji: "🔍", title: app.T("Loại khác", "More types"),
                     detail: extra.isEmpty
                        ? app.T("Tìm \(EventPrefTaxonomy.interests.count) loại", "\(EventPrefTaxonomy.interests.count) to search")
                        : app.T("Đã chọn \(extra.count)", "\(extra.count) picked"),
                     selected: !extra.isEmpty, identifier: "onboarding.interests.more") {
                    typesOpen = true
                }
                .accessibilityHint(app.T("Mở danh sách mọi loại sự kiện", "Opens every event type"))
            }
            if !extra.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(extra, id: \.self) { k in
                            Button { flow.send(.toggle(.interests, k)) } label: {
                                Text("\(typeLabel(k)) ×")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(app.palette.paper)
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .background(app.palette.ink, in: Capsule())
                            }
                            .buttonStyle(PressableButtonStyle(haptic: false))
                            .accessibilityLabel(app.T("Bỏ \(typeLabel(k))", "Remove \(typeLabel(k))"))
                            .accessibilityIdentifier("onboarding.interests.chip.\(k)")
                        }
                    }
                }
            }
        }
    }

    private func tile(emoji: String, title: String, detail: String, selected: Bool, identifier: String,
                      action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 4) {
                Text(emoji).font(.system(size: 26)).accessibilityHidden(true)
                Text(title).font(.footnote.weight(selected ? .bold : .medium))
                    .multilineTextAlignment(.center).lineLimit(2)
                if countsReady || identifier.hasSuffix(".more") {
                    Text(detail).font(.caption2).foregroundStyle(app.palette.ink.opacity(0.65))
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 4).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(selected ? app.palette.ink.opacity(0.07) : app.palette.field, in: shape)
            .overlay(shape.stroke(selected ? app.palette.ink : app.palette.rule, lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.footnote).padding(6).accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: when / budget rows with live counts

    private var availabilityOptions: some View {
        VStack(spacing: 8) {
            ForEach(EventPrefTaxonomy.availability) { o in
                countRow(title: vi ? o.vi : o.en, detail: availabilityDetail(o.id),
                         count: OnboardingCounts.optionCount(candidates, draft, question: .availability, option: o.id,
                                                             region: flow.state.budgetRegion),
                         selected: draft.availability?.contains(o.id) == true,
                         identifier: "onboarding.availability.\(o.id)") {
                    flow.send(.toggle(.availability, o.id))
                }
            }
        }
    }

    private func availabilityDetail(_ id: String) -> String {
        switch id {
        case "weekdays": return app.T("Thứ Hai đến thứ Sáu", "Monday to Friday")
        case "weekends": return app.T("Thứ Bảy và Chủ nhật", "Saturday and Sunday")
        case "daytime": return app.T("Bắt đầu trước 17:00", "Starts before 17:00")
        default: return app.T("Bắt đầu từ 17:00", "Starts at 17:00 or later")
        }
    }

    private var budgetOptions: some View {
        let region = flow.state.budgetRegion
        return VStack(alignment: .leading, spacing: 8) {
            Picker(app.T("Loại tiền", "Currency"), selection: Binding(
                get: { region }, set: { flow.send(.setRegion($0)) })) {
                Text("VND").tag(BudgetRegion.vn)
                Text("USD").tag(BudgetRegion.us)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.budget.region")
            .padding(.bottom, 4)
            ForEach(EventPrefTaxonomy.budgetTiers, id: \.self) { tier in
                countRow(title: tier == "flexible" ? app.T("Giá nào cũng được", "Price doesn't matter") : region.label(tier: tier, vi: vi),
                         detail: nil,
                         count: OnboardingCounts.optionCount(candidates, draft, question: .budget, option: tier, region: region),
                         selected: draft.budget?.tier == tier,
                         identifier: "onboarding.budget.\(tier)") {
                    flow.send(.pickBudget(tier))
                }
            }
        }
    }

    private func countRow(title: String, detail: String?, count: Int, selected: Bool, identifier: String,
                          action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(selected ? .bold : .medium))
                    if let detail { Text(detail).font(.footnote).opacity(0.7) }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if countsReady {
                    Text(eventCountText(count, vi: vi)).font(.footnote).monospacedDigit().opacity(0.7)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? app.palette.ink : app.palette.ink.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(selected ? app.palette.ink.opacity(0.07) : app.palette.field, in: shape)
            .overlay(shape.stroke(selected ? app.palette.ink : app.palette.rule, lineWidth: selected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle(haptic: false))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(identifier)
    }
}

/// "More types": every type, searchable. Types with events on now first (most first), then the rest A to Z, so the
/// question's grid stays six tiles however many types exist and no type is a placeholder (App Review 2.1).
private struct OnboardingTypesPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    let counts: [String: Int]
    let countsReady: Bool
    let onClose: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var vi: Bool { !app.isEN }

    private var rows: (live: [PrefOption], rest: [PrefOption]) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = EventPrefTaxonomy.interests.filter {
            q.isEmpty || $0.vi.lowercased().contains(q) || $0.en.lowercased().contains(q)
        }
        let label: (PrefOption) -> String = { vi ? $0.vi : $0.en }
        let live = all.filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) != (counts[$1.id] ?? 0) ? (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) : label($0) < label($1) }
        let rest = all.filter { (counts[$0.id] ?? 0) == 0 }.sorted { label($0) < label($1) }
        return (live, rest)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                HStack {
                    Text(app.T("Mọi loại sự kiện", "All types"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(app.T("Xong", "Done"), action: onClose)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("onboarding.types.done")
                }
                .padding(.horizontal, 20).padding(.top, 14)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").opacity(0.6).accessibilityHidden(true)
                    TextField(app.T("Tìm \(EventPrefTaxonomy.interests.count) loại, như rượu vang hay phim",
                                    "Search \(EventPrefTaxonomy.interests.count) types, like wine or film"), text: $query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("onboarding.types.search")
                }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(app.palette.field, in: Capsule())
                .padding(.horizontal, 20).padding(.vertical, 10)
                let r = rows
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if r.live.isEmpty && r.rest.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.T("Không có loại nào tên “\(query)”", "No type called “\(query)”")).font(.headline)
                                Text(app.T("Thử một từ ngắn hơn.", "Try a shorter word.")).font(.subheadline).opacity(0.7)
                            }
                            .padding(.vertical, 24)
                        }
                        if !r.live.isEmpty {
                            groupHeader(app.T("Đang có sự kiện", "On now"))
                            ForEach(r.live) { row($0) }
                        }
                        if !r.rest.isEmpty {
                            groupHeader(app.T("Các loại khác, A đến Z", "More types, A to Z"))
                            ForEach(r.rest) { row($0) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
            .foregroundStyle(app.palette.ink)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .background(app.palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
            .padding(.top, 60)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onClose)
            .accessibilityIdentifier("onboarding.types")
        }
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(1.2)
            .foregroundStyle(app.palette.ink.opacity(0.6))
            .padding(.top, 16).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ o: PrefOption) -> some View {
        let on = flow.state.draft.declaredInterests.contains(o.id)
        let n = counts[o.id] ?? 0
        return Button {
            Haptics.selection()
            flow.send(.toggle(.interests, o.id))
        } label: {
            HStack(spacing: 12) {
                Text(PrefEmoji.of(o.id)).font(.title3).frame(width: 32).accessibilityHidden(true)
                Text(vi ? o.vi : o.en).font(.body.weight(on ? .semibold : .regular))
                Spacer(minLength: 8)
                if countsReady && n > 0 { Text(eventCountText(n, vi: vi)).font(.footnote).opacity(0.65) }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? app.palette.ink : app.palette.ink.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("onboarding.types.\(o.id)")
    }
}

// MARK: - Saving / failure

private struct OnboardingSavingView: View {
    @EnvironmentObject var app: AppState
    var title: String? = nil
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(title ?? app.T("Đang lưu lựa chọn của bạn…", "Saving your picks…")).font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.saving")
    }
}

/// The settings marker didn't save. The choices themselves are already written; only "done" is missing.
private struct OnboardingSettingsFailedView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).accessibilityHidden(true)
            Text(app.T("Chưa hoàn tất được", "Couldn't finish setup yet"))
                .font(BanbeTheme.display(28))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.settingsFailed")
            Text(app.T("Lựa chọn của bạn đã được lưu. Thử lại, hoặc bỏ qua lúc này (bước này có thể hiện lại lần mở sau).",
                       "Your choices are saved. Retry, or skip for now (this step may come back next time you open the app)."))
                .font(.subheadline).lineSpacing(3)
            InkButton(title: app.T("Thử lại", "Retry")) { flow.send(.retrySettings) }
                .accessibilityIdentifier("onboarding.settings.retry")
                .padding(.top, 8)
            OnboardingLinkButton(title: app.T("Bỏ qua lúc này", "Skip for now"), identifier: "onboarding.settings.skip") {
                // Session-only, as before: the server marker stays unset.
                app.needsSettingsOnboarding = false
                flow.send(.skipSettingsForNow)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Your For You (the reveal)

/// The payoff before anything is asked. Never empty while any upcoming event exists (`OnboardingCounts.reveal`):
/// each of its four cases says which one it is and offers a way back to the answers.
struct PersonalizedRevealView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator
    @State private var loading = false
    @State private var tracked = false

    private var vi: Bool { !app.isEN }
    private var prefs: EventPreferences { app.eventPrefs ?? flow.state.draft.normalizedForSave() }
    private var plan: RevealPlan { OnboardingCounts.reveal(app.forYouAreaCandidates, prefs: prefs) }
    private var areaLimited: Bool { app.area != LocationHierarchy.allID }
    private var failed: Bool { app.discoveryEventsLoadFailed && app.discoveryEvents.isEmpty }
    private var isLoading: Bool { loading || app.discoveryEventsLoading }
    private var celebrating: Bool { !isLoading && !failed && plan.mode == .picked }

    var body: some View {
        let plan = self.plan
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        OnboardingEyebrow(text: app.T("Dành cho bạn", "Your For You"))
                        if celebrating {
                            Text("🎉").overlay { ConfettiBurst() }.accessibilityHidden(true)
                        }
                    }
                    Text(isLoading ? app.T("Đang tìm sự kiện cho bạn…", "Finding your events…") : title(plan))
                        .font(BanbeTheme.display(30))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.reveal")
                    if !isLoading && !failed {
                        Text(subtitle(plan))
                            .font(.subheadline).lineSpacing(3)
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .accessibilityIdentifier("onboarding.reveal.sub")
                    }
                    results(plan).padding(.top, 22)
                }
                .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 24)
            }
            VStack(spacing: 2) {
                InkButton(title: app.T("Tiếp tục", "Continue"), enabled: !isLoading) { flow.send(.revealContinue) }
                    .accessibilityIdentifier("onboarding.reveal.continue")
                OnboardingLinkButton(title: redoTitle(plan), identifier: "onboarding.reveal.redo") { flow.send(.redoAnswers) }
            }
            .padding(.horizontal, 24).padding(.bottom, 14).padding(.top, 8)
        }
        .task {
            if app.discoveryEvents.isEmpty && !app.discoveryEventsLoading { await reload() }
            trackOnce()
        }
        .onChange(of: celebrating, initial: true) { _, on in if on { Haptics.success() } }
    }

    private func reload() async {
        loading = true
        await app.loadDiscoveryEvents()
        loading = false
    }

    private func trackOnce() {
        guard !tracked, !isLoading, !failed else { return }
        tracked = true
        Analytics.track(.personalizedResultsViewed(matchBucket: AnalyticsEvent.bucket(plan.exact)))
    }

    private func names(_ ids: [String], or: Bool = false) -> String {
        joinedTypeNames(ids, vi: vi, last: or ? (vi: "hoặc", en: "or") : (vi: "và", en: "and"))
    }

    private func title(_ p: RevealPlan) -> String {
        switch p.mode {
        case .popular: return app.T("Đây là những gì sắp diễn ra", "Here's what's on soon")
        case .soon: return app.T("Chưa có buổi \(names(p.waiting)) nào", "Nothing on for \(names(p.waiting)) right now")
        case .topped:
            if p.exact == 0 { return app.T("Chưa có gì khớp mọi câu trả lời", "Nothing fits every answer yet") }
            return app.T("\(p.exact) sự kiện khớp, và vài buổi tương tự",
                         "\(p.exact) close \(p.exact == 1 ? "match" : "matches"), and more like \(p.exact == 1 ? "it" : "them")")
        case .picked: return app.T("\(p.exact) sự kiện chọn cho bạn", "\(p.exact) events picked for you")
        }
    }

    private func subtitle(_ p: RevealPlan) -> String {
        let later = !p.waiting.isEmpty && p.mode != .soon
            ? app.T(" Hiện chưa có buổi \(names(p.waiting, or: true)); chúng sẽ hiện khi host đăng.",
                    " Nothing is on for \(names(p.waiting, or: true)) yet; those show up as hosts post them.")
            : ""
        switch p.mode {
        case .popular:
            return app.T("Bạn bỏ qua phần sở thích, nên danh sách bắt đầu với các sự kiện sớm nhất. Trả lời lúc nào cũng được trong Tài khoản › Sở thích sự kiện.",
                         "You skipped what you like, so this starts with the soonest events. Answer any time in Account › Event preferences.")
        case .soon:
            return app.T("Trong lúc chờ, đây là những sự kiện sớm nhất. Khi host đăng một buổi \(names(p.waiting, or: true)), nó sẽ được gợi ý trước.",
                         "Meanwhile, here are the soonest events. When a host posts \(names(p.waiting, or: true)), it's suggested first.")
        case .topped:
            return app.T("\(p.exact > 0 ? "Chỉ vài sự kiện khớp mọi câu trả lời lúc này, nên" : "Câu trả lời của bạn hơi hẹp lúc này, nên") danh sách thêm các buổi \(names(p.live)) khác, rồi đến những gì sắp diễn ra. Buổi khớp nhất luôn đứng đầu.",
                         "\(p.exact > 0 ? "Only a few events fit all your answers right now, so" : "Your answers are narrow right now, so") this also shows other \(names(p.live)) events, then what's on soon. Exact matches stay first.") + later
        case .picked:
            return app.T("Chọn từ những gì bạn thích: \(names(p.live)). Bật ★ Dành cho bạn trên Trang chính để chỉ xem chúng.",
                         "Picked from what you like: \(names(p.live)). Turn on ★ For You on Home to see only these.") + later
        }
    }

    private func redoTitle(_ p: RevealPlan) -> String {
        switch p.mode {
        case .popular: return app.T("Trả lời các câu hỏi", "Answer the questions")
        case .soon, .topped: return app.T("Chọn loại khác", "Pick other types")
        case .picked: return app.T("Đổi câu trả lời", "Change my answers")
        }
    }

    @ViewBuilder
    private func results(_ p: RevealPlan) -> some View {
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
        } else if p.keys.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Hiện chưa có sự kiện sắp tới nào\(areaLimited ? " ở \(app.currentAreaLabel)" : "").",
                           "No upcoming events yet\(areaLimited ? " in \(app.currentAreaLabel)" : "")."))
                    .font(.headline)
                    .accessibilityIdentifier("onboarding.reveal.empty")
                if areaLimited {
                    Button(app.T("Xem ở mọi khu vực", "Look in all areas")) { app.pickArea(LocationHierarchy.allID) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("onboarding.reveal.allAreas")
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(p.keys, id: \.self) { key in
                        if let event = app.discoveryEvents.first(where: { $0.key == key }) {
                            RevealEventCard(event: event)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.reveal.count")
        }
    }
}

/// A real event as a photo card (photo, name, when, price) with ♡ Save, so liked ones are kept in one tap.
private struct RevealEventCard: View {
    @EnvironmentObject var app: AppState
    let event: CatalogEvent

    var body: some View {
        let saved = app.isSaved(event.key)
        VStack(alignment: .leading, spacing: 0) {
            CatalogPhoto(path: event.img, height: 210, width: 180, cornerRadius: 14)
                .frame(width: 180, height: 210)
                .overlay(alignment: .topTrailing) {
                    Button {
                        app.toggleFavorite(event.key)  // plays its own selection haptic
                    } label: {
                        Image(systemName: saved ? "heart.fill" : "heart")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(saved ? app.palette.clay : app.palette.ink)
                            .frame(width: 40, height: 40)
                            .background(app.palette.paper.opacity(0.92), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableButtonStyle(haptic: false))
                    .padding(4)
                    .accessibilityLabel(saved ? app.T("Bỏ lưu \(event.name)", "Unsave \(event.name)") : app.T("Lưu \(event.name)", "Save \(event.name)"))
                    .accessibilityAddTraits(saved ? [.isSelected] : [])
                    .accessibilityIdentifier("onboarding.reveal.save")
                }
            Text(event.name)
                .font(.subheadline.weight(.semibold)).lineLimit(2)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding.reveal.event")
            Text("\(app.trStatus(event.when)) · \(app.trStatus(event.price))")
                .font(.caption).opacity(0.7).lineLimit(2)
                .padding(.top, 2)
        }
        .frame(width: 180, alignment: .leading)
        .foregroundStyle(app.palette.ink)
    }
}

// MARK: - One choice per screen

private struct OnboardingConsentView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator

    private var index: Int {
        if case .consent(let i) = flow.state.stage { return i }
        return 0
    }
    private var kind: OnboardingConsent { flow.state.currentConsent ?? .hosting }
    private var total: Int { flow.state.consents.count }

    private struct Copy {
        let icon: String
        let eyebrow: String
        let title: String
        let lead: String
        let ticks: [String]
        let fine: String
    }

    private var copy: Copy {
        switch kind {
        case .push:
            return Copy(icon: "bell",
                        eyebrow: app.T("Thông báo", "Notifications"),
                        title: app.T("Biết khi nào cần đi", "Know when it's time to go"),
                        lead: app.T("banbe có thể báo trên iPhone khi có gì mới với vé, thanh toán và tin nhắn của bạn.",
                                    "banbe can tell you on this iPhone when something happens with your tickets, payments and messages."),
                        ticks: [app.T("Chỉ về vé, thanh toán và tin nhắn của bạn", "Only about your own tickets, payments and messages"),
                                app.T("Thông báo quảng bá vẫn tắt trừ khi bạn bật", "Promotional pushes stay off unless you turn them on"),
                                app.T("Đổi trong Cài đặt iPhone › banbe", "Change it in iPhone Settings › banbe")],
                        fine: app.T("Tiếp theo, iPhone sẽ hỏi. Bạn quyết định ở đó.", "Next, your iPhone asks. You decide there."))
        case .digest:
            return Copy(icon: "envelope",
                        eyebrow: app.T("Bản tin", "Weekly digest"),
                        title: app.T("Sự kiện cuối tuần, mỗi tuần một lần", "This weekend's events, once a week"),
                        lead: app.T("Một bản tin ngắn tối thứ Năm với các sự kiện cuối tuần.",
                                    "A short digest on Thursday evening with the weekend's events."),
                        ticks: [app.T("Mỗi tuần một lần, tối thứ Năm", "Once a week, Thursday evening"),
                                app.T("Là tin quảng bá, nên tắt trừ khi bạn đồng ý", "It's promotional, so it stays off unless you say yes"),
                                app.T("Đổi trong Tài khoản › Cài đặt › Thông báo", "Change it in Account › Settings › Notifications")],
                        fine: app.T("Tiếp tục để bật. Để sau thì vẫn tắt.", "Continue turns this on. Not now keeps it off."))
        case .hosting:
            return Copy(icon: "storefront",
                        eyebrow: app.T("Tổ chức", "Hosting"),
                        title: app.T("Muốn tự tổ chức sự kiện?", "Want to host your own events?"),
                        lead: app.T("Chế độ tổ chức thêm công cụ để tạo sự kiện, check-in khách và nhận tiền.",
                                    "Hosting mode adds the tools to create events, check guests in and get paid."),
                        ticks: [app.T("Tạo sự kiện trong khoảng 5 phút", "Create an event in about 5 minutes"),
                                app.T("Phần đi chơi vẫn y như cũ", "Going out stays exactly the same"),
                                app.simpleShellEnabled
                                    ? app.T("Tắt lúc nào cũng được, ngay trên Trang chính", "Switch it off any time, right on Home")
                                    : app.T("Tắt lúc nào cũng được, trong Tài khoản", "Switch it off any time, in Account")],
                        fine: app.T("Tiếp tục để bật chế độ tổ chức. Để sau thì ứng dụng gọn hơn.",
                                    "Continue turns on Hosting mode. Not now keeps the app simpler."))
        }
    }

    var body: some View {
        let c = copy
        let busy = flow.consentBusy
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepHeader(label: app.T("Lựa chọn \(index + 1)/\(total)", "Choice \(index + 1) of \(total)"),
                                 step: index, total: total)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: c.icon)
                        .font(.system(size: 30, weight: .regular))
                        .padding(.top, 18)
                        .accessibilityHidden(true)
                    OnboardingEyebrow(text: c.eyebrow).padding(.top, 16)
                    Text(c.title)
                        .font(BanbeTheme.display(30))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.consent.\(kind.rawValue)")
                    Text(c.lead)
                        .font(.subheadline).lineSpacing(3)
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(c.ticks, id: \.self) { t in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).accessibilityHidden(true)
                                Text(t).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(app.palette.rule).frame(height: 1) }
                        }
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
                .id(kind)
            }
            VStack(spacing: 10) {
                InkButton(title: busy ? app.T("Đang lưu…", "Saving…") : app.T("Tiếp tục", "Continue"), enabled: !busy) {
                    flow.answer(true)
                }
                .accessibilityIdentifier("onboarding.consent.continue")
                if !kind.asksSystem {
                    // Same size as Continue: saying no is as easy as saying yes.
                    Button { flow.answer(false) } label: {
                        Text(app.T("Để sau", "Not now"))
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(app.palette.ink, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle(haptic: false))
                    .disabled(busy)
                    .accessibilityIdentifier("onboarding.consent.notNow")
                }
                Text(c.fine)
                    .font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
        }
    }
}

// MARK: - Recap and the tour offer

private struct OnboardingRecapView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var flow: OnboardingCoordinator

    private var vi: Bool { !app.isEN }
    private var chapters: [TourChapter] {
        OnboardingTourContent.plan(organizerMode: app.organizerMode, simpleShell: app.simpleShellEnabled).map(\.chapter)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingEyebrow(text: app.T("Xong", "Done"))
                    Text(app.T("Bạn đã sẵn sàng", "You're all set"))
                        .font(BanbeTheme.display(30))
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.recap")
                    Text(app.T("Đây là những gì bạn chọn. Đổi lúc nào cũng được.", "Here's what you chose. All of it can change later."))
                        .font(.subheadline)
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        row("sparkles", app.T("Dành cho bạn", "For You"), app.T("Tài khoản › Sở thích sự kiện", "Account › Event preferences"),
                            value: forYouValue, on: forYouValue != nil, id: "forYou")
                        if flow.state.consents.contains(.push) {
                            let on = flow.state.choices[OnboardingConsent.push.rawValue] == true
                            row("bell", app.T("Thông báo trên iPhone này", "Notifications on this iPhone"),
                                app.T("Cài đặt iPhone › banbe", "iPhone Settings › banbe"),
                                value: on ? app.T("Cho phép", "Allowed") : app.T("Không cho phép", "Not allowed"), on: on, id: "push")
                        }
                        if flow.state.consents.contains(.digest) {
                            let on = flow.state.choices[OnboardingConsent.digest.rawValue] == true
                            row("envelope", app.T("Bản tin cuối tuần", "Weekly digest"),
                                app.T("Tài khoản › Cài đặt › Thông báo", "Account › Settings › Notifications"),
                                value: on ? app.T("Bật", "On") : app.T("Tắt", "Off"), on: on, id: "digest")
                        }
                        row("storefront", app.T("Chế độ tổ chức", "Hosting mode"),
                            app.simpleShellEnabled ? app.T("Trang chính, nút Tổ chức", "Home, the Hosting switch")
                                                   : app.T("Tài khoản, dưới tên bạn", "Account, under your name"),
                            value: app.organizerMode ? app.T("Bật", "On") : app.T("Tắt", "Off"), on: app.organizerMode, id: "hosting")
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.T("Xem hướng dẫn, khoảng 2 phút", "Take the tour, about 2 minutes"))
                            .font(.headline)
                        Text(app.T("\(chapters.count) chương ngắn trên chính các màn hình thật. Chỉ đi tới, và bạn có thể dừng sau mỗi chương.",
                                   "\(chapters.count) short chapters on the real screens. It only goes forward, and you can stop after any chapter."))
                            .font(.subheadline).lineSpacing(2)
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            ForEach(chapters) { c in
                                Text(vi ? c.name.vi : c.name.en)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(app.palette.paper, in: Capsule())
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 24).padding(.top, 40).padding(.bottom, 24)
            }
            VStack(spacing: 2) {
                InkButton(title: app.T("Bắt đầu hướng dẫn", "Start the tour")) { flow.send(.startTour) }
                    .accessibilityIdentifier("onboarding.recap.tour")
                OnboardingLinkButton(title: app.onboardingPreview ? app.T("Bỏ qua, xem sự kiện (chưa đăng nhập nên chưa lưu)", "Skip, browse events (not logged in, so nothing is saved)") : app.T("Bỏ qua, về Trang chính", "Skip, go to Home"), identifier: "onboarding.recap.home") {
                    flow.send(.skipTour)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 14).padding(.top, 8)
        }
    }

    /// nil = nothing answered (For You isn't set yet).
    private var forYouValue: String? {
        guard let p = flow.state.payload ?? app.eventPrefs, !p.isEmpty else { return nil }
        let n = p.declaredInterests.count
        if n > 0 { return app.T("\(n) loại", "\(n) \(n == 1 ? "type" : "types")") }
        return app.T("Đã lưu", "Saved")
    }

    private func row(_ icon: String, _ title: String, _ where_: String, value: String?, on: Bool, id: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.body).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(where_).font(.caption).foregroundStyle(app.palette.ink.opacity(0.62))
            }
            Spacer(minLength: 8)
            Text(value ?? app.T("Chưa đặt", "Not set yet"))
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(app.palette.ink.opacity(on ? 1 : 0.62))
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.recap.\(id)")
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

import SwiftUI

/// "How banbe works" story body, shared by the public Welcome screen and Help & Legal (note 63).
/// Version 1 = the original emoji tile + three text points per page. Version 2 = per section, a swipeable deck of
/// small demo screens: the centred one is the focus, its neighbours peek in dimmed, scaled down and blurred. The
/// admin switch `onboarding_v2` (migration 201) picks the version; hosts draw their own top bar (Back, N/4, Skip)
/// and give each page its own `.id`, so every section arrives fresh. Web twin: src/components/HowBanbeWorks.jsx.
struct HowBanbeWorksBody<Finale: View, Footer: View>: View {
    @EnvironmentObject private var app: AppState
    let page: Int
    let v2: Bool
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    let onNext: () -> Void
    /// Owner, 2026-10-24: the tour has been finished (swipe past the very last screen, or Done) → thank-you message.
    var finished = false
    /// Called by the swipe past the very last screen. nil = no swipe-to-finish (the host has no thank-you).
    var onFinish: (() -> Void)? = nil
    /// Shown on the last section under the deck (Welcome: sign-up buttons; Help: Done).
    @ViewBuilder let finale: () -> Finale
    /// Shown under the thank-you message (Welcome: sign-up buttons; Help: Back to Help).
    @ViewBuilder let footer: () -> Footer

    private var section: HowItWorksContent.Section {
        HowItWorksContent.sections[min(max(page, 0), HowItWorksContent.pageCount - 1)]
    }
    private var isLast: Bool { page >= HowItWorksContent.pageCount - 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if finished {
                    StoryThanksView()
                    footer().padding(.top, 10)
                } else {
                    if v2 {
                        StoryDeckSection(page: page, section: section, headingFocused: headingFocused,
                                         onNext: isLast ? onFinish : onNext, finishes: isLast)
                    } else {
                        StoryPointsView(page: page, section: section, headingFocused: headingFocused)
                    }
                    Group {
                        if isLast {
                            finale()
                        } else {
                            InkButton(title: app.T("Tiếp", "Next"), font: .headline, action: onNext)
                                .accessibilityIdentifier("welcome.story.next")
                        }
                    }
                    .padding(.top, v2 ? 6 : 24)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The closing beat (owner, 2026-10-24): a thank-you and a warm wish once the tour is done. A tile pops in with a
/// short confetti burst (nothing under Reduce Motion), then the lines rise.
private struct StoryThanksView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    private func motion(_ delay: Double, _ duration: Double = 0.9) -> Animation {
        reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🎉")
                .font(.system(size: 52))
                .frame(width: 100, height: 100)
                .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -10))
                .opacity(shown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.55, dampingFraction: 0.6).delay(0.1), value: shown)
                .overlay { if shown { ConfettiBurst() } }
                .padding(.top, 36)
                .accessibilityHidden(true)
            Text(app.T("Cảm ơn bạn đã xem hết!", "Thanks for taking the tour!"))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 16)
                .animation(motion(0.35), value: shown)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("hiw.thanks")
            Text(app.T("Giờ bạn đã biết banbe hoạt động thế nào. Chúc bạn có những buổi tối thật ấm áp, món ngon và những người bạn mới. Hẹn gặp bạn bên bàn tiệc! 🥂",
                       "Now you know how banbe works. We wish you warm evenings, good food and new friends. See you at the table! 🥂"))
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(app.palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 16)
                .animation(motion(0.55), value: shown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            shown = true
            Haptics.success()
        }
    }
}

/// Help & Legal > How banbe works: the same story, replayable while signed in. Ends with Done instead of the sign-up
/// buttons. Web twin: src/screens/HowItWorks.jsx.
struct HowItWorksScreen: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var story = PublicStoryState(page: 0)
    @State private var finished = false
    @AccessibilityFocusState private var headingFocused: Bool

    private var version: Int { app.onboardingV2Enabled ? 2 : 1 }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        if finished { withAnimation(AuthMotion.animation(reduceMotion: reduceMotion)) { finished = false } }
                        else if (story.page ?? 0) > 0 { withAnimation(AuthMotion.animation(reduceMotion: reduceMotion)) { story.back() } } else { app.goBack() }
                    } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.T("Quay lại", "Back"))
                    .accessibilityIdentifier("hiw.back")
                    Text(app.T("\((story.page ?? 0) + 1)/\(HowItWorksContent.pageCount)",
                               "\((story.page ?? 0) + 1) of \(HowItWorksContent.pageCount)"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.65))
                        .accessibilityIdentifier("welcome.story.progress")
                    Spacer(minLength: 0)
                    if !story.isLastPage {
                        Button {
                            Analytics.track(.publicStorySkipped(step: story.page ?? 0))
                            app.goBack()
                        } label: {
                            Text(app.T("Bỏ qua", "Skip")).font(.subheadline.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("welcome.story.skip")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8)

                let page = story.page ?? 0
                HowBanbeWorksBody(page: page, v2: app.onboardingV2Enabled, headingFocused: $headingFocused,
                                  onNext: { withAnimation(AuthMotion.animation(reduceMotion: reduceMotion)) { story.next() } },
                                  finished: finished, onFinish: finish) {
                    InkButton(title: app.T("Xong", "Done"), font: .headline) { finish() }
                        .accessibilityIdentifier("hiw.done")
                        .onAppear { Analytics.track(.publicStoryCompleted) }
                } footer: {
                    InkButton(title: app.T("Về Trợ giúp", "Back to Help"), font: .headline) { app.goBack() }
                        .accessibilityIdentifier("hiw.close")
                }
                .id("hiw.\(page).\(finished)")
                .transition(AuthMotion.transition(forward: story.forward, reduceMotion: reduceMotion))
            }
        }
        .foregroundStyle(app.palette.ink)
        .onAppear { Analytics.track(.publicStoryOpened) }
        .onChange(of: story.page) { _, _ in headingFocused = true; finished = false }
        .accessibilityIdentifier("hiw.screen.v\(version)")
    }

    private func finish() {
        withAnimation(AuthMotion.animation(reduceMotion: reduceMotion)) { finished = true }
    }
}

// MARK: - Version 1

/// One story page's top: the emoji tile, the title and three emoji points. Each page is a fresh view (`.id`), so the
/// entrance plays once per page: the tile grows in, then the points drift up one after another. Slow, no-overshoot
/// ease-out (owner, 2026-10-22, twice: first "too quick and jerky", then "slower, so it reads"). The points wait
/// for the page's own slide, then come in 0.35s apart. Played only on arrival; Reduce Motion gets a plain fade.
private struct StoryPointsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: Int
    let section: HowItWorksContent.Section
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    @State private var shown = false

    private var tile: Color { [app.palette.honeyBg, app.palette.clayBg, app.palette.field, app.palette.honeyBg][page % 4] }

    /// easeOutQuint: starts gently moving and settles softly, with no bounce.
    private func motion(_ delay: Double, duration: Double = 1.0) -> Animation {
        reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.emoji)
                .font(.system(size: 42))
                .frame(width: 84, height: 84)
                .background(tile, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .scaleEffect(shown || reduceMotion ? 1 : 0.85)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -4))
                .opacity(shown ? 1 : 0)
                .animation(motion(0.2, duration: 1.1), value: shown)
                .padding(.top, 40)
                .accessibilityHidden(true)
            Text(app.T(section.vi, section.en))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)
                .accessibilityIdentifier("welcome.story.heading.\(page)")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.points.enumerated()), id: \.offset) { i, point in
                    HStack(spacing: 14) {
                        Text(point.emoji)
                            .font(.system(size: 24))
                            .frame(width: 46, height: 46)
                            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        Text(app.T(point.vi, point.en))
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(app.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown || reduceMotion ? 0 : 14)
                    .animation(motion(reduceMotion ? 0 : 0.7 + Double(i) * 0.35, duration: 1.0), value: shown)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("welcome.story.point.\(page).\(i)")
                }
            }
            .padding(.top, 4)
        }
        .onAppear { shown = true }
    }
}

// MARK: - Version 2

/// Title, the centred screen's caption, the swipeable deck, dots and a one-time swipe hint. Native paging:
/// `.viewAligned` snapping, `.scrollPosition` tracks the centred card, `.scrollTransition` scales/dims/blurs the
/// neighbours live while dragging. Light selection haptic on each snap.
private struct StoryDeckSection: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: Int
    let section: HowItWorksContent.Section
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    /// Swiping past the last screen moves on to the next section (nil on the last section, which ends the story).
    var onNext: (() -> Void)? = nil
    /// The last section: swiping past its last screen finishes the tour (a different, bouncing hint).
    var finishes = false
    @State private var active: Int? = 0
    @State private var swiped = false
    @State private var appeared = false
    @State private var deckWidth: CGFloat = 390
    /// Which screen was centred when the current drag began: only a drag that STARTS on the last screen may move on
    /// (the drag that lands on the last screen must not skip past it).
    @State private var dragStart: Int?

    private let gap: CGFloat = 14
    /// Owner, 2026-10-24: "large, clear, easy to read": the centred screen takes ~3/4 of the width.
    private var cardWidth: CGFloat { min(deckWidth * 0.76, 330) }
    private var cardHeight: CGFloat { cardWidth * 1.3 }
    private var current: Int { min(max(active ?? 0, 0), section.cards.count - 1) }

    private func motion(_ delay: Double, duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(section.emoji + " ") + Text(app.T(section.vi, section.en)))
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 14)
                .animation(motion(0, duration: 0.8), value: appeared)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)
                .accessibilityIdentifier("welcome.story.heading.\(page)")

            let card = section.cards[current]
            Text(app.T(card.vi, card.en))
                .font(.system(.body, design: .rounded))
                .foregroundStyle(app.palette.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
                .padding(.top, 8)
                .id("caption.\(current)")
                .transition(.opacity)
                .accessibilityIdentifier("hiw.caption")

            deck
                .overlay(alignment: .trailing) {
                    if onNext != nil, current == section.cards.count - 1 {
                        Group {
                            if finishes { FinishHint() } else { NextSectionHint() }
                        }
                        .padding(.trailing, -16).transition(.opacity)
                    }
                }
                .padding(.horizontal, -24)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared || reduceMotion ? 0 : 90)
                .animation(motion(0.2, duration: 1.0), value: appeared)

            HStack(spacing: 6) {
                ForEach(section.cards.indices, id: \.self) { i in
                    Capsule().fill(app.palette.ink.opacity(i == current ? 0.85 : 0.2))
                        .frame(width: i == current ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.35), value: current)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(app.T("Màn \(current + 1)/\(section.cards.count)", "Screen \(current + 1) of \(section.cards.count)"))
            .accessibilityIdentifier("hiw.dots")

            Text(app.T("Vuốt để xem tiếp ⟶", "Swipe to see more ⟶"))
                .font(.caption.weight(.semibold))
                .opacity(swiped ? 0 : 0.55)
                .animation(.easeOut(duration: 0.4), value: swiped)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .onAppear { appeared = true }
        .onChange(of: active) { _, new in
            Haptics.selection()
            if (new ?? 0) > 0 { swiped = true }
        }
        .animation(.easeOut(duration: 0.25), value: current)
    }

    private var deck: some View {
        let still = reduceMotion // captured: the scrollTransition closure is Sendable
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: gap) {
                ForEach(section.cards.indices, id: \.self) { i in
                    DemoCard(card: section.cards[i], active: i == current)
                        .frame(width: cardWidth, height: cardHeight)
                        .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(app.palette.rule))
                        .shadow(color: .black.opacity(0.13), radius: 20, y: 14)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            let d = min(abs(phase.value), 1)
                            return content
                                .scaleEffect(still ? 1 : 1 - 0.14 * d)
                                .opacity(1 - 0.55 * d)
                                .blur(radius: still ? 0 : 3 * d)
                        }
                        .allowsHitTesting(i == current)
                        .accessibilityHidden(i != current)
                        .accessibilityElement(children: .contain) // keep the demo controls' own identifiers
                        .accessibilityIdentifier("hiw.card.\(i)")
                        .id(i)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 12).padding(.bottom, 22)
        }
        .contentMargins(.horizontal, max((deckWidth - cardWidth) / 2, 0), for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $active, anchor: .center)
        .frame(height: cardHeight + 46)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { deckWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in deckWidth = w }
        })
        .simultaneousGesture(DragGesture(minimumDistance: 24).onChanged { _ in
            if dragStart == nil { dragStart = current }
        }.onEnded { v in
            // On the last screen, a clear left swipe continues to the next section (Next stays the main way).
            let startedOn = dragStart
            dragStart = nil
            guard let onNext, startedOn == section.cards.count - 1,
                  v.translation.width < -60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            Haptics.light()
            onNext()
        })
        .accessibilityIdentifier("hiw.deck")
    }
}

/// Owner, 2026-10-24: the very last screen of the tour gets its own cue: a small clay "done" pill with a check that
/// bounces (a springy hop, not the grey chevron's slow pulse), saying "swipe to finish". Reduce Motion: still.
private struct FinishHint: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hop = false
    private var still: Bool { reduceMotion || !loopsMotion }
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy))
            Image(systemName: "chevron.compact.right").font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(app.palette.clay)
        .frame(width: 34, height: 72)
        .background(app.palette.clayBg, in: Capsule())
        .overlay(Capsule().stroke(app.palette.clay.opacity(0.35)))
        .scaleEffect(still ? 1 : (hop ? 1.08 : 0.94))
        .offset(x: still ? 0 : (hop ? -7 : 1))
        .onAppear {
            guard !still else { return }
            withAnimation(.interpolatingSpring(stiffness: 170, damping: 9).repeatForever(autoreverses: true).delay(0.2)) { hop = true }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(app.T("Vuốt để hoàn tất", "Swipe to finish"))
        .accessibilityIdentifier("hiw.finishHint")
    }
}

/// Owner, 2026-10-24: on the last screen of a section, a soft grey chevron pulses at the right edge to say "swipe on
/// to the next section". Decorative; Next stays. Reduce Motion: shown still.
private struct NextSectionHint: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    private var still: Bool { reduceMotion || !loopsMotion }
    var body: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(app.palette.ink.opacity(0.35))
            .frame(width: 30, height: 64)
            .background(app.palette.ink.opacity(0.06), in: Capsule())
            .opacity(still ? 0.8 : (pulse ? 0.95 : 0.35))
            .offset(x: still ? 0 : (pulse ? -4 : 2))
            .onAppear {
                guard !still else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
            }
            .allowsHitTesting(false)
            .accessibilityLabel(app.T("Vuốt để sang phần tiếp theo", "Swipe to the next section"))
            .accessibilityIdentifier("hiw.nextSectionHint")
    }
}

// MARK: - Demo screens
// Self-contained mocks built from the bundled catalogue (no live data, nothing is saved). The few controls inside
// (interest tiles, ticket count, organizer switch) only change the mock. `active` starts each screen's animation.
// Owner, 2026-10-24: every screen fills its card with large, readable content (no big empty gaps): bigger type,
// bigger photos, and an extra useful row where a screen used to float in white space.

/// Endless decorations (pulse, countdown, money flow) hold still under UI tests: XCUITest waits for an idle app,
/// which never comes while something loops. Same still state as Reduce Motion.
private var loopsMotion: Bool {
    #if DEBUG
    if UITestFixture.isActive { return false }
    #endif
    return true
}

private let gold = Color(red: 0.80, green: 0.62, blue: 0.16)
private let liveGreen = Color(red: 0.235, green: 0.604, blue: 0.373)

private enum Demo {
    static var events: [CatalogEvent] { EventCatalog.all }
    static func event(_ i: Int) -> CatalogEvent? { events.isEmpty ? nil : events[i % events.count] }
    static func price(_ e: CatalogEvent?) -> Int { Int((e?.price ?? "").filter(\.isNumber)) ?? 0 }
    static func vnd(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "vi_VN")
        return (f.string(from: NSNumber(value: n)) ?? "\(n)") + "₫"
    }
    static func when(_ e: CatalogEvent?) -> String { (e?.when ?? "").replacingOccurrences(of: "▪︎", with: "·") }
    static func area(_ e: CatalogEvent?) -> String {
        ((e?.where ?? "").components(separatedBy: "▪︎").first ?? "").trimmingCharacters(in: .whitespaces)
    }
}

/// Pops a small element in (scale 1.6 → 1, slight turn) once its screen is in the centre.
private struct Stamp: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    var delay: Double = 0
    func body(content: Content) -> some View {
        content
            .scaleEffect(active || reduceMotion ? 1 : 1.6)
            .rotationEffect(.degrees(active || reduceMotion ? 0 : -8))
            .opacity(active ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.55).delay(delay), value: active)
    }
}

private extension View {
    func stamp(_ active: Bool, delay: Double = 0) -> some View { modifier(Stamp(active: active, delay: delay)) }
}

private struct DemoCard: View {
    let card: HowItWorksContent.Card
    let active: Bool
    var body: some View {
        switch card.kind {
        case .quiz: QuizDemo()
        case .stars: StarsDemo(active: active)
        case .private: PrivateDemo()
        case .tickets: TicketsDemo()
        case .hold: HoldDemo(active: active)
        case .pay: PayDemo()
        case .qr: QrDemo(active: active)
        case .organizer: OrganizerDemo()
        case .free: FreeDemo()
        case .direct: DirectDemo(active: active)
        case .step: StepDemo(n: card.step, active: active)
        case .recipe: RecipeDemo(active: active)
        case .live: LiveDemo(active: active)
        }
    }
}

private struct DemoLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .bold)).kerning(0.6).opacity(0.55)
    }
}

/// A field-coloured row, the basic building block of the mocks.
private struct FieldBox<Content: View>: View {
    @EnvironmentObject private var app: AppState
    var fill: Color? = nil
    /// Grow to share the card's free height (the box itself grows, so there are no empty gaps between rows).
    var stretch = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 10) { content() }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .leading)
            .background(fill ?? app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ForYouChip: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(gold)
            Text(app.T("Dành cho bạn", "For You")).font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(app.palette.paper, in: Capsule())
        .overlay(Capsule().stroke(gold.opacity(0.7)))
    }
}

private struct DemoPad<Content: View>: View {
    var spacing: CGFloat = 12
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: alignment, spacing: spacing) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The REAL onboarding interests question (owner, 2026-10-24: "use the actual question screen with the current
/// categories"): the same top bar, title, subtitle, emoji tiles (EventPrefTaxonomy.interests) and Continue button as
/// OnboardingQuestionView, laid out at phone width and scaled down into the card. Tiles toggle; nothing is saved.
private struct QuizDemo: View {
    @EnvironmentObject private var app: AppState
    @State private var picked: Set<String> = ["supper", "gallery"]
    private let phoneWidth: CGFloat = 390

    var body: some View {
        GeometryReader { geo in
            // Guard the first layout pass (width 0): never divide by zero.
            let scale = max(geo.size.width, 1) / phoneWidth
            VStack(alignment: .leading, spacing: 0) {
                OnboardingTopBar(step: 2, onBack: {}, onSkip: {})
                    .padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 10) {
                    Text("🎟️").font(.system(size: 52)).accessibilityHidden(true)
                    Text(app.T("Loại sự kiện nào hợp với bạn?", "Which kinds of events are you into?"))
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(app.T("Chỉ những loại bạn chọn được gắn ★.", "Only the kinds you pick get the ★."))
                        .font(.subheadline).foregroundStyle(app.palette.ink.opacity(0.7))
                        .padding(.bottom, 12)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(EventPrefTaxonomy.interests) { o in
                            OnboardingChoiceRow(title: app.isEN ? o.en : o.vi, emoji: PrefEmoji.of(o.id), tile: true,
                                                selected: picked.contains(o.id), identifier: "hiw.quiz.\(o.id)") {
                                if picked.contains(o.id) { picked.remove(o.id) } else { picked.insert(o.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20)
                Spacer(minLength: 0)
            }
            .frame(width: phoneWidth, height: max(geo.size.height, 1) / scale, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                // The Continue button sits over the tiles like the real screen's bottom bar.
                InkButton(title: app.T("Tiếp tục", "Continue")) {}
                    .allowsHitTesting(false)
                    .padding(.horizontal, 24).padding(.vertical, 18)
                    .background(LinearGradient(colors: [app.palette.paper.opacity(0), app.palette.paper], startPoint: .top, endPoint: .center))
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

private struct StarsDemo: View {
    @EnvironmentObject private var app: AppState
    let active: Bool
    var body: some View {
        DemoPad(spacing: 0) {
            HStack {
                DemoLabel(text: app.T("Trang chủ", "Home"))
                Spacer()
                ForYouChip().opacity(0.9)
            }
            .padding(.bottom, 6)
            ForEach(Array([0, 5, 2].enumerated()), id: \.offset) { i, idx in
                let e = Demo.event(idx)
                HStack(spacing: 12) {
                    CatalogPhoto(path: e?.img ?? "", height: 76, width: 76, cornerRadius: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e?.name ?? "").font(.system(size: 16.5, weight: .bold)).lineLimit(1)
                        Text("\(Demo.when(e)) · \(Demo.area(e))").font(.system(size: 13)).opacity(0.6).lineLimit(1)
                        if i != 1 {
                            ForYouChip().stamp(active, delay: 0.25 + Double(i) * 0.3).padding(.top, 2)
                        } else {
                            Text(e?.price ?? "").font(.system(size: 13, weight: .semibold)).opacity(0.75).padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                if i < 2 { Divider().overlay(app.palette.rule) }
            }
        }
    }
}

private struct PrivateDemo: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        DemoPad(spacing: 12) {
            HStack(spacing: 14) {
                Text("🔒").font(.system(size: 40)).frame(width: 78, height: 78)
                    .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.T("Câu trả lời", "Your answers")).font(BanbeTheme.display(24))
                    Text(app.T("Riêng tư, chỉ mình bạn", "Private, just for you")).font(.system(size: 14)).opacity(0.65)
                }
            }
            .padding(.bottom, 4)
            FieldBox(stretch: true) { Text("🙈"); Text(app.T("Host không bao giờ thấy", "Hosts never see them")) }
            FieldBox(stretch: true) { Text("✏️"); Text(app.T("Đổi trong Tài khoản", "Change them in Account")) }
            FieldBox(stretch: true) { Text("⭐"); Text(app.T("Chỉ dùng để gắn ★ cho bạn", "Only used to star picks for you")) }
        }
    }
}

private struct TicketsDemo: View {
    @EnvironmentObject private var app: AppState
    @State private var n = 2
    var body: some View {
        let e = Demo.event(0)
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                CatalogPhoto(path: e?.img ?? "", height: geo.size.height * 0.36, width: geo.size.width, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e?.name ?? "").font(.system(size: 18, weight: .bold))
                        Text("\(Demo.when(e)) · \(Demo.vnd(Demo.price(e)))").font(.system(size: 13.5)).opacity(0.6)
                    }
                    HStack(spacing: 8) {
                        ForEach(1...3, id: \.self) { k in
                            Button {
                                Haptics.selection()
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)) { n = k }
                            } label: {
                                Text("\(k) " + app.T("vé", k == 1 ? "ticket" : "tickets"))
                                    .font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .foregroundStyle(n == k ? app.palette.paper : app.palette.ink)
                                    .background(n == k ? app.palette.ink : app.palette.field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(n == k ? .isSelected : [])
                            .accessibilityIdentifier("hiw.tickets.\(k)")
                        }
                    }
                    FieldBox(fill: app.palette.honeyBg) {
                        Text("⏱️")
                        Text(app.T("Giữ chỗ 30 phút khi bạn thanh toán", "Held 30 min while you pay")).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(app.T("Tổng", "Total")).font(.system(size: 12.5)).opacity(0.55)
                            Text(Demo.vnd(Demo.price(e) * n)).font(.system(size: 22, weight: .heavy))
                                .contentTransition(.numericText()).accessibilityIdentifier("hiw.tickets.total")
                        }
                        Spacer()
                        Text(app.T("Giữ chỗ", "Hold seats")).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(app.palette.clay, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
        }
    }
}

private struct HoldDemo: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    private let total = 30 * 60
    @State private var left = 30 * 60 - 1
    var body: some View {
        let e = Demo.event(0)
        DemoPad(spacing: 14, alignment: .center) {
            DemoLabel(text: app.T("Đang giữ chỗ cho bạn", "Seat held for you"))
            ZStack {
                Circle().stroke(app.palette.field, lineWidth: 14)
                Circle().trim(from: 0, to: CGFloat(left) / CGFloat(total))
                    .stroke(app.palette.clay, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                VStack(spacing: 2) {
                    Text(String(format: "%02d:%02d", left / 60, left % 60))
                        .font(.system(size: 40, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityIdentifier("hiw.hold.clock")
                    Text(app.T("còn lại", "left")).font(.system(size: 13, weight: .semibold)).opacity(0.55)
                }
            }
            .frame(maxWidth: 190, maxHeight: 190)
            .frame(maxHeight: .infinity)
            FieldBox {
                CatalogPhoto(path: e?.img ?? "", height: 40, width: 40, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e?.name ?? "").font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(app.T("2 vé · thanh toán trước khi hết giờ", "2 tickets · pay before time runs out"))
                        .font(.system(size: 12.5)).opacity(0.65).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .task(id: active) {
            left = total - 1
            guard active, !reduceMotion, loopsMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                withAnimation { left = left > 0 ? left - 1 : total - 1 }
            }
        }
    }
}

private struct PayDemo: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        let e = Demo.event(0)
        DemoPad(spacing: 12) {
            DemoLabel(text: app.T("Chuyển khoản cho host", "Transfer to the host"))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(e?.orgName ?? "").font(.system(size: 13.5, weight: .semibold)).opacity(0.75)
                    Spacer()
                    Image(systemName: "building.columns").font(.system(size: 15)).opacity(0.75)
                }
                Text("VCB •••• 6543").font(.system(size: 19, weight: .bold)).kerning(1)
                Text(Demo.vnd(Demo.price(e) * 2)).font(.system(size: 30, weight: .heavy)).padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.17, green: 0.16, blue: 0.16), Color(red: 0.33, green: 0.32, blue: 0.29)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 10)
            FieldBox {
                Text(app.T("Nội dung", "Note")).opacity(0.6)
                Text("BB-4821").bold()
                Spacer()
                Image(systemName: "doc.on.doc").font(.system(size: 14)).opacity(0.55)
            }
            FieldBox(fill: app.palette.clayBg) {
                Text("⏱️")
                Text(app.T("Chỗ còn giữ 28:41", "Seat still held 28:41")).monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(app.T("Tôi đã chuyển khoản", "I've transferred")).font(.system(size: 16, weight: .bold))
                .foregroundStyle(app.palette.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

private struct QrDemo: View {
    @EnvironmentObject private var app: AppState
    let active: Bool
    /// A fixed, made-up QR-like pattern (finder squares + noise). Not a real code.
    private static let bits: [Bool] = (0..<121).map { (($0 * 7919) % 13) % 3 == 0 }
    var body: some View {
        let e = Demo.event(0)
        DemoPad(spacing: 12, alignment: .center) {
            DemoLabel(text: app.T("Vé của bạn", "Your ticket"))
            Canvas { ctx, size in
                let cell = size.width / 11
                for i in 0..<121 {
                    let x = i % 11, y = i / 11
                    let finder = (x < 3 && y < 3) || (x > 7 && y < 3) || (x < 3 && y > 7)
                    let on = finder ? (x % 2 == 0 || y % 2 == 0) : Self.bits[i]
                    if on { ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(Color(white: 0.11))) }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 150, maxHeight: .infinity)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 6)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(e?.name ?? "").font(.system(size: 17, weight: .bold))
                Text(Demo.when(e)).font(.system(size: 13)).opacity(0.6)
            }
            HStack(spacing: 6) {
                ForEach(Array([("T5", "Thu"), ("T6", "Fri"), ("T7", "Sat"), ("CN", "Sun")].enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 5) {
                        Text(app.T(d.0, d.1)).font(.system(size: 13, weight: .semibold))
                        Circle().fill(app.palette.clay).frame(width: 9, height: 9)
                            .opacity(i == 2 ? 1 : 0)
                            .stamp(active && i == 2, delay: 0.5)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(i == 2 ? app.palette.honeyBg : app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

private struct OrganizerDemo: View {
    @EnvironmentObject private var app: AppState
    @State private var on = false
    var body: some View {
        DemoPad(spacing: 12) {
            DemoLabel(text: app.T("Tài khoản", "Account"))
            HStack(spacing: 12) {
                Image("BanbeFavicon").resizable().scaledToFill()
                    .frame(width: 46, height: 46).clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.T("Bạn", "You")).font(.system(size: 17, weight: .bold))
                    Text(on ? app.T("Cá nhân · Host", "Personal · Host") : app.T("Cá nhân", "Personal"))
                        .font(.system(size: 13)).opacity(0.6)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                row("person.crop.circle", app.T("Hồ sơ", "Profile")) { chevron }
                Divider().overlay(app.palette.rule).padding(.leading, 46)
                row("music.mic", app.T("Chế độ tổ chức", "Organizer mode")) {
                    Toggle("", isOn: Binding(get: { on }, set: { v in Haptics.light(); withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)) { on = v } }))
                        .labelsHidden().tint(app.palette.clay)
                        .accessibilityLabel(app.T("Chế độ tổ chức", "Organizer mode"))
                        .accessibilityIdentifier("hiw.organizer.switch")
                }
                Divider().overlay(app.palette.rule).padding(.leading, 46)
                row("questionmark.circle", app.T("Trợ giúp", "Help")) { chevron }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Host tools: dimmed until the switch is on, then they light up. Fills the rest of the card.
            VStack(alignment: .leading, spacing: 10) {
                Text(on ? app.T("✨ Đã mở công cụ host", "✨ Host tools on") : app.T("Bật để mở công cụ host", "Turn it on for host tools"))
                    .font(.system(size: 14, weight: .bold)).opacity(on ? 1 : 0.6)
                HStack(spacing: 8) {
                    tool("plus.circle", app.T("Tạo", "Create"))
                    tool("person.2", app.T("Khách", "Guests"))
                    tool("qrcode.viewfinder", app.T("Soát vé", "Check-in"))
                }
                .frame(maxHeight: .infinity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(on ? app.palette.clayBg : app.palette.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(app.palette.ink.opacity(on ? 0 : 0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).opacity(0.35)
    }

    private func row<T: View>(_ icon: String, _ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 26)
            Text(title).font(.system(size: 15.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    }

    private func tool(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(app.palette.paper.opacity(on ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(on ? 1 : 0.45)
    }
}

private struct FreeDemo: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        DemoPad(spacing: 12) {
            DemoLabel(text: app.T("Phí cho host", "Host fees"))
            VStack(alignment: .leading, spacing: 0) {
                Text("0₫").font(BanbeTheme.display(80)).kerning(-2)
                Text(app.T("để đăng và bán vé", "to list and sell tickets")).font(.system(size: 15, weight: .semibold)).opacity(0.7)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            FieldBox { Text(app.T("Phí đăng", "Listing fee")); Spacer(); Text("0₫").bold() }
            FieldBox { Text(app.T("Phí giao dịch", "Transaction fee")); Spacer(); Text("0₫").bold() }
            FieldBox(fill: app.palette.clayBg) { Text(app.T("Bạn nhận", "You receive")); Spacer(); Text("100%").bold() }
        }
        .background(LinearGradient(colors: [app.palette.honeyBg, .clear], startPoint: .top, endPoint: .center))
    }
}

/// Guest → host money flow, top to bottom, with banbe standing aside (its real favicon as the avatar, owner
/// 2026-10-24). The 💸 travels down the line while the card is in the centre.
private struct DirectDemo: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    var body: some View {
        let amount = Demo.vnd(Demo.price(Demo.event(0)) * 2)
        let still = reduceMotion || !loopsMotion
        DemoPad(spacing: 0) {
            DemoLabel(text: app.T("Tiền đi thẳng", "Money goes direct"))
                .padding(.bottom, 14)
            person(Text("🙋").font(.system(size: 26)), app.palette.field,
                   app.T("Khách", "Guest"), app.T("Chuyển khoản \(amount)", "Transfers \(amount)"))
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Rectangle().fill(app.palette.ink.opacity(0.15)).frame(width: 2)
                    if active {
                        TimelineView(.animation(paused: still)) { tl in
                            let t = still ? 0.5 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                            Text("💸").font(.system(size: 22))
                                .offset(y: CGFloat(t) * max(geo.size.height - 26, 0))
                                .opacity(still ? 1 : min(1, min(t, 1 - t) * 6))
                        }
                    }
                }
                .frame(width: 52, height: geo.size.height)
            }
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 6)
            .overlay(alignment: .leading) {
                // What travels down the line, so it never reads as empty space.
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.T("Chuyển khoản ngân hàng", "Bank transfer")).font(.system(size: 14, weight: .bold))
                    Text(app.T("thẳng từ khách đến bạn,\nkhông qua trung gian", "straight from guest to you,\nno middleman"))
                        .font(.system(size: 13)).opacity(0.65)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .fixedSize()
                .offset(x: 64)
            }
            person(Text("🎤").font(.system(size: 26)), app.palette.clayBg,
                   app.T("Bạn (host)", "You (host)"), app.T("Nhận đủ \(amount)", "Receives all \(amount)"))
            HStack(spacing: 12) {
                Image("BanbeFavicon").resizable().scaledToFill()
                    .frame(width: 42, height: 42).clipShape(Circle())
                    .overlay(Circle().stroke(app.palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).padding(-4))
                    .padding(.leading, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("banbe · 0₫").font(.system(size: 15.5, weight: .bold))
                    Text(app.T("Chỉ kết nối, không giữ tiền", "Connects you, never holds money"))
                        .font(.system(size: 13)).opacity(0.65)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 16)
        }
    }

    private func person<A: View>(_ avatar: A, _ bg: Color, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            avatar.frame(width: 52, height: 52).background(bg, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 16.5, weight: .bold))
                Text(detail).font(.system(size: 13.5)).opacity(0.65).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StepRing: View {
    @EnvironmentObject private var app: AppState
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(app.palette.field, lineWidth: 6)
            Circle().trim(from: 0, to: value)
                .stroke(app.palette.clay, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9), value: value)
        }
        .frame(width: 54, height: 54)
    }
}

private struct StepDemo: View {
    @EnvironmentObject private var app: AppState
    let n: Int
    let active: Bool
    var body: some View {
        let e = Demo.event(n)
        let name = HowItWorksContent.stepNames[n - 1]
        DemoPad(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    StepRing(value: Double(active ? n : n - 1) / 5)
                    Text("\(n)/5").font(.system(size: 13, weight: .heavy))
                }
                VStack(alignment: .leading, spacing: 0) {
                    DemoLabel(text: app.T("Bước \(n)", "Step \(n)"))
                    Text(app.T(name.vi, name.en)).font(BanbeTheme.display(23))
                }
            }
            stepBody(e)
            if n < 5 {
                let tip = HowItWorksContent.stepTips[n - 1]
                Text("💡 " + app.T(tip.vi, tip.en))
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(i < n ? app.palette.clay : app.palette.field).frame(height: 5)
                }
            }
        }
    }

    /// Each step's fields stretch to fill the card (`maxHeight: .infinity`), so no step leaves a gap.
    @ViewBuilder
    private func stepBody(_ e: CatalogEvent?) -> some View {
        Group {
            switch n {
            case 1:
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image("BanbeFavicon").resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e?.orgName ?? "").font(.system(size: 16.5, weight: .bold))
                            Text(app.T("Host", "Host")).font(.system(size: 13)).opacity(0.6)
                        }
                        Spacer(minLength: 0)
                    }
                    FieldBox(stretch: true) { Text("📝"); Text(app.T("Giới thiệu ngắn về bạn", "A line about you")).opacity(0.75) }
                    FieldBox(stretch: true) { Text("📸"); Text(e?.orgIg.isEmpty == false ? e!.orgIg : "@banbe.host").opacity(0.75) }
                }
            case 2:
                VStack(alignment: .leading, spacing: 10) {
                    FieldBox(stretch: true) { Text(e?.name ?? "").bold() }
                    HStack(spacing: 6) {
                        ForEach(Array([("🍽️", "Supper club"), ("🎨", app.T("Nghệ thuật", "Art"))].enumerated()), id: \.offset) { i, c in
                            Text("\(c.0) \(c.1)").font(.system(size: 13.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .fixedSize(horizontal: i == 0, vertical: false)
                                .background(i == 0 ? app.palette.honeyBg : app.palette.field, in: Capsule())
                                .overlay(Capsule().stroke(i == 0 ? app.palette.ink : .clear, lineWidth: 1.5))
                        }
                    }
                    FieldBox(stretch: true) { Text(app.T("Bữa tối 6 món, 12 khách quanh một bàn dài.", "A 6-course dinner, 12 guests at one long table.")).opacity(0.75).lineLimit(2) }
                }
            case 3:
                VStack(spacing: 10) {
                    FieldBox(stretch: true) { Text("📅"); Text(Demo.when(e)) }
                    FieldBox(stretch: true) { Text("📍"); Text(Demo.area(e)) }
                    FieldBox(stretch: true) { Text("⏳"); Text(app.T("Khoảng 3 giờ", "About 3 hours")) }
                }
            case 4:
                VStack(spacing: 10) {
                    FieldBox(stretch: true) { Text(app.T("Giá", "Price")); Spacer(); Text(Demo.vnd(Demo.price(e))).bold() }
                    FieldBox(stretch: true) { Text(app.T("Số chỗ", "Seats")); Spacer(); Text("−   14   +").bold() }
                    FieldBox(stretch: true) { Text(app.T("Hoàn tiền", "Refunds")); Spacer(); Text(app.T("Trước 48 giờ", "Up to 48h before")).bold() }
                }
            default:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array([0, 1, 2, 4].enumerated()), id: \.offset) { i, k in
                        CatalogPhoto(path: Demo.event(k)?.img ?? "", height: 128, cornerRadius: 14)
                            .stamp(active, delay: Double(i) * 0.12)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .frame(maxHeight: n == 5 ? nil : .infinity)
    }
}

private struct RecipeDemo: View {
    @EnvironmentObject private var app: AppState
    let active: Bool
    private let items = [("📸", "Ảnh rõ, sáng", "Bright, clear photos"), ("🕖", "Giờ đẹp cuối tuần", "A good weekend slot"),
                         ("💬", "Lời mời ấm áp", "A warm opening line"), ("💰", "Giá hợp khu vực", "A fair local price")]
    var body: some View {
        DemoPad(spacing: 10) {
            DemoLabel(text: "🧑‍🍳 " + app.T("Công thức thành công", "Recipe for success"))
            HStack(alignment: .firstTextBaseline) {
                Text("8/10").font(BanbeTheme.display(30))
                Text(app.T("nguyên liệu", "ingredients")).font(.system(size: 14, weight: .semibold)).opacity(0.65)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(app.palette.field)
                    Capsule().fill(LinearGradient(colors: [app.palette.honey, app.palette.clay], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (active ? 0.8 : 0.1))
                        .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.6).delay(0.2), value: active)
                }
            }
            .frame(height: 14)
            ForEach(items.indices, id: \.self) { i in
                FieldBox(stretch: true) {
                    Text(items[i].0)
                    Text(app.T(items[i].1, items[i].2))
                    Spacer()
                    Text("✓").font(.system(size: 16, weight: .heavy)).foregroundStyle(app.palette.clay)
                        .stamp(active, delay: 0.4 + Double(i) * 0.22)
                }
            }
        }
    }
}

private struct LiveDemo: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var pulse = false
    private let steps = [("Đã gửi", "Submitted"), ("banbe đang duyệt", "banbe reviewing"), ("Đang mở bán", "Live")]
    var body: some View {
        DemoPad(spacing: 12) {
            ZStack(alignment: .topLeading) {
                GeometryReader { geo in
                    CatalogPhoto(path: Demo.event(0)?.img ?? "", height: geo.size.height, width: geo.size.width, cornerRadius: 16)
                }
                HStack(spacing: 6) {
                    Circle().fill(liveGreen).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(liveGreen.opacity(pulse ? 0 : 0.55), lineWidth: pulse ? 6 : 0))
                    Text(app.T("Đang mở", "Live")).font(.system(size: 13, weight: .heavy))
                }
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(app.palette.paper, in: Capsule())
                .padding(10)
                .stamp(active, delay: 1.3)
            }
            .frame(maxHeight: .infinity)
            ForEach(steps.indices, id: \.self) { i in
                HStack(spacing: 12) {
                    Text("✓").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(i == 2 ? liveGreen : app.palette.clay, in: Circle())
                        .stamp(active, delay: 0.2 + Double(i) * 0.5)
                    Text(app.T(steps[i].0, steps[i].1)).font(.system(size: 16, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            guard !reduceMotion, loopsMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

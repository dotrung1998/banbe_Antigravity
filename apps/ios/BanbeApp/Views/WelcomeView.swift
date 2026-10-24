import SwiftUI

/// Signed-out public entry (note 44). ONE concise welcome screen with
/// "Get started" (→ Sign up) and an equally visible "Log in" (→ Login, no
/// intermediate pages). "See how banbe works" opens 4 optional pages with
/// Back and Skip; never auto-advances, never required, never replayed
/// automatically. Requests no permissions and touches no personalization
/// markers. Note 63: the admin switch `onboarding_v2` picks Version 1 (still
/// welcome + text story) or Version 2 (animated entrance every time Welcome
/// opens + swipeable demo screens, HowBanbeWorksView.swift).
struct WelcomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var story = PublicStoryState()
    @State private var storySeen = PublicStoryMarker.hasSeen()
    @AccessibilityFocusState private var headingFocused: Bool
    /// V2 entrance plays when Welcome opens, not again when coming back from the story.
    @State private var entrance = true
    @State private var entered = false
    /// Owner, 2026-10-24: swiping past the very last demo screen finishes the tour with a thank-you.
    @State private var storyFinished = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.top, 8)
                Group {
                    if let page = story.page {
                        storyPage(page).id("story.\(page).\(storyFinished)")
                    } else {
                        welcome.id("welcome")
                    }
                }
                .transition(AuthMotion.transition(forward: story.forward, reduceMotion: reduceMotion))
            }
        }
        .foregroundStyle(app.palette.ink)
        .onAppear {
            Analytics.track(.publicEntryViewed)
            entered = true
        }
        .onChange(of: story.page) { _, _ in headingFocused = true; storyFinished = false }
    }

    private func move(_ change: () -> Void) {
        withAnimation(AuthMotion.animation(reduceMotion: reduceMotion), change)
    }

    // MARK: top bar (language / appearance always reachable)

    private var topBar: some View {
        HStack(spacing: 8) {
            if story.isOnStory {
                Button {
                    move { if storyFinished { storyFinished = false } else { story.back() } }
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.T("Quay lại", "Back"))
                .accessibilityIdentifier("welcome.story.back")
                Text(app.T("\((story.page ?? 0) + 1)/\(PublicStoryState.pageCount)",
                           "\((story.page ?? 0) + 1) of \(PublicStoryState.pageCount)"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
                    .accessibilityIdentifier("welcome.story.progress")
            }
            Spacer(minLength: 0)
            pill(app.T("EN", "VN"), id: "welcome.lang") { app.toggleLang() }
            pill(app.theme == "dark" ? app.T("Sáng", "Light") : app.T("Tối", "Dark"), id: "welcome.theme") {
                app.pickTheme(app.theme == "dark" ? "light" : "dark")
            }
            if story.isOnStory {
                Button {
                    Analytics.track(.publicStorySkipped(step: story.page ?? 0))
                    move { story.close() }
                } label: {
                    Text(app.T("Bỏ qua", "Skip")).font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(app.T("Đóng phần giới thiệu", "Closes the introduction"))
                .accessibilityIdentifier("welcome.story.skip")
            }
        }
    }

    private func pill(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(app.palette.field, in: Capsule())
                .overlay(Capsule().stroke(app.palette.rule))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: welcome

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WelcomeIllustration(animated: animatesEntrance)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                Text(app.T("Tìm những buổi gặp gỡ nhỏ đáng để đi", "Find small gatherings worth going to"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .padding(.top, 28)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("welcome.heading")
                    .riseIn(animatesEntrance, shown: entered, index: 0)
                Text(app.T("Supper club, triển lãm, nhạc và pop-up quanh bạn. Giữ chỗ chỉ trong vài chạm.",
                           "Supper clubs, galleries, music and pop-ups near you. Hold a seat in a few taps."))
                    .font(.body).lineSpacing(3)
                    .foregroundStyle(app.palette.ink.opacity(0.8))
                    .padding(.top, 10)
                    .riseIn(animatesEntrance, shown: entered, index: 1)

                ctas.padding(.top, 30)
                    .riseIn(animatesEntrance, shown: entered, index: 2)

                Button {
                    Analytics.track(.publicStoryOpened)
                    PublicStoryMarker.markSeen()
                    storySeen = true
                    entrance = false
                    move { story.open() }
                } label: {
                    Text(storySeen ? app.T("Xem lại banbe hoạt động thế nào", "How banbe works")
                                   : app.T("Xem banbe hoạt động thế nào", "See how banbe works"))
                        .font(storySeen ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                        .underline()
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .riseIn(animatesEntrance, shown: entered, index: 3)
                .accessibilityIdentifier("welcome.story.open")
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
    }

    /// Note 48 (reciprocity): "Explore events" first — real events before
    /// any ask — then Create account and Log in, both still one tap.
    private var ctas: some View {
        VStack(spacing: 10) {
            // Note 53, three clearly different levels: the solid primary is the one thing to do; Create account is
            // the quieter field-filled secondary (it used to be a same-size ink outline that read as a twin);
            // Log in is text only.
            InkButton(title: app.T("Khám phá sự kiện", "Explore events"), font: .headline) {
                app.browseAsGuest()
            }
            .accessibilityIdentifier("welcome.explore")
            SecondaryButton(title: app.T("Tạo tài khoản", "Create an account"), emoji: "✨") {
                Analytics.track(.publicEntryGetStarted)
                app.openAuth(.signup)
            }
            .accessibilityIdentifier("welcome.getStarted")
            Button {
                Analytics.track(.publicEntryLogin)
                app.openAuth(.login)
            } label: {
                (Text(app.T("Đã có tài khoản? ", "Already have an account? ")).foregroundColor(app.palette.ink.opacity(0.7))
                 + Text(app.T("Đăng nhập", "Log in")).bold().underline())
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(haptic: false))
            .accessibilityIdentifier("welcome.login")
        }
    }

    private var animatesEntrance: Bool { app.onboardingV2Enabled && entrance }

    // MARK: optional story

    private func storyPage(_ page: Int) -> some View {
        HowBanbeWorksBody(page: page, v2: app.onboardingV2Enabled, headingFocused: $headingFocused,
                          onNext: { move { story.next() } },
                          finished: storyFinished, onFinish: { move { storyFinished = true } }) {
            ctas.onAppear { Analytics.track(.publicStoryCompleted) }
        } footer: {
            ctas
        }
    }
}

/// Note 63, Version 2: the copy and buttons rise from the bottom after the illustration, ~90ms apart. Reduce Motion
/// gets a short fade with no travel. No-op when not animating (Version 1, or back from the story).
private struct WelcomeRise: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let enabled: Bool
    let shown: Bool
    let index: Int
    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 24)
                .animation(reduceMotion ? .easeOut(duration: 0.2)
                           : .timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(1.0 + Double(index) * 0.09), value: shown)
        } else {
            content
        }
    }
}

private extension View {
    func riseIn(_ enabled: Bool, shown: Bool, index: Int) -> some View {
        modifier(WelcomeRise(enabled: enabled, shown: shown, index: index))
    }
}

/// Decorative stack built from the bundled catalogue photos (the same art the feed ships offline) and the real For
/// You chip styling. Version 1: no motion at all. Version 2 (`animated`, note 63): the side photos slide in from
/// their own edge and swing into the fan, the middle one rises; then the For You chip arrives from below, lights up
/// gold and settles where it always sits. Reduce Motion: a short fade only. Web twin: Welcome.jsx (.bb-wel-*).
private struct WelcomeIllustration: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animated = false
    @State private var photosIn = false
    @State private var chipIn = false
    @State private var glow = false

    private var photos: [String] { Array(EventCatalog.all.prefix(3).map(\.img)) }
    private var still: Bool { !animated }

    private func ease(_ duration: Double, _ delay: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }

    var body: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, path in
                let placed = still || photosIn || reduceMotion
                let side = CGFloat(i - 1)
                CatalogPhoto(path: path, height: 150, width: 116, cornerRadius: 18)
                    .rotationEffect(.degrees(Double(i - 1) * 7 + (placed ? 0 : Double(side) * 16)))
                    .offset(x: CGFloat(i - 1) * 78 + (placed ? 0 : side * 320), y: (i == 1 ? -6 : 8) + (placed ? 0 : (i == 1 ? 50 : 30)))
                    .scaleEffect(placed || i != 1 ? 1 : 0.88)
                    .opacity(still || photosIn ? 1 : 0)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .zIndex(i == 1 ? 1 : 0)
                    .animation(ease(i == 1 ? 0.95 : 1.0, [0, 0.2, 0.08][i]), value: photosIn)
            }
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.80, green: 0.62, blue: 0.16))
                Text(app.T("Dành cho bạn", "For You")).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(app.palette.paper, in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.80, green: 0.62, blue: 0.16).opacity(0.7)))
            .shadow(color: Color(red: 0.80, green: 0.62, blue: 0.16).opacity(glow ? 0.6 : 0), radius: glow ? 16 : 0)
            .background(Capsule().stroke(Color(red: 0.80, green: 0.62, blue: 0.16).opacity(glow ? 0.28 : 0), lineWidth: glow ? 12 : 0))
            .scaleEffect(still || chipIn || reduceMotion ? 1 : 1.35)
            .offset(y: 86 + (still || chipIn || reduceMotion ? 0 : 56))
            .opacity(still || chipIn ? 1 : 0)
            .animation(ease(0.75, 0), value: chipIn)
            .zIndex(2)
        }
        .frame(height: 200)
        .onAppear {
            guard animated else { return }
            photosIn = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(750))
                chipIn = true
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.45)) { glow = true }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeOut(duration: 0.85)) { glow = false }
            }
        }
    }
}

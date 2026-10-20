import SwiftUI

/// Signed-out public entry (note 44). ONE concise welcome screen with
/// "Get started" (→ Sign up) and an equally visible "Log in" (→ Login, no
/// intermediate pages). "See how banbe works" opens at most two optional
/// pages with Back and Skip; never auto-advances, never required, never
/// replayed automatically. Requests no permissions and touches no
/// personalization markers.
struct WelcomeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var story = PublicStoryState()
    @State private var storySeen = PublicStoryMarker.hasSeen()
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.top, 8)
                Group {
                    if let page = story.page {
                        storyPage(page).id("story.\(page)")
                    } else {
                        welcome.id("welcome")
                    }
                }
                .transition(AuthMotion.transition(forward: story.forward, reduceMotion: reduceMotion))
            }
        }
        .foregroundStyle(app.palette.ink)
        .onAppear { Analytics.track(.publicEntryViewed) }
        .onChange(of: story.page) { _, _ in headingFocused = true }
    }

    private func move(_ change: () -> Void) {
        withAnimation(AuthMotion.animation(reduceMotion: reduceMotion), change)
    }

    // MARK: top bar (language / appearance always reachable)

    private var topBar: some View {
        HStack(spacing: 8) {
            if story.isOnStory {
                Button {
                    move { story.back() }
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
                WelcomeIllustration()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                Text(app.T("Tìm những buổi gặp gỡ nhỏ đáng để đi", "Find small gatherings worth going to"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .padding(.top, 28)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("welcome.heading")
                Text(app.T("Supper club, triển lãm, nhạc và pop-up quanh bạn. Giữ chỗ chỉ trong vài chạm.",
                           "Supper clubs, galleries, music and pop-ups near you. Hold a seat in a few taps."))
                    .font(.body).lineSpacing(3)
                    .foregroundStyle(app.palette.ink.opacity(0.8))
                    .padding(.top, 10)

                ctas.padding(.top, 30)

                Button {
                    Analytics.track(.publicStoryOpened)
                    PublicStoryMarker.markSeen()
                    storySeen = true
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

    // MARK: optional story

    private func storyPage(_ page: Int) -> some View {
        let content: (String, String, String) = page == 0
            ? ("🌟",
               app.T("Gợi ý hợp với bạn", "Picks that fit you"),
               app.T("Sau khi đăng ký, trả lời tối đa 5 câu hỏi (không bắt buộc). banbe gắn sao ★ Dành cho bạn cho những sự kiện phù hợp. Câu trả lời chỉ bạn thấy.",
                     "After you sign up, answer up to five optional questions. banbe stars ★ For You on events that match. Only you see your answers."))
            : ("🎟️",
               app.T("Giữ chỗ và theo dõi kế hoạch", "Hold a seat, keep your plans"),
               app.T("Giữ chỗ, thanh toán trực tiếp cho host và nhận vé QR khi host xác nhận. Kế hoạch của bạn hiện trong Lịch.",
                     "Hold a seat, pay the host directly, and get a QR ticket once they confirm. Your plans show up in Schedule."))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Note 53: an emoji tile per idea instead of another outline icon.
                Text(content.0)
                    .font(.system(size: 42))
                    .frame(width: 84, height: 84)
                    .background(page == 0 ? app.palette.honeyBg : app.palette.clayBg,
                                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                Text(content.1)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("welcome.story.heading.\(page)")
                Text(content.2).font(.body).lineSpacing(3)
                    .foregroundStyle(app.palette.ink.opacity(0.8))

                if story.isLastPage {
                    ctas.padding(.top, 24)
                        .onAppear { Analytics.track(.publicStoryCompleted) }
                } else {
                    InkButton(title: app.T("Tiếp", "Next"), font: .headline) { move { story.next() } }
                        .accessibilityIdentifier("welcome.story.next")
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
    }
}

/// Static decorative stack built from the bundled catalogue photos (the
/// same art the feed ships offline) and the real For You chip styling. No
/// motion at all.
private struct WelcomeIllustration: View {
    @EnvironmentObject private var app: AppState

    private var photos: [String] { Array(EventCatalog.all.prefix(3).map(\.img)) }

    var body: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, path in
                CatalogPhoto(path: path, height: 150, width: 116, cornerRadius: 18)
                    .rotationEffect(.degrees(Double(i - 1) * 7))
                    .offset(x: CGFloat(i - 1) * 78, y: i == 1 ? -6 : 8)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .zIndex(i == 1 ? 1 : 0)
            }
            HStack(spacing: 4) {
                Image(systemName: "star.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.80, green: 0.62, blue: 0.16))
                Text(app.T("Dành cho bạn", "For You")).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(app.palette.paper, in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.80, green: 0.62, blue: 0.16).opacity(0.7)))
            .offset(y: 86)
            .zIndex(2)
        }
        .frame(height: 200)
    }
}

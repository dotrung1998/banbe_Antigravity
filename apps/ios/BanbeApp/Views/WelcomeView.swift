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

    /// The optional story's pages: a short title and three emoji points each, instead of a paragraph (owner,
    /// 2026-10-21: "too much text"). Pages 3–4 introduce hosting and creating an event.
    /// Web twin: the `pages` array in src/screens/Welcome.jsx.
    private var storyPages: [StoryPageContent] {
        [
            StoryPageContent(emoji: "🌟", title: app.T("Gợi ý hợp với bạn", "Picks that fit you"), points: [
                ("✍️", app.T("Trả lời 5 câu ngắn, không bắt buộc", "Answer 5 quick, optional questions")),
                ("⭐", app.T("banbe gắn ★ Dành cho bạn lên sự kiện hợp", "banbe stars ★ For You on events that fit")),
                ("🔒", app.T("Chỉ mình bạn thấy câu trả lời", "Only you see your answers")),
            ]),
            StoryPageContent(emoji: "🎟️", title: app.T("Giữ chỗ trong vài chạm", "Hold a seat in a few taps"), points: [
                ("⏱️", app.T("Giữ chỗ 30 phút để bạn thanh toán", "Your seat is held 30 minutes while you pay")),
                ("💸", app.T("Chuyển khoản thẳng cho host", "Pay the host directly")),
                ("📲", app.T("Nhận vé QR, kế hoạch hiện trong Lịch", "Get a QR ticket, plans land in Schedule")),
            ]),
            StoryPageContent(emoji: "🎤", title: app.T("Tự tổ chức sự kiện", "Host your own events"), points: [
                ("⚙️", app.T("Bật Chế độ tổ chức trong Tài khoản", "Turn on Organizer mode in Account")),
                ("🆓", app.T("Miễn phí: không phí đăng, không phí giao dịch", "Free: no listing or transaction fees")),
                ("🤝", app.T("Khách trả thẳng cho bạn, banbe không giữ tiền", "Guests pay you, banbe never holds money")),
            ]),
            StoryPageContent(emoji: "🛠️", title: app.T("Tạo sự kiện trong 5 bước", "Create an event in 5 steps"), points: [
                ("📝", app.T("Host → Cơ bản → Thời gian & nơi → Vé → Ảnh", "Host → Basics → When & where → Tickets → Photos")),
                ("🧑‍🍳", app.T("Công thức thành công gợi ý cách lấp đầy chỗ", "The Recipe for success helps fill seats")),
                ("✅", app.T("banbe duyệt rồi đưa lên sóng, báo cho bạn", "banbe reviews it, then it goes live")),
            ]),
        ]
    }

    private func storyTileBackground(_ page: Int) -> Color {
        [app.palette.honeyBg, app.palette.clayBg, app.palette.field, app.palette.honeyBg][page % 4]
    }

    private func storyPage(_ page: Int) -> some View {
        let content = storyPages[min(max(page, 0), storyPages.count - 1)]
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StoryPointsView(page: page, content: content, tile: storyTileBackground(page),
                                headingFocused: $headingFocused)

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

struct StoryPageContent {
    let emoji: String
    let title: String
    let points: [(emoji: String, text: String)]
}

/// One story page's top: the emoji tile, the title and three emoji points. Each page is a fresh view (`.id`), so the
/// entrance plays once per page: the tile grows in, then the points drift up one after another. Slow, no-overshoot
/// ease-out (owner, 2026-10-22, twice: first "too quick and jerky", then "slower, so it reads"). The points wait
/// for the page's own slide, then come in 0.35s apart. Played only on arrival; Reduce Motion gets a plain fade.
private struct StoryPointsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: Int
    let content: StoryPageContent
    let tile: Color
    var headingFocused: AccessibilityFocusState<Bool>.Binding
    @State private var shown = false

    /// easeOutQuint: starts gently moving and settles softly, with no bounce.
    private func motion(_ delay: Double, duration: Double = 1.0) -> Animation {
        reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.emoji)
                .font(.system(size: 42))
                .frame(width: 84, height: 84)
                .background(tile, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .scaleEffect(shown || reduceMotion ? 1 : 0.85)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -4))
                .opacity(shown ? 1 : 0)
                .animation(motion(0.2, duration: 1.1), value: shown)
                .padding(.top, 40)
                .accessibilityHidden(true)
            Text(content.title)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(headingFocused)
                .accessibilityIdentifier("welcome.story.heading.\(page)")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(content.points.enumerated()), id: \.offset) { i, point in
                    HStack(spacing: 14) {
                        Text(point.emoji)
                            .font(.system(size: 24))
                            .frame(width: 46, height: 46)
                            .background(app.palette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        Text(point.text)
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

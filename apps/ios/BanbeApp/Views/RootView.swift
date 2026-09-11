import SwiftUI

/// Top-level screen switch and sheet host — the iOS equivalent of the
/// SCREENS map and sheet layer in src/App.jsx. One screen shows at a time,
/// with explicit back targets, exactly as the web app does it.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    // Live-follows the finger while an edge swipe is in progress, the same
    // way UIKit's interactivePopGestureRecognizer drags the current view
    // along with the touch instead of just reacting once the gesture ends.
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var isCommittingBack = false

    private var dragProgress: CGFloat {
        guard !isCommittingBack else { return 1 }
        let width = UIScreen.main.bounds.width
        return width > 0 ? min(1, dragTranslation / width) : 0
    }

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard app.canSwipeBack, value.startLocation.x < 32 else { return }
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                guard app.canSwipeBack, value.startLocation.x < 32,
                      abs(value.translation.height) < 80
                else { return }
                // A firm flick commits even if it hasn't crossed the
                // halfway mark yet — matches how forgiving the system
                // gesture is about a fast, short swipe.
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.35
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    withAnimation(.easeOut(duration: 0.22)) { isCommittingBack = true }
                }
            }
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()

            ZStack {
                switch app.screen {
                case .splash: SplashView()
                case .langPick: LangPickView()
                case .themePick: ThemePickView()
                case .home: HomeView()
                case .profile: AccountView()
                case .inbox: InboxView()
                case .event: EventDetailView()
                case .organizer: OrganizerView()
                case .reserve: ReserveView()
                case .confirmed: ConfirmedView()
                case .refunded: RefundedView()
                case .login: LoginView()
                case .chat: ChatView()
                case .dashboard: DashboardView()
                case .hostIntro: HostIntroView()
                case .create: CreateEventView()
                case .attendance: AttendanceView()
                case .preferences: PreferencesView()
                case .editName: EditNameView()
                case .notifications: NotificationsView()
                case .eventList: EventListView()
                }
            }
            // Every screen change — swiped back, tapped back, or pushed
            // forward — cross-fades with a slight horizontal drift instead
            // of the previous hard cut, which is most of what made it feel
            // unlike a native push/pop.
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            ))
            .animation(isCommittingBack || dragTranslation > 0 ? nil : .easeInOut(duration: 0.28), value: app.screen)
            // Follows the finger 1:1 during the drag, then either finishes
            // the slide off-screen (commit) or springs back to place
            // (cancel) — the same two outcomes the system gesture has.
            .offset(x: isCommittingBack ? UIScreen.main.bounds.width : dragTranslation)
            // Depth cue on the dragged edge, same as UIKit's pop shadow —
            // the plain paper the outer ZStack already paints behind this
            // is enough to read as "the previous page" peeking through.
            .shadow(color: .black.opacity(dragProgress * 0.16), radius: 16, x: -6, y: 0)

            // Names the current screen for UI tests, the same way the web
            // screens carry a data-screen-label attribute for Playwright.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("screen.\(app.screen.rawValue)")

            if app.areaAsking { AreaSheetView() }
            if app.askingLocation { LocationSheetView() }
            if app.reasonPrompt != nil { ReasonSheetView() }
            if app.loading { loadingOverlay }

            // Face ID app-lock sits above everything — see FaceIDLockView.
            if auth.isLocked { FaceIDLockView() }
        }
        .animation(.easeInOut(duration: 0.2), value: app.areaAsking)
        .animation(.easeInOut(duration: 0.2), value: app.askingLocation)
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: dragTranslation)
        // The screen switch above is a plain ZStack, not a NavigationStack,
        // so it never got the system's edge-swipe-to-go-back for free —
        // this reproduces it, tracking the finger live rather than jumping
        // only once the gesture ends.
        .gesture(edgeSwipe)
        .onChange(of: isCommittingBack) { _, committing in
            guard committing else { return }
            // Let the slide-off animation actually play before switching
            // screens, then reset instantly — the incoming screen is a
            // different view entirely, so there's nothing to visibly snap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                app.goBack()
                isCommittingBack = false
            }
        }
        .preferredColorScheme(app.theme == "dark" ? .dark : .light)
        .fullScreenCover(isPresented: $app.scanningQr) { QRScannerView() }
        // The session is owned by AuthViewModel (it also drives the Face ID
        // lock); AppState mirrors it into the profile/bookings/notifications
        // the screens read.
        .task(id: auth.session?.user.id) { await app.applySession(auth.session) }
        .onChange(of: auth.session?.user.id) { _, _ in
            // Signing in from a gated screen returns to whatever asked for it.
            if auth.session != nil && app.screen == .login { app.screen = app.authReturnScreen }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            app.palette.paper.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 14) {
                // src/screens/Loading.jsx tumbles the mark while it waits.
                BanbeLogo(kind: .mark, width: 54, height: 54)
                ProgressView()
                Text(app.T("Đang giữ chỗ cho bạn…", "Holding your seat…"))
                    .font(.system(size: 13))
                    .foregroundStyle(app.palette.ink)
            }
        }
    }
}

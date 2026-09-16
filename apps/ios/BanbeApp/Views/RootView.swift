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
    // A plain @State (not @GestureState) so every touch update can apply
    // with NO implicit animation — layering a spring on top of an already
    // continuous, per-frame gesture value is what was making the drag feel
    // laggy, since it was smoothing toward a target that kept moving.
    @State private var dragTranslation: CGFloat = 0
    @State private var isCommittingBack = false
    @State private var isDragTracking = false

    // How far in from the leading edge a swipe can originate — matches the
    // HIG's own edge-swipe affordance width. `edgeSwipe` below is attached
    // only to a strip this wide (see the `Color.clear` in `body` carrying
    // `.highPriorityGesture(edgeSwipe)`), not the whole screen — attaching
    // it everywhere (`.simultaneousGesture` on the full ZStack, the
    // previous approach) put it in constant arbitration with every screen's
    // own ScrollView for every touch on screen, which is exactly what made
    // a normal-speed partial swipe sometimes get swallowed by the scroll
    // view's pan recognizer instead — only a slow drag, or one dragged
    // nearly the full width, gave this gesture enough of a window to still
    // win that arbitration. Bounding its hit-testing region to a thin edge
    // strip means a touch that starts outside it is never routed to this
    // recognizer at all, so there's nothing left to arbitrate against the
    // ScrollView beneath it.
    private let edgeSwipeZoneWidth: CGFloat = 20

    private var dragProgress: CGFloat {
        guard !isCommittingBack else { return 1 }
        let width = UIScreen.main.bounds.width
        return width > 0 ? min(1, dragTranslation / width) : 0
    }

    private var edgeSwipe: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if !isDragTracking {
                    guard app.canSwipeBack else { return }
                    isDragTracking = true
                }
                guard isDragTracking else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = max(0, value.translation.width)
                    // Task 1 (11-realtime-map.md follow-up): mirrors this
                    // gesture's own live progress into
                    // `app.mapCloseSwipeProgress` — see that property's own
                    // doc comment — so `MapExploreView`'s sheet can track
                    // the Map-Explore-closing-to-Home drag directly,
                    // without a second, independent tracker anywhere else.
                    // Scoped to `.mapExplore` specifically: that's the only
                    // screen for which the CURRENT, foreground instance
                    // being dragged away is ever a `MapExploreView` at all
                    // (the Event-Detail-to-Map-Explore swipe reveals
                    // MapExploreView as the non-interactive `isPreview`
                    // BACKDROP underneath, a different, already-handled
                    // case — see that flag's own doc comment).
                    if app.screen == .mapExplore { app.mapCloseSwipeProgress = dragProgress }
                }
            }
            .onEnded { value in
                defer { isDragTracking = false }
                guard isDragTracking, abs(value.translation.height) < 80 else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                        dragTranslation = 0
                        if app.screen == .mapExplore { app.mapCloseSwipeProgress = 0 }
                    }
                    return
                }
                // A firm flick commits even if it hasn't crossed the
                // halfway mark yet — matches how forgiving the system
                // gesture is about a fast, short swipe.
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.35
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isCommittingBack = true
                        if app.screen == .mapExplore { app.mapCloseSwipeProgress = 1 }
                    }
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                        dragTranslation = 0
                        if app.screen == .mapExplore { app.mapCloseSwipeProgress = 0 }
                    }
                }
            }
    }

    private var isPeeking: Bool { isDragTracking || isCommittingBack }

    /// A sliver of parallax on the revealed screen — it drifts in from
    /// slightly off-frame rather than sitting flush at 0, the same subtle
    /// depth cue UIKit's pop transition gives the view underneath.
    private var peekOffset: CGFloat {
        -(1 - dragProgress) * UIScreen.main.bounds.width * 0.28
    }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()

            // The screen a swipe-back would land on, revealed underneath as
            // it drags instead of leaving blank paper — this is what was
            // missing: dragging used to uncover empty space because nothing
            // was actually rendered behind the current screen.
            if isPeeking {
                // `isPreview: true` — follow-up bug 1/2 (11-realtime-map.md):
                // this was the actual confirmed root cause of "edge-swipe
                // back to Map Explore returns to a broken/reloaded state."
                // Before this flag existed, this peeked-at copy was a FULL
                // `MapExploreView(restored:)` instance — including its own
                // `.task`, which awaits `app.loadMapEvents()` and then
                // clears `app.mapExploreState` once it resolves. That ran
                // for every edge-swipe drag the user started, including ones
                // that never committed (sprang back to Event Detail) — a
                // second, independent load/clear race against whichever
                // instance the ACTUAL navigation later creates. A user who
                // merely touched-and-released near the edge, then tapped
                // "‹ Bản đồ" afterward, could already have had their
                // snapshot silently wiped by this throwaway preview's own
                // `.task` before the real return ever happened. `isPreview`
                // stops this copy from running any of that side-effecting
                // work — it only needs to render, from whatever `app.mapEvents`/
                // `app.mapExploreState` already hold, a static visual
                // backdrop (`.allowsHitTesting(false)` below already makes
                // it non-interactive).
                screenView(for: app.backTargetScreen, isPreview: true)
                    .offset(x: peekOffset)
                    .overlay(Color.black.opacity((1 - dragProgress) * 0.1))
                    .allowsHitTesting(false)
            }

            screenView(for: app.screen)
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
            // Depth cue on the dragged edge, same as UIKit's pop shadow.
            .shadow(color: .black.opacity(dragProgress * 0.16), radius: 16, x: -6, y: 0)
            // Belt-and-suspenders once a drag is already tracking: keeps a
            // screen's own ScrollView from also visibly jiggling/scrolling
            // while it's being dragged sideways. `edgeSwipeZone` below is
            // what actually keeps the two gestures from arbitrating over the
            // same touch in the first place.
            .scrollDisabled(isDragTracking || isCommittingBack)

            // The swipe-back gesture itself, confined to a thin strip along
            // the leading edge rather than attached to the whole screen —
            // see `edgeSwipeZoneWidth`'s comment for why. `highPriorityGesture`
            // (not `simultaneousGesture`) so that, within this strip, it wins
            // outright over whatever's underneath the instant it recognizes;
            // a touch that never moves past `minimumDistance` (an ordinary
            // tap — e.g. a back-button link whose hit area happens to graze
            // this strip) never recognizes at all, so it still reaches
            // whatever's underneath normally.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: edgeSwipeZoneWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .highPriorityGesture(edgeSwipe)

            // Names the current screen for UI tests, the same way the web
            // screens carry a data-screen-label attribute for Playwright.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityIdentifier("screen.\(app.screen.rawValue)")

            if app.areaAsking { AreaSheetView() }
            if app.askingLocation { LocationSheetView() }
            if app.reasonPrompt != nil { ReasonSheetView() }
            if let photo = app.photoViewer { PhotoViewerView(item: photo) }
            if app.loading { loadingOverlay }

            if !app.toasts.isEmpty {
                ToastOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // Face ID app-lock sits above everything — see FaceIDLockView.
            // Task 2: splash must show BEFORE the Face ID prompt, not
            // simultaneously over it — held off while app.screen == .splash.
            if auth.isLocked && app.screen != .splash { FaceIDLockView() }
        }
        .animation(.easeInOut(duration: 0.2), value: app.areaAsking)
        .animation(.easeInOut(duration: 0.2), value: app.askingLocation)
        .animation(.easeInOut(duration: 0.2), value: app.photoViewer)
        // The screen switch above is a plain ZStack, not a NavigationStack,
        // so it never got the system's edge-swipe-to-go-back for free — the
        // `edgeSwipeZone` strip above reproduces it, tracking the finger
        // live rather than jumping only once the gesture ends.
        .onChange(of: isCommittingBack) { _, committing in
            guard committing else { return }
            // Let the slide-off animation actually play before switching
            // screens, then reset instantly — the incoming screen is a
            // different view entirely, so there's nothing to visibly snap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                // By the time this runs, the peeked-at screen is already
                // sitting exactly where the real one is about to appear —
                // so this swap must be completely unanimated. Without
                // forcing that here, isCommittingBack flips to false in the
                // same tick app.screen changes, which un-suppresses the
                // .animation(value: app.screen) below and replays its
                // slide-in transition on top of a screen that's already in
                // place, reading as a jerk back into position.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    app.goBack()
                    isCommittingBack = false
                    // The offset formula falls back to dragTranslation once
                    // isCommittingBack flips back off — leaving it at the
                    // drag's last value pushed the newly-arrived screen off
                    // to the right instead of resetting to 0.
                    dragTranslation = 0
                    // Task 1: by this point `app.screen` has already
                    // changed away from `.mapExplore` (via `app.goBack()`
                    // just above), so the MapExploreView instance that was
                    // reading this value is already gone — safe to reset
                    // here, unanimated, so the NEXT time Map Explore opens
                    // fresh it doesn't start looking pre-collapsed from a
                    // stale prior close.
                    app.mapCloseSwipeProgress = 0
                }
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
        // Task 1 — no guest browsing of any screen: the single, centralized
        // enforcement point, rather than auditing every `screen = .x`
        // call site in this large app individually. Catches cases the
        // targeted fixes (finishOnboarding, dismissSplash, signOut) don't
        // — e.g. goHome()'s plain `screen = .home`, callable from
        // anywhere, has no auth check of its own.
        .onChange(of: app.screen) { _, newScreen in
            if !app.isSignedIn && !AppState.guestAllowedScreens.contains(newScreen) {
                app.authMandatory = true
                app.authReturnScreen = newScreen
                app.authBackScreen = newScreen
                app.screen = .login
            }
        }
    }

    /// The SCREENS map, factored out so both the current screen and the
    /// peeked-at previous one (during a swipe) can render from the same
    /// switch instead of keeping two copies in sync. `isPreview` only ever
    /// matters to the `.mapExplore` case (see its own call site's comment)
    /// — every other screen ignores it, so this stays a one-line addition
    /// rather than a second switch to keep in sync.
    @ViewBuilder
    private func screenView(for screen: Screen, isPreview: Bool = false) -> some View {
        switch screen {
        case .splash: SplashView()
        case .langPick: LangPickView()
        case .themePick: ThemePickView()
        case .policy: PolicyView()
        // `MapExploreView.init(restored:)` reads `app.mapExploreState`
        // (11-realtime-map.md, bug 2) directly at construction time — not
        // in a later `.task` — so the very first frame this switch draws
        // already shows the restored camera/detent/filters/selection
        // instead of flashing the defaults for a frame first.
        case .mapExplore: MapExploreView(restored: app.mapExploreState, isPreview: isPreview)
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
        case .security: SecurityView()
        case .paymentDetails: PaymentDetailsView()
        case .billing: BillingView()
        case .payout: PayoutView()
        case .documents: DocumentsView()
        case .documentView: DocumentViewerView()
        case .verifications: VerificationsView()
        case .disputes: AdminDashboardView()
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

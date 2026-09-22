import SwiftUI
import UIKit

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
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { dragTranslation = 0 }
                    cancelMapCloseSwipe()
                    return
                }
                // A firm flick commits even if it hasn't crossed the
                // halfway mark yet — matches how forgiving the system
                // gesture is about a fast, short swipe.
                let width = UIScreen.main.bounds.width
                let crossedDistance = value.translation.width > width * 0.35
                let flicked = value.predictedEndTranslation.width > width * 0.6
                if crossedDistance || flicked {
                    withAnimation(.easeOut(duration: 0.22)) { isCommittingBack = true }
                    // Task 1 (11-realtime-map.md follow-up): a completed
                    // edge-swipe now calls the EXACT SAME shared confirm
                    // path the "← Đóng" button calls — not a second,
                    // parallel implementation. `AppState.confirmMapExploreClose()`
                    // owns the fast sheet-dismiss animation, the snapshot
                    // clear, and (0.22s later) the actual `goBack()` —
                    // see the `.onChange(of: isCommittingBack)` handler
                    // below for why this view's own generic reset must NOT
                    // also call `goBack()` for this specific screen.
                    app.confirmMapExploreClose()
                } else {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) { dragTranslation = 0 }
                    cancelMapCloseSwipe()
                }
            }
    }

    /// Task 2 (11-realtime-map.md follow-up): an interrupted swipe must
    /// NOT navigate anywhere (it never did — `isCommittingBack` never
    /// becomes `true` on this path, so `goBack()` is never reached) — it
    /// only needs to undo the LIVE-drag visual feedback and hand off to
    /// `MapExploreView`'s own hide-then-reveal recovery, which reuses the
    /// exact same delayed-reveal mechanism as returning from Event Detail
    /// (`AppState.mapCloseSwipeCancelled`, observed by that view — see its
    /// own doc comment). `mapCloseSwipeProgress` is reset unanimated, not
    /// sprung back over ~1s the way the prior pass did: it drives a
    /// content transform that's about to be hidden entirely (`sheetPresented
    /// = false`) anyway, so animating it here would be invisible work.
    private func cancelMapCloseSwipe() {
        guard app.screen == .mapExplore else { return }
        app.mapCloseSwipeProgress = 0
        app.mapCloseSwipeCancelled = true
    }

    private var isPeeking: Bool { isDragTracking || isCommittingBack }

    /// BUG 1 fix (2026-09-22 tenth follow-up) — true whenever the
    /// currently-showing screen is an Event Detail reached FROM a story
    /// (`app.eventBackIsStory`, set/cleared by
    /// `goEventFromStory()`/`backFromEvent()`/`goEvent()` — see
    /// AppState.swift). While true, the retained `app.storyViewer` (no
    /// longer nulled out on this path — see `goEventFromStory()`'s own
    /// comment) is the genuine underlay to reveal during an edge-swipe,
    /// not the generic `backTargetScreen` preview copy.
    private var storyUnderlaysEvent: Bool { app.screen == .event && app.eventBackIsStory }

    /// A sliver of parallax on the revealed screen — it drifts in from
    /// slightly off-frame rather than sitting flush at 0, the same subtle
    /// depth cue UIKit's pop transition gives the view underneath.
    private var peekOffset: CGFloat {
        -(1 - dragProgress) * UIScreen.main.bounds.width * 0.28
    }

    var body: some View {
        ZStack {
            // BUG 2 fix (2026-09-22 fourteenth follow-up) — real root cause
            // of the white-blank-instead-of-story reveal: this background
            // had NO explicit zIndex, defaulting to 0 — the SAME implicit
            // value as `screenView(for: app.screen)` below. The retained
            // `StoryViewerView` below is intentionally kept at `.zIndex(-1)`
            // while suspended (so Event Detail's own slide-away offset
            // progressively reveals it, not a snap to front — see that
            // zIndex's own comment). But -1 is LOWER than this background's
            // implicit 0, so as Event Detail slid away, what actually got
            // uncovered was this opaque paper/white background sitting
            // ABOVE StoryViewerView, not StoryViewerView itself — the
            // reported white blank. Pinning this explicitly below -1
            // guarantees it can never again outrank a retained, suspended
            // underlay that intentionally sits at a negative zIndex.
            app.palette.paper.ignoresSafeArea()
                .zIndex(-2)

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
                // BUG 1 fix (2026-09-22 tenth follow-up) — when the screen
                // underneath is an Event Detail opened FROM a story, the
                // genuine underlay is the retained `app.storyViewer`
                // (rendered separately below, at full opacity/zIndex
                // during a peek), not a throwaway preview of
                // `backTargetScreen` (Home) — showing both would be
                // visually redundant, and the whole point of this fix is
                // that Home must never be what appears here at all.
                if !storyUnderlaysEvent {
                    screenView(for: app.backTargetScreen, isPreview: true)
                        .offset(x: peekOffset)
                        .overlay(Color.black.opacity((1 - dragProgress) * 0.1))
                        .allowsHitTesting(false)
                }
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
            if app.chatPhotoViewer != nil { ChatPhotoViewerView() }
            // BUG 1 fix (2026-09-22 tenth follow-up) — `app.storyViewer`
            // now stays retained (non-nil) the whole time Event Detail is
            // showing after being opened FROM a story (see
            // AppState.goEventFromStory()'s own comment), so this can no
            // longer be a plain `if app.storyViewer != nil { StoryViewerView() }`
            // — that would render it ON TOP of Event Detail at rest, not
            // just during the edge-swipe peek. `isSuspended` pauses its
            // internal timer/gesture and drops it BELOW Event Detail in
            // z-order and out of hit-testing while `storyUnderlaysEvent`
            // and not peeking; the moment a peek starts (or the swipe
            // fully completes and `screen` leaves `.event`), it's exactly
            // the same single retained instance becoming visible again —
            // never a second `StoryViewerView` instance.
            if app.storyViewer != nil {
                // `isSuspended` pauses the story's own timer/progress for
                // the WHOLE time Event Detail is the nominal top screen —
                // including while peeking (a cancelled peek must not have
                // silently burned through story time the user only ever
                // glanced at); the zIndex/hit-testing below are the
                // separate VISUAL concern of when it's actually revealed.
                // BUG 1 fix (2026-09-22 thirteenth follow-up) — this used to
                // read `storyUnderlaysEvent && !isPeeking`, flipping zIndex
                // to 27 (ABOVE Event Detail) the instant a drag merely
                // started (`isDragTracking` goes true almost immediately,
                // `minimumDistance: 4`). That put StoryViewer on TOP of
                // Event Detail at full opacity/position from the first
                // pixel of travel — a snap, not a reveal — instead of
                // letting Event Detail's own already-continuous
                // `dragTranslation` offset (below, in `body`) progressively
                // uncover it. StoryViewer must stay BEHIND (zIndex -1, same
                // relative order as the generic `backTargetScreen` peek)
                // for the WHOLE time `storyUnderlaysEvent` is true —
                // through the drag AND through `isCommittingBack`'s slide-
                // off — only rising to zIndex 27 once `app.screen` actually
                // leaves `.event` (which naturally flips `storyUnderlaysEvent`
                // false once `goBack()` fires in the `isCommittingBack`
                // handler below).
                StoryViewerView(isSuspended: storyUnderlaysEvent)
                    .zIndex(storyUnderlaysEvent ? -1 : 27)
                    .allowsHitTesting(!storyUnderlaysEvent)
            }
            if app.loading { loadingOverlay }

            if !app.toasts.isEmpty {
                ToastOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            // BUG 3 follow-up (this session's real-device report on
            // 80c1ac3): BottomTabBar used to render HERE, as a ZStack
            // sibling with an explicit `.zIndex(10)` — correctly ordered
            // against MapExploreView's native `Map()` view (a real ZStack
            // sibling), but with zero effect against MapExploreView's
            // filter/list sheet, which is a genuine `.sheet()` presentation
            // layered by UIKit above this ENTIRE ZStack's content, not a
            // ZStack sibling at all. See BottomTabBarOverlay.swift's own
            // doc comment for the full investigation and why the fix is a
            // separate always-on-top UIWindow instead — attached below via
            // `.onAppear`, rendering the bar independently of this ZStack
            // (and therefore independently of whatever's presented modally
            // over it) for every screen in `BottomTabBar.visibleScreens`.
            // One known trade-off: the overlay doesn't know about
            // `isPeeking` (a plain `@State` local to this view), so unlike
            // before, the bar stays tappable for the brief moment an
            // edge-swipe-back is peeking at the previous screen — a narrow
            // edge case, not the one this fix targets.

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
                    // Task 1 (11-realtime-map.md follow-up): Map Explore's
                    // own confirmed close now navigates through the SHARED
                    // `AppState.confirmMapExploreClose()` (called directly
                    // from the commit branch above), which already owns
                    // its own `goBack()`/snapshot-clear/progress-reset
                    // timing on its own, independently-scheduled 0.22s
                    // timer. Calling `goBack()` again here for that same
                    // screen would double-navigate — every OTHER screen's
                    // swipe-back still goes through this generic path
                    // exactly as before, unaffected.
                    if app.screen != .mapExplore { app.goBack() }
                    isCommittingBack = false
                    // The offset formula falls back to dragTranslation once
                    // isCommittingBack flips back off — leaving it at the
                    // drag's last value pushed the newly-arrived screen off
                    // to the right instead of resetting to 0.
                    dragTranslation = 0
                }
            }
        }
        .preferredColorScheme(app.theme == "dark" ? .dark : .light)
        // BottomTabBarOverlay.swift: the bar now lives in its own always-
        // on-top UIWindow instead of this ZStack — attach it once a
        // UIWindowScene actually exists. Idempotent (guards on `window ==
        // nil` internally), so re-running this on every appearance of
        // RootView (there's only ever one, but harmless either way) is fine.
        .onAppear {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene {
                BottomTabBarOverlay.shared.attach(to: scene, appState: app)
            }
        }
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
        .onChange(of: app.screen) { oldScreen, newScreen in
            if !app.isSignedIn && !AppState.guestAllowedScreens.contains(newScreen) {
                app.authMandatory = true
                app.authReturnScreen = newScreen
                app.authBackScreen = newScreen
                app.screen = .login
            }
            // BUG 1 fix (2026-09-22 tenth follow-up) — `app.storyViewer`
            // now stays retained across an Event Detail opened from a
            // story (see AppState.goEventFromStory()'s own comment)
            // instead of being cleared up front, so any OTHER way the
            // screen leaves `.event` — a "Reserve"/"other events" tap,
            // anything that isn't `backFromEvent()`'s own sanctioned
            // return-to-story path — must explicitly discard it here, or
            // it would linger and pop back up (full zIndex/interactive)
            // over whatever screen this navigation actually lands on.
            // `backFromEvent()`/`goEvent()` already clear
            // `eventBackIsStory` THEMSELVES as part of the very same
            // state update that changes `screen` — so by the time this
            // fires, `eventBackIsStory` being STILL true is exactly the
            // signal that this wasn't that sanctioned path.
            // `.organizer` is explicitly exempted — `backToEvent()`
            // returns straight to `.event` from there, and
            // `eventBackScreen` itself already treats `.organizer` as
            // "still within this event's own neighborhood" (see
            // `goEvent()`'s own condition) — an Organizer round-trip must
            // not lose the story context either.
            if oldScreen == .event, newScreen != .event, newScreen != .organizer, app.eventBackIsStory {
                app.eventBackIsStory = false
                app.closeStoryViewer()
            }
            // Every screen change starts the bottom tab bar back at full
            // size, matching src/App.jsx Shell's own per-screen reset.
            app.bottomBarCollapsed = false
            // BUG follow-up (a5fd823 real-device report: Reserve/View
            // Ticket unresponsive on Event Detail) — see
            // BottomTabBarOverlay.updateVisibility()'s own doc comment for
            // the full root cause. Must run on every screen change, not
            // just once at attach time, since the overlay window persists
            // for the app's lifetime and otherwise keeps intercepting
            // touches in its band on screens the bar was never meant to
            // show on.
            BottomTabBarOverlay.shared.updateVisibility(for: newScreen)
        }
        // Task 1 (2026-09-22 follow-up, 07-notifications.md) — StoryViewer
        // opens over Home/Profile WITHOUT a `Screen` change (it's an
        // overlay, not a navigation), so the `.onChange(of: app.screen)`
        // above never sees it. A separate, dedicated flag on the overlay
        // (not folded into `forcedHidden`) so this and InboxView's own
        // screen-local sheet check can't stomp on each other.
        .onChange(of: app.storyViewer) { _, viewer in
            BottomTabBarOverlay.shared.setStoryViewerOpen(viewer != nil)
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

import SwiftUI

/// Top-level screen switch and sheet host — the iOS equivalent of the
/// SCREENS map and sheet layer in src/App.jsx. One screen shows at a time,
/// with explicit back targets, exactly as the web app does it.
struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()

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

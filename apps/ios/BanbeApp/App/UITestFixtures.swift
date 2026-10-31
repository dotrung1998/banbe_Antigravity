#if DEBUG
import SwiftUI

// DEBUG-ONLY deterministic fixtures for UI tests and screenshots of the
// Reports dashboard and the onboarding flow. Activated only by the launch
// argument `-uiFixture <name>` (UserDefaults, the same convention as
// `-banbe.onboarded`); compiled out of Release. With a fixture active the
// normal RootView is not mounted and the reports/discovery network loads
// return early, so nothing here can reach Supabase or a real account.
//
// The data below is synthetic test data for exercising layouts only — it is
// never shown outside a fixture launch.

enum UITestFixture {
    static let name: String? = UserDefaults.standard.string(forKey: "uiFixture")
    static var isActive: Bool { name != nil }
    /// How many times a HomeView has appeared (HomeView's own onAppear bumps it). The shell fixture shows it as
    /// `fixture.homeMounts`, so a test can prove the Home under Event Detail is the same live instance (note 47).
    static var homeMounts = 0
    /// `-uiFixtureMonth YES` opens Schedule's month sheet at launch (screenshots).
    static let opensMonth = UserDefaults.standard.bool(forKey: "uiFixtureMonth")
    /// Note 50 — `-uiFixtureFilters YES` opens Home's filter sheet; `-uiFixtureSearch <q>` pre-fills Search;
    /// `-uiFixtureBench YES` seeds the create flow with the synthetic benchmark payload from EventRecipeTests.
    static let opensFilters = UserDefaults.standard.bool(forKey: "uiFixtureFilters")
    static let searchQuery = UserDefaults.standard.string(forKey: "uiFixtureSearch") ?? ""
    static let seedsBenchmarks = UserDefaults.standard.bool(forKey: "uiFixtureBench")
    /// `-uiFixtureForYou YES` gives the fixture account event preferences that match its events, so Home shows the
    /// pinned For You chip (used to check it is the same height as Filters / Sort / the quick chips).
    static let seedsForYou = UserDefaults.standard.bool(forKey: "uiFixtureForYou")
    /// `-uiFixtureReview YES` (with `shell.create`) opens Review before submitting with synthetic photos (2026-10-21).
    static let opensReview = UserDefaults.standard.bool(forKey: "uiFixtureReview")
    /// Note 51 — `-uiFixturePulse YES` seeds the daily Banbe Pulse ranking (the Home ticker's content);
    /// `-uiFixtureRewards off` is an admin having hidden Rewards & badges (migration 187).
    static let seedsPulse = UserDefaults.standard.bool(forKey: "uiFixturePulse")
    static let rewardsSwitch = UserDefaults.standard.string(forKey: "uiFixtureRewards") ?? "on"
    /// Note 63: `-uiFixtureOnboardingV2 YES` is an admin having picked onboarding Version 2.
    static let onboardingV2 = UserDefaults.standard.bool(forKey: "uiFixtureOnboardingV2")
    /// Note 64: `-uiFixtureTourV3 YES` (with a `shell.*` fixture) is onboarding Version 3 with its tour started
    /// (as a Help & Legal replay, so no first-run marker is written).
    static let tourV3 = UserDefaults.standard.bool(forKey: "uiFixtureTourV3")
    /// Note 65: `-uiFixtureEventTypes YES` is an admin having turned on `event_type_profiles` (with `shell.create`
    /// the draft also gets supper club facts; with `shell.home` two fixture events get some).
    static let eventTypes = UserDefaults.standard.bool(forKey: "uiFixtureEventTypes")
    /// Note 66: `-uiFixtureSimpleShell YES` is an admin having turned on `simple_shell` (new Home + centre "+" dock);
    /// `-uiFixtureHostMode YES` (with a `shell.*` fixture) starts in organizer mode (Home shows the host sections).
    static let simpleShell = UserDefaults.standard.bool(forKey: "uiFixtureSimpleShell")
    /// Note 71: `-uiFixturePolaroid YES` is an admin having turned on `polaroid_cards` (Calm Pass event cards).
    static let polaroid = UserDefaults.standard.bool(forKey: "uiFixturePolaroid")
    static let hostMode = UserDefaults.standard.bool(forKey: "uiFixtureHostMode")
    /// Simple Shell follow-up: `-uiFixtureGuest YES` (with a `shell.*` fixture) is a signed-out guest browsing.
    static let guest = UserDefaults.standard.bool(forKey: "uiFixtureGuest")
    /// `-uiFixtureHostKPIs YES` seeds the host's month numbers (the Host Home KPI tiles read `app.reportsData`);
    /// `-uiFixtureHostMode YES` seeds them too.
    static let hostKPIs = UserDefaults.standard.bool(forKey: "uiFixtureHostKPIs")
    /// Note 66: `-uiFixtureEventKey jazzgac` opens that catalogue event with `shell.event`; `-uiFixtureCreateType popup`
    /// makes the `shell.create` draft that type.
    static let eventKey = UserDefaults.standard.string(forKey: "uiFixtureEventKey") ?? "bepnho"
    static let createType = UserDefaults.standard.string(forKey: "uiFixtureCreateType")
    /// Stable fake account id so the draft store/relaunch tests have a key.
    static let userID = UUID(uuidString: "00000000-0000-4000-8000-00000000F1F0")!

    // MARK: Note 54 — Admin > Manage events (in-memory stand-in for migrations 188/189; same rules as the server).
    static var adminManagedEvents: [AdminEventRow] = {
        let now = Date()
        return [
            AdminEventRow(id: "fx-ev-live", name: "Supper club tối thứ Bảy", status: "live", startsAt: now.addingTimeInterval(5 * 86400), organizerName: "Bếp Nhỏ"),
            AdminEventRow(id: "fx-ev-booked", name: "Rooftop acoustic night", status: "live", startsAt: now.addingTimeInterval(3 * 86400), organizerName: "Mây Music"),
            AdminEventRow(id: "fx-ev-refund", name: "Gallery walk (cancelled)", status: "cancelled", startsAt: now.addingTimeInterval(2 * 86400), organizerName: "Art Hub"),
            AdminEventRow(id: "fx-ev-ended", name: "Pop-up market October", status: "ended", startsAt: now.addingTimeInterval(-6 * 86400), organizerName: "Chợ Phiên"),
            AdminEventRow(id: "fx-ev-draft", name: "Spam test event", status: "draft", startsAt: now.addingTimeInterval(9 * 86400), organizerName: "Test Host"),
            AdminEventRow(id: "fx-ev-removed", name: "Duplicate listing", status: "removed", startsAt: now.addingTimeInterval(8 * 86400),
                          removalReason: "Duplicate", removedAt: now.addingTimeInterval(-3600), organizerName: "Test Host"),
            // 2026-10-21: an event waiting for review, and two whose host deleted their account.
            AdminEventRow(id: "fx-ev-review", name: "Wine & vinyl evening", status: "review", startsAt: now.addingTimeInterval(12 * 86400),
                          organizerName: "Mây Music", createdAt: now.addingTimeInterval(-2 * 86400), submittedAt: now.addingTimeInterval(-86400),
                          priceVnd: 350_000, capacity: 20, seatsRemaining: 20, area: "Quận 1"),
            AdminEventRow(id: "fx-ev-orphan-refund", name: "Bàn dài (host left)", status: "cancelled", startsAt: now.addingTimeInterval(4 * 86400),
                          organizerName: AdminManagedEvents.deletedOrganizerName, organizerHasAccount: false,
                          priceVnd: 200_000, capacity: 12, seatsRemaining: 11),
            AdminEventRow(id: "fx-ev-orphan-draft", name: "Untitled draft (host left)", status: "draft", startsAt: nil,
                          organizerName: "Old Host", organizerHasAccount: false),
        ]
    }()
    static var adminEventChecks: [String: AdminEventCheck] = [
        "fx-ev-booked": AdminEventCheck(eventId: "fx-ev-booked", activeBookings: 3, bookingsEver: 3, removable: false),
        "fx-ev-refund": AdminEventCheck(eventId: "fx-ev-refund", unsettledRefunds: 1, bookingsEver: 1, removable: false),
        "fx-ev-ended": AdminEventCheck(eventId: "fx-ev-ended", bookingsEver: 4),
        "fx-ev-removed": AdminEventCheck(eventId: "fx-ev-removed", removable: false, purgeable: true),
        "fx-ev-orphan-refund": AdminEventCheck(eventId: "fx-ev-orphan-refund", unsettledRefunds: 1, bookingsEver: 1, removable: false),
    ]

    @MainActor
    static func runAdminEventAction(_ action: AdminEventAction, ids: [String], reason: String, app: AppState) -> AdminEventActionOutcome {
        if (action == .remove || action == .purge) && reason.trimmingCharacters(in: .whitespaces).count < 3 {
            return AdminEventActionOutcome(error: "REASON_REQUIRED")
        }
        if action == .wipeTesting && !FeatureFlags.isOn(app.featureFlags, "admin_event_wipe") {
            return AdminEventActionOutcome(error: "NOT_ENABLED")
        }
        var out = AdminEventActionOutcome()
        for id in ids {
            guard let i = adminManagedEvents.firstIndex(where: { $0.id == id }) else {
                out.skipped.append(AdminEventActionResult(eventId: id, ok: false, error: "NOT_FOUND")); continue
            }
            let row = adminManagedEvents[i]
            let check = adminEventChecks[id] ?? AdminEventCheck(eventId: id)
            func skip(_ e: String) { out.skipped.append(AdminEventActionResult(eventId: id, ok: false, error: e)) }
            switch action {
            case .remove:
                if row.status == "removed" { skip("ALREADY_REMOVED"); continue }
                if check.isBlocked { skip("HAS_OPEN_OBLIGATIONS"); continue }
                adminManagedEvents[i] = AdminEventRow(id: row.id, name: row.name, status: "removed", startsAt: row.startsAt,
                                                      removalReason: reason, removedAt: Date(), organizerId: row.organizerId,
                                                      organizerName: row.organizerName, organizerFound: row.organizerFound,
                                                      organizerHasAccount: row.organizerHasAccount)
                adminEventChecks[id] = AdminEventCheck(eventId: id, bookingsEver: check.bookingsEver, removable: false,
                                                       purgeable: check.bookingsEver == 0)
            case .restore:
                if row.status != "removed" { skip("NOT_REMOVED"); continue }
                adminManagedEvents[i] = AdminEventRow(id: row.id, name: row.name, status: "live", startsAt: row.startsAt,
                                                      organizerId: row.organizerId, organizerName: row.organizerName,
                                                      organizerFound: row.organizerFound, organizerHasAccount: row.organizerHasAccount)
                adminEventChecks[id] = AdminEventCheck(eventId: id, bookingsEver: check.bookingsEver)
            case .purge:
                if row.status != "removed" { skip("NOT_REMOVED"); continue }
                if check.bookingsEver > 0 { skip("HAS_BOOKING_HISTORY"); continue }
                adminManagedEvents.remove(at: i)
            case .wipeTesting:
                adminManagedEvents.remove(at: i)
            }
            out.done += 1
        }
        return out
    }
}

struct UITestFixtureRoot: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    @State private var flow: OnboardingCoordinator?
    @State private var ready = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if ready {
                if name.hasPrefix("reports") {
                    ReportsView()
                } else if name.hasPrefix("shell") {
                    // The REAL RootView (dock, swipe gestures, headers) on seeded signed-in state.
                    RootView()
                        .overlay(alignment: .topLeading) {
                            // Re-read a few times a second: the counter is a plain static, not observable state.
                            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                                Text("\(UITestFixture.homeMounts)")
                                    .font(.system(size: 1)).opacity(0.01)
                                    .accessibilityIdentifier("fixture.homeMounts")
                            }
                            .allowsHitTesting(false)
                        }
                } else if isRouted {
                    routed
                } else if let flow {
                    if flow.state.stage == .finished {
                        Text("Fixture finished").accessibilityIdentifier("fixture.finished")
                    } else {
                        OnboardingFlowView(flow: flow)
                    }
                }
            }
        }
        .preferredColorScheme(ThemeChoice.colorScheme(for: app.theme))
        .task { configure() }
    }

    private func configure() {
        guard !ready else { return }
        let signedOut = name.hasPrefix("auth") || name == "routing.signedOut" || (name.hasPrefix("shell") && UITestFixture.guest)
        if !signedOut { app.userID = UITestFixture.userID }
        if UITestFixture.onboardingV2 { app.featureFlags["onboarding_v2"] = true }
        if UITestFixture.tourV3 { app.featureFlags["onboarding_v3"] = true }
        if UITestFixture.simpleShell { app.featureFlags["simple_shell"] = true }
        if UITestFixture.polaroid { app.featureFlags["polaroid_cards"] = true }
        if UITestFixture.eventTypes {
            app.featureFlags["event_type_profiles"] = true
            // The facts the production backfill gave these catalogue events (note 66), as their real rows would.
            let seeded: [String: EventDetails] = [
                "bepnho": ["dietary": .list(["vegetarian", "can_accommodate"]), "alcohol": .text("included"), "min_age": .text("18")],
                "comnha": ["dietary": .list(["vegetarian"]), "alcohol": .text("none"), "min_age": .text("16"), "dress_code": .text("Thoải mái")],
                "jazzgac": ["lineup": .list(["Bộ ba Gác", "Khách mời: Linh Sax"]), "genre": .list(["jazz"]), "format": .text("seated"),
                            "alcohol": .text("included"), "min_age": .text("18")],
                "khongnguoi": ["artists": .list(["Trần Vũ"]), "medium": .list(["photography"]), "alcohol": .text("none"), "min_age": .text("16")],
                "aeie": ["brands": .list(["AEIE"]), "experience": .text("show"), "price_range": .text("premium"),
                         "alcohol": .text("none"), "min_age": .text("16")],
            ]
            for (key, details) in seeded {
                app.homeLiveEvents[key] = LiveEventStatus(status: "live", startsAt: nil, cancelledAt: nil, cancelReason: nil,
                                                          details: EventDetailsPayload(details), capacity: nil)
            }
        }
        if name.hasPrefix("shell") { configureShell() }
        else if name.hasPrefix("reports") { configureReports() }
        else if isRouted { configureRouted() }
        else { configureOnboarding() }
        ready = true
    }

    // MARK: shell (real RootView)

    /// `shell.home` / `shell.schedule` / `shell.account` / `shell.accountSolo`
    /// (Account with only the Personal tab) / `shell.search` / `shell.create` (note 50). Seeds the same fake events as the
    /// schedule fixtures and keeps the signed-in state (applySession is skipped).
    private func configureShell() {
        // The dock window starts "shown" in its own bookkeeping and only really appears on the
        // first hidden→visible change (the splash does that in the real app); do it here.
        BottomTabBarOverlay.shared.updateVisibility(for: .splash)
        configureSchedule()
        let variant = name.split(separator: ".").dropFirst().first.map(String.init) ?? "home"
        app.organizerMode = (variant == "account" || UITestFixture.hostMode) && !UITestFixture.guest
        // As a sign-in sync would (Lib/HomeMode.swift): organizer mode on opens Home on Hosting.
        app.homeView = HomeMode.viewAfterSync(prevOrganizerMode: false, prevHomeView: .goer, organizerMode: app.organizerMode)
        if UITestFixture.hostKPIs || UITestFixture.hostMode {
            // The host's month numbers, as Reports would have loaded them (Host Home KPI tiles).
            app.reportsData = Self.report(role: "host", metrics: Self.metrics("host"))
            app.reportsLoadedAt = Date()
        }
        app.accountType = (variant == "account" || variant == "adminFeatures" || variant == "adminManageEvents") ? "admin" : "participant"
        app.accountTab = "host"   // note 69: the default; resolves to the first tab that exists
        // Streak/coins capsule visible: the tightest Home header layout.
        app.rewardsSummary = RewardSummary(balance: 120, streak: 3, activeToday: true)
        app.rewardsSummaryStatus = .loaded
        // Real seat fill for two fixture events: one almost full, one with social proof (note 50).
        // bepnho mirrors production (capacity 3, nothing booked): "3 of 3 left" with no bar, stepper capped at 3 (note 70).
        app.eventFill = ["fx-hosted": (booked: 18, capacity: 20), "fx-near": (booked: 6, capacity: 20), "bepnho": (booked: 0, capacity: 3)]
        app.homeFilterSheetOpen = UITestFixture.opensFilters
        if UITestFixture.rewardsSwitch == "off" { app.featureFlags = ["rewards": false] }
        if UITestFixture.seedsPulse {
            app.pulseDaily = ["Supper club 6 món ở Quận 3", "Đêm nhạc acoustic Thảo Điền", "Gallery walk Bình Thạnh"].enumerated().map { i, name in
                let json = """
                {"event_id":"fx-pulse-\(i)","event_name":"\(name)","organizer_id":"o","organizer_name":"Host","organizer_verified":false,"score":\(40 - i * 10)}
                """
                return try! JSONDecoder().decode(PulseItem.self, from: Data(json.utf8))
            }
        }
        if UITestFixture.tourV3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [app] in app.replayOnboardingTour() }
        }
        if UITestFixture.seedsForYou {
            app.eventPrefs = EventPreferences(interests: ["supper", "gallery", "music"], goals: ["meet_people"], availability: ["evening"],
                                              budget: BudgetPref(tier: "flexible", currency: nil), languages: ["vi", "en"])
            app.eventPrefsVersion += 1
        }
        switch variant {
        case "schedule": app.screen = .schedule
        case "map": app.screen = .mapExplore   // Map redesign: live public events, fixture fill above
        case "inbox": app.screen = .inbox
        case "account", "accountSolo": app.screen = .profile
        case "adminFeatures": app.screen = .adminFeatures
        case "guide":
            app.helpGuideKey = UserDefaults.standard.string(forKey: "uiFixtureGuide") ?? "personal"
            app.screen = .helpGuide
        case "faq": app.screen = .helpFaq
        case "adminManageEvents":
            // Note 54. `-uiFixtureWipe YES` is an admin having turned the TESTING-PHASE wipe switch on.
            if UserDefaults.standard.bool(forKey: "uiFixtureWipe") { app.featureFlags["admin_event_wipe"] = true }
            app.screen = .adminManageEvents
        case "search":
            app.searchQuery = UITestFixture.searchQuery
            app.screen = .search
        case "create":
            configureCreateDraft()
            app.screen = .create
        case "createNew":
            // The real entry: Home's create button → goCreate() (fresh draft + smart defaults).
            app.organizerMode = true
            app.screen = .home
            app.goCreate()
        case "event":
            // Event Detail on a long catalogue event (included items, photos, long description), so scrolling
            // reaches the collapsing nav bar (note 52).
            app.screen = .home
            app.goEvent(UITestFixture.eventKey)
        case "publicProfile":
            // Note 68: the signed-in account's own identity card (synthetic data). Interests repeat "Admin" on purpose:
            // the real banbetestadmin row does, and it used to show two identical chips.
            let json: [String: Any] = [
                "success": true, "id": UITestFixture.userID.uuidString.lowercased(), "handle": "fixturehost",
                "display_name": "Linh Trần", "bio": "Long tables, slow dinners, new friends.",
                "city": "Hanoi", "interests": ["Admin", "Admin", "Jazz"], "profile_theme": "rose", "organizer_mode": true,
                "organizer": ["id": "fx-org", "name": "Bếp Nhỏ", "verified": false, "hosting_since_year": 2025,
                              "event_count": 3, "follower_count": 12, "following": false],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                app.publicProfile = try? JSONDecoder().decode(PublicProfile.self, from: data)
            }
            app.publicProfileLoading = false
            app.screen = .publicProfile
        default: app.screen = .home
        }
    }

    /// A half-finished draft so the recipe meter has something to say (synthetic data only).
    private func configureCreateDraft() {
        app.organizerMode = true
        app.orgRegName = "Fixture Host"
        app.createOriginScreen = .home
        app.createName = "Six-course supper club in District 3"
        app.createCats = ["supper"]
        app.createDesc = "A long table for sixteen in a converted garage."
        app.createKeywords = "wine"
        app.createIncludedItems = [IncludedItem(label: "5 courses", detail: "")]
        if UITestFixture.eventTypes {
            app.createDetails = ["supper": ["dietary": .list(["vegetarian"]), "alcohol": .text("byo")]]
            if let type = UITestFixture.createType { app.createCats = [type] }
            // Open on Basics, where the type's own fields are (the Undo restore hook, no new view state).
            app.createDraftStash.step = 1
            app.createRestorePending = true
        }
        app.createPrice = "300000"
        app.createSeats = "16"
        app.createCity = "Hồ Chí Minh"
        app.createEventDate = SmartDefaults.nextWeekday(SmartDefaults.saturday, after: Date(), minDaysAhead: 3)
        app.createEventTime = SmartDefaults.timeOfDay("19:00")
        if UITestFixture.seedsBenchmarks {
            let json = #"""
            {"success": true, "level": "category_city", "n": 13, "free_share": 0,
             "price": {"n": 13, "p25": 280000, "median": 320000, "p75": 380000, "min": 220000, "max": 440000,
                       "histogram": [2, 1, 1, 2, 1, 1, 1, 1, 1, 2]},
             "fill": {"n": 12, "median_fill": 0.6, "median_capacity": 20, "median_booked": 12},
             "slots": [{"dow": 6, "slot": "evening", "n": 8, "median_fill": 0.85},
                       {"dow": 3, "slot": "evening", "n": 5, "median_fill": 0.5}],
             "well_filled": {"n": 6, "median_photos": 6, "intro_share": 0.5, "included_share": 1, "median_lead_days": 16.4},
             "keywords": ["wine", "rooftop", "chef"]}
            """#
            app.hostBenchmarksCache["supper|hồ chí minh"] = try? JSONDecoder().decode(HostBenchmarks.self, from: Data(json.utf8))
        }
    }

    // MARK: routed fixtures (public entry, routing, schedule, plan actions)

    private var isRouted: Bool {
        name.hasPrefix("auth") || name.hasPrefix("routing") || name.hasPrefix("schedule") || name.hasPrefix("plan")
    }

    /// A tiny stand-in for RootView's screen switch: only the screens these
    /// fixtures exercise; every other destination renders a marker.
    @ViewBuilder
    private var routed: some View {
        ZStack {
            switch app.screen {
            case .welcome: WelcomeView().transition(AuthMotion.transition(forward: app.authNavForward, reduceMotion: reduceMotion))
            case .login: LoginView().transition(AuthMotion.transition(forward: app.authNavForward, reduceMotion: reduceMotion))
            case .schedule: ScheduleView()
            case .event:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fixture event \(app.eventKey)").accessibilityIdentifier("fixture.event.\(app.eventKey)")
                        if let e = app.resolvedEvent(for: app.eventKey) { EventPlanTitleRow(event: e) }
                        Button("Back to schedule") { app.screen = .schedule }.accessibilityIdentifier("fixture.backToSchedule")
                    }
                    .padding(20)
                }
            default:
                Text("screen \(app.screen.rawValue)").accessibilityIdentifier("fixture.screen.\(app.screen.rawValue)")
            }
        }
        .animation(app.screen == .welcome || app.screen == .login ? AuthMotion.animation(reduceMotion: reduceMotion) : nil,
                   value: app.screen)
    }

    private func configureRouted() {
        switch name {
        case "routing.signedIn":
            app.screen = .splash
            app.dismissSplash(isSignedIn: true)
        case "routing.signedOut":
            app.screen = .splash
            app.dismissSplash(isSignedIn: false)
        case "routing.signOut":
            app.screen = .home
            Task { await app.signOut() }
        case let n where n.hasPrefix("auth"):
            app.screen = .welcome
        case let n where n.hasPrefix("schedule") || n.hasPrefix("plan"):
            configureSchedule()
        default:
            break
        }
    }

    /// Two days from today (device zone) so nothing is in the past.
    static var scheduleDay: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private func configureSchedule() {
        let cal = Calendar.current
        let day = Self.scheduleDay
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: dayOffset, to: day) ?? day
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }
        let iso = ISO8601DateFormatter()
        func row(_ id: String, _ name: String, _ start: Date, _ cat: String) -> [String: Any] {
            ["id": id, "name": name, "status": "live", "visibility": "public", "cat_key": cat, "price_vnd": 0,
             "country_code": "VN", "seats_remaining": 10, "capacity": 20, "organizer_id": "fx-org",
             "starts_at": iso.string(from: start)]
        }
        let rows = [
            row("fx-hosted", "Fixture host supper", at(0, 13), "supper"),
            row("fx-added", "Fixture added gallery", at(0, 18), "gallery"),
            row("fx-near", "Fixture rooftop set", at(0, 14), "music"),
            row("fx-later", "Fixture print show", at(1, 10), "gallery"),
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? JSONSerialization.data(withJSONObject: rows),
              let summaries = try? decoder.decode([RealEventSummary].self, from: data) else { return }
        let events = summaries.map { CatalogEvent.fromReal($0) }
        for e in events { app.realEventsByID[e.key] = e }

        let empty = name == "schedule.empty"
        let failed = name == "schedule.error"
        // Hosted: the account's own organizer owns fx-hosted.
        if !empty && !failed {
            app.myOrganizerID = "fx-org"
            app.myOrgEventKeys = ["fx-hosted"]
            app.myOrgEventOrganizerID = ["fx-hosted": "fx-org"]
            app.myOrgEventSummaries = summaries.filter { $0.id == "fx-hosted" }
        }
        // Manual addition (device-local store), reset per launch.
        let store = InAppCalendarStore()
        store.clear(uid: UITestFixture.userID)
        if !empty && !failed && !name.hasPrefix("plan") { store.add("fx-added", uid: UITestFixture.userID) }
        app.refreshScheduleAdded()
        // Discover pool (public + live), including the hosted one to prove dedupe.
        app.discoveryEvents = failed ? [] : events.filter { $0.key != "fx-added" || name.hasPrefix("plan") }
        app.discoveryEventsLoadFailed = failed
        app.paymentBookingsLoadFailed = failed
        app.scheduleSelectedDate = day
        if name.hasPrefix("plan") {
            app.eventKey = "fx-added"
            app.screen = .event
        } else {
            app.scheduleMode = name == "schedule.discover" ? .discover : .mine
            app.screen = .schedule
        }
    }

    // MARK: reports

    private func configureReports() {
        let parts = name.split(separator: ".").map(String.init)
        let variant = parts.count > 1 ? parts[1] : "personal"
        let role = ["personal", "host", "admin"].contains(variant) ? variant : (parts.count > 2 ? parts[2] : "host")
        app.reportsScope = role
        app.reportsRangeDays = .days30
        switch variant {
        case "loading":
            app.reportsLoading = true
        case "error":
            app.reportsError = app.T("Không thể tải số liệu lúc này. Vui lòng thử lại.", "Couldn't load these numbers right now. Please try again.")
        case "empty":
            app.reportsData = Self.report(role: role, metrics: [])
        case "stale":
            app.reportsData = Self.report(role: role, metrics: Self.metrics(role))
            app.reportsLoadedAt = Date(timeIntervalSinceNow: -3600)
            app.reportsError = app.T("Không thể tải số liệu lúc này. Vui lòng thử lại.", "Couldn't load these numbers right now. Please try again.")
        default:
            app.reportsData = Self.report(role: role, metrics: Self.metrics(role))
            app.reportsLoadedAt = Date()
        }
    }

    /// 30 daily buckets ending today (UTC), a fixed repeating pattern.
    private static func series(_ pattern: [Double]) -> [[String: Any]] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let today = cal.startOfDay(for: Date())
        return (0..<30).map { i in
            let d = cal.date(byAdding: .day, value: i - 29, to: today)!
            return ["d": f.string(from: d), "v": pattern[i % pattern.count]]
        }
    }

    private static func metric(_ key: String, _ label: String, _ unit: String, _ value: Double,
                               series: [Double]? = nil, rows: [[String: Any]]? = nil) -> [String: Any] {
        var m: [String: Any] = ["key": key, "label": label, "unit": unit, "value": value]
        if let series {
            let s = Self.series(series)
            m["series"] = s
            m["value"] = s.reduce(0) { $0 + (($1["v"] as? Double) ?? 0) }
        }
        if let rows { m["rows"] = rows }
        return m
    }

    private static func metrics(_ role: String) -> [[String: Any]] {
        switch role {
        case "host":
            return [
                metric("published_events", "Sự kiện đã công khai", "count", 6),
                metric("upcoming_events", "Sắp diễn ra", "count", 2),
                metric("confirmed_seats", "Chỗ đã xác nhận", "count", 0, series: [0, 2, 0, 0, 4, 1, 0, 0, 3, 0],
                       rows: [["id": "fx1", "event_name": "Fixture supper", "qty": 2, "at": "2026-10-10T12:00:00+00:00"]]),
                metric("check_ins", "Đã check-in", "count", 0, series: [0, 0, 0, 1, 0, 0, 2, 0, 0, 0]),
                metric("confirmed_payment_amount", "Số tiền thanh toán đã xác nhận", "vnd", 0,
                       series: [0, 450_000, 0, 0, 900_000, 250_000, 0, 0, 600_000, 0]),
                metric("refunds_owed", "Hoàn tiền còn nợ", "vnd", 350_000,
                       rows: [["id": "fr1", "event_name": "Fixture gallery night", "amount_vnd": 350_000,
                               "due_at": "2026-10-01T00:00:00+00:00", "overdue": true]]),
                metric("refunds_overdue", "Hoàn tiền quá hạn", "count", 1),
            ]
        case "admin":
            return [
                metric("pending_event_reviews", "Sự kiện chờ duyệt", "count", 3,
                       rows: [["id": "fe1", "event_name": "Fixture pop-up", "submitted_at": "2026-10-12T00:00:00+00:00", "age_days": 4.2]]),
                metric("unresolved_disputes", "Tranh chấp chưa xử lý", "count", 1,
                       rows: [["id": "fd1", "event_name": "Fixture music", "disputed_at": "2026-10-14T00:00:00+00:00", "age_days": 1.5]]),
                metric("backlog_avg_age_days", "Tuổi trung bình hàng chờ (ngày)", "days", 3.5),
                metric("platform_new_events", "Sự kiện mới toàn nền tảng", "count", 0, series: [1, 0, 2, 0, 0, 1]),
                metric("platform_new_bookings", "Đặt chỗ mới toàn nền tảng", "count", 0, series: [3, 5, 2, 0, 4, 6, 1]),
            ]
        default:
            return [
                metric("saved_events", "Sự kiện đã lưu", "count", 4, rows: []),
                metric("confirmed_bookings", "Đặt chỗ đã xác nhận", "count", 0, series: [0, 0, 1, 0, 0, 0, 0, 2, 0, 0],
                       rows: [["id": "fb1", "event_name": "Fixture music", "qty": 1, "at": "2026-10-11T10:00:00+00:00"]]),
                metric("attended_events", "Đã tham dự", "count", 0, series: [0, 0, 0, 0, 1, 0, 0, 0, 0, 0], rows: []),
                metric("upcoming_events", "Sắp diễn ra", "count", 1,
                       rows: [["id": "fb1", "event_name": "Fixture music", "starts_at": "2026-10-30T12:00:00+00:00"]]),
                metric("outstanding_refunds", "Hoàn tiền đang chờ", "vnd", 200_000,
                       rows: [["id": "fr2", "event_name": "Fixture pop-up", "amount_vnd": 200_000, "status": "host_marked_sent",
                               "since": "2026-10-09T00:00:00+00:00"]]),
            ]
        }
    }

    private static func report(role: String, metrics: [[String: Any]]) -> AccountKpiReport? {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var payload: [String: Any] = [
            "success": true, "scope": role, "metrics": metrics,
            "range": ["start": iso.string(from: now.addingTimeInterval(-30 * 86_400)), "end": iso.string(from: now)],
        ]
        if role == "host" { payload["organizer_id"] = "fixture-org" }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(AccountKpiReport.self, from: data)
    }

    // MARK: onboarding

    private func configureOnboarding() {
        let defaults = UserDefaults.standard
        let store = OnboardingDraftStore()
        if defaults.bool(forKey: "uiFixtureReset") { store.clear(uid: UITestFixture.userID) }
        let variant = name.split(separator: ".").dropFirst().first.map(String.init) ?? "default"
        switch variant {
        case "offline":
            app.discoveryEvents = []
            app.discoveryEventsLoadFailed = true
        case "zero":
            app.discoveryEvents = Self.events(cats: ["fashion"])
        default:
            app.discoveryEvents = Self.events(cats: ["music", "gallery", "supper", "music"])
        }
        app.needsPreferencesOnboarding = true
        let saveFails = variant == "saveFails"
        var state = store.resume(uid: UITestFixture.userID, needsPreferences: true, needsSettings: false, region: .vn)
        // Screenshot entry points straight into a later screen.
        if variant == "budget" { state.stage = .question(3); state.draft.budget = BudgetPref(tier: "low", currency: "VND") }
        if variant == "reveal" {
            let prefs = EventPreferences(interests: ["music", "gallery"], goals: ["meet_people"], availability: ["evening"],
                                         budget: BudgetPref(tier: "free", currency: nil), languages: ["vi", "en"])
            state.draft = prefs
            state.needsPreferences = false
            state.stage = .reveal
            app.eventPrefs = prefs
            app.needsPreferencesOnboarding = false
        }
        flow = OnboardingCoordinator(state: state, uid: UITestFixture.userID, store: store) { [weak app] prefs in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !saveFails, let app else { return false }
            if let prefs { app.eventPrefs = prefs; app.eventPrefsVersion += 1 }
            app.needsPreferencesOnboarding = false
            return true
        }
    }

    /// Synthetic upcoming public events (VN, free) through the real
    /// `CatalogEvent.fromReal` shaping, so the real matcher ranks them.
    private static func events(cats: [String]) -> [CatalogEvent] {
        let iso = ISO8601DateFormatter()
        let names = ["Fixture listening night", "Fixture print show", "Fixture supper table", "Fixture rooftop set"]
        let rows: [[String: Any]] = cats.enumerated().map { i, cat in
            [
                "id": "fixture-\(i)", "name": names[i % names.count], "status": "live", "visibility": "public",
                "cat_key": cat, "price_vnd": 0, "country_code": "VN", "seats_remaining": 10, "capacity": 20,
                "starts_at": iso.string(from: Date().addingTimeInterval(Double(i + 2) * 86_400 + 12 * 3600)),
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([RealEventSummary].self, from: data)) ?? []
        return decoded.map { CatalogEvent.fromReal($0) }
    }
}
#endif

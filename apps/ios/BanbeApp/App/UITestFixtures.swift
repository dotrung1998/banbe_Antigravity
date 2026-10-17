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
    /// Stable fake account id so the draft store/relaunch tests have a key.
    static let userID = UUID(uuidString: "00000000-0000-4000-8000-00000000F1F0")!
}

struct UITestFixtureRoot: View {
    @EnvironmentObject private var app: AppState
    let name: String
    @State private var flow: OnboardingCoordinator?
    @State private var ready = false

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            if ready {
                if name.hasPrefix("reports") {
                    ReportsView()
                } else if let flow {
                    if flow.state.stage == .finished {
                        Text("Fixture finished").accessibilityIdentifier("fixture.finished")
                    } else {
                        OnboardingFlowView(flow: flow)
                    }
                }
            }
        }
        .preferredColorScheme(app.theme == "dark" ? .dark : .light)
        .task { configure() }
    }

    private func configure() {
        guard !ready else { return }
        app.userID = UITestFixture.userID
        if name.hasPrefix("reports") { configureReports() } else { configureOnboarding() }
        ready = true
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

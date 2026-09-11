import Foundation
import SwiftUI
import Supabase

/// Which screen is showing. The web app (src/App.jsx) keys one screen at a
/// time off a string and remembers explicit "back" targets rather than using
/// a router stack; this keeps the same model so the back behaviour matches.
enum Screen: String {
    case splash, langPick, themePick, home, profile, inbox, event, organizer
    case reserve, confirmed, refunded, login, chat, dashboard, hostIntro
    case create, attendance, preferences, editName, notifications, eventList
}

/// Which set of events EventListView shows — ports the same split used by
/// the "Going"/"Saved" counters on Account.
enum EventListMode: String {
    case going, saved
}

/// Feed area filter — ports AREAS in src/state/GocContext.jsx. Labels stay
/// Vietnamese in both languages, as on the web.
struct AreaOption: Identifiable {
    let key: String
    let label: String
    let match: (CatalogEvent) -> Bool
    var id: String { key }

    static let all: [AreaOption] = [
        AreaOption(key: "all", label: "Toàn Sài Gòn", match: { _ in true }),
        AreaOption(key: "q1", label: "Quận 1", match: { $0.meta.contains("Quận 1") }),
        AreaOption(key: "thaodien", label: "Thảo Điền", match: { $0.meta.contains("Thảo Điền") }),
        AreaOption(key: "binhthanh", label: "Bình Thạnh", match: { $0.meta.contains("Bình Thạnh") }),
        AreaOption(key: "other", label: "Quận khác", match: {
            !$0.meta.contains("Quận 1") && !$0.meta.contains("Thảo Điền") && !$0.meta.contains("Bình Thạnh")
        }),
        AreaOption(key: "danang", label: "Đà Nẵng", match: { _ in false }),
    ]
}

/// Predefined reasons an organizer must pick from before reversing a
/// check-in or cancelling a paid booking — ports UNDO_CHECKIN_REASONS /
/// CANCEL_BOOKING_REASONS. No free text, so the guest's notification always
/// says something concrete.
struct ReasonOption: Identifiable {
    let key: String
    let vi: String
    let en: String
    var id: String { key }

    static let undoCheckin: [ReasonOption] = [
        .init(key: "wrong_person", vi: "Nhầm người", en: "Wrong person"),
        .init(key: "tapped_by_mistake", vi: "Bấm nhầm", en: "Tapped by mistake"),
        .init(key: "not_arrived", vi: "Khách chưa thực sự có mặt", en: "Guest hasn't actually arrived"),
        .init(key: "other", vi: "Khác", en: "Other"),
    ]
    static let cancelBooking: [ReasonOption] = [
        .init(key: "event_changed", vi: "Sự kiện đổi lịch hoặc huỷ", en: "Event rescheduled or cancelled"),
        .init(key: "guest_requested", vi: "Khách yêu cầu huỷ", en: "Guest asked to cancel"),
        .init(key: "payment_incomplete", vi: "Không thanh toán đúng hạn", en: "Payment not completed in time"),
        .init(key: "policy_violation", vi: "Vi phạm quy định", en: "Policy violation"),
        .init(key: "other", vi: "Khác", en: "Other"),
    ]
}

struct ReasonPrompt: Equatable {
    enum Kind { case undoCheckin, cancelBooking }
    let kind: Kind
    let bookingID: UUID
    let guestName: String
}

struct AttendanceGuest: Identifiable, Equatable {
    let id: UUID
    let name: String
    let qty: Int
    var checkedIn: Bool
}

struct InboxThread: Identifiable, Equatable {
    let id: UUID
    let eventKey: String
    let name: String
    let img: String
    let snippet: String
    let lastAt: Date?
}

/// The whole app's state and behaviour — the iOS counterpart of
/// src/state/GocContext.jsx. Deliberately one object, like the web app, so
/// the two stay easy to compare; screens read it from the environment.
@MainActor
final class AppState: ObservableObject {

    // MARK: Navigation
    @Published var screen: Screen = .home
    @Published var eventKey: String = "bepnho"
    @Published var eventBackScreen: Screen = .home
    @Published var authReturnScreen: Screen = .home
    @Published var authBackScreen: Screen = .home
    @Published var chatBack: Screen = .organizer
    @Published var mode: String = "goer"
    // Inbox and Dashboard are each reachable from more than one place (Home's
    // message icon/host link vs Account's "Messages" row/hosting card), so a
    // single hardcoded back target sends at least one of those callers
    // somewhere it didn't come from.
    @Published var inboxBack: Screen = .home
    @Published var dashboardBack: Screen = .home
    @Published var eventListMode: EventListMode = .going

    // MARK: Preferences (persisted per-device and, once signed in, per-account)
    @Published var lang: String = UserDefaults.standard.string(forKey: "banbe.lang") ?? "vi" {
        didSet { UserDefaults.standard.set(lang, forKey: "banbe.lang") }
    }
    @Published var theme: String = UserDefaults.standard.string(forKey: "banbe.theme") ?? "light" {
        didSet { UserDefaults.standard.set(theme, forKey: "banbe.theme") }
    }
    @Published var area: String = "all"
    @Published var filter: String = "all"

    // MARK: Session
    @Published var user: Profile?
    @Published var userID: UUID?
    @Published var userEmail: String?
    @Published var accountType: String = "participant"
    @Published var organizerMode = false
    @Published var organizerModeError = ""
    @Published var hasHosted = false

    // MARK: Feed state
    @Published var favorites: [String] = []
    @Published var following: [String] = []
    @Published var attending: [String] = []
    @Published var tickets: [String: Int] = [:]
    @Published var myOrgEventKeys: [String] = []

    // MARK: Location
    @Published var located: Bool?
    @Published var userCoords: Coordinates?
    @Published var askingLocation = false
    @Published var areaAsking = false

    // MARK: Booking
    @Published var qty: Int = 1
    @Published var formName = ""
    @Published var formEmail = ""
    @Published var booking: Booking?
    @Published var holdDeadline: Date?
    @Published var now = Date()
    @Published var reserveError = ""
    @Published var loading = false
    @Published var calAdded = false
    @Published var sharedFlash = false

    // MARK: Chat
    @Published var chatThreadID: UUID?
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatDraft = ""
    @Published var inboxThreads: [InboxThread] = []

    // MARK: Notifications
    @Published var notifications: [AppNotification] = []
    var unreadNotifications: Int { notifications.filter { $0.readAt == nil }.count }

    // MARK: Display name
    @Published var editNameValue = ""
    @Published var editNameError = ""
    @Published var editNameSaving = false

    // MARK: Attendance / check-in
    @Published var attendanceEventKey: String?
    @Published var attendanceGuests: [AttendanceGuest] = []
    @Published var attendanceLoading = false
    @Published var scanningQr = false
    @Published var reasonPrompt: ReasonPrompt?
    @Published var reasonPromptBusy = false
    @Published var reasonPromptError = ""

    // MARK: Create event
    @Published var orgRegName = ""
    @Published var orgRegIg = ""
    @Published var orgRegDesc = ""
    @Published var createName = ""
    @Published var createDesc = ""
    @Published var createLoc = ""
    @Published var createDate = ""
    @Published var createPrice = ""
    @Published var createSeats = ""
    @Published var createCats: [String] = []
    @Published var createSent = false
    @Published var createError = ""
    @Published var orgVerifyRequested = false

    private let locationService = LocationService()
    private var tickTimer: Timer?
    private var chatPollTimer: Timer?

    init() {
        locationService.onUpdate = { [weak self] coords in
            self?.userCoords = coords
        }
        // A saved preference means this device has already been through
        // onboarding — replaying the splash/language/theme pickers on every
        // launch is what made the choice look like it "resets" on the web.
        let seen = UserDefaults.standard.bool(forKey: "banbe.onboarded")
        screen = seen ? .home : .splash
        if UserDefaults.standard.object(forKey: "banbe.located") != nil {
            let allowed = UserDefaults.standard.bool(forKey: "banbe.located")
            located = allowed
            if allowed { locationService.request() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }

    deinit {
        tickTimer?.invalidate()
        chatPollTimer?.invalidate()
    }

    // MARK: - Localization

    var isEN: Bool { lang == "en" }

    /// The web app's T(vi, en).
    func T(_ vi: String, _ en: String) -> String { isEN ? en : vi }

    /// Ports trStatus() — the catalogue's status strings are written in
    /// Vietnamese, and English mode rewrites the handful of recurring
    /// phrases rather than duplicating the whole catalogue.
    func trStatus(_ input: String) -> String {
        guard isEN else { return input }
        var s = input
        let patterns: [(String, String)] = [
            ("Còn (\\d+) chỗ", "$1 seats left"),
            ("Còn (\\d+) ngày", "In $1 days"),
            ("Hôm nay", "Today"),
            ("Ngày mai", "Tomorrow"),
            ("(\\d+) giờ trước", "$1h ago"),
            ("(\\d+) ngày trước", "$1d ago"),
            ("Hết chỗ", "Sold out"),
            ("Đã hủy", "Cancelled"),
            ("Đã hoàn tiền", "Refunded"),
            ("Đã diễn ra", "Ended"),
            ("Đang giữ", "On hold"),
            ("Đã thanh toán", "Paid"),
            ("Đã lưu", "Saved"),
            ("Đang tham gia", "Going"),
            ("Trả để xác nhận", "Pay to confirm"),
            ("(\\d+) vé", "$1 tix"),
            ("Miễn phí", "Free"),
            (" km từ bạn", " km away"),
            ("từ bạn", "away"),
            ("Thời trang", "Fashion"),
            ("Phòng tranh", "Gallery"),
            ("Nhạc", "Music"),
        ]
        for (pattern, replacement) in patterns {
            s = s.replacingOccurrences(
                of: pattern, with: replacement, options: [.regularExpression], range: nil
            )
        }
        return s
    }

    /// Ports stripKm(): with no location permission the km segment is
    /// removed entirely rather than showing the catalogue's placeholder as
    /// if it meant something; with permission it's replaced by the real
    /// computed distance.
    func stripKm(_ input: String, event: CatalogEvent? = nil) -> String {
        guard located == true else {
            return input.replacingOccurrences(
                of: " ▪︎ \\d+[.,]\\d+ km( từ bạn| away)?",
                with: "", options: [.regularExpression], range: nil
            )
        }
        guard let event, let km = haversineKm(from: userCoords, to: event) else { return input }
        let formatted = String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")
        return input.replacingOccurrences(
            of: "\\d+[.,]\\d+(?= km)", with: formatted, options: [.regularExpression], range: nil
        )
    }

    // MARK: - Derived

    var currentEvent: CatalogEvent { EventCatalog.find(eventKey) ?? EventCatalog.all[0] }
    var currentArea: AreaOption { AreaOption.all.first { $0.key == area } ?? AreaOption.all[0] }
    var isSignedIn: Bool { userID != nil }
    var canHost: Bool { organizerMode || accountType == "admin" || hasHosted }

    var displayName: String {
        if let name = user?.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let email = userEmail { return String(email.split(separator: "@").first ?? "") }
        return T("Khách", "Guest")
    }

    func isSaved(_ key: String) -> Bool { favorites.contains(key) }
    func isGoing(_ key: String) -> Bool { attending.contains(key) }

    /// The home feed — same filter and ordering as src/screens/Home.jsx:
    /// invite-only events never appear, and cancelled ones sink to the end.
    var feed: [CatalogEvent] {
        EventCatalog.all
            .filter { !$0.inviteOnly }
            .filter { filter == "all" || $0.catKey == filter || $0.cat2Key == filter }
            .filter { currentArea.match($0) }
            .sorted { a, b in demoted(a) < demoted(b) }
    }

    private func demoted(_ e: CatalogEvent) -> Int {
        (e.cancelled && (e.cancelledHoursAgo ?? 99) >= 2) ? 1 : 0
    }

    /// The "Your events" strip: saved + attending + invited + held, minus
    /// anything that ended more than 48h ago.
    var savedStrip: [CatalogEvent] {
        var keys: [String] = []
        for key in favorites + attending where !keys.contains(key) { keys.append(key) }
        if let heldKey = heldEvent?.key, !keys.contains(heldKey) { keys.append(heldKey) }
        return keys.compactMap { key in EventCatalog.all.first { $0.key == key } }
            .filter { ($0.endedHoursAgo ?? 0) <= 48 }
    }

    var heldEvent: CatalogEvent? {
        guard let deadline = holdDeadline, deadline > now else { return nil }
        return EventCatalog.all.first { $0.key == eventKey }
    }

    /// What EventListView shows for the current `eventListMode` — the
    /// "Going"/"Saved" cards on Account each open this filtered to their own set.
    var eventListEvents: [CatalogEvent] {
        let keys = eventListMode == .going ? attending : favorites
        return keys.compactMap { key in EventCatalog.all.first { $0.key == key } }
    }

    // MARK: - Onboarding

    func dismissSplash() { screen = .langPick }
    func pickLang(_ value: String) {
        lang = value
        screen = .themePick
        persistPreference(["locale": value])
    }
    func pickTheme(_ value: String) {
        theme = value
        persistPreference(["theme": value])
    }
    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "banbe.onboarded")
        screen = .home
    }
    func toggleLang() {
        let next = isEN ? "vi" : "en"
        lang = next
        persistPreference(["locale": next])
    }

    /// Once signed in, language & theme are account preferences, not just
    /// this device's — persist every change so they follow the account
    /// anywhere, exactly as persistAccountPreference() does on the web.
    func persistPreference(_ patch: [String: String]) {
        guard let uid = userID else { return }
        let update = ProfilePreferenceUpdate(
            locale: patch["locale"], theme: patch["theme"], prefsSaved: true
        )
        Task {
            do {
                try await SupabaseService.client.from("profiles")
                    .update(update)
                    .eq("id", value: uid)
                    .execute()
            } catch {
                print("Failed to save preferences to account:", error)
            }
        }
    }

    // MARK: - Navigation

    func goHome() { screen = .home }
    func goProfile() { screen = .profile }
    func goEvent(_ key: String) {
        if screen != .event { eventBackScreen = screen }
        eventKey = key
        screen = .event
        Task { await loadBookingForCurrentEvent() }
    }
    func backFromEvent() { screen = eventBackScreen }
    func goOrganizer() { screen = .organizer }
    func backToEvent() { screen = .event }
    func openHeld() { screen = .confirmed }
    func openPreferences() { screen = .preferences }
    func goLogin() { requireAuth(returnTo: .profile, backTo: .home) }

    func goInbox() {
        guard isSignedIn else { return requireAuth(returnTo: .inbox, backTo: .home) }
        inboxBack = screen == .profile ? .profile : .home
        screen = .inbox
        Task { await loadInboxThreads() }
    }
    func backFromInbox() { screen = inboxBack }

    func goGoingList() { eventListMode = .going; screen = .eventList }
    func goSavedList() { eventListMode = .saved; screen = .eventList }
    func backFromEventList() { screen = .profile }

    func goReserve() {
        guard isSignedIn else { return requireAuth(returnTo: .reserve, backTo: .event) }
        formName = user?.displayName ?? ""
        formEmail = userEmail ?? ""
        screen = .reserve
    }

    func goDashboard() { screen = .dashboard }

    func goCreate() {
        guard isSignedIn else { return requireAuth(returnTo: .create, backTo: .hostIntro) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        mode = "host"
        screen = .create
    }

    func goHostIntro() {
        guard isSignedIn else { return requireAuth(returnTo: .hostIntro, backTo: .profile) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        screen = .hostIntro
    }

    func createBack() { screen = hasHosted ? .dashboard : .hostIntro }

    func switchToHost(back: Screen = .home) {
        guard isSignedIn else { return requireAuth(returnTo: .dashboard, backTo: .home) }
        if !canHost { Task { await applyOrganizerMode(true) } }
        mode = "host"
        dashboardBack = back
        screen = .dashboard
        Task { await loadMyEvents() }
    }
    func backFromDashboard() { screen = dashboardBack }

    func switchToGoer() {
        mode = "goer"
        screen = .home
    }

    func requireAuth(returnTo: Screen, backTo: Screen) {
        authReturnScreen = returnTo
        authBackScreen = backTo
        screen = .login
    }

    // MARK: - Feed interactions

    func toggleFavorite(_ key: String) {
        if let index = favorites.firstIndex(of: key) { favorites.remove(at: index) } else { favorites.append(key) }
    }

    func toggleFollow(_ key: String) {
        if let index = following.firstIndex(of: key) { following.remove(at: index) } else { following.append(key) }
    }

    func pickFilter(_ key: String) { filter = key }
    func clearFilters() { filter = "all"; area = "all" }
    func openArea() { areaAsking = true }
    func pickArea(_ key: String) { area = key; areaAsking = false }

    func askLocation() { if located == nil { askingLocation = true } }

    func allowLocation() {
        askingLocation = false
        areaAsking = false
        located = true
        UserDefaults.standard.set(true, forKey: "banbe.located")
        locationService.request()
    }

    func denyLocation() {
        askingLocation = false
        located = false
        userCoords = nil
        UserDefaults.standard.set(false, forKey: "banbe.located")
    }

    /// Distance line shown under each card once location is shared.
    func metaLine(for event: CatalogEvent) -> String {
        trStatus(event.catDisplay) + " ▪︎ " + trStatus(stripKm(event.meta, event: event))
    }

    /// Seats/status label for a feed card — mirrors the web feed's rules.
    func seatsLabel(for event: CatalogEvent) -> String {
        if event.cancelled { return trStatus("Đã hủy") }
        if event.soldOut { return trStatus("Hết chỗ") }
        if let ended = event.endedHoursAgo { return trStatus(EventLabels.ago(ended)) }
        if event.until != nil {
            let suffix = event.untilLabel.replacingOccurrences(of: "^Còn ", with: "", options: [.regularExpression])
            return trStatus(event.seats + " ▪︎ " + suffix)
        }
        return trStatus(event.seats)
    }
}

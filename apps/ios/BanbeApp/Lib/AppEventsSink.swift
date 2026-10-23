import Foundation
import UIKit

// First-party measurement (migration 196) — the iOS twin of the sink in src/lib/analytics.js. Events go to banbe's
// own database through log_app_events and nowhere else, only while the admin switch `app_events` is on AND someone
// is signed in (AppState installs this sink after sign-in and removes it on sign-out or when the switch goes off).

/// The ONLY event names and property keys that may leave the device. Same list as tests/fixtures/app-events.json
/// (asserted by AppEventsTests), src/lib/analytics.js `APP_EVENT_PROPS` and the server's app_event_names table.
enum AppEventsContract {
    static let allowed: [String: Set<String>] = [
        "app_opened": [],
        "event_opened": ["event_id", "source"],
        "ticket_opened": ["day_bucket"],
        "notification_opened": ["kind", "source"],
        "share_completed": ["channel", "context"],
        "follow_tapped": ["context"],
        "onboarding_started": [],
        "onboarding_question_viewed": ["question_id"],
        "onboarding_question_answered": ["question_id", "answer_count"],
        "onboarding_question_skipped": ["question_id"],
        "onboarding_completed": ["answered_questions", "skipped_all"],
        "personalized_results_viewed": ["match_bucket"],
        "first_event_opened": [],
        "first_event_saved": [],
        "first_reservation_started": [],
        "permission_prompted": ["permission"],
        "permission_result": ["permission", "result"],
        "public_entry_viewed": [],
        "public_entry_get_started": [],
        "public_entry_login": [],
        "public_story_opened": [],
        "public_story_completed": [],
        "public_story_skipped": ["step"],
        "guest_browse_started": [],
        "guest_signin_prompt_shown": ["context"],
        "guest_signin_prompt_accepted": ["context"],
        "create_event_started_blank": [],
        "recipe_opened": [],
        "recipe_fix_tapped": ["ingredient"],
        "submit_recipe_score": ["bucket"],
        "schedule_opened": [],
        "schedule_mode_selected": ["mode"],
        "schedule_day_selected": ["day_bucket"],
        "schedule_conflict_shown": ["count_bucket"],
        "banbe_schedule_add": [],
        "banbe_schedule_remove": [],
        "banbe_schedule_result": ["result"],
        "system_calendar_editor_opened": [],
        "system_calendar_editor_result": ["result"],
        "rewards_badge_celebrated": ["code"],
        "rewards_week_milestone": ["weeks"],
        "rewards_goal_set": ["goal"],
    ]
    static let maxValueLength = 64 // same cap as log_app_events
    static let maxPerCall = 50 // same cap as log_app_events

    /// Only whitelisted keys with short non-empty values; nil for a name the server would not keep.
    static func payload(_ event: AnalyticsEvent) -> AppEventPayload? {
        guard let keys = allowed[event.name] else { return nil }
        let props = event.properties.filter { keys.contains($0.key) && !$0.value.isEmpty && $0.value.count <= maxValueLength }
        return AppEventPayload(name: event.name, props: props)
    }
}

struct AppEventPayload: Codable, Equatable {
    let name: String
    let props: [String: String]
}

/// Batching sink: flushes every `flushInterval`, as soon as `batchSize` events are waiting, and when the app goes
/// to the background. Nothing is queued or sent unless `isEnabled()` and `isSignedIn()` both hold; a flush that
/// finds either false drops the queue instead. `send` never throws into the app.
final class AppEventsSink: AnalyticsSink {
    typealias Send = ([AppEventPayload]) async -> Void
    /// The account this sink sends for (AppState replaces the sink when the account changes).
    let owner: UUID?
    private let isEnabled: () -> Bool
    private let isSignedIn: () -> Bool
    private let send: Send
    private let batchSize: Int
    private let maxQueue = 200
    private let lock = NSLock()
    private var queue: [AppEventPayload] = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    init(owner: UUID? = nil, isEnabled: @escaping () -> Bool, isSignedIn: @escaping () -> Bool, send: @escaping Send,
         flushInterval: TimeInterval = 15, batchSize: Int = 20, schedule: Bool = true) {
        self.owner = owner
        self.isEnabled = isEnabled
        self.isSignedIn = isSignedIn
        self.send = send
        self.batchSize = batchSize
        guard schedule else { return }
        timer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            guard let self, self.count > 0 else { return }
            self.flush()
        }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.flush() }
    }

    deinit { stop() }

    var count: Int { lock.lock(); defer { lock.unlock() }; return queue.count }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled(), isSignedIn() else { clear(); return }
        guard let payload = AppEventsContract.payload(event) else { return }
        lock.lock()
        queue.append(payload)
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        let full = queue.count >= batchSize
        lock.unlock()
        if full { flush() }
    }

    /// Sends everything queued (in calls of at most 50), or drops it when the switch is off / nobody is signed in.
    func flush() {
        let allowed = isEnabled() && isSignedIn()
        lock.lock()
        let pending = queue
        queue.removeAll()
        lock.unlock()
        guard allowed, !pending.isEmpty else { return }
        let send = self.send
        let batches = stride(from: 0, to: pending.count, by: AppEventsContract.maxPerCall).map {
            Array(pending[$0..<min($0 + AppEventsContract.maxPerCall, pending.count)])
        }
        Task { for batch in batches { await send(batch) } }
    }

    func clear() { lock.lock(); queue.removeAll(); lock.unlock() }

    /// Stops the timer and the background observer and drops whatever is still queued (sign-out, switch off).
    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        clear()
    }
}

/// Small pure rules shared with src/lib/analytics.js (same vectors in AppEventsTests / appEvents.test.mjs).
enum AppEventRules {
    /// `event_opened.source` from the screen being left: home | search | map | schedule | other ('link' is passed
    /// by the deep-link opener itself).
    static func eventOpenSource(screen: Screen, searchOverlayOpen: Bool) -> String {
        switch screen {
        case .home: return searchOverlayOpen ? "search" : "home"
        case .search: return "search"
        case .mapExplore: return "map"
        case .schedule: return "schedule"
        default: return "other"
        }
    }

    /// `ticket_opened.day_bucket`: the event's calendar day vs today's, both in `timeZone` (the venue's zone).
    static func ticketDayBucket(start: Date, now: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let a = cal.dateComponents([.year, .month, .day], from: now)
        let b = cal.dateComponents([.year, .month, .day], from: start)
        let ka = (a.year ?? 0) * 10_000 + (a.month ?? 0) * 100 + (a.day ?? 0)
        let kb = (b.year ?? 0) * 10_000 + (b.month ?? 0) * 100 + (b.day ?? 0)
        return ka == kb ? "day_of" : (ka < kb ? "before" : "after")
    }

    static let appOpenedKey = "banbe.appEvents.openedDay.v1"

    /// Local calendar day as YYYY-MM-DD (device time zone).
    static func localDayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// True once per local day per device (and records that day).
    static func claimAppOpenedToday(_ defaults: UserDefaults = .standard, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let day = localDayKey(now, calendar: calendar)
        guard defaults.string(forKey: appOpenedKey) != day else { return false }
        defaults.set(day, forKey: appOpenedKey)
        return true
    }

    /// `share_completed.channel` from the share sheet's activity type: a fixed short name, never the raw identifier
    /// of a third-party app.
    static func shareChannel(_ type: UIActivity.ActivityType?) -> String {
        switch type {
        case .some(.message): return "messages"
        case .some(.mail): return "mail"
        case .some(.copyToPasteboard): return "copy"
        case .some(.airDrop): return "airdrop"
        case .some(.saveToCameraRoll): return "photos"
        default: return "other"
        }
    }
}

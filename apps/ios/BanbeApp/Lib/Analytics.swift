import Foundation
import os

// Product-funnel analytics boundary. There is NO analytics vendor in this app
// and none is added here: events go to `Analytics.sink`, a no-op by default
// (DEBUG builds also log them to the unified log under the "analytics"
// category). Wiring a provider = one type conforming to `AnalyticsSink`,
// assigned to `Analytics.sink` at launch, after a privacy review.
//
// Privacy contract — enforced by the TYPE, not by convention: an event can
// only carry the fields its case declares. Never add a case or property that
// carries raw preference values, DOB, precise location, message content,
// names, emails, phone numbers, event ids or user ids. Counts are bucketed.

enum AnalyticsEvent: Equatable {
    case onboardingStarted
    case onboardingQuestionViewed(question: String)
    /// Answer COUNT only, never which options.
    case onboardingQuestionAnswered(question: String, answerCount: Int)
    case onboardingQuestionSkipped(question: String)
    case onboardingCompleted(answeredQuestions: Int, skippedAll: Bool)
    case personalizedResultsViewed(matchBucket: String)
    case firstEventOpened
    case firstEventSaved
    case firstReservationStarted
    /// `permission` ∈ faceID | location.
    case permissionPrompted(permission: String)
    /// `result` ∈ granted | denied | unavailable.
    case permissionResult(permission: String, result: String)

    var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .onboardingQuestionViewed: return "onboarding_question_viewed"
        case .onboardingQuestionAnswered: return "onboarding_question_answered"
        case .onboardingQuestionSkipped: return "onboarding_question_skipped"
        case .onboardingCompleted: return "onboarding_completed"
        case .personalizedResultsViewed: return "personalized_results_viewed"
        case .firstEventOpened: return "first_event_opened"
        case .firstEventSaved: return "first_event_saved"
        case .firstReservationStarted: return "first_reservation_started"
        case .permissionPrompted: return "permission_prompted"
        case .permissionResult: return "permission_result"
        }
    }

    /// Flat, non-sensitive properties for a provider.
    var properties: [String: String] {
        switch self {
        case .onboardingQuestionViewed(let q), .onboardingQuestionSkipped(let q):
            return ["question_id": q]
        case .onboardingQuestionAnswered(let q, let n):
            return ["question_id": q, "answer_count": String(n)]
        case .onboardingCompleted(let n, let skipped):
            return ["answered_questions": String(n), "skipped_all": skipped ? "true" : "false"]
        case .personalizedResultsViewed(let bucket):
            return ["match_bucket": bucket]
        case .permissionPrompted(let p):
            return ["permission": p]
        case .permissionResult(let p, let r):
            return ["permission": p, "result": r]
        default:
            return [:]
        }
    }

    /// 0 · 1-2 · 3-5 · 6-10 · 11+ — never an exact count.
    static func bucket(_ n: Int) -> String {
        switch n {
        case ..<1: return "0"
        case 1...2: return "1-2"
        case 3...5: return "3-5"
        case 6...10: return "6-10"
        default: return "11+"
        }
    }
}

protocol AnalyticsSink: AnyObject {
    func track(_ event: AnalyticsEvent)
}

final class NoopAnalyticsSink: AnalyticsSink {
    func track(_ event: AnalyticsEvent) {}
}

/// Test/debug sink that just remembers what was tracked.
final class RecordingAnalyticsSink: AnalyticsSink {
    private(set) var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
}

enum Analytics {
    static var sink: AnalyticsSink = NoopAnalyticsSink()
    private static let log = Logger(subsystem: "com.banbe.ios", category: "analytics")

    static func track(_ event: AnalyticsEvent) {
        #if DEBUG
        log.debug("\(event.name, privacy: .public) \(event.properties.description, privacy: .public)")
        #endif
        sink.track(event)
    }

    /// `first_*` events fire once per account per device. The marker is a
    /// local boolean keyed by the account id — the id itself is never sent.
    static func trackFirst(_ event: AnalyticsEvent, userID: UUID?, defaults: UserDefaults = .standard) {
        guard let userID else { return }
        let key = "banbe.analytics.first.\(event.name).\(userID.uuidString)"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        track(event)
    }
}

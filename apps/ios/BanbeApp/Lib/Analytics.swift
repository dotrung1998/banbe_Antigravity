import Foundation
import os

// Product-funnel analytics boundary. There is NO analytics vendor in this app
// and none is added here: events go to `Analytics.sink`, a no-op by default
// (DEBUG builds also log them to the unified log under the "analytics"
// category). The only real sink is first-party: `AppEventsSink`
// (Lib/AppEventsSink.swift, migration 196), installed by AppState for a
// signed-in account while the admin switch `app_events` is on.
//
// Privacy contract — enforced by the TYPE, not by convention: an event can
// only carry the fields its case declares, and AppEventsContract drops any
// key tests/fixtures/app-events.json does not list. Never add a case or
// property that carries raw preference values, DOB, precise location, message
// content, names, emails, phone numbers or user ids. The one id allowed is a
// public event id on event_opened. Counts are bucketed.

enum AnalyticsEvent: Equatable {
    // Retention measurement (migration 196).
    /// Once per local day per device, on launch / foreground, signed in.
    case appOpened
    /// `source` ∈ home | search | map | schedule | link | other.
    case eventOpened(eventID: String, source: String)
    /// `dayBucket` ∈ day_of | before | after (the event's day vs today, venue zone).
    case ticketOpened(dayBucket: String)
    /// `kind` = the notification's fixed kind name; `source` ∈ bell | push.
    case notificationOpened(kind: String, source: String)
    /// Only when the share sheet reports `completed == true`. `channel` is a fixed short name (AppEventRules.shareChannel).
    case shareCompleted(channel: String, context: String)
    /// A tap that FOLLOWS a host (unfollowing is not counted). `context` ∈ host_profile | pulse.
    case followTapped(context: String)
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
    // Public entry (signed out).
    case publicEntryViewed
    case publicEntryGetStarted
    case publicEntryLogin
    case publicStoryOpened
    case publicStoryCompleted
    /// `step` = the story page index the person left from.
    case publicStorySkipped(step: Int)
    // Guest browsing + friction pass (note 48).
    case guestBrowseStarted
    /// `context` ∈ save | follow | reserve | message | like.
    case guestSignInPromptShown(context: String)
    case guestSignInPromptAccepted(context: String)
    case createEventStartedBlank
    // Recipe for success (note 50). Ingredient ids are fixed names (title, photos…), never content.
    case recipeOpened
    case recipeFixTapped(ingredient: String)
    /// `bucket` ∈ 0-3 | 4-6 | 7-8 | 9-10 — never the exact score.
    case submitRecipeScore(bucket: String)
    /// `field` is a create-form field id (name, photos…), never what was typed.
    case createEventStillNeededTapped(field: String)
    /// `type` is the primary event type key (supper, music…).
    case createEventTypeSelected(type: String)
    // Schedule.
    case scheduleOpened
    /// `mode` ∈ mine | discover.
    case scheduleModeSelected(mode: String)
    /// `bucket` ∈ past | today | next7 | later — never the date itself.
    case scheduleDaySelected(bucket: String)
    case scheduleConflictShown(countBucket: String)
    case banbeScheduleAdd
    case banbeScheduleRemove
    /// `result` ∈ added | alreadyAdded | removed | notPresent | ineligible.
    case banbeScheduleResult(result: String)
    case systemCalendarEditorOpened
    /// `result` ∈ saved | cancelled | deleted | unavailable.
    case systemCalendarEditorResult(result: String)
    // Rewards v2 (migration 192). Badge codes are fixed names; goal ∈ 0 | 1 | 2 | 4; weeks ∈ the milestone list.
    case rewardsBadgeCelebrated(code: String)
    case rewardsWeekMilestone(weeks: Int)
    case rewardsGoalSet(goal: Int)

    var name: String {
        switch self {
        case .appOpened: return "app_opened"
        case .eventOpened: return "event_opened"
        case .ticketOpened: return "ticket_opened"
        case .notificationOpened: return "notification_opened"
        case .shareCompleted: return "share_completed"
        case .followTapped: return "follow_tapped"
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
        case .publicEntryViewed: return "public_entry_viewed"
        case .publicEntryGetStarted: return "public_entry_get_started"
        case .publicEntryLogin: return "public_entry_login"
        case .publicStoryOpened: return "public_story_opened"
        case .publicStoryCompleted: return "public_story_completed"
        case .publicStorySkipped: return "public_story_skipped"
        case .guestBrowseStarted: return "guest_browse_started"
        case .guestSignInPromptShown: return "guest_signin_prompt_shown"
        case .guestSignInPromptAccepted: return "guest_signin_prompt_accepted"
        case .createEventStartedBlank: return "create_event_started_blank"
        case .recipeOpened: return "recipe_opened"
        case .recipeFixTapped: return "recipe_fix_tapped"
        case .submitRecipeScore: return "submit_recipe_score"
        case .createEventStillNeededTapped: return "create_event_still_needed_tapped"
        case .createEventTypeSelected: return "create_event_type_selected"
        case .scheduleOpened: return "schedule_opened"
        case .scheduleModeSelected: return "schedule_mode_selected"
        case .scheduleDaySelected: return "schedule_day_selected"
        case .scheduleConflictShown: return "schedule_conflict_shown"
        case .banbeScheduleAdd: return "banbe_schedule_add"
        case .banbeScheduleRemove: return "banbe_schedule_remove"
        case .banbeScheduleResult: return "banbe_schedule_result"
        case .systemCalendarEditorOpened: return "system_calendar_editor_opened"
        case .systemCalendarEditorResult: return "system_calendar_editor_result"
        case .rewardsBadgeCelebrated: return "rewards_badge_celebrated"
        case .rewardsWeekMilestone: return "rewards_week_milestone"
        case .rewardsGoalSet: return "rewards_goal_set"
        }
    }

    /// Flat, non-sensitive properties for a provider.
    var properties: [String: String] {
        switch self {
        case .eventOpened(let id, let source):
            return ["event_id": id, "source": source]
        case .ticketOpened(let bucket):
            return ["day_bucket": bucket]
        case .notificationOpened(let kind, let source):
            return ["kind": kind, "source": source]
        case .shareCompleted(let channel, let context):
            return ["channel": channel, "context": context]
        case .followTapped(let context):
            return ["context": context]
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
        case .publicStorySkipped(let step):
            return ["step": String(step)]
        case .guestSignInPromptShown(let c), .guestSignInPromptAccepted(let c):
            return ["context": c]
        case .recipeFixTapped(let ingredient):
            return ["ingredient": ingredient]
        case .submitRecipeScore(let bucket):
            return ["bucket": bucket]
        case .createEventStillNeededTapped(let field):
            return ["field": field]
        case .createEventTypeSelected(let type):
            return ["type": type]
        case .scheduleModeSelected(let mode):
            return ["mode": mode]
        case .scheduleDaySelected(let bucket):
            return ["day_bucket": bucket]
        case .scheduleConflictShown(let bucket):
            return ["count_bucket": bucket]
        case .banbeScheduleResult(let r), .systemCalendarEditorResult(let r):
            return ["result": r]
        case .rewardsBadgeCelebrated(let code):
            return ["code": code]
        case .rewardsWeekMilestone(let weeks):
            return ["weeks": String(weeks)]
        case .rewardsGoalSet(let goal):
            return ["goal": String(goal)]
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
    /// Note 64: the v3 tour shows the real screens without the person using them, so nothing is measured meanwhile.
    static var paused = false
    private static let log = Logger(subsystem: "com.banbe.ios", category: "analytics")

    static func track(_ event: AnalyticsEvent) {
        if paused { return }
        #if DEBUG
        log.debug("\(event.name, privacy: .public) \(event.properties.description, privacy: .public)")
        #endif
        sink.track(event)
    }

    /// `first_*` events fire once per account per device. The marker is a
    /// local boolean keyed by the account id — the id itself is never sent.
    static func trackFirst(_ event: AnalyticsEvent, userID: UUID?, defaults: UserDefaults = .standard) {
        guard let userID, !paused else { return }
        let key = "banbe.analytics.first.\(event.name).\(userID.uuidString)"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        track(event)
    }
}

import Foundation
import Supabase
import MapKit

/// Interest surveys (Slice B, migration 114) — mirrors web's GocContext.jsx
/// survey section function-for-function and RPC-for-RPC. One screen
/// (SurveyPublicView) serves both the dedicated browser-equivalent deep
/// link (/surveys/<publicId>, handled by AppState+Profile.swift's
/// handleUniversalLink) and in-app navigation (openSurveyPublic), sharing
/// the exact same backend calls — a survey is NOT a live event, booking,
/// ticket or payment commitment.

struct SurveyOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    // Structured date/time slot ('yyyy-MM-dd' / 'HH:mm', Vietnam time) for a
    // date option picked with the Create Event date/time controls. Nil for
    // older free-text options and for every non-date option set.
    var date: String? = nil
    var time: String? = nil
    // Structured address for a location option picked with the same address
    // search Create Event uses (all nil for older free-text options).
    var addressLine: String? = nil
    var district: String? = nil
    var city: String? = nil
    var postalCode: String? = nil
    var countryCode: String? = nil
    var stateProvince: String? = nil
    var neighborhood: String? = nil
    var lat: Double? = nil
    var lng: Double? = nil
    enum CodingKeys: String, CodingKey {
        case id, label, date, time, district, city, neighborhood, lat, lng
        case addressLine = "address_line"
        case postalCode = "postal_code"
        case countryCode = "country_code"
        case stateProvince = "state_province"
    }
}

/// `survey_event_candidates.location_data` — the location option's
/// structured address, snapshotted at generation time ('{}' for free text).
struct SurveyLocationData: Decodable, Equatable {
    var addressLine: String?
    var district: String?
    var city: String?
    var postalCode: String?
    var countryCode: String?
    var stateProvince: String?
    var neighborhood: String?
    var lat: Double?
    var lng: Double?
    enum CodingKeys: String, CodingKey {
        case district, city, neighborhood, lat, lng
        case addressLine = "address_line"
        case postalCode = "postal_code"
        case countryCode = "country_code"
        case stateProvince = "state_province"
    }
}

struct SurveyConfig: Codable, Equatable {
    var dateOptions: [SurveyOption] = []
    var locationOptions: [SurveyOption] = []
    var budgetOptions: [SurveyOption] = []
    var activityOptions: [SurveyOption] = []
    var groupSizeMin: Int?
    var groupSizeMax: Int?
    // Postgres booleans inside a jsonb column decode fine as Bool; a
    // missing key (a field the host never marked required) decodes as
    // simply absent from the dictionary, read as `false` by the accessor
    // below rather than requiring every key to be present.
    var required: [String: Bool] = [:]
    enum CodingKeys: String, CodingKey {
        case dateOptions = "date_options"
        case locationOptions = "location_options"
        case budgetOptions = "budget_options"
        case activityOptions = "activity_options"
        case groupSizeMin = "group_size_min"
        case groupSizeMax = "group_size_max"
        case required
    }
    func isRequired(_ key: String) -> Bool { required[key] == true }
}

/// Exactly get_survey_public()'s return shape (never raw table rows) — the
/// public route can never expose more than this RPC's own allowlisted
/// fields, same guarantee as web's identical function.
struct SurveyPublic: Decodable, Equatable {
    let success: Bool?
    let error: String?
    let surveyId: UUID?
    let publicId: String?
    let title: String?
    let description: String?
    let hostName: String?
    let timezone: String?
    let opensAt: Date?
    let closesAt: Date?
    // "active" | "closed" | "not_open_yet" — computed server-side against
    // real time, not the stored column alone (the closure worker may not
    // have run yet).
    let status: String?
    let config: SurveyConfig?
    let configVersion: Int?
    enum CodingKeys: String, CodingKey {
        case success, error
        case surveyId = "survey_id"
        case publicId = "public_id"
        case title, description
        case hostName = "host_name"
        case timezone
        case opensAt = "opens_at"
        case closesAt = "closes_at"
        case status, config
        case configVersion = "config_version"
    }
}

/// A raw `surveys` row, for the host's own management list
/// (surveys_select_host RLS — host/admin only, never the public route).
struct SurveySummary: Decodable, Identifiable, Equatable {
    let id: UUID
    let organizerId: String
    let publicId: String
    let title: String
    let description: String?
    let status: String
    let closesAt: Date?
    enum CodingKeys: String, CodingKey {
        case id
        case organizerId = "organizer_id"
        case publicId = "public_id"
        case title, description, status
        case closesAt = "closes_at"
    }
}

/// A `survey_event_candidates` row (migration 143) — a server-scored
/// "date x location" idea derived from a closed survey's responses.
struct SurveyCandidate: Decodable, Identifiable, Equatable {
    let id: UUID
    let surveyId: UUID
    let dateLabel: String
    let locationLabel: String
    let budgetLabel: String
    let activityLabels: [String]
    let dateValue: String
    let timeValue: String
    let locationData: SurveyLocationData?
    let supporterCount: Int
    let responseTotal: Int
    let consentCount: Int
    let suggestedGroupSize: Int?
    let score: Double
    var status: String
    enum CodingKeys: String, CodingKey {
        case id
        case surveyId = "survey_id"
        case dateLabel = "date_label"
        case locationLabel = "location_label"
        case budgetLabel = "budget_label"
        case activityLabels = "activity_labels"
        case dateValue = "date_value"
        case timeValue = "time_value"
        case locationData = "location_data"
        case supporterCount = "supporter_count"
        case responseTotal = "response_total"
        case consentCount = "consent_count"
        case suggestedGroupSize = "suggested_group_size"
        case score, status
    }
}

/// A raw `survey_responses` row — RLS already scopes SELECT to the
/// respondent's own row or the survey's host/admin (never another
/// respondent's name/answers).
struct SurveyResponseRow: Decodable, Equatable {
    let id: UUID
    let surveyId: UUID
    let respondentId: UUID
    let interestLevel: Int?
    let dateOptions: [String]
    let groupSize: Int?
    let locationOptions: [String]
    let budgetOption: String?
    let activities: [String]
    let freeText: String
    let contactConsent: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case surveyId = "survey_id"
        case respondentId = "respondent_id"
        case interestLevel = "interest_level"
        case dateOptions = "date_options"
        case groupSize = "group_size"
        case locationOptions = "location_options"
        case budgetOption = "budget_option"
        case activities
        case freeText = "free_text"
        case contactConsent = "contact_consent"
    }
}

/// The signed-in respondent's in-progress answer — plain local state, no
/// sessionStorage-equivalent persistence on iOS (unlike web's browser
/// page): the app itself is the durable session, so there's no separate
/// "auth round trip loses the draft" risk a browser tab reload has.
struct SurveyDraft: Equatable {
    var interestLevel: Int?
    var dateOptions: [String] = []
    var groupSize: Int?
    var locationOptions: [String] = []
    var budgetOption: String?
    var activities: [String] = []
    var freeText: String = ""
    var contactConsent: Bool = false
}

extension AppState {
    // ==================== Respondent side ====================

    /// In-app navigation to the same screen the universal-link deep link
    /// (/surveys/<publicId>) uses — one screen, one backend.
    func openSurveyPublic(publicID: String, back: Screen = .home) async {
        surveyPublicBackScreen = back
        surveyPublic = nil
        surveyPublicLoading = true
        surveyPublicError = ""
        surveyPublicID = publicID
        surveyResponseSuccess = false
        surveyResponseError = ""
        surveyEditMode = false
        surveyDraft = SurveyDraft()
        mySurveyResponse = nil
        surveyRespondStep = "idle"; surveyRespondEmail = ""; surveyRespondCode = ""; surveyRespondError = ""; surveyRespondConsent = false
        screen = .surveyPublic
        do {
            let result: SurveyPublic = try await SupabaseService.client
                .rpc("get_survey_public", params: ["p_public_id": publicID])
                .execute().value
            guard result.success == true else {
                surveyPublicLoading = false
                surveyPublicError = T("Không tìm thấy khảo sát này.", "This survey couldn't be found.")
                return
            }
            surveyPublic = result
            surveyPublicLoading = false
            if let surveyID = result.surveyId, isSignedIn {
                await loadMySurveyResponse(surveyID: surveyID)
            }
        } catch {
            print("openSurveyPublic failed:", error)
            surveyPublicLoading = false
            surveyPublicError = T("Không tìm thấy khảo sát này.", "This survey couldn't be found.")
        }
    }

    /// The signed-in respondent's own existing answer, if any — loaded
    /// separately from get_survey_public (anon-reachable, must never carry
    /// one respondent's data). Pre-fills the draft so re-opening an
    /// already-answered survey shows the real answer, not a blank form.
    func loadMySurveyResponse(surveyID: UUID) async {
        mySurveyResponseLoading = true
        do {
            let rows: [SurveyResponseRow] = try await SupabaseService.client
                .from("survey_responses").select()
                .eq("survey_id", value: surveyID.uuidString)
                .limit(1)
                .execute().value
            mySurveyResponseLoading = false
            guard let row = rows.first else { return }
            mySurveyResponse = row
            surveyDraft = SurveyDraft(
                interestLevel: row.interestLevel, dateOptions: row.dateOptions, groupSize: row.groupSize,
                locationOptions: row.locationOptions, budgetOption: row.budgetOption, activities: row.activities,
                freeText: row.freeText, contactConsent: row.contactConsent
            )
        } catch {
            print("loadMySurveyResponse failed:", error)
            mySurveyResponseLoading = false
        }
    }

    /// The one submission path — server (submit_survey_response, migration
    /// 114) is the real validation/closure gate, this is just the UI-facing
    /// wrapper. Requires a signed-in identity; the view itself is what
    /// prompts sign-in first.
    func submitSurveyResponse() async {
        guard let surveyID = surveyPublic?.surveyId else { return }
        surveyResponseSubmitting = true
        surveyResponseError = ""
        struct Params: Encodable {
            let surveyId: UUID
            let interestLevel: Int?
            let dateOptions: [String]
            let groupSize: Int?
            let locationOptions: [String]
            let budgetOption: String?
            let activities: [String]
            let freeText: String
            let contactConsent: Bool
            enum CodingKeys: String, CodingKey {
                case surveyId = "p_survey_id", interestLevel = "p_interest_level", dateOptions = "p_date_options"
                case groupSize = "p_group_size", locationOptions = "p_location_options", budgetOption = "p_budget_option"
                case activities = "p_activities", freeText = "p_free_text", contactConsent = "p_contact_consent"
            }
        }
        let d = surveyDraft
        do {
            let _: SurveyResponseRow = try await SupabaseService.client
                .rpc("submit_survey_response", params: Params(
                    surveyId: surveyID, interestLevel: d.interestLevel, dateOptions: d.dateOptions,
                    groupSize: d.groupSize, locationOptions: d.locationOptions, budgetOption: d.budgetOption,
                    activities: d.activities, freeText: d.freeText, contactConsent: d.contactConsent
                ))
                .execute().value
            surveyResponseSubmitting = false
            surveyResponseSuccess = true
            Haptics.success()
        } catch {
            surveyResponseSubmitting = false
            let code = (error as? PostgrestError)?.message ?? ""
            surveyResponseError = [
                "NOT_AUTHENTICATED": T("Bạn cần đăng nhập để trả lời.", "You need to sign in to respond."),
                "SURVEY_NOT_ACTIVE": T("Khảo sát này hiện không mở.", "This survey isn't open right now."),
                "SURVEY_CLOSED": T("Khảo sát này đã đóng.", "This survey has closed."),
                "SURVEY_NOT_OPEN_YET": T("Khảo sát này chưa mở.", "This survey hasn't opened yet."),
                "DATE_OPTIONS_REQUIRED": T("Vui lòng chọn ít nhất một ngày.", "Please pick at least one date."),
                "LOCATION_OPTIONS_REQUIRED": T("Vui lòng chọn ít nhất một địa điểm.", "Please pick at least one location."),
                "BUDGET_REQUIRED": T("Vui lòng chọn mức ngân sách.", "Please pick a budget range."),
                "ACTIVITIES_REQUIRED": T("Vui lòng chọn ít nhất một hoạt động.", "Please pick at least one activity."),
                "GROUP_SIZE_REQUIRED": T("Vui lòng nhập số người.", "Please enter a group size."),
                "INVALID_GROUP_SIZE": T("Số người không hợp lệ.", "That group size isn't valid."),
                "INTEREST_LEVEL_REQUIRED": T("Vui lòng chọn mức độ quan tâm.", "Please pick an interest level."),
            ][code] ?? T("Không thể gửi câu trả lời. Vui lòng thử lại.", "Could not submit your response. Please try again.")
        }
    }

    func toggleSurveyEditMode(_ on: Bool) { surveyEditMode = on }

    /// Section 2 — open the same SurveyPublicView content as a `.fullScreenCover`
    /// over whatever's currently showing (a paused story) instead of
    /// navigating `screen` away — RootView watches `storySurveyModalPublicID`
    /// and StoryViewerView pauses via its existing `isSuspended` the same
    /// way it already does for an Event Detail sheet on top.
    func openSurveyStoryModal(publicID: String) async {
        storySurveyModalPublicID = publicID
        surveyPublic = nil
        surveyPublicLoading = true
        surveyPublicError = ""
        surveyPublicID = publicID
        surveyResponseSuccess = false
        surveyResponseError = ""
        surveyEditMode = false
        surveyDraft = SurveyDraft()
        mySurveyResponse = nil
        surveyRespondStep = "idle"; surveyRespondEmail = ""; surveyRespondCode = ""; surveyRespondError = ""; surveyRespondConsent = false
        do {
            let result: SurveyPublic = try await SupabaseService.client
                .rpc("get_survey_public", params: ["p_public_id": publicID])
                .execute().value
            guard result.success == true else {
                surveyPublicLoading = false
                surveyPublicError = T("Không tìm thấy khảo sát này.", "This survey couldn't be found.")
                return
            }
            surveyPublic = result
            surveyPublicLoading = false
            if let surveyID = result.surveyId, isSignedIn {
                await loadMySurveyResponse(surveyID: surveyID)
            }
        } catch {
            print("openSurveyStoryModal failed:", error)
            surveyPublicLoading = false
            surveyPublicError = T("Không tìm thấy khảo sát này.", "This survey couldn't be found.")
        }
    }

    /// `discard` clears nothing persisted on iOS (no sessionStorage-
    /// equivalent draft cache to begin with — see SurveyDraft's own doc
    /// comment), it just resets the in-memory draft so reopening the same
    /// survey from the same story doesn't resurface answers the respondent
    /// explicitly threw away.
    func closeSurveyStoryModal(discard: Bool = false) {
        if discard { surveyDraft = SurveyDraft() }
        storySurveyModalPublicID = nil
        surveyPublic = nil
    }

    // ==================== Section 3: lightweight respondent verification ====================

    /// Step 1 — request the code. Requires `surveyRespondConsent` first —
    /// the explicit, additive consent path for a respondent who never saw
    /// the ordinary Login screen's own checkbox.
    func sendSurveyRespondCode(email: String) async {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.contains("@"), clean.contains(".") else {
            surveyRespondError = T("Nhập email hợp lệ.", "Enter a valid email.")
            return
        }
        guard surveyRespondConsent else {
            surveyRespondError = T("Vui lòng đồng ý trước khi tiếp tục.", "Please agree before continuing.")
            return
        }
        surveyRespondSending = true
        surveyRespondError = ""
        do {
            let isNew = try await AuthAPIService.requestRespondEmailCode(
                email: clean, displayName: T("Khách trả lời khảo sát", "Survey respondent")
            )
            surveyRespondSending = false
            surveyRespondStep = "codeSent"
            surveyRespondEmail = clean
            surveyRespondIsNewAccount = isNew
        } catch {
            surveyRespondSending = false
            surveyRespondError = T("Không thể gửi mã. Vui lòng thử lại.", "Could not send the code. Please try again.")
        }
    }

    /// Step 2 — verify. A brand-new identity was created via the "signup"
    /// linkType server-side (api/auth's isRespondMode branch), so it
    /// verifies the same way; the resulting real session resolves
    /// `submit_survey_response`'s identity via its own auth.uid() — never a
    /// client-supplied id.
    func verifySurveyRespondCode() async {
        let token = surveyRespondCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            surveyRespondError = T("Nhập mã đã gửi tới email của bạn.", "Enter the code sent to your email.")
            return
        }
        surveyRespondSending = true
        surveyRespondError = ""
        do {
            try await SupabaseService.client.auth.verifyOTP(
                email: surveyRespondEmail, token: token, type: surveyRespondIsNewAccount ? .signup : .email
            )
            surveyRespondSending = false
            surveyRespondStep = "idle"
            surveyRespondCode = ""
        } catch {
            surveyRespondSending = false
            surveyRespondError = T("Mã không đúng hoặc đã hết hạn.", "That code is wrong or has expired.")
        }
    }

    // ==================== Host side: Hosting -> Surveys & Event Ideas ====================

    func loadMySurveys() async {
        guard let organizerID = myOrganizerID else { return }
        mySurveysLoading = true
        do {
            let rows: [SurveySummary] = try await SupabaseService.client
                .from("surveys").select()
                .eq("organizer_id", value: organizerID)
                .order("created_at", ascending: false)
                .execute().value
            mySurveys = rows
            // "Not Shared To Story" status — see `mySurveySharedIds`'s own
            // doc comment (AppState.swift). One lightweight query, scoped to
            // this organizer's own rows (ordinary host-owner RLS, the same
            // access `loadHomeStories()`'s own `ownRows` branch already
            // relies on) — never a guess from `mySurveys` alone, which has
            // no way to know whether a `stories` row exists for a survey.
            struct ShareRow: Decodable { let surveyId: UUID?
                enum CodingKeys: String, CodingKey { case surveyId = "survey_id" } }
            let shareRows: [ShareRow] = (try? await SupabaseService.client
                .from("stories").select("survey_id")
                .eq("organizer_id", value: organizerID)   // survey_share rows AND edited (photo) survey stories
                .execute().value) ?? []
            mySurveySharedIds = Set(shareRows.compactMap(\.surveyId))
        } catch {
            print("loadMySurveys failed:", error)
            mySurveys = []
            mySurveySharedIds = []
        }
        mySurveysLoading = false
    }

    @discardableResult
    func createSurvey(title: String, description: String, closesInDays: Int, config: SurveyConfig) async -> Bool {
        guard let organizerID = myOrganizerID else { return false }
        mySurveyCreateBusy = true
        mySurveyCreateError = ""
        struct Params: Encodable {
            let organizerId: String
            let title: String
            let description: String
            let opensAt: Date
            let closesAt: Date
            let timezone: String
            let config: SurveyConfig
            enum CodingKeys: String, CodingKey {
                case organizerId = "p_organizer_id", title = "p_title", description = "p_description"
                case opensAt = "p_opens_at", closesAt = "p_closes_at", timezone = "p_timezone", config = "p_config"
            }
        }
        let now = Date()
        let closes = now.addingTimeInterval(Double(max(1, closesInDays)) * 86400)
        do {
            let _: SurveySummary = try await SupabaseService.client
                .rpc("create_survey", params: Params(
                    organizerId: organizerID, title: title, description: description,
                    opensAt: now, closesAt: closes, timezone: "Asia/Ho_Chi_Minh", config: config
                ))
                .execute().value
            mySurveyCreateBusy = false
            await loadMySurveys()
            return true
        } catch {
            let code = (error as? PostgrestError)?.message ?? ""
            mySurveyCreateError = [
                "TITLE_REQUIRED": T("Vui lòng nhập tiêu đề.", "Please enter a title."),
                "INVALID_WINDOW": T("Hạn chót phải sau thời điểm mở.", "The deadline must be after the opening time."),
            ][code] ?? T("Không thể tạo khảo sát. Vui lòng thử lại.", "Could not create the survey. Please try again.")
            mySurveyCreateBusy = false
            return false
        }
    }

    func publishSurvey(_ surveyID: UUID) async {
        do {
            let _: SurveySummary = try await SupabaseService.client
                .rpc("publish_survey", params: ["p_survey_id": surveyID.uuidString]).execute().value
            Haptics.success()
            await loadMySurveys()
        } catch { print("publishSurvey failed:", error) }
    }
    func closeSurveyEarly(_ surveyID: UUID) async {
        do {
            let _: SurveySummary = try await SupabaseService.client
                .rpc("close_survey", params: ["p_survey_id": surveyID.uuidString]).execute().value
            await loadMySurveys()
        } catch { print("closeSurvey failed:", error) }
    }
    func archiveSurvey(_ surveyID: UUID) async {
        do {
            let _: SurveySummary = try await SupabaseService.client
                .rpc("archive_survey", params: ["p_survey_id": surveyID.uuidString]).execute().value
            await loadMySurveys()
        } catch { print("archiveSurvey failed:", error) }
    }
    /// Draft-only (migration 116) — a published survey may already have
    /// real respondent answers; archive_survey is the correct action once
    /// a survey has ever been live, not delete.
    func deleteSurvey(_ surveyID: UUID) async {
        do {
            let _: Bool = try await SupabaseService.client
                .rpc("delete_survey", params: ["p_survey_id": surveyID.uuidString]).execute().value
            await loadMySurveys()
        } catch { print("deleteSurvey failed:", error) }
    }

    // ==================== Slice C: suggested event drafts ====================

    /// Candidates for the host's closed/archived surveys (host/admin RLS).
    /// The scoring runs server-side when a survey closes (migration 143).
    func loadSurveyCandidates() async {
        let ids = mySurveys.filter { $0.status == "closed" || $0.status == "archived" }.map { $0.id.uuidString }
        guard !ids.isEmpty else { mySurveyCandidates = []; mySurveyCandidatesError = ""; return }
        mySurveyCandidatesLoading = true
        mySurveyCandidatesError = ""
        do {
            let rows: [SurveyCandidate] = try await SupabaseService.client
                .from("survey_event_candidates").select()
                .in("survey_id", values: ids)
                .order("score", ascending: false)
                .execute().value
            mySurveyCandidates = rows
        } catch {
            print("loadSurveyCandidates failed:", error)
            mySurveyCandidates = []
            mySurveyCandidatesError = T("Không thể tải gợi ý sự kiện.", "Could not load suggested event drafts.")
        }
        mySurveyCandidatesLoading = false
    }

    func refreshSurveyCandidates(_ surveyID: UUID) async {
        mySurveyCandidatesBusySurveyID = surveyID
        defer { mySurveyCandidatesBusySurveyID = nil }
        do {
            let _: Int = try await SupabaseService.client
                .rpc("generate_survey_candidates", params: ["p_survey_id": surveyID.uuidString]).execute().value
            await loadSurveyCandidates()
        } catch {
            print("refreshSurveyCandidates failed:", error)
            mySurveyCandidatesError = T("Không thể làm mới gợi ý.", "Could not refresh suggestions.")
        }
    }

    func dismissSurveyCandidate(_ candidate: SurveyCandidate) async {
        do {
            try await SupabaseService.client
                .rpc("set_survey_candidate_status", params: ["p_candidate_id": candidate.id.uuidString, "p_status": "dismissed"])
                .execute()
            setCandidateStatusLocally([candidate.id], "dismissed")
        } catch { print("dismissSurveyCandidate failed:", error) }
    }

    /// Dismissed drafts stay listed (behind "Show dismissed") so a mis-tap
    /// is never permanent.
    func restoreSurveyCandidate(_ candidate: SurveyCandidate) async {
        do {
            try await SupabaseService.client
                .rpc("set_survey_candidate_status", params: ["p_candidate_id": candidate.id.uuidString, "p_status": "suggested"])
                .execute()
            setCandidateStatusLocally([candidate.id], "suggested")
        } catch { print("restoreSurveyCandidate failed:", error) }
    }

    private func setCandidateStatusLocally(_ ids: Set<UUID>, _ status: String) {
        mySurveyCandidates = mySurveyCandidates.map { c in
            guard ids.contains(c.id) else { return c }
            var copy = c
            copy.status = status
            return copy
        }
    }

    /// Dismiss / restore many drafts at once (dismiss selected, dismiss all).
    func setSurveyCandidatesStatus(_ ids: [UUID], _ status: String) async {
        guard !ids.isEmpty else { return }
        struct Params: Encodable {
            let ids: [String]
            let status: String
            enum CodingKeys: String, CodingKey { case ids = "p_candidate_ids", status = "p_status" }
        }
        do {
            let _: Int = try await SupabaseService.client
                .rpc("set_survey_candidates_status", params: Params(ids: ids.map(\.uuidString), status: status))
                .execute().value
            setCandidateStatusLocally(Set(ids), status)
        } catch { print("setSurveyCandidatesStatus failed:", error) }
    }

    /// Closed surveys -> Archived (one, several or all) and back, so
    /// archiving is never a one-way door.
    func archiveSurveys(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        do {
            let _: Int = try await SupabaseService.client
                .rpc("archive_surveys", params: ["p_survey_ids": ids.map(\.uuidString)])
                .execute().value
            await loadMySurveys()
        } catch { print("archiveSurveys failed:", error) }
    }
    /// Permanent. Archived surveys only (the server enforces it); cascades to
    /// the survey's responses, ideas and story shares. Callers confirm first.
    func deleteArchivedSurveys(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        do {
            let _: Int = try await SupabaseService.client
                .rpc("delete_archived_surveys", params: ["p_survey_ids": ids.map(\.uuidString)])
                .execute().value
            let gone = Set(ids)
            mySurveyCandidates.removeAll { gone.contains($0.surveyId) }
            await loadMySurveys()
        } catch { print("deleteArchivedSurveys failed:", error) }
    }
    /// Permanent. Only ideas already in Archived ("used").
    func deleteSurveyCandidates(_ ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        do {
            let _: Int = try await SupabaseService.client
                .rpc("delete_survey_candidates", params: ["p_candidate_ids": ids.map(\.uuidString)])
                .execute().value
            let gone = Set(ids)
            mySurveyCandidates.removeAll { gone.contains($0.id) }
        } catch { print("deleteSurveyCandidates failed:", error) }
    }
    func unarchiveSurvey(_ id: UUID) async {
        do {
            try await SupabaseService.client
                .rpc("unarchive_survey", params: ["p_survey_id": id.uuidString]).execute()
            await loadMySurveys()
        } catch { print("unarchiveSurvey failed:", error) }
    }

    /// Same MapKit search + result type Create Event's address picker uses,
    /// but stateless (no `create*` state touched), so the survey form can
    /// pick structured locations without disturbing an event draft.
    func searchSurveyAddresses(_ rawQuery: String) async -> (suggestions: [AddressSuggestion], error: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return ([], "") }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10.7769, longitude: 106.7009),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            let found = response.mapItems.compactMap(AddressSuggestion.init(mapItem:))
            return (found, found.isEmpty ? T("Không tìm thấy địa chỉ nào. Thử ghi rõ số nhà và đường.", "No addresses found. Try including a house number and street.") : "")
        } catch {
            if Task.isCancelled { return ([], "") }
            return ([], T("Không thể tìm địa chỉ lúc này. Kiểm tra kết nối rồi thử lại.", "Couldn't search addresses right now. Check your connection and retry."))
        }
    }

    /// "Use This Idea" -> Create Event, pre-filled. Date options are the
    /// host's own free-text labels (not parseable dates) and the location is
    /// a label, not a confirmed address — so those become description hints
    /// and the host still picks the real date and confirms the real
    /// address. Nothing is created or submitted by this.
    func applySurveyCandidate(_ candidate: SurveyCandidate, survey: SurveySummary) {
        let hints = [
            (candidate.dateLabel.isEmpty || !candidate.dateValue.isEmpty) ? nil : "\(T("Thời gian được quan tâm nhất", "Most-wanted time")): \(candidate.dateLabel)",
            candidate.locationLabel.isEmpty ? nil : "\(T("Khu vực", "Area")): \(candidate.locationLabel)",
            candidate.budgetLabel.isEmpty ? nil : "\(T("Ngân sách phổ biến", "Common budget")): \(candidate.budgetLabel)",
            candidate.activityLabels.isEmpty ? nil : "\(T("Hoạt động", "Activities")): \(candidate.activityLabels.joined(separator: ", "))",
        ].compactMap { $0 }.joined(separator: "\n")
        goCreate()
        createName = survey.title
        createDesc = [survey.description ?? "", hints].filter { !$0.isEmpty }.joined(separator: "\n\n")
        createLoc = candidate.locationLabel
        // Structured slot from the survey -> the exact Date values Create
        // Event's own date/time sheet works with (Vietnam time).
        if !candidate.dateValue.isEmpty, !candidate.timeValue.isEmpty,
           let d = AppState.vnDateFormatter.date(from: candidate.dateValue),
           let t = AppState.vnTimeFormatter.date(from: candidate.timeValue + ":00") {
            createEventDate = d
            createEventTime = t
        }
        // A location picked with the address search carries the full
        // structured address — Create Event opens with it already confirmed
        // (same fields selectCreateAddressSuggestion sets).
        if let loc = candidate.locationData, let lat = loc.lat, let lng = loc.lng {
            createAddressLine = loc.addressLine ?? ""
            createDistrict = loc.district ?? ""
            createCity = loc.city ?? ""
            createPostalCode = loc.postalCode ?? ""
            createCountryCode = loc.countryCode ?? ""
            createStateProvince = loc.stateProvince ?? ""
            createNeighborhood = loc.neighborhood ?? ""
            createLat = lat
            createLng = lng
            createLocLabel = candidate.locationLabel
            createLocConfirmed = true
        }
        createSeats = candidate.suggestedGroupSize.map(String.init) ?? ""
        createKeywords = candidate.activityLabels.joined(separator: ", ")
        Task {
            _ = try? await SupabaseService.client
                .rpc("set_survey_candidate_status", params: ["p_candidate_id": candidate.id.uuidString, "p_status": "used"])
                .execute()
        }
        setCandidateStatusLocally([candidate.id], "used")
    }

    /// Task 4 — "Share Link": native share sheet, through the canonical
    /// `AppConfig.publicWebOrigin` (never the unavailable banbe.app).
    func shareSurveyLink(_ survey: SurveySummary) -> URL? {
        URL(string: AppConfig.publicWebOrigin + "/surveys/" + survey.publicId)
    }

    /// Task 4 — "Share To Story": opens a preview (SurveysHostingView's own
    /// confirm sheet), never posts automatically. The real story row is
    /// only created on explicit Publish (confirmShareSurveyToStory).
    func openShareToStoryConfirm(_ survey: SurveySummary) {
        surveyShareToStoryTarget = survey
        surveyShareToStoryError = ""
    }
    func closeShareToStoryConfirm() {
        surveyShareToStoryTarget = nil
        surveyShareToStoryError = ""
    }
    func confirmShareSurveyToStory() async {
        guard let survey = surveyShareToStoryTarget else { return }
        surveyShareToStoryBusy = true
        surveyShareToStoryError = ""
        do {
            let _: Story = try await SupabaseService.client
                .rpc("create_survey_share_story", params: ["p_survey_id": survey.id.uuidString]).execute().value
            surveyShareToStoryBusy = false
            surveyShareToStoryTarget = nil
            // Refreshes `mySurveySharedIds` too — without this, the "Not
            // Shared To Story" label this pass adds would keep showing
            // stale right after a successful share, on the very screen the
            // host just acted from.
            await loadMySurveys()
            await loadHomeStories()
        } catch {
            let code = (error as? PostgrestError)?.message ?? ""
            surveyShareToStoryBusy = false
            surveyShareToStoryError = code == "SURVEY_NOT_ACTIVE"
                ? T("Chỉ khảo sát đang mở mới có thể chia sẻ lên story.", "Only an active survey can be shared to a story.")
                : T("Không thể đăng lên story. Vui lòng thử lại.", "Could not post to story. Please try again.")
        }
    }

    // ============ Section 5 — Home survey discovery (source-of-discovery
    // pass, migration 120) ============
    // Replaces the old `stories`/`survey_share`-row-based feed entirely:
    // PUBLISHING an eligible public survey makes it discoverable, whether
    // or not it was ever explicitly shared to a story — that remains a
    // separate, optional action (Share To Story / `mySurveySharedIds`
    // above). Reads `get_public_survey_discovery()` directly, an
    // authenticated-only, allowlisted-field RPC — never the raw `surveys`
    // table, and never respondent data.

    private static let surveyDiscoveryInitialPageSize = 3
    private static let surveyDiscoveryPageSize = 10

    private struct SurveyDiscoveryRow: Decodable {
        let surveyId: UUID
        let publicId: String
        let title: String
        let organizerId: String
        let hostName: String?
        let hostAvatarPath: String?
        let closesAt: Date?
        let createdAt: Date
        enum CodingKeys: String, CodingKey {
            case surveyId = "survey_id", publicId = "public_id", title
            case organizerId = "organizer_id", hostName = "host_name", hostAvatarPath = "host_avatar_path"
            case closesAt = "closes_at", createdAt = "created_at"
        }
    }
    private struct SurveyDiscoveryResponse: Decodable {
        let success: Bool
        let error: String?
        let surveys: [SurveyDiscoveryRow]?
        let hasMore: Bool?
        enum CodingKeys: String, CodingKey { case success, error, surveys, hasMore = "has_more" }
    }
    private struct SurveyDiscoveryParams: Encodable {
        let cursorCreatedAt: Date?
        let cursorId: String?
        let limit: Int
        enum CodingKeys: String, CodingKey {
            case cursorCreatedAt = "p_cursor_created_at", cursorId = "p_cursor_id", limit = "p_limit"
        }
    }

    private func fetchSurveyDiscoveryPage(cursorCreatedAt: Date?, cursorId: UUID?, limit: Int) async throws -> ([SurveyDiscoveryCard], Bool) {
        let response: SurveyDiscoveryResponse = try await SupabaseService.client
            .rpc("get_public_survey_discovery", params: SurveyDiscoveryParams(
                cursorCreatedAt: cursorCreatedAt, cursorId: cursorId?.uuidString, limit: limit
            ))
            .execute().value
        guard response.success else {
            throw NSError(domain: "SurveyDiscovery", code: 0, userInfo: [NSLocalizedDescriptionKey: response.error ?? "unknown"])
        }
        let cards = (response.surveys ?? []).map { row -> SurveyDiscoveryCard in
            // Avatar pass — same public-bucket resolver (`organizer-photos`,
            // synchronous `getPublicURL`) every other organizer avatar in
            // this app already uses — no signing, no extra network call.
            let avatarURL: URL? = {
                MediaURLs.organizerAvatar(path: row.hostAvatarPath, r2Ref: nil, variant: .thumb)
            }()
            return SurveyDiscoveryCard(
                organizerId: row.organizerId, surveyId: row.surveyId, publicId: row.publicId,
                title: row.title, hostName: row.hostName ?? "", hostAvatarURL: avatarURL,
                closesAt: row.closesAt, createdAt: row.createdAt
            )
        }
        return (cards, response.hasMore ?? false)
    }

    /// Fresh load — called on Home's initial mount, pull-to-refresh, and
    /// after an account change. Resets pagination state entirely so a new
    /// account (or a re-sign-in) never inherits a stale cursor/page from
    /// the previous session. Starts at a small page (3) so the collapsed→
    /// expanded header always opens onto a short, immediately-readable list
    /// — `loadMoreHomeSurveyDiscovery()` below fetches larger pages after.
    func loadHomeSurveyDiscovery() async {
        guard userID != nil else {
            homeSurveyDiscovery = []
            homeSurveyDiscoveryLoading = false; homeSurveyDiscoveryError = ""
            homeSurveyDiscoveryHasMore = false
            homeSurveyDiscoveryCursorCreatedAt = nil; homeSurveyDiscoveryCursorId = nil
            homeSurveyDiscoveryExpanded = false
            return
        }
        homeSurveyDiscoveryGeneration += 1
        let generation = homeSurveyDiscoveryGeneration
        homeSurveyDiscoveryLoading = true
        homeSurveyDiscoveryError = ""
        do {
            let (cards, hasMore) = try await fetchSurveyDiscoveryPage(cursorCreatedAt: nil, cursorId: nil, limit: Self.surveyDiscoveryInitialPageSize)
            // Stale-async-result guard — a newer call (or a sign-out/
            // account-switch) already superseded this one; never let a
            // slow, older response overwrite the current, correct state.
            guard generation == homeSurveyDiscoveryGeneration else { return }
            homeSurveyDiscovery = cards
            homeSurveyDiscoveryHasMore = hasMore
            homeSurveyDiscoveryCursorCreatedAt = cards.last?.createdAt
            homeSurveyDiscoveryCursorId = cards.last?.surveyId
            homeSurveyDiscoveryLoading = false
        } catch {
            guard generation == homeSurveyDiscoveryGeneration else { return }
            print("loadHomeSurveyDiscovery failed:", error)
            homeSurveyDiscoveryLoading = false
            homeSurveyDiscoveryError = T("Không thể tải khảo sát công khai. Vui lòng thử lại.", "Could not load public surveys. Please try again.")
        }
    }

    /// "Show More" — appends the next page without disturbing rows already
    /// loaded/rendered (preserves Home's own scroll position, since nothing
    /// above this list re-renders).
    func loadMoreHomeSurveyDiscovery() async {
        guard !homeSurveyDiscoveryLoadingMore, homeSurveyDiscoveryHasMore else { return }
        let generation = homeSurveyDiscoveryGeneration
        homeSurveyDiscoveryLoadingMore = true
        do {
            let (cards, hasMore) = try await fetchSurveyDiscoveryPage(
                cursorCreatedAt: homeSurveyDiscoveryCursorCreatedAt, cursorId: homeSurveyDiscoveryCursorId,
                limit: Self.surveyDiscoveryPageSize
            )
            guard generation == homeSurveyDiscoveryGeneration else { return }
            homeSurveyDiscovery.append(contentsOf: cards)
            homeSurveyDiscoveryHasMore = hasMore
            if let last = cards.last {
                homeSurveyDiscoveryCursorCreatedAt = last.createdAt
                homeSurveyDiscoveryCursorId = last.surveyId
            }
            homeSurveyDiscoveryLoadingMore = false
        } catch {
            guard generation == homeSurveyDiscoveryGeneration else { return }
            print("loadMoreHomeSurveyDiscovery failed:", error)
            homeSurveyDiscoveryLoadingMore = false
            homeSurveyDiscoveryError = T("Không thể tải thêm khảo sát. Vui lòng thử lại.", "Could not load more surveys. Please try again.")
        }
    }
}

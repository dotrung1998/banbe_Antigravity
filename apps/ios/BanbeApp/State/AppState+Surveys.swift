import Foundation
import Supabase

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
        } catch {
            print("loadMySurveys failed:", error)
            mySurveys = []
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
            await loadHomeStories()
        } catch {
            let code = (error as? PostgrestError)?.message ?? ""
            surveyShareToStoryBusy = false
            surveyShareToStoryError = code == "SURVEY_NOT_ACTIVE"
                ? T("Chỉ khảo sát đang mở mới có thể chia sẻ lên story.", "Only an active survey can be shared to a story.")
                : T("Không thể đăng lên story. Vui lòng thử lại.", "Could not post to story. Please try again.")
        }
    }
}

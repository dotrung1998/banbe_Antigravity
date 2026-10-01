import SwiftUI

private enum SurveysTab: String, CaseIterable {
    case active, closed, drafts
}

/// Hosting -> Surveys & Event Ideas (Slice B host side). "Suggested Event
/// Drafts" (candidate generation) is intentionally an honest empty state
/// here: that pipeline is not implemented in this pass — this tab is not
/// hidden, since the IA position itself is real, but it never claims
/// candidates exist that don't. Mirrors web's SurveysHosting.jsx.
struct SurveysHostingView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: SurveysTab = .active
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { app.goBack() } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(app.T("Khảo Sát & Ý Tưởng Sự Kiện", "Surveys & Event Ideas")).font(BanbeTheme.display(16))
                    Spacer()
                    Color.clear.frame(width: 18)
                }

                HStack(spacing: 8) {
                    tabButton(.active, app.T("Đang mở", "Active Surveys"))
                    tabButton(.closed, app.T("Đã đóng", "Closed Surveys"))
                    tabButton(.drafts, app.T("Gợi ý sự kiện", "Suggested Event Drafts"))
                }

                if tab == .active {
                    if showCreate {
                        CreateSurveyFormView(onCreated: { showCreate = false })
                    } else {
                        Button { showCreate = true } label: {
                            Text(app.T("+ Tạo khảo sát mới", "+ Create a new survey"))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(app.palette.rule))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if tab == .drafts {
                    Text(app.T(
                        "Chưa có gợi ý sự kiện nào — tính năng tạo gợi ý tự động từ kết quả khảo sát chưa được xây dựng.",
                        "No suggested event drafts yet — automatic candidate generation from survey results has not been built yet."
                    ))
                    .font(.system(size: 13)).opacity(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
                } else if app.mySurveysLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if filtered.isEmpty {
                    Text(tab == .active ? app.T("Chưa có khảo sát nào đang mở.", "No active surveys yet.") : app.T("Chưa có khảo sát đã đóng.", "No closed surveys yet."))
                        .font(.system(size: 13)).opacity(0.6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(filtered) { survey in
                            surveyCard(survey)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        .task { await app.loadMySurveys() }
        .sheet(item: $app.surveyShareToStoryTarget) { survey in
            ShareSurveyToStoryConfirmView(survey: survey)
        }
    }

    private var filtered: [SurveySummary] {
        app.mySurveys.filter { sv in
            switch tab {
            case .active: return sv.status == "draft" || sv.status == "active"
            case .closed: return sv.status == "closed" || sv.status == "archived"
            case .drafts: return false
            }
        }
    }

    private func tabButton(_ key: SurveysTab, _ label: String) -> some View {
        Button { tab = key } label: {
            Text(label)
                .font(.system(size: 12.5))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(tab == key ? app.palette.ink : .clear, in: Capsule())
                .foregroundStyle(tab == key ? app.palette.paper : app.palette.ink)
                .overlay(Capsule().stroke(tab == key ? .clear : app.palette.rule))
        }
        .buttonStyle(.plain)
    }

    private func surveyCard(_ survey: SurveySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(survey.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(survey.status.uppercased()).font(.system(size: 10.5)).opacity(0.6)
            }
            if let closesAt = survey.closesAt {
                Text("\(app.T("Hạn", "Deadline")): \(closesAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12)).opacity(0.6)
            }
            if survey.status != "draft" {
                let link = AppConfig.publicWebOrigin + "/surveys/" + survey.publicId
                Text(link)
                    .font(.system(size: 11))
                    .opacity(0.6)
                    .onTapGesture { UIPasteboard.general.string = link }
            }
            HStack(spacing: 14) {
                Button(app.T("Xem trước", "Preview")) {
                    Task { await app.openSurveyPublic(publicID: survey.publicId, back: .surveysHosting) }
                }
                if survey.status == "draft" {
                    Button(app.T("Xuất bản", "Publish")) { Task { await app.publishSurvey(survey.id) } }
                    Button(app.T("Xoá", "Delete")) { Task { await app.deleteSurvey(survey.id) } }
                        .foregroundStyle(BanbeTheme.alert)
                }
                if survey.status == "active" {
                    if let url = URL(string: AppConfig.publicWebOrigin + "/surveys/" + survey.publicId) {
                        ShareLink(item: url, subject: Text(survey.title)) {
                            Text(app.T("Chia sẻ liên kết", "Share Link"))
                        }
                    }
                    Button(app.T("Chia sẻ lên story", "Share To Story")) {
                        app.openShareToStoryConfirm(survey)
                    }
                    Button(app.T("Đóng sớm", "Close early")) { Task { await app.closeSurveyEarly(survey.id) } }
                }
                if survey.status == "closed" {
                    Button(app.T("Lưu trữ", "Archive")) { Task { await app.archiveSurvey(survey.id) } }
                }
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .underline()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
    }
}

/// Task 4 — "Show a preview and require explicit Publish; no automatic
/// posting." Mirrors exactly what SurveyShareCard renders in the real
/// story (host/title/purpose/deadline/Answer Survey), so there's no
/// surprise between preview and what actually gets posted.
private struct ShareSurveyToStoryConfirmView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let survey: SurveySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(app.T("Xem trước story", "Story preview")).font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Người tổ chức của bạn", "Your organizer")).font(.system(size: 10.5)).opacity(0.6)
                Text(survey.title).font(.system(size: 15, weight: .semibold))
                if let closesAt = survey.closesAt {
                    Text("\(app.T("Hạn", "Deadline")): \(closesAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).opacity(0.6)
                }
                Text(app.T("Trả lời khảo sát", "Answer Survey"))
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(app.palette.paper)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))

            if !app.surveyShareToStoryError.isEmpty {
                Text(app.surveyShareToStoryError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }
            HStack(spacing: 8) {
                Button(app.T("Huỷ", "Cancel")) { app.closeShareToStoryConfirm(); dismiss() }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(app.palette.rule))
                Button(app.surveyShareToStoryBusy ? app.T("Đang đăng…", "Posting…") : app.T("Xuất bản", "Publish")) {
                    Task {
                        await app.confirmShareSurveyToStory()
                        if app.surveyShareToStoryTarget == nil { dismiss() }
                    }
                }
                .disabled(app.surveyShareToStoryBusy)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(app.palette.paper)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(20)
        .presentationDetents([.medium])
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
    }
}

private struct CreateSurveyFormView: View {
    @EnvironmentObject var app: AppState
    let onCreated: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var closesInDays = "7"
    @State private var dateOptions = ""
    @State private var locationOptions = ""
    @State private var budgetOptions = "Dưới 300k, 300-600k, Trên 600k"
    @State private var activityOptions = ""
    @State private var groupSizeMax = "20"

    private func parseOptions(_ text: String) -> [SurveyOption] {
        text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { SurveyOption(id: "o\($0.offset + 1)", label: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(app.T("Tiêu đề", "Title"), $title)
            field(app.T("Mô tả", "Description"), $description)
            field(app.T("Đóng sau (ngày)", "Closes in (days)"), $closesInDays, keyboard: .numberPad)
            field(app.T("Lựa chọn ngày/giờ (cách nhau bởi dấu phẩy)", "Date/time options (comma-separated)"), $dateOptions)
            field(app.T("Lựa chọn địa điểm (cách nhau bởi dấu phẩy)", "Location options (comma-separated)"), $locationOptions)
            field(app.T("Mức ngân sách (cách nhau bởi dấu phẩy)", "Budget ranges (comma-separated)"), $budgetOptions)
            field(app.T("Hoạt động mong muốn (không bắt buộc)", "Desired activities (optional)"), $activityOptions)
            field(app.T("Số người tối đa mỗi nhóm", "Max group size"), $groupSizeMax, keyboard: .numberPad)

            if !app.mySurveyCreateError.isEmpty {
                Text(app.mySurveyCreateError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }

            Button {
                var config = SurveyConfig()
                config.dateOptions = parseOptions(dateOptions)
                config.locationOptions = parseOptions(locationOptions)
                config.budgetOptions = parseOptions(budgetOptions)
                config.activityOptions = parseOptions(activityOptions)
                config.groupSizeMin = 1
                config.groupSizeMax = Int(groupSizeMax) ?? 20
                config.required = ["date_options": true, "location_options": true]
                Task {
                    let ok = await app.createSurvey(title: title, description: description, closesInDays: Int(closesInDays) ?? 7, config: config)
                    if ok { onCreated() }
                }
            } label: {
                Text(app.T("Tạo khảo sát (bản nháp)", "Create survey (draft)"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(app.palette.paper)
                    .opacity(app.mySurveyCreateBusy || title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(app.mySurveyCreateBusy || title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
    }

    private func field(_ label: String, _ text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).opacity(0.7)
            TextField("", text: text)
                .keyboardType(keyboard)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
        }
    }
}

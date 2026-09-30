import SwiftUI

private func chip(_ label: String, active: Bool, palette: Palette) -> some View {
    Text(label)
        .font(.system(size: 13))
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(active ? palette.ink : .clear, in: Capsule())
        .foregroundStyle(active ? palette.paper : palette.ink)
        .overlay(Capsule().stroke(active ? .clear : palette.rule))
}

/// Interest surveys (Slice B) — ONE screen for both the universal-link deep
/// link (/surveys/<publicId>, reachable signed out) and in-app navigation
/// (openSurveyPublic), sharing the exact same backend
/// (get_survey_public/submit_survey_response, migration 114). A survey is
/// NOT a live event/booking/ticket — this screen says so explicitly and
/// never touches the booking/claim path at all. Mirrors web's
/// SurveyPublic.jsx section-for-section.
struct SurveyPublicView: View {
    @EnvironmentObject var app: AppState

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.surveyPublic?.hostName ?? "").font(.system(size: 12)).opacity(0.6)
                    Spacer()
                    Button { app.goBack() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityIdentifier("survey-close")
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                if app.surveyPublicLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 60)
                } else if !app.surveyPublicError.isEmpty || app.surveyPublic == nil {
                    VStack(spacing: 12) {
                        Text(app.surveyPublicError.isEmpty ? app.T("Không tìm thấy khảo sát này.", "This survey couldn't be found.") : app.surveyPublicError)
                            .font(.system(size: 14))
                        Button(app.T("Quay lại", "Go back")) { app.goBack() }
                            .font(.system(size: 13)).underline()
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    content
                }
            }
        }
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        let survey = app.surveyPublic!
        let config = survey.config ?? SurveyConfig()
        VStack(alignment: .leading, spacing: 14) {
            Text(survey.title ?? "").font(BanbeTheme.display(24))
            if let desc = survey.description, !desc.isEmpty {
                Text(desc).font(.system(size: 14)).lineSpacing(3)
            }
            if let closesAt = survey.closesAt {
                Text("\(app.T("Hạn trả lời", "Deadline")): \(Self.deadlineFormatter.string(from: closesAt)) (\(survey.timezone ?? "Asia/Ho_Chi_Minh"))")
                    .font(.system(size: 12)).opacity(0.7)
            }
            Text(app.T("Đây không phải là giữ chỗ.", "This does not reserve a place."))
                .font(.system(size: 12, weight: .semibold))

            if survey.status == "draft" {
                Text(app.T("Đây là bản xem trước — khảo sát chưa được xuất bản.", "This is a preview — the survey hasn't been published yet."))
                    .font(.system(size: 13.5)).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else if survey.status == "closed" {
                Text(app.T("Khảo sát này đã đóng. Cảm ơn bạn đã quan tâm.", "This survey is closed. Thanks for your interest."))
                    .font(.system(size: 13.5)).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else if survey.status == "not_open_yet" {
                Text(app.T("Khảo sát này chưa mở.", "This survey hasn't opened yet."))
                    .font(.system(size: 13.5)).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            } else if app.surveyResponseSuccess {
                Text(app.T(
                    "Đã ghi nhận câu trả lời của bạn. Bạn có thể quay lại chỉnh sửa trước khi khảo sát đóng.",
                    "Your response is recorded. You can come back and edit it before the survey closes."
                ))
                .font(.system(size: 13.5)).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("survey-success")
            } else {
                form(config: config)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 60)
    }

    @ViewBuilder
    private func form(config: SurveyConfig) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Mức độ quan tâm", "Interest level")).font(.system(size: 12)).opacity(0.7)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { n in
                        Button { app.surveyDraft.interestLevel = n } label: {
                            chip("\(n)", active: app.surveyDraft.interestLevel == n, palette: app.palette)
                        }.buttonStyle(.plain)
                    }
                }
            }

            if !config.dateOptions.isEmpty {
                optionSection(title: app.T("Ngày/giờ phù hợp", "Preferred date/time"), options: config.dateOptions, selection: $app.surveyDraft.dateOptions)
            }
            if !config.locationOptions.isEmpty {
                optionSection(title: app.T("Địa điểm phù hợp", "Preferred location"), options: config.locationOptions, selection: $app.surveyDraft.locationOptions)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Số người (tính cả bạn)", "Group size (including you)")).font(.system(size: 12)).opacity(0.7)
                TextField("", value: $app.surveyDraft.groupSize, format: .number)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .frame(width: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
            }

            if !config.budgetOptions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("Ngân sách", "Budget")).font(.system(size: 12)).opacity(0.7)
                    FlowRow(spacing: 8) {
                        ForEach(config.budgetOptions) { opt in
                            Button { app.surveyDraft.budgetOption = opt.id } label: {
                                chip(opt.label, active: app.surveyDraft.budgetOption == opt.id, palette: app.palette)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if !config.activityOptions.isEmpty {
                optionSection(title: app.T("Hoạt động mong muốn", "Desired activities"), options: config.activityOptions, selection: $app.surveyDraft.activities)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Góp ý thêm (không bắt buộc)", "Additional suggestions (optional)")).font(.system(size: 12)).opacity(0.7)
                TextEditor(text: $app.surveyDraft.freeText)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
            }

            Button {
                app.surveyDraft.contactConsent.toggle()
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: app.surveyDraft.contactConsent ? "checkmark.square.fill" : "square")
                    Text(app.T(
                        "Đồng ý để người tổ chức liên hệ về sự kiện này (không phải quảng cáo).",
                        "OK for the host to contact me about this specific event (not marketing)."
                    )).font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)

            if !app.surveyResponseError.isEmpty {
                Text(app.surveyResponseError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }

            Button {
                if !app.isSignedIn {
                    app.requireAuth(returnTo: .surveyPublic, backTo: .surveyPublic)
                } else {
                    Task { await app.submitSurveyResponse() }
                }
            } label: {
                Text(!app.isSignedIn
                     ? app.T("Đăng nhập để gửi câu trả lời", "Sign in to submit")
                     : (app.mySurveyResponse != nil ? app.T("Cập nhật câu trả lời", "Update response") : app.T("Gửi câu trả lời", "Submit response")))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(app.palette.paper)
                    .opacity(app.surveyResponseSubmitting ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(app.surveyResponseSubmitting)
            .accessibilityIdentifier("survey-submit")
        }
    }

    private func optionSection(title: String, options: [SurveyOption], selection: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).opacity(0.7)
            FlowRow(spacing: 8) {
                ForEach(options) { opt in
                    Button {
                        if selection.wrappedValue.contains(opt.id) {
                            selection.wrappedValue.removeAll { $0 == opt.id }
                        } else {
                            selection.wrappedValue.append(opt.id)
                        }
                    } label: {
                        chip(opt.label, active: selection.wrappedValue.contains(opt.id), palette: app.palette)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

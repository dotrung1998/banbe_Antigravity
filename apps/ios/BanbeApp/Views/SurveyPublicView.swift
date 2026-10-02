import SwiftUI

/// Keyboard pass — every editable field in this screen (its own form AND
/// the nested `RespondVerifyInlineView`) shares ONE `@FocusState`, so a
/// single "Done" toolbar / background tap / Submit / X can always resign
/// whichever field actually has focus, instead of each sub-view needing its
/// own private focus state and its own copy of the dismiss plumbing.
private enum SurveyFocusField: Hashable {
    case groupSize, freeText, respondEmail, respondCode
}

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
    /// Survey-sharing pass — this SAME view also renders inside the
    /// `.fullScreenCover` a story's "Answer Survey" CTA presents
    /// (RootView.swift). `asModal` only changes CLOSE behavior
    /// (closeSurveyStoryModal instead of goBack, and hides the "navigate to
    /// full sign-in" option, which would abandon the paused story
    /// underneath) — everything else is identical, per this ticket's own
    /// "reuse the existing screen; change its presentation" rule.
    var asModal: Bool = false
    @State private var closeConfirmOpen = false
    @FocusState private var focusedField: SurveyFocusField?
    // Fast follow-up fix (reported: "Additional suggestions" still hidden
    // under the keyboard) — the REAL root cause: `content`'s own bottom
    // padding is a fixed 60pt, far less than the keyboard's real height
    // (~300pt+ with the suggestions bar) — the earlier delayed/`.bottom`-
    // anchored `scrollTo` fix was correct but had nowhere left to scroll
    // TO, since there was never enough scrollable room below a
    // near-the-end field like this one to begin with. Tracking the real
    // keyboard height and padding the content by that much (added ON TOP
    // of, not instead of, the existing fixed padding below) guarantees
    // every field — not just this one — can actually be scrolled clear of
    // the keyboard.
    @State private var keyboardHeight: CGFloat = 0

    private static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    private var isDraftDirty: Bool {
        let d = app.surveyDraft
        return d.interestLevel != nil || !d.dateOptions.isEmpty || d.groupSize != nil
            || !d.locationOptions.isEmpty || d.budgetOption != nil || !d.activities.isEmpty
            || !d.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || d.contactConsent
    }
    private func requestClose() {
        // X ends editing first (per this ticket's "X ends editing and
        // follows existing unsaved-draft confirmation rules") — resigning
        // focus doesn't touch `isDraftDirty` (it reads submitted draft
        // fields, not focus), so the confirm-alert decision below is
        // unaffected either way.
        focusedField = nil
        if isDraftDirty && !app.surveyResponseSuccess { closeConfirmOpen = true; return }
        if asModal { app.closeSurveyStoryModal() } else { app.goBack() }
    }
    private func confirmClose(discard: Bool) {
        closeConfirmOpen = false
        if asModal { app.closeSurveyStoryModal(discard: discard) } else { app.goBack() }
    }
    /// Deferred one run-loop tick, same reasoning `FocusableTextField`
    /// (Components.swift) already established elsewhere in this app:
    /// calling into layout-dependent machinery in the SAME tick a state
    /// change that affects that layout (`keyboardHeight`, here) was just
    /// written is unreliable — SwiftUI hasn't re-rendered yet. Yielding to
    /// the next turn first lets that update commit before this reacts to it.
    private func scrollToField(_ field: SurveyFocusField, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(field, anchor: .bottom) }
        }
    }

    var body: some View {
        // `ScrollViewReader` — "bring the focused field into view" below,
        // keyed on `focusedField` itself (the one signal already common to
        // every field on this screen, including the ones nested inside
        // `RespondVerifyInlineView`) rather than a per-field scroll offset
        // this screen never previously tracked.
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.surveyPublic?.hostName ?? "").font(.system(size: 12)).opacity(0.6)
                    Spacer()
                    Button { requestClose() } label: {
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
                        Button(app.T("Quay lại", "Go back")) { requestClose() }
                            .font(.system(size: 13)).underline()
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // `.contentShape` makes the WHOLE frame above (including the
            // empty padding margins between sections, not just the pixels
            // text/controls actually paint) hit-testable for the tap gesture
            // below — otherwise a plain VStack only responds where a child
            // already draws something.
            .contentShape(Rectangle())
            // Keyboard pass — tapping neutral form background dismisses the
            // keyboard without intercepting any real control: `.onTapGesture`
            // on this container only ever fires for a touch that doesn't
            // land on one of its interactive children (a chip/option Button,
            // a field, Submit, X) in the first place — SwiftUI resolves the
            // more specific child gesture first — so it can never swallow a
            // tap meant for one of them.
            .onTapGesture { focusedField = nil }
            // Second fast follow-up (reported: field no longer covered, but
            // only visible after a MANUAL scroll — the auto-scroll itself
            // wasn't actually landing). Real cause: this additive bottom
            // spacer only grew the ScrollView's CONTENT, never its
            // effective VIEWPORT — `scrollTo(anchor: .bottom)` anchors
            // against the scroll view's own bounds, which (thanks to this
            // whole screen's `.ignoresSafeArea(edges: .bottom)`) still
            // reported the FULL, un-shrunk screen height, i.e. still
            // including the area the keyboard physically covers. A
            // `.safeAreaInset`, unlike a plain content row, genuinely
            // shrinks what `anchor: .bottom` considers "the bottom of the
            // visible area" by exactly the keyboard's height, so scrolling
            // a field to `.bottom` now actually lands it just above the
            // keyboard instead of still underneath it.
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: keyboardHeight) }
        }
        .onChange(of: focusedField) { _, field in
            // Covers moving focus from one field to another while the
            // keyboard is ALREADY up — `keyboardWillShowNotification` only
            // fires once, when the keyboard first rises, so switching
            // fields afterward needs its own trigger.
            guard let field else { return }
            scrollToField(field, proxy: proxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            // Third fast follow-up (reported: still not auto-scrolling at
            // all) — real bug: this used to set `keyboardHeight` AND call
            // `proxy.scrollTo` in the very same closure/tick. SwiftUI only
            // re-renders (and only THEN does the `.safeAreaInset` below
            // actually grow) on the NEXT run-loop pass — `scrollTo` was
            // therefore always computing against the OLD, zero-height
            // layout, every single time, which is why nothing visibly
            // moved. Setting the height here and leaving the actual scroll
            // to `.onChange(of: keyboardHeight)` below (which only fires
            // AFTER that re-render has happened) is what fixes it.
            keyboardHeight = frame.height
        }
        .onChange(of: keyboardHeight) { _, height in
            guard height > 0, let field = focusedField else { return }
            scrollToField(field, proxy: proxy)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        }
        // Lets a drag-to-scroll gesture dismiss the keyboard too, per this
        // ticket's "allow keyboard dismissal by scrolling interactively".
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // Number-pad keyboards (Group size) have no Return key at all,
            // and most of this form's other fields are optional chips/
            // checkboxes with no natural "next field" — one shared Done
            // action, above every keyboard this screen ever shows, resigns
            // focus without submitting anything.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(app.T("Xong", "Done")) { focusedField = nil }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        // REAL root cause of three failed keyboard-scroll attempts in a
        // row: this used to unconditionally ignore the bottom safe area
        // (so the paper background extends behind the home indicator when
        // nothing is focused). The system models keyboard intrusion AS an
        // additional bottom safe-area inset on the hosting controller — a
        // view that's told to ignore that edge also stops reacting to that
        // inset changing, which silently cancelled BOTH SwiftUI's own
        // built-in "scrollable content avoids the keyboard automatically"
        // behavior AND every manual `.safeAreaInset`/`scrollTo` patch tried
        // above it, no matter how correctly timed. Only ignoring it while
        // NO field is focused keeps the home-indicator cosmetic exactly as
        // before and lets the real keyboard-avoidance mechanism run while
        // editing.
        .ignoresSafeArea(edges: focusedField == nil ? .bottom : [])
        .alert(app.T("Bạn có câu trả lời chưa gửi", "You have unsent answers"), isPresented: $closeConfirmOpen) {
            Button(app.T("Giữ nháp", "Keep draft")) { confirmClose(discard: false) }
            Button(app.T("Bỏ đi", "Discard"), role: .destructive) { confirmClose(discard: true) }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.T("Giữ lại để tiếp tục sau, hay bỏ đi?", "Keep them for later, or discard?"))
        }
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
                // Section 2's required success state — distinct, never auto-
                // closed/auto-advanced; the respondent decides when to leave.
                VStack(spacing: 16) {
                    Text(app.T("Đã Gửi Câu Trả Lời. Cảm Ơn Bạn!", "Response Submitted. Thank You!"))
                        .font(BanbeTheme.display(20))
                    Text(app.T("Bạn có thể quay lại chỉnh sửa trước khi khảo sát đóng.", "You can come back and edit it before the survey closes."))
                        .font(.system(size: 13)).opacity(0.75).multilineTextAlignment(.center)
                    Button(app.T("Đóng", "Close")) { requestClose() }
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(app.palette.paper)
                        .accessibilityIdentifier("survey-success-close")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .accessibilityIdentifier("survey-success")
            } else if app.mySurveyResponse != nil && !app.surveyEditMode {
                alreadyResponded(config: config)
            } else {
                form(config: config)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 60)
    }

    /// "You Have Already Responded" — a read-only summary, never a fresh-
    /// looking blank form suggesting a second, independent submission.
    @ViewBuilder
    private func alreadyResponded(config: SurveyConfig) -> some View {
        let r = app.mySurveyResponse!
        VStack(alignment: .leading, spacing: 14) {
            Text(app.T("Bạn Đã Trả Lời Khảo Sát Này", "You Have Already Responded"))
                .font(.system(size: 13.5, weight: .semibold)).padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("survey-already-responded")
            VStack(alignment: .leading, spacing: 6) {
                if let level = r.interestLevel {
                    Text("\(app.T("Mức độ quan tâm", "Interest level")): \(level)").font(.system(size: 12.5))
                }
                if !r.dateOptions.isEmpty {
                    Text("\(app.T("Ngày/giờ", "Date/time")): \(r.dateOptions.compactMap { id in config.dateOptions.first { $0.id == id }?.label ?? id }.joined(separator: ", "))").font(.system(size: 12.5))
                }
                if !r.locationOptions.isEmpty {
                    Text("\(app.T("Địa điểm", "Location")): \(r.locationOptions.compactMap { id in config.locationOptions.first { $0.id == id }?.label ?? id }.joined(separator: ", "))").font(.system(size: 12.5))
                }
                if let size = r.groupSize {
                    Text("\(app.T("Số người", "Group size")): \(size)").font(.system(size: 12.5))
                }
                if let budget = r.budgetOption {
                    Text("\(app.T("Ngân sách", "Budget")): \(config.budgetOptions.first { $0.id == budget }?.label ?? budget)").font(.system(size: 12.5))
                }
                if !r.freeText.isEmpty {
                    Text("\(app.T("Góp ý", "Notes")): \(r.freeText)").font(.system(size: 12.5))
                }
            }
            .opacity(0.85)
            if app.surveyPublic?.status == "active" {
                Button(app.T("Chỉnh sửa câu trả lời", "Edit Response")) { app.toggleSurveyEditMode(true) }
                    .font(.system(size: 12.5)).underline()
                    .accessibilityIdentifier("survey-edit-response")
            }
        }
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
                    .focused($focusedField, equals: .groupSize)
                    .padding(10)
                    .frame(width: 100)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
            }
            .id(SurveyFocusField.groupSize)

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
                    .focused($focusedField, equals: .freeText)
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
            }
            .id(SurveyFocusField.freeText)

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

            // Section 3 — "offer existing sign-in OR email-code
            // verification" for a signed-out respondent. The full sign-in
            // screen is only offered OUTSIDE the story-popup modal —
            // navigating away from inside it would also abandon the paused
            // story behind it.
            if !app.isSignedIn {
                VStack(alignment: .leading, spacing: 10) {
                    RespondVerifyInlineView(focusedField: $focusedField)
                    if !asModal {
                        Button(app.T("Hoặc đăng nhập bằng tài khoản banbe có sẵn", "Or sign in with an existing banbe account")) {
                            app.requireAuth(returnTo: .surveyPublic, backTo: .surveyPublic)
                        }
                        .font(.system(size: 12.5)).underline().opacity(0.75)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } else {
                Button {
                    // Submit ends editing first — a failed server-side
                    // validation re-renders this same `form(config:)` with
                    // `app.surveyDraft` untouched (the error path never
                    // clears any answer), so every field's current value is
                    // retained exactly as this ticket requires either way.
                    focusedField = nil
                    Task { await app.submitSurveyResponse() }
                } label: {
                    Text(app.mySurveyResponse != nil ? app.T("Cập nhật câu trả lời", "Update response") : app.T("Gửi câu trả lời", "Submit response"))
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

/// Section 3 — lightweight, no-password/no-profile respondent email
/// verification for a signed-out visitor. Reuses the existing OTP-by-email
/// mechanism (AuthAPIService, mode: .respond) — never a separate auth
/// system — and discloses whether this creates a new banbe identity BEFORE
/// the respondent types the code, per this ticket's own "disclose
/// accurately before confirmation" rule. The explicit consent toggle here
/// IS the additive consent path for someone who never saw the ordinary
/// sign-in screen's own checkbox.
private struct RespondVerifyInlineView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    var focusedField: FocusState<SurveyFocusField?>.Binding

    var body: some View {
        if app.surveyRespondStep == "codeSent" {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.surveyRespondIsNewAccount
                     ? app.T("Email này chưa có tài khoản banbe — chúng tôi sẽ tạo một tài khoản tối giản gắn với email này để lưu câu trả lời của bạn.", "This email doesn't have a banbe account yet — we'll create a minimal one tied to this email so your response can be saved.")
                     : app.T("Email này đã có tài khoản banbe — nhập mã để xác nhận đó là bạn.", "This email already has a banbe account — enter the code to confirm it's you."))
                    .font(.system(size: 12.5))
                TextField(app.T("Mã 8 chữ số", "8-digit code"), text: $app.surveyRespondCode)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: .respondCode)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
                if !app.surveyRespondError.isEmpty {
                    Text(app.surveyRespondError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                }
                Button(app.surveyRespondSending ? app.T("Đang xác nhận…", "Verifying…") : app.T("Xác nhận mã", "Confirm code")) {
                    focusedField.wrappedValue = nil
                    Task { await app.verifySurveyRespondCode() }
                }
                .disabled(app.surveyRespondSending)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(app.palette.paper)
                .opacity(app.surveyRespondSending ? 0.6 : 1)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
            .id(SurveyFocusField.respondCode)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.T("Xác nhận email để gửi câu trả lời", "Verify your email to submit")).font(.system(size: 12.5, weight: .semibold))
                TextField(app.T("Email của bạn", "Your email"), text: $email)
                    .keyboardType(.emailAddress).autocapitalization(.none)
                    .focused(focusedField, equals: .respondEmail)
                    .submitLabel(.send)
                    .onSubmit { focusedField.wrappedValue = nil; Task { await app.sendSurveyRespondCode(email: email) } }
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
                Button {
                    app.surveyRespondConsent.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: app.surveyRespondConsent ? "checkmark.square.fill" : "square")
                        Text(app.T(
                            "Tôi đồng ý xác nhận email này để gửi câu trả lời. Nếu email chưa có tài khoản banbe, một tài khoản tối giản sẽ được tạo, theo Chính sách quyền riêng tư của banbe.",
                            "I agree to verify this email to submit my response. If it doesn't have a banbe account, a minimal one will be created, under banbe's Privacy Policy."
                        )).font(.system(size: 11.5))
                    }
                }.buttonStyle(.plain)
                if !app.surveyRespondError.isEmpty {
                    Text(app.surveyRespondError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                }
                Button(app.surveyRespondSending ? app.T("Đang gửi…", "Sending…") : app.T("Gửi mã xác nhận", "Send verification code")) {
                    focusedField.wrappedValue = nil
                    Task { await app.sendSurveyRespondCode(email: email) }
                }
                .disabled(app.surveyRespondSending)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(app.palette.paper)
                .opacity(app.surveyRespondSending ? 0.6 : 1)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
            .id(SurveyFocusField.respondEmail)
        }
    }
}

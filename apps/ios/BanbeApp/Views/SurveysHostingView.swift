import SwiftUI

private enum SurveysTab: String, CaseIterable {
    case active, closed, drafts, archived
}

/// Segmented tabs with a draggable "liquid glass" droplet: translucent
/// material, specular rim, and a squash-and-stretch while the finger is
/// down (wider/flatter, like a drop of water being pushed), springing back
/// into place on release. Works as a plain tap target too.
private struct GlassSegmentedTabs: View {
    struct Item { let key: SurveysTab; let label: String; let badge: Int }
    let items: [Item]
    @Binding var selection: SurveysTab
    @EnvironmentObject var app: AppState
    @GestureState private var fingerX: CGFloat? = nil

    private let inset: CGFloat = 3
    private let height: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let segW = (geo.size.width - inset * 2) / CGFloat(items.count)
            let idx = items.firstIndex { $0.key == selection } ?? 0
            let restX = inset + segW * CGFloat(idx)
            let dragging = fingerX != nil
            let dropX = fingerX.map { min(max($0 - segW / 2, inset), geo.size.width - inset - segW) } ?? restX
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(app.palette.ink.opacity(0.06))
                RoundedRectangle(cornerRadius: 16).stroke(app.palette.rule)

                // The droplet.
                RoundedRectangle(cornerRadius: 13)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(dragging ? 0.22 : 0.12), radius: dragging ? 12 : 5, y: dragging ? 6 : 2)
                    .frame(width: segW, height: height - inset * 2)
                    .scaleEffect(x: dragging ? 1.16 : 1, y: dragging ? 0.9 : 1)
                    .offset(x: dropX, y: inset)
                    .animation(.spring(response: dragging ? 0.18 : 0.42, dampingFraction: dragging ? 0.85 : 0.62), value: dropX)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dragging)

                HStack(spacing: 0) {
                    ForEach(items, id: \.key) { item in
                        let on = item.key == selection
                        HStack(spacing: 5) {
                            Text(item.label).lineLimit(1).minimumScaleFactor(0.8)
                            if item.badge > 0 {
                                Text("\(item.badge)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                                    .background(app.palette.ink, in: Capsule())
                                    .foregroundStyle(app.palette.paper)
                            }
                        }
                        .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(app.palette.ink.opacity(on ? 1 : 0.55))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, inset)
                .frame(height: height)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($fingerX) { value, state, _ in state = value.location.x }
                    .onChanged { value in select(at: value.location.x, segW: segW) }
            )
        }
        .frame(height: height)
    }

    private func select(at x: CGFloat, segW: CGFloat) {
        let i = min(max(Int((x - inset) / segW), 0), items.count - 1)
        let key = items[i].key
        guard key != selection else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        selection = key
    }
}

/// Hosting -> Surveys & Event Ideas. "Suggested Event Drafts" lists the
/// candidates migration 143 generates server-side when a survey closes
/// (deterministic scoring of date x location over the responses); "Use This
/// Idea" pre-fills Create Event and never creates anything by itself.
/// Mirrors web's SurveysHosting.jsx.
struct SurveysHostingView: View {
    @EnvironmentObject var app: AppState
    private var tab: SurveysTab { SurveysTab(rawValue: app.surveysHostingTab) ?? .active }
    private var tabBinding: Binding<SurveysTab> {
        Binding(get: { tab }, set: { app.surveysHostingTab = $0.rawValue })
    }
    @State private var showCreate = false
    @State private var showDismissed = false
    // Multi-select (Closed tab: archive; Suggested tab: dismiss). One mode
    // flag + one id set, reset whenever the tab changes.
    @State private var selectMode = false
    @State private var selected: Set<UUID> = []
    @State private var deleteRequest: DeleteRequest?

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

                // One short word per tab, full-width segmented control: all four
                // always fit one row — no wrapping, no dead space on the right.
                // Tap, or press and slide: a liquid-glass droplet follows the
                // finger and the tab switches live as it passes each segment.
                GlassSegmentedTabs(
                    items: [
                        .init(key: .active, label: app.T("Đang mở", "Active"), badge: 0),
                        .init(key: .closed, label: app.T("Đã đóng", "Closed"), badge: 0),
                        .init(key: .drafts, label: app.T("Gợi ý", "Ideas"), badge: activeCandidateCount),
                        .init(key: .archived, label: app.T("Lưu trữ", "Archived"), badge: 0),
                    ],
                    selection: tabBinding
                )

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
                    candidatesSection
                } else if tab == .archived {
                    archivedSection
                } else if app.mySurveysLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if filtered.isEmpty {
                    Text(tab == .active ? app.T("Chưa có khảo sát nào đang mở.", "No active surveys yet.") : app.T("Chưa có khảo sát đã đóng.", "No closed surveys yet."))
                        .font(.system(size: 13)).opacity(0.6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    if tab == .closed {
                        selectBar(ids: filtered.map(\.id), allLabel: app.T("Lưu trữ tất cả", "Archive all"),
                                  bulkLabel: app.T("Lưu trữ đã chọn", "Archive selected")) { ids in
                            await app.archiveSurveys(ids)
                            return true
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(filtered) { survey in
                            HStack(alignment: .top, spacing: 10) {
                                if selectMode && tab == .closed { checkbox(survey.id) }
                                surveyCard(survey)
                            }
                        }
                    }
                }
            }
            .padding(20)
            // One spring for everything Select changes at once (pills
            // swapping, checkboxes sliding in, cards making room) so it
            // reads as a single smooth transition instead of a pop.
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectMode)
        }
        .onChange(of: tab) { _ in selectMode = false; selected = [] }
        .alert(
            deleteRequest?.isSurvey == true ? app.T("Xoá vĩnh viễn?", "Delete permanently?") : app.T("Xoá ý tưởng?", "Delete ideas?"),
            isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } }),
            presenting: deleteRequest
        ) { req in
            Button(app.T("Xoá", "Delete"), role: .destructive) {
                Task {
                    if req.isSurvey { await app.deleteArchivedSurveys(req.ids) } else { await app.deleteSurveyCandidates(req.ids) }
                    selectMode = false; selected = []
                }
            }
            Button(app.T("Huỷ", "Cancel"), role: .cancel) {}
        } message: { req in
            Text(req.isSurvey
                 ? app.T("Xoá \(req.ids.count) khảo sát cùng toàn bộ câu trả lời và gợi ý của chúng. Không thể hoàn tác.",
                         "This deletes \(req.ids.count) survey\(req.ids.count == 1 ? "" : "s") with all their responses and ideas. It can't be undone.")
                 : app.T("Xoá \(req.ids.count) ý tưởng đã dùng. Không thể hoàn tác.",
                         "This deletes \(req.ids.count) used idea\(req.ids.count == 1 ? "" : "s"). It can't be undone."))
        }
        .onDisappear {
            // Keep the tab only for the Preview round trip (the screen swaps
            // to .surveyPublic, or is momentarily re-created while still
            // .surveysHosting); any other exit starts fresh on Active.
            if app.screen != .surveyPublic && app.screen != .surveysHosting { app.surveysHostingTab = "active" }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(app.T("Xong", "Done")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .background(app.palette.paper)
        .foregroundStyle(app.palette.ink)
        .task { await app.loadMySurveys() }
        .task(id: app.mySurveys) { if !app.mySurveysLoading { await app.loadSurveyCandidates() } }
        .sheet(item: $app.surveyShareToStoryTarget) { survey in
            ShareSurveyToStoryConfirmView(survey: survey)
        }
    }

    // Suggested tab = ideas from CLOSED surveys still open for a decision
    // (suggested/dismissed). A used idea moves to Archived on its own;
    // archiving a survey moves the survey there too.
    private var closedSurveys: [SurveySummary] { app.mySurveys.filter { $0.status == "closed" } }
    private var archivedSurveys: [SurveySummary] { app.mySurveys.filter { $0.status == "archived" } }
    private var decidable: [SurveyCandidate] {
        let ids = Set(closedSurveys.map(\.id))
        return app.mySurveyCandidates.filter { ids.contains($0.surveyId) && $0.status != "used" }
    }
    private var dismissedCount: Int { decidable.filter { $0.status == "dismissed" }.count }
    private var activeCandidateCount: Int { decidable.count - dismissedCount }
    private var suggestedIDs: [UUID] { decidable.filter { $0.status == "suggested" }.map(\.id) }
    private func surveyTitle(_ id: UUID) -> String { app.mySurveys.first { $0.id == id }?.title ?? "" }

    private func checkbox(_ id: UUID) -> some View {
        Button {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } label: {
            Image(systemName: selected.contains(id) ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .animation(.easeInOut(duration: 0.15), value: selected.contains(id))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .transition(.move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.5)))
    }

    /// Shared "Select / <bulk> all" bar. Two bars can share one select mode
    /// (Archived tab), so each only counts and acts on its own section's ids.
    /// `onBulk` returns true when the action is done (select mode then ends);
    /// a confirm-first action returns false and ends select mode itself.
    @ViewBuilder
    private func selectBar(ids: [UUID], allLabel: String, bulkLabel: String, destructive: Bool = false,
                           onBulk: @escaping ([UUID]) async -> Bool) -> some View {
        if !ids.isEmpty {
            let mine = ids.filter { selected.contains($0) }
            HStack(spacing: 8) {
                if !selectMode {
                    pill(app.T("Chọn", "Select")) { selectMode = true }.transition(.opacity.combined(with: .scale(scale: 0.94)))
                    pill(allLabel, destructive ? .danger : .outline) { Task { _ = await onBulk(ids) } }.transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else {
                    pill(mine.count == ids.count ? app.T("Bỏ chọn hết", "Deselect all") : app.T("Chọn tất cả", "Select all")) {
                        if mine.count == ids.count { selected.subtract(ids) } else { selected.formUnion(ids) }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    pill("\(bulkLabel) (\(mine.count))", destructive ? .danger : .filled, disabled: mine.isEmpty) {
                        Task {
                            if await onBulk(mine) { selectMode = false; selected = [] }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    pill(app.T("Huỷ", "Cancel")) { selectMode = false; selected = [] }
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
        }
    }

    /// Permanent deletes always confirm first (alert below); the ids wait here.
    private struct DeleteRequest { let ids: [UUID]; let isSurvey: Bool }

    private func requestDelete(_ ids: [UUID], isSurvey: Bool) -> Bool {
        deleteRequest = DeleteRequest(ids: ids, isSurvey: isSurvey)
        return false
    }

    @ViewBuilder
    private var archivedSection: some View {
        let used = app.mySurveyCandidates.filter { $0.status == "used" }
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Khảo sát đã lưu trữ", "Archived surveys")).font(.system(size: 12.5, weight: .semibold))
                if archivedSurveys.isEmpty {
                    Text(app.T("Chưa có khảo sát nào được lưu trữ.", "No archived surveys yet.")).font(.system(size: 13)).opacity(0.6)
                }
                selectBar(ids: archivedSurveys.map(\.id), allLabel: app.T("Xoá tất cả", "Delete all"),
                          bulkLabel: app.T("Xoá đã chọn", "Delete selected"), destructive: true) { ids in
                    requestDelete(ids, isSurvey: true)
                }
                ForEach(archivedSurveys) { sv in
                    HStack(alignment: .top, spacing: 10) {
                        if selectMode { checkbox(sv.id) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sv.title).font(.system(size: 14, weight: .semibold))
                            HStack(spacing: 8) {
                                pill(app.T("Xem trước", "Preview")) { openPreview(sv) }
                                pill(app.T("Khôi phục", "Restore"), id: "survey.unarchive") { Task { await app.unarchiveSurvey(sv.id) } }
                                pill(app.T("Xoá", "Delete"), .danger, id: "survey.deleteArchived") { _ = requestDelete([sv.id], isSurvey: true) }
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Ý tưởng sự kiện đã dùng", "Used event ideas")).font(.system(size: 12.5, weight: .semibold))
                if used.isEmpty {
                    Text(app.T("Ý tưởng đã dùng sẽ tự động chuyển vào đây.", "Ideas you use move here automatically.")).font(.system(size: 13)).opacity(0.6)
                }
                selectBar(ids: used.map(\.id), allLabel: app.T("Xoá tất cả", "Delete all"),
                          bulkLabel: app.T("Xoá đã chọn", "Delete selected"), destructive: true) { ids in
                    requestDelete(ids, isSurvey: false)
                }
                ForEach(used) { c in
                    let title = [c.dateLabel, c.locationLabel].filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
                    HStack(alignment: .top, spacing: 10) {
                        if selectMode { checkbox(c.id) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title.isEmpty ? surveyTitle(c.surveyId) : title).font(.system(size: 14, weight: .semibold))
                            Text(surveyTitle(c.surveyId)).font(.system(size: 12)).opacity(0.6)
                            HStack(spacing: 8) {
                                pill(app.T("Đưa về gợi ý", "Move back"), id: "survey.candidate.unarchive") { Task { await app.restoreSurveyCandidate(c) } }
                                pill(app.T("Xoá", "Delete"), .danger, id: "survey.candidate.delete") { _ = requestDelete([c.id], isSurvey: false) }
                            }
                            .padding(.top, 6)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var candidatesSection: some View {
        let groups = closedSurveys.compactMap { sv -> (SurveySummary, [SurveyCandidate])? in
            let all = decidable.filter { $0.surveyId == sv.id && (showDismissed || $0.status != "dismissed") }
            let items = all.filter { $0.status != "dismissed" } + all.filter { $0.status == "dismissed" }
            return items.isEmpty ? nil : (sv, items)
        }
        VStack(alignment: .leading, spacing: 16) {
            if dismissedCount > 0 {
                Button(showDismissed ? app.T("Ẩn gợi ý đã bỏ qua", "Hide dismissed") : app.T("Hiện gợi ý đã bỏ qua (\(dismissedCount))", "Show dismissed (\(dismissedCount))")) {
                    showDismissed.toggle()
                }
                .font(.system(size: 12)).underline().opacity(0.75)
                .accessibilityIdentifier("survey.candidates.toggleDismissed")
            }
            selectBar(ids: suggestedIDs, allLabel: app.T("Bỏ qua tất cả", "Dismiss all"),
                      bulkLabel: app.T("Bỏ qua đã chọn", "Dismiss selected")) { ids in
                await app.setSurveyCandidatesStatus(ids, "dismissed")
                return true
            }
            if !app.mySurveyCandidatesError.isEmpty {
                Text(app.mySurveyCandidatesError).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
            }
            if (app.mySurveysLoading || app.mySurveyCandidatesLoading) && groups.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if groups.isEmpty {
                Text(closedSurveys.isEmpty
                     ? app.T("Chưa có gợi ý — gợi ý sự kiện được tạo tự động khi một khảo sát đóng và có người trả lời.",
                             "No suggestions yet — event drafts are generated automatically when a survey closes with responses.")
                     : app.T("Không còn gợi ý nào cần xử lý. Có thể làm mới bên dưới để tạo lại.",
                             "No suggestions left to review. You can refresh below to generate them again."))
                    .font(.system(size: 13)).opacity(0.7)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            }
            ForEach(groups, id: \.0.id) { sv, items in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(sv.title).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(app.mySurveyCandidatesBusySurveyID == sv.id ? app.T("Đang làm mới…", "Refreshing…") : app.T("Làm mới", "Refresh")) {
                            Task { await app.refreshSurveyCandidates(sv.id) }
                        }
                        .font(.system(size: 11.5)).underline().opacity(0.7)
                        .disabled(app.mySurveyCandidatesBusySurveyID != nil)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, c in
                        HStack(alignment: .top, spacing: 10) {
                            if selectMode && c.status == "suggested" { checkbox(c.id) }
                            candidateCard(c, survey: sv, index: index)
                        }
                    }
                }
            }
            if !app.mySurveysLoading {
                ForEach(closedSurveys.filter { sv in !groups.contains { $0.0.id == sv.id } }) { sv in
                    HStack {
                        Text(sv.title).font(.system(size: 12.5))
                        Spacer()
                        Button(app.mySurveyCandidatesBusySurveyID == sv.id ? app.T("Đang làm mới…", "Refreshing…") : app.T("Tạo gợi ý", "Generate suggestions")) {
                            Task { await app.refreshSurveyCandidates(sv.id) }
                        }
                        .font(.system(size: 12.5)).underline()
                        .disabled(app.mySurveyCandidatesBusySurveyID != nil)
                    }
                    .opacity(0.7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func candidateCard(_ c: SurveyCandidate, survey: SurveySummary, index: Int) -> some View {
        let title = [c.dateLabel, c.locationLabel].filter { !$0.isEmpty }.joined(separator: " ▪︎ ")
        var fit = app.T("\(c.supporterCount)/\(c.responseTotal) người phù hợp", "\(c.supporterCount) of \(c.responseTotal) respondents fit")
        if let size = c.suggestedGroupSize { fit += " · " + app.T("nhóm ~", "group ~") + "\(size)" }
        if c.consentCount > 0 { fit += " · " + app.T("\(c.consentCount) đồng ý liên hệ", "\(c.consentCount) OK'd contact") }
        let extra = ([c.budgetLabel] + [c.activityLabels.joined(separator: ", ")]).filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.isEmpty ? survey.title : title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(c.status == "used" ? app.T("Đã dùng", "Used").uppercased() : c.status == "dismissed" ? app.T("Đã bỏ qua", "Dismissed").uppercased() : "#\(index + 1)")
                    .font(.system(size: 10.5)).opacity(0.6)
            }
            Text(fit).font(.system(size: 12)).opacity(0.7)
            if !extra.isEmpty { Text(extra).font(.system(size: 12)).opacity(0.6) }
            HStack(spacing: 8) {
                pill(app.T("Dùng ý tưởng này", "Use This Idea"), .filled, id: "survey.candidate.use") { app.applySurveyCandidate(c, survey: survey) }
                if c.status == "dismissed" {
                    pill(app.T("Khôi phục", "Restore"), id: "survey.candidate.restore") { Task { await app.restoreSurveyCandidate(c) } }
                } else {
                    pill(app.T("Bỏ qua", "Dismiss")) { Task { await app.dismissSurveyCandidate(c) } }
                }
            }
            .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
    }

    private var filtered: [SurveySummary] {
        app.mySurveys.filter { sv in
            switch tab {
            case .active: return sv.status == "draft" || sv.status == "active"
            case .closed: return sv.status == "closed"
            case .drafts, .archived: return false
            }
        }
    }

    private func openPreview(_ survey: SurveySummary) {
        Task { await app.openSurveyPublic(publicID: survey.publicId, back: .surveysHosting) }
    }

    // Equal-width action buttons — rows of these fill the card edge to edge
    // instead of ragged underlined links.
    private enum PillKind { case outline, filled, danger }

    private func pillLabel(_ text: String, _ kind: PillKind) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 6)
            .background(kind == .filled ? app.palette.ink : .clear, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(kind == .filled ? app.palette.paper : kind == .danger ? BanbeTheme.alert : app.palette.ink)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(kind == .danger ? BanbeTheme.alert : kind == .filled ? app.palette.ink : app.palette.rule))
            .contentShape(Rectangle())
    }

    private func pill(_ text: String, _ kind: PillKind = .outline, id: String? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { pillLabel(text, kind) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .accessibilityIdentifier(id ?? "")
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
            // Discovery-completeness pass — a published survey with no
            // `stories` row is real, expected state (Share To Story is a
            // separate, explicit action), not a bug — but it looked exactly
            // like one from the host's own side, since nothing distinguished
            // it from an already-shared survey. This is the distinction made
            // visible, right where the host can act on it (`mySurveySharedIds`,
            // AppState.swift — populated by `loadMySurveys()`).
            if survey.status == "active" && !app.mySurveySharedIds.contains(survey.id) {
                Text(app.T("Chưa chia sẻ lên story", "Not Shared To Story"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BanbeTheme.alert)
                    .accessibilityIdentifier("survey-not-shared-badge")
            }
            let preview = { openPreview(survey) }
            if survey.status == "draft" {
                HStack(spacing: 8) {
                    pill(app.T("Xuất bản", "Publish"), .filled) { Task { await app.publishSurvey(survey.id) } }
                    pill(app.T("Xem trước", "Preview"), action: preview)
                    pill(app.T("Xoá", "Delete"), .danger) { Task { await app.deleteSurvey(survey.id) } }
                }
                .padding(.top, 6)
            }
            if survey.status == "active" {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        pill(app.T("Chia sẻ lên story", "Share To Story"), .filled) { app.openShareToStoryConfirm(survey) }
                        if let url = URL(string: AppConfig.publicWebOrigin + "/surveys/" + survey.publicId) {
                            ShareLink(item: url, subject: Text(survey.title)) {
                                pillLabel(app.T("Chia sẻ liên kết", "Share Link"), .outline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 8) {
                        pill(app.T("Xem trước", "Preview"), action: preview)
                        pill(app.T("Đóng sớm", "Close early")) { Task { await app.closeSurveyEarly(survey.id) } }
                    }
                }
                .padding(.top, 6)
            }
            if survey.status == "closed" {
                HStack(spacing: 8) {
                    pill(app.T("Xem trước", "Preview"), action: preview)
                    pill(app.T("Lưu trữ", "Archive")) { Task { await app.archiveSurvey(survey.id) } }
                }
                .padding(.top, 6)
            }
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
/// Section 4 redesign — a full-bleed story-canvas preview instead of a
/// small padded card in a medium sheet. Reuses SurveyStoryCardView (the
/// SAME renderer StoryViewerView's real in-story card uses) with the
/// host's own real organizer name/avatar — never a generic "Your
/// organizer" placeholder — so there's no surprise between preview and
/// what viewers actually see. The card's `onAnswerSurvey` is nil here (a
/// visual preview only, never an accidental submit/navigation); Publish
/// below is the only publishing action. Cancel/Publish are anchored in
/// their own bottom bar outside the scrollable canvas, safe-area aware, so
/// a long title/description can never push them off-screen.
private struct ShareSurveyToStoryConfirmView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let survey: SurveySummary

    private var organizerAvatarURL: URL? {
        guard !app.myOrganizerAvatarPath.isEmpty else { return nil }
        return try? SupabaseService.client.storage.from("organizer-photos").getPublicURL(path: app.myOrganizerAvatarPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(app.T("Xem trước story", "Story preview")).font(.system(size: 12.5, weight: .semibold)).opacity(0.7)
                Spacer()
                Button { app.closeShareToStoryConfirm(); dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("survey.shareToStory.close")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            GeometryReader { geo in
                SurveyStoryCardView(
                    hostName: app.orgRegName, hostAvatarURL: organizerAvatarURL,
                    title: survey.title, description: survey.description,
                    closesAt: survey.closesAt, status: "active",
                    onAnswerSurvey: nil, fill: true
                )
                .frame(width: geo.size.width, height: min(geo.size.height, geo.size.width * 15 / 9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)

            if !app.surveyShareToStoryError.isEmpty {
                Text(app.surveyShareToStoryError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
                    .padding(.horizontal, 16).padding(.top, 10)
            }

            HStack(spacing: 8) {
                Button(app.T("Huỷ", "Cancel")) { app.closeShareToStoryConfirm(); dismiss() }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(app.palette.rule))
                Button(app.surveyShareToStoryBusy ? app.T("Đang đăng…", "Posting…") : app.T("Xuất bản", "Publish")) {
                    Task {
                        await app.confirmShareSurveyToStory()
                        if app.surveyShareToStoryTarget == nil { dismiss() }
                    }
                }
                .disabled(app.surveyShareToStoryBusy)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 11))
                .foregroundStyle(app.palette.paper)
                .opacity(app.surveyShareToStoryBusy ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13.5, weight: .semibold))
            .padding(.horizontal, 16).padding(.top, 14)
        }
        .padding(.bottom, 8)
        .presentationDetents([.large])
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
    // Structured date/time slots, picked with the same EventDateTimeSheet
    // Create Event uses, so a suggested draft's date/time can be applied
    // to the event verbatim.
    @State private var slots: [SurveyOption] = []
    @State private var showSlotSheet = false
    @State private var pickedDate: Date?
    @State private var pickedTime: Date?
    // Locations are picked with the same address search Create Event uses
    // (structured address + coordinates), not typed as free text.
    @State private var locations: [SurveyOption] = []
    @State private var locQuery = ""
    @State private var locSuggestions: [AddressSuggestion] = []
    @State private var locSearching = false
    @State private var locError = ""
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

    private static let slotTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = AppState.vietnamTimeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    private func addPickedSlot() {
        defer { pickedDate = nil; pickedTime = nil }
        guard let d = pickedDate, let t = pickedTime else { return }
        let date = AppState.vnDateFormatter.string(from: d)
        let time = Self.slotTimeFormatter.string(from: t)
        guard !slots.contains(where: { $0.date == date && $0.time == time }) else { return }
        let parts = date.split(separator: "-")
        let label = "\(parts[2])/\(parts[1])/\(parts[0]) ▪︎ \(time)"
        slots.append(SurveyOption(id: "", label: label, date: date, time: time))
        slots.sort { ($0.date ?? "") + ($0.time ?? "") < ($1.date ?? "") + ($1.time ?? "") }
    }

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Địa điểm (tìm địa chỉ, có thể thêm nhiều)", "Locations (search an address, add as many as you like)")).font(.system(size: 11.5)).opacity(0.7)
            if !locations.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(locations.enumerated()), id: \.offset) { index, loc in
                        HStack(spacing: 6) {
                            Text(loc.label).font(.system(size: 12))
                            Button { locations.remove(at: index) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(app.palette.rule))
                    }
                }
            }
            TextField(app.T("Nhập số nhà, đường, quận…", "House number, street, district…"), text: $locQuery)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
                .accessibilityIdentifier("survey.location.search")
            if locSearching { Text(app.T("Đang tìm…", "Searching…")).font(.system(size: 11.5)).opacity(0.6) }
            if !locError.isEmpty { Text(locError).font(.system(size: 11.5)).foregroundStyle(BanbeTheme.alert) }
            if !locSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(locSuggestions.enumerated()), id: \.offset) { index, sg in
                        Button { addLocation(sg) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sg.addressLine).font(.system(size: 12.5, weight: .semibold))
                                Text([sg.district, sg.city].filter { !$0.isEmpty }.joined(separator: ", ")).font(.system(size: 11.5)).opacity(0.6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                        if index < locSuggestions.count - 1 { Divider() }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(app.palette.rule))
            }
        }
        // Debounced live search (500ms, 4-char minimum — the same
        // convention Create Event's address box uses); .task(id:) cancels a
        // superseded search automatically.
        .task(id: locQuery) {
            locSuggestions = []; locError = ""
            let q = locQuery.trimmingCharacters(in: .whitespaces)
            guard q.count >= 4 else { locSearching = false; return }
            locSearching = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            let result = await app.searchSurveyAddresses(q)
            if Task.isCancelled { return }
            locSearching = false
            locSuggestions = result.suggestions
            locError = result.error
        }
    }

    private func addLocation(_ sg: AddressSuggestion) {
        let label = [sg.addressLine, sg.district, sg.city].filter { !$0.isEmpty }.joined(separator: ", ")
        let finalLabel = label.isEmpty ? sg.label : label
        guard !locations.contains(where: { $0.label == finalLabel }) else { return }
        locations.append(SurveyOption(
            id: "", label: finalLabel, addressLine: sg.addressLine, district: sg.district, city: sg.city,
            postalCode: sg.postalCode, countryCode: sg.countryCode ?? "", stateProvince: sg.stateProvince ?? "",
            neighborhood: sg.neighborhood ?? "", lat: sg.lat, lng: sg.lng
        ))
        locQuery = ""; locSuggestions = []; locError = ""
    }

    private var slotsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Lựa chọn ngày/giờ (có thể thêm nhiều)", "Date/time options (add as many as you like)")).font(.system(size: 11.5)).opacity(0.7)
            if !slots.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                        HStack(spacing: 6) {
                            Text(slot.label).font(.system(size: 12))
                            Button { slots.remove(at: index) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(app.palette.rule))
                    }
                }
            }
            Button { showSlotSheet = true } label: {
                Text(app.T("+ Thêm ngày/giờ", "+ Add date & time"))
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity).padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(app.palette.rule))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("survey.slot.add")
        }
        .sheet(isPresented: $showSlotSheet, onDismiss: addPickedSlot) {
            EventDateTimeSheet(date: $pickedDate, time: $pickedTime)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(app.T("Tiêu đề", "Title"), $title)
            field(app.T("Mô tả", "Description"), $description)
            field(app.T("Đóng sau (ngày)", "Closes in (days)"), $closesInDays, keyboard: .numberPad)
            slotsSection
            locationsSection
            field(app.T("Mức ngân sách (cách nhau bởi dấu phẩy)", "Budget ranges (comma-separated)"), $budgetOptions)
            field(app.T("Hoạt động mong muốn (không bắt buộc)", "Desired activities (optional)"), $activityOptions)
            field(app.T("Số người tối đa mỗi nhóm", "Max group size"), $groupSizeMax, keyboard: .numberPad)

            if !app.mySurveyCreateError.isEmpty {
                Text(app.mySurveyCreateError).font(.system(size: 12)).foregroundStyle(BanbeTheme.alert)
            }

            Button {
                var config = SurveyConfig()
                config.dateOptions = slots.enumerated().map { SurveyOption(id: "o\($0.offset + 1)", label: $0.element.label, date: $0.element.date, time: $0.element.time) }
                config.locationOptions = locations.enumerated().map { var o = $0.element; o = SurveyOption(id: "o\($0.offset + 1)", label: o.label, addressLine: o.addressLine, district: o.district, city: o.city, postalCode: o.postalCode, countryCode: o.countryCode, stateProvince: o.stateProvince, neighborhood: o.neighborhood, lat: o.lat, lng: o.lng); return o }
                config.budgetOptions = parseOptions(budgetOptions)
                config.activityOptions = parseOptions(activityOptions)
                config.groupSizeMin = 1
                config.groupSizeMax = Int(groupSizeMax) ?? 20
                config.required = ["date_options": !slots.isEmpty, "location_options": !locations.isEmpty]
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

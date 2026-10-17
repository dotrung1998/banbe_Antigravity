import SwiftUI

// Metrics & Reports — a role-aware dashboard over the ONE canonical
// get_account_kpis payload (migration 097): header + range, primary insight,
// KPI overview, needs attention, trends, and a per-metric details sheet.
// Mapping/formatting lives in Lib/ReportsPresentation.swift; components in
// ReportsDashboardComponents.swift; fetch/export in AppState+Reports.swift.

/// `sheet(item:)` needs Identifiable; a String key alone isn't.
private struct ReportDetailTarget: Identifiable {
    let key: String
    var id: String { key }
}

private struct ReportExportFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ReportsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var detail: ReportDetailTarget?
    @State private var showCustomRange = false

    private var dashboard: ReportsDashboard? {
        app.reportsData.map { ReportsPresentation.dashboard($0, fallbackScope: app.reportsScope, T: app.T) }
    }
    private var roleLabel: String { ReportRole(scope: app.reportsData?.scope ?? app.reportsScope).label(app.T) }
    private var rangeLabel: String { ReportsPresentation.rangeText(app.reportsData?.range) }
    /// Data is on screen but a different range is being fetched.
    private var refreshing: Bool { app.reportsLoading && app.reportsData != nil }

    var body: some View {
        ScreenScaffold(onRefresh: { await app.refreshAccountKpis() }) {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.backFromReports() }
                    .padding(.top, 16)

                header.padding(.top, 10)
                rangePicker.padding(.top, 14)

                content
                    .padding(.top, 18)
                    .padding(.bottom, 40)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
        }
        .sheet(item: $detail) { target in
            ReportMetricDetailSheet(metricKey: target.key) { detail = nil }
                .environmentObject(app)
                .presentationDragIndicator(.visible)
                .sheet(item: exportBinding(presentedFromDetail: true)) { file in
                    BanbeShareSheet(items: [file.url]).ignoresSafeArea()
                }
        }
        .sheet(item: exportBinding(presentedFromDetail: false)) { file in
            BanbeShareSheet(items: [file.url]).ignoresSafeArea()
        }
        .sheet(isPresented: $showCustomRange) {
            ReportCustomRangeSheet(isPresented: $showCustomRange).environmentObject(app)
        }
    }

    /// The finished export opens the share sheet from whichever layer is on
    /// top (the details sheet or the dashboard) — never both at once.
    private func exportBinding(presentedFromDetail: Bool) -> Binding<ReportExportFile?> {
        Binding(
            get: {
                guard (detail != nil) == presentedFromDetail else { return nil }
                return app.reportsExportedFileURL.map(ReportExportFile.init)
            },
            set: { if $0 == nil { app.reportsExportedFileURL = nil } }
        )
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background((ROW_ACCENT_COLORS["reports"] ?? .clear).opacity(0.33), in: Circle())
                    .accessibilityHidden(true)
                Text(app.T("Số liệu & báo cáo", "Metrics & Reports"))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                overflowMenu
            }
            // One text run, so large Dynamic Type wraps it as a sentence.
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(roleLabel).fontWeight(.semibold))\(rangeLabel.isEmpty ? "" : "  ·  \(rangeLabel)")")
                if app.reportsLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(app.T("Đang cập nhật…", "Updating…"))
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(app.palette.ink.opacity(0.7))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reports.subtitle")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button { Task { await app.refreshAccountKpis() } } label: {
                Label(app.T("Làm mới", "Refresh"), systemImage: "arrow.clockwise")
            }
            Section(app.T("Xuất báo cáo", "Export report")) {
                Button { app.exportReportsPdf() } label: {
                    Label(app.T("Báo cáo PDF", "PDF report"), systemImage: "doc.richtext")
                }
                .accessibilityIdentifier("reports.export.pdf")
                Button { app.exportReportsJson() } label: {
                    Label(app.T("Dữ liệu JSON", "JSON data"), systemImage: "curlybraces")
                }
                .accessibilityIdentifier("reports.export.json")
            }
            .disabled(app.reportsData == nil || !app.reportsExportBusy.isEmpty)
        } label: {
            Image(systemName: app.reportsExportBusy.isEmpty ? "ellipsis.circle" : "hourglass")
                .font(.system(size: 22, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(app.T("Xuất và tuỳ chọn khác", "Export and more"))
        .accessibilityIdentifier("reports.menu")
    }

    // MARK: range

    private var rangePicker: some View {
        let options: [(ReportsRangeDays, String, String)] = [
            (.days7, "7 ngày", "7d"), (.days30, "30 ngày", "30d"), (.days90, "90 ngày", "90d"),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.2) { days, vi, en in
                    rangeChip(app.T(vi, en), selected: app.reportsRangeDays == days, id: "reports.range.\(en)") {
                        app.setReportsRangeDays(days)
                    }
                }
                rangeChip(app.T("Tuỳ chọn…", "Custom…"), selected: app.reportsRangeDays == .custom, id: "reports.range.custom") {
                    showCustomRange = true
                }
            }
        }
    }

    private func rangeChip(_ text: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(text)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(selected ? app.palette.ink : .clear, in: Capsule())
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .overlay(Capsule().stroke(selected ? .clear : app.palette.rule))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    // MARK: states

    @ViewBuilder
    private var content: some View {
        if let dashboard {
            VStack(alignment: .leading, spacing: 12) {
                if !app.reportsError.isEmpty { staleBanner }
                if dashboard.isEmpty {
                    emptyState
                } else {
                    loaded(dashboard)
                        .opacity(refreshing ? 0.5 : 1)
                        .allowsHitTesting(!refreshing)
                        .animation(.easeInOut(duration: 0.2), value: refreshing)
                }
            }
        } else if !app.reportsError.isEmpty && !app.reportsLoading {
            errorState
        } else {
            ReportsSkeleton()
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(app.reportsError, systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(BanbeTheme.alert)
                .accessibilityIdentifier("reports.error")
            InkButton(title: app.T("Thử lại", "Retry")) { app.loadAccountKpis() }
                .accessibilityIdentifier("reports.retry")
        }
        .reportCard()
    }

    private var staleBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.T("Chưa làm mới được.", "Couldn't refresh."))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("reports.stale")
                if let at = app.reportsLoadedAt {
                    Text(app.T("Đang hiện số liệu lúc \(at.formatted(date: .omitted, time: .shortened)).",
                               "Showing numbers from \(at.formatted(date: .omitted, time: .shortened))."))
                        .font(.footnote)
                }
            }
            Spacer(minLength: 8)
            Button(app.T("Thử lại", "Retry")) { app.loadAccountKpis() }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("reports.stale.retry")
        }
        .padding(14)
        .background(app.palette.honeyBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar").font(.title).opacity(0.5).accessibilityHidden(true)
            Text(app.T("Chưa có số liệu.", "Nothing to show yet."))
                .font(.subheadline)
                .foregroundStyle(app.palette.ink.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reports.empty")
    }

    // MARK: dashboard

    @ViewBuilder
    private func loaded(_ d: ReportsDashboard) -> some View {
        if d.attentionFirst { attentionSection(d.attention) }
        if let primary = d.primary {
            ReportPrimaryCard(metric: primary) { open(primary.key) }
        }
        if !d.overview.isEmpty {
            ReportSectionTitle(text: app.T("Tổng quan", "Overview"))
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(d.overview) { m in ReportKpiTile(metric: m) { open(m.key) } }
            }
        }
        if !d.attentionFirst { attentionSection(d.attention) }
        if !d.insights.isEmpty {
            ReportSectionTitle(text: app.T("Phân tích", "Breakdown"))
            ForEach(d.insights) { i in ReportInsightCard(insight: i) { open(i.metricKey) } }
        }
        if !d.trends.isEmpty {
            ReportSectionTitle(text: app.T("Xu hướng", "Trends"))
            ForEach(d.trends) { m in ReportTrendCard(metric: m) { open(m.key) } }
        }
        allMetrics(d.all)
    }

    @ViewBuilder
    private func attentionSection(_ items: [ReportAttentionItem]) -> some View {
        if !items.isEmpty {
            ReportSectionTitle(text: app.T("Cần chú ý", "Needs attention"))
            ForEach(items) { item in ReportAttentionCard(item: item) { open(item.key) } }
        }
    }

    /// Every metric, one line each — the index into the details sheet, so no
    /// metric is ever unreachable whatever the cards above chose to feature.
    private func allMetrics(_ all: [ReportMetricPresentation]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportSectionTitle(text: app.T("Tất cả số liệu", "All metrics")).padding(.bottom, 6)
            ForEach(Array(all.enumerated()), id: \.element.id) { i, m in
                Button { open(m.key) } label: {
                    HStack(spacing: 10) {
                        Text(m.title).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(m.valueText).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.4)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityValue(m.accessibilityValue)
                .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
                .accessibilityIdentifier("reports.all.\(m.key)")
                if i < all.count - 1 { Divider().overlay(app.palette.rule) }
            }
        }
        .padding(.top, 8)
    }

    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    private func open(_ key: String) {
        Haptics.light()
        detail = ReportDetailTarget(key: key)
    }
}

// MARK: - Custom range

private struct ReportCustomRangeSheet: View {
    @EnvironmentObject private var app: AppState
    @Binding var isPresented: Bool
    @State private var start = Date()
    @State private var end = Date()
    @State private var seeded = false

    /// The RPC builds a daily series for the whole range; a year is plenty.
    private static let maxDays = 366
    private var tooLong: Bool {
        (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) >= Self.maxDays
    }

    var body: some View {
        CardSheet(title: app.T("Khoảng tuỳ chọn", "Custom range"), closeID: "reports.custom.close",
                  onClose: { isPresented = false }) {
            VStack(alignment: .leading, spacing: 16) {
                DatePicker(app.T("Từ ngày", "From"), selection: $start, in: ...end, displayedComponents: .date)
                    .accessibilityIdentifier("reports.custom.start")
                DatePicker(app.T("Đến ngày", "To"), selection: $end, in: start...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("reports.custom.end")
                if tooLong {
                    Label(app.T("Chọn tối đa 1 năm.", "Pick at most one year."), systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(BanbeTheme.alert)
                }
                InkButton(title: app.T("Áp dụng", "Apply"), enabled: !tooLong) {
                    app.setReportsCustomRange(start: start, end: end)
                    isPresented = false
                }
                .accessibilityIdentifier("reports.custom.apply")
            }
            .environment(\.locale, Locale(identifier: app.isEN ? "en_US" : "vi_VN"))
        }
        .presentationDetents([.medium])
        .onAppear {
            guard !seeded else { return }
            seeded = true
            if app.reportsRangeDays == .custom {
                start = app.reportsCustomStart; end = app.reportsCustomEnd
            } else {
                end = Date()
                start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
            }
        }
    }
}

import Charts
import SwiftUI

// Building blocks of the Metrics & Reports dashboard (ReportsView.swift).
// Everything renders a `ReportMetricPresentation`/`ReportAttentionItem`
// (Lib/ReportsPresentation.swift) — no view formats a raw payload value.

// MARK: - Surface

/// The dashboard's card surface: the existing `field` fill on the paper
/// canvas, a larger radius and a soft lift in light mode only (a shadow on
/// dark paper reads as dirt, so dark gets a hairline instead).
struct ReportCardSurface: ViewModifier {
    @EnvironmentObject private var app: AppState
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(app.palette.rule.opacity(app.theme == "dark" ? 0.6 : 0), lineWidth: 1)
            )
            .shadow(color: app.palette.ink.opacity(app.theme == "dark" ? 0 : 0.06), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func reportCard(padding: CGFloat = 16) -> some View { modifier(ReportCardSurface(padding: padding)) }
}

/// Small uppercase-free section heading used between dashboard groups.
struct ReportSectionTitle: View {
    @EnvironmentObject private var app: AppState
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(app.palette.ink.opacity(0.7))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 8)
    }
}

// MARK: - Charts

/// Compact bars without axes for the primary card. Zero days stay visible as
/// faint stubs so the rhythm of the range reads at a glance.
struct ReportSparkline: View {
    @EnvironmentObject private var app: AppState
    let metric: ReportMetricPresentation

    var body: some View {
        Chart(metric.series) { p in
            BarMark(x: .value(app.T("Ngày", "Day"), p.date, unit: .day),
                    y: .value(metric.title, p.value > 0 ? p.value : maxValue * 0.02))
                .foregroundStyle(app.palette.ink.opacity(p.value > 0 ? 0.85 : 0.14))
                .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(maxValue, 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(ReportsPresentation.seriesSentence(metric, T: app.T))
    }

    private var maxValue: Double { metric.series.map(\.value).max() ?? 0 }
}

/// The full chart (axes, readable labels) used by trend cards, the detail
/// sheet and the "Save image" export.
struct ReportTrendChart: View {
    @EnvironmentObject private var app: AppState
    let metric: ReportMetricPresentation
    var height: CGFloat = 170

    var body: some View {
        Chart(metric.series) { p in
            BarMark(x: .value(app.T("Ngày", "Day"), p.date, unit: .day),
                    y: .value(metric.title, p.value))
                .foregroundStyle(app.palette.ink.opacity(0.82))
                .cornerRadius(2)
                .accessibilityLabel(ReportsPresentation.formatDay(p.date, T: app.T))
                .accessibilityValue(ReportsPresentation.formatValue(p.value, kind: metric.kind, metricKey: metric.key, T: app.T, spoken: true))
        }
        .chartYScale(domain: 0...max(metric.series.map(\.value).max() ?? 0, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(app.palette.rule)
                AxisValueLabel {
                    if let d = value.as(Date.self) { Text(ReportsPresentation.formatDay(d, T: app.T)) }
                }
                .foregroundStyle(app.palette.ink.opacity(0.65))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(app.palette.rule)
                AxisValueLabel {
                    if let n = value.as(Double.self) { Text(ReportsPresentation.compact(n, kind: metric.kind, T: app.T)) }
                }
                .foregroundStyle(app.palette.ink.opacity(0.65))
            }
        }
        .frame(height: height)
        .accessibilityLabel(metric.title)
        .accessibilityValue(ReportsPresentation.seriesSentence(metric, T: app.T))
    }
}

/// What "Save image" rasterizes: title + range baked in so the PNG stands
/// alone, always on a light background for legibility outside the app.
struct ReportChartView: View {
    @EnvironmentObject private var app: AppState
    let metric: ReportMetricPresentation
    let rangeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title).font(.system(size: 15, weight: .semibold))
            Text("\(metric.valueText) · \(rangeLabel)").font(.system(size: 11)).opacity(0.65)
            ReportTrendChart(metric: metric, height: 180).padding(.top, 8)
        }
        .foregroundStyle(Palette.light.ink)
        .padding(16)
        .background(Palette.light.paper)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Cards

/// The one large card at the top: headline value, a compact real chart and
/// two facts read off the same series. No delta — there is no prior period.
struct ReportPrimaryCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReportMetricPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.45)
                        .accessibilityHidden(true)
                }
                Text(metric.valueText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(metric.isTimeSeries ? app.T("Trong khoảng đã chọn", "In this range") : app.T("Hiện tại", "Right now"))
                    .font(.footnote)
                    .foregroundStyle(app.palette.ink.opacity(0.65))

                if let summary = metric.summary {
                    if summary.hasActivity && dynamicTypeSize.isAccessibilitySize {
                        // Large text: a readable sentence instead of a squeezed chart.
                        Text(ReportsPresentation.seriesSentence(metric, T: app.T))
                            .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    } else if summary.hasActivity {
                        ReportSparkline(metric: metric).frame(height: 64).padding(.top, 4)
                        facts(summary)
                    } else {
                        Label(app.T("Không có hoạt động trong khoảng này.", "No activity in this range."),
                              systemImage: "minus.circle")
                            .font(.footnote)
                            .foregroundStyle(app.palette.ink.opacity(0.65))
                            .padding(.top, 2)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .reportCard(padding: 18)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.accessibilityValue). \(ReportsPresentation.seriesSentence(metric, T: app.T))")
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.primary.\(metric.key)")
    }

    private func facts(_ s: ReportSeriesSummary) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { factItems(s) }
            VStack(alignment: .leading, spacing: 6) { factItems(s) }
        }
        .font(.footnote)
        .foregroundStyle(app.palette.ink.opacity(0.75))
    }

    @ViewBuilder
    private func factItems(_ s: ReportSeriesSummary) -> some View {
        if let peak = s.peak {
            Label(app.T("Cao nhất \(ReportsPresentation.compact(peak.value, kind: metric.kind, T: app.T)) · \(ReportsPresentation.formatDay(peak.date, T: app.T))",
                        "Peak \(ReportsPresentation.compact(peak.value, kind: metric.kind, T: app.T)) · \(ReportsPresentation.formatDay(peak.date, T: app.T))"),
                  systemImage: "arrow.up.to.line")
        }
        Label(app.T("\(s.activeDays)/\(s.dayCount) ngày có hoạt động", "Active \(s.activeDays) of \(s.dayCount) days"),
              systemImage: "calendar")
    }
}

/// A compact KPI tile for the overview grid.
struct ReportKpiTile: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReportMetricPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text(metric.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(app.palette.ink.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(metric.valueText)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                // A compact strip only for a genuine series with activity.
                if metric.summary?.hasActivity == true && !dynamicTypeSize.isAccessibilitySize {
                    ReportSparkline(metric: metric).frame(height: 18)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("reports.kpi.strip.\(metric.key)")
                }
                Text(metric.isTimeSeries ? app.T("Trong khoảng đã chọn", "In this range") : app.T("Hiện tại", "Right now"))
                    .font(.caption)
                    .foregroundStyle(app.palette.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .foregroundStyle(app.palette.ink)
            .reportCard(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue(metric.accessibilityValue)
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.kpi.\(metric.key)")
    }
}

/// "Needs attention": icon + words carry the state, the accent only repeats it.
struct ReportAttentionCard: View {
    @EnvironmentObject private var app: AppState
    let item: ReportAttentionItem
    let onOpen: () -> Void

    private var tint: Color { item.severity == .pending ? app.palette.honey : BanbeTheme.alert }
    private var badge: String {
        switch item.severity {
        case .overdue: return app.T("Quá hạn", "Overdue")
        case .urgent: return app.T("Cần xử lý sớm", "Act soon")
        case .pending: return app.T("Cần xử lý", "Needs action")
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(minWidth: 28)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(item.valueText).font(.system(.headline, design: .rounded).weight(.bold))
                    }
                    Text(item.message)
                        .font(.footnote)
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.top, 2)
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.45)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .leading) {
                // A leading rule, so the state never depends on the icon colour alone.
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge): \(item.title)")
        .accessibilityValue("\(item.valueText). \(item.message)")
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.attention.\(item.key)")
    }
}

/// A larger chart card for each remaining genuine series.
struct ReportTrendCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReportMetricPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(metric.valueText).font(.system(.headline, design: .rounded).weight(.bold))
                }
                if metric.summary?.hasActivity == true && dynamicTypeSize.isAccessibilitySize {
                    Text(ReportsPresentation.seriesSentence(metric, T: app.T))
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                } else if metric.summary?.hasActivity == true {
                    ReportTrendChart(metric: metric, height: 150)
                } else {
                    Label(app.T("Không có hoạt động trong khoảng này.", "No activity in this range."),
                          systemImage: "minus.circle")
                        .font(.footnote)
                        .foregroundStyle(app.palette.ink.opacity(0.65))
                }
            }
            .foregroundStyle(app.palette.ink)
            .reportCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.accessibilityValue). \(ReportsPresentation.seriesSentence(metric, T: app.T))")
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.trend.\(metric.key)")
    }
}

// MARK: - Breakdowns

/// A share (ring + "n of m") or a distribution (segmented bar + labelled
/// legend). Every value is printed as text; segments differ by both shade
/// and a separator, and the legend names each one — never colour alone.
struct ReportInsightCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let insight: ReportInsight
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.45)
                        .accessibilityHidden(true)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    Text(ReportsPresentation.insightSentence(insight, T: app.T))
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                } else {
                    switch insight {
                    case .share(let s): share(s)
                    case .distribution(let d): distribution(d)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .reportCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(ReportsPresentation.insightSentence(insight, T: app.T))
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("reports.insight.\(insight.id)")
    }

    private var title: String {
        switch insight {
        case .share(let s): return s.title
        case .distribution(let d): return d.title
        }
    }

    private func share(_ s: ReportShareInsight) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(app.palette.ink.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: s.fraction)
                    .stroke(app.palette.ink, style: StrokeStyle(lineWidth: 7, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text("\(s.numerator)/\(s.denominator)")
                    .font(.system(.footnote, design: .rounded).weight(.bold)).monospacedDigit()
            }
            .frame(width: 58, height: 58)
            Text(s.caption).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func distribution(_ d: ReportDistributionInsight) -> some View {
        let shades: [Double] = [0.9, 0.55, 0.32, 0.18]
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(d.segments.enumerated()), id: \.element.id) { i, seg in
                        if seg.count > 0 {
                            Rectangle().fill(app.palette.ink.opacity(shades[i % shades.count]))
                                .frame(width: max(4, (geo.size.width - CGFloat(d.segments.count - 1) * 2) * CGFloat(seg.count) / CGFloat(max(d.total, 1))))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 12)
            ForEach(Array(d.segments.enumerated()), id: \.element.id) { i, seg in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(app.palette.ink.opacity(shades[i % shades.count]))
                        .frame(width: 10, height: 10)
                    Text(seg.label).font(.footnote)
                    Spacer(minLength: 8)
                    Text("\(seg.count)").font(.footnote.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Loading skeleton

/// Same footprint as the loaded dashboard (primary + 4 tiles + one trend), so
/// nothing jumps when data arrives. Static — no shimmer to respect motion.
struct ReportsSkeleton: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            block(height: 196)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in block(height: 96) }
            }
            block(height: 210)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Đang tải số liệu", "Loading metrics"))
        .accessibilityIdentifier("reports.skeleton")
    }

    private func block(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(app.palette.field)
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(app.palette.ink.opacity(0.08)).frame(width: 110, height: 10)
                    Capsule().fill(app.palette.ink.opacity(0.12)).frame(width: 70, height: 18)
                }
                .padding(16)
            }
    }
}

// MARK: - Metric details

struct ReportMetricDetailSheet: View {
    @EnvironmentObject private var app: AppState
    let metricKey: String
    let onClose: () -> Void
    @State private var savingImage = false
    @State private var saveMessage: String?

    private var raw: AccountKpiMetric? { app.reportsData?.metrics?.first { $0.key == metricKey } }

    var body: some View {
        CardSheet(title: raw.map { ReportMetricLabels.label($0, app.T) } ?? "", closeID: "reports.detail.close", onClose: onClose) {
            if let raw {
                let metric = ReportsPresentation.metric(raw, T: app.T)
                let rows = ReportsPresentation.rows(raw, T: app.T)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.valueText)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .accessibilityLabel(metric.accessibilityValue)
                            Text(metric.isTimeSeries ? rangeLabel : app.T("Số liệu hiện tại, không theo thời gian.", "A current total, not a time series."))
                                .font(.footnote).foregroundStyle(app.palette.ink.opacity(0.65))
                        }

                        if metric.isTimeSeries {
                            ReportTrendChart(metric: metric, height: 200)
                            Text(ReportsPresentation.seriesSentence(metric, T: app.T))
                                .font(.footnote).foregroundStyle(app.palette.ink.opacity(0.75))
                            Button {
                                Task { await saveImage(metric) }
                            } label: {
                                Label(savingImage ? app.T("Đang lưu…", "Saving…") : app.T("Lưu ảnh biểu đồ", "Save chart image"),
                                      systemImage: "square.and.arrow.down")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(savingImage)
                            .accessibilityIdentifier("reports.detail.saveImage")
                            if let saveMessage {
                                Text(saveMessage).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.7))
                            }
                        }

                        HStack {
                            Text(app.T("Dữ liệu chi tiết", "Underlying data")).font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button {
                                app.exportReportCardCsv(metricKey)
                            } label: {
                                Label(app.T("Xuất CSV", "Export CSV"), systemImage: "tablecells")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityIdentifier("reports.detail.csv")
                        }
                        .padding(.top, 6)

                        if rows.isEmpty {
                            Text(app.T("Không có bản ghi nào để hiển thị.", "No records to show."))
                                .font(.footnote).foregroundStyle(app.palette.ink.opacity(0.65))
                        } else {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(rows.prefix(100)) { row in rowCard(row) }
                            }
                            if rows.count > 100 {
                                Text(app.T("Hiển thị 100/\(rows.count) bản ghi. Xuất CSV để xem tất cả.",
                                           "Showing 100 of \(rows.count) records. Export CSV for all of them."))
                                    .font(.footnote).foregroundStyle(app.palette.ink.opacity(0.65))
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            } else {
                Text(app.T("Số liệu này không còn trong báo cáo.", "This metric is no longer in the report."))
                    .font(.footnote)
            }
        }
    }

    private var rangeLabel: String { ReportsPresentation.rangeText(app.reportsData?.range) }

    private func rowCard(_ row: ReportRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.subheadline.weight(.semibold))
                if row.flagged {
                    Spacer(minLength: 6)
                    Label(app.T("Quá hạn", "Overdue"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BanbeTheme.alert)
                }
            }
            ForEach(Array(row.fields.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(f.label).font(.footnote).foregroundStyle(app.palette.ink.opacity(0.65))
                    Spacer(minLength: 8)
                    Text(f.value).font(.footnote.weight(.medium)).multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor
    private func saveImage(_ metric: ReportMetricPresentation) async {
        savingImage = true
        defer { savingImage = false }
        let ok = await app.saveReportChartImage(
            ReportChartView(metric: metric, rangeLabel: rangeLabel).environmentObject(app).frame(width: 360))
        saveMessage = ok ? app.T("Đã lưu vào Ảnh", "Saved to Photos") : app.T("Không thể lưu ảnh. Hãy cho phép banbe thêm ảnh trong Cài đặt.", "Couldn't save the image. Allow banbe to add photos in Settings.")
    }
}

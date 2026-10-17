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
    /// Stretch to the row height (KPI grid), so neighbouring tiles line up.
    var fillHeight = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(app.palette.rule.opacity(app.theme == "dark" ? 0.6 : 0), lineWidth: 1)
            )
            .shadow(color: app.palette.ink.opacity(app.theme == "dark" ? 0 : 0.06), radius: 12, x: 0, y: 4)
    }
}

/// The hero's warmer, layered surface: the screen's own Reports accent
/// (moss, as on the header icon) washing into the usual card fill.
struct ReportHeroSurface: ViewModifier {
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        let dark = app.theme == "dark"
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(app.palette.field)
                shape.fill(LinearGradient(colors: [reportsAccent.opacity(dark ? 0.2 : 0.55), reportsAccent.opacity(0)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(shape.stroke(app.palette.ink.opacity(dark ? 0.14 : 0.05), lineWidth: 1))
            .shadow(color: app.palette.ink.opacity(dark ? 0 : 0.08), radius: 18, x: 0, y: 8)
    }
}

/// The Reports screen accent, shared with its header icon and Account row.
var reportsAccent: Color { ROW_ACCENT_COLORS["reports"] ?? .clear }

extension View {
    func reportCard(padding: CGFloat = 16, fillHeight: Bool = false) -> some View {
        modifier(ReportCardSurface(padding: padding, fillHeight: fillHeight))
    }
    func reportHeroCard() -> some View { modifier(ReportHeroSurface()) }
}

/// A metric's glyph in the screen's accent circle. Decoration only — it
/// always sits next to the metric's title, so it's hidden from VoiceOver.
struct ReportGlyph: View {
    @EnvironmentObject private var app: AppState
    let symbol: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(app.palette.ink.opacity(0.8))
            .frame(width: size, height: size)
            .background(reportsAccent.opacity(app.theme == "dark" ? 0.28 : 0.5), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Section heading between dashboard groups, with an optional count.
struct ReportSectionTitle: View {
    @EnvironmentObject private var app: AppState
    let text: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(app.palette.ink.opacity(0.75))
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(app.palette.ink.opacity(0.08), in: Capsule())
                    .foregroundStyle(app.palette.ink.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.top, 14)
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

// MARK: - Dashboard charts

/// Dashboard-only daily bars: data first, no axes or grid. The peak day is
/// the one full-strength bar and carries its value; the first/last days
/// under the plot name the range — so the meaning reads without touching
/// anything. Zero days stay as faint stubs so the rhythm of the range shows.
/// (The detail sheet and the "Save image" export keep `ReportTrendChart`,
/// unchanged.)
struct ReportDailyBars: View {
    @EnvironmentObject private var app: AppState
    let metric: ReportMetricPresentation
    var height: CGFloat = 110

    private var maxValue: Double { metric.series.map(\.value).max() ?? 0 }

    var body: some View {
        let peak = metric.summary?.peak
        let top = max(maxValue, 1)
        VStack(spacing: 6) {
            Chart(metric.series) { p in
                // Every day that reaches the peak value looks the same; only
                // the first (the one the stats name) carries the label.
                let atPeak = peak.map { p.value == $0.value } ?? false
                BarMark(x: .value(app.T("Ngày", "Day"), p.date, unit: .day),
                        y: .value(metric.title, p.value > 0 ? p.value : top * 0.03),
                        width: .ratio(0.62))
                    .foregroundStyle(app.palette.ink.opacity(atPeak ? 0.95 : (p.value > 0 ? 0.5 : 0.12)))
                    .cornerRadius(metric.series.count > 45 ? 1 : 3)
                    .annotation(position: .top, spacing: 3) {
                        if p.dayKey == peak?.dayKey {
                            Text(ReportsPresentation.compact(p.value, kind: metric.kind, T: app.T))
                                .font(.caption2.weight(.bold)).monospacedDigit()
                                .foregroundStyle(app.palette.ink)
                                .fixedSize()
                        }
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            // Headroom for the peak label.
            .chartYScale(domain: 0...(top * 1.28))
            .frame(height: height)

            if let first = metric.series.first, let last = metric.series.last {
                HStack {
                    Text(ReportsPresentation.formatDay(first.date, T: app.T))
                    Spacer(minLength: 8)
                    Text(ReportsPresentation.formatDay(last.date, T: app.T))
                }
                .font(.caption2).monospacedDigit()
                .foregroundStyle(app.palette.ink.opacity(0.55))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(ReportsPresentation.seriesSentence(metric, T: app.T))
    }
}

/// Three facts read off the same series — peak, active days, daily average.
/// Side by side when they fit, stacked otherwise.
struct ReportSeriesStats: View {
    @EnvironmentObject private var app: AppState
    let metric: ReportMetricPresentation
    let summary: ReportSeriesSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                items(divided: true)
            }
            VStack(alignment: .leading, spacing: 10) { items(divided: false) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func items(divided: Bool) -> some View {
        if let peak = summary.peak {
            stat(app.T("Cao nhất", "Peak"),
                 ReportsPresentation.compact(peak.value, kind: metric.kind, T: app.T),
                 ReportsPresentation.formatDay(peak.date, T: app.T), divided: divided)
        }
        if divided { separator }
        stat(app.T("Hoạt động", "Active days"), "\(summary.activeDays)/\(summary.dayCount)",
             app.T("ngày", "days"), divided: divided)
        if divided { separator }
        stat(app.T("Trung bình", "Daily average"),
             ReportsPresentation.dailyAverageText(summary, kind: metric.kind, T: app.T), nil, divided: divided)
    }

    private var separator: some View {
        Rectangle().fill(app.palette.ink.opacity(0.12)).frame(width: 1).frame(maxHeight: 36)
    }

    private func stat(_ label: String, _ value: String, _ detail: String?, divided: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(app.palette.ink.opacity(0.6))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold)).monospacedDigit()
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(app.palette.ink.opacity(0.6)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: divided ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - Cards

/// The one hero at the top: one dominant number, what it counts (the RPC's
/// own definition), the real daily bars behind it and three facts read off
/// the same series. No delta, target or benchmark — there is no prior period.
struct ReportPrimaryCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 46
    let metric: ReportMetricPresentation
    let role: ReportRole
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ReportGlyph(symbol: ReportsPresentation.symbol(for: metric.key), size: 30)
                    Text(metric.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.45)
                        .accessibilityHidden(true)
                }
                Text(metric.valueText)
                    .font(.system(size: valueSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.top, 14)
                Text(ReportsPresentation.meaning(metric, role: role, T: app.T))
                    .font(.footnote)
                    .foregroundStyle(app.palette.ink.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)

                if let summary = metric.summary {
                    Group {
                        if summary.hasActivity && dynamicTypeSize.isAccessibilitySize {
                            // Large text: a readable sentence instead of a squeezed chart.
                            Text(ReportsPresentation.seriesSentence(metric, T: app.T))
                                .font(.footnote).fixedSize(horizontal: false, vertical: true)
                        } else if summary.hasActivity {
                            VStack(alignment: .leading, spacing: 14) {
                                ReportDailyBars(metric: metric, height: 104)
                                Divider().overlay(app.palette.ink.opacity(0.08))
                                ReportSeriesStats(metric: metric, summary: summary)
                            }
                        } else {
                            Label(app.T("Không có hoạt động trong khoảng này.", "No activity in this range."),
                                  systemImage: "minus.circle")
                                .font(.footnote)
                                .foregroundStyle(app.palette.ink.opacity(0.65))
                        }
                    }
                    .padding(.top, 18)
                }
            }
            .foregroundStyle(app.palette.ink)
            .reportHeroCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.accessibilityValue). \(ReportsPresentation.meaning(metric, role: role, T: app.T)). \(ReportsPresentation.seriesSentence(metric, T: app.T))")
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.primary.\(metric.key)")
    }
}

/// A KPI tile: title, the number, one line of what it counts, and a compact
/// strip only when there is a genuine series with activity.
struct ReportKpiTile: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReportMetricPresentation
    let role: ReportRole
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text(metric.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.78))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if !dynamicTypeSize.isAccessibilitySize {
                        ReportGlyph(symbol: ReportsPresentation.symbol(for: metric.key), size: 26)
                    }
                }
                Text(metric.valueText)
                    .font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 8)
                Text(ReportsPresentation.meaning(metric, role: role, T: app.T))
                    .font(.caption)
                    .foregroundStyle(app.palette.ink.opacity(0.6))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Spacer(minLength: 10)
                if metric.summary?.hasActivity == true && !dynamicTypeSize.isAccessibilitySize {
                    ReportSparkline(metric: metric).frame(height: 22)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("reports.kpi.strip.\(metric.key)")
                }
            }
            .foregroundStyle(app.palette.ink)
            .reportCard(padding: 14, fillHeight: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.accessibilityValue). \(ReportsPresentation.meaning(metric, role: role, T: app.T))")
        .accessibilityHint(app.T("Mở chi tiết", "Opens details"))
        .accessibilityIdentifier("reports.kpi.\(metric.key)")
    }
}

/// "Needs attention": a state badge in words, the amount, what's going on
/// and what tapping shows. Icon + words + leading rule carry the state; the
/// tint only repeats it. Alert red is kept for genuinely late/conflicting
/// items; a queue gets the calmer honey.
struct ReportAttentionCard: View {
    @EnvironmentObject private var app: AppState
    let item: ReportAttentionItem
    let onOpen: () -> Void

    private var calm: Bool { item.severity == .pending }
    private var tint: Color { calm ? app.palette.honey : BanbeTheme.alert }
    private var badge: String {
        switch item.severity {
        case .overdue: return app.T("Quá hạn", "Overdue")
        case .urgent: return app.T("Cần xử lý sớm", "Act soon")
        case .pending: return app.T("Cần xử lý", "Needs action")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(tint.opacity(0.14), in: Capsule())
                        Spacer(minLength: 8)
                        Text(item.valueText)
                            .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(item.title).font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                    Text(item.message)
                        .font(.footnote)
                        .foregroundStyle(app.palette.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text(ReportsPresentation.attentionAction(item, T: app.T))
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 6)
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(16)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(app.palette.field)
                shape.fill(calm ? app.palette.honeyBg.opacity(0.7) : BanbeTheme.alert.opacity(0.07))
            }
            .overlay(shape.stroke(tint.opacity(0.22), lineWidth: 1))
            .overlay(alignment: .leading) {
                // A leading rule, so the state never depends on the icon colour alone.
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4).padding(.vertical, 16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge): \(item.title)")
        .accessibilityValue("\(item.valueText). \(item.message)")
        .accessibilityHint(ReportsPresentation.attentionAction(item, T: app.T))
        .accessibilityIdentifier("reports.attention.\(item.key)")
    }
}

/// A chart card for each remaining genuine series: total, meaning, the same
/// daily bars as the hero and a one-line peak/active-days fact.
struct ReportTrendCard: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let metric: ReportMetricPresentation
    let role: ReportRole
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ReportGlyph(symbol: ReportsPresentation.symbol(for: metric.key), size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.title).font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(ReportsPresentation.meaning(metric, role: role, T: app.T))
                            .font(.caption).foregroundStyle(app.palette.ink.opacity(0.6))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(metric.valueText)
                        .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if let s = metric.summary, s.hasActivity, dynamicTypeSize.isAccessibilitySize {
                    Text(ReportsPresentation.seriesSentence(metric, T: app.T))
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                } else if let s = metric.summary, s.hasActivity {
                    ReportDailyBars(metric: metric, height: 84).padding(.top, 4)
                    ReportSeriesStats(metric: metric, summary: s).padding(.top, 2)
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
            block(height: 300, radius: 24)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in block(height: 150) }
            }
            block(height: 200)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.T("Đang tải số liệu", "Loading metrics"))
        .accessibilityIdentifier("reports.skeleton")
    }

    private func block(height: CGFloat, radius: CGFloat = 20) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
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

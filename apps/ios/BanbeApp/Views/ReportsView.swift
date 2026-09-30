import SwiftUI
import Charts

private let roleLabels: [String: (String, String)] = [
    "personal": ("Cá nhân", "Personal"), "host": ("Tổ chức", "Host"), "admin": ("Quản trị", "Admin"),
]

private func vnDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: iso) ?? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: iso)
    }() else { return iso }
    let df = DateFormatter()
    df.dateFormat = "dd/MM"
    df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
    return df.string(from: d)
}

/// The mini chart — a real Swift Charts `Chart`, not a third-party
/// dependency, with its own title/range baked directly into the view (so
/// rasterizing THIS exact view for "Lưu ảnh" already carries them, per the
/// ticket's own "PNG with title, range and readable labels" ask).
struct ReportChartView: View {
    let metric: AccountKpiMetric
    let rangeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label).font(.system(size: 13, weight: .semibold))
            Text(rangeLabel).font(.system(size: 11)).opacity(0.6)
            if let series = metric.series, !series.isEmpty {
                Chart(series) { point in
                    BarMark(x: .value("d", vnDate(point.d)), y: .value("v", point.v))
                        .foregroundStyle(.primary.opacity(point.v > 0 ? 0.82 : 0.12))
                }
                .frame(height: 160)
                .chartYAxis { AxisMarks(position: .leading) }
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
    }
}

struct ReportsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showCustomRange = false

    private var roleLabel: String {
        guard let pair = roleLabels[app.reportsScope] else { return app.reportsScope }
        return app.T(pair.0, pair.1)
    }
    private var rangeLabel: String {
        guard let range = app.reportsData?.range,
              let s = ISO8601DateFormatter().date(from: range.start), let e = ISO8601DateFormatter().date(from: range.end) else { return "" }
        let df = DateFormatter(); df.dateFormat = "dd/MM/yyyy"; df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return "\(df.string(from: s)) – \(df.string(from: e))"
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Quay lại", "Back")) { app.backFromReports() }
                    .padding(.top, 16)

                Text(app.T("Số liệu & báo cáo", "Metrics & Reports"))
                    .font(BanbeTheme.display(24)).padding(.top, 10)
                Text(roleLabel).font(.system(size: 12)).foregroundStyle(app.palette.ink.opacity(0.65))

                rangePicker.padding(.top, 16)

                HStack(spacing: 14) {
                    Button(app.T("Mở tất cả", "Expand all")) { app.expandAllReportCards() }
                    Button(app.T("Thu gọn tất cả", "Collapse all")) { app.collapseAllReportCards() }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.top, 12)

                if app.reportsLoading && app.reportsData == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if !app.reportsError.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.reportsError).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert)
                        InkButton(title: app.T("Thử lại", "Retry")) { app.loadAccountKpis() }
                    }
                    .padding(.top, 20)
                } else if let metrics = app.reportsData?.metrics {
                    if metrics.isEmpty {
                        Text(app.T("Chưa có số liệu.", "Nothing to show yet."))
                            .font(.system(size: 13)).foregroundStyle(app.palette.ink.opacity(0.6))
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(metrics) { metric in
                                MetricCardView(metric: metric, rangeLabel: rangeLabel, expanded: app.reportsExpanded.contains(metric.key))
                            }
                        }
                        .padding(.top, 16)

                        HStack(spacing: 10) {
                            if let url = app.reportsExportedFileURL {
                                ShareLink(item: url) {
                                    Text(app.T("Chia sẻ tệp đã xuất", "Share exported file"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                                        .foregroundStyle(app.palette.ink)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                                }
                            }
                        }
                        .padding(.top, 12)

                        HStack(spacing: 10) {
                            Button(app.T("Tải dữ liệu JSON", "Download JSON")) { app.exportReportsJson() }
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.palette.rule))
                            Button(app.reportsExportBusy == "pdf" ? app.T("Đang tạo…", "Generating…") : app.T("Tải báo cáo PDF", "Download PDF report")) {
                                app.exportReportsPdf()
                            }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(app.palette.ink, in: RoundedRectangle(cornerRadius: 12))
                            .disabled(!app.reportsExportBusy.isEmpty)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach([(ReportsRangeDays.days7, "7"), (.days30, "30"), (.days90, "90")], id: \.1) { days, label in
                Button {
                    app.setReportsRangeDays(days)
                } label: {
                    Text(app.T("\(label) ngày", "\(label)d"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(app.reportsRangeDays == days ? app.palette.ink : .clear, in: Capsule())
                        .foregroundStyle(app.reportsRangeDays == days ? app.palette.paper : app.palette.ink)
                        .overlay(Capsule().stroke(app.reportsRangeDays == days ? .clear : app.palette.rule))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MetricCardView: View {
    @EnvironmentObject private var app: AppState
    let metric: AccountKpiMetric
    let rangeLabel: String
    let expanded: Bool
    @State private var savingImage = false
    @State private var saveResultMessage: String?

    private var displayValue: String {
        if metric.unit == "vnd" {
            let n: Double = { if case .number(let v) = metric.value { return v }; return 0 }()
            let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "."
            return "\(f.string(from: NSNumber(value: n)) ?? "0") đ"
        }
        if metric.unit == "days" { return app.T("\(metric.value.displayString) ngày", "\(metric.value.displayString) days") }
        return metric.value.displayString
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { app.toggleReportCard(metric.key) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label).font(.system(size: 13, weight: .semibold))
                        Text(metric.series?.isEmpty == false ? rangeLabel : app.T("Hiện tại", "Right now"))
                            .font(.system(size: 11)).opacity(0.6)
                    }
                    Spacer()
                    Text(displayValue).font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 11)).opacity(0.55)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(app.palette.ink)
                .padding(14)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let series = metric.series, !series.isEmpty {
                        ReportChartView(metric: metric, rangeLabel: rangeLabel)
                            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 10))
                        Button(savingImage ? app.T("Đang lưu…", "Saving…") : app.T("Lưu ảnh", "Save image")) {
                            Task {
                                savingImage = true
                                let ok = await app.saveReportChartImage(ReportChartView(metric: metric, rangeLabel: rangeLabel).frame(width: 340))
                                saveResultMessage = ok ? app.T("Đã lưu vào Ảnh", "Saved to Photos") : app.T("Không thể lưu ảnh", "Couldn't save the image")
                                savingImage = false
                            }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .disabled(savingImage)
                        if let msg = saveResultMessage {
                            Text(msg).font(.system(size: 10.5)).opacity(0.6)
                        }
                    } else {
                        Text(app.T("Số liệu hiện tại, không theo biểu đồ thời gian.", "A current total, not a time series."))
                            .font(.system(size: 11.5)).opacity(0.6)
                    }

                    HStack {
                        Text(app.T("Dữ liệu chi tiết", "Underlying data")).font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Button(app.T("Tải CSV", "Download CSV")) { app.exportReportCardCsv(metric.key) }
                            .font(.system(size: 11.5, weight: .semibold))
                    }

                    let rows = metric.rows ?? []
                    if rows.isEmpty {
                        Text(app.T("Không có dữ liệu trong khoảng thời gian này.", "No data in this range."))
                            .font(.system(size: 12)).opacity(0.6)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                let columns = rows[0].keys.sorted()
                                Text(columns.joined(separator: "  •  ")).font(.system(size: 10.5, weight: .semibold)).opacity(0.6)
                                ForEach(Array(rows.prefix(50).enumerated()), id: \.offset) { _, row in
                                    Text(columns.map { row[$0]?.displayString ?? "" }.joined(separator: "  •  "))
                                        .font(.system(size: 11))
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .padding(.top, -6)
            }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

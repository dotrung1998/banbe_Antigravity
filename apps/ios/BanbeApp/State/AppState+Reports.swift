import SwiftUI
import Photos

// Account extension (2026-09-27, Stage 3) — one SECURITY DEFINER RPC
// (get_account_kpis, migration 097) reused for the on-screen cards, CSV,
// PDF and JSON export alike, so a number here can never disagree with the
// same number in an export — mirrors src/screens/Reports.jsx exactly.

/// A tiny generic-JSON value — `rows` differs in shape per metric (booking
/// rows vs. refund rows vs. event-review rows), so it can't be one fixed
/// Decodable struct the way a real table's columns can.
enum KpiJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([KpiJSONValue])
    case object([String: KpiJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([KpiJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: KpiJSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "✓" : ""
        case .null, .array, .object: return ""
        }
    }
    /// For CSV/JSON export — a plain JSON-ish scalar, not a display string.
    var rawExportValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return ""
        case .array(let a): return a.map { $0.rawExportValue }
        case .object(let o): return o.mapValues { $0.rawExportValue }
        }
    }
}

struct AccountKpiSeriesPoint: Decodable, Identifiable {
    var id: String { d }
    let d: String
    let v: Double
}

struct AccountKpiMetric: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let unit: String
    let value: KpiJSONValue
    let series: [AccountKpiSeriesPoint]?
    let rows: [[String: KpiJSONValue]]?
}

struct AccountKpiRange: Decodable {
    let start: String
    let end: String
}

struct AccountKpiReport: Decodable {
    let success: Bool
    let error: String?
    let scope: String?
    let organizerId: String?
    let range: AccountKpiRange?
    let metrics: [AccountKpiMetric]?
    enum CodingKeys: String, CodingKey {
        case success, error, scope, range, metrics
        case organizerId = "organizer_id"
    }
}

enum ReportsRangeDays: Equatable {
    case days7, days30, days90, custom
    var rpcValue: String {
        switch self {
        case .days7: return "7"
        case .days30: return "30"
        case .days90: return "90"
        case .custom: return "custom"
        }
    }
}

extension AppState {
    // Opening this from Cá nhân/Admin needs no organizer id; opening it
    // from Tổ chức always passes the account's real organizer_id — never
    // guessed (mirrors the prior ticket's own "never silently substitute
    // the first org" rule).
    func openReports(scope: String, organizerID: String? = nil, back: Screen = .profile) {
        reportsScope = scope
        reportsOrganizerId = organizerID ?? ""
        reportsBackScreen = back
        reportsData = nil
        reportsError = ""
        reportsExpanded = []
        screen = .reports
        Task { await fetchAccountKpis(scope: scope, organizerID: organizerID ?? "", rangeDays: reportsRangeDays, customStart: reportsCustomStart, customEnd: reportsCustomEnd) }
    }
    func backFromReports() { screen = reportsBackScreen }

    private struct GetAccountKpisParams: Encodable {
        let pScope: String
        let pStart: String
        let pEnd: String
        let pOrganizerId: String?
        enum CodingKeys: String, CodingKey {
            case pScope = "p_scope", pStart = "p_start", pEnd = "p_end", pOrganizerId = "p_organizer_id"
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func fetchAccountKpis(scope: String, organizerID: String, rangeDays: ReportsRangeDays, customStart: Date, customEnd: Date) async {
        reportsLoading = true
        reportsError = ""
        let now = Date()
        let start: Date
        let end: Date
        switch rangeDays {
        case .custom:
            start = Calendar.current.startOfDay(for: customStart)
            end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd) ?? customEnd
        case .days7: start = now.addingTimeInterval(-7 * 86400); end = now
        case .days30: start = now.addingTimeInterval(-30 * 86400); end = now
        case .days90: start = now.addingTimeInterval(-90 * 86400); end = now
        }
        do {
            let result: AccountKpiReport = try await SupabaseService.client
                .rpc("get_account_kpis", params: GetAccountKpisParams(
                    pScope: scope,
                    pStart: Self.isoFormatter.string(from: start),
                    pEnd: Self.isoFormatter.string(from: end),
                    pOrganizerId: scope == "host" ? organizerID : nil
                ))
                .execute().value
            guard result.success else {
                reportsLoading = false
                reportsError = T("Không thể tải số liệu lúc này. Vui lòng thử lại.", "Couldn't load these numbers right now. Please try again.")
                return
            }
            reportsData = result
            reportsLoading = false
        } catch {
            print("fetchAccountKpis failed:", error)
            reportsLoading = false
            reportsError = T("Không thể tải số liệu lúc này. Vui lòng thử lại.", "Couldn't load these numbers right now. Please try again.")
        }
    }

    /// Reload with whatever scope/organizer/range are ALREADY committed —
    /// safe here (a retry button, not chained right after a `set`) unlike
    /// `openReports`, which must pass its own parameters explicitly.
    func loadAccountKpis() {
        Task { await fetchAccountKpis(scope: reportsScope, organizerID: reportsOrganizerId, rangeDays: reportsRangeDays, customStart: reportsCustomStart, customEnd: reportsCustomEnd) }
    }

    func setReportsRangeDays(_ days: ReportsRangeDays) {
        reportsRangeDays = days
        loadAccountKpis()
    }
    func setReportsCustomRange(start: Date, end: Date) {
        reportsRangeDays = .custom
        reportsCustomStart = start
        reportsCustomEnd = end
        loadAccountKpis()
    }

    func toggleReportCard(_ key: String) {
        if reportsExpanded.contains(key) { reportsExpanded.remove(key) } else { reportsExpanded.insert(key) }
    }
    func expandAllReportCards() { reportsExpanded = Set((reportsData?.metrics ?? []).map(\.key)) }
    func collapseAllReportCards() { reportsExpanded = [] }

    // MARK: - Export

    /// Spreadsheet-injection guard — see GocContext.jsx's `csvCell` for the
    /// full rationale (a hostile event/organizer name starting with
    /// =/+/-/@ could otherwise execute as a formula when opened).
    private func csvCell(_ value: Any) -> String {
        var str: String
        if let b = value as? Bool { str = b ? "true" : "false" }
        else if let d = value as? Double { str = d == d.rounded() ? String(Int(d)) : String(d) }
        else { str = String(describing: value) }
        if let first = str.first, "=+-@\t\r".contains(first) { str = "'" + str }
        if str.contains(",") || str.contains("\"") || str.contains("\n") {
            str = "\"" + str.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return str
    }

    private func writeTempFile(name: String, data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch {
            print("writeTempFile failed:", error)
            return nil
        }
    }

    /// One metric card's own `rows` as a real CSV — UTF-8 with a BOM (so
    /// Excel reads Vietnamese diacritics correctly), one row per underlying
    /// record — sets `reportsExportedFileURL` for a `ShareLink` to present.
    func exportReportCardCsv(_ metricKey: String) {
        guard let metric = reportsData?.metrics?.first(where: { $0.key == metricKey }) else { return }
        let rows = metric.rows ?? []
        var lines: [String] = []
        if let first = rows.first {
            let columns = first.keys.sorted()
            lines.append(columns.joined(separator: ","))
            for row in rows {
                lines.append(columns.map { csvCell(row[$0]?.rawExportValue ?? "") }.joined(separator: ","))
            }
        } else {
            lines.append("value")
            lines.append(csvCell(metric.value.rawExportValue))
        }
        let content = "\u{FEFF}" + lines.joined(separator: "\r\n")
        guard let data = content.data(using: .utf8),
              let url = writeTempFile(name: "banbe-\(metricKey).csv", data: data) else { return }
        reportsExportedFileURL = url
    }

    func exportReportsJson() {
        guard let report = reportsData else { return }
        var metricsJson: [[String: Any]] = []
        for m in report.metrics ?? [] {
            var entry: [String: Any] = [
                "key": m.key, "label": m.label, "unit": m.unit, "value": m.value.rawExportValue,
            ]
            if let series = m.series { entry["series"] = series.map { ["d": $0.d, "v": $0.v] } }
            if let rows = m.rows { entry["rows"] = rows.map { row in row.mapValues { $0.rawExportValue } } }
            metricsJson.append(entry)
        }
        let payload: [String: Any] = [
            "schema_version": 1,
            "role": report.scope ?? reportsScope,
            "range": ["start": report.range?.start ?? "", "end": report.range?.end ?? ""],
            "generated_at": Self.isoFormatter.string(from: Date()),
            "metrics": metricsJson,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let url = writeTempFile(name: "banbe-report-\(report.scope ?? "report").json", data: data) else { return }
        reportsExportedFileURL = url
    }

    /// Native `UIGraphicsPDFRenderer` — no third-party dependency needed on
    /// this platform at all (unlike the web export, which added `jspdf`).
    /// Reuses the SAME fetched `reportsData` — never a second query.
    func exportReportsPdf() {
        guard let report = reportsData else { return }
        reportsExportBusy = "pdf"
        let pageWidth: CGFloat = 595, pageHeight: CGFloat = 842 // A4 @ 72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let roleLabel: String
        switch report.scope {
        case "host": roleLabel = T("Tổ chức", "Host")
        case "admin": roleLabel = T("Quản trị", "Admin")
        default: roleLabel = T("Cá nhân", "Personal")
        }
        let logo = UIImage(named: "banbe-wordmark")
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 40
            if let logo {
                let w: CGFloat = 84
                let h = w * logo.size.height / logo.size.width
                logo.draw(in: CGRect(x: 40, y: y, width: w, height: h))
                y += h + 16
            }
            let title = T("Báo cáo số liệu (\(roleLabel))", "KPI report (\(roleLabel))")
            title.draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 16)])
            y += 26
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy"
            df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
            let rangeText: String
            if let range = report.range, let s = Self.isoFormatter.date(from: range.start), let e = Self.isoFormatter.date(from: range.end) {
                rangeText = "\(T("Khoảng thời gian", "Range")): \(df.string(from: s)) - \(df.string(from: e))"
            } else { rangeText = "" }
            rangeText.draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            y += 16
            "\(T("Tạo lúc", "Generated")): \(df.string(from: Date()))".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10)])
            y += 24
            for metric in report.metrics ?? [] {
                if y > pageHeight - 80 { ctx.beginPage(); y = 40 }
                ReportMetricLabels.label(metric, T).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12)])
                let displayValue = metric.unit == "vnd"
                    ? "\(Int(numberFrom(metric.value)).formattedVnd()) đ"
                    : metric.value.displayString
                displayValue.draw(at: CGPoint(x: 400, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                y += 16
                T("Nguồn: get_account_kpis, dữ liệu thực trên máy chủ", "Source: get_account_kpis, real server data")
                    .draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])
                y += 20
            }
        }
        guard let url = writeTempFile(name: "banbe-report-\(report.scope ?? "report").pdf", data: data) else {
            reportsExportBusy = ""
            return
        }
        reportsExportedFileURL = url
        reportsExportBusy = ""
    }

    private func numberFrom(_ v: KpiJSONValue) -> Double {
        if case .number(let n) = v { return n }
        return 0
    }

    /// "Lưu ảnh" — rasterizes the SAME SwiftUI chart the card is showing
    /// (via `ImageRenderer`, iOS 16+) and saves it to Photos, reusing the
    /// exact save-to-Photos mechanism `downloadChatPhoto()` already
    /// established (AppState+Data.swift) rather than a second one.
    @MainActor
    func saveReportChartImage(_ view: some View) async -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        guard let image = renderer.uiImage else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            return true
        } catch {
            print("saveReportChartImage failed:", error)
            return false
        }
    }
}

private extension Int {
    func formattedVnd() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: self)) ?? String(self)
    }
}

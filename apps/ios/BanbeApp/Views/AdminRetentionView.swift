import SwiftUI

/// Admin › Retention report (migration 196) — the iOS counterpart of src/screens/AdminRetention.jsx. Aggregate
/// numbers only, straight from admin_retention_report: the server checks is_platform_admin(), excludes test accounts
/// and hides every group under 20 people.
struct AdminRetentionView: View {
    @EnvironmentObject private var app: AppState
    @State private var days = RetentionReport.defaultRangeDays
    @State private var report: RetentionReport.Reply?
    @State private var error = ""
    @State private var loading = false

    private func message(_ code: String) -> String {
        switch code {
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền xem báo cáo này.", "You are not allowed to see this report.")
        case "NOT_DEPLOYED": return app.T("Máy chủ chưa có báo cáo này (chạy migration 196).", "The server does not have this report yet (apply migration 196).")
        default: return app.T("Không tải được báo cáo. Thử lại nhé.", "Couldn't load the report. Try again.")
        }
    }

    private func load() async {
        guard app.isAdmin else { return }
        #if DEBUG
        if UITestFixture.isActive { return } // fixtures never reach the server
        #endif
        let range = RetentionReport.range(days: days)
        let requested = days
        loading = true
        error = ""
        defer { if requested == days { loading = false } }
        do {
            let r: RetentionReport.Reply = try await SupabaseService.client
                .rpc("admin_retention_report", params: ["p_from": range.from, "p_to": range.to]).execute().value
            guard requested == days else { return } // a newer range was picked meanwhile
            if r.success == true { report = r } else { report = nil; error = r.error ?? "NETWORK" }
        } catch {
            guard requested == days else { return }
            report = nil
            self.error = RewardsLogic.isFunctionMissing(error) ? "NOT_DEPLOYED" : "NETWORK"
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminRetention.back")
                Text(app.T("Báo cáo quay lại", "Retention report"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("adminRetention.title")
                Text(app.T("Nhóm dưới 20 người được ẩn để bảo vệ quyền riêng tư. Tài khoản thử nghiệm không được tính.",
                           "Groups under 20 people are hidden to protect privacy. Test accounts are excluded."))
                    .font(.system(size: 13.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)
                    .accessibilityIdentifier("adminRetention.privacy")

                HStack(spacing: 6) {
                    ForEach(RetentionReport.rangeDays, id: \.self) { n in rangeChip(n) }
                }
                .padding(.top, 16)

                if let report, let from = report.from, let to = report.to {
                    Text("\(from) → \(to)").font(.system(size: 12)).opacity(0.6).padding(.top, 10)
                        .accessibilityIdentifier("adminRetention.period")
                }
                if loading && report == nil {
                    Text(app.T("Đang tải…", "Loading…")).font(.system(size: 13)).opacity(0.7).padding(.top, 18)
                }
                if !error.isEmpty {
                    Text(message(error)).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 14)
                        .accessibilityIdentifier("adminRetention.error")
                }

                if let report {
                    ForEach(RetentionReport.orderedMarkets(report.markets), id: \.market) { m in marketSection(m) }
                    notificationsSection(report)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 40)
        }
        .task(id: days) { await load() }
    }

    private func rangeChip(_ n: Int) -> some View {
        let selected = days == n
        return Button {
            Haptics.selection()
            days = n
        } label: {
            Text(app.T("\(n) ngày", "\(n) days"))
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(selected ? app.palette.ink : .clear, in: Capsule())
                .foregroundStyle(selected ? app.palette.paper : app.palette.ink)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("adminRetention.range.\(n)")
    }

    private func marketSection(_ m: RetentionReport.Market) -> some View {
        let label = RetentionReport.marketLabel(m.market)
        let rows = RetentionReport.rows(m)
        return VStack(alignment: .leading, spacing: 8) {
            Text(app.T(label.vi, label.en)).font(.system(size: 15, weight: .bold)).padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.key) { i, r in
                    if i > 0 { Divider().overlay(app.palette.rule) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(app.T(r.vi, r.en)).font(.system(size: 13.5)).opacity(0.8)
                        Spacer(minLength: 8)
                        Text(r.value).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("adminRetention.\(m.market).\(r.key)")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 22)
        .accessibilityIdentifier("adminRetention.market.\(m.market)")
    }

    private func notificationsSection(_ report: RetentionReport.Reply) -> some View {
        let kinds = report.notifications ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text(app.T("Thông báo theo loại", "Notifications by kind")).font(.system(size: 15, weight: .bold)).padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(app.T("Loại", "Kind")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(app.T("Đã gửi", "Sent")).frame(width: 52, alignment: .trailing)
                    Text(app.T("Đã đọc", "Read")).frame(width: 52, alignment: .trailing)
                    Text(app.T("Phút đọc (TV)", "Med. min")).frame(width: 64, alignment: .trailing)
                }
                .font(.system(size: 11.5, weight: .semibold)).opacity(0.7)
                .padding(.horizontal, 14).padding(.vertical, 10)
                ForEach(kinds) { n in
                    Divider().overlay(app.palette.rule)
                    HStack(spacing: 8) {
                        Text(n.kind).frame(maxWidth: .infinity, alignment: .leading)
                        Text(RetentionReport.count(n.sent)).frame(width: 52, alignment: .trailing)
                        Text(RetentionReport.count(n.read)).frame(width: 52, alignment: .trailing)
                        Text(RetentionReport.median(n.readMinutesMedian)).frame(width: 64, alignment: .trailing)
                    }
                    .font(.system(size: 13)).monospacedDigit()
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("adminRetention.kind.\(n.kind)")
                }
                if kinds.isEmpty {
                    Divider().overlay(app.palette.rule)
                    Text(app.T("Chưa có loại nào đủ 20 người.", "No kind has reached 20 people yet."))
                        .font(.system(size: 13)).opacity(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(app.T("Phút đọc (TV): số phút trung vị từ lúc gửi tới lúc đọc.", "Med. min: median minutes from sent to read."))
                .font(.system(size: 11.5)).opacity(0.6).padding(.horizontal, 2)
            if let hiddenKinds = report.notificationKindsHidden, hiddenKinds > 0 {
                Text(app.T("\(hiddenKinds) loại dưới 20 người được ẩn.", "\(hiddenKinds) kind(s) under 20 people hidden."))
                    .font(.system(size: 12)).opacity(0.65).padding(.horizontal, 2)
                    .accessibilityIdentifier("adminRetention.kindsHidden")
            }
        }
        .padding(.top, 28)
    }
}

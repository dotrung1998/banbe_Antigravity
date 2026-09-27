import SwiftUI

/// Account IA pass (2026-09-27) — the ONE shared child screen every
/// Account group entry card opens (`app.openAccountGroup(_:)`), keyed by
/// `app.accountGroupKey`. Mirrors web's `src/screens/AccountGroup.jsx`
/// exactly — same six group keys, same relocated rows/testids/routes, so
/// the two platforms can't drift on what a given group actually contains.
/// Never a separate screen per group: six near-identical files/screens
/// for what's really one layout (a title, a back-to-Account link, and a
/// handful of EXISTING rows) would just be repetition, not a real
/// architectural need.
struct AccountGroupView: View {
    @EnvironmentObject var app: AppState

    private var title: String {
        switch app.accountGroupKey {
        case "team": return app.T("Hồ sơ & Team", "Profile & Team")
        case "activity": return app.T("Vé & hoạt động", "Tickets & activity")
        case "payments": return app.T("Thanh toán & giấy tờ", "Payments & documents")
        case "preferences": return app.T("Tùy chỉnh", "Preferences")
        case "hostOps": return app.T("Vận hành & thanh toán tổ chức", "Event operations & payments")
        case "adminReview": return app.T("Duyệt & kiểm duyệt", "Review & moderation")
        default: return ""
        }
    }

    private var titleIcon: String {
        switch app.accountGroupKey {
        case "team": return "person.3"
        case "activity": return "calendar.badge.checkmark"
        case "payments": return "banknote"
        case "preferences": return "slider.horizontal.3"
        case "hostOps": return "checklist"
        case "adminReview": return "exclamationmark.shield"
        default: return "circle"
        }
    }

    private var completedCount: Int {
        app.completedEventsCount
    }

    var body: some View {
        ScreenScaffold {
            LazyVStack(alignment: .leading, spacing: 0) {
                Button { app.goBack() } label: {
                    Text("‹ " + app.T("Tài khoản", "Account"))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.palette.ink)
                .accessibilityIdentifier("accountGroup.back")

                HStack(spacing: 10) {
                    Image(systemName: titleIcon)
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 34, height: 34)
                        .background(ROW_ACCENT_COLORS[app.accountGroupKey ?? ""]?.opacity(0.33) ?? .clear, in: Circle())
                    Text(title).font(BanbeTheme.display(27))
                }
                .padding(.top, 16)

                Group {
                    switch app.accountGroupKey {
                    case "team": teamContent
                    case "activity": activityContent
                    case "payments": paymentsContent
                    case "preferences": preferencesContent
                    case "hostOps": hostOpsContent
                    case "adminReview": adminReviewContent
                    default: EmptyView()
                    }
                }
                .padding(.top, 22)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 60)
        }
        // Safety net (mirrors AccountView's own accountTab role-sync) — a
        // role change while this happens to be open sends it back to
        // Account rather than showing a group its role no longer has.
        .onChange(of: app.organizerMode) { _, on in
            if app.accountGroupKey == "hostOps", !on { app.screen = .profile }
        }
        .onChange(of: app.accountType) { _, type in
            if app.accountGroupKey == "adminReview", type != "admin" { app.screen = .profile }
        }
    }

    @ViewBuilder
    private var teamContent: some View {
        if !app.myOrganizerInvites.isEmpty {
            Text(app.T("Lời mời Team", "Team invites")).font(.system(size: 11.5, weight: .semibold))
            ForEach(app.myOrganizerInvites) { inv in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("\(inv.organizers?.name ?? "Một tổ chức") mời bạn làm \(inv.publicRole)", "\(inv.organizers?.name ?? "An organizer") invited you as \(inv.publicRole)"))
                        .font(.system(size: 13))
                    HStack(spacing: 8) {
                        InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: true) } }
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToOrganizerInvite(membershipID: inv.id, accept: false) } }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("team.invite.\(inv.id)")
            }
        }
        if !app.myTeamMemberships.isEmpty {
            Text(app.T("Đội ngũ của tôi", "My teams")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myTeamMemberships) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.organizers?.name ?? app.T("Một tổ chức", "An organizer")).font(.system(size: 13))
                        Text(m.publicRole).font(.system(size: 11)).opacity(0.65)
                    }
                    Spacer()
                    Button {
                        Task { await app.setOrganizerMemberVisibility(membershipID: m.id, visible: !m.publicVisible) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(app.T("Hiển thị tôi trong Team", "Show me in the Team")).font(.system(size: 10.5))
                            ZStack(alignment: m.publicVisible ? .trailing : .leading) {
                                Capsule().fill(m.publicVisible ? app.palette.ink : app.palette.ink.opacity(0.18)).frame(width: 38, height: 22)
                                Circle().fill(app.palette.paper).frame(width: 17, height: 17).padding(2.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("team.membership.visibility.\(m.id)")
                }
                .foregroundStyle(app.palette.ink)
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
            }
        }
        if app.myOrganizerInvites.isEmpty && app.myTeamMemberships.isEmpty {
            Text(app.T("Chưa có lời mời hay Team nào.", "No invites or teams yet."))
                .font(.system(size: 13)).opacity(0.65)
        }
    }

    @ViewBuilder
    private var activityContent: some View {
        VStack(spacing: 0) {
            row(app.T("Sự kiện đã hoàn thành", "Completed events"), identifier: "account.completedList", icon: "calendar.badge.checkmark", trailing: "\(completedCount) ›") { app.goCompletedList() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        if !app.myEventCredits.isEmpty {
            Text(app.T("Đóng góp sự kiện — lời mời đang chờ", "Event contributions — pending invites")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myEventCredits) { c in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T(
                        "\(c.organizers?.name ?? "Một tổ chức") ghi nhận bạn đã tổ chức \"\(c.events?.name ?? "")\"",
                        "\(c.organizers?.name ?? "An organizer") credited you for organizing \"\(c.events?.name ?? "")\""
                    )).font(.system(size: 13))
                    HStack(spacing: 8) {
                        InkButton(title: app.T("Chấp nhận", "Accept")) { Task { await app.respondToEventCredit(creditID: c.id, accept: true) } }
                        Button(app.T("Từ chối", "Decline")) { Task { await app.respondToEventCredit(creditID: c.id, accept: false) } }
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(app.palette.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(app.palette.rule))
                    }
                }
                .padding(14)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("eventCredit.\(c.id)")
            }
        }
        if !app.myConfirmedEventCredits.isEmpty {
            Text(app.T("Đóng góp sự kiện — đã xác nhận", "Event contributions — confirmed")).font(.system(size: 11.5, weight: .semibold)).padding(.top, 18)
            ForEach(app.myConfirmedEventCredits) { c in
                Button { app.goEvent(c.eventId) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.events?.name ?? app.T("Một sự kiện", "An event")).font(.system(size: 13, weight: .semibold))
                            Text(c.organizers?.name ?? app.T("Một tổ chức", "An organizer")).font(.system(size: 11)).opacity(0.65)
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 18)).opacity(0.5)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                .accessibilityIdentifier("eventCreditConfirmed.\(c.id)")
            }
        }
    }

    @ViewBuilder
    private var paymentsContent: some View {
        VStack(spacing: 0) {
            row(app.T("Hoá đơn", "Invoices"), identifier: "account.invoices", icon: "doc.text", trailing: "›") { app.openDocuments(kind: "invoice", role: "guest") }
            Divider().overlay(app.palette.rule)
            row(app.T("Biên nhận", "Receipts"), identifier: "account.receipts", icon: "receipt", trailing: "›") { app.openDocuments(kind: "receipt", role: "guest") }
            Divider().overlay(app.palette.rule)
            row(app.T("Tài khoản thanh toán & nhận hoàn tiền", "Payment & refund accounts"), identifier: "account.refundAccounts", icon: "banknote", trailing: "›") { app.openRefundAccounts(back: .profile) }
            Divider().overlay(app.palette.rule)
            row(app.T("Hoàn tiền", "Refunds"), identifier: "account.refunds", icon: "checklist", trailing: "›") { app.openMyRefunds(back: .profile) }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var preferencesContent: some View {
        VStack(spacing: 0) {
            row(app.T("Tùy chỉnh ứng dụng", "App preferences"),
                identifier: "account.preferences", icon: "slider.horizontal.3",
                trailing: (app.lang == "en" ? "English" : "Tiếng Việt") + " ▪︎ "
                    + (app.theme == "dark" ? app.T("Tối", "Dark") : app.T("Sáng", "Light"))) {
                app.openPreferences()
            }
            Divider().overlay(app.palette.rule)
            row(app.T("Bảo mật", "Security"), identifier: "account.security", icon: "lock.shield", trailing: "›") { app.openSecurity() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var hostOpsContent: some View {
        VStack(spacing: 0) {
            row(app.T("Chờ xác nhận thanh toán", "Awaiting verification"), identifier: "host.verifications", icon: "checklist", trailing: "›") { app.openVerifications() }
            Divider().overlay(app.palette.rule)
            row(app.T("Nhận thanh toán", "Getting paid"), identifier: "host.payout", icon: "banknote", trailing: "›") { app.openPayout() }
            Divider().overlay(app.palette.rule)
            row(app.T("Hoá đơn đã phát hành", "Invoices issued"), identifier: "host.invoices", icon: "doc.text", trailing: "›") { app.openDocuments(kind: "invoice", role: "host") }
            Divider().overlay(app.palette.rule)
            row(app.T("Biên nhận đã phát hành", "Receipts issued"), identifier: "host.receipts", icon: "receipt", trailing: "›") { app.openDocuments(kind: "receipt", role: "host") }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // NOTE: iOS's own pre-existing admin rows differ from web's here —
    // web has a dedicated "Tranh chấp thanh toán"/"Payment disputes" row
    // (`openDisputes`); iOS's `adminSection` (before this pass) only ever
    // had "Bảng quản trị"/"Admin Panel" (`openAdminDashboard`) and "Sự
    // kiện chờ duyệt"/"Pending events" (`openAdminEvents`) — a real,
    // pre-existing platform divergence, not something this pass invents
    // or silently papers over by inventing an `openDisputes` call iOS
    // never had. Kept EXACTLY as iOS already had it; reconciling the two
    // platforms' admin surface is a separate, out-of-scope task.
    @ViewBuilder
    private var adminReviewContent: some View {
        VStack(spacing: 0) {
            row(app.T("Bảng quản trị", "Admin Panel"), identifier: "admin.panel", icon: "exclamationmark.shield", trailing: "›") { app.openAdminDashboard() }
            Divider().overlay(app.palette.rule)
            row(app.T("Sự kiện chờ duyệt", "Pending events"), identifier: "admin.events", icon: "exclamationmark.shield", trailing: "›") { app.openAdminEvents() }
        }
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, identifier: String? = nil, icon: String, trailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22, height: 22)
                    .opacity(0.72)
                Text(title).font(.system(size: 14))
                Spacer()
                Text(trailing).font(.system(size: 13))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

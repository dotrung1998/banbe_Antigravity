import SwiftUI

/// Quick settings from the Home avatar (web twin: src/components/home/QuickSheetV5.jsx, commits 8f78ead, 24a1d6f,
/// 0dd20de). Profile link, Hosting mode switch, Personal/Host/Admin tabs with four shortcuts each, Appearance and
/// Language segments, Notifications (opens Notification preferences) and Sign out. Guests get the sign-in card and
/// the two segments.
///
/// Presented by the Home header as a native sheet (contained in the device, never over the dock):
///     .sheet(isPresented: $quickSheetOpen) { QuickSheetView(onClose: { quickSheetOpen = false }) }
struct QuickSheetView: View {
    @EnvironmentObject private var app: AppState
    let onClose: () -> Void

    @State private var tabSel: String?
    @State private var prefsOpen = false
    @State private var contentHeight: CGFloat = 0

    /// Bottom safe-area inset as the sheet's OWN content sees it. A `.height` detent is the whole sheet frame and the
    /// content only lays out above this inset, so detent = measured content + this. Reading the window's inset (34pt)
    /// double counted: on iOS 26 the sheet floats above the home indicator and reports a much smaller inset inside.
    @State private var sheetSafeBottom: CGFloat = 0

    // MARK: Derived

    private var name: String {
        guard let u = app.user else { return "" }
        let n = u.displayName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? app.T("Bạn", "You") : n
    }
    /// The same Hosting mode switch as Account (organizer mode itself, not the Home view), so the switch and the
    /// Host tab can never disagree.
    private var hostOn: Bool { app.organizerMode }
    private var tabs: [String] {
        app.user == nil ? [] : AccountTabs.tabs(isAdmin: app.isAdmin, hostMode: hostOn && app.canHost)
    }
    private var tab: String { AccountTabs.resolve(tabSel ?? app.accountTab, tabs: tabs) }

    private struct Shortcut: Identifiable {
        let id: String
        let icon: String
        let label: String
        var badge: Int = 0
        let action: () -> Void
    }

    private func go(_ fn: @escaping () -> Void) -> () -> Void { { onClose(); fn() } }
    private func openGroup(_ key: String) {
        app.accountGroupParentKey = nil
        app.accountGroupReturnsHome = false
        app.accountTab = tab   // Back from the group lands on Account on the tab the shortcut came from
        app.accountGroupKey = key
        app.screen = .accountGroup
    }
    /// Help & guides, with Back returning to Home (this sheet's origin).
    private func openHelp() {
        app.accountGroupParentKey = nil
        app.accountTab = "personal"
        app.accountGroupKey = "helpLegal"
        app.accountGroupReturnsHome = true
        app.screen = .accountGroup
    }
    private func toAccount(_ key: String) {
        app.accountTab = key
        app.screen = .profile
    }

    private var shortcuts: [Shortcut] {
        switch tab {
        case "host":
            return [
                Shortcut(id: "create", icon: "plus", label: app.T("Tạo", "Create")) { app.goCreate() },
                Shortcut(id: "events", icon: "calendar.badge.checkmark", label: app.T("Sự kiện", "Events")) { app.goDashboard(back: .home) },
                Shortcut(id: "paid", icon: "banknote", label: app.T("Nhận tiền", "Get paid")) { openGroup("hostOps") },
                Shortcut(id: "settings", icon: "slider.horizontal.3", label: app.T("Cài đặt", "Settings")) { toAccount("host") },
            ]
        case "admin":
            return [
                Shortcut(id: "review", icon: "checkmark.shield", label: app.T("Duyệt", "Review")) { openGroup("adminReview") },
                Shortcut(id: "events", icon: "calendar.badge.checkmark", label: app.T("Sự kiện", "Events")) { app.openAdminEvents() },
                Shortcut(id: "switches", icon: "slider.horizontal.3", label: app.T("Công tắc", "Switches")) { app.screen = .adminFeatures },
                Shortcut(id: "console", icon: "shield", label: app.T("Bảng quản trị", "Console")) { toAccount("admin") },
            ]
        default:
            return [
                Shortcut(id: "tickets", icon: "ticket", label: app.T("Vé", "Tickets"),
                         badge: AccountBadges.myTicketsActionCount(paymentBookings: app.paymentBookings)) { openGroup("activity") },
                Shortcut(id: "wallet", icon: "creditcard", label: app.T("Ví", "Wallet")) { openGroup("payments") },
                Shortcut(id: "saved", icon: "bookmark", label: app.T("Đã lưu", "Saved")) { app.goSavedList(back: .home) },
                Shortcut(id: "help", icon: "questionmark.circle", label: app.T("Trợ giúp", "Help")) { openHelp() },
            ]
        }
    }

    private func tabLabel(_ k: String) -> String {
        switch k {
        case "host": return app.T("Tổ chức", "Host")
        case "admin": return app.T("Quản trị", "Admin")
        default: return app.T("Cá nhân", "Personal")
        }
    }

    /// "All on" / "N of 3 on" for the three Notification preferences groups (tickets, payments, events). A group is
    /// on while none of its kinds is muted. Disputes and the weekly digest are not part of any group.
    private var prefsSummary: String {
        func group(_ kind: String) -> Int? {
            if kind == "weekly_digest" { return nil }
            if kind.hasPrefix("hold_") { return 0 }
            switch notificationCategory(kind) {
            case "booking": return 0
            case "payment", "refund": return 1
            case "event", "reminder", "team": return 2
            case "message": return kind == "event_announcement" ? 2 : nil
            default: return nil
            }
        }
        let off = Set(app.mutedNotificationKinds.compactMap(group))
        let on = 3 - off.count
        if on == 3 { return app.T("Đang bật hết", "All on") }
        if on == 0 { return app.T("Đang tắt hết", "All off") }
        return app.T("Bật \(on)/3", "\(on) of 3 on")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if app.user != nil { signedInTop } else { guestCard }
                VStack(spacing: 0) {
                    settingRow(icon: "sun.max", title: app.T("Giao diện", "Appearance")) {
                        segments([(app.T("Sáng", "Light"), !app.isDark, "quick.theme.light", { app.pickTheme("light") }),
                                  (app.T("Tối", "Dark"), app.isDark, "quick.theme.dark", { app.pickTheme("dark") })])
                    }
                    settingRow(icon: "globe", title: app.T("Ngôn ngữ", "Language")) {
                        segments([("VI", !app.isEN, "quick.lang.vi", { if app.isEN { app.toggleLang() } }),
                                  ("EN", app.isEN, "quick.lang.en", { if !app.isEN { app.toggleLang() } })])
                    }
                    if app.user != nil {
                        Button { prefsOpen = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "bell").font(.app(size: 20, weight: .light)).frame(width: 26)
                                Text(app.T("Tùy chọn thông báo", "Notification preferences")).font(.app(size: 15))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 8)
                                Text(prefsSummary).font(.app(size: 13)).foregroundStyle(app.palette.ink2)
                                Image(systemName: "chevron.right").font(.app(size: 12, weight: .semibold)).foregroundStyle(app.palette.ink3)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quick.notifications")
                        Divider().overlay(app.palette.divider)
                    }
                }
                .padding(.horizontal, 20)
                if app.user != nil {
                    Button { onClose(); Task { await app.signOut() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right").font(.app(size: 15))
                            Text(app.T("Đăng xuất", "Sign out")).font(.app(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(BanbeTheme.alert)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Capsule().stroke(BanbeTheme.alert, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 22)
                    .accessibilityIdentifier("quick.signOut")
                }
            }
            .padding(.top, 20).padding(.bottom, 16)
            .foregroundStyle(app.palette.ink)
            .background(GeometryReader { g in
                Color.clear.onAppear { contentHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in contentHeight = h }
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(GeometryReader { g in
            Color.clear.onAppear { sheetSafeBottom = g.safeAreaInsets.bottom }
                .onChange(of: g.safeAreaInsets.bottom) { _, b in sheetSafeBottom = b }
        })
        .background(app.palette.paper.ignoresSafeArea())
        // Hugs its content (web twin: a bottom sheet sized to its content); .large stays available for huge text.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + sheetSafeBottom), .large] : [.large])
        .hidesDock("quickSheet")
        .presentationDragIndicator(.visible)
        .onChange(of: app.hostSetupOpen) { _, open in if open { onClose() } }
        .sheet(isPresented: $prefsOpen) {
            // Owned by the Notification preferences screen (Views/NotificationPrefsView.swift).
            NotificationPrefsView(style: .sheet)
        }
        .accessibilityIdentifier("home.quickSheet")
    }

    // MARK: Pieces

    private var signedInTop: some View {
        VStack(spacing: 0) {
            Button { onClose(); app.goProfile() } label: {
                HStack(spacing: 16) {
                    AccountAvatarView(size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(BanbeTheme.display(20)).lineLimit(1)
                        Text(app.T("Tài khoản", "Account") + " ›").font(.app(size: 13))
                            .overlay(alignment: .bottom) { Rectangle().fill(app.palette.rule).frame(height: 1) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quick.account")

            // Hosting mode: the same switch as Account.
            VStack(alignment: .leading, spacing: 8) {
                HostingModeCard(isOn: hostOn, busy: app.organizerModeBusy, identifier: "quick.hostSwitch") {
                    if !hostOn { tabSel = "host" }
                    app.toggleOrganizerMode()
                }
                if !app.organizerModeError.isEmpty {
                    Text(app.organizerModeError).font(.app(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 18)

            if !tabs.isEmpty {
                HStack(spacing: 2) {
                    ForEach(tabs, id: \.self) { k in
                        let on = tab == k
                        Button { tabSel = k } label: {
                            Text(tabLabel(k)).font(.app(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(on ? app.palette.paper : app.palette.ink2)
                                .background(on ? app.palette.ink : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("quick.tab.\(k)")
                    }
                }
                .padding(2).background(app.palette.block, in: Capsule())
                .padding(.horizontal, 20).padding(.top, 12)
            }

            HStack(spacing: 0) {
                ForEach(shortcuts) { s in
                    Button(action: go(s.action)) {
                        VStack(spacing: 8) {
                            Image(systemName: s.icon).font(.app(size: 22, weight: .light)).frame(height: 26)
                            Text(s.label).font(.app(size: 12)).foregroundStyle(app.palette.ink2)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 12)
                        .overlay(alignment: .topTrailing) {
                            if s.badge > 0 {
                                Text("\(s.badge)").font(.app(size: 10, weight: .bold)).foregroundStyle(BanbeTheme.onAlert)
                                    .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                                    .background(BanbeTheme.alert, in: Capsule())
                                    .padding(.top, 8).padding(.trailing, 14)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("quick.shortcut.\(s.id)")
                }
            }
            .overlay(alignment: .top) { Divider().overlay(app.palette.divider) }
            .overlay(alignment: .bottom) { Divider().overlay(app.palette.divider) }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
        }
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.T("Bạn đang xem với tư cách khách", "You're browsing as a guest")).font(BanbeTheme.display(20))
            Text(app.T("Đăng nhập để đặt chỗ, lưu sự kiện và nhắn tin cho host.", "Log in to reserve, save and message hosts."))
                .font(.app(size: 14)).foregroundStyle(app.palette.ink2)
            Button { onClose(); app.goLogin() } label: {
                Text(app.T("Đăng nhập", "Log in")).font(.app(size: 15, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(app.palette.ink, in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 8)
            .accessibilityIdentifier("quick.login")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.palette.block, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func settingRow<Content: View>(icon: String, title: String, @ViewBuilder trailing: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.app(size: 20, weight: .light)).frame(width: 26)
                Text(title).font(.app(size: 15))
                Spacer(minLength: 8)
                trailing()
            }
            .frame(minHeight: 56)
            Divider().overlay(app.palette.divider)
        }
    }

    private func segments(_ items: [(String, Bool, String, () -> Void)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                Button(action: it.3) {
                    Text(it.0).font(.app(size: 12, weight: it.1 ? .semibold : .regular))
                        .padding(.horizontal, 11).frame(height: 30)
                        .foregroundStyle(it.1 ? app.palette.paper : app.palette.ink2)
                        .background(it.1 ? app.palette.ink : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(it.1 ? .isSelected : [])
                .accessibilityIdentifier(it.2)
            }
        }
        .padding(2).background(app.palette.block, in: Capsule())
    }
}

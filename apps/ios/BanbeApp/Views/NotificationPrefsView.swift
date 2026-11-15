import SwiftUI

/// Notification preferences (web: src/screens/NotificationPrefs.jsx): one switch per group of notification kinds,
/// saved as the existing profiles.muted_notification_kinds list (Lib/NotificationPrefs.swift). "News from banbe" is
/// the weekly digest opt-in (promotional, off by default, only while the `weekly_digest` switch is on). "New
/// messages" is always on. Two presentations of the same content: a page (`.notifPrefs` screen, from Account) and a content-hugging sheet (Home quick panel).
struct NotificationPrefsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error = ""
    /// nil = not loaded yet.
    @State private var digest: Bool?

    enum Style { case page, sheet }
    /// `.page`: the Account screen (Back link, dock like other Account sub-screens). `.sheet`: the Home quick panel
    /// (drag indicator, Done, detent hugging the content, dock hidden).
    var style: Style = .page

    @State private var contentHeight: CGFloat = 0
    @State private var sheetSafeBottom: CGFloat = 0

    private var title: String { app.T("Tùy chọn thông báo", "Notification preferences") }

    var body: some View {
        switch style {
        case .page:
            ScreenScaffold {
                VStack(alignment: .leading, spacing: 0) {
                    BackLink(label: app.backLabel(for: app.backTargetScreen)) { app.goBack() }
                    Text(title)
                        .font(BanbeTheme.display(27))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 16)
                    rows
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .padding(.bottom, 42)
            }
            .accessibilityIdentifier("notifPrefs.screen")
            .task(id: loadKey) { await loadDigest() }
        case .sheet:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(title)
                            .font(.app(size: 24, weight: .light))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Button(app.T("Xong", "Done")) { dismiss() }
                            .font(.app(size: 15, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("notifPrefs.done")
                    }
                    rows
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 24)
                .padding(.top, 24).padding(.bottom, 20)
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
            .presentationDetents(contentHeight > 0 ? [.height(contentHeight + sheetSafeBottom), .large] : [.height(460), .large])
            .presentationDragIndicator(.visible)
            .hidesDock("notifPrefsSheet")
            .accessibilityIdentifier("notifPrefs.screen")
            .task(id: loadKey) { await loadDigest() }
        }
    }

    private var loadKey: String { "\(app.userID?.uuidString ?? "")-\(app.weeklyDigestEnabled)" }

    private func loadDigest() async {
        digest = nil
        guard app.weeklyDigestEnabled, app.isSignedIn else { return }
        let prefs = await app.fetchNotificationPreferences()
        digest = prefs?.digestOptIn ?? false
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(NotificationPrefs.groups) { g in
                    let on = NotificationPrefs.isOn(app.mutedNotificationKinds, g)
                    switchRow(title: app.T(g.titleVi, g.titleEn), sub: app.T(g.subVi, g.subEn), on: on,
                              enabled: !saving, identifier: "notifPrefs.\(g.key)") { Task { await toggle(g) } }
                    divider
                }
                if app.weeklyDigestEnabled {
                    switchRow(title: app.T("Tin từ banbe", "News from banbe"),
                              sub: app.T("Bản tin cuối tuần, tối thứ Năm. Tắt trừ khi bạn bật.",
                                         "This weekend's events, Thursday evening. Off unless you turn it on."),
                              on: digest ?? false, enabled: digest != nil && !saving,
                              identifier: "notifPrefs.news") { Task { await toggleDigest() } }
                        .opacity(digest == nil ? 0.6 : 1)
                    divider
                }
                switchRow(title: app.T("Tin nhắn mới", "New messages"),
                          sub: app.T("Thông báo đẩy và chấm chưa đọc trong Tin nhắn. Không lặp lại trong Thông báo.",
                                     "Push alert and an unread dot in Messages. Never repeated in Notifications."),
                          on: true, enabled: false, identifier: "notifPrefs.messages") {}
                    .opacity(0.6)
            }
            .padding(.top, 12)

            Text(app.T("Thông báo về tranh chấp luôn được gửi.", "Dispute updates always reach you."))
                .font(.app(size: 12.5)).foregroundStyle(app.palette.ink3)
                .padding(.top, 12)
            if !error.isEmpty {
                Text(error).font(.app(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 8)
                    .accessibilityIdentifier("notifPrefs.error")
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(app.palette.divider).frame(height: 1 / UIScreen.main.scale)
    }

    private func switchRow(title: String, sub: String, on: Bool, enabled: Bool, identifier: String,
                           action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(size: 15))
                Text(sub).font(.app(size: 12.5)).foregroundStyle(app.palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { on }, set: { next in if next != on { action() } }))
                .labelsHidden()
                .toggleStyle(BanbeLiquidToggleStyle())
                .disabled(!enabled)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(sub)")
        .accessibilityValue(on ? app.T("Bật", "On") : app.T("Tắt", "Off"))
        .accessibilityIdentifier(identifier)
    }

    private var failedCopy: String { app.T("Không lưu được. Thử lại nhé.", "Couldn't save. Try again.") }

    private func toggle(_ group: NotificationPrefs.Group) async {
        guard let uid = app.userID, !saving else { return }
        let previous = app.mutedNotificationKinds
        let next = NotificationPrefs.toggled(previous, group)
        let muting = next.count > previous.count
        saving = true; error = ""
        // Muting hides what is already in the feed (as "mute this kind" does); unmuting reloads it.
        app.mutedNotificationKinds = next
        if muting { app.notifications.removeAll { next.contains($0.kind) } }
        var failed = false
        do {
            try await SupabaseService.client.from("profiles")
                .update(MutedKindsUpdate(mutedNotificationKinds: next))
                .eq("id", value: uid)
                .execute()
        } catch {
            print("Failed to save muted_notification_kinds:", error)
            failed = true
        }
        saving = false
        if failed { app.mutedNotificationKinds = previous; error = failedCopy }
        if failed ? muting : !muting { await app.loadNotifications() }
    }

    private func toggleDigest() async {
        guard let current = digest, !saving else { return }
        let want = !current
        saving = true; error = ""; digest = want
        let code = await app.setNotificationConsent("set_my_digest_opt_in", enabled: want)
        saving = false
        if code != nil { digest = current; error = failedCopy }
    }
}

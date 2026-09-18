import SwiftUI

/// Port of src/screens/Inbox.jsx — every conversation this account is in,
/// on either side (as guest, and as organizer of their own events).
struct InboxView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.T("Tin nhắn", "Messages")).font(BanbeTheme.display(27))
                    Spacer()
                    Button(app.T("Xong", "Done")) { app.backFromInbox() }
                        .font(.system(size: 12)).buttonStyle(.plain)
                }
                .padding(.bottom, 14)

                if app.inboxThreads.isEmpty {
                    Text(app.T(
                        "Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.",
                        "No conversations yet. Message an organizer from an event page."
                    ))
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 80)
                } else {
                    ForEach(app.inboxThreads) { thread in
                        Button { app.openThread(id: thread.id, eventKey: thread.eventKey, back: .inbox) } label: {
                            HStack(spacing: 16) {
                                CatalogPhoto(path: thread.img, height: 56, width: 56, cornerRadius: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(thread.name).font(BanbeTheme.display(18))
                                    Text(thread.snippet).font(.system(size: 13)).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(app.palette.rule)
                    }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .task { await app.loadInboxThreads() }
    }
}

/// Port of src/screens/Chat.jsx — the real threads/messages conversation,
/// polled every few seconds while open (there's no realtime subscription on
/// the web side either).
struct ChatView: View {
    @EnvironmentObject var app: AppState
    @State private var pollTask: Task<Void, Never>?

    private var event: CatalogEvent { app.currentEvent }

    var body: some View {
        ZStack {
            app.palette.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(app.palette.rule)
                messages
                composer
            }
        }
        .onAppear {
            pollTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if let id = app.chatThreadID { await app.loadChatMessages(id) }
                }
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Button("‹ " + (app.chatBack == .inbox ? app.T("Tin nhắn", "Messages") : app.chatBack == .notifications ? app.T("Thông báo", "Notifications") : event.orgName)) {
                    app.chatBackAction()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                Text(event.hostShort).font(BanbeTheme.display(18))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(app.T("Trả lời trong ngày", "Replies within a day")).font(.system(size: 10.5))
                Text(app.userEmail ?? "").font(.system(size: 10))
            }
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if app.chatMessages.isEmpty {
                        bubble(text: event.greeting, mine: false, messageID: nil)
                    }
                    ForEach(app.chatMessages) { message in
                        bubble(text: message.body, mine: message.senderId == app.userID, messageID: message.id)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .onChange(of: app.chatMessages.count) {
                if let last = app.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(text: String, mine: Bool, messageID: UUID?) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            // Own messages only — messageID is nil for the static greeting
            // placeholder, and a system note is never `mine` (senderId nil
            // can't equal app.userID), so neither ever gets this.
            if mine, let messageID {
                Button {
                    Task { await app.deleteMessage(messageID) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.message.delete")
            }
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(mine ? app.palette.paper : app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    mine ? app.palette.ink : app.palette.paper,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(mine ? .clear : app.palette.rule, lineWidth: 1)
                )
            if !mine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(app.palette.rule)
            HStack(spacing: 8) {
                TextField(
                    app.chatThreadID != nil
                        ? app.T("Viết cho \(event.hostShort)…", "Message \(event.hostShort)…")
                        : app.T("Đang mở cuộc trò chuyện…", "Opening conversation…"),
                    text: $app.chatDraft
                )
                .font(.system(size: 13.5))
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(app.palette.field, in: Capsule())
                .disabled(app.chatThreadID == nil)
                .onSubmit { Task { await app.chatSend() } }

                Button(app.T("Gửi", "Send")) { Task { await app.chatSend() } }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(app.palette.paper)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(app.palette.ink, in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(app.chatThreadID == nil)
                    .opacity(app.chatThreadID == nil ? 0.5 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}

/// Redesigned to read like Instagram/Facebook's own notification list
/// (07-notifications.md's 2026-09-18 follow-up): a left avatar per row
/// (derived per-kind — see avatarSource(for:maps:accountType:)), a bold
/// title + single-line truncated preview, and time-based sections with
/// unread always pinned to the top regardless of age. Same fonts/colors as
/// everywhere else in the app (BanbeTheme/app.palette) — no new design system.
private let notificationCollapseAt = 20

struct NotificationsView: View {
    @EnvironmentObject var app: AppState
    // Which sections have had their "Xem thêm" tapped — purely a
    // render-time slice of already-loaded data (loadNotifications() fetches
    // up to 50 at once), so a plain local Set is enough; nothing here needs
    // a new query.
    @State private var expandedSections: Set<String> = []
    // BUG 4: the "•••" action menu, open for at most one row's
    // notification at a time.
    @State private var menuFor: AppNotification?
    // 2026-09-18 follow-up (BUG 3): a notification's SECTION is decided
    // once — the first time this screen sees it — and frozen from then on,
    // keyed by id. Reading it only flips its own readAt (handled live in
    // row(_:), for the bold/dim weight), it never moves the row to a
    // different section. Without this, section membership was recomputed
    // from live readAt on every body re-render — app.notifications is also
    // overwritten wholesale every 5s by the app-wide toast poll
    // (startNotificationPolling(), AppState+Data.swift), so a plain
    // computed property re-shuffled a notification the instant either
    // markNotificationRead() OR that unrelated poll tick re-rendered this
    // screen — which is what "reading moves it" actually was.
    @State private var sectionMembership: [UUID: String] = [:]

    private struct NotificationSection: Identifiable {
        let id: String
        let title: String
        let items: [AppNotification]
    }

    private func classifyAtLoad(_ n: AppNotification, now: Date) -> String {
        guard n.readAt == nil else {
            switch notificationAgeBucket(n.createdAt, now: now) {
            case .today: return "today"
            case .week: return "week"
            case .older: return "older"
            }
        }
        return "new"
    }

    /// Assigns a section to any notification not already in
    /// `sectionMembership` — called on load and whenever `app.notifications`
    /// changes, but never touches an id that's already been assigned.
    private func syncSectionMembership() {
        let now = Date()
        for n in app.notifications where sectionMembership[n.id] == nil {
            sectionMembership[n.id] = classifyAtLoad(n, now: now)
        }
    }

    // Exactly one bucket per key, regardless of how many unread items are
    // interleaved with read ones in app.notifications — grouping by a
    // frozen, pre-computed membership id can never split "Mới" into two
    // blocks the way a live re-scan keyed on readAt (recomputed mid-list)
    // could.
    private var sections: [NotificationSection] {
        var grouped: [String: [AppNotification]] = ["new": [], "today": [], "week": [], "older": []]
        let now = Date()
        for n in app.notifications {
            let key = sectionMembership[n.id] ?? classifyAtLoad(n, now: now)
            grouped[key, default: []].append(n)
        }
        return [
            NotificationSection(id: "new", title: app.T("Mới", "New"), items: grouped["new"] ?? []),
            NotificationSection(id: "today", title: app.T("Hôm nay", "Today"), items: grouped["today"] ?? []),
            NotificationSection(id: "week", title: app.T("7 ngày qua", "Last 7 days"), items: grouped["week"] ?? []),
            NotificationSection(id: "older", title: app.T("Cũ hơn", "Older"), items: grouped["older"] ?? []),
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
        ZStack {
            ScreenScaffold {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(app.T("Thông báo", "Notifications")).font(BanbeTheme.display(27))
                        Spacer()
                        Button(app.T("Xong", "Done")) { app.goHome() }
                            .font(.system(size: 12)).buttonStyle(.plain)
                    }
                    .padding(.bottom, 14)

                    let allSections = sections
                    if allSections.isEmpty {
                        Text(app.T("Chưa có thông báo nào.", "No notifications yet."))
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                    } else {
                        ForEach(allSections) { sec in
                            section(sec)
                        }
                    }
                }
                .foregroundStyle(app.palette.ink)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .task {
                await app.loadNotifications()
                syncSectionMembership()
            }
            .onChange(of: app.notifications) { _, _ in syncSectionMembership() }

            // BUG 4: replaces the old per-row "×" delete with a "•••" menu,
            // modeled on Facebook's own notification action sheet — but
            // only the actions this app can actually back for real (no
            // "Show more"/"Show less": nothing ranks or personalizes this
            // list; no "Report issue": no generic issue-report mechanism
            // exists anywhere else in the app to call into — see
            // 07-notifications.md). Reuses BottomSheet, the same
            // dim-overlay + sliding-panel component ReasonSheetView already
            // uses, rather than inventing a new dropdown/floating-menu.
            if let n = menuFor {
                BottomSheet(onDismiss: { menuFor = nil }) {
                    menuRow(n.readAt != nil ? app.T("Đánh dấu chưa đọc", "Mark as unread") : app.T("Đánh dấu đã đọc", "Mark as read")) {
                        Task {
                            if n.readAt != nil { await app.markNotificationUnread(n) } else { await app.markNotificationRead(n) }
                        }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.toggleRead")
                    Divider().overlay(app.palette.rule)
                    menuRow(app.T("Tắt loại thông báo này", "Turn off this kind of notification")) {
                        Task { await app.muteNotificationKind(n.kind) }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.mute")
                    Divider().overlay(app.palette.rule)
                    menuRow(app.T("Xoá thông báo này", "Delete this notification"), destructive: true) {
                        Task { await app.deleteNotification(n) }
                        menuFor = nil
                    }
                    .accessibilityIdentifier("notification.menu.delete")
                }
            }
        }
    }

    private func menuRow(_ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14.5))
                .foregroundStyle(destructive ? BanbeTheme.alert : app.palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func section(_ sec: NotificationSection) -> some View {
        let expanded = expandedSections.contains(sec.id)
        let visible = expanded ? sec.items : Array(sec.items.prefix(notificationCollapseAt))
        let hiddenCount = sec.items.count - visible.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(sec.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(app.palette.ink.opacity(0.6))
            ForEach(visible) { item in
                // Live readAt, not the (frozen) section — marking a
                // notification read only changes its weight/dimming in
                // place, per BUG 3, never which section it's in.
                row(item, unread: item.readAt == nil)
                Divider().overlay(app.palette.rule)
            }
            if hiddenCount > 0 {
                Button(app.T("Xem thêm (\(hiddenCount))", "View more (\(hiddenCount))")) {
                    expandedSections.insert(sec.id)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(app.palette.ink.opacity(0.65))
                .buttonStyle(.plain)
                .padding(.vertical, 12)
                .accessibilityIdentifier("notifications.more.\(sec.id)")
            }
        }
        .padding(.bottom, 22)
    }

    private func row(_ item: AppNotification, unread: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { app.openNotification(item) } label: {
                HStack(alignment: .top, spacing: 10) {
                    avatar(for: item)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            // BUG 3: bold only while unread — reading a
                            // notification unbolds it in place (fontWeight
                            // only), it never moves sections.
                            Text(item.title)
                                .font(BanbeTheme.display(15))
                                .fontWeight(unread ? .bold : .regular)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Text(app.trStatus(EventLabels.ago(hoursAgo(item.createdAt))))
                                .font(.system(size: 11))
                        }
                        // Instagram's own "bold actor/action + secondary
                        // preview" shape — one truncated line, not the old
                        // full-body wrap.
                        Text(item.body)
                            .font(.system(size: 13))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // BUG 4: "•••" opens the action menu (delete / toggle read /
            // mute this kind) instead of deleting directly.
            Button {
                menuFor = item
            } label: {
                Text("•••")
                    .font(.system(size: 15))
                    .foregroundStyle(app.palette.ink.opacity(0.4))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification-menu")
        }
        .opacity(unread ? 1 : 0.6)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func avatar(for item: AppNotification) -> some View {
        switch avatarSource(for: item, maps: app.notificationAvatarMaps, accountType: app.accountType) {
        case .image(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        case .catalogPhoto(let path):
            CatalogPhoto(path: path, height: 40, width: 40, cornerRadius: 20)
        case .fallback:
            avatarFallback
        }
    }

    // A plain colored circle with the app's own bell mark — never a broken
    // image. Used whenever avatarSource(for:maps:accountType:) can't
    // resolve an event photo or a guest avatar (neither exists, or the
    // notification kind has no specific actor at all, e.g. referral_joined).
    private var avatarFallback: some View {
        Circle()
            .fill(app.palette.ink.opacity(0.08))
            .frame(width: 40, height: 40)
            .overlay(Text("🔔").font(.system(size: 16)))
    }

    private func hoursAgo(_ date: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(date) / 3600))
    }
}

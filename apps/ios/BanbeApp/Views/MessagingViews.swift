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

    private struct NotificationSection: Identifiable {
        let id: String
        let title: String
        let items: [AppNotification]
        let unread: Bool
    }

    private var sections: [NotificationSection] {
        let unread = app.notifications.filter { $0.readAt == nil }
        // Instagram/Facebook's own convention: unread sits in its own
        // section on top regardless of age — a week-old unread notification
        // still belongs in "Mới", not "Cũ hơn". Everything else buckets by age.
        var today: [AppNotification] = [], week: [AppNotification] = [], older: [AppNotification] = []
        let now = Date()
        for n in app.notifications where n.readAt != nil {
            switch notificationAgeBucket(n.createdAt, now: now) {
            case .today: today.append(n)
            case .week: week.append(n)
            case .older: older.append(n)
            }
        }
        return [
            NotificationSection(id: "new", title: app.T("Mới", "New"), items: unread, unread: true),
            NotificationSection(id: "today", title: app.T("Hôm nay", "Today"), items: today, unread: false),
            NotificationSection(id: "week", title: app.T("7 ngày qua", "Last 7 days"), items: week, unread: false),
            NotificationSection(id: "older", title: app.T("Cũ hơn", "Older"), items: older, unread: false),
        ].filter { !$0.items.isEmpty }
    }

    var body: some View {
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
        .task { await app.loadNotifications() }
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
                row(item, unread: sec.unread)
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
                            Text(item.title)
                                .font(BanbeTheme.display(15))
                                .fontWeight(.bold)
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

            // A real, permanent delete (notifications_delete_own
            // RLS, migration 050) — not audit-sensitive the way
            // dispute_messages is, so no confirm dialog either.
            Button {
                Task { await app.deleteNotification(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.4))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification-delete")
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

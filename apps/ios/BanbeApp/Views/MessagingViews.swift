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
                    Button(app.T("Xong", "Done")) { app.goHome() }
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
                Button("‹ " + (app.chatBack == .inbox ? app.T("Tin nhắn", "Messages") : event.orgName)) {
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
                        bubble(text: event.greeting, mine: false)
                    }
                    ForEach(app.chatMessages) { message in
                        bubble(text: message.body, mine: message.senderId == app.userID)
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

    private func bubble(text: String, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
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

/// Port of src/screens/Notifications.jsx — unread and read split into their
/// own sections; tapping one marks it read and opens whatever it points at.
struct NotificationsView: View {
    @EnvironmentObject var app: AppState

    private var unread: [AppNotification] { app.notifications.filter { $0.readAt == nil } }
    private var read: [AppNotification] { app.notifications.filter { $0.readAt != nil } }

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

                if app.notifications.isEmpty {
                    Text(app.T("Chưa có thông báo nào.", "No notifications yet."))
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                } else {
                    if !unread.isEmpty { section(app.T("Chưa đọc", "Unread"), items: unread, unread: true) }
                    if !read.isEmpty { section(app.T("Đã đọc", "Read"), items: read, unread: false) }
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .task { await app.loadNotifications() }
    }

    private func section(_ title: String, items: [AppNotification], unread: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(app.palette.ink.opacity(0.6))
            ForEach(items) { item in
                Button { app.openNotification(item) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(unread ? app.palette.ink : .clear)
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(BanbeTheme.display(16))
                                    .fontWeight(unread ? .bold : .regular)
                                Spacer(minLength: 12)
                                Text(app.trStatus(EventLabels.ago(hoursAgo(item.createdAt))))
                                    .font(.system(size: 11))
                            }
                            Text(item.body).font(.system(size: 13)).multilineTextAlignment(.leading)
                        }
                    }
                    .opacity(unread ? 1 : 0.6)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(app.palette.rule)
            }
        }
        .padding(.bottom, 22)
    }

    private func hoursAgo(_ date: Date) -> Int {
        max(1, Int(Date().timeIntervalSince(date) / 3600))
    }
}

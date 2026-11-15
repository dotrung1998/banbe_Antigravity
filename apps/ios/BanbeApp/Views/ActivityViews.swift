import SwiftUI

/// Activity screen pieces (web twin: the Messages / Notifications tabs in src/screens/Inbox.jsx, commits b9ee09a,
/// bcfa1ee, cd0118e). InboxView hosts them; this file holds the tab bar, filter chips, the notifications tab and the
/// small memory that lets a notification opened from Activity return to Activity on the same tab.

enum ActivityTab: String { case messages, notifications }

/// Survives the trip into a notification's destination screen. `openNotification` routes every destination's Back to
/// `.notifications`; `NotificationsView` (non-overlay) hands that straight back to the Activity screen while
/// `returnPending` is fresh, so Back lands on Activity with the Notifications tab selected instead of a second list.
enum ActivityMemory {
    static var tab: ActivityTab = .messages
    private static var pendingAt: Date?
    static var returnPending: Bool {
        guard let at = pendingAt else { return false }
        return Date().timeIntervalSince(at) < 600
    }
    static func markReturn() { tab = .notifications; pendingAt = Date() }
    static func clearReturn() { pendingAt = nil }
}

/// Messages / Notifications segmented control with unread counts.
struct ActivityTabsBar: View {
    @EnvironmentObject private var app: AppState
    @Binding var tab: ActivityTab

    var body: some View {
        HStack(spacing: 0) {
            segment(.messages, app.T("Tin nhắn", "Messages"), app.unreadMessages, "activity.tab.messages")
            segment(.notifications, app.T("Thông báo", "Notifications"), app.unreadNotifications, "activity.tab.notifications")
        }
        .padding(3)
        .background(app.palette.block, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .tourTarget("tour.activity.tabs")
    }

    private func segment(_ k: ActivityTab, _ label: String, _ count: Int, _ id: String) -> some View {
        let on = tab == k
        return Button {
            tab = k
            ActivityMemory.tab = k
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.app(size: 14, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.app(size: 10, weight: .bold))
                        .foregroundStyle(BanbeTheme.onAlert)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(BanbeTheme.alert, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(on ? app.palette.paper : app.palette.ink3)
            .background(on ? app.palette.ink : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// A horizontal row of filter chips (selected = ink fill, others = block fill).
struct ActivityChips<K: Hashable>: View {
    @EnvironmentObject private var app: AppState
    let items: [(K, String)]
    @Binding var value: K
    var identifierPrefix: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let on = value == item.0
                    Button { value = item.0 } label: {
                        Text(item.1)
                            .font(.app(size: 13, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .foregroundStyle(on ? app.palette.paper : app.palette.ink2)
                            .background(on ? app.palette.ink : app.palette.block, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifierPrefix).\(item.1)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14).padding(.bottom, 10)
        }
    }
}

enum ActivityMessageFilter: Hashable { case all, unread, dispute }
enum ActivityNotificationFilter: Hashable { case all, tickets, payments, events, rewards }

/// The Notifications tab: chips, "Mark all as read" and the same row the Notifications screen uses. A tap opens the
/// destination and remembers this tab, so Back returns here.
struct ActivityNotificationsList: View {
    @EnvironmentObject private var app: AppState
    let query: String
    @State private var filter: ActivityNotificationFilter = .all

    /// Same grouping as web: bookings + reminders = Tickets, money + disputes = Payments, events + messages = Events,
    /// the rest = Rewards.
    private func chip(for kind: String) -> ActivityNotificationFilter {
        switch notificationCategory(kind) {
        case "booking", "reminder": return .tickets
        case "payment", "refund", "dispute": return .payments
        case "event", "message": return .events
        default: return .rewards
        }
    }

    private var list: [AppNotification] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return app.notifications.filter { n in
            (filter == .all || chip(for: n.kind) == filter)
                && (q.isEmpty || n.title.lowercased().contains(q) || n.body.lowercased().contains(q))
        }
    }

    var body: some View {
        let items = list
        let unreadAll = app.notifications.filter { $0.readAt == nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ActivityChips(
                    items: [(ActivityNotificationFilter.all, app.T("Tất cả", "All")), (ActivityNotificationFilter.tickets, app.T("Vé", "Tickets")),
                            (ActivityNotificationFilter.payments, app.T("Thanh toán", "Payments")), (ActivityNotificationFilter.events, app.T("Sự kiện", "Events")),
                            (ActivityNotificationFilter.rewards, app.T("Thưởng", "Rewards"))],
                    value: $filter, identifierPrefix: "activity.ntChip"
                )
                .padding(.horizontal, -20)   // chips carry their own 20pt gutter
                if !unreadAll.isEmpty {
                    HStack {
                        Spacer()
                        Button(app.T("Đánh dấu đã đọc", "Mark all as read")) {
                            Task { for n in unreadAll { await app.markNotificationRead(n) } }
                        }
                        .font(.app(size: 13))
                        .foregroundStyle(app.palette.ink)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notifications.markAll")
                    }
                    .padding(.bottom, 4)
                }
                if items.isEmpty {
                    Text(app.T("Chưa có thông báo nào.", "Nothing here yet."))
                        .font(.app(size: 14))
                        .foregroundStyle(app.palette.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    ForEach(items) { item in
                        ActivityNotificationRow(item: item)
                        Divider().overlay(app.palette.divider)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, BottomTabBar.contentClearance)
        }
        .foregroundStyle(app.palette.ink)
        .refreshable { await app.loadNotifications() }
        .task { await app.loadNotifications() }
    }
}

/// One notification, laid out like the Notifications screen's row (avatar, title + kind icon, one-line preview, age,
/// "…" menu), minus selection mode.
private struct ActivityNotificationRow: View {
    @EnvironmentObject private var app: AppState
    let item: AppNotification
    private var unread: Bool { item.readAt == nil }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SwipeSafeButton {
                ActivityMemory.markReturn()
                app.notificationsBack = .inbox
                app.openNotification(item)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.kind == "event_announcement" ? "📣 " + app.T("Thông báo từ host", "Host announcement") : item.title)
                                .font(BanbeTheme.display(15))
                                .fontWeight(unread ? .bold : .regular)
                                .foregroundStyle(item.kind == "event_announcement" ? BanbeTheme.alert : app.palette.ink)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            NotificationKindIcon(category: notificationCategory(item.kind))
                            Spacer(minLength: 12)
                            Text(app.trStatus(EventLabels.ago(max(1, Int(Date().timeIntervalSince(item.createdAt) / 3600)))))
                                .font(.app(size: 11))
                        }
                        Text(item.body)
                            .font(.app(size: 13))
                            .foregroundStyle(app.palette.ink.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification.row")

            Menu {
                Button {
                    Task { if item.readAt != nil { await app.markNotificationUnread(item) } else { await app.markNotificationRead(item) } }
                } label: {
                    Label(item.readAt != nil ? app.T("Đánh dấu chưa đọc", "Mark as unread") : app.T("Đánh dấu đã đọc", "Mark as read"),
                          systemImage: item.readAt != nil ? "envelope.badge" : "envelope.open")
                }
                Button { Task { await app.muteNotificationKind(item.kind) } } label: {
                    Label(app.T("Tắt loại thông báo này", "Turn off this kind of notification"), systemImage: "bell.slash")
                }
                Button(role: .destructive) { Task { await app.deleteNotification(item) } } label: {
                    Label(app.T("Xoá thông báo này", "Delete this notification"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.app(size: 15, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.4))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("notification-menu")
        }
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(unread ? app.palette.ink.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, -10)
    }

    @ViewBuilder private var avatar: some View {
        switch avatarSource(for: item, maps: app.notificationAvatarMaps, accountType: app.accountType) {
        case .image(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { fallback("🔔") }
            }
            .frame(width: 40, height: 40).clipShape(Circle())
        case .catalogPhoto(let path):
            CatalogPhoto(path: path, height: 40, width: 40, cornerRadius: 20)
        case .teamFallback:
            Circle().fill(app.palette.ink.opacity(0.08)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "person.2.fill").font(.app(size: 15)).foregroundStyle(app.palette.ink.opacity(0.55)))
        case .fallback:
            fallback("🔔")
        }
    }

    private func fallback(_ glyph: String) -> some View {
        Circle().fill(app.palette.ink.opacity(0.08)).frame(width: 40, height: 40)
            .overlay(Text(glyph).font(.app(size: 16)))
    }
}

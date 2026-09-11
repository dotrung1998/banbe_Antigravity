import SwiftUI

/// Port of src/screens/Account.jsx — profile header with rename, the
/// going/saved counters, links to messages and preferences, the organizer
/// mode switch, and sign in/out.
struct AccountView: View {
    @EnvironmentObject var app: AppState

    private var subtitle: String {
        if app.accountType == "admin" { return app.T("Quản trị viên", "Admin") }
        return app.canHost ? app.T("Người tham gia ▪︎ Người tổ chức", "Goer ▪︎ Host")
                           : app.T("Người tham gia", "Goer")
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(app.T("Tài khoản", "Account")).font(BanbeTheme.display(27))
                    Spacer()
                    Button(app.T("Xong", "Done")) { app.goHome() }
                        .font(.system(size: 12)).buttonStyle(.plain)
                }

                HStack(spacing: 14) {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .font(BanbeTheme.display(22))
                        .frame(width: 56, height: 56)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(app.displayName).font(BanbeTheme.display(22)).lineLimit(1)
                            if app.isSignedIn {
                                Button(app.T("Đổi tên", "Rename")) { app.goEditName() }
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(app.palette.ink.opacity(0.65))
                                    .buttonStyle(.plain)
                            }
                        }
                        Text(subtitle).font(.system(size: 11)).kerning(0.6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 22)

                HStack(spacing: 10) {
                    counter(value: app.goingEventsCount, label: app.T("Đang tham gia", "Going")) { app.goGoingList() }
                    counter(value: app.favorites.count, label: app.T("Đã lưu", "Saved")) { app.goSavedList() }
                }
                .padding(.top, 22)

                VStack(spacing: 0) {
                    row(app.T("Tin nhắn", "Messages"), trailing: "›") { app.goInbox() }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Sự kiện đã hoàn thành", "Completed events"), trailing: "\(app.completedEventsCount) ›") { app.goCompletedList() }
                    Divider().overlay(app.palette.rule)
                    row(app.T("Ngôn ngữ & hiển thị", "Language & appearance"),
                        identifier: "account.preferences",
                        trailing: (app.lang == "en" ? "English" : "Tiếng Việt") + " ▪︎ "
                            + (app.theme == "dark" ? app.T("Tối", "Dark") : app.T("Sáng", "Light"))) {
                        app.openPreferences()
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 20)

                Text(app.T("Tổ chức", "Hosting"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 22)

                Button { app.toggleOrganizerMode() } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.T("Chế độ tổ chức", "Organizer mode")).font(.system(size: 14))
                            Text(app.T("Bật để tạo và quản lý sự kiện. Tắt lúc nào cũng được.",
                                       "Turn on to create and manage events. Turn it off any time."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(app.palette.ink.opacity(0.7))
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        ZStack(alignment: app.canHost ? .trailing : .leading) {
                            Capsule()
                                .fill(app.canHost ? app.palette.ink : app.palette.ink.opacity(0.18))
                                .frame(width: 44, height: 26)
                            Circle().fill(app.palette.paper).frame(width: 20, height: 20).padding(3)
                        }
                        .animation(.easeInOut(duration: 0.15), value: app.canHost)
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                if !app.organizerModeError.isEmpty {
                    Text(app.organizerModeError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                }

                if app.canHost {
                    Button { app.switchToHost(back: .profile) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.orgRegName.isEmpty ? "Bếp Nhỏ" : app.orgRegName)
                                    .font(BanbeTheme.display(17))
                                Text(app.mode == "host"
                                     ? app.T("Xem trang tổ chức của bạn", "View your host page")
                                     : app.T("Chuyển sang chế độ tổ chức", "Switch to hosting"))
                                    .font(.system(size: 12))
                            }
                            Spacer()
                            Text("›").font(.system(size: 17))
                        }
                        .foregroundStyle(app.palette.ink)
                        .padding(16)
                        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(app.T("Tổ chức sự kiện đầu tiên", "Host your first event"))
                            .font(BanbeTheme.display(19))
                        Text(app.T(
                            "Miễn phí hoàn toàn khi banbe còn mới — không phí đăng, không phí giao dịch. Tạo sự kiện đầu tiên để mở trang tổ chức.",
                            "Completely free while banbe is new — no listing or transaction fees. Create your first event to unlock your host page."
                        ))
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        InkButton(title: app.T("Bắt đầu tổ chức ▪︎ miễn phí", "Start hosting ▪︎ free")) {
                            app.toggleOrganizerMode()
                        }
                    }
                    .foregroundStyle(app.palette.ink)
                    .padding(16)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 10)
                }

                Button(app.isSignedIn
                       ? app.T("Đăng xuất", "Sign out")
                       : app.T("Đăng nhập để lưu sự kiện và nhắn tin", "Sign in to save events and message hosts")) {
                    if app.isSignedIn { Task { await app.signOut() } } else { app.goLogin() }
                }
                .font(.system(size: 13))
                .foregroundStyle(app.palette.ink)
                .buttonStyle(.plain)
                .accessibilityIdentifier(app.isSignedIn ? "account.signOut" : "account.signIn")
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func counter(value: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)").font(BanbeTheme.display(24))
                Text(label).font(.system(size: 11))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(app.palette.ink)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, identifier: String? = nil, trailing: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
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

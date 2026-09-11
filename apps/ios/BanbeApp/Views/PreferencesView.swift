import SwiftUI

/// Port of src/screens/Preferences.jsx — language and appearance, both of
/// which follow the signed-in account (see AppState.persistPreference).
struct PreferencesView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }

                Text(app.T("Ngôn ngữ & hiển thị", "Language & appearance"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 16)
                Text(app.T("Chọn cách banbe xuất hiện với bạn. Bạn có thể đổi lại bất cứ lúc nào.",
                           "Choose how banbe looks. You can change it anytime."))
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .padding(.top, 10)

                section(app.T("Ngôn ngữ", "Language")) {
                    choice(title: "Tiếng Việt", subtitle: app.T("Mặc định", "Vietnamese"),
                           active: app.lang == "vi") {
                        app.lang = "vi"
                        app.persistPreference(["locale": "vi"])
                    }
                    .accessibilityIdentifier("pref.lang.vi")
                    choice(title: "English", subtitle: app.T("Bạn có thể đổi lại bất cứ lúc nào", "Switch anytime"),
                           active: app.lang == "en") {
                        app.lang = "en"
                        app.persistPreference(["locale": "en"])
                    }
                    .accessibilityIdentifier("pref.lang.en")
                }

                section(app.T("Hiển thị", "Appearance")) {
                    choice(title: app.T("Sáng", "Light"), subtitle: app.T("Nền giấy ấm", "Warm paper"),
                           active: app.theme == "light") { app.pickTheme("light") }
                        .accessibilityIdentifier("pref.theme.light")
                    choice(title: app.T("Tối", "Dark"), subtitle: app.T("Nền mực dịu mắt", "Soft ink background"),
                           active: app.theme == "dark") { app.pickTheme("dark") }
                        .accessibilityIdentifier("pref.theme.dark")
                }
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 42)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            content()
        }
        .padding(.top, 28)
    }

    private func choice(title: String, subtitle: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(BanbeTheme.display(17))
                    Text(subtitle).font(.system(size: 11.5))
                }
                Spacer()
                Text(active ? "✓" : "›").font(.system(size: 15))
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 18).padding(.vertical, 17)
            .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(active ? app.palette.ink : app.palette.rule, lineWidth: active ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Port of src/screens/EditName.jsx — renaming notifies every organizer
/// this guest has booked with, in-app and by email (the RPC does the first,
/// /api/notify-name-change the second).
struct EditNameView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Tài khoản", "Account")) { app.screen = .profile }

                Text(app.T("Tên hiển thị", "Display name"))
                    .font(BanbeTheme.display(27))
                    .padding(.top, 16)
                Text(app.T(
                    "Đây là tên mà người tổ chức và khách khác thấy. Nếu bạn từng giữ chỗ ở đâu, đổi tên sẽ báo cho người tổ chức đó qua thông báo và email.",
                    "This is the name organizers and other guests see. If you have any bookings, changing it notifies those organizers by in-app notification and email."
                ))
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .padding(.top, 10)

                BanbeField(label: nil, placeholder: app.T("Tên của bạn", "Your name"), text: $app.editNameValue)
                    .padding(.top, 22)

                if !app.editNameError.isEmpty {
                    Text(app.editNameError)
                        .font(.system(size: 12))
                        .foregroundStyle(BanbeTheme.alert)
                        .padding(.top, 10)
                }

                InkButton(title: app.editNameSaving ? app.T("Đang lưu…", "Saving…") : app.T("Lưu tên", "Save name"),
                          enabled: !app.editNameSaving) {
                    Task { await app.saveDisplayName() }
                }
                .padding(.top, 18)
            }
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 42)
        }
    }
}

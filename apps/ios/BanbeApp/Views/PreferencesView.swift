import SwiftUI

/// Port of src/screens/Preferences.jsx — language and appearance, both of
/// which follow the signed-in account (see AppState.persistPreference).
struct PreferencesView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // Sub-section-of-a-group back-navigation fix (2026-09-29,
                // second pass) — was hardcoded to `.profile`, skipping the
                // "Tùy chỉnh"/"Preferences" group page this is actually
                // opened from (AccountGroupView). `goBack()` already routes
                // `.preferences` to `.accountGroup` correctly — reused
                // here instead of a second hardcoded target.
                BackLink(label: app.backLabel(for: app.backTargetScreen)) { app.goBack() }

                Text(app.T("Ngôn ngữ & Hiển thị", "Language & Appearance"))
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

                    liquidGlassPreview
                    .foregroundStyle(app.palette.ink)
                    .padding(.horizontal, 18).padding(.vertical, 15)
                    .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
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

    private var liquidGlassPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(app.T("Liquid Glass", "Liquid Glass"))
                    .font(BanbeTheme.display(17))
                Spacer()
                Text("\(Int(app.glassOpacity * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(app.palette.ink.opacity(0.65))
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(app.palette.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(app.palette.rule, lineWidth: 1)
                    }
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.T("Khu vực", "Area"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(app.palette.ink.opacity(0.6))
                    Text(app.currentAreaLabel)
                        .font(BanbeTheme.display(22))
                    Text(app.T("Chạm để mở bộ lọc khu vực", "Tap to open the area filter"))
                        .font(.system(size: 12))
                        .foregroundStyle(app.palette.ink.opacity(0.62))
                    HStack(spacing: 8) {
                        previewCapsule(app.T("Khu vực", "Area"))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 10) {
                Image(systemName: "square.on.square")
                    .font(.system(size: 20))
                    .foregroundStyle(app.palette.ink.opacity(0.58))
                    .accessibilityHidden(true)
                Slider(value: $app.glassOpacity, in: 0.0...1.0, step: 0.05)
                    .tint(app.palette.ink)
                    .accessibilityIdentifier("pref.glassOpacity")
                    .accessibilityLabel(app.T("Độ trong Liquid Glass", "Liquid Glass opacity"))
                    .accessibilityValue("\(Int(app.glassOpacity * 100))%")
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(app.palette.ink.opacity(0.58))
                    .accessibilityHidden(true)
            }
            Text(app.T(
                "Trong suốt hơn giúp nền hiển thị rõ hơn; đậm hơn tăng độ tương phản cho nội dung và nút.",
                "Clear is more transparent; tinted increases opacity and contrast for content and controls."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(app.palette.ink.opacity(0.68))
            .lineSpacing(3)
        }
        .foregroundStyle(app.palette.ink)
        .padding(.horizontal, 18).padding(.vertical, 15)
        .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(app.palette.rule, lineWidth: 1))
    }

    @ViewBuilder
    private func previewCapsule(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(app.palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer {
                        Capsule()
                            .fill(app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .opacity(app.glassOpacity)
                    }
                } else {
                    Capsule()
                        .fill(app.palette.ink.opacity(0.04 + 0.20 * app.glassOpacity))
                        .background(.thinMaterial, in: Capsule())
                        .opacity(app.glassOpacity)
                }
            }
            .overlay(Capsule().stroke(app.palette.rule.opacity(0.7 * app.glassOpacity), lineWidth: 1))
    }
}

/// Port of src/screens/EditName.jsx — renaming notifies every organizer
/// this guest has booked with, in-app and by email (the RPC does the first,
/// /api/notify (type: name_change) the second).
struct EditNameView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                // TASK 4 (Reserve→edit-name pass) — `editNameReturnScreen`
                // (set by `goEditName()`) is wherever this was actually
                // opened from now, not always Account.
                BackLink(label: app.editNameReturnScreen == .reserve ? app.T("Đặt chỗ", "Reserve") : app.T("Tài khoản", "Account")) {
                    app.screen = app.editNameReturnScreen
                }

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

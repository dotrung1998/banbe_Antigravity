import SwiftUI

/// Admin > Feature switches (migration 187, note 51) — the iOS counterpart of src/screens/AdminFeatures.jsx. One row
/// per platform feature flag. Turning a switch off hides the feature everywhere (web + iOS, signed in and signed
/// out) without a release; turning it on shows it again. The server decides who may flip it (is_platform_admin()
/// inside admin_set_feature_flag, audited); this view only calls it, and the switch moves only after the server
/// accepted the change.
struct AdminFeaturesView: View {
    @EnvironmentObject private var app: AppState
    @State private var error = ""

    private struct Flag: Identifiable {
        let key: String, vi: String, en: String, hintVi: String, hintEn: String
        var id: String { key }
    }
    private let flags = [
        Flag(key: "rewards", vi: "Phần thưởng & huy hiệu", en: "Rewards & badges",
             hintVi: "Ẩn xu, chuỗi ngày, huy hiệu và mẫu móc khoá thưởng khỏi toàn bộ ứng dụng. Dữ liệu không bị xoá.",
             hintEn: "Hides coins, streaks, badges and reward keychain designs everywhere in the app. No data is deleted."),
    ]

    private func message(_ code: String?) -> String {
        switch code ?? "" {
        case "NOT_AUTHORIZED": return app.T("Bạn không có quyền.", "You are not allowed to do this.")
        case "INVALID_VALUE": return app.T("Giá trị không hợp lệ.", "Invalid value.")
        case "NOT_DEPLOYED": return app.T("Máy chủ chưa có công tắc này (chạy migration 187).", "The server does not have this switch yet (apply migration 187).")
        case "BUSY": return app.T("Đang xử lý…", "Working…")
        default: return app.T("Không kết nối được. Thử lại nhé.", "Couldn't reach the server. Try again.")
        }
    }

    private func flip(_ key: String, to enabled: Bool) async {
        error = ""
        let r = await app.setFeatureFlag(key, enabled: enabled)
        if !r.ok {
            error = message(r.error)
            await app.loadFeatureFlags(force: true)
        }
    }

    var body: some View {
        ScreenScaffold {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(label: app.T("Duyệt & Kiểm Duyệt", "Review & Moderation")) { app.screen = .accountGroup }
                    .padding(.top, 8)
                    .accessibilityIdentifier("adminFeatures.back")
                Text(app.T("Công tắc tính năng", "Feature switches"))
                    .font(BanbeTheme.display(24)).padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("adminFeatures.title")
                Text(app.T("Bật hoặc tắt một tính năng cho mọi người dùng, không cần phát hành bản mới. Mọi thay đổi đều được ghi lại.",
                           "Turn a feature on or off for every user without a release. Every change is logged."))
                    .font(.system(size: 13.5)).foregroundStyle(app.palette.ink.opacity(0.75)).padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(flags) { f in
                        let on = FeatureFlags.isOn(app.featureFlags, f.key)
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.T(f.vi, f.en)).font(.system(size: 15.5, weight: .semibold))
                                Text(app.T(f.hintVi, f.hintEn)).font(.system(size: 12.5)).opacity(0.7)
                                Text(on ? app.T("Đang hiện cho mọi người", "Visible to everyone")
                                        : app.T("Đang ẩn với mọi người", "Hidden from everyone"))
                                    .font(.system(size: 12, weight: .semibold)).opacity(on ? 1 : 0.7).padding(.top, 3)
                                    .accessibilityIdentifier("adminFeatures.\(f.key).state")
                            }
                            Spacer(minLength: 0)
                            GlassSwitch(isOn: on, loading: app.featureFlagBusy == f.key, identifier: "adminFeatures.\(f.key).switch") {
                                Task { await flip(f.key, to: !on) }
                            }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("adminFeatures.\(f.key)")
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 22)

                if !error.isEmpty {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.top, 12)
                        .accessibilityIdentifier("adminFeatures.error")
                }
            }
            .padding(.horizontal, 22)
        }
    }
}

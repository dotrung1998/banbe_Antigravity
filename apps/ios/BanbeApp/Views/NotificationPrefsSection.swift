import SwiftUI

/// L5 weekly digest opt-in (switch `weekly_digest`, migration 200), in Account › Settings › Notifications — the iOS
/// counterpart of src/screens/DigestOptIn.jsx. PROMOTIONAL, so it is off until the person turns it on here, says so in
/// one line, and turning it off always works (set_my_digest_opt_in refuses only turning it ON while the switch is
/// off). While real push is on (`push_enabled`) the separate promotional-push consent sits under it
/// (set_my_promo_push). Every change is logged server-side. Hidden entirely while `weekly_digest` is off.
struct NotificationPrefsSection: View {
    @EnvironmentObject private var app: AppState
    @State private var digest: Bool?
    @State private var promoPush: Bool?
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        if app.weeklyDigestEnabled, app.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.T("Thông báo", "Notifications"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.top, 24)
                VStack(spacing: 0) {
                    toggleRow(title: app.T("Bản tin cuối tuần: sự kiện cuối tuần, tối thứ Năm", "Weekly digest: this weekend's events, Thursday evening"),
                              detail: app.T("Tin quảng bá. Mặc định tắt. Tắt bất cứ lúc nào.", "Promotional. Off by default. Turn off anytime."),
                              value: digest, identifier: "account.digestToggle") { next in
                        await set("set_my_digest_opt_in", next, current: $digest)
                    }
                    if app.pushEnabled {
                        Divider().overlay(app.palette.rule)
                        toggleRow(title: app.T("Thông báo đẩy quảng bá", "Promotional push notifications"), detail: nil,
                                  value: promoPush, identifier: "account.promoPushToggle") { next in
                            await set("set_my_promo_push", next, current: $promoPush)
                        }
                    }
                }
                .background(app.palette.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if !error.isEmpty {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(BanbeTheme.alert).padding(.horizontal, 2)
                }
            }
            .foregroundStyle(app.palette.ink)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account.notificationsSection")
            .task(id: app.userID) {
                let prefs = await app.fetchNotificationPreferences()
                digest = prefs?.digestOptIn ?? false
                promoPush = prefs?.promoPush ?? false
            }
        }
    }

    private func toggleRow(title: String, detail: String?, value: Bool?, identifier: String,
                           change: @escaping (Bool) async -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { value ?? false }, set: { next in Task { await change(next) } }))
                .labelsHidden()
                .toggleStyle(BanbeLiquidToggleStyle())
                .disabled(value == nil || busy)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func set(_ rpc: String, _ next: Bool, current: Binding<Bool?>) async {
        guard current.wrappedValue != nil, !busy else { return }
        let previous = current.wrappedValue
        busy = true
        error = ""
        current.wrappedValue = next
        let code = await app.setNotificationConsent(rpc, enabled: next)
        busy = false
        guard let code else { return }
        current.wrappedValue = previous
        error = code == "NOT_AVAILABLE"
            ? app.T("Bản tin cuối tuần đang tạm tắt.", "The weekly digest is turned off for now.")
            : app.T("Không lưu được. Thử lại nhé.", "Couldn't save. Try again.")
    }
}

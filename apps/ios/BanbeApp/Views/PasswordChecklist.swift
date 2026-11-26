import SwiftUI

/// Live checklist under a "new password" field (sign-up, Account › Security, reset link). Each row carries a
/// ✓ / ○ symbol plus its label, so meeting a rule never depends on colour alone. Twin:
/// src/components/PasswordChecklist.jsx (same rules from `PasswordRules`).
struct PasswordChecklist: View {
    let password: String
    let isEN: Bool

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PasswordRules.checks(password)) { check in
                HStack(spacing: 8) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(check.label(isEN: isEN))
                        .font(.app(size: 12.5, weight: check.ok ? .semibold : .regular))
                }
                .foregroundStyle(check.ok ? app.palette.ink : app.palette.ink3)
                .accessibilityElement(children: .combine)
                .accessibilityValue(check.ok ? (isEN ? "Met" : "Đã đạt") : (isEN ? "Not met" : "Chưa đạt"))
            }
        }
        .padding(.top, 10)
        .animation(.easeOut(duration: 0.15), value: PasswordRules.checks(password).map(\.ok))
        .accessibilityIdentifier("password.checklist")
    }
}

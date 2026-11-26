import Foundation

/// One password rule for every place a password is chosen: sign-up, Account › Security (change), and the
/// reset-link "choose a new password" screen. The checklist under the field renders these items in order; the
/// submit button stays off until every item is met. Logging in never checks these (older accounts may have
/// shorter passwords and must still get in).
/// Twin: src/lib/passwordRules.js (same ids, order, copy).
enum PasswordRules {
    static let minLength = 8

    struct Check: Identifiable, Equatable {
        let id: String
        let ok: Bool
        let vi: String
        let en: String
        func label(isEN: Bool) -> String { isEN ? en : vi }
    }

    static func checks(_ password: String) -> [Check] {
        [
            Check(id: "length", ok: password.count >= minLength, vi: "Ít nhất 8 ký tự", en: "At least 8 characters"),
            Check(id: "lower", ok: password.contains(where: { $0.isLowercase }), vi: "Một chữ thường", en: "One lowercase letter"),
            Check(id: "upper", ok: password.contains(where: { $0.isUppercase }), vi: "Một chữ hoa", en: "One uppercase letter"),
            Check(id: "number", ok: password.contains(where: { $0.isNumber }), vi: "Một chữ số", en: "One number"),
        ]
    }

    static func meetsRules(_ password: String) -> Bool { checks(password).allSatisfy(\.ok) }
}

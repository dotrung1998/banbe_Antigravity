import Foundation
import Supabase

/// Account › Security "change password": when Save may run, what a failed step tells the person, and the throwaway
/// client that re-checks the current password. Twin: src/lib/passwordChange.js (same blockers, same copy).
enum PasswordChange {
    enum ProofMode: Equatable { case password, code }
    enum Blocker: Equatable { case proof, rules, same, confirm }

    static func blocker(mode: ProofMode, current: String, code: String, password: String, confirm: String) -> Blocker? {
        if mode == .code {
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            if trimmed.count != 6 || !trimmed.allSatisfy(\.isASCII) || !trimmed.allSatisfy(\.isNumber) { return .proof }
        } else if current.isEmpty {
            return .proof
        }
        if !PasswordRules.meetsRules(password) { return .rules }
        if mode != .code && password == current { return .same }
        if password != confirm { return .confirm }
        return nil
    }

    private static let rateLimitCodes: Set<String> = [
        "over_request_rate_limit", "over_email_send_rate_limit", "over_sms_send_rate_limit",
    ]

    /// (code, HTTP status, is a network failure) of an auth error.
    private static func parts(_ error: Error) -> (String, Int?, Bool) {
        if error is URLError { return ("", nil, true) }
        if let auth = error as? AuthError {
            if case let .api(_, errorCode, _, response) = auth {
                return (errorCode == .unknown ? "" : errorCode.rawValue, response.statusCode, false)
            }
            return (auth.errorCode == .unknown ? "" : auth.errorCode.rawValue, nil, false)
        }
        return ("", nil, false)
    }

    private static func suffix(_ code: String, _ status: Int?) -> String {
        if !code.isEmpty { return " (\(code))" }
        if let status { return " (HTTP \(status))" }
        return ""
    }

    static func currentPasswordMessage(for error: Error, isEN: Bool) -> String {
        func T(_ vi: String, _ en: String) -> String { isEN ? en : vi }
        let (code, status, network) = parts(error)
        if code == "invalid_credentials" || (code.isEmpty && status == 400) {
            return T("Mật khẩu hiện tại không đúng.", "Your current password is not correct.")
        }
        if rateLimitCodes.contains(code) || status == 429 {
            return T("Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.", "Too many attempts. Wait a few minutes and try again.")
        }
        if code == "captcha_failed" {
            return T("Kiểm tra bảo mật đang chặn bước này. Hãy xác nhận bằng mã qua email.",
                     "A security check is blocking this step. Confirm with an email code instead.")
        }
        if network {
            return T("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.", "Could not reach the server. Check your connection and try again.")
        }
        let s = suffix(code, status)
        return T("Không kiểm tra được mật khẩu hiện tại.\(s)", "We could not check your current password.\(s)")
    }

    /// For a failed `update(user:)` or `reauthenticate()`.
    static func updateMessage(for error: Error, isEN: Bool) -> String {
        func T(_ vi: String, _ en: String) -> String { isEN ? en : vi }
        let (code, status, network) = parts(error)
        switch code {
        case "same_password":
            return T("Mật khẩu mới phải khác mật khẩu hiện tại.", "Your new password must be different from the current one.")
        case "weak_password":
            return T("Mật khẩu này quá yếu hoặc đã bị lộ ở nơi khác. Hãy chọn mật khẩu khác.",
                     "This password is too weak or has appeared in a data leak. Choose a different one.")
        case "reauthentication_needed":
            return T("Cần xác nhận lại. Hãy xác nhận bằng mã qua email.", "Please confirm it is you again. Use an email code.")
        case "reauthentication_not_valid":
            return T("Mã xác nhận không đúng hoặc đã hết hạn.", "That confirmation code is wrong or has expired.")
        default: break
        }
        if rateLimitCodes.contains(code) || status == 429 {
            return T("Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.", "Too many attempts. Wait a few minutes and try again.")
        }
        if network {
            return T("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.", "Could not reach the server. Check your connection and try again.")
        }
        let s = suffix(code, status)
        return T("Không lưu được mật khẩu lúc này. Vui lòng thử lại.\(s)", "We could not save that password right now. Please try again.\(s)")
    }

    static func isReauthenticationNeeded(_ error: Error) -> Bool { parts(error).0 == "reauthentication_needed" }

    /// A client whose session lives only in memory under its own key, so signing in on it never replaces the
    /// real session in the Keychain. Never call `signOut()` on it with the default (global) scope.
    static func makeReauthClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(auth: .init(
                storage: EphemeralAuthStorage(),
                storageKey: "banbe-reauth-throwaway",
                autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true
            ))
        )
    }
}

/// In-memory auth storage for the throwaway client above.
final class EphemeralAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    func store(key: String, value: Data) throws { lock.lock(); values[key] = value; lock.unlock() }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
}

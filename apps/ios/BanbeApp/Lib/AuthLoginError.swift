import Foundation
import Supabase

/// Password login: turns a Supabase auth error into the reason the person actually needs to see. Before this,
/// every failure read "Wrong email or password", which hid a server-side CAPTCHA block (2026-11-26) behind a
/// message that sent people hunting for a password that was never wrong.
///
/// A wrong password and an unknown email still share one message (a login form should not say which).
/// Twin: src/lib/authLoginError.js (same kinds, same copy).
enum AuthLoginError {
    enum Kind: Equatable {
        case credentials, emailNotConfirmed, captcha, banned, rateLimit, network, other
    }

    private static let rateLimitCodes: Set<String> = [
        "over_request_rate_limit", "over_email_send_rate_limit", "over_sms_send_rate_limit",
    ]

    static func kind(code: String?, status: Int?) -> Kind {
        let code = code ?? ""
        switch code {
        case "invalid_credentials", "user_not_found": return .credentials
        case "email_not_confirmed": return .emailNotConfirmed
        case "captcha_failed": return .captcha
        case "user_banned": return .banned
        default: break
        }
        if rateLimitCodes.contains(code) || status == 429 { return .rateLimit }
        // Older GoTrue answers carry no code: a 400 on the password grant is the credentials case.
        if code.isEmpty && status == 400 { return .credentials }
        return .other
    }

    static func kind(of error: Error) -> Kind {
        if error is URLError { return .network }
        if let auth = error as? AuthError {
            if case let .api(_, errorCode, _, response) = auth {
                return kind(code: errorCode.rawValue, status: response.statusCode)
            }
            return kind(code: auth.errorCode.rawValue, status: nil)
        }
        return .other
    }

    /// The code shown in brackets for an unexpected failure, so it can be traced.
    private static func traceCode(of error: Error) -> String? {
        guard let auth = error as? AuthError else { return nil }
        if case let .api(_, errorCode, _, response) = auth {
            return errorCode.rawValue.isEmpty || errorCode == .unknown ? "HTTP \(response.statusCode)" : errorCode.rawValue
        }
        return auth.errorCode == .unknown ? nil : auth.errorCode.rawValue
    }

    static func message(for error: Error, isEN: Bool) -> String {
        func T(_ vi: String, _ en: String) -> String { isEN ? en : vi }
        switch kind(of: error) {
        case .credentials:
            return T("Sai email hoặc mật khẩu.", "Wrong email or password.")
        case .emailNotConfirmed:
            return T("Email này chưa được xác nhận. Hãy đăng nhập bằng mã qua email để xác nhận.",
                     "This email is not confirmed yet. Log in with an email code to confirm it.")
        case .captcha:
            return T("Kiểm tra bảo mật đang chặn đăng nhập. Vui lòng thử lại sau.",
                     "A security check is blocking sign-in right now. Please try again later.")
        case .banned:
            return T("Tài khoản này đang bị khoá. Hãy liên hệ banbe.", "This account is locked. Please contact banbe.")
        case .rateLimit:
            return T("Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.",
                     "Too many attempts. Wait a few minutes and try again.")
        case .network:
            return T("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.",
                     "Could not reach the server. Check your connection and try again.")
        case .other:
            let suffix = traceCode(of: error).map { " (\($0))" } ?? ""
            return T("Không thể đăng nhập lúc này. Vui lòng thử lại sau.\(suffix)",
                     "We could not log you in right now. Please try again later.\(suffix)")
        }
    }
}

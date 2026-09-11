import Foundation

/// Which flow a code request is for — matches the web app's `mode` field
/// (src/state/GocContext.jsx's authMode), not a Supabase auth concept.
enum AuthMode: String {
    case login
    case signup
}

/// One of the JSON `{ "error": "SOME_CODE" }` bodies api/auth/send-email-code.js
/// (see api/_lib/authLookup.js) can return — mirrors the codes
/// src/state/GocContext.jsx's authEmailErrorMessage() maps to Vietnamese/
/// English copy; this maps the same set to English only, since the iOS
/// scaffold has no language toggle yet.
struct AuthAPIError: LocalizedError {
    let code: String

    var errorDescription: String? {
        switch code {
        case "AUTH_ACCOUNT_NOT_FOUND":
            return "No account exists for this email. Try Sign up instead."
        case "AUTH_ACCOUNT_EXISTS":
            return "This email already has an account. Try Log in instead."
        case "VALID_NAME_REQUIRED":
            return "Please enter a display name."
        case "VALID_EMAIL_REQUIRED":
            return "Enter a valid email address."
        case "AUTH_EMAIL_DELIVERY_FAILED":
            return "We could not send the email right now. Please try again later."
        case "AUTH_ACCOUNT_LOOKUP_FAILED":
            return "We could not check the account right now. Please try again later."
        case "AUTH_LINK_GENERATION_FAILED":
            return "We could not create the verification code. Please try again later."
        case "AUTH_EMAIL_SERVICE_NOT_CONFIGURED":
            return "The email service is not configured yet. Please try again later."
        default:
            return "We could not send the code. Please try again later."
        }
    }
}

/// Talks to the same /api/auth/* Vercel functions the web app uses (see
/// src/lib/authEmail.js) instead of Supabase's own outgoing mail — see the
/// note in SupabaseService.swift on why: Supabase's built-in mailer is
/// rate-limited to only a handful of emails per hour and fails immediately
/// in practice, where these functions send via Gmail with no such limit.
enum AuthAPIService {
    /// Requests a 6-digit sign-in/sign-up code by email. Verifying it is
    /// still done directly against Supabase — see AuthViewModel.verifyEmailCode.
    static func requestEmailCode(email: String, mode: AuthMode, displayName: String? = nil) async throws {
        var body: [String: String] = ["email": email, "mode": mode.rawValue]
        if let displayName, !displayName.isEmpty {
            body["displayName"] = displayName
        }
        try await post(path: "/api/auth/send-email-code", body: body)
    }

    private static func post(path: String, body: [String: String]) async throws {
        guard let url = URL(string: AppConfig.apiBaseURL + path) else {
            throw AuthAPIError(code: "AUTH_EMAIL_REQUEST_FAILED")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPIError(code: "AUTH_EMAIL_REQUEST_FAILED")
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthAPIError(code: "AUTH_EMAIL_REQUEST_FAILED")
        }
        guard (200...299).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = json?["error"] as? String
            throw AuthAPIError(code: code ?? "AUTH_EMAIL_REQUEST_FAILED")
        }
    }
}

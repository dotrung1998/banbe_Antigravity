import Foundation

/// Which flow a code request is for — matches the web app's `mode` field
/// (src/state/BanBeContext.jsx's authMode), not a Supabase auth concept.
enum AuthMode: String {
    case login
    case signup
    // Survey-respondent lightweight verification (section 3 of the survey-
    // sharing pass) — deliberately does not pre-commit to signup/login, see
    // api/auth/index.js's own isRespondMode branch for why.
    case respond
}

/// One of the JSON `{ "error": "SOME_CODE" }` bodies api/auth/index.js (type: send_email_code)
/// (see api/_lib/authLookup.js) can return — mirrors the codes
/// src/state/BanBeContext.jsx's authEmailErrorMessage() maps to Vietnamese/
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
        case "VALID_PASSWORD_REQUIRED":
            return "Passwords need at least 8 characters."
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

/// Error shape for `AuthAPIService.deleteAccount` — carries the raw JSON
/// payload alongside the code so the caller can read `openEvents` on a
/// `ACCOUNT_DELETION_BLOCKED_OPEN_EVENT` refusal, unlike the plain
/// `AuthAPIError` above which only ever needs a static message.
struct AccountDeletionError: LocalizedError {
    let code: String
    let payload: [String: Any]

    var errorDescription: String? {
        if code == "ACCOUNT_DELETION_BLOCKED_OPEN_EVENT" {
            let names = (payload["openEvents"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let joined = names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
            return "You still own an open event\(joined). Please cancel or end it before deleting your account."
        }
        return "We could not delete your account right now. Please try again later."
    }
}

/// Talks to the same /api/auth Vercel function the web app uses (see
/// src/lib/authEmail.js) instead of Supabase's own outgoing mail — see the
/// note in SupabaseService.swift on why: Supabase's built-in mailer is
/// rate-limited to only a handful of emails per hour and fails immediately
/// in practice, where these functions send via Gmail with no such limit.
enum AuthAPIService {
    /// Requests a 8-digit sign-in/sign-up code by email. Verifying it is
    /// still done directly against Supabase — see AuthViewModel.verifyEmailCode.
    static func requestEmailCode(email: String, mode: AuthMode, displayName: String? = nil) async throws {
        var body: [String: String] = ["type": "send_email_code", "email": email, "mode": mode.rawValue]
        if let displayName, !displayName.isEmpty {
            body["displayName"] = displayName
        }
        try await post(path: "/api/auth", body: body)
    }

    /// Section 3 — a signed-out survey respondent's own lightweight
    /// verification. Same endpoint/body shape as `requestEmailCode` (mode:
    /// "respond"), but this one needs the response body back: the server
    /// auto-detects new-vs-existing identity and returns `isNewAccount` so
    /// the caller can disclose which one just happened BEFORE the
    /// respondent types the code — never silently.
    static func requestRespondEmailCode(email: String, displayName: String) async throws -> Bool {
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/auth") else {
            throw AuthAPIError(code: "AUTH_EMAIL_REQUEST_FAILED")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "send_email_code", "email": email, "mode": AuthMode.respond.rawValue, "displayName": displayName,
        ])
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPIError(code: "AUTH_EMAIL_REQUEST_FAILED")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthAPIError(code: json["error"] as? String ?? "AUTH_EMAIL_REQUEST_FAILED")
        }
        return json["isNewAccount"] as? Bool ?? false
    }

    /// Creates an account with a password of the person's own choosing.
    /// Like the code path this still finishes with the emailed 8-digit
    /// confirmation (verified as `.signup`) — the account exists but is
    /// unconfirmed until then. Mirrors src/lib/authEmail.js's
    /// requestPasswordSignup.
    static func requestPasswordSignup(email: String, password: String,
                                      displayName: String, locale: String) async throws {
        try await post(path: "/api/auth", body: [
            "type": "signup_password",
            "email": email, "password": password,
            "displayName": displayName, "locale": locale,
        ])
    }

    /// Sends the "choose a new password" email — the same endpoint and the
    /// same branded template the web app uses. Unlike sign-in, this stays a
    /// link rather than a code: it opens the web app with a Supabase
    /// recovery session already established, which is where the new
    /// password actually gets set (see api/auth/index.js, type: send_password_reset).
    ///
    /// The server answers 200 whether or not an account exists, so callers
    /// must show the same "check your email" message either way rather than
    /// branching on the result.
    static func requestPasswordReset(email: String) async throws {
        try await post(path: "/api/auth", body: ["type": "send_password_reset", "email": email])
    }

    /// Fire-and-forget call to the /api/notify endpoint (dispatched by a
    /// `type` field in `body`), with the
    /// caller's session token attached. Those endpoints re-derive their own
    /// recipient and authorization from the database using that token, so
    /// nothing here is trusted; the in-app notification has already been
    /// written by the RPC regardless, which is why a failure is silent.
    static func notify(path: String, body: [String: String]) async {
        guard let url = URL(string: AppConfig.apiBaseURL + path),
              let token = try? await SupabaseService.client.auth.session.accessToken
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Account deletion (Task 2, Account/Settings pass) — folds into the
    /// SAME `/api/auth` dispatcher (type: delete_account), never a new
    /// endpoint file. Unlike every function above, this call carries the
    /// caller's OWN bearer token (the endpoint verifies it server-side and
    /// derives the user id to delete from THAT token — never from anything
    /// this body sends). Returns the raw decoded JSON so the caller
    /// (DeleteAccountView) can read `openEvents` on a 409 refusal or
    /// `requestId` on success, mirroring web's equivalent fetch in
    /// BanBeContext.jsx's `confirmDeleteAccount`.
    static func deleteAccount(reasonCode: String?, reasonText: String?) async throws -> [String: Any] {
        guard let url = URL(string: AppConfig.apiBaseURL + "/api/auth"),
              let token = try? await SupabaseService.client.auth.session.accessToken
        else { throw AuthAPIError(code: "AUTH_REQUIRED") }

        var body: [String: Any] = ["type": "delete_account"]
        if let reasonCode, !reasonCode.isEmpty { body["reasonCode"] = reasonCode }
        if let reasonText, !reasonText.isEmpty { body["reasonText"] = reasonText }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthAPIError(code: "ACCOUNT_DELETION_FAILED")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = json["error"] as? String ?? "ACCOUNT_DELETION_FAILED"
            throw AccountDeletionError(code: code, payload: json)
        }
        return json
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

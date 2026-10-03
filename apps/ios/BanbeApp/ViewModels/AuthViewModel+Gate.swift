import Foundation
import Supabase

/// What the server says about the signed-in session (booleans only — the
/// stored date of birth is never sent to the client).
struct AccountGateStatus: Decodable, Equatable {
    let ready: Bool
    let phoneRequired: Bool
    let phoneVerified: Bool
    let dobEnrollmentRequired: Bool
    let dobConfirmationRequired: Bool

    enum CodingKeys: String, CodingKey {
        case ready
        case phoneRequired = "phone_required"
        case phoneVerified = "phone_verified"
        case dobEnrollmentRequired = "dob_enrollment_required"
        case dobConfirmationRequired = "dob_confirmation_required"
    }
}

enum AccountGateState: Equatable {
    /// No session, or the first check hasn't finished.
    case unknown
    case ready
    /// Enrollment or date-of-birth confirmation still required.
    case blocked(AccountGateStatus)
    /// The check itself failed (network/server). The app stays blocked — it
    /// never assumes "fine" — and the user can retry or sign out.
    case unavailable
}

enum PhoneCodeFailure: Equatable {
    case phoneInUse, rateLimited, providerUnavailable, invalidNumber, expired, wrongCode, network, other
}

enum DOBConfirmResult: Equatable {
    case success
    case incorrect(attemptsLeft: Int?)
    case locked(retryAfterSeconds: Int?)
    case failed
}

extension AuthViewModel {

    var gateReady: Bool { gate == .ready }

    // MARK: Status

    /// Asks the server whether this session may use the app. Silent refreshes
    /// (token refresh) never flip an already-decided state to "checking".
    func refreshGate() async {
        guard session != nil else { gate = .unknown; return }
        do {
            let status: AccountGateStatus = try await SupabaseService.client
                .rpc("account_gate_status").execute().value
            gateStatus = status
            let wasReady = gate == .ready
            gate = status.ready ? .ready : .blocked(status)
            // Profile reads were blocked by RLS while gated — load now.
            if status.ready, !wasReady, let uid = session?.user.id { await loadProfile(userId: uid) }
        } catch {
            if Self.isFunctionMissing(error) {
                // Migration 123 isn't deployed on this project: there is no
                // server rule to enforce, so don't lock everyone out of the app.
                gate = .ready
            } else if gate == .unknown {
                gate = .unavailable
            }
        }
    }

    private static func isFunctionMissing(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError {
            return pg.code == "PGRST202" || pg.code == "42883"
                || pg.message.localizedCaseInsensitiveContains("could not find the function")
        }
        return false
    }

    // MARK: Phone (real SMS OTP, bound to THIS user)

    /// Sends a verification code to `e164` and attaches it to the signed-in
    /// user as a pending phone change — Supabase never creates a second
    /// account for a phone. Uses the project's configured SMS provider.
    func sendPhoneCode(e164: String) async -> PhoneCodeFailure? {
        do {
            _ = try await SupabaseService.client.auth.update(user: UserAttributes(phone: e164))
            return nil
        } catch { return Self.phoneFailure(error) }
    }

    func resendPhoneCode(e164: String) async -> PhoneCodeFailure? {
        do {
            try await SupabaseService.client.auth.resend(phone: e164, type: .phoneChange)
            return nil
        } catch { return Self.phoneFailure(error) }
    }

    func verifyPhoneCode(e164: String, code: String) async -> PhoneCodeFailure? {
        do {
            _ = try await SupabaseService.client.auth.verifyOTP(phone: e164, token: code, type: .phoneChange)
            await refreshGate()
            return nil
        } catch {
            let failure = Self.phoneFailure(error)
            return failure == .other || failure == .invalidNumber ? .wrongCode : failure
        }
    }

    private static func phoneFailure(_ error: Error) -> PhoneCodeFailure {
        if let auth = error as? AuthError, case let .api(_, code, _, _) = auth {
            switch code {
            case .phoneExists: return .phoneInUse
            case .overSMSSendRateLimit, .overRequestRateLimit: return .rateLimited
            case .smsSendFailed, .phoneProviderDisabled, .otpDisabled: return .providerUnavailable
            case .otpExpired: return .expired
            case .validationFailed: return .invalidNumber
            default: return .other
            }
        }
        if (error as? URLError) != nil { return .network }
        return .other
    }

    // MARK: Date of birth

    private struct DOBRpcResult: Decodable {
        let success: Bool?
        let error: String?
        let attemptsLeft: Int?
        let retryAfterSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case success, error
            case attemptsLeft = "attempts_left"
            case retryAfterSeconds = "retry_after_seconds"
        }
    }

    /// New registration: store the DOB once (the server refuses an overwrite and
    /// refuses it before the phone is verified). `iso` is "YYYY-MM-DD".
    func submitEnrollmentDOB(iso: String) async -> Bool {
        do {
            let result: DOBRpcResult = try await SupabaseService.client
                .rpc("set_date_of_birth", params: ["p_dob": iso]).execute().value
            guard result.success == true else { return false }
            await refreshGate()
            return true
        } catch { return false }
    }

    /// Confirm date of birth for this session. Never logs the value.
    func confirmDOB(iso: String) async -> DOBConfirmResult {
        do {
            let result: DOBRpcResult = try await SupabaseService.client
                .rpc("confirm_date_of_birth", params: ["p_dob": iso]).execute().value
            if result.success == true {
                await refreshGate()
                return .success
            }
            switch result.error {
            case "INCORRECT": return .incorrect(attemptsLeft: result.attemptsLeft)
            case "LOCKED": return .locked(retryAfterSeconds: result.retryAfterSeconds)
            default: return .failed
            }
        } catch { return .failed }
    }
}

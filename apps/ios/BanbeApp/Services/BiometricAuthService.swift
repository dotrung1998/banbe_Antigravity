import LocalAuthentication

/// Thin wrapper around LocalAuthentication — used purely as an app-lock in
/// front of a session Supabase has already restored on its own (its client
/// persists sessions in the Keychain across launches regardless of this).
/// Face ID/Touch ID has no relationship to any Supabase credential; it just
/// gates whether this device's already-signed-in session gets shown.
enum BiometricAuthService {
    static func canAuthenticate() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static func biometryType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Returns true only on a genuine successful biometric match. Any
    /// failure (not enrolled, cancelled, lockout, etc.) returns false rather
    /// than throwing — the caller just stays locked and can retry.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var evalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &evalError) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }
}

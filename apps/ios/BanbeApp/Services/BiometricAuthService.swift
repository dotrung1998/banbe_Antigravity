import LocalAuthentication
import UIKit

/// Thin wrapper around LocalAuthentication — used purely as an app-lock in
/// front of a session Supabase has already restored on its own (its client
/// persists sessions in the Keychain across launches regardless of this).
/// Face ID/Touch ID has no relationship to any Supabase credential; it just
/// gates whether this device's already-signed-in session gets shown.
enum BiometricAuthService {
    /// `canEvaluatePolicy` is a synchronous call into the system's biometry service. View
    /// bodies re-run every second (AppState republishes `now`), so they must read THIS cached
    /// value, never the live calls below (note 45: it was a source of swipe stutter on Home).
    struct Availability: Equatable {
        let available: Bool
        let type: LABiometryType
    }

    private static var cached: Availability?
    private static var observing = false

    static var cachedAvailability: Availability {
        if let cached { return cached }
        let context = LAContext()
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        let value = Availability(available: ok, type: context.biometryType)
        cached = value
        if !observing {
            observing = true
            // Enrolling/removing a face or finger happens in Settings: re-read when we return.
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                cached = nil
            }
        }
        return value
    }

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

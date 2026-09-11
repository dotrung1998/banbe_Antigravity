import Foundation
import Supabase

/// Owns the current auth session and profile — the iOS equivalent of
/// GocContext's `user`/`accountType` state and its onAuthStateChange
/// listener on the web side (src/state/GocContext.jsx).
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var isSendingCode = false
    @Published var codeSent = false
    @Published var errorMessage: String?

    /// True whenever there's a restored session but Face ID app-lock (see
    /// BiometricAuthService) hasn't cleared it yet this launch. RootView
    /// shows FaceIDLockView on top of the app while this is true. This is
    /// purely a local UI gate — Supabase's own session persistence already
    /// happened before this is ever set.
    @Published var isLocked = false

    /// Persisted opt-in for the Face ID app-lock, toggled from SettingsView.
    /// Off by default — restoring a session works exactly as it does today
    /// until someone turns this on.
    @Published var faceIDEnabled: Bool = UserDefaults.standard.bool(forKey: AuthViewModel.faceIDDefaultsKey) {
        didSet { UserDefaults.standard.set(faceIDEnabled, forKey: AuthViewModel.faceIDDefaultsKey) }
    }
    private static let faceIDDefaultsKey = "banbe.faceIDEnabled"

    var isSignedIn: Bool { session != nil }

    private var authListenerTask: Task<Void, Never>?

    init() {
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            // Restores any persisted session on launch, then keeps listening
            // for sign-in/out and token refresh — mirrors
            // supabase.auth.onAuthStateChange in GocContext.jsx.
            for await (event, session) in SupabaseService.client.auth.authStateChanges {
                if event == .initialSession || event == .signedIn || event == .tokenRefreshed {
                    self.session = session
                    if let userId = session?.user.id {
                        await self.loadProfile(userId: userId)
                    }
                    // Only gate the cold-launch restore, not a session that
                    // was just freshly signed into in this same launch —
                    // that person is clearly already present.
                    if event == .initialSession, session != nil, self.faceIDEnabled {
                        self.isLocked = true
                    }
                } else if event == .signedOut {
                    self.session = nil
                    self.profile = nil
                    self.isLocked = false
                }
            }
        }
    }

    deinit {
        authListenerTask?.cancel()
    }

    private func loadProfile(userId: UUID) async {
        do {
            let profile: Profile = try await SupabaseService.client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            self.profile = profile
        } catch {
            // A brand-new sign-up may not have a profiles row yet if the
            // trigger that creates one hasn't run — not fatal, just empty.
            self.profile = nil
        }
    }

    /// Requests a 6-digit sign-in/sign-up code by email — via
    /// AuthAPIService (Gmail delivery through the same Vercel function the
    /// web app uses), not Supabase's own `signInWithOTP`. Supabase's
    /// built-in mailer is capped at a handful of emails per hour on this
    /// project and was failing almost immediately with "email rate limit
    /// exceeded"; the server function has no such limit. Also deliberately
    /// asks for no redirect link — this used to pass
    /// `redirectTo: "banbe://login-callback"`, a URL scheme that was never
    /// actually registered anywhere in the app, so that option just failed
    /// silently when tapped. Sign-in here is code-entry only.
    func sendEmailCode(to email: String, mode: AuthMode, displayName: String? = nil) async {
        isSendingCode = true
        errorMessage = nil
        defer { isSendingCode = false }
        do {
            try await AuthAPIService.requestEmailCode(email: email, mode: mode, displayName: displayName)
            codeSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Verifies the code from that email and establishes the session
    /// directly against Supabase (just checking a token, not sending
    /// anything — no rate limit involved) — the auth-state listener above
    /// takes it from there. `mode` must match whichever mode the code was
    /// requested for: a signup confirmation code verifies as `.signup`, a
    /// login code as `.email`.
    func verifyEmailCode(email: String, code: String, mode: AuthMode) async {
        errorMessage = nil
        do {
            try await SupabaseService.client.auth.verifyOTP(
                email: email, token: code, type: mode == .signup ? .signup : .email
            )
            codeSent = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Re-locks the app immediately — call this if biometry ever becomes
    /// unavailable (e.g. removed in Settings) while the toggle is still on,
    /// or from a manual "Lock now" affordance if one gets added later.
    func lockIfEnabled() {
        guard faceIDEnabled, session != nil else { return }
        isLocked = true
    }

    func signOut() async {
        try? await SupabaseService.client.auth.signOut()
    }
}

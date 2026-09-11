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

    /// Requests a 6-digit sign-in code by email via Supabase's built-in OTP
    /// endpoint. Deliberately no `redirectTo` — this used to pass
    /// `banbe://login-callback`, but that URL scheme was never actually
    /// registered anywhere in the app (no CFBundleURLTypes entry in
    /// project.yml, no onOpenURL handling wired to it either), so the
    /// emailed "sign in via link" option just failed silently when tapped.
    /// Since the app only ever verifies with a typed code, not a link,
    /// there's no reason to ask Supabase to include one — see the note in
    /// SupabaseService.swift about matching the web app's
    /// /api/auth/send-email-code endpoint more exactly in the future.
    func sendEmailCode(to email: String) async {
        isSendingCode = true
        errorMessage = nil
        defer { isSendingCode = false }
        do {
            try await SupabaseService.client.auth.signInWithOTP(email: email)
            codeSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Verifies the code from that email and establishes the session
    /// directly — the auth-state listener above takes it from there.
    func verifyEmailCode(email: String, code: String) async {
        errorMessage = nil
        do {
            try await SupabaseService.client.auth.verifyOTP(email: email, token: code, type: .email)
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

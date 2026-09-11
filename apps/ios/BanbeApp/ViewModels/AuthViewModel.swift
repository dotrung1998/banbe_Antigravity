import Foundation
import Supabase

/// Owns the current auth session and profile — the iOS equivalent of
/// GocContext's `user`/`accountType` state and its onAuthStateChange
/// listener on the web side (src/state/GocContext.jsx).
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var isSendingLink = false
    @Published var linkSent = false
    @Published var errorMessage: String?

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
                } else if event == .signedOut {
                    self.session = nil
                    self.profile = nil
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

    /// Sends a magic-link email via Supabase's built-in OTP flow. See the
    /// note in SupabaseService.swift about this vs. the web app's custom
    /// /api/auth/send-email-link endpoint.
    func sendMagicLink(to email: String) async {
        isSendingLink = true
        errorMessage = nil
        defer { isSendingLink = false }
        do {
            try await SupabaseService.client.auth.signInWithOTP(
                email: email,
                redirectTo: URL(string: "banbe://login-callback")
            )
            linkSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call from the app's onOpenURL when the magic link redirects back into
    /// the app (requires the `banbe` URL scheme registered in Info.plist).
    func handleAuthCallback(url: URL) async {
        do {
            try await SupabaseService.client.auth.session(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        try? await SupabaseService.client.auth.signOut()
    }
}

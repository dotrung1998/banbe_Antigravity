import Foundation

/// Sign-in hand-off (note 64). Web twin: beginSignInHandoff / completeSignInHandoff in src/state/BanBeContext.jsx.
///
/// Two conditions, one navigation: the session is applied (or the account gate has answered "blocked") AND the
/// login button's ✓ has finished. RootView's gate task keeps its authority: it calls `markSignInReady()` after
/// `applySession`, and only navigates itself when no hand-off is pending. The 20s timer is only a way out of a
/// stuck request, never a success signal.
extension AppState {
    func beginSignInHandoff() {
        resolveSignInReady(false)
        signInHandoffGeneration += 1
        signInReady = false
        signInHandoffPending = true
    }

    /// Called by RootView once the session is applied, or once the gate answers blocked/unavailable.
    func markSignInReady() {
        guard signInHandoffPending else { return }
        signInReady = true
        resolveSignInReady(true)
    }

    func awaitSignInReady() async -> Bool {
        if signInReady { return true }
        let generation = signInHandoffGeneration
        return await withCheckedContinuation { continuation in
            signInReadyContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.signInHandoffGeneration == generation else { return }
                self.resolveSignInReady(false)
            }
        }
    }

    /// The submit failed or never became ready: drop the hand-off. A session that already landed goes where it
    /// would have gone without it.
    func cancelSignInHandoff(sessionApplied: Bool) {
        resolveSignInReady(false)
        signInHandoffPending = false
        signInReady = false
        if sessionApplied && (screen == .login || screen == .welcome) { screen = authReturnScreen }
    }

    /// The ✓ finished. Navigates exactly once; a blocked gate simply shows over Login now that the hand-off is over.
    func completeSignInHandoff(sessionApplied: Bool) {
        guard signInHandoffPending else { return }
        signInHandoffPending = false
        signInReady = false
        guard sessionApplied, screen == .login || screen == .welcome else { return }
        let destination = authReturnScreen
        screen = destination
        justSignedIn = destination == .home
        runPendingAuthResume()
    }

    private func resolveSignInReady(_ value: Bool) {
        let c = signInReadyContinuation
        signInReadyContinuation = nil
        c?.resume(returning: value)
    }
}

import Foundation

/// One state model for every "do it, then show ✓" button (note 64). Web twin: src/lib/asyncAction.js.
///
///     idle ──start──▶ pending ──resolve(ok)──▶ success ──animDone──▶ completed
///                       └──resolve(error)──▶ failure ──reset──▶ idle
///
/// The operation's own result decides success; the animation only delays a hand-off that is already allowed.
/// `start` is ignored outside idle, so a double tap can never run the operation twice.
enum AsyncActionPhase: Equatable {
    case idle, pending, success, completed, failure

    /// The control must not accept another activation in these phases.
    var isLocked: Bool { self == .pending || self == .success || self == .completed }
}

struct AsyncActionState: Equatable {
    var phase: AsyncActionPhase = .idle
    var error: String? = nil
    /// Turns true exactly once (on animDone): the caller runs onSuccessAnimationComplete only on that transition.
    var fired = false

    enum Event: Equatable { case start, resolve(ok: Bool, error: String?), animDone, reset }

    func reduce(_ event: Event) -> AsyncActionState {
        switch event {
        case .start:
            return phase == .idle ? AsyncActionState(phase: .pending) : self
        case let .resolve(ok, error):
            guard phase == .pending else { return self }
            var s = self
            s.phase = ok ? .success : .failure
            s.error = ok ? nil : error
            return s
        case .animDone:
            guard phase == .success else { return self }
            var s = self
            s.phase = .completed
            s.fired = true
            return s
        case .reset:
            if phase == .pending { return self }
            return AsyncActionState(phase: .idle, error: phase == .failure ? error : nil)
        }
    }
}

/// What an operation reports back. A thrown error is a failure, never a success.
struct AsyncActionResult: Equatable {
    var ok: Bool
    var error: String? = nil
    static let success = AsyncActionResult(ok: true)
    static func failure(_ error: String? = nil) -> AsyncActionResult { AsyncActionResult(ok: false, error: error) }
}

// One state model for every "do it, then show ✓" button (note 64). Mirrored by apps/ios/BanbeApp/Lib/AsyncAction.swift.
//
//   idle ──start──▶ pending ──resolve(ok)──▶ success ──animDone──▶ completed
//                     │
//                     └──resolve(error)──▶ failure ──(next tick)──▶ idle
//
// The operation's own result decides success. The animation only delays a hand-off that is already allowed.
// `start` is ignored outside idle, so a double tap or Enter + click can never run the operation twice.

export const PHASES = Object.freeze({ idle: 'idle', pending: 'pending', success: 'success', completed: 'completed', failure: 'failure' });

export const initialAction = Object.freeze({ phase: 'idle', error: null, fired: false });

export function reduceAction(state, event) {
  const s = state || initialAction;
  switch (event?.type) {
    case 'start':
      return s.phase === 'idle' ? { phase: 'pending', error: null, fired: false } : s;
    case 'resolve':
      if (s.phase !== 'pending') return s;
      return event.ok ? { ...s, phase: 'success', error: null } : { ...s, phase: 'failure', error: event.error ?? null };
    case 'animDone':
      // `fired` turns true exactly once: the caller runs onSuccessAnimationComplete only on that transition.
      return s.phase === 'success' ? { ...s, phase: 'completed', fired: true } : s;
    case 'reset':
      // Failure always returns to idle. A completed "stay and update" button resets too. Pending never resets
      // (the operation is still running).
      return s.phase === 'pending' ? s : { phase: 'idle', error: s.phase === 'failure' ? s.error : null, fired: false };
    default:
      return s;
  }
}

/** True for the phases in which the control must not accept another activation. */
export const isLocked = phase => phase === 'pending' || phase === 'success' || phase === 'completed';

/**
 * Normalises whatever an operation returned into {ok, error}. Success must be explicit: `true` or `{ ok: true }`.
 * Anything else (false, undefined from an early return, a thrown error) is a failure, never a ✓.
 */
export async function runOperation(run) {
  try {
    const r = await run();
    if (r === true) return { ok: true, error: null };
    if (r && typeof r === 'object' && 'ok' in r) return { ok: !!r.ok, error: r.ok ? null : (r.error ?? null) };
    return { ok: false, error: null };
  } catch (e) {
    return { ok: false, error: e?.message || String(e) };
  }
}

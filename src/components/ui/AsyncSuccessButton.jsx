// "Do it, then ✓" button (note 64). iOS twin: apps/ios/BanbeApp/Views/AsyncSuccessButton.swift.
// State model: src/lib/asyncAction.js (idle → pending → success → completed, or pending → failure → idle).
//
// - `run` performs the real work and returns {ok, error?} (or throws). Only that result can show the ✓.
// - While pending the button freezes its width, morphs into a circle on its own axis and spins an arc.
// - On success the arc finishes its turn, a ✓ draws, success is announced, then onSuccessAnimationComplete runs
//   exactly once. That callback is where a caller navigates / presents (the hand-off was already allowed by `run`).
// - On failure the shape and label come back, focus stays here, and the caller shows its own role="alert" error.
// - `resetAfterSuccess` is for "stay and update" saves: after the ✓ it returns to the idle label.
import { useCallback, useEffect, useLayoutEffect, useReducer, useRef, useState } from 'react';
import { ink, paper, inkButton } from '../../theme.js';
import { reduceAction, initialAction, isLocked, runOperation } from '../../lib/asyncAction.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';

const LOOKS = {
  primary: () => inkButton({ padding: '15px 0', borderRadius: 18 }),
  secondary: () => ({ background: 'var(--bb-field)', color: ink, border: '1px solid var(--bb-rule)', borderRadius: 18, padding: '15px 0', fontSize: 15, fontWeight: 600 }),
  destructive: () => ({ background: 'var(--bb-alert)', color: paper, border: 'none', borderRadius: 18, padding: '15px 0', fontSize: 15, fontWeight: 600 }),
};

export default function AsyncSuccessButton({
  label, ariaLabel, pendingLabel, successLabel, enabled = true, variant = 'primary', run,
  onSuccessAnimationComplete, onFailure, testId, style, wrapStyle, successHoldMs = 0, resetAfterSuccess = false,
  successNeutral = false, onPhaseChange,
}) {
  const [state, dispatch] = useReducer(reduceAction, initialAction);
  const phase = state.phase;
  const reduce = useReducedMotion();
  const btnRef = useRef(null);
  const [box, setBox] = useState(null); // {w, h} frozen at activation
  const [arcDone, setArcDone] = useState(false);
  const phaseRef = useRef(phase);
  phaseRef.current = phase;
  const cbRef = useRef(onSuccessAnimationComplete);
  cbRef.current = onSuccessAnimationComplete;
  const mounted = useRef(true);
  // Set on every mount: StrictMode mounts, unmounts and remounts once in development.
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  useEffect(() => { onPhaseChange?.(phase); }, [phase]); // eslint-disable-line react-hooks/exhaustive-deps

  const activate = useCallback(async () => {
    if (!enabled || isLocked(phaseRef.current) || !run) return;
    const r = btnRef.current?.getBoundingClientRect();
    setBox(r ? { w: r.width, h: r.height } : null);
    setArcDone(false);
    phaseRef.current = 'pending'; // re-entry guard before React re-renders
    dispatch({ type: 'start' });
    const res = await runOperation(run);
    if (!mounted.current) return;
    dispatch({ type: 'resolve', ok: res.ok, error: res.error });
    if (!res.ok) onFailure?.(res.error);
  }, [enabled, run, onFailure]);

  // Failure: back to the original shape and label on the next frame; focus never left the button.
  useEffect(() => {
    if (phase !== 'failure') return undefined;
    const id = requestAnimationFrame(() => dispatch({ type: 'reset' }));
    return () => cancelAnimationFrame(id);
  }, [phase]);
  // Release the frozen width once the shape has come back.
  useEffect(() => {
    if (phase !== 'idle' || !box) return undefined;
    const t = setTimeout(() => setBox(null), reduce ? 0 : 340);
    return () => clearTimeout(t);
  }, [phase, box, reduce]);
  // Reduced motion has no spin to finish.
  useEffect(() => { if (phase === 'success' && reduce) setArcDone(true); }, [phase, reduce]);

  const finishCheck = useCallback(() => {
    if (phaseRef.current !== 'success') return;
    const go = () => {
      if (!mounted.current || phaseRef.current !== 'success') return;
      phaseRef.current = 'completed';
      dispatch({ type: 'animDone' });
      cbRef.current?.();
    };
    if (successHoldMs > 0) setTimeout(go, successHoldMs); else go();
  }, [successHoldMs]);
  // Safety net only: if the browser never delivers animationend (hidden tab, display:none), don't strand the user.
  useEffect(() => {
    if (phase !== 'success' || !arcDone) return undefined;
    const t = setTimeout(finishCheck, 1200);
    return () => clearTimeout(t);
  }, [phase, arcDone, finishCheck]);
  useEffect(() => {
    if (phase !== 'success') return undefined;
    const t = setTimeout(() => setArcDone(true), 1000); // spinner never iterated (e.g. animations off)
    return () => clearTimeout(t);
  }, [phase]);
  useEffect(() => {
    if (phase !== 'completed' || !resetAfterSuccess) return undefined;
    const t = setTimeout(() => mounted.current && dispatch({ type: 'reset' }), 700);
    return () => clearTimeout(t);
  }, [phase, resetAfterSuccess]);

  const morphed = !reduce && box && phase !== 'idle' && phase !== 'failure';
  const showSpinner = phase === 'pending' || (phase === 'success' && !arcDone);
  const showCheck = (phase === 'success' && arcDone) || phase === 'completed';
  const look = (LOOKS[variant] || LOOKS.primary)();
  // Disabled (only while idle): the shared "not yet" look, same as InkButton / Button.
  if (!enabled && phase === 'idle') Object.assign(look, { background: 'rgba(var(--bb-fg-rgb), 0.16)', color: ink, boxShadow: 'none', border: 'none', textShadow: 'none' });
  const sizeStyle = box
    ? { width: morphed ? box.h : box.w, height: box.h, ...(morphed ? { borderRadius: box.h / 2, paddingLeft: 0, paddingRight: 0 } : {}) }
    : { width: '100%' };
  const live = phase === 'pending' ? (pendingLabel || '') : (phase === 'success' || phase === 'completed') && !successNeutral ? (successLabel || '') : '';

  useLayoutEffect(() => { if (phase === 'failure') btnRef.current?.focus?.({ preventScroll: true }); }, [phase]);

  return (
    <div style={{ display: 'flex', justifyContent: 'center', width: '100%', ...wrapStyle }}>
      <button
        ref={btnRef} type="button" data-testid={testId} data-phase={phase}
        className="bb-press bb-async"
        aria-label={ariaLabel || (typeof label === 'string' ? label : undefined)}
        aria-busy={phase === 'pending' || undefined}
        aria-disabled={!enabled || isLocked(phase) || undefined}
        disabled={!enabled && phase === 'idle'}
        onClick={activate}
        style={{
          ...look, fontFamily: 'inherit', minHeight: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          boxSizing: 'border-box', cursor: enabled && !isLocked(phase) ? 'pointer' : 'default', ...style, ...sizeStyle,
        }}>
        <span className="bb-async-label" style={{ opacity: phase === 'idle' || phase === 'failure' ? 1 : 0, whiteSpace: 'nowrap' }}>{label}</span>
        {showSpinner && (
          <span className="bb-async-glyph" aria-hidden="true">
            <svg className="bb-async-spinner" width="22" height="22" viewBox="0 0 22 22"
              onAnimationIteration={e => { if (e.animationName === 'bb-async-spin' && phaseRef.current === 'success') setArcDone(true); }}>
              <circle cx="11" cy="11" r="9" fill="none" stroke="currentColor" strokeOpacity="0.25" strokeWidth="2.4" />
              <path d="M11 2 a9 9 0 0 1 9 9" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
            </svg>
          </span>
        )}
        {showCheck && (
          <span className="bb-async-glyph" aria-hidden="true" data-testid={testId ? `${testId}-check` : undefined}>
            <svg className="bb-async-check" width="22" height="22" viewBox="0 0 22 22"
              onAnimationEnd={e => { if (e.animationName === 'bb-async-draw' || e.animationName === 'bb-async-fade') finishCheck(); }}>
              <path d="M5 11.5 l4 4 l8 -9" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
        )}
      </button>
      <span className="bb-sr-only" aria-live="polite" role="status">{live}</span>
    </div>
  );
}

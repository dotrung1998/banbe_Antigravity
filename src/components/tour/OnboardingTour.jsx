// Onboarding Version 3 (note 64): a guided tour over the REAL app. iOS twin: Views/OnboardingTourOverlay.swift +
// State/OnboardingTourController.swift. Steps: src/data/onboardingTour.js.
//
// Non-mutating by construction:
// - The app root gets `inert` while the tour runs, so nothing underneath can be clicked, focused or read by a screen
//   reader; the overlay lives in a portal outside it and is the only thing that takes input.
// - A step change only sets `screen` (home / profile). It never activates the highlighted control.
// - Analytics are paused and Home's For You alert stops observing (s.tourActive) for the duration.
// - Only completion is persisted: banbe.tour.v3.done.<uid>. A Help & Legal replay never reads or writes it.
//
// Starts (first run): onboarding Version 3 is on, the account has no marker, no gate / policy / personalization is
// up, Home is showing, and either the sign-in reveal just ended or the personalization flow just landed on Home.
import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { useAccountGate } from '../../lib/accountGate.js';
import { useEventOnboardingActive } from '../../screens/EventOnboarding.jsx';
import { onboardingVersion } from '../../lib/featureFlags.js';
import { setAnalyticsPaused } from '../../lib/analytics.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';
import { eligibleSteps, WEB_TARGETS, tourDoneKey } from '../../data/onboardingTour.js';
import { paper, ink, display } from '../../theme.js';

const WAIT_MS = 1500;
const PAD = 6;
const TOUR_SCREENS = new Set(['home', 'profile']);

const readDone = uid => { try { return !!localStorage.getItem(tourDoneKey(uid)); } catch { return false; } };
const writeDone = uid => { try { localStorage.setItem(tourDoneKey(uid), new Date().toISOString()); } catch { /* private mode */ } };
const findTarget = id => {
  const sel = WEB_TARGETS[id];
  if (!sel) return null;
  const el = document.querySelector(sel);
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0 ? el : null;
};

export default function OnboardingTour() {
  const { state: s, set, T } = useBanBe();
  const gate = useAccountGate();
  const eventOnboardingActive = useEventOnboardingActive();
  const reduce = useReducedMotion();
  // run: { replay, steps, index, dir, missing:Set }
  const [run, setRun] = useState(null);
  const [rect, setRect] = useState(null);
  const restoreFocus = useRef(null);
  const titleRef = useRef(null);
  const cardRef = useRef(null);
  const pendingStart = useRef(0);

  const start = useCallback(({ replay }) => {
    const steps = eligibleSteps({ organizerMode: !!s.organizerMode });
    if (!steps.length) return;
    restoreFocus.current = document.activeElement;
    setRect(null);
    setRun({ replay, steps, index: 0, dir: 1, missing: new Set() });
  }, [s.organizerMode]);

  const end = useCallback((completed) => {
    setRun(r => {
      if (r && completed && !r.replay && s.user?.id) writeDone(s.user.id);
      return null;
    });
    setRect(null);
    set({ screen: 'home', homeScrollTopToken: Date.now() });
    const el = restoreFocus.current;
    restoreFocus.current = null;
    setTimeout(() => { if (el && document.contains(el)) el.focus?.({ preventScroll: true }); }, 0);
  }, [set, s.user?.id]);

  // ---- entry points ----
  useEffect(() => { if (s.tourAutoStartToken) pendingStart.current = Date.now(); }, [s.tourAutoStartToken]);
  useEffect(() => {
    if (run || !pendingStart.current || Date.now() - pendingStart.current > 4000) return;
    if (onboardingVersion(s.featureFlags) !== 3 || !s.user?.id || readDone(s.user.id)) { pendingStart.current = 0; return; }
    if (gate.blocking || eventOnboardingActive || s.policyGateActive || s.screen !== 'home') return;
    pendingStart.current = 0;
    start({ replay: false });
  }, [run, s.tourAutoStartToken, s.featureFlags, s.user?.id, gate.blocking, eventOnboardingActive, s.policyGateActive, s.screen, start]);
  useEffect(() => {
    if (s.tourReplayRequest && s.user) start({ replay: true });
  }, [s.tourReplayRequest]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- active-tour side effects: inert app, paused analytics, shared flag for Home ----
  const active = !!run;
  useEffect(() => {
    if (!active) return undefined;
    const root = document.getElementById('root');
    root?.setAttribute('inert', '');
    setAnalyticsPaused(true);
    set({ tourActive: true });
    return () => { root?.removeAttribute('inert'); setAnalyticsPaused(false); set({ tourActive: false }); };
  }, [active, set]);

  // Abort (no marker) when something more important takes over: a gate, personalization, sign-out, a deep link.
  useEffect(() => {
    if (!run) return;
    if (!s.user || gate.blocking || eventOnboardingActive || s.policyGateActive || !TOUR_SCREENS.has(s.screen)) {
      setRun(null); setRect(null);
    }
  }, [run, s.user, gate.blocking, eventOnboardingActive, s.policyGateActive, s.screen]);

  // ---- step: go to its screen, wait for the target, then follow it every frame ----
  const step = run ? run.steps[run.index] : null;
  useEffect(() => {
    if (!run || !step) return undefined;
    if (s.screen !== step.screen) { set({ screen: step.screen }); return undefined; }
    let raf = 0; let cancelled = false; let el = null; let last = '';
    const t0 = performance.now();
    const skip = () => setRun(r => {
      if (!r) return r;
      const missing = new Set(r.missing); missing.add(r.index);
      let i = r.index + r.dir;
      while (i >= 0 && i < r.steps.length && missing.has(i)) i += r.dir;
      if (i < 0) { i = r.index + 1; while (i < r.steps.length && missing.has(i)) i += 1; }
      if (i >= r.steps.length) { setTimeout(() => end(true), 0); return { ...r, missing }; }
      return { ...r, missing, index: i };
    });
    const tick = () => {
      if (cancelled) return;
      if (!el || !document.contains(el)) {
        el = findTarget(step.target);
        if (!el) {
          if (performance.now() - t0 > WAIT_MS) { skip(); return; }
          raf = requestAnimationFrame(tick); return;
        }
        const r0 = el.getBoundingClientRect();
        if (r0.top < 0 || r0.bottom > window.innerHeight) el.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' });
      }
      const r = el.getBoundingClientRect();
      const key = `${Math.round(r.left)},${Math.round(r.top)},${Math.round(r.width)},${Math.round(r.height)}`;
      if (key !== last) { last = key; setRect({ left: r.left, top: r.top, width: r.width, height: r.height }); }
      raf = requestAnimationFrame(tick);
    };
    setRect(null);
    raf = requestAnimationFrame(tick);
    return () => { cancelled = true; cancelAnimationFrame(raf); };
  }, [run?.index, run?.steps, step, s.screen]); // eslint-disable-line react-hooks/exhaustive-deps

  // Focus the step title each time a step lands (screen readers hear the new step).
  const landed = !!rect;
  useEffect(() => { if (landed) titleRef.current?.focus({ preventScroll: true }); }, [run?.index, landed]);

  const goTo = useCallback((i) => setRun(r => (r && i >= 0 && i < r.steps.length && !r.missing.has(i) ? { ...r, index: i, dir: i >= r.index ? 1 : -1 } : r)), []);
  const next = useCallback(() => {
    if (!run) return;
    let i = run.index + 1;
    while (i < run.steps.length && run.missing.has(i)) i += 1;
    if (i >= run.steps.length) end(true); else setRun(r => ({ ...r, index: i, dir: 1 }));
  }, [run, end]);
  const back = useCallback(() => {
    if (!run) return;
    let i = run.index - 1;
    while (i >= 0 && run.missing.has(i)) i -= 1;
    if (i >= 0) setRun(r => ({ ...r, index: i, dir: -1 }));
  }, [run]);
  const skipAll = useCallback(() => end(true), [end]);

  // Keyboard: Escape = Skip, Tab stays inside the card, arrows step.
  useEffect(() => {
    if (!run) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); skipAll(); return; }
      if (e.key === 'Tab') {
        const items = [...(cardRef.current?.querySelectorAll('button:not([disabled]), [tabindex="-1"]') || [])].filter(x => x.tagName === 'BUTTON');
        if (!items.length) return;
        const first = items[0], lastEl = items[items.length - 1];
        if (e.shiftKey && (document.activeElement === first || !cardRef.current.contains(document.activeElement))) { e.preventDefault(); lastEl.focus(); }
        else if (!e.shiftKey && (document.activeElement === lastEl || !cardRef.current.contains(document.activeElement))) { e.preventDefault(); first.focus(); }
      }
    };
    document.addEventListener('keydown', onKey, true);
    return () => document.removeEventListener('keydown', onKey, true);
  }, [run, skipAll]);

  if (!run || !step) return null;
  const n = run.steps.length;
  const lang = s.lang === 'en' ? 'en' : 'vi';
  const [title, body] = step[lang];
  const isLast = (() => { let i = run.index + 1; while (i < n && run.missing.has(i)) i += 1; return i >= n; })();
  const isFirst = (() => { let i = run.index - 1; while (i >= 0 && run.missing.has(i)) i -= 1; return i < 0; })();

  const vw = window.innerWidth, vh = window.innerHeight;
  const cardW = Math.min(340, vw - 32);
  let cardStyle = { left: Math.max(16, (vw - cardW) / 2) };
  if (rect) {
    const cx = rect.left + rect.width / 2;
    cardStyle.left = Math.min(Math.max(16, cx - cardW / 2), vw - cardW - 16);
    const below = step.placement === 'below' ? rect.top + rect.height < vh * 0.62 : rect.top < vh * 0.38;
    if (below) cardStyle.top = Math.min(rect.top + rect.height + PAD + 12, vh - 220);
    else cardStyle.bottom = Math.max(16, vh - rect.top + PAD + 12);
  } else {
    cardStyle.top = vh * 0.35;
  }
  const hole = rect && { x: rect.left - PAD, y: rect.top - PAD, w: rect.width + PAD * 2, h: rect.height + PAD * 2 };
  const ease = reduce ? 'none' : 'all .28s cubic-bezier(.22,1,.36,1)';

  return createPortal(
    <div data-testid="tour-overlay" data-step={step.id} data-index={run.index} data-replay={run.replay || undefined}
      style={{ position: 'fixed', inset: 0, zIndex: 3000 }}>
      {/* Scrim with a cut-out around the real control. It swallows every pointer event: the control is never pressed. */}
      <svg aria-hidden="true" width={vw} height={vh} style={{ position: 'absolute', inset: 0 }} onClick={e => e.stopPropagation()}>
        <defs>
          <mask id="bb-tour-mask">
            <rect x="0" y="0" width={vw} height={vh} fill="white" />
            {hole && <rect x={hole.x} y={hole.y} width={hole.w} height={hole.h} rx="16" fill="black" />}
          </mask>
        </defs>
        <rect x="0" y="0" width={vw} height={vh} fill="rgba(20,18,14,0.58)" mask="url(#bb-tour-mask)" />
      </svg>
      {hole && (
        <div aria-hidden="true" data-testid="tour-highlight"
          style={{ position: 'absolute', left: hole.x, top: hole.y, width: hole.w, height: hole.h, borderRadius: 16,
            boxShadow: '0 0 0 2px var(--bb-clay, #C2683F), 0 0 0 6px rgba(194,104,63,0.25)', transition: ease, pointerEvents: 'none' }} />
      )}
      <div ref={cardRef} role="dialog" aria-modal="true" aria-labelledby="tour-title" aria-describedby="tour-body" data-testid="tour-card"
        style={{ position: 'absolute', width: cardW, boxSizing: 'border-box', padding: '16px 16px 14px', borderRadius: 20, background: paper, color: ink,
          boxShadow: '0 18px 44px rgba(20,18,14,0.35)', transition: ease, ...cardStyle }}>
        <div style={{ fontSize: 12, fontWeight: 600, opacity: 0.6 }} aria-hidden="true">{T(`Bước ${run.index + 1}/${n}`, `Step ${run.index + 1} of ${n}`)}</div>
        <h2 id="tour-title" ref={titleRef} tabIndex={-1} data-testid="tour-title" style={{ ...display(20, { margin: '4px 0 0', outline: 'none' }) }}>
          <span className="bb-sr-only">{T(`Bước ${run.index + 1}/${n}: `, `Step ${run.index + 1} of ${n}: `)}</span>{title}
        </h2>
        <p id="tour-body" data-testid="tour-body" style={{ fontSize: 14, lineHeight: 1.5, margin: '6px 0 0' }}>{body}</p>
        <div role="group" aria-label={T('Các bước', 'Steps')} style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
          {run.steps.map((st, i) => {
            const missing = run.missing.has(i);
            const current = i === run.index;
            return (
              <button key={st.id} type="button" data-testid={`tour-step-${i + 1}`} disabled={missing}
                aria-current={current ? 'step' : undefined}
                aria-label={T(`Bước ${i + 1}/${n}: ${st.short[0]}`, `Step ${i + 1} of ${n}: ${st.short[1]}`)}
                onClick={() => goTo(i)}
                style={{ width: 32, height: 32, minWidth: 32, borderRadius: 999, border: current ? 'none' : '1px solid var(--bb-rule)', fontFamily: 'inherit',
                  fontSize: 13, fontWeight: 700, cursor: missing ? 'default' : 'pointer', opacity: missing ? 0.35 : 1,
                  background: current ? ink : 'var(--bb-field)', color: current ? paper : ink }}>
                {i + 1}
              </button>
            );
          })}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 14 }}>
          <button type="button" data-testid="tour-skip" onClick={skipAll}
            style={{ minHeight: 44, padding: '0 10px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, opacity: 0.75, cursor: 'pointer' }}>
            {T('Bỏ qua', 'Skip')}
          </button>
          <span style={{ flex: 1 }} />
          <button type="button" data-testid="tour-back" onClick={back} disabled={isFirst}
            style={{ minHeight: 44, padding: '0 16px', borderRadius: 999, border: '1px solid var(--bb-rule)', background: 'var(--bb-field)', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, opacity: isFirst ? 0.4 : 1, cursor: isFirst ? 'default' : 'pointer' }}>
            {T('Quay lại', 'Back')}
          </button>
          <button type="button" data-testid="tour-next" onClick={next}
            style={{ minHeight: 44, padding: '0 18px', borderRadius: 999, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
            {isLast ? T('Xong', 'Done') : T('Tiếp', 'Next')}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}

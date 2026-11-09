// The guided tour over the REAL app (note 64), forward-only chapters since onboarding v5 (note 80). iOS twin:
// Views/OnboardingTourOverlay.swift + State/OnboardingTourController.swift. Steps and chapters: src/data/onboardingTour.js.
//
// Non-mutating by construction:
// - The app root gets `inert` while the tour runs, so nothing underneath can be clicked, focused or read by a screen
//   reader; the overlay lives in a portal outside it and is the only thing that takes input.
// - A step change only sets `screen` (home / profile). It never activates the highlighted control. A "do it" step
//   runs that control's own action from here (a click inside the highlight, or the card's button).
// - Analytics are paused and Home's For You alert stops observing (s.tourActive) for the duration.
// - Only completion is persisted: banbe.tour.v3.done.<uid>. A Help & Legal replay never reads or writes it.
//
// No Back and no jumpable step numbers: the progress bar only shows where you are. Stopping happens at a chapter
// break or with End tour.
//
// Starts: the onboarding recap's "Start the tour" (any version), or (first run, Version 3) the sign-in reveal ended or
// personalization landed on Home without a recap; replays come from Help & Legal.
import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { useAccountGate } from '../../lib/accountGate.js';
import { useEventOnboardingActive } from '../../screens/EventOnboarding.jsx';
import { onboardingVersion, flagOn } from '../../lib/featureFlags.js';
import { setAnalyticsPaused } from '../../lib/analytics.js';
import { useReducedMotion } from '../../lib/useReducedMotion.js';
import { tourPlan, WEB_TARGETS, tourDoneKey, TOUR_DO_IT, HOSTING_ON_COPY } from '../../data/onboardingTour.js';
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

/** Index of the chapter holding step `i`. */
const chapterOf = (run, i) => Math.max(0, run.chapters.findIndex(c => i >= c.from && i < c.to));

/** Next step in this chapter, else the chapter break, else the closing sheet. Never goes back. */
function advance(r) {
  const c = r.chapters[chapterOf(r, r.index)];
  let i = r.index + 1;
  while (i < c.to && r.missing.has(i)) i += 1;
  if (i < c.to) return { ...r, index: i };
  return { ...r, phase: chapterOf(r, r.index) + 1 < r.chapters.length ? 'chapterDone' : 'finished' };
}

export default function OnboardingTour() {
  const { state: s, set, T, toggleHomeFilter } = useBanBe();
  const gate = useAccountGate();
  const eventOnboardingActive = useEventOnboardingActive();
  const reduce = useReducedMotion();
  // run: { replay, steps, chapters: [{ id, name, from, to }], index, phase: 'step'|'chapterDone'|'finished', missing:Set }
  const [run, setRun] = useState(null);
  const [rect, setRect] = useState(null);
  const restoreFocus = useRef(null);
  const titleRef = useRef(null);
  const cardRef = useRef(null);
  const pendingStart = useRef(0);
  const pendingRecap = useRef(0);

  const start = useCallback(({ replay }) => {
    const plan = tourPlan({ organizerMode: !!s.organizerMode, simpleShell: flagOn(s.featureFlags, 'simple_shell') });
    if (!plan.length) return;
    const steps = [];
    const chapters = plan.map(({ chapter, steps: st }) => {
      const from = steps.length;
      steps.push(...st);
      return { id: chapter.id, name: chapter.name, from, to: steps.length };
    });
    restoreFocus.current = document.activeElement;
    setRect(null);
    setRun({ replay, steps, chapters, index: 0, phase: 'step', missing: new Set() });
  }, [s.organizerMode, s.featureFlags]);

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
  useEffect(() => { if (s.tourRecapStartToken) pendingRecap.current = Date.now(); }, [s.tourRecapStartToken]);
  useEffect(() => {
    if (run) return;
    const blocked = gate.blocking || eventOnboardingActive || s.policyGateActive || s.screen !== 'home';
    // The recap's "Start the tour": the person asked for it, so no version switch or marker check applies.
    if (pendingRecap.current && Date.now() - pendingRecap.current <= 4000) {
      if (!s.user?.id) { pendingRecap.current = 0; return; }
      if (blocked) return;
      pendingRecap.current = 0;
      start({ replay: false });
      return;
    }
    if (!pendingStart.current || Date.now() - pendingStart.current > 4000) return;
    if (onboardingVersion(s.featureFlags) !== 3 || !s.user?.id || readDone(s.user.id)) { pendingStart.current = 0; return; }
    if (blocked) return;
    pendingStart.current = 0;
    start({ replay: false });
  }, [run, s.tourAutoStartToken, s.tourRecapStartToken, s.featureFlags, s.user?.id, gate.blocking, eventOnboardingActive, s.policyGateActive, s.screen, start]);
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
  const onStep = run?.phase === 'step';
  const step = run && onStep ? run.steps[run.index] : null;
  useEffect(() => {
    if (!run || !step) return undefined;
    if (s.screen !== step.screen) { set({ screen: step.screen }); return undefined; }
    let raf = 0; let cancelled = false; let el = null; let last = '';
    const t0 = performance.now();
    // A target that never showed up is skipped, forward only.
    const skip = () => setRun(r => (r ? advance({ ...r, missing: new Set([...r.missing, r.index]) }) : r));
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
  }, [run?.index, run?.phase, run?.steps, step, s.screen]); // eslint-disable-line react-hooks/exhaustive-deps

  // Focus the title each time a step or sheet lands (screen readers hear it).
  const landed = !!rect || (run && !onStep);
  useEffect(() => { if (landed) titleRef.current?.focus({ preventScroll: true }); }, [run?.index, run?.phase, landed]);

  const next = useCallback(() => setRun(r => (r && r.phase === 'step' ? advance(r) : r)), []);
  const continueChapter = useCallback(() => setRun(r => {
    if (!r || r.phase !== 'chapterDone') return r;
    const c = r.chapters[chapterOf(r, r.index) + 1];
    return c ? { ...r, phase: 'step', index: c.from } : r;
  }), []);
  const doIt = step ? TOUR_DO_IT[step.id] : null;
  // A "do it" step: run what the highlighted control does, from here, then move on.
  const performDoIt = useCallback(() => {
    if (!run || run.phase !== 'step') return;
    const st = run.steps[run.index];
    if (!TOUR_DO_IT[st.id]) return;
    if (st.id === 'home.forYou' && !s.filterForYou) toggleHomeFilter('forYou');
    next();
  }, [run, s.filterForYou, toggleHomeFilter, next]);
  const endTour = useCallback(() => end(true), [end]);

  // Keyboard: Escape = End tour, Tab stays inside the card or sheet.
  useEffect(() => {
    if (!run) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); endTour(); return; }
      if (e.key === 'Tab') {
        const items = [...(cardRef.current?.querySelectorAll('button:not([disabled])') || [])];
        if (!items.length) return;
        const first = items[0], lastEl = items[items.length - 1];
        if (e.shiftKey && (document.activeElement === first || !cardRef.current.contains(document.activeElement))) { e.preventDefault(); lastEl.focus(); }
        else if (!e.shiftKey && (document.activeElement === lastEl || !cardRef.current.contains(document.activeElement))) { e.preventDefault(); first.focus(); }
      }
    };
    document.addEventListener('keydown', onKey, true);
    return () => document.removeEventListener('keydown', onKey, true);
  }, [run, endTour]);

  if (!run) return null;
  const lang = s.lang === 'en' ? 1 : 0;
  const L = (pair) => pair[lang];
  const vw = window.innerWidth, vh = window.innerHeight;
  const ease = reduce ? 'none' : 'all .28s cubic-bezier(.22,1,.36,1)';
  const ci = chapterOf(run, run.index);
  const chapter = run.chapters[ci];

  const scrim = (hole) => (
    <svg aria-hidden="true" width={vw} height={vh} style={{ position: 'absolute', inset: 0 }}
      onClick={(e) => {
        e.stopPropagation();
        // Only a "do it" step reacts, and only to a click inside its highlight.
        if (doIt && hole && e.clientX >= hole.x && e.clientX <= hole.x + hole.w && e.clientY >= hole.y && e.clientY <= hole.y + hole.h) performDoIt();
      }}>
      <defs>
        <mask id="bb-tour-mask">
          <rect x="0" y="0" width={vw} height={vh} fill="white" />
          {hole && <rect x={hole.x} y={hole.y} width={hole.w} height={hole.h} rx="16" fill="black" />}
        </mask>
      </defs>
      <rect x="0" y="0" width={vw} height={vh} fill="rgba(20,18,14,0.62)" mask="url(#bb-tour-mask)" />
    </svg>
  );

  // ---- chapter break / closing sheet ----
  if (!onStep) {
    const finished = run.phase === 'finished';
    const nx = run.chapters[ci + 1];
    const sheetBtn = (testId, label, onClick, primary) => (
      <button type="button" data-testid={testId} onClick={onClick}
        style={{ width: '100%', minHeight: primary ? 50 : 44, borderRadius: 18, border: 'none', fontFamily: 'inherit', cursor: 'pointer',
          fontSize: primary ? 15 : 14, fontWeight: primary ? 700 : 600, background: primary ? ink : 'none', color: primary ? paper : ink, opacity: primary ? 1 : 0.75, marginTop: primary ? 0 : 4 }}>
        {label}
      </button>
    );
    return createPortal(
      <div data-testid="tour-overlay" data-phase={run.phase} data-replay={run.replay || undefined} style={{ position: 'fixed', inset: 0, zIndex: 3000 }}>
        {scrim(null)}
        <div ref={cardRef} role="dialog" aria-modal="true" aria-labelledby="tour-title" data-testid={finished ? 'tour-finish' : 'tour-break'}
          style={{ position: 'absolute', left: 0, right: 0, bottom: 0, margin: '0 auto', maxWidth: 480, boxSizing: 'border-box', padding: '10px 20px 30px',
            borderRadius: '26px 26px 0 0', background: paper, color: ink, animation: reduce ? 'none' : 'bbTourUp .32s cubic-bezier(.22,.61,.36,1) both' }}>
          <div aria-hidden style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(var(--bb-fg-rgb), 0.2)', margin: '0 auto 12px' }} />
          <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.12em', textTransform: 'uppercase', opacity: 0.6 }}>
            {finished ? T('Xong hướng dẫn', 'Tour complete') : T(`Xong chương ${ci + 1}`, `Chapter ${ci + 1} done`)}
          </div>
          <h2 id="tour-title" ref={titleRef} tabIndex={-1} data-testid="tour-sheet-title" style={display(26, { margin: '6px 0 0', outline: 'none', fontWeight: 300 })}>
            {finished ? T('Đó là banbe', "That's banbe") : T(`Tiếp theo: ${L(nx.name).toLowerCase()}`, `Next: ${L(nx.name).toLowerCase()}`)}
          </h2>
          {finished ? (
            <p style={{ fontSize: 14, lineHeight: 1.55, opacity: 0.8, margin: '8px 0 18px' }}>
              {T('Bạn đã biết cách tìm sự kiện, nơi có lịch và tin nhắn, và chỗ đổi mọi lựa chọn lúc thiết lập. Xem lại bất cứ lúc nào trong Tài khoản › Trợ giúp.',
                "You've seen how to find an event, where your plans and messages live, and where every choice from setup can be changed. Replay it any time from Account › Help.")}
            </p>
          ) : (
            <div style={{ margin: '14px 0 18px' }}>
              {run.chapters.map((c, i) => {
                const st = i <= ci ? 'done' : i === ci + 1 ? 'cur' : 'later';
                const n = c.to - c.from;
                return (
                  <div key={c.id} data-testid={`tour-chapter-${c.id}`} data-state={st}
                    style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '12px 0', borderBottom: '1px solid var(--bb-rule)', fontSize: 15, fontWeight: st === 'cur' ? 600 : 400, opacity: st === 'later' ? 0.6 : 1 }}>
                    <span aria-hidden style={{ width: 26, height: 26, borderRadius: 13, flex: 'none', display: 'grid', placeItems: 'center', fontSize: 12, fontWeight: 700,
                      border: `1.5px solid ${st === 'cur' ? ink : 'var(--bb-rule)'}`, background: st === 'done' ? ink : 'transparent', color: st === 'done' ? paper : ink }}>
                      {st === 'done' ? '✓' : i + 1}
                    </span>
                    <span style={{ flex: 1 }}>{L(c.name)}</span>
                    <small style={{ fontSize: 12, opacity: 0.6, fontWeight: 400 }}>{T(`${n} bước`, `${n} ${n === 1 ? 'step' : 'steps'}`)}</small>
                  </div>
                );
              })}
            </div>
          )}
          {finished
            ? sheetBtn('tour-finish-done', T('Khám phá banbe', 'Explore banbe'), endTour, true)
            : (
              <>
                {sheetBtn('tour-break-continue', T(`Tiếp tục, ${nx.to - nx.from} bước`, `Continue, ${nx.to - nx.from} ${nx.to - nx.from === 1 ? 'step' : 'steps'}`), continueChapter, true)}
                {sheetBtn('tour-break-stop', T('Dừng ở đây', 'Finish for now'), endTour, false)}
              </>
            )}
        </div>
      </div>,
      document.body,
    );
  }

  // ---- step card ----
  const useHostingOn = step.id === 'account.organizerMode' && s.organizerMode && !flagOn(s.featureFlags, 'simple_shell');
  const [title, body] = useHostingOn ? (lang ? HOSTING_ON_COPY.en : HOSTING_ON_COPY.vi) : (lang ? step.en : step.vi);
  const stepInChapter = run.index - chapter.from + 1;
  const chapterSteps = chapter.to - chapter.from;
  const lastInChapter = (() => { let i = run.index + 1; while (i < chapter.to && run.missing.has(i)) i += 1; return i >= chapter.to; })();
  const total = run.steps.length;

  const cardW = Math.min(360, vw - 24);
  const cardStyle = { left: Math.max(12, (vw - cardW) / 2) };
  if (rect) {
    const cx = rect.left + rect.width / 2;
    cardStyle.left = Math.min(Math.max(12, cx - cardW / 2), vw - cardW - 12);
    const below = step.placement === 'below' ? rect.top + rect.height < vh * 0.62 : rect.top < vh * 0.38;
    if (below) cardStyle.top = Math.min(rect.top + rect.height + PAD + 12, vh - 250);
    else cardStyle.bottom = Math.max(16, vh - rect.top + PAD + 12);
  } else {
    cardStyle.top = vh * 0.35;
  }
  const hole = rect && { x: rect.left - PAD, y: rect.top - PAD, w: rect.width + PAD * 2, h: rect.height + PAD * 2 };

  return createPortal(
    <div data-testid="tour-overlay" data-phase="step" data-step={step.id} data-index={run.index} data-replay={run.replay || undefined}
      style={{ position: 'fixed', inset: 0, zIndex: 3000 }}>
      {/* Scrim with a cut-out around the real control. It swallows every pointer event: the control is never pressed. */}
      {scrim(hole)}
      {hole && (
        <div aria-hidden="true" data-testid="tour-highlight"
          style={{ position: 'absolute', left: hole.x, top: hole.y, width: hole.w, height: hole.h, borderRadius: 16,
            boxShadow: '0 0 0 2px var(--bb-clay, #C2683F), 0 0 0 6px rgba(194,104,63,0.25)', transition: ease, pointerEvents: 'none' }}>
          {doIt && !reduce && (
            <span style={{ position: 'absolute', inset: -6, borderRadius: 'inherit', border: '2px solid #fff', animation: 'bbTourRing 1.4s ease-out infinite' }} />
          )}
        </div>
      )}
      <div ref={cardRef} role="dialog" aria-modal="true" aria-labelledby="tour-title" aria-describedby="tour-body" data-testid="tour-card"
        style={{ position: 'absolute', width: cardW, boxSizing: 'border-box', padding: '16px 18px 14px', borderRadius: 22, background: paper, color: ink,
          boxShadow: '0 18px 50px rgba(20,18,14,0.35)', transition: ease, ...cardStyle }}>
        <div data-testid="tour-chapter" style={{ display: 'flex', alignItems: 'baseline', gap: 8, fontSize: 11, fontWeight: 600, letterSpacing: '.1em', textTransform: 'uppercase', opacity: 0.6 }}>
          <span style={{ flex: 1, minWidth: 0 }}>{T(`Chương ${ci + 1}/${run.chapters.length} · ${L(chapter.name)}`, `Chapter ${ci + 1} of ${run.chapters.length} · ${L(chapter.name)}`)}</span>
          <span style={{ flex: 'none', whiteSpace: 'nowrap' }}>{T(`${stepInChapter}/${chapterSteps}`, `${stepInChapter} of ${chapterSteps}`)}</span>
        </div>
        <h2 id="tour-title" ref={titleRef} tabIndex={-1} data-testid="tour-title" style={{ ...display(22, { margin: '8px 0 0', outline: 'none', fontWeight: 300 }) }}>{title}</h2>
        <p id="tour-body" data-testid="tour-body" style={{ fontSize: 14, lineHeight: 1.5, margin: '6px 0 0', opacity: 0.8 }}>{body}</p>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 14 }}>
          {doIt ? (
            <button type="button" data-testid="tour-do-it" onClick={performDoIt}
              style={{ flex: 1, minHeight: 44, display: 'flex', alignItems: 'center', gap: 8, border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer', textAlign: 'left', padding: 0 }}>
              <span aria-hidden>↗</span>{T(`${doIt[0]} để tiếp tục`, `${doIt[1]} to continue`)}
            </button>
          ) : (
            <button type="button" data-testid="tour-next" onClick={next}
              style={{ flex: 1, minHeight: 44, borderRadius: 999, border: 'none', background: ink, color: paper, fontFamily: 'inherit', fontSize: 15, fontWeight: 700, cursor: 'pointer' }}>
              {lastInChapter ? T('Xong chương này', 'Finish chapter') : T('Tiếp', 'Next')}
            </button>
          )}
          <button type="button" data-testid="tour-end" onClick={endTour}
            style={{ minHeight: 44, padding: '0 8px', border: 'none', background: 'none', color: ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600, opacity: 0.7, cursor: 'pointer', whiteSpace: 'nowrap' }}>
            {T('Kết thúc', 'End tour')}
          </button>
        </div>
        {/* One bar per step, a gap between chapters. Read-only: it shows where you are, it can't be used to jump. */}
        <div data-testid="tour-progress" role="progressbar" aria-valuemin={1} aria-valuemax={total} aria-valuenow={run.index + 1}
          aria-label={T(`Tiến độ: bước ${run.index + 1}/${total}`, `Tour progress, step ${run.index + 1} of ${total}`)}
          style={{ display: 'flex', gap: 3, marginTop: 12 }}>
          {run.steps.map((st, i) => (
            <i key={st.id} style={{ flex: 1, height: 3, borderRadius: 2, background: i <= run.index ? ink : 'var(--bb-rule)',
              marginLeft: run.chapters.some(c => c.from === i && i > 0) ? 7 : 0 }} />
          ))}
        </div>
      </div>
    </div>,
    document.body,
  );
}

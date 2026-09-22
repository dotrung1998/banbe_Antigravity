import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, display } from '../../theme.js';
import { bg } from '../../data/events.js';

// Task 3.4 (07-notifications.md) — the story progression viewer. A
// deliberately SEPARATE component/state from PhotoViewer.jsx and
// ChatPhotoViewer.jsx (14-photo-viewer.md's own instruction not to conflate
// origin/back semantics across viewer kinds) even though it reuses the same
// blurred-fullscreen visual language and, as of this pass, the same
// live-drag-follow / hold-to-pause CONVENTIONS ChatPhotoViewer established
// (b75b884) — not its component/state, per that same instruction.
//
// BUG 5 fix (2026-09-22 follow-up) — `s.storyViewer` now stores the FULL
// ordered deck (`groups`/`groupIndex`/`storyIndex`), not one organizer's
// stories in isolation — see GocContext.jsx's own comment on
// openStoryViewer()/storyNext()/storyPrev().
const STORY_MS = 5000;
const DISMISS_MS = 260;
const DISMISS_EASING = 'cubic-bezier(.22,.61,.36,1)';
const DRAG_THRESHOLD = 90;
const DRAG_REVEAL_DISTANCE = 220;
const HOLD_MS = 180; // a press held longer than this pauses instead of counting as a tap
const HSWIPE_THRESHOLD = 60; // px of horizontal travel that commits to prev/next

export default function StoryViewer() {
  const { state: s, T, closeStoryViewer, storyNext, storyPrev, markStoryViewedAt } = useGoc();
  const viewer = s.storyViewer;
  const group = viewer?.groups?.[viewer.groupIndex];
  const story = group?.stories?.[viewer?.storyIndex];

  const [closing, setClosing] = useState(false);
  const [chromeHidden, setChromeHidden] = useState(false); // during a hold
  const fillRef = useRef(null);
  const photoRef = useRef(null);
  const dimRef = useRef(null);
  const chromeRef = useRef(null);

  // ---- Task 3: smooth, elapsed-time-driven progress (not a React-state
  // countdown) — a single rAF loop imperatively sets the fill bar's
  // transform via a ref, so a re-render never causes a visible stutter/
  // jump. `elapsedRef` accumulates real elapsed ms across pause/resume
  // (hold, or a drag-down that implicitly pauses), so resuming continues
  // from the exact same point rather than restarting.
  const elapsedRef = useRef(0);
  const runStartRef = useRef(0);
  const pausedRef = useRef(false);
  const rafRef = useRef(null);

  const tick = () => {
    if (pausedRef.current) return;
    const now = performance.now();
    const elapsed = elapsedRef.current + (now - runStartRef.current);
    const progress = Math.min(1, elapsed / STORY_MS);
    if (fillRef.current) fillRef.current.style.transform = `scaleX(${progress})`;
    if (progress >= 1) { storyNext(); return; }
    rafRef.current = requestAnimationFrame(tick);
  };
  const startFresh = () => {
    elapsedRef.current = 0;
    runStartRef.current = performance.now();
    pausedRef.current = false;
    if (fillRef.current) fillRef.current.style.transform = 'scaleX(0)';
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
    rafRef.current = requestAnimationFrame(tick);
  };
  const pause = () => {
    if (pausedRef.current) return;
    elapsedRef.current += performance.now() - runStartRef.current;
    pausedRef.current = true;
    if (rafRef.current) cancelAnimationFrame(rafRef.current);
  };
  const resume = () => {
    if (!pausedRef.current) return;
    runStartRef.current = performance.now();
    pausedRef.current = false;
    rafRef.current = requestAnimationFrame(tick);
  };

  useEffect(() => {
    if (viewer) markStoryViewedAt();
    startFresh();
    return () => { if (rafRef.current) cancelAnimationFrame(rafRef.current); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewer?.groupIndex, viewer?.storyIndex]);

  if (!viewer || !group || !story) return null;

  const dismiss = () => {
    if (closing) return;
    pause();
    setClosing(true);
    setTimeout(closeStoryViewer, DISMISS_MS);
  };

  // ---- Task 2/3/5: one pointer-gesture set disambiguating tap / hold /
  // vertical-drag-dismiss / horizontal-drag-navigate, mirroring
  // ChatPhotoViewer.jsx's stage gesture (b75b884) structurally, kept as
  // this component's OWN copy rather than a shared import — the two
  // viewers' surrounding state (progress bars/cross-host navigation vs.
  // chrome-toggle) differ enough that sharing the raw gesture handler
  // would couple two otherwise-independent viewers. Direction is only
  // classified once movement clears a small threshold (never on the very
  // first pixel), so a vertical dismiss and a horizontal swipe can never
  // both fire for the same gesture.
  const gesture = useRef(null);
  const onStagePointerDown = (e) => {
    gesture.current = { x: e.clientX, y: e.clientY, dragging: null, holding: false, downAt: performance.now() };
    gesture.current.holdTimer = setTimeout(() => {
      if (!gesture.current || gesture.current.dragging) return;
      gesture.current.holding = true;
      pause();
      setChromeHidden(true);
    }, HOLD_MS);
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };
  const onStagePointerMove = (e) => {
    const g = gesture.current;
    if (!g || closing) return;
    const dy = e.clientY - g.y;
    const dx = e.clientX - g.x;
    if (!g.dragging && !g.holding) {
      if (dy > 6 && dy > Math.abs(dx)) {
        g.dragging = 'vertical';
        clearTimeout(g.holdTimer);
        pause();
        setChromeHidden(false); // a drag reveals its own progressive fade below, not the hold's instant hide
      } else if (Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) {
        g.dragging = 'horizontal';
        clearTimeout(g.holdTimer);
        pause();
      } else {
        return;
      }
    }
    if (g.dragging === 'vertical') {
      const progress = Math.min(1, dy / DRAG_REVEAL_DISTANCE);
      if (photoRef.current) { photoRef.current.style.transition = 'none'; photoRef.current.style.transform = `translateY(${dy}px) scale(${1 - progress * 0.08})`; }
      if (dimRef.current) { dimRef.current.style.transition = 'none'; dimRef.current.style.opacity = String(1 - progress); }
      if (chromeRef.current) { chromeRef.current.style.transition = 'none'; chromeRef.current.style.opacity = String(1 - progress); }
      g.lastDy = dy;
    } else if (g.dragging === 'horizontal') {
      g.lastDx = dx;
    }
  };
  const onStagePointerUp = (e) => {
    const g = gesture.current;
    if (!g) return;
    clearTimeout(g.holdTimer);
    gesture.current = null;
    if (g.dragging === 'vertical') {
      const dy = g.lastDy || 0;
      if (dy > DRAG_THRESHOLD) { dismiss(); return; }
      // Short of threshold — spring everything back and resume progress.
      [photoRef, dimRef, chromeRef].forEach(r => {
        if (r.current) { r.current.style.transition = `all ${DISMISS_MS}ms ${DISMISS_EASING}`; r.current.style.transform = ''; r.current.style.opacity = ''; }
      });
      resume();
      return;
    }
    if (g.dragging === 'horizontal') {
      const dx = g.lastDx || 0;
      if (Math.abs(dx) > HSWIPE_THRESHOLD) { (dx < 0 ? storyNext : storyPrev)(); return; }
      resume(); // short of threshold — no navigation, just resume where it was
      return;
    }
    if (g.holding) {
      resume();
      setChromeHidden(false);
      return; // a hold-and-release never navigates
    }
    // A plain tap — which half of the screen.
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    if (x < rect.width / 2) storyPrev(); else storyNext();
  };

  const isEventShare = story.kind === 'event_share';

  return (
    <div
      data-screen-label="Story viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 27, background: '#000', overflow: 'hidden', opacity: closing ? 0 : 1, transition: `opacity ${DISMISS_MS}ms ease` }}
    >
      <div ref={dimRef} aria-hidden style={{ position: 'absolute', inset: 0, background: '#000' }} />

      <div
        data-testid="story-viewer-stage"
        onPointerDown={onStagePointerDown}
        onPointerMove={onStagePointerMove}
        onPointerUp={onStagePointerUp}
        style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', touchAction: 'none' }}
      >
        <div ref={photoRef} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: '100%', height: '100%' }}>
          {isEventShare ? (
            <EventShareCard story={story} T={T} />
          ) : (
            <img src={story.url} alt="" data-testid="story-viewer-image" style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} />
          )}
        </div>
      </div>

      <div ref={chromeRef} style={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
        {/* Progress bars — one per story in the CURRENT host's own group
            (resets per host, standard deck behavior), the current one
            filling smoothly via rAF. */}
        <div style={{ position: 'absolute', top: 54, left: 12, right: 12, display: 'flex', gap: 4, opacity: chromeHidden ? 0 : 1, transition: 'opacity 0.15s ease' }}>
          {group.stories.map((st, i) => (
            <div key={st.id} style={{ flex: 1, height: 2.5, borderRadius: 2, background: 'rgba(255,255,255,0.35)', overflow: 'hidden' }}>
              <div
                ref={i === viewer.storyIndex ? fillRef : null}
                style={{ height: '100%', width: '100%', background: '#fff', transformOrigin: 'left', transform: `scaleX(${i < viewer.storyIndex ? 1 : 0})` }}
              />
            </div>
          ))}
        </div>

        <span style={{ position: 'absolute', top: 62, left: 16, color: 'rgba(255,255,255,0.85)', fontSize: 11, fontWeight: 600, opacity: chromeHidden ? 0 : 1, transition: 'opacity 0.15s ease' }}>
          {group.orgName}
        </span>

        <div
          onClick={(e) => { e.stopPropagation(); dismiss(); }}
          data-testid="story-viewer-close"
          style={{ position: 'absolute', top: 62, right: 16, color: '#fff', fontSize: 22, cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))', pointerEvents: chromeHidden ? 'none' : 'auto', opacity: chromeHidden ? 0 : 1, transition: 'opacity 0.15s ease' }}
        >
          ×
        </div>

        <span style={{ position: 'absolute', bottom: 40, left: 18, color: 'rgba(255,255,255,0.75)', fontSize: 10.5, letterSpacing: '0.04em', textShadow: '0 1px 3px rgba(12,12,12,0.55)', opacity: chromeHidden ? 0 : 1, transition: 'opacity 0.15s ease' }}>
          banbe ▪︎ {T('story', 'story')}
        </span>
      </div>
    </div>
  );
}

// Task 4 — an event-share story renders as a dedicated card, not a plain
// photo. `story.kind === 'event_share'` carries `eventSnapshot`
// (denormalized at load time — see GocContext.jsx's own comment on why) so
// the card still renders correctly even if the event later changes.
function EventShareCard({ story, T }) {
  const { goEventFromStory } = useGoc();
  const snap = story.eventSnapshot;
  if (!snap) {
    return (
      <div style={{ color: '#fff', fontSize: 13, textAlign: 'center', padding: 24 }}>
        {T('Sự kiện này không còn khả dụng.', 'This event is no longer available.')}
      </div>
    );
  }
  return (
    <div
      data-testid="story-event-card"
      onClick={(e) => { e.stopPropagation(); goEventFromStory(snap.eventKey); }}
      style={{ width: '86%', maxWidth: 340, borderRadius: 18, overflow: 'hidden', background: paper, cursor: 'pointer', boxShadow: '0 18px 44px rgba(0,0,0,0.5)' }}
    >
      {/* BUG 2 fix (2026-09-22 follow-up) — reuses the same `bg()` cover-
          photo helper Event Detail/Home/Organizer already use for every
          other event image, instead of an ad-hoc inline style. */}
      <div style={bg(snap.img, { width: '100%', aspectRatio: '4 / 5', borderRadius: 0 })} />
      <div style={{ padding: '16px 18px 18px' }}>
        <div style={{ ...display(18, { color: ink }) }}>{snap.name}</div>
        <div style={{ fontSize: 12, color: ink, opacity: 0.7, marginTop: 4 }}>{snap.when}</div>
        <div
          data-testid="story-event-cta"
          onClick={(e) => { e.stopPropagation(); goEventFromStory(snap.eventKey); }}
          style={{ marginTop: 14, padding: '12px 0', textAlign: 'center', borderRadius: 12, background: ink, color: paper, fontSize: 13.5, fontWeight: 700 }}
        >
          {T('Xem sự kiện', 'View event')}
        </div>
      </div>
    </div>
  );
}

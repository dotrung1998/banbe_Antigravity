import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, display, cardGlass } from '../../theme.js';
import { bg, distanceLabel } from '../../data/events.js';

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
const HSWIPE_VELOCITY = 0.6; // px/ms — a fast flick commits even under the distance threshold
const HSWIPE_SETTLE_MS = 190; // banbe's own "gallery drift" settle duration, not Instagram's

// FEATURE 3 (2026-09-22 follow-up) — a banbe-specific "gallery drift"
// transition: the current story follows the finger, a softly rounded,
// glass-token "companion" card drifts in alongside it from whichever edge
// the swipe is headed toward, using only transform/opacity/filter (GPU-
// friendly, no React state per pointer-move pixel — the same imperative-
// ref convention Task 3's progress bar already established). Deliberately
// NOT Instagram's extreme 3D side-card/header/icon look — a single flat
// glass panel with depth from blur+shadow, not a rotated 3D card stack.
// Read once at module load (a live prefers-reduced-motion change mid-
// session is an edge case not worth a listener for a story viewer).
const REDUCED_MOTION = typeof window !== 'undefined' && window.matchMedia
  ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
  : false;

export default function StoryViewer() {
  const { state: s, T, closeStoryViewer, storyNext, storyPrev, storyNextHost, storyPrevHost, markStoryViewedAt } = useGoc();
  const viewer = s.storyViewer;
  const group = viewer?.groups?.[viewer.groupIndex];
  const story = group?.stories?.[viewer?.storyIndex];
  // PRODUCT CHANGE 3 (2026-09-22 tenth follow-up) — whether a horizontal
  // swipe in each direction actually has another HOST to land on. Read by
  // both the gesture handlers (to decide companion-peek vs BUG 4's
  // reveal-underneath treatment) and the render below (so the companion
  // only ever represents a REAL adjacent host, never a placeholder for one
  // that doesn't exist).
  const hasNextHost = !!viewer?.groups?.slice(viewer.groupIndex + 1).some(g => g.stories.length > 0);
  const hasPrevHost = !!viewer?.groups?.slice(0, viewer.groupIndex).some(g => g.stories.length > 0);

  const [closing, setClosing] = useState(false);
  const [chromeHidden, setChromeHidden] = useState(false); // during a hold
  const fillRef = useRef(null);
  const photoRef = useRef(null);
  const dimRef = useRef(null);
  const chromeRef = useRef(null);
  const stageRef = useRef(null);
  // The whole viewer's own outer container — faded during BUG 4's
  // "final story of the final host, swipe forward" case to progressively
  // reveal whatever real screen (Home/Account) is already mounted
  // underneath, instead of the companion card (which only ever stands in
  // for a REAL adjacent host — see `hasNextHost`/`hasPrevHost` above).
  const containerRef = useRef(null);
  // The incoming neighbor's soft glass "peek" card (gallery-drift, Feature 3).
  const companionRef = useRef(null);

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

  // Gallery-drift companion transform (Feature 3) — pure function of drag
  // progress/direction, imperative (no React state per pointer-move pixel).
  // Defined ABOVE the early `if (!viewer...) return null` below (unlike
  // dismiss()/the gesture handlers, which are only ever referenced from
  // JSX that doesn't exist on that early-return path) because the
  // `useEffect` right below calls `resetCompanion` on every render,
  // including ones where the component returns null before ever reaching
  // a same-named `const` declared further down — that would be a real
  // temporal-dead-zone crash the very first time the viewer opens.
  const applyCompanionTransform = (dx, width) => {
    if (!companionRef.current || REDUCED_MOTION) return;
    const progress = Math.min(1, Math.abs(dx) / Math.max(1, width));
    const fromRight = dx < 0; // dragging left reveals the NEXT card from the right edge
    const edgeOffset = (1 - progress) * (width * 0.5 + 40);
    const x = fromRight ? edgeOffset : -edgeOffset;
    companionRef.current.style.display = 'block';
    companionRef.current.style.transition = 'none';
    companionRef.current.style.transform = `translateX(${x}px) scale(${0.86 + progress * 0.14})`;
    companionRef.current.style.opacity = String(Math.min(0.92, progress * 1.15));
  };
  const resetCompanion = (animate) => {
    if (!companionRef.current) return;
    companionRef.current.style.transition = animate ? `all ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}` : 'none';
    companionRef.current.style.opacity = '0';
    companionRef.current.style.transform = 'scale(0.86)';
    if (!animate) companionRef.current.style.display = 'none';
  };
  // BUG 4 (2026-09-22 tenth follow-up) — the "reveal Home underneath"
  // treatment for the final story of the final host (forward swipe) /
  // the very first story of the deck (backward swipe, spring-back only,
  // never actually needs to reveal anything but shares the reset). Same
  // imperative-ref convention as everything else here — no React state.
  const resetReveal = (animate) => {
    if (!containerRef.current) return;
    containerRef.current.style.transition = animate ? `opacity ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}` : 'none';
    containerRef.current.style.opacity = '1';
  };

  useEffect(() => {
    if (viewer) markStoryViewedAt();
    startFresh();
    // A settled gallery-drift transition already resets photoRef's own
    // transform back to '' before calling storyNext/storyPrev (see
    // onStagePointerUp above); this is just the defensive reset for every
    // OTHER way groupIndex/storyIndex can change (tap-to-advance, auto-
    // advance on timeout, manual storyPrev/storyNext elsewhere) — a fresh
    // story should never inherit a leftover drag transform.
    if (photoRef.current) { photoRef.current.style.transition = 'none'; photoRef.current.style.transform = ''; }
    resetCompanion(false);
    resetReveal(false);
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
      const now = performance.now();
      g.velocity = (dx - (g.lastDx || 0)) / Math.max(1, now - (g.lastMoveAt || g.downAt));
      g.lastDx = dx;
      g.lastMoveAt = now;
      const width = stageRef.current?.getBoundingClientRect().width || window.innerWidth;
      const goingNext = dx < 0;
      // PRODUCT CHANGE 3 (2026-09-22 tenth follow-up) — the drag only ever
      // targets the adjacent HOST, never the current host's own next/prev
      // post (that's `storyNext`/`storyPrev`'s job — the timer and tap
      // zones, untouched). `hasNextHost`/`hasPrevHost` decide which of two
      // very different visual treatments this same drag gets:
      //   - a real adjacent host exists → the abstract glass "companion"
      //     card (now representing that HOST, not an individual post);
      //   - no adjacent host in that direction → BUG 4's fix: reveal
      //     whatever real screen is already mounted underneath (Home/
      //     Account) progressively, exactly like the vertical dismiss
      //     already reveals it, instead of a gray/empty companion card.
      const revealingUnderneath = (goingNext && !hasNextHost) || (!goingNext && !hasPrevHost);
      if (photoRef.current) {
        photoRef.current.style.transition = 'none';
        photoRef.current.style.transform = REDUCED_MOTION
          ? `translateX(${dx}px)`
          : `translateX(${dx}px) scale(${1 - Math.min(1, Math.abs(dx) / width) * 0.06})`;
      }
      if (revealingUnderneath) {
        if (goingNext && containerRef.current) {
          // Only the FORWARD case actually reveals anything (BUG 4) — the
          // backward "no previous host" case has nothing real to reveal
          // (there's no logical prior context before the deck's very
          // first host), so it just rubber-bands the current card via
          // `photoRef` above and always springs back on release below.
          containerRef.current.style.transition = 'none';
          containerRef.current.style.opacity = String(1 - Math.min(1, Math.abs(dx) / width));
        }
      } else {
        applyCompanionTransform(dx, width);
      }
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
      const width = stageRef.current?.getBoundingClientRect().width || window.innerWidth;
      const goingNext = dx < 0;
      // PRODUCT CHANGE 3 — a backward swipe past the beginning of the
      // WHOLE deck (no previous host at all) never commits to anything;
      // it only ever springs back, regardless of distance/velocity — "no
      // logical prior context" per BUG 4's own symmetry requirement.
      const canCommit = goingNext ? hasNextHost : hasPrevHost;
      const committed = canCommit && (Math.abs(dx) > HSWIPE_THRESHOLD || Math.abs(g.velocity || 0) > HSWIPE_VELOCITY);
      if (committed) {
        // Settle: finish the drift the rest of the way out, THEN advance —
        // storyNextHost/storyPrevHost change groupIndex/storyIndex, which
        // remounts fresh content via the effect below; finishing the
        // outward motion first is what makes it read as one continuous
        // drift instead of a snap-then-jump. No progress/mark-viewed side
        // effect happens here — that's still solely the effect keyed on
        // groupIndex/storyIndex.
        if (photoRef.current) {
          photoRef.current.style.transition = `transform ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`;
          photoRef.current.style.transform = `translateX(${goingNext ? -width : width}px)`;
        }
        if (companionRef.current && !REDUCED_MOTION) {
          companionRef.current.style.transition = `all ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`;
          companionRef.current.style.transform = 'translateX(0) scale(1)';
          companionRef.current.style.opacity = '1';
        }
        setTimeout(() => {
          if (photoRef.current) { photoRef.current.style.transition = 'none'; photoRef.current.style.transform = ''; }
          resetCompanion(false);
          (goingNext ? storyNextHost : storyPrevHost)();
        }, HSWIPE_SETTLE_MS);
        return;
      }
      // BUG 4 — the final story of the final host, swipe forward, PAST the
      // commit threshold: complete the reveal into Home/Account instead of
      // springing back. Dock visibility only restores once `closeStoryViewer()`
      // actually runs (Shell's own `showBar = ... && !state.storyViewer`
      // already gates on that), i.e. only after the settle finishes.
      if (goingNext && !hasNextHost) {
        const beyondThreshold = Math.abs(dx) > HSWIPE_THRESHOLD || Math.abs(g.velocity || 0) > HSWIPE_VELOCITY;
        if (beyondThreshold) {
          if (containerRef.current) {
            containerRef.current.style.transition = `opacity ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`;
            containerRef.current.style.opacity = '0';
          }
          if (photoRef.current) {
            photoRef.current.style.transition = `transform ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`;
            photoRef.current.style.transform = `translateX(${-width}px)`;
          }
          setTimeout(() => { closeStoryViewer(); }, HSWIPE_SETTLE_MS);
          return;
        }
      }
      // Short of threshold/velocity (or no adjacent host to land on) —
      // spring the current card back, fade the companion out, undo any
      // reveal-underneath progress, then resume where it was. Explicitly
      // does NOT reset story position/progress — same "no state reset"
      // contract as every other cancelled gesture here.
      if (photoRef.current) { photoRef.current.style.transition = `transform ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`; photoRef.current.style.transform = ''; }
      resetCompanion(true);
      resetReveal(true);
      resume();
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
      ref={containerRef}
      data-screen-label="Story viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 27, background: '#000', overflow: 'hidden', opacity: closing ? 0 : 1, transition: `opacity ${DISMISS_MS}ms ease` }}
    >
      <div ref={dimRef} aria-hidden style={{ position: 'absolute', inset: 0, background: '#000' }} />

      <div
        ref={stageRef}
        data-testid="story-viewer-stage"
        data-org-id={group.organizerId}
        data-story-count={group.stories.length}
        data-story-index={viewer.storyIndex}
        onPointerDown={onStagePointerDown}
        onPointerMove={onStagePointerMove}
        onPointerUp={onStagePointerUp}
        style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', touchAction: 'none' }}
      >
        {/* Gallery-drift companion (Feature 3) — a soft glass panel standing
            in for the incoming neighbor, purely transform/opacity driven,
            hidden (display:none) whenever not mid-drag so it costs nothing
            at rest. */}
        <div
          ref={companionRef}
          aria-hidden
          style={{
            display: 'none', position: 'absolute', inset: '8%', borderRadius: 28,
            ...cardGlass({}), boxShadow: '0 18px 50px rgba(0,0,0,0.45)',
            opacity: 0, transform: 'scale(0.86)', pointerEvents: 'none',
          }}
        />
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
  const { state: s, goEventFromStory } = useGoc();
  const snap = story.eventSnapshot;
  if (!snap) {
    return (
      <div style={{ color: '#fff', fontSize: 13, textAlign: 'center', padding: 24 }}>
        {T('Sự kiện này không còn khả dụng.', 'This event is no longer available.')}
      </div>
    );
  }
  // BUG 2 (2026-09-22 tenth follow-up) — the same canonical `distanceLabel()`
  // helper Event Detail/MapExplore use, recomputed on EVERY render from
  // the CURRENT `s.userCoords`/`s.located` (both live GocContext state) —
  // never cached at the moment the story was opened, so it updates live if
  // location resolves/changes while the card is on screen, and shows
  // nothing at all (never a static/wrong number) whenever a real distance
  // genuinely isn't available yet.
  const dist = distanceLabel(s.userCoords, s.located === true, snap);
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
        <div style={{ fontSize: 12, color: ink, opacity: 0.7, marginTop: 4 }} data-testid="story-event-distance">
          {snap.when}{dist ? ` ▪︎ ${dist}` : ''}
        </div>
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

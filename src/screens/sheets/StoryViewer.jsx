import { useEffect, useLayoutEffect, useRef, useState } from 'react';
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
// A deck this size or smaller preloads in full on open; a larger one only
// preloads the current host + the immediately adjacent hosts (BUG 3,
// 2026-09-22 eleventh follow-up) — bounded so a very active account
// doesn't kick off dozens of simultaneous downloads for a deck it may
// never fully scroll through.
const PRELOAD_FULL_DECK_STORY_LIMIT = 20;

// The actual renderable image URL for a story — a real media story's own
// signed `url`, or an event-share story's cover path (the same one `bg()`
// renders as a CSS background elsewhere in this file). Module-scope pure
// function (no component state), shared by the preload effect and the
// companion's own low-detail backdrop below.
function coverUrlFor(st) {
  if (!st) return null;
  return st.kind === 'event_share' ? (st.eventSnapshot?.img || null) : st.url;
}

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
  // The companion's own low-detail backdrop image (BUG 3) — a separate
  // inner layer so its `background-image` never has to fight `cardGlass()`'s
  // own `background` shorthand on the SAME element.
  const companionBackdropRef = useRef(null);
  // BUG 3 (2026-09-22 eleventh follow-up) — URLs already handed to the
  // browser for preloading this viewer session, so re-renders (every
  // story tick, every drag frame) never re-request the same image twice.
  const preloadedUrlsRef = useRef(new Set());
  // Task 1 (2026-09-22 twelfth follow-up) — true once the expand-from-ring
  // entrance has already played for this open session, so the effect below
  // (which re-runs on every groupIndex/storyIndex change too, since
  // `viewer` is a new object each time) never replays it on ordinary
  // story/host navigation, only on a genuine fresh open.
  const enteredEntryRef = useRef(false);

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
    // BUG 3 (2026-09-22 eleventh follow-up) — the companion now shows the
    // adjacent host's own (preloaded) cover as a blurred, low-detail
    // backdrop behind the glass, rather than a blank/gray panel — a
    // deliberate branded placeholder look (blur + the same glass tint
    // every other companion state already used), not raw empty gray, and
    // instant either way since the URL was already warmed by the preload
    // effect above by the time a drag can physically begin.
    const neighborGroup = fromRight ? viewer?.groups?.[viewer.groupIndex + 1] : viewer?.groups?.[viewer.groupIndex - 1];
    const coverUrl = coverUrlFor(neighborGroup?.stories?.[0]);
    if (companionBackdropRef.current) {
      companionBackdropRef.current.style.backgroundImage = coverUrl ? `url("${coverUrl}")` : 'none';
    }
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

  // BUG 3 (2026-09-22 eleventh follow-up) — preload story media in the
  // background so a host-to-host swipe never shows a loading gap. Signed
  // URLs for the WHOLE deck are already resolved up front by
  // `loadHomeStories()` (one batched `createSignedUrls` call, not
  // per-story) — the only thing actually missing by the time this viewer
  // opens is the browser having fetched/decoded the image BYTES, which is
  // what this warms. `new Image()` lets the browser's own HTTP cache and
  // connection-pool limits provide bounded concurrency for free — no
  // custom scheduler needed — and `preloadedUrlsRef` stops the same URL
  // from ever being requested twice. Runs once per `groupIndex` change
  // (not per `storyIndex`, since the target set — current host in full,
  // adjacent hosts' first story — only actually changes when the host
  // does), and immediately on open (this effect fires on mount too, same
  // as any other), never blocking the current story from rendering first
  // — this is a background side effect, not something the initial render
  // waits on.
  useEffect(() => {
    if (!viewer) return;
    const totalStories = viewer.groups.reduce((n, g) => n + g.stories.length, 0);
    const targetGroups = totalStories <= PRELOAD_FULL_DECK_STORY_LIMIT
      ? viewer.groups
      : [viewer.groups[viewer.groupIndex - 1], viewer.groups[viewer.groupIndex], viewer.groups[viewer.groupIndex + 1]].filter(Boolean);
    for (const g of targetGroups) {
      // The current host's own full set; an adjacent host's just its
      // FIRST story (the one a swipe would actually land on first) —
      // matches this ticket's own "at minimum" preload scope.
      const stories = g === viewer.groups[viewer.groupIndex] ? g.stories : g.stories.slice(0, 1);
      for (const st of stories) {
        const url = coverUrlFor(st);
        if (!url || preloadedUrlsRef.current.has(url)) continue;
        preloadedUrlsRef.current.add(url);
        const img = new Image();
        img.src = url;
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewer?.groupIndex, viewer?.groups]);

  // Task 1 (2026-09-22 twelfth follow-up) — the ring-window's own inset
  // clip-path, from the given rect's screen position/size to a rounded
  // window, expressed against the viewport (the container is
  // `position: absolute; inset: 0`). `clip-path` (not `transform: scale`,
  // tried first) is what makes this safe: a CSS transform changes what
  // `getBoundingClientRect()` reports for every descendant for as long as
  // it's mid-animation — the gesture stage's own drag-coordinate math, AND
  // several existing tests that read a child's real rendered size right
  // after open, both read wildly wrong (tiny/offset) values during that
  // window, confirmed by real regressions when this was tried as a
  // transform. `clip-path` only affects what's PAINTED — every descendant's
  // actual layout box/rect stays its true, final full-screen size the
  // entire time, so dragging or measuring content works correctly even
  // mid-animation; it also already excludes pointer events outside the
  // clipped region by itself, no separate `pointer-events` gating needed.
  const ringClipPath = (rect) => {
    if (typeof window === 'undefined') return null;
    const vw = window.innerWidth, vh = window.innerHeight;
    const top = Math.max(0, rect.top);
    const left = Math.max(0, rect.left);
    const right = Math.max(0, vw - (rect.left + rect.width));
    const bottom = Math.max(0, vh - (rect.top + rect.height));
    return `inset(${top}px ${right}px ${bottom}px ${left}px round 15px)`;
  };

  // Task 1 — expand-from-ring entrance: starts the container's visible
  // window clipped down to the tapped ring's own rect, transition disabled
  // for that first frame, then flips to the full-screen clip (identity)
  // with a transition one/two rAFs later so the browser actually has a
  // "before" frame to interpolate from — same double-rAF reasoning
  // PhotoViewer.jsx's own doc comment on `entered` describes for why a
  // same-tick animation+transition swap doesn't animate. `useLayoutEffect`
  // (not `useEffect`) so this first, un-clipped-to-ring frame paints BEFORE
  // the browser shows anything, avoiding a full-size flash before the
  // window starts small.
  useLayoutEffect(() => {
    if (!viewer) { enteredEntryRef.current = false; return; }
    if (enteredEntryRef.current || REDUCED_MOTION) return;
    enteredEntryRef.current = true;
    const el = containerRef.current;
    const rect = viewer.originRect;
    const clip = rect && ringClipPath(rect);
    if (!el || !clip) return;
    el.style.transition = 'none';
    el.style.clipPath = clip;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        if (!el.isConnected) return;
        el.style.transition = `clip-path ${DISMISS_MS}ms ${DISMISS_EASING}`;
        el.style.clipPath = 'inset(0px 0px 0px 0px round 0px)';
      });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewer]);

  // Task 1 — dismiss shrink-back target: a LIVE DOM lookup of the
  // CURRENTLY active host's own ring (never the stored `originRect`, which
  // only ever reflects whichever host was ORIGINALLY tapped) — satisfies
  // "if the user drifted from Host A to Host B before dismissing, shrink
  // toward Host B's ring." Home is always mounted underneath (see
  // App.jsx's Shell — Screen renders before StoryViewer as siblings,
  // `state.screen` never changes while browsing stories), so its story
  // row's ring elements are real, live DOM nodes at dismiss time even
  // though they're visually covered. No rect found (ring scrolled out of
  // Home's own row, or this session's Home never rendered one for this
  // host) falls back to a plain opacity fade — never animates toward a
  // stale/guessed frame, per this ticket's own instruction.
  const shrinkToRing = (organizerId, ms = DISMISS_MS) => {
    const el = containerRef.current;
    if (!el) return;
    el.style.transition = REDUCED_MOTION ? `opacity ${ms}ms ease` : `clip-path ${ms}ms ${DISMISS_EASING}, opacity ${ms}ms ease`;
    if (!REDUCED_MOTION && typeof document !== 'undefined' && organizerId) {
      const ringEl = document.querySelector(`[data-testid="home-story-avatar"][data-org-id="${organizerId}"]`);
      const rect = ringEl ? ringEl.getBoundingClientRect() : null;
      const clip = rect && rect.width > 0 && rect.height > 0 ? ringClipPath(rect) : null;
      if (clip) el.style.clipPath = clip;
    }
    el.style.opacity = '0';
  };

  if (!viewer || !group || !story) return null;

  const dismiss = () => {
    if (closing) return;
    pause();
    setClosing(true);
    shrinkToRing(group.organizerId);
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
    // BUG (2026-09-22 eleventh follow-up, found while reproducing BUG 1's
    // own live repro) — real bug, confirmed live: capturing the pointer
    // HERE, on every touch-down (including a plain tap that never moves),
    // silently swallowed the browser's own synthetic `click` event for
    // ANY interactive child underneath the touch — the event-share card's
    // `onClick`/its CTA's `onClick` NEVER fired at all, confirmed via a
    // raw `addEventListener('click', ...)` that never ran even with no
    // drag involved. `click`'s target is resolved from where the
    // mousedown/mouseup compat events actually landed while capture was
    // held — releasing capture again afterward (tried first) does NOT
    // undo that once it's already happened. The real fix: only capture
    // once a gesture has actually been classified as a DRAG (below,
    // mirroring `onStagePointerUp`'s own reasoning for why `dragKind`
    // classification exists at all) — a plain tap never moves enough to
    // reach this classification, so it never captures the pointer, and
    // the browser resolves its own click normally.
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
        e.currentTarget.setPointerCapture?.(e.pointerId);
      } else if (Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) {
        g.dragging = 'horizontal';
        clearTimeout(g.holdTimer);
        pause();
        e.currentTarget.setPointerCapture?.(e.pointerId);
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
      //   - no adjacent host in that direction → BUG 4/BUG 2 fix: reveal
      //     whatever real screen is already mounted underneath (Home/
      //     Account) progressively, exactly like the vertical dismiss
      //     already reveals it, instead of a gray/empty companion card.
      // BUG 2 (2026-09-22 eleventh follow-up) — this used to only reveal
      // for the FORWARD/no-next-host edge; the BACKWARD/no-prev-host edge
      // (first story of the first host, swiping right) just rubber-banded
      // with nothing shown underneath, an asymmetry this ticket explicitly
      // calls out. Both edges of the whole deck now reveal identically —
      // there's no reason Home is only a valid destination from one end.
      const revealingUnderneath = (goingNext && !hasNextHost) || (!goingNext && !hasPrevHost);
      if (photoRef.current) {
        photoRef.current.style.transition = 'none';
        photoRef.current.style.transform = REDUCED_MOTION
          ? `translateX(${dx}px)`
          : `translateX(${dx}px) scale(${1 - Math.min(1, Math.abs(dx) / width) * 0.06})`;
      }
      if (revealingUnderneath) {
        if (containerRef.current) {
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
    // BUG (2026-09-22 eleventh follow-up, found while reproducing BUG 1's
    // own live repro) — real bug, confirmed live: `setPointerCapture` in
    // `onStagePointerDown` keeps this pointer's events targeted at the
    // STAGE for the rest of the gesture, which is what dragging off-stage
    // needs — but Chromium also redirects the COMPATIBILITY mouse events
    // synthesized from this same pointer (`mouseup`/`click`) to the
    // capturing element for as long as capture is held. Left captured
    // through the end of this handler, that meant the browser's own
    // `click` event for a plain tap NEVER reached the event-share card's
    // `onClick`/its CTA's `onClick` at all — confirmed by adding a raw
    // `addEventListener('click', ...)` on the CTA directly, which never
    // fired, even without any drag or the `elementFromPoint` guard above
    // in the picture. Releasing capture here, once the gesture is
    // genuinely over, lets the browser resolve the subsequent click
    // normally — it doesn't affect drag tracking, since the drag is
    // already finished by the time `onStagePointerUp` runs.
    e.currentTarget.releasePointerCapture?.(e.pointerId);
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
      // PRODUCT CHANGE 3 — a swipe past either edge of the WHOLE deck (no
      // next/previous host to land on) never commits to a HOST change via
      // storyNextHost/storyPrevHost — that edge case is handled entirely
      // by the reveal-Home branch below instead (BUG 2/BUG 4).
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
      // BUG 4 / BUG 2 (2026-09-22 tenth/eleventh follow-up) — at EITHER
      // edge of the whole deck (final story of the final host, swipe
      // forward; OR first story of the first host, swipe backward), past
      // the commit threshold: complete the reveal into Home/Account
      // instead of springing back. Both edges now behave identically —
      // BUG 2's own fix removes the asymmetry the previous pass left
      // (only the forward edge revealed anything). Dock visibility only
      // restores once `closeStoryViewer()` actually runs (Shell's own
      // `showBar = ... && !state.storyViewer` already gates on that),
      // i.e. only after the settle finishes.
      if ((goingNext && !hasNextHost) || (!goingNext && !hasPrevHost)) {
        const beyondThreshold = Math.abs(dx) > HSWIPE_THRESHOLD || Math.abs(g.velocity || 0) > HSWIPE_VELOCITY;
        if (beyondThreshold) {
          // Task 1 (2026-09-22 twelfth follow-up) — this edge-of-deck
          // reveal-into-Home dismiss now shrinks toward the CURRENT host's
          // ring too, same as dismiss()/the vertical drag-down path, not
          // just a plain opacity fade.
          shrinkToRing(group.organizerId, HSWIPE_SETTLE_MS);
          if (photoRef.current) {
            photoRef.current.style.transition = `transform ${HSWIPE_SETTLE_MS}ms ${DISMISS_EASING}`;
            photoRef.current.style.transform = `translateX(${goingNext ? -width : width}px)`;
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
    // BUG (2026-09-22 eleventh follow-up, found while reproducing BUG 1's
    // own live repro) — real bug, confirmed live: a tap that lands on the
    // event-share card/CTA fires `pointerdown`/`pointerup` here TOO (they
    // bubble up from the card before its own `onClick` even runs) —
    // `e.stopPropagation()` in the card's `onClick` only stops the
    // synthetic CLICK from bubbling, not the pointer events this stage
    // handler is listening for. Without this check, tapping the card
    // ALSO ran `storyPrev()`/`storyNext()` from the very same tap —
    // sometimes DISMISSING the whole viewer (the deck's last story) and
    // unmounting the card before `goEventFromStory()`'s own click handler
    // ever got to run. `e.target` can't be used here — `onStagePointerDown`
    // calls `setPointerCapture`, which per spec RETARGETS every subsequent
    // pointer event's `target` to the CAPTURING element (this stage div
    // itself), so `e.target.closest(...)` would always resolve to the
    // stage, never the card underneath, regardless of where the finger
    // actually was. `elementFromPoint` does real hit-testing at the
    // pointer's coordinates instead, bypassing that retargeting. Checked
    // here (not by stopping the pointer events at the card itself) so a
    // genuine DRAG that merely starts or ends over the card's large hit
    // area still reaches the stage normally — only a true, un-dragged TAP
    // that lands on the card defers entirely to the card's own onClick.
    if (document.elementFromPoint(e.clientX, e.clientY)?.closest('[data-testid="story-event-card"]')) return;
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
      // Task 1 (2026-09-22 twelfth follow-up) — opacity/transform/
      // transition/borderRadius are now ALL imperative-ref-driven (entry
      // effect, shrinkToRing, resetReveal, the drag-reveal branch in
      // onStagePointerMove), never declared here — same reasoning as every
      // other ref in this file (photoRef/dimRef/etc.): a declared style key
      // here would get reset by React on every re-render (e.g. `closing`
      // flipping true), fighting the imperative CSS transition mid-flight.
      style={{ position: 'absolute', inset: 0, zIndex: 27, background: '#000', overflow: 'hidden' }}
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
            at rest. BUG 3 (2026-09-22 eleventh follow-up): now shows the
            adjacent host's own preloaded cover as a blurred, low-detail
            backdrop underneath the glass tint — a deliberate branded
            placeholder, never a blank gray panel — instead of nothing. */}
        <div
          ref={companionRef}
          aria-hidden
          style={{
            display: 'none', position: 'absolute', inset: '8%', borderRadius: 28,
            overflow: 'hidden', boxShadow: '0 18px 50px rgba(0,0,0,0.45)',
            opacity: 0, transform: 'scale(0.86)', pointerEvents: 'none',
          }}
        >
          <div
            ref={companionBackdropRef}
            style={{ position: 'absolute', inset: -20, backgroundSize: 'cover', backgroundPosition: 'center', filter: 'blur(18px) saturate(0.85)', transform: 'scale(1.15)' }}
          />
          <div style={{ position: 'absolute', inset: 0, ...cardGlass({ borderRadius: 28 }) }} />
        </div>
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

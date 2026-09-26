import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { bg } from '../../data/events.js';

// Minimal line icons — the app has no icon set, and emoji would sit badly
// against this typography. Stroked paths inherit currentColor, so they
// follow the same white the captions use.
function Icon({ name, filled }) {
  const common = { width: 19, height: 19, viewBox: '0 0 24 24', fill: filled ? 'currentColor' : 'none', stroke: 'currentColor', strokeWidth: 1.7, strokeLinecap: 'round', strokeLinejoin: 'round' };
  if (name === 'heart') {
    return <svg {...common}><path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.5a4.7 4.7 0 0 1 8.5 2.7c0 5.8-8.5 11.3-8.5 11.3Z" /></svg>;
  }
  if (name === 'bookmark') {
    return <svg {...common}><path d="M6 3.75h12v16.5L12 16l-6 4.25V3.75Z" /></svg>;
  }
  return <svg {...common}><path d="M12 15.5V3.5m0 0L7.75 7.75M12 3.5l4.25 4.25M4.5 13.5v5.25a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5V13.5" /></svg>;
}

// Same easing this app already uses for its entrance animations (index.css's
// gocIn/gocSheetIn) — reused here for the dismiss transform rather than a
// new curve.
const DISMISS_EASING = 'cubic-bezier(.22,.61,.36,1)';
const DISMISS_MS = 280;

// A swipe/tap past this many px counts as a deliberate gesture rather than
// noise; short of it in both axes is a plain tap.
const GESTURE_THRESHOLD = 44;

// A tapped gallery photo, shown over a fully blurred copy of itself.
// Deliberately not full-screen: the photo sits in the middle third of the
// display with the same 14px corner every other photo in the app has. The
// credit/tagline/actions sit right against the photo's own top and bottom
// edges (not the screen's).
//
// Gesture zones (14-photo-viewer.md — fixes tapping the photo instantly
// closing the viewer, the previous behavior):
// - Tap/release on the LEFT half of the PHOTO ITSELF -> previous photo.
// - Tap/release on the RIGHT half of the PHOTO ITSELF -> next photo.
// - A horizontal drag past GESTURE_THRESHOLD on the photo -> same
//   prev/next, unchanged from before this fix.
// - A downward drag past GESTURE_THRESHOLD on the photo -> dismiss.
// - A tap anywhere OUTSIDE the photo (credit line, tagline/actions row,
//   the dimmed/blurred surround) -> dismiss.
// Dismissing (either path) shrinks the photo back to the exact thumbnail
// rect it was opened from, rather than fading/sliding away generically.
// Task 2b follow-up: how far (px) a downward drag has to travel before the
// backdrop is fully revealed (opacity 0) — independent of GESTURE_THRESHOLD
// (which only decides prev/next/dismiss at release); a careful drag can
// travel well past the threshold without releasing, and should keep
// getting visibly closer to fully-revealed the whole way.
const DRAG_REVEAL_DISTANCE = 200;

export default function PhotoViewer() {
  const { state: s, T, closePhoto, showPhotoAt, togglePhotoLike, sharePhoto, isSaved, toggleFav } = useGoc();
  const drag = useRef(null);
  const photoRef = useRef(null);
  // Task 2b follow-up: the blurred-copy backdrop and its dim overlay, so a
  // live downward drag can fade them imperatively (see onPhotoPointerMove)
  // without going through React state on every pointer move — the same
  // ref-driven-not-state-driven pattern this session's bottom-tab-bar work
  // already established for a live drag-follow visual, for the same
  // reason (a state update per pixel of drag would be needless re-render
  // churn for a purely visual, per-frame value).
  const backdropRef = useRef(null);
  const dimRef = useRef(null);
  // Task 4 follow-up: the credit line and the tagline/actions row, so a
  // live drag can fade them in sync with the backdrop's own fade (same
  // `progress` value, same ref-driven-not-state-driven reasoning).
  const creditRef = useRef(null);
  const taglineRowRef = useRef(null);
  // Set only while the shrink-back dismiss animation is playing — holds the
  // computed transform so render can apply it, and blocks a second dismiss
  // from starting mid-animation. Cleared (along with the real close) once
  // the transition ends.
  const [closing, setClosing] = useState(null); // { transform } | null
  const index = s.photoViewer?.index;
  // True once the entrance animation has had time to finish. Deliberately
  // NOT the same render as `closing` turning on — a CSS Animation
  // (`gocIn`) still assigned to `transform` blocks a same-property CSS
  // Transition from ever interpolating when both are toggled in one
  // update (confirmed by sampling the computed transform frame-by-frame
  // during dismiss: it always jumped straight to the end value instead of
  // easing there). Letting the animation naturally lapse and clearing it
  // in its own, earlier render is what makes the later dismiss transition
  // actually animate instead of snapping.
  const [entered, setEntered] = useState(false);
  useEffect(() => {
    setEntered(false);
    const t = setTimeout(() => setEntered(true), 240);
    return () => clearTimeout(t);
  }, [index]);
  if (!s.photoViewer) return null;

  const { gallery, organizer, originRect } = s.photoViewer;
  // Identity fix — `gallery` entries are real { id, url, eventId } rows
  // now, not bare URLs (see openPhoto's own comment). Every like/save/share
  // action below keys off the photo's own `id`/`eventId`, never the URL.
  const photo = gallery[index];
  const url = photo.url;
  const engagement = s.photoEngagement[photo.id] || { likeCount: 0, shareCount: 0, likedByMe: false };
  const liked = engagement.likedByMe;
  const saved = isSaved(photo.eventId);

  // Task 2a (real-device follow-up): confirmed by reading this function's
  // own call sites, not assumed — the backdrop's `onBackdropClick` below
  // and the swipe-past-threshold branch in `onPhotoPointerUp` already both
  // call this SAME `dismiss()`, not two separate "plain" vs "shrink-back"
  // implementations. Nothing changed here; kept as the one shared dismiss
  // path both triggers already used.
  //
  // Task 2b: reads `el.getBoundingClientRect()` for the CURRENT on-screen
  // rect — during an active live drag (see onPhotoPointerMove below) that
  // already reflects the imperative `translateY(...)` transform applied so
  // far, so calling dismiss() mid-drag naturally computes "the rest of the
  // way to origin FROM here," continuing smoothly rather than jumping —
  // no special-casing needed for "continue from the current dragged
  // position," it falls out of reading the live rect.
  const dismiss = () => {
    if (closing) return;
    const el = photoRef.current;
    if (!el || !originRect) { closePhoto(); return; }
    const current = el.getBoundingClientRect();
    const scaleX = originRect.width / current.width;
    const scaleY = originRect.height / current.height;
    const dx = (originRect.left + originRect.width / 2) - (current.left + current.width / 2);
    const dy = (originRect.top + originRect.height / 2) - (current.top + current.height / 2);
    // Clears the live-drag inline styles (transform/transition) — the
    // element's OWN declared `transform`/`transition` (in the JSX below)
    // take back over on the next render with the real `closing` value, so
    // this just needs to not leave a stale `transition: none` behind.
    if (backdropRef.current) { backdropRef.current.style.transition = ''; backdropRef.current.style.opacity = ''; }
    if (dimRef.current) { dimRef.current.style.transition = ''; dimRef.current.style.opacity = ''; }
    if (creditRef.current) { creditRef.current.style.transition = ''; creditRef.current.style.opacity = ''; }
    if (taglineRowRef.current) { taglineRowRef.current.style.transition = ''; taglineRowRef.current.style.opacity = ''; }
    setClosing({ transform: `translate(${dx}px, ${dy}px) scale(${scaleX}, ${scaleY})` });
    setTimeout(closePhoto, DISMISS_MS);
  };

  const onBackdropClick = () => dismiss();

  const onPhotoPointerDown = (e) => {
    drag.current = { x: e.clientX, y: e.clientY, dragging: false };
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };

  // Task 2b: live 1:1 tracking for a downward (dismiss-direction) drag —
  // previously this gesture only evaluated dx/dy once, at release
  // (onPhotoPointerUp), with no visual feedback while the finger was still
  // down. Gated so it only engages once the drag is CLEARLY vertical and
  // downward (matches the exact axis-priority check onPhotoPointerUp
  // already used at release, just evaluated progressively) — a horizontal
  // swipe-browse drag is never affected by this at all.
  const onPhotoPointerMove = (e) => {
    if (!drag.current || closing) return;
    const dx = e.clientX - drag.current.x;
    const dy = e.clientY - drag.current.y;
    if (!drag.current.dragging) {
      if (dy < 6 || dy <= Math.abs(dx)) return;
      drag.current.dragging = true;
    }
    const progress = Math.min(1, dy / DRAG_REVEAL_DISTANCE);
    const el = photoRef.current;
    if (el) { el.style.transition = 'none'; el.style.transform = `translateY(${dy}px) scale(${1 - progress * 0.06})`; }
    if (backdropRef.current) { backdropRef.current.style.transition = 'none'; backdropRef.current.style.opacity = String(1 - progress); }
    if (dimRef.current) { dimRef.current.style.transition = 'none'; dimRef.current.style.opacity = String(1 - progress); }
    // Task 4: caption/buttons fade out in step with the backdrop, so they
    // don't stay opaque, floating detached, once the backdrop behind them
    // has mostly revealed Event Detail.
    if (creditRef.current) { creditRef.current.style.transition = 'none'; creditRef.current.style.opacity = String(1 - progress); }
    if (taglineRowRef.current) { taglineRowRef.current.style.transition = 'none'; taglineRowRef.current.style.opacity = String(1 - progress); }
  };

  const onPhotoPointerUp = (e) => {
    if (!drag.current) return;
    const wasDragging = drag.current.dragging;
    const dx = e.clientX - drag.current.x;
    const dy = e.clientY - drag.current.y;
    drag.current = null;
    if (Math.abs(dy) > Math.abs(dx) && dy > GESTURE_THRESHOLD) {
      dismiss();
      return;
    }
    if (wasDragging) {
      // Task 2b: released short of the threshold — spring the live-dragged
      // photo/backdrop back to fully open, same easing/duration as the
      // dismiss animation itself, then hand control back to the element's
      // own declared (identity/opacity-1) style once the spring finishes.
      const el = photoRef.current;
      if (el) { el.style.transition = `transform ${DISMISS_MS}ms ${DISMISS_EASING}`; el.style.transform = ''; }
      if (backdropRef.current) { backdropRef.current.style.transition = `opacity ${DISMISS_MS}ms ease`; backdropRef.current.style.opacity = ''; }
      if (dimRef.current) { dimRef.current.style.transition = `opacity ${DISMISS_MS}ms ease`; dimRef.current.style.opacity = ''; }
      // Task 4: restore caption/buttons to full opacity in sync with the
      // same snap-back transition, rather than leaving them faded.
      if (creditRef.current) { creditRef.current.style.transition = `opacity ${DISMISS_MS}ms ease`; creditRef.current.style.opacity = ''; }
      if (taglineRowRef.current) { taglineRowRef.current.style.transition = `opacity ${DISMISS_MS}ms ease`; taglineRowRef.current.style.opacity = ''; }
      setTimeout(() => {
        if (el) el.style.transition = '';
        if (backdropRef.current) backdropRef.current.style.transition = '';
        if (dimRef.current) dimRef.current.style.transition = '';
        if (creditRef.current) creditRef.current.style.transition = '';
        if (taglineRowRef.current) taglineRowRef.current.style.transition = '';
      }, DISMISS_MS);
      return;
    }
    if (Math.abs(dx) > GESTURE_THRESHOLD) {
      if (dx < 0 && index < gallery.length - 1) showPhotoAt(index + 1);
      else if (dx > 0 && index > 0) showPhotoAt(index - 1);
      // A swipe past the first/last photo just stays put — no loop.
      return;
    }
    // A plain tap: which half of the photo's own width it landed in.
    const rect = photoRef.current?.getBoundingClientRect();
    const tapX = rect ? e.clientX - rect.left : 0;
    const half = rect ? rect.width / 2 : 0;
    if (tapX >= half) {
      if (index < gallery.length - 1) showPhotoAt(index + 1);
    } else {
      if (index > 0) showPhotoAt(index - 1);
    }
  };

  // Faint, but never illegible: the blur underneath can land on any colour,
  // so the white sits on the same soft shadow the on-photo chips use.
  const caption = {
    fontSize: 10.5, letterSpacing: '0.04em',
    color: 'rgba(255,255,255,0.72)', textShadow: '0 1px 3px rgba(27,25,22,0.55)',
    pointerEvents: 'none', maxWidth: 'calc(100% - 130px)',
    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
  };
  // Top-aligned, not centred: centring left as much empty space above the
  // icon as below inside its 34px box, which is what made the row read as
  // sitting further from the photo than the credit text above it.
  const iconButton = (active) => ({
    display: 'flex', alignItems: 'flex-start', justifyContent: 'center',
    width: 34, height: 34, cursor: 'pointer',
    color: active ? '#FFFFFF' : 'rgba(255,255,255,0.72)',
    filter: 'drop-shadow(0 1px 3px rgba(27,25,22,0.55))',
  });
  // The icon buttons sit inside the same element the backdrop's
  // tap-to-close handler covers, so a plain onClick stopPropagation isn't
  // enough on its own — kept here anyway since the buttons are direct
  // children of the stage column, not the backdrop, but stopping
  // propagation defends against event bubbling regardless of exactly which
  // ancestor ends up owning the dismiss handler.
  const stop = (fn) => (e) => { e.stopPropagation(); fn(e); };

  return (
    <div
      data-screen-label="Photo viewer"
      style={{
        position: 'absolute', inset: 0, zIndex: 24, overflow: 'hidden',
        animation: entered ? undefined : 'gocFade 0.2s ease both',
        opacity: closing ? 0 : 1,
        // Always present, even before there's anything to transition —
        // adding this in the SAME render that first changes `opacity`
        // (rather than before it) gives the browser no earlier frame to
        // interpolate from, so the fade would jump straight to its end
        // state instead of animating. Confirmed by measuring the actual
        // computed style frame-by-frame during dismiss before this fix:
        // the value never moved.
        transition: `opacity ${DISMISS_MS}ms ease`,
      }}
    >
      {/* The photo itself, blown up and blurred into a backdrop. Scaled past
          the edges so the blur has no soft, transparent border to show.
          Tapping here (or anywhere else that isn't the photo itself)
          dismisses — this is the "outside" area. */}
      <div
        ref={backdropRef}
        aria-hidden
        onClick={onBackdropClick}
        style={{
          ...bg(url, {
            position: 'absolute', inset: '-12%', borderRadius: 0,
            filter: 'blur(34px) saturate(1.1) brightness(0.62)', transform: 'scale(1.12)',
          }),
        }}
      />
      <div ref={dimRef} aria-hidden onClick={onBackdropClick} style={{ position: 'absolute', inset: 0, background: 'rgba(12,12,12,0.28)' }} />

      {/* The "stage": credit, photo and the tagline/actions row stacked
          tight against one another as one column. The column itself (not
          its full-screen-size flex parent) is what dismisses on tap — the
          photo carves out its own gesture area below, and stopPropagation
          keeps its taps/drags from ever reaching this handler. */}
      <div
        onClick={onBackdropClick}
        style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'center', padding: '0 20px' }}
      >
        <span ref={creditRef} style={{ ...caption, marginBottom: 8 }}>{T('Ảnh của', 'Photo by')} {organizer}</span>
        <div
          ref={photoRef}
          key={index}
          data-testid="photo-viewer-image"
          data-index={index}
          onClick={stop(() => {})}
          onPointerDown={stop(onPhotoPointerDown)}
          onPointerMove={stop(onPhotoPointerMove)}
          onPointerUp={stop(onPhotoPointerUp)}
          style={{
            ...bg(url, {
              width: '100%',
              height: '33vh',
              borderRadius: 14,
              boxShadow: '0 18px 44px rgba(12,12,12,0.4)',
              touchAction: 'none',
              animation: entered ? undefined : 'gocIn 0.22s cubic-bezier(.22,.61,.36,1) both',
              transform: closing ? closing.transform : 'none',
              transformOrigin: 'center',
              // Always present — same reasoning as the backdrop's opacity
              // transition above. `animation: gocIn` (which also animates
              // `transform`) wins over this while it's running; once it
              // finishes the element is at rest with `transform: none` and
              // this transition, so a later JS-driven change to `transform`
              // (dismissing) has an actual prior frame to interpolate from.
              transition: `transform ${DISMISS_MS}ms ${DISMISS_EASING}`,
            }),
          }}
        />
        {/* Top-aligned, not bottom: the row is as tall as the 34px icon
            buttons, and bottom-aligning the tagline text inside that box
            pushed it well below the photo — top-aligning puts it right
            after the marginTop gap, matching the credit's spacing above. */}
        <div ref={taglineRowRef} style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', width: '100%', marginTop: 8 }}>
          <span style={caption}>
            {s.photoShared ? T('Đã sao chép link', 'Link copied') : 'banbe ▪︎ bạn mới mỗi tuần'}
          </span>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 'none' }}>
            {/* A.6 — counts sit immediately LEFT of their icon. No save
                count: the bookmark below saves the EVENT, not the photo
                (there's no real photo-save model in this schema — see the
                ticket's own instruction not to fake one), so it gets no
                count at all, unlike like/share. */}
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <span style={caption}>{engagement.likeCount}</span>
              <span
                onClick={stop(() => togglePhotoLike(photo.id))}
                data-testid="photo-like"
                title={T('Thích ảnh này', 'Like this photo')}
                style={iconButton(liked)}
              ><Icon name="heart" filled={liked} /></span>
            </span>
            <span
              onClick={stop(() => toggleFav(photo.eventId))}
              data-testid="photo-save-event"
              title={T('Lưu sự kiện', 'Save this event')}
              style={iconButton(saved)}
            ><Icon name="bookmark" filled={saved} /></span>
            <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
              <span style={caption}>{engagement.shareCount}</span>
              <span
                onClick={stop(() => sharePhoto({ photo_id: photo.id, organizer_name: organizer }))}
                data-testid="photo-share"
                title={T('Chia sẻ', 'Share')}
                style={iconButton(false)}
              ><Icon name="share" /></span>
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

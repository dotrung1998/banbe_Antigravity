import { useRef } from 'react';
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

// A tapped gallery photo, shown over a fully blurred copy of itself.
// Deliberately not full-screen: the photo sits in the middle third of the
// display with the same 14px corner every other photo in the app has. The
// credit/tagline/actions sit right against the photo's own top and bottom
// edges (not the screen's), and a left/right swipe moves through the rest
// of the gallery it was opened from without closing the viewer.
export default function PhotoViewer() {
  const { state: s, T, closePhoto, showPhotoAt, isPhotoLiked, togglePhotoLike, sharePhotoOrganizer, isSaved, toggleFav } = useGoc();
  const drag = useRef(null);
  if (!s.photoViewer) return null;

  const { gallery, index, organizer, eventKey } = s.photoViewer;
  const url = gallery[index];
  const liked = isPhotoLiked(url);
  const saved = isSaved(eventKey);

  // A swipe past this many px changes the photo; anything short of that
  // (including a plain tap, which never moves at all) closes the viewer —
  // the same "tap anywhere" behaviour this had before swiping existed.
  const SWIPE_THRESHOLD = 44;
  const onPointerDown = (e) => { drag.current = { x: e.clientX }; };
  const onPointerUp = (e) => {
    if (!drag.current) return;
    const dx = e.clientX - drag.current.x;
    drag.current = null;
    if (Math.abs(dx) > SWIPE_THRESHOLD) {
      if (dx < 0 && index < gallery.length - 1) showPhotoAt(index + 1);
      else if (dx > 0 && index > 0) showPhotoAt(index - 1);
      // A swipe past the first/last photo just stays put — nothing to
      // close for, either.
    } else {
      closePhoto();
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
  const iconButton = (active) => ({
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    width: 34, height: 34, cursor: 'pointer',
    color: active ? '#FFFFFF' : 'rgba(255,255,255,0.72)',
    filter: 'drop-shadow(0 1px 3px rgba(27,25,22,0.55))',
  });
  // The icon buttons sit inside the same element the swipe/tap-to-close
  // gesture is attached to, so a plain onClick stopPropagation isn't
  // enough — pointerdown/pointerup still bubble up first and would count
  // as a (very short) tap that closes the viewer out from under the click.
  const stopPointer = (e) => e.stopPropagation();
  const stop = (fn) => (e) => { e.stopPropagation(); fn(); };

  return (
    <div
      data-screen-label="Photo viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 24, overflow: 'hidden', animation: 'gocFade 0.2s ease both' }}
    >
      {/* The photo itself, blown up and blurred into a backdrop. Scaled past
          the edges so the blur has no soft, transparent border to show. */}
      <div
        aria-hidden
        style={{
          ...bg(url, {
            position: 'absolute', inset: '-12%', borderRadius: 0,
            filter: 'blur(34px) saturate(1.1) brightness(0.62)', transform: 'scale(1.12)',
          }),
        }}
      />
      <div aria-hidden style={{ position: 'absolute', inset: 0, background: 'rgba(12,12,12,0.28)' }} />

      {/* The "stage": credit, photo and the tagline/actions row stacked
          tight against one another as one column, so the text sits close
          to the photo's own edges rather than the screen's. Fills the
          screen (not just the column's own width) so a tap/swipe anywhere
          — not just directly on the photo — is caught by the same
          gesture. */}
      <div
        onPointerDown={onPointerDown}
        onPointerUp={onPointerUp}
        style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'center', padding: '0 20px', touchAction: 'pan-y' }}
      >
        <span style={{ ...caption, marginBottom: 8 }}>{T('Ảnh của', 'Photo by')} {organizer}</span>
        <div
          key={index}
          data-testid="photo-viewer-image"
          data-index={index}
          style={{
            ...bg(url, {
              width: '100%',
              height: '33vh',
              borderRadius: 14,
              boxShadow: '0 18px 44px rgba(12,12,12,0.4)',
              animation: 'gocIn 0.22s cubic-bezier(.22,.61,.36,1) both',
            }),
          }}
        />
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', width: '100%', marginTop: 8 }}>
          <span style={caption}>
            {s.photoShared ? T('Đã sao chép link', 'Link copied') : 'banbe ▪︎ bạn mới mỗi tuần'}
          </span>
          <div style={{ display: 'flex', alignItems: 'center', gap: 2, flex: 'none' }}>
            <span
              onClick={stop(() => togglePhotoLike(url))}
              onPointerDown={stopPointer}
              onPointerUp={stopPointer}
              data-testid="photo-like"
              title={T('Thích ảnh này', 'Like this photo')}
              style={iconButton(liked)}
            ><Icon name="heart" filled={liked} /></span>
            <span
              onClick={stop(() => toggleFav(eventKey))}
              onPointerDown={stopPointer}
              onPointerUp={stopPointer}
              data-testid="photo-save-event"
              title={T('Lưu sự kiện', 'Save this event')}
              style={iconButton(saved)}
            ><Icon name="bookmark" filled={saved} /></span>
            <span
              onClick={stop(sharePhotoOrganizer)}
              onPointerDown={stopPointer}
              onPointerUp={stopPointer}
              data-testid="photo-share"
              title={T('Chia sẻ', 'Share')}
              style={iconButton(false)}
            ><Icon name="share" /></span>
          </div>
        </div>
      </div>
    </div>
  );
}

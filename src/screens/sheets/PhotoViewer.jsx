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
// display with the same 14px corner every other photo in the app has, and
// the credit, tagline and actions sit on the blur *outside* it, so nothing
// covers the picture.
export default function PhotoViewer() {
  const { state: s, T, closePhoto, isPhotoLiked, togglePhotoLike, sharePhotoOrganizer, isSaved, toggleFav } = useGoc();
  if (!s.photoViewer) return null;

  const { url, organizer, eventKey } = s.photoViewer;
  const liked = isPhotoLiked(url);
  const saved = isSaved(eventKey);

  // Faint, but never illegible: the blur underneath can land on any colour,
  // so the white sits on the same soft shadow the on-photo chips use.
  const caption = {
    position: 'absolute', fontSize: 10.5, letterSpacing: '0.04em',
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
  const stop = (fn) => (e) => { e.stopPropagation(); fn(); };

  return (
    <div
      onClick={closePhoto}
      data-screen-label="Photo viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 24, overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center', animation: 'gocFade 0.2s ease both' }}
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

      <div
        style={{
          ...bg(url, {
            position: 'relative',
            width: 'calc(100% - 40px)',
            height: '33vh',
            borderRadius: 14,
            boxShadow: '0 18px 44px rgba(12,12,12,0.4)',
            animation: 'gocIn 0.28s cubic-bezier(.22,.61,.36,1) both',
          }),
        }}
      />

      <span style={{ ...caption, top: 18, left: 22 }}>{T('Ảnh của', 'Photo by')} {organizer}</span>
      <span style={{ ...caption, bottom: 22, left: 22 }}>
        {s.photoShared ? T('Đã sao chép link', 'Link copied') : 'banbe ▪︎ bạn mới mỗi tuần'}
      </span>

      <div style={{ position: 'absolute', right: 16, bottom: 14, display: 'flex', alignItems: 'center', gap: 2 }}>
        <span
          onClick={stop(() => togglePhotoLike(url))}
          data-testid="photo-like"
          title={T('Thích ảnh này', 'Like this photo')}
          style={iconButton(liked)}
        ><Icon name="heart" filled={liked} /></span>
        <span
          onClick={stop(() => toggleFav(eventKey))}
          data-testid="photo-save-event"
          title={T('Lưu sự kiện', 'Save this event')}
          style={iconButton(saved)}
        ><Icon name="bookmark" filled={saved} /></span>
        <span
          onClick={stop(sharePhotoOrganizer)}
          data-testid="photo-share"
          title={T('Chia sẻ', 'Share')}
          style={iconButton(false)}
        ><Icon name="share" /></span>
      </div>
    </div>
  );
}

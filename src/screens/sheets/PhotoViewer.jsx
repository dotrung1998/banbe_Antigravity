import { useGoc } from '../../state/GocContext.jsx';
import { bg } from '../../data/events.js';

// A tapped gallery photo, shown larger over a dimmed backdrop — deliberately
// not full-screen: it sits in the middle third of the display, keeping the
// same 14px corner the photos everywhere else in the app have (see bg() in
// data/events.js). Tapping anywhere closes it.
export default function PhotoViewer() {
  const { state: s, T, closePhoto } = useGoc();
  if (!s.photoViewer) return null;

  const { url, organizer } = s.photoViewer;
  // Faint, but never illegible: a photo can be any colour underneath, so the
  // white sits on the same soft shadow the on-photo chips use.
  const caption = {
    position: 'absolute', left: 14, fontSize: 10.5, letterSpacing: '0.04em',
    color: 'rgba(255,255,255,0.72)', textShadow: '0 1px 3px rgba(27,25,22,0.55)',
    pointerEvents: 'none',
  };

  return (
    <div
      onClick={closePhoto}
      data-screen-label="Photo viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 24, background: 'rgba(12,12,12,0.72)', display: 'flex', alignItems: 'center', justifyContent: 'center', animation: 'gocFade 0.2s ease both' }}
    >
      <div
        style={{
          ...bg(url, {
            position: 'relative',
            width: 'calc(100% - 40px)',
            height: '33vh',
            borderRadius: 14,
            animation: 'gocIn 0.28s cubic-bezier(.22,.61,.36,1) both',
          }),
        }}
      >
        <span style={{ ...caption, top: 12 }}>{T('Ảnh của', 'Photo by')} {organizer}</span>
        <span style={{ ...caption, bottom: 12 }}>banbe ▪︎ bạn mới mỗi tuần</span>
      </div>
    </div>
  );
}

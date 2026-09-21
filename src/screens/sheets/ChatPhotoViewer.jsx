import { useEffect, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, rule } from '../../theme.js';

// Task 2 (07-notifications.md / 14-photo-viewer.md follow-up) — a chat
// photo's own dedicated fullscreen viewer. Deliberately a SEPARATE
// component/state from PhotoViewer.jsx (event-gallery photos), per this
// ticket's own instruction — different action set (Save/Share/Forward, not
// Like/Save-event), and must never be confused with an Event Detail photo.
// Reuses PhotoViewer's backdrop + dismiss-motion CONVENTIONS (blurred
// backdrop, shrink-toward-origin) rather than its code: PhotoViewer's own
// dismiss logic is built around a *gallery* (prev/next swipe, liked photos,
// event-key-scoped save) that doesn't apply here, and retrofitting it would
// risk regressing that already-verified component. A live drag-follow
// (14-photo-viewer.md's later refinement) was judged not worth duplicating
// for a single non-browsable image — dismiss here is a single eased
// transform computed once, not a per-frame pointer tracker.
const DISMISS_MS = 260;
const DISMISS_EASING = 'cubic-bezier(.22,.61,.36,1)';

export default function ChatPhotoViewer() {
  const { state: s, T, closeChatPhoto, downloadChatPhoto, shareChatPhoto, openChatForward, closeChatForward, forwardChatPhoto } = useGoc();
  const item = s.chatPhotoViewer;
  const [menuOpen, setMenuOpen] = useState(false);
  const [closing, setClosing] = useState(false);
  const [actionMsg, setActionMsg] = useState('');

  useEffect(() => { setClosing(false); setMenuOpen(false); setActionMsg(''); }, [item?.messageId]);

  if (!item) return null;

  const dismiss = () => {
    if (closing) return;
    setClosing(true);
    setTimeout(closeChatPhoto, DISMISS_MS);
  };

  const doDownload = async () => {
    setMenuOpen(false);
    const r = await downloadChatPhoto();
    setActionMsg(r?.success ? T('Đã lưu ảnh', 'Photo saved') : T('Không lưu được ảnh', "Couldn't save photo"));
  };
  const doShare = async () => {
    setMenuOpen(false);
    await shareChatPhoto();
  };
  const doForward = () => { setMenuOpen(false); openChatForward(); };

  const eligibleThreads = (s.inboxThreads || []).filter(t => t.threadId !== s.chatThreadId);

  // originRect-based shrink: falls back to a plain fade+scale-down if no
  // rect was captured (e.g. opened from a context without one).
  const originStyle = item.originRect
    ? { transformOrigin: `${item.originRect.left + item.originRect.width / 2}px ${item.originRect.top + item.originRect.height / 2}px` }
    : {};

  return (
    <div
      data-screen-label="Chat photo viewer"
      style={{ position: 'absolute', inset: 0, zIndex: 26, overflow: 'hidden', background: 'rgba(12,12,12,0.9)', opacity: closing ? 0 : 1, transition: `opacity ${DISMISS_MS}ms ease` }}
      onClick={dismiss}
    >
      <img
        src={item.url}
        alt=""
        data-testid="chat-photo-viewer-image"
        style={{
          position: 'absolute', top: '50%', left: '50%', maxWidth: '92vw', maxHeight: '70vh',
          transform: closing ? `translate(-50%,-50%) scale(0.86)` : 'translate(-50%,-50%) scale(1)',
          borderRadius: 14, boxShadow: '0 18px 44px rgba(12,12,12,0.5)',
          transition: `transform ${DISMISS_MS}ms ${DISMISS_EASING}`,
          ...originStyle,
        }}
        onClick={(e) => e.stopPropagation()}
      />

      <div onClick={(e) => e.stopPropagation()} style={{ position: 'absolute', top: 56, left: 18, right: 18, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span onClick={dismiss} data-testid="chat-photo-close" style={{ color: '#fff', fontSize: 22, cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>×</span>
        <span onClick={() => setMenuOpen(v => !v)} data-testid="chat-photo-menu" style={{ color: '#fff', fontSize: 20, cursor: 'pointer', letterSpacing: 2, filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>•••</span>
      </div>

      {actionMsg && (
        <div style={{ position: 'absolute', top: 96, left: '50%', transform: 'translateX(-50%)', background: 'rgba(255,255,255,0.92)', color: ink, fontSize: 12, fontWeight: 600, padding: '8px 14px', borderRadius: 999 }}>
          {actionMsg}
        </div>
      )}

      {/* Task 4 — visible short labels, not icon-only. */}
      {menuOpen && (
        <div onClick={(e) => { e.stopPropagation(); setMenuOpen(false); }} style={{ position: 'absolute', inset: 0 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ position: 'absolute', top: 94, right: 18, background: paper, borderRadius: 14, padding: 6, minWidth: 200, boxShadow: '0 12px 28px rgba(12,12,12,0.4)' }}>
            <div onClick={doDownload} data-testid="chat-photo-save" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8 }}>{T('Lưu ảnh', 'Save photo')}</div>
            <div onClick={doShare} data-testid="chat-photo-share" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8 }}>{T('Chia sẻ', 'Share')}</div>
            {eligibleThreads.length > 0 && (
              <div onClick={doForward} data-testid="chat-photo-forward" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8 }}>{T('Chuyển tiếp', 'Forward')}</div>
            )}
          </div>
        </div>
      )}

      {item.forwardOpen && (
        <div onClick={closeChatForward} style={{ position: 'absolute', inset: 0, background: 'rgba(12,12,12,0.55)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '20px 20px 30px', maxHeight: '60vh', overflow: 'auto' }}>
            <span style={{ fontSize: 13, fontWeight: 700, color: ink }}>{T('Chuyển tiếp đến', 'Forward to')}</span>
            <div style={{ display: 'flex', flexDirection: 'column', marginTop: 12 }}>
              {eligibleThreads.map(t => (
                <div key={t.threadId} onClick={() => forwardChatPhoto(t.threadId)} data-testid="chat-forward-target" style={{ padding: '13px 2px', borderBottom: `1px solid ${rule}`, fontSize: 14, color: ink, cursor: 'pointer' }}>
                  {t.name}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

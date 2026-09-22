import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, rule } from '../../theme.js';
import { AttachMenuIcon } from '../Chat.jsx';

// Task 2 (2026-09-22 real-device follow-up, 07-notifications.md /
// 14-photo-viewer.md) — revised interaction model for the chat photo
// viewer, per real-device feedback:
// - A tap on the blank backdrop OR the photo itself no longer dismisses —
//   it toggles "chrome" (top bar + bottom composer) visibility, entering a
//   cleaner true-fullscreen presentation.
// - ONLY a downward drag past DISMISS_THRESHOLD dismisses, reusing
//   14-photo-viewer.md's established live-drag-follow convention (photo
//   tracks the finger 1:1, chrome/backdrop fade with drag progress,
//   release short of threshold springs back) — ref-driven, not
//   React-state-driven, for the same per-frame-churn reason that file's
//   own drag code already documents.
const DISMISS_MS = 260;
const DISMISS_EASING = 'cubic-bezier(.22,.61,.36,1)';
const DRAG_THRESHOLD = 90; // px of downward travel that commits to dismiss
const DRAG_REVEAL_DISTANCE = 220; // px of travel over which chrome/backdrop fully fades

// A small, fixed set of common reactions — not a full emoji-picker library
// (this app has none, and pulling one in for six buttons isn't worth it).
const QUICK_EMOJI = ['❤️', '😂', '😮', '😢', '👏', '🔥'];

export default function ChatPhotoViewer() {
  const {
    state: s, T, closeChatPhoto, downloadChatPhoto, shareChatPhoto, openChatForward, closeChatForward, forwardChatPhoto,
    openPostToStoryConfirm, closePostToStoryConfirm, postChatPhotoToStory, sendChatViewerReply, sendChatAttachment, canHost,
  } = useGoc();
  const item = s.chatPhotoViewer;
  const [menuOpen, setMenuOpen] = useState(false);
  const [closing, setClosing] = useState(false);
  const [actionMsg, setActionMsg] = useState('');
  const [chromeHidden, setChromeHidden] = useState(false);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [copySupported, setCopySupported] = useState(false);
  const [replyError, setReplyError] = useState('');

  const photoRef = useRef(null);
  const topBarRef = useRef(null);
  const bottomBarRef = useRef(null);
  const backdropDimRef = useRef(null);
  const drag = useRef(null);
  const fileInputRef = useRef(null);

  useEffect(() => {
    setClosing(false); setMenuOpen(false); setActionMsg(''); setChromeHidden(false); setDraft(''); setReplyError('');
  }, [item?.messageId]);

  useEffect(() => {
    setCopySupported(typeof navigator !== 'undefined' && !!navigator.clipboard && typeof window.ClipboardItem !== 'undefined');
  }, []);

  if (!item) return null;

  const dismiss = () => {
    if (closing) return;
    setClosing(true);
    setTimeout(closeChatPhoto, DISMISS_MS);
  };

  const clearDragStyles = () => {
    [photoRef, topBarRef, bottomBarRef, backdropDimRef].forEach(r => {
      if (r.current) { r.current.style.transition = ''; r.current.style.transform = ''; r.current.style.opacity = ''; }
    });
  };

  const onStagePointerDown = (e) => {
    drag.current = { y: e.clientY, dragging: false };
    e.currentTarget.setPointerCapture?.(e.pointerId);
  };
  const onStagePointerMove = (e) => {
    if (!drag.current || closing) return;
    const dy = e.clientY - drag.current.y;
    if (!drag.current.dragging) {
      if (dy < 6) return; // only a downward drag counts — ignores tiny jitter and upward moves
      drag.current.dragging = true;
    }
    const progress = Math.min(1, dy / DRAG_REVEAL_DISTANCE);
    if (photoRef.current) { photoRef.current.style.transition = 'none'; photoRef.current.style.transform = `translate(-50%, calc(-50% + ${dy}px)) scale(${1 - progress * 0.08})`; }
    if (backdropDimRef.current) { backdropDimRef.current.style.transition = 'none'; backdropDimRef.current.style.opacity = String(1 - progress); }
    if (topBarRef.current) { topBarRef.current.style.transition = 'none'; topBarRef.current.style.opacity = String(1 - progress); }
    if (bottomBarRef.current) { bottomBarRef.current.style.transition = 'none'; bottomBarRef.current.style.opacity = String(1 - progress); }
  };
  const onStagePointerUp = () => {
    if (!drag.current) return;
    const wasDragging = drag.current.dragging;
    const dy = drag.current.lastDy || 0;
    drag.current = null;
    if (!wasDragging) {
      // A plain tap (backdrop or photo, same handler) — toggle chrome, never dismiss.
      setChromeHidden(v => !v);
      return;
    }
    if (dy > DRAG_THRESHOLD) { dismiss(); return; }
    // Short of the threshold — spring everything back to fullscreen rest.
    [photoRef, backdropDimRef, topBarRef, bottomBarRef].forEach(r => {
      if (r.current) { r.current.style.transition = `all ${DISMISS_MS}ms ${DISMISS_EASING}`; r.current.style.transform = ''; r.current.style.opacity = ''; }
    });
    setTimeout(clearDragStyles, DISMISS_MS);
  };
  // Track dy on every move for onStagePointerUp to read without re-deriving
  // clientY math from a possibly-stale event.
  const onStagePointerMoveTracked = (e) => { if (drag.current) drag.current.lastDy = e.clientY - drag.current.y; onStagePointerMove(e); };

  const doDownload = async () => {
    setMenuOpen(false);
    const r = await downloadChatPhoto();
    setActionMsg(r?.success ? T('Đã lưu ảnh', 'Photo saved') : T('Không lưu được ảnh', "Couldn't save photo"));
    setTimeout(() => setActionMsg(''), 2200);
  };
  const doShare = async () => { setMenuOpen(false); await shareChatPhoto(); };
  const doForward = () => { setMenuOpen(false); openChatForward(); };
  const doCopy = async () => {
    setMenuOpen(false);
    try {
      const res = await fetch(item.url);
      const blob = await res.blob();
      await navigator.clipboard.write([new window.ClipboardItem({ [blob.type || 'image/png']: blob })]);
      setActionMsg(T('Đã sao chép ảnh', 'Image copied'));
    } catch {
      setActionMsg(T('Không sao chép được', "Couldn't copy"));
    }
    setTimeout(() => setActionMsg(''), 2200);
  };

  // Task 5 (2026-09-22 twelfth follow-up) — on success, sendChatViewerReply
  // itself closes the viewer (chatPhotoViewer: null) and sets
  // chatScrollToMessageId/chatFocusComposer for Chat.jsx to pick up; on
  // failure it returns { success: false } and leaves the viewer open, so
  // the only thing left to do here is surface a clear error.
  const doQuickReaction = async (emoji) => {
    if (sending) return;
    setSending(true);
    const r = await sendChatViewerReply(emoji, item.messageId, false);
    setSending(false);
    if (!r?.success) { setReplyError(T('Không gửi được', "Couldn't send")); setTimeout(() => setReplyError(''), 2200); }
  };
  const doSendReply = async () => {
    if (!draft.trim() || sending) return;
    setSending(true);
    const r = await sendChatViewerReply(draft, item.messageId, true);
    setSending(false);
    if (r?.success) { setDraft(''); } else { setReplyError(T('Không gửi được', "Couldn't send")); setTimeout(() => setReplyError(''), 2200); }
  };
  const onPickReplyFile = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || sending) return;
    setSending(true);
    const r = await sendChatAttachment(file, item.messageId);
    setSending(false);
    if (!r?.success) { setReplyError(T('Không gửi được', "Couldn't send")); setTimeout(() => setReplyError(''), 2200); }
  };

  const eligibleThreads = (s.inboxThreads || []).filter(t => t.threadId !== s.chatThreadId);

  const originStyle = item.originRect
    ? { transformOrigin: `${item.originRect.left + item.originRect.width / 2}px ${item.originRect.top + item.originRect.height / 2}px` }
    : {};

  return (
    <div
      data-screen-label="Chat photo viewer"
      data-chrome={chromeHidden ? 'hidden' : 'visible'}
      style={{ position: 'absolute', inset: 0, zIndex: 26, overflow: 'hidden', background: '#000', opacity: closing ? 0 : 1, transition: `opacity ${DISMISS_MS}ms ease` }}
    >
      <div ref={backdropDimRef} aria-hidden style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.94)' }} />

      <div
        data-testid="chat-photo-stage"
        onPointerDown={onStagePointerDown}
        onPointerMove={onStagePointerMoveTracked}
        onPointerUp={onStagePointerUp}
        style={{ position: 'absolute', inset: 0, touchAction: 'none' }}
      >
        <img
          ref={photoRef}
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
        />
      </div>

      {/* Top bar — Task 2.3: close (left), Post to Story / Save / More (right). */}
      <div
        ref={topBarRef}
        onClick={(e) => e.stopPropagation()}
        style={{
          position: 'absolute', top: 56, left: 18, right: 18, display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          opacity: chromeHidden ? 0 : 1, pointerEvents: chromeHidden ? 'none' : 'auto', transition: `opacity ${DISMISS_MS}ms ease`,
        }}
      >
        <span onClick={dismiss} data-testid="chat-photo-close" style={{ color: '#fff', fontSize: 22, cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>×</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 18 }}>
          {canHost && (
            <span onClick={openPostToStoryConfirm} data-testid="chat-photo-post-story" title={T('Đăng story', 'Post to Story')} style={{ color: '#fff', cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="8.5" /><path d="M12 8v8M8 12h8" /></svg>
            </span>
          )}
          <span onClick={doDownload} data-testid="chat-photo-save" title={T('Lưu ảnh', 'Save')} style={{ color: '#fff', cursor: 'pointer', filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3.5v11.5M7.5 10.5 12 15l4.5-4.5" /><path d="M5 18.5h14" /></svg>
          </span>
          <span onClick={() => setMenuOpen(v => !v)} data-testid="chat-photo-menu" style={{ color: '#fff', fontSize: 20, cursor: 'pointer', letterSpacing: 2, filter: 'drop-shadow(0 1px 3px rgba(12,12,12,0.55))' }}>•••</span>
        </div>
      </div>

      {actionMsg && (
        <div style={{ position: 'absolute', top: 96, left: '50%', transform: 'translateX(-50%)', background: 'rgba(255,255,255,0.92)', color: ink, fontSize: 12, fontWeight: 600, padding: '8px 14px', borderRadius: 999 }}>
          {actionMsg}
        </div>
      )}

      {/* More menu — banbe-styled rows, icon left + text right. Copy only
          shown when the platform actually supports it (Clipboard API +
          ClipboardItem); Edit/Live Text intentionally NOT included this
          pass — see 07-notifications.md for why, rather than shipping a
          dead/half-working action. */}
      {menuOpen && (
        <div onClick={(e) => { e.stopPropagation(); setMenuOpen(false); }} style={{ position: 'absolute', inset: 0 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ position: 'absolute', top: 94, right: 18, background: paper, borderRadius: 14, padding: 6, minWidth: 210, boxShadow: '0 12px 28px rgba(12,12,12,0.4)' }}>
            <div onClick={doShare} data-testid="chat-photo-share" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
              <ShareIcon /> {T('Chia sẻ', 'Share')}
            </div>
            {eligibleThreads.length > 0 && (
              <div onClick={doForward} data-testid="chat-photo-forward" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
                <ForwardIcon /> {T('Chuyển tiếp', 'Forward')}
              </div>
            )}
            {copySupported && (
              <div onClick={doCopy} data-testid="chat-photo-copy" style={{ padding: '12px 14px', fontSize: 13.5, color: ink, cursor: 'pointer', borderRadius: 8, display: 'flex', alignItems: 'center', gap: 10 }}>
                <CopyIcon /> {T('Sao chép ảnh', 'Copy image')}
              </div>
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

      {/* Task 2.3a — a real review step before publishing, per this
          ticket's own instruction ("do not immediately publish by
          accidental tap"). */}
      {item.postToStoryConfirm && (
        <div onClick={s.storyCreateBusy ? undefined : closePostToStoryConfirm} style={{ position: 'absolute', inset: 0, background: 'rgba(12,12,12,0.6)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, padding: '22px 20px 30px' }}>
            <span style={{ fontSize: 13.5, fontWeight: 700, color: ink }}>{T('Đăng ảnh này lên story?', 'Post this photo to your Story?')}</span>
            <p style={{ fontSize: 12, color: ink, opacity: 0.7, margin: '8px 0 0' }}>{T('Story sẽ tự động ẩn sau 24 giờ.', 'Your Story disappears automatically after 24 hours.')}</p>
            <div style={{ display: 'flex', gap: 10, marginTop: 16 }}>
              <div onClick={closePostToStoryConfirm} style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 12, border: `1px solid ${rule}`, color: ink, fontSize: 13.5, fontWeight: 600, cursor: 'pointer' }}>{T('Huỷ', 'Cancel')}</div>
              <div
                onClick={s.storyCreateBusy ? undefined : async () => {
                  const r = await postChatPhotoToStory();
                  setActionMsg(r?.success ? T('Đã đăng story', 'Posted to Story') : T('Không đăng được', "Couldn't post"));
                  setTimeout(() => setActionMsg(''), 2200);
                }}
                data-testid="chat-photo-post-story-confirm"
                style={{ flex: 1, textAlign: 'center', padding: 13, borderRadius: 12, background: ink, color: paper, fontSize: 13.5, fontWeight: 600, cursor: 'pointer', opacity: s.storyCreateBusy ? 0.6 : 1 }}
              >
                {s.storyCreateBusy ? T('Đang đăng…', 'Posting…') : T('Đăng story', 'Post')}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Task 3 — reply/reaction composer. */}
      <div
        ref={bottomBarRef}
        onClick={(e) => e.stopPropagation()}
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0, padding: '10px 14px calc(env(safe-area-inset-bottom, 0px) + 14px)',
          background: 'linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,0.75) 40%, rgba(0,0,0,0.85) 100%)',
          opacity: chromeHidden ? 0 : 1, pointerEvents: chromeHidden ? 'none' : 'auto', transition: `opacity ${DISMISS_MS}ms ease`,
        }}
      >
        {replyError && (
          <div data-testid="chat-photo-reply-error" style={{ fontSize: 11.5, color: '#ff8a8a', marginBottom: 6 }}>{replyError}</div>
        )}
        <div style={{ display: 'flex', gap: 6, marginBottom: 8, overflowX: 'auto' }}>
          {QUICK_EMOJI.map(e => (
            <span key={e} onClick={() => doQuickReaction(e)} data-testid="chat-photo-quick-reaction" style={{ fontSize: 20, cursor: 'pointer', padding: '2px 4px' }}>{e}</span>
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span onClick={() => fileInputRef.current?.click()} data-testid="chat-photo-reply-attach" style={{ color: '#fff', cursor: 'pointer', flex: 'none' }}>
            <AttachMenuIcon name="library" />
          </span>
          <input ref={fileInputRef} type="file" accept="image/*,application/pdf" style={{ display: 'none' }} onChange={onPickReplyFile} data-testid="chat-photo-reply-file-input" />
          <input
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') doSendReply(); }}
            placeholder={T('Trả lời ảnh này…', 'Reply to this photo…')}
            data-testid="chat-photo-reply-input"
            style={{ flex: 1, padding: '10px 14px', borderRadius: 999, border: 'none', background: 'rgba(255,255,255,0.16)', color: '#fff', fontSize: 13.5, outline: 'none' }}
          />
          <span onClick={doSendReply} data-testid="chat-photo-reply-send" style={{ color: '#fff', fontSize: 13, fontWeight: 700, cursor: 'pointer', flex: 'none', opacity: draft.trim() ? 1 : 0.5 }}>
            {T('Gửi', 'Send')}
          </span>
        </div>
      </div>
    </div>
  );
}

function ShareIcon() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="18" cy="5.5" r="2.6" /><circle cx="6" cy="12" r="2.6" /><circle cx="18" cy="18.5" r="2.6" /><path d="M8.3 10.7 15.7 7M8.3 13.3l7.4 3.7" /></svg>;
}
function ForwardIcon() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M13 6l6 6-6 6" /><path d="M5 6v4a4 4 0 0 0 4 4h10" /></svg>;
}
function CopyIcon() {
  return <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="8.5" y="8.5" width="11" height="11" rx="2" /><path d="M15.5 8.5V6a1.5 1.5 0 0 0-1.5-1.5H6A1.5 1.5 0 0 0 4.5 6v8A1.5 1.5 0 0 0 6 15.5h2.5" /></svg>;
}

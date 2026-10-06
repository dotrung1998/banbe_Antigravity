import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { ink, rule, cardGlass } from '../theme.js';

// Small, ephemeral in-app toasts — separate from Notifications.jsx (the
// permanent, pull-based inbox): this is what actually surfaces an event
// (booking confirmed, dispute resolved, a new dispute chat message, etc.)
// while the app is already open, instead of it sitting invisible until
// someone happens to open the bell screen. See .claude/notes/07-notifications.md.
//
// Fixed to the viewport rather than the scrollable screen content below it
// (same reason Loading.jsx/the sheets escape scroll position), centered to
// match this app's own centered 480px column regardless of viewport width.
//
// Only the visible stack is ever capped (VISIBLE_COUNT) — "Xem thêm" reveals
// the rest of the SAME local queue in place, it never fetches anything.
// "Tắt tất cả" and every dismiss path here (individual/see-more/all) only
// ever touch this local `state.toasts` queue via dismissToast/dismissAllToasts
// — neither calls markNotificationRead(), so the bell inbox's unread state
// and badge count are untouched by anything on this screen. See
// .claude/notes/07-notifications.md.
const VISIBLE_COUNT = 3;
// Same media query index.css uses to draw the desktop phone frame: there the
// frame's own status bar occupies the top 50px, so (like iOS's safe-area top
// padding) the banner sits just below it instead of over the Dynamic Island.
const IN_PHONE_FRAME = typeof window !== 'undefined' && !!window.matchMedia
  && window.matchMedia('(min-width: 700px) and (min-height: 560px) and (hover: hover) and (pointer: fine)').matches;

// Notification banner fix pass (2026-09-30 third) — one toast card,
// factored out so it can own its own mount effect (marks the auto-dismiss
// timer's real start, BanBeContext.jsx's own `markToastVisible` doc comment)
// and its own pointer/touch handlers (pause/resume the SAME real timer,
// never just a visual state). The whole card is the tap target — the ✕
// button is the only nested target, and it stops propagation so it doesn't
// also fire the card's own open-notification tap.
function ToastCard({ t, markVisible, onOpen, onDismiss, onPause, onResume }) {
  // Duration starts here — when this card is actually mounted/visible — not
  // at whatever earlier moment pushToast() enqueued it (it may have sat
  // behind "Xem thêm" until now). `markToastVisible` itself is idempotent,
  // so a re-render of an already-ticking toast never restarts its clock.
  useEffect(() => { markVisible(t.id); }, [markVisible, t.id]);
  return (
    <div
      key={t.id}
      data-testid="toast"
      onClick={onOpen}
      onPointerEnter={onPause}
      onPointerLeave={onResume}
      onTouchStart={onPause}
      onTouchEnd={onResume}
      style={{
        ...cardGlass({ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 2 }),
        border: `1px solid ${rule}`,
        cursor: 'pointer', pointerEvents: 'auto',
        animation: t.leaving ? 'banbeToastOut 0.28s ease both' : 'banbeToastIn 0.3s cubic-bezier(.22,.61,.36,1) both',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', gap: 8 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
          {t.notification?.title && <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{t.notification.title}</span>}
          {t.notification?.body && <span style={{ fontSize: 12, color: ink, opacity: 0.75, lineHeight: 1.4 }}>{t.notification.body}</span>}
        </div>
        <button
          type="button"
          data-testid="toast-dismiss"
          aria-label="Đóng"
          onClick={(e) => { e.stopPropagation(); onDismiss(); }}
          style={{
            flexShrink: 0, width: 20, height: 20, borderRadius: '50%', border: 'none',
            background: 'transparent', color: ink, opacity: 0.55, fontSize: 14, lineHeight: 1,
            cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <svg width={10} height={10} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={3} strokeLinecap="round"><path d="M5 5l14 14M19 5L5 19" /></svg>
        </button>
      </div>
    </div>
  );
}

export default function ToastStack() {
  const { state, openNotification, dismissToast, dismissAllToasts, markToastVisible, pauseToastTimer, resumeToastTimer } = useBanBe();
  const toasts = state.toasts || [];
  const [expanded, setExpanded] = useState(false);
  if (toasts.length === 0) return null;

  const hiddenCount = toasts.length - VISIBLE_COUNT;
  const shown = expanded || hiddenCount <= 0 ? toasts : toasts.slice(0, VISIBLE_COUNT);

  return (
    <div
      style={{
        position: 'fixed', top: IN_PHONE_FRAME ? 58 : 14, left: '50%', transform: 'translateX(-50%)',
        width: 'calc(100% - 32px)', maxWidth: 448, zIndex: 80,
        display: 'flex', flexDirection: 'column', gap: 8, pointerEvents: 'none',
      }}
    >
      {shown.map(t => (
        <ToastCard
          key={t.id}
          t={t}
          markVisible={markToastVisible}
          onOpen={() => {
            // Race fix: cancel the auto-dismiss timer synchronously, before
            // openNotification's own async work resolves, so the banner
            // can't disappear out from under an in-flight tap.
            dismissToast(t.id);
            if (t.notification) openNotification(t.notification);
          }}
          onDismiss={() => dismissToast(t.id)}
          onPause={() => pauseToastTimer(t.id)}
          onResume={() => resumeToastTimer(t.id)}
        />
      ))}
      {(hiddenCount > 0 || toasts.length > 1) && (
        <div style={{ display: 'flex', gap: 8, justifyContent: 'center', pointerEvents: 'auto' }}>
          {!expanded && hiddenCount > 0 && (
            <button
              type="button"
              data-testid="toast-see-more"
              onClick={() => setExpanded(true)}
              style={{
                ...cardGlass({ padding: '6px 12px' }),
                border: `1px solid ${rule}`, cursor: 'pointer',
                fontSize: 11.5, fontWeight: 600, color: ink,
              }}
            >
              Xem thêm ({hiddenCount})
            </button>
          )}
          {toasts.length > 1 && (
            <button
              type="button"
              data-testid="toast-dismiss-all"
              onClick={() => { dismissAllToasts(); setExpanded(false); }}
              style={{
                ...cardGlass({ padding: '6px 12px' }),
                border: `1px solid ${rule}`, cursor: 'pointer',
                fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.75,
              }}
            >
              Tắt tất cả
            </button>
          )}
        </div>
      )}
    </div>
  );
}

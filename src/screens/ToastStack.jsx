import { useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
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

export default function ToastStack() {
  const { state, openNotification, dismissToast, dismissAllToasts } = useGoc();
  const toasts = state.toasts || [];
  const [expanded, setExpanded] = useState(false);
  if (toasts.length === 0) return null;

  const hiddenCount = toasts.length - VISIBLE_COUNT;
  const shown = expanded || hiddenCount <= 0 ? toasts : toasts.slice(0, VISIBLE_COUNT);

  return (
    <div
      style={{
        position: 'fixed', top: 14, left: '50%', transform: 'translateX(-50%)',
        width: 'calc(100% - 32px)', maxWidth: 448, zIndex: 80,
        display: 'flex', flexDirection: 'column', gap: 8, pointerEvents: 'none',
      }}
    >
      {shown.map(t => (
        <div
          key={t.id}
          data-testid="toast"
          onClick={() => {
            if (t.notification) openNotification(t.notification);
            dismissToast(t.id); // don't wait for the auto-dismiss timer — it's been acted on
          }}
          style={{
            ...cardGlass({ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 2 }),
            border: `1px solid ${rule}`,
            cursor: 'pointer', pointerEvents: 'auto',
            animation: t.leaving ? 'gocToastOut 0.28s ease both' : 'gocToastIn 0.3s cubic-bezier(.22,.61,.36,1) both',
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
              onClick={(e) => { e.stopPropagation(); dismissToast(t.id); }}
              style={{
                flexShrink: 0, width: 20, height: 20, borderRadius: '50%', border: 'none',
                background: 'transparent', color: ink, opacity: 0.55, fontSize: 14, lineHeight: 1,
                cursor: 'pointer', padding: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
            >
              ✕
            </button>
          </div>
        </div>
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

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
export default function ToastStack() {
  const { state, openNotification, dismissToast } = useGoc();
  const toasts = state.toasts || [];
  if (toasts.length === 0) return null;

  return (
    <div
      style={{
        position: 'fixed', top: 14, left: '50%', transform: 'translateX(-50%)',
        width: 'calc(100% - 32px)', maxWidth: 448, zIndex: 80,
        display: 'flex', flexDirection: 'column', gap: 8, pointerEvents: 'none',
      }}
    >
      {toasts.map(t => (
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
          {t.notification?.title && <span style={{ fontSize: 12.5, fontWeight: 600, color: ink }}>{t.notification.title}</span>}
          {t.notification?.body && <span style={{ fontSize: 12, color: ink, opacity: 0.75, lineHeight: 1.4 }}>{t.notification.body}</span>}
        </div>
      ))}
    </div>
  );
}

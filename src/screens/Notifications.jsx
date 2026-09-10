import { useGoc } from '../state/GocContext.jsx';
import { agoLabel } from '../data/events.js';
import { paper, ink, display } from '../theme.js';

export default function Notifications() {
  const { state, T, trStatus, goHome, markNotificationRead } = useGoc();
  const s = state;

  const withAgo = (n) => ({
    ...n,
    ago: trStatus(agoLabel(Math.max(1, Math.round((Date.now() - new Date(n.created_at).getTime()) / 3600000)))),
  });
  const unread = s.notifications.filter(n => !n.read_at).map(withAgo);
  const read = s.notifications.filter(n => n.read_at).map(withAgo);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Notifications">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(27) }}>{T('Thông báo', 'Notifications')}</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('Xong', 'Done')}</span>
      </div>
      {(unread.length > 0 || read.length > 0) ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {unread.length > 0 && (
            <Section title={T('Chưa đọc', 'Unread')}>
              {unread.map(n => (
                <Row key={n.id} n={n} unread onClick={() => markNotificationRead(n.id)} />
              ))}
            </Section>
          )}
          {read.length > 0 && (
            <Section title={T('Đã đọc', 'Read')}>
              {read.map(n => <Row key={n.id} n={n} />)}
            </Section>
          )}
        </div>
      ) : (
        <div style={{ padding: '80px 40px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{T('Chưa có thông báo nào.', 'No notifications yet.')}</p>
        </div>
      )}
    </div>
  );
}

function Section({ title, children }) {
  return (
    <div style={{ marginBottom: 22 }}>
      <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.04em', color: ink, opacity: 0.6, textTransform: 'uppercase' }}>{title}</span>
      <div style={{ marginTop: 6 }}>{children}</div>
    </div>
  );
}

function Row({ n, unread, onClick }) {
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', gap: 10, padding: '14px 0',
        borderBottom: '1px solid rgba(27,25,22,0.16)',
        cursor: unread ? 'pointer' : 'default',
        opacity: unread ? 1 : 0.6,
      }}
    >
      <span aria-hidden style={{ flex: 'none', width: 7, height: 7, borderRadius: '50%', marginTop: 6, background: unread ? ink : 'transparent' }} />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0, flex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
          <span style={{ ...display(16, { lineHeight: 1.3 }), fontWeight: unread ? 700 : 400 }}>{n.title}</span>
          <span style={{ fontSize: 11, color: ink, flex: 'none', whiteSpace: 'nowrap' }}>{n.ago}</span>
        </div>
        <span style={{ fontSize: 13, lineHeight: 1.5, color: ink, fontWeight: unread ? 600 : 400 }}>{n.body}</span>
      </div>
    </div>
  );
}

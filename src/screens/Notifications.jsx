import { useEffect } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { agoLabel } from '../data/events.js';
import { paper, ink, display } from '../theme.js';

export default function Notifications() {
  const { state, T, trStatus, goHome, markNotificationsRead } = useGoc();
  const s = state;

  useEffect(() => {
    markNotificationsRead();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const items = s.notifications.map(n => ({
    ...n,
    ago: trStatus(agoLabel(Math.max(1, Math.round((Date.now() - new Date(n.created_at).getTime()) / 3600000)))),
  }));

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Notifications">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(27) }}>{T('Thông báo', 'Notifications')}</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('Xong', 'Done')}</span>
      </div>
      {items.length > 0 ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {items.map(n => (
            <div key={n.id} style={{ display: 'flex', flexDirection: 'column', gap: 4, padding: '16px 0', borderBottom: '1px solid rgba(27,25,22,0.16)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                <span style={{ ...display(16, { lineHeight: 1.3 }) }}>{n.title}</span>
                <span style={{ fontSize: 11, color: ink, flex: 'none', whiteSpace: 'nowrap' }}>{n.ago}</span>
              </div>
              <span style={{ fontSize: 13, lineHeight: 1.5, color: ink }}>{n.body}</span>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ padding: '80px 40px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{T('Chưa có thông báo nào.', 'No notifications yet.')}</p>
        </div>
      )}
    </div>
  );
}

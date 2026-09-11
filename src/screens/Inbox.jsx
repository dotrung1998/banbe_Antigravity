import { useGoc } from '../state/GocContext.jsx';
import { bg } from '../data/events.js';
import { paper, ink, display } from '../theme.js';

export default function Inbox() {
  const { state, T, backFromInbox, openThread } = useGoc();
  const s = state;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Inbox">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(27) }}>{T('Tin nhắn', 'Messages')}</span>
        <span onClick={backFromInbox} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>{T('Xong', 'Done')}</span>
      </div>
      {s.inboxThreads.length > 0 ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {s.inboxThreads.map(c => (
            <div key={c.threadId} onClick={() => openThread(c.threadId, c.eventKey, 'inbox')} style={{ display: 'flex', gap: 16, alignItems: 'center', padding: '16px 0', borderBottom: '1px solid #191919', cursor: 'pointer' }}>
              <div style={bg(c.img, { flex: 'none', width: 56, height: 56, borderRadius: '50%' })} />
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <span style={{ ...display(18, { lineHeight: 1.15 }) }}>{c.name}</span>
                <span style={{ fontSize: 13, color: ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.snippet}</span>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ padding: '80px 40px', textAlign: 'center' }}>
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>{T('Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.', 'No conversations yet. Message an organizer from an event page.')}</p>
        </div>
      )}
    </div>
  );
}

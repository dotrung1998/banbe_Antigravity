import { useGoc } from '../state/GocContext.jsx';
import { EVENTS, bg } from '../data/events.js';
import { paper, ink, display } from '../theme.js';

export default function Inbox() {
  const { state, set, T, goHome } = useGoc();
  const s = state;

  const inbox = Object.keys(s.chats).map(k => {
    const e = EVENTS.find(x => x.key === k);
    if (!e) return null;
    const thread = s.chats[k];
    const last = thread[thread.length - 1];
    return {
      key: k,
      name: e.orgName,
      img: e.img,
      snippet: (last.who === 'me' ? (T('Bạn: ', 'You: ')) : '') + last.text,
    };
  }).filter(Boolean);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Inbox">
      <div style={{ padding: '70px 24px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <span style={{ ...display(27) }}>Tin nhắn</span>
        <span onClick={goHome} style={{ fontSize: 12, color: ink, cursor: 'pointer' }}>Xong</span>
      </div>
      {inbox.length > 0 ? (
        <div style={{ padding: '14px 24px 40px' }}>
          {inbox.map(c => (
            <div key={c.key} onClick={() => set({ screen: 'chat', eventKey: c.key, chatBack: 'inbox' })} style={{ display: 'flex', gap: 16, alignItems: 'center', padding: '16px 0', borderBottom: '1px solid #191919', cursor: 'pointer' }}>
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
          <p style={{ fontSize: 14, lineHeight: 1.55, color: ink }}>Chưa có cuộc trò chuyện nào. Nhắn cho người tổ chức từ trang sự kiện.</p>
        </div>
      )}
    </div>
  );
}

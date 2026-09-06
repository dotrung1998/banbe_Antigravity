import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, inkButton } from '../theme.js';

export default function Chat() {
  const { state, T, curEvent: ev, chatBackFn, chatOnType, chatOnKey, chatSend } = useGoc();
  const s = state;

  const thread = s.chats[ev.key] || [{ who: 'host', text: ev.greeting }];
  const chatBackLabel = s.chatBack === 'inbox' ? T('Tin nhắn', 'Messages') : ev.orgName;
  const signedInAs = s.user ? ({ zalo: T('qua Zalo', 'via Zalo'), phone: T('qua số điện thoại', 'via phone'), facebook: T('qua Facebook', 'via Facebook'), instagram: T('qua Instagram', 'via Instagram') }[s.user.via] || s.user.email || '') : '';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Chat">
      <div style={{ padding: '66px 22px 14px', borderBottom: `1px solid ${rule}`, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
          <span onClick={chatBackFn} style={{ fontSize: 11, color: ink, cursor: 'pointer' }}>‹ {chatBackLabel}</span>
          <span style={{ ...display(18) }}>{ev.hostShort}</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 1 }}>
          <span style={{ fontSize: 10.5, color: ink }}>{T('Trả lời trong ngày', 'Replies within a day')}</span>
          <span style={{ fontSize: 10, color: ink }}>{signedInAs}</span>
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '18px 22px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {thread.map((m, i) => (
          <div key={i} style={{ display: 'flex', justifyContent: m.who === 'me' ? 'flex-end' : 'flex-start' }}>
            <div style={{
              maxWidth: '78%', padding: '11px 14px', fontSize: 13.5, lineHeight: 1.5,
              borderRadius: m.who === 'me' ? '16px 16px 5px 16px' : '16px 16px 16px 5px',
              background: m.who === 'me' ? ink : paper,
              color: m.who === 'me' ? paper : ink,
              border: m.who === 'me' ? 'none' : `1px solid ${rule}`,
            }}>{m.text}</div>
          </div>
        ))}
      </div>
      <div style={{ padding: '12px 18px 30px', borderTop: `1px solid ${rule}`, display: 'flex', gap: 8 }}>
        <input
          value={s.chatDraft} onChange={chatOnType} onKeyDown={chatOnKey}
          placeholder={'Viết cho ' + ev.hostShort + '…'}
          style={{ ...fieldGlass({ flex: 1, padding: '12px 14px', borderRadius: 999, border: 'none' }), fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
        />
        <div onClick={chatSend} style={{ ...inkButton({ borderRadius: 999, padding: '12px 20px', display: 'flex', alignItems: 'center', flex: 'none' }) }}>Gửi</div>
      </div>
    </div>
  );
}

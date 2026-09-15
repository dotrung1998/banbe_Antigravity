import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, inkButton } from '../theme.js';

export default function Chat() {
  const { state, T, curEvent: ev, chatBackFn, chatOnType, chatOnKey, chatSend, deleteMessage } = useGoc();
  const s = state;

  const thread = s.chatMessages.length
    ? s.chatMessages.map(m => ({ id: m.id, who: m.sender_id === s.user?.id ? 'me' : 'host', text: m.body }))
    : [{ who: 'host', text: ev.greeting }];
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
          <div key={m.id ?? i} style={{ display: 'flex', alignItems: 'center', gap: 6, justifyContent: m.who === 'me' ? 'flex-end' : 'flex-start' }}>
            {/* A real, permanent delete (messages_delete_own RLS, migration
                054) — own messages only; m.id is absent for the static
                greeting placeholder and for a system note (sender_id NULL,
                so it's never "me"), so neither ever gets this affordance. */}
            {m.who === 'me' && m.id && (
              <span
                onClick={() => deleteMessage(m.id)}
                data-testid="chat-message-delete"
                style={{ fontSize: 13, color: ink, opacity: 0.35, cursor: 'pointer', flex: 'none' }}
              >
                ×
              </span>
            )}
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
          placeholder={s.chatThreadId ? ('Viết cho ' + ev.hostShort + '…') : T('Đang mở cuộc trò chuyện…', 'Opening conversation…')}
          disabled={!s.chatThreadId}
          style={{ ...fieldGlass({ flex: 1, padding: '12px 14px', borderRadius: 999, border: 'none' }), fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none', opacity: s.chatThreadId ? 1 : 0.6 }}
        />
        <div onClick={s.chatThreadId ? chatSend : undefined} style={{ ...inkButton({ borderRadius: 999, padding: '12px 20px', display: 'flex', alignItems: 'center', flex: 'none' }), opacity: s.chatThreadId ? 1 : 0.5, cursor: s.chatThreadId ? 'pointer' : 'default' }}>Gửi</div>
      </div>
    </div>
  );
}

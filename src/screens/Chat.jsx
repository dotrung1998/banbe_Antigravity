import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, alert, display, fieldGlass, inkButton, cardGlass } from '../theme.js';

// Task 3d — payment-status system messages as a distinct inline card
// (reference: "Confirmed ... Show details"), not a plain text bubble.
// `messages.kind` only has 'text'/'system' (schema-confirmed, see
// 07-notifications.md) — no dedicated kind per lifecycle event — so this
// classifies by the exact body prefix each RPC already writes today:
// confirm_payment() (060:83), reject_pending_guest() (059:151),
// cancel_booking() (022:167). Content-based, in the UI layer only, per this
// ticket's own instruction — not a schema change.
function classifySystemMessage(body) {
  if (!body) return null;
  if (body.startsWith('Host marked payment received via')) {
    return { status: 'confirmed', label: { vi: 'Đã xác nhận thanh toán', en: 'Payment confirmed' } };
  }
  if (body.startsWith('Người tổ chức không nhận yêu cầu đặt chỗ này') || body.startsWith('Booking cancelled.')) {
    return { status: 'declined', label: { vi: 'Đặt chỗ đã bị huỷ', en: 'Booking cancelled' } };
  }
  return null;
}

function formatTime(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
}

export default function Chat() {
  const { state, T, curEvent: ev, chatBackFn, chatOnType, chatOnKey, chatSend, deleteMessage, goEvent } = useGoc();
  const s = state;

  const thread = s.chatMessages.length
    ? s.chatMessages.map(m => ({ id: m.id, who: m.sender_id === s.user?.id ? 'me' : 'host', text: m.body, kind: m.kind, createdAt: m.created_at }))
    : [{ who: 'host', text: ev.greeting }];
  const chatBackLabel = s.chatBack === 'inbox' ? T('Tin nhắn', 'Messages')
    : s.chatBack === 'notifications' ? T('Thông báo', 'Notifications')
    : ev.orgName;
  // Task 3b — the OTHER participant's own name (host name for a guest,
  // guest name for an organizer), set once at openThread()/openChatFor()
  // time since it depends on which side of the thread I'm on, not just the
  // event. Falls back to ev.hostShort for the one caller that doesn't know
  // it yet (a 'new_message' notification tap — see GocContext.jsx).
  const headerTitle = s.chatOtherName || ev.hostShort;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="Chat">
      <div style={{ padding: '66px 22px 14px', borderBottom: `1px solid ${rule}`, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 1, minWidth: 0 }}>
          <span onClick={chatBackFn} data-testid="chat-back" style={{ fontSize: 11, color: ink, cursor: 'pointer' }}>‹ {chatBackLabel}</span>
          <span style={{ ...display(18) }}>{headerTitle}</span>
          {/* Task 3b — event date + name subtitle directly under the title. */}
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>{ev.dayLong} · {ev.name}</span>
        </div>
        <div
          onClick={() => goEvent(s.eventKey)}
          data-testid="chat-details"
          style={{ ...fieldGlass({ padding: '6px 12px', borderRadius: 999, flex: 'none' }), fontSize: 11.5, fontWeight: 600, color: ink, cursor: 'pointer' }}
        >
          {T('Chi tiết', 'Details')}
        </div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '18px 22px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {thread.map((m, i) => {
          const rows = [];
          // Task 2 — unread divider: rendered once, right above the first
          // message that was unread at the moment this thread was opened
          // (s.chatUnreadDividerId, captured once by loadChatMessages'
          // computeDivider pass — see GocContext.jsx). Naturally disappears
          // on the next open since those rows are marked read immediately.
          if (m.id && m.id === s.chatUnreadDividerId) {
            rows.push(
              <div key="unread-divider" data-testid="chat-unread-divider" style={{ display: 'flex', alignItems: 'center', gap: 10, margin: '4px 0', opacity: 0.55 }}>
                <div style={{ flex: 1, height: 1, background: rule }} />
                <span style={{ fontSize: 10.5, color: alert, fontWeight: 600 }}>— {T('Chưa đọc', 'Unread')} —</span>
                <div style={{ flex: 1, height: 1, background: rule }} />
              </div>
            );
          }

          const sysCard = m.kind === 'system' ? classifySystemMessage(m.text) : null;
          if (sysCard) {
            // Task 3d — inline status card instead of a plain bubble.
            rows.push(
              <div key={m.id ?? i} data-testid="chat-system-card" style={{ ...cardGlass({ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }), border: `1px solid ${rule}` }}>
                <span style={{ fontSize: 11, fontWeight: 700, color: sysCard.status === 'confirmed' ? ink : alert }}>
                  {T(sysCard.label.vi, sysCard.label.en)}
                </span>
                <span style={{ fontSize: 12.5, color: ink, opacity: 0.75, lineHeight: 1.4 }}>{m.text}</span>
                <div
                  onClick={() => goEvent(s.eventKey)}
                  data-testid="chat-system-card-details"
                  style={{ alignSelf: 'flex-start', fontSize: 11.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
                >
                  {T('Xem chi tiết', 'Show details')}
                </div>
              </div>
            );
            return rows;
          }

          // Task 3c — per-message sender + timestamp, not a bare bubble.
          const senderLabel = m.who === 'me' ? T('Bạn', 'You') : headerTitle;
          rows.push(
            <div key={m.id ?? i} style={{ display: 'flex', flexDirection: 'column', gap: 3, alignItems: m.who === 'me' ? 'flex-end' : 'flex-start' }}>
              {m.createdAt && (
                <span style={{ fontSize: 10, color: ink, opacity: 0.5, padding: '0 4px' }}>{senderLabel} · {formatTime(m.createdAt)}</span>
              )}
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, justifyContent: m.who === 'me' ? 'flex-end' : 'flex-start' }}>
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
            </div>
          );
          return rows;
        })}
      </div>
      <div style={{ padding: '12px 18px 30px', borderTop: `1px solid ${rule}`, display: 'flex', gap: 8 }}>
        <input
          value={s.chatDraft} onChange={chatOnType} onKeyDown={chatOnKey}
          placeholder={s.chatThreadId ? ('Viết cho ' + headerTitle + '…') : T('Đang mở cuộc trò chuyện…', 'Opening conversation…')}
          disabled={!s.chatThreadId}
          style={{ ...fieldGlass({ flex: 1, padding: '12px 14px', borderRadius: 999, border: 'none' }), fontSize: 13.5, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none', opacity: s.chatThreadId ? 1 : 0.6 }}
        />
        <div onClick={s.chatThreadId ? chatSend : undefined} style={{ ...inkButton({ borderRadius: 999, padding: '12px 20px', display: 'flex', alignItems: 'center', flex: 'none' }), opacity: s.chatThreadId ? 1 : 0.5, cursor: s.chatThreadId ? 'pointer' : 'default' }}>Gửi</div>
      </div>
    </div>
  );
}

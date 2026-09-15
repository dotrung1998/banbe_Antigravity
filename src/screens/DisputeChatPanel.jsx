import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { ink, rule, fieldGlass, cardGlass, alert } from '../theme.js';

// The temporary chat for an escalated dispute — shared between the guest's
// side (PaymentDetails.jsx, while payment_state = 'disputed') and the
// organizer's side (Verifications.jsx, in the "escalated to banbe" list).
// Deliberately its own small table (dispute_messages), not the ordinary
// booking thread: this conversation is purged once resolve_dispute() closes
// it out (see purge_resolved_dispute_threads, 72h grace window), where the
// ordinary thread is permanent.
export default function DisputeChatPanel({ bookingId }) {
  const { state, T, loadDisputeChat, disputeChatDraftType, sendDisputeMessage, clearChatHighlight } = useGoc();
  const s = state;
  const listRef = useRef(null);
  const messageRefs = useRef({}); // message id -> DOM node, for scrollIntoView
  const [highlightedId, setHighlightedId] = useState(null);

  // No realtime subscription exists anywhere in this app (no
  // supabase.channel()/postgres_changes usage, and dispute_messages was
  // never added to the supabase_realtime publication) — without this poll,
  // the party who didn't just send a message never sees a new one until
  // they leave and reopen this panel. 4s, matching PaymentDetails.jsx's own
  // 6s poll for the same "nothing pushes to this client" reason.
  useEffect(() => {
    loadDisputeChat(bookingId);
    const id = setInterval(() => loadDisputeChat(bookingId), 4000);
    return () => clearInterval(id);
  }, [bookingId, loadDisputeChat]);

  const messages = s.disputeChatBookingId === bookingId ? s.disputeChatMessages : [];

  // Reached by tapping a 'dispute_message' toast/notification
  // (openNotification, GocContext.jsx) — scrolls to and briefly highlights
  // the specific message named by `chatHighlight.messageId`, or just the
  // bottom of the thread if that's null (an older notification row from
  // before migration 050 added message_id). Only runs once per highlight —
  // clearChatHighlight() consumes it so the 4s poll's re-renders don't
  // keep re-triggering the scroll/flash.
  useEffect(() => {
    if (s.chatHighlight?.bookingId !== bookingId) return;
    const { messageId } = s.chatHighlight;
    if (messageId) {
      const node = messageRefs.current[messageId];
      if (!node) return; // messages haven't loaded yet — wait for the next render
      node.scrollIntoView({ behavior: 'smooth', block: 'center' });
      setHighlightedId(messageId);
      setTimeout(() => setHighlightedId(id => (id === messageId ? null : id)), 1600);
    } else if (messages.length > 0 && listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    } else if (messages.length === 0) {
      return; // nothing to scroll to yet — wait for the next render
    }
    clearChatHighlight();
  }, [s.chatHighlight, bookingId, messages, clearChatHighlight]);

  return (
    <div style={{ ...fieldGlass({ marginTop: 10, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="dispute-chat-panel">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
        {T('Trao đổi trực tiếp về tranh chấp này', 'Direct chat about this dispute')}
      </span>
      <p style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.7, margin: 0 }}>
        {T('Cuộc trò chuyện này là tạm thời — sẽ bị xoá sau khi banbe đưa ra quyết định, và bản ghi được gửi qua email cho cả hai bên.',
           'This conversation is temporary — it is deleted once banbe rules on the dispute, and a copy is emailed to both of you.')}
      </p>

      <div ref={listRef} style={{ display: 'flex', flexDirection: 'column', gap: 6, maxHeight: 220, overflowY: 'auto' }}>
        {s.disputeChatLoading && messages.length === 0 && (
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }}>{T('Đang tải…', 'Loading…')}</span>
        )}
        {!s.disputeChatLoading && messages.length === 0 && !s.disputeChatError && (
          <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }} data-testid="dispute-chat-empty">
            {T('Chưa có tin nhắn nào.', 'No messages yet.')}
          </span>
        )}
        {messages.map(m => (
          <div
            key={m.id}
            ref={(node) => { if (node) messageRefs.current[m.id] = node; else delete messageRefs.current[m.id]; }}
            style={{
              ...cardGlass({ padding: '8px 10px' }),
              transition: 'background-color 0.3s ease, box-shadow 0.3s ease',
              boxShadow: highlightedId === m.id ? `0 0 0 1.5px ${alert}` : undefined,
            }}
            data-testid="dispute-chat-message"
            data-highlighted={highlightedId === m.id || undefined}
          >
            <div style={{ fontSize: 10, color: ink, opacity: 0.55 }}>
              {m.sender_role === 'organizer' ? T('Người tổ chức', 'Organizer')
                : m.sender_role === 'guest' ? T('Khách', 'Guest')
                : m.sender_role === 'admin' ? T('banbe', 'banbe') : T('Hệ thống', 'System')}
              {' ▪︎ '}{new Date(m.created_at).toLocaleString()}
            </div>
            <div style={{ fontSize: 13, color: ink, marginTop: 2 }}>{m.body}</div>
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', gap: 8 }}>
        <input
          value={s.disputeChatDraft} onChange={disputeChatDraftType}
          placeholder={T('Nhắn gì đó…', 'Say something…')}
          data-testid="dispute-chat-input"
          onKeyDown={(e) => { if (e.key === 'Enter' && s.disputeChatDraft.trim()) sendDisputeMessage(bookingId); }}
          style={{ ...fieldGlass({ padding: '10px 12px', border: 'none', flex: 1 }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
        />
        <div
          onClick={() => s.disputeChatDraft.trim() && sendDisputeMessage(bookingId)}
          data-testid="dispute-chat-send"
          style={{
            flex: 'none', display: 'flex', alignItems: 'center', padding: '0 16px', borderRadius: 12,
            fontSize: 13, fontWeight: 600, cursor: s.disputeChatDraft.trim() ? 'pointer' : 'default',
            background: s.disputeChatDraft.trim() ? ink : 'rgba(27,25,22,0.16)', color: '#F7F4EC',
            border: `1px solid ${rule}`,
          }}
        >
          {T('Gửi', 'Send')}
        </div>
      </div>
      {s.disputeChatError && (
        <p style={{ fontSize: 11.5, color: alert, margin: 0 }} data-testid="dispute-chat-error">
          {s.disputeChatError}
        </p>
      )}
    </div>
  );
}

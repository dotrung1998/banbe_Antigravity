import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { ink, rule, fieldGlass, cardGlass, alert } from '../theme.js';

// A static (non-ticking, computed at render time), read-only countdown —
// never a delete button, unlike the ordinary chat (Chat.jsx) or the
// notification inbox (Notifications.jsx): dispute_messages must survive
// until purge_resolved_dispute_threads() actually removes it, per
// 05-notify-retention.md's 72h retention requirement. Returns null for an
// open thread (resolvedAt/purgeAfter both null) or one whose purge_after
// has already passed (about to be swept, or the cron just hasn't run yet
// — either way, nothing useful to say).
function retentionLabel(thread, T) {
  if (!thread?.resolvedAt || !thread.purgeAfter) return null;
  const msLeft = new Date(thread.purgeAfter).getTime() - Date.now();
  if (msLeft <= 0) return null;
  const hoursLeft = msLeft / 3600000;
  if (hoursLeft >= 1) {
    const n = Math.round(hoursLeft);
    return T(`Sẽ tự xoá trong ~${n} giờ`, `Auto-deletes in ~${n}h`);
  }
  const n = Math.max(1, Math.round(msLeft / 60000));
  return T(`Sẽ tự xoá trong ~${n} phút`, `Auto-deletes in ~${n}m`);
}

// The temporary chat for a dispute — shared between the guest's side
// (PaymentDetails.jsx, while payment_state = 'disputed') and the
// organizer's side (Verifications.jsx, in the "escalated to banbe" list).
// Deliberately its own small table (dispute_messages), not the ordinary
// booking thread: this conversation is purged once resolve_dispute() closes
// it out (see purge_resolved_dispute_threads, 72h grace window), where the
// ordinary thread is permanent.
//
// Two kinds, one panel (migration 129): a PAYMENT dispute (the host
// escalated to banbe, keyed by booking) and a REFUND dispute (the goer
// reported not receiving the money, keyed by refund claim — settled between
// the two of them, no banbe ruling). Same table, same purge machinery, so
// only the selector, the RPCs and the explanatory copy differ. Exactly one of
// bookingId / refundClaimId is passed.
export default function DisputeChatPanel({ bookingId, refundClaimId }) {
  const { state, T, loadDisputeChat, loadRefundDisputeChat, disputeChatDraftType, sendDisputeMessage, sendRefundDisputeMessage, clearChatHighlight } = useGoc();
  const s = state;
  const listRef = useRef(null);
  const messageRefs = useRef({}); // message id -> DOM node, for scrollIntoView
  const [highlightedId, setHighlightedId] = useState(null);
  const isRefund = !!refundClaimId;

  // No realtime subscription exists anywhere in this app (no
  // supabase.channel()/postgres_changes usage, and dispute_messages was
  // never added to the supabase_realtime publication) — without this poll,
  // the party who didn't just send a message never sees a new one until
  // they leave and reopen this panel. 4s, matching PaymentDetails.jsx's own
  // 6s poll for the same "nothing pushes to this client" reason.
  const reload = isRefund ? loadRefundDisputeChat : loadDisputeChat;
  const chatKey = isRefund ? refundClaimId : bookingId;
  useEffect(() => {
    reload(chatKey);
    const id = setInterval(() => reload(chatKey), 4000);
    return () => clearInterval(id);
  }, [chatKey, reload]);

  // Same staleness guard the payment-only version had, expressed once: state
  // records WHICH dispute it currently holds, and the panel only renders that
  // one. A 4s poll for a different thread landing late therefore can't paint
  // the wrong conversation here.
  const isActiveChat = isRefund ? s.disputeChatRefundClaimId === refundClaimId : s.disputeChatBookingId === bookingId;
  const messages = isActiveChat ? s.disputeChatMessages : [];
  const thread = isActiveChat ? s.disputeChatThread : null;
  const retention = retentionLabel(thread, T);
  // Once a dispute is concluded the chat is a read-only record until the
  // purge sweep removes it (send_refund_dispute_message/send_dispute_message
  // both refuse once resolved) — so the composer is hidden rather than left
  // there to fail on submit.
  const readOnly = !!thread?.resolvedAt;
  const send = isRefund ? sendRefundDisputeMessage : sendDisputeMessage;

  // Reached by tapping a 'dispute_message' toast/notification
  // (openNotification, GocContext.jsx) — scrolls to and briefly highlights
  // the specific message named by `chatHighlight.messageId`, or just the
  // bottom of the thread if that's null (an older notification row from
  // before migration 050 added message_id). Only runs once per highlight —
  // clearChatHighlight() consumes it so the 4s poll's re-renders don't
  // keep re-triggering the scroll/flash.
  useEffect(() => {
    const highlight = s.chatHighlight;
    if (!highlight) return;
    if (isRefund ? highlight.refundClaimId !== refundClaimId : highlight.bookingId !== bookingId) return;
    const { messageId } = highlight;
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
  }, [s.chatHighlight, bookingId, refundClaimId, isRefund, messages, clearChatHighlight]);

  return (
    <div style={{ ...fieldGlass({ marginTop: 10, padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="dispute-chat-panel">
      <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
        {T('Trao đổi trực tiếp về tranh chấp này', 'Direct chat about this dispute')}
      </span>
      <p style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.7, margin: 0 }}>
        {/* The two kinds have genuinely different endings — a payment
            dispute is closed by banbe and emailed a transcript, a refund
            dispute is just settled between the two parties — so the promise
            made to the reader has to differ too. */}
        {isRefund
          ? T('Cuộc trò chuyện này là tạm thời: khi tranh chấp kết thúc, nó sẽ tự xoá sau 7 ngày.',
               'This conversation is temporary: once the dispute is settled it deletes itself after 7 days.')
          : T('Cuộc trò chuyện này là tạm thời: sẽ bị xoá sau khi banbe đưa ra quyết định, và bản ghi được gửi qua email cho cả hai bên.',
               'This conversation is temporary: it is deleted once banbe rules on the dispute, and a copy is emailed to both of you.')}
      </p>
      {readOnly && (
        <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.55 }} data-testid="dispute-chat-closed">
          {T('Tranh chấp đã kết thúc — chỉ còn để đọc.', 'This dispute has ended — read only.')}
        </span>
      )}
      {retention && (
        <span style={{ fontSize: 10.5, fontWeight: 600, color: ink, opacity: 0.55 }} data-testid="dispute-chat-retention">
          {retention}
        </span>
      )}

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

      {!readOnly && (
        <div style={{ display: 'flex', gap: 8 }}>
          <input
            value={s.disputeChatDraft} onChange={disputeChatDraftType}
            placeholder={T('Nhắn gì đó…', 'Say something…')}
            data-testid="dispute-chat-input"
            onKeyDown={(e) => { if (e.key === 'Enter' && s.disputeChatDraft.trim()) send(chatKey); }}
            style={{ ...fieldGlass({ padding: '10px 12px', border: 'none', flex: 1 }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
          />
          <div
            onClick={() => s.disputeChatDraft.trim() && send(chatKey)}
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
      )}
      {s.disputeChatError && (
        <p style={{ fontSize: 11.5, color: alert, margin: 0 }} data-testid="dispute-chat-error">
          {s.disputeChatError}
        </p>
      )}
    </div>
  );
}

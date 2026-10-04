import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { ink, honey, honeyBg } from '../theme.js';

// Same 6s cadence as the Inbox's own dispute poll — nothing here subscribes to
// Supabase Realtime, and this entry only exists for a handful of seconds on a
// screen that's already polling its own data.
const POLL_MS = 6000;

/**
 * The yellow "Awaiting Verification" entry for ONE disputed refund — the
 * counterpart of the pinned yellow section in Messages, placed where the
 * person who has to act about it already is (the goer's payment screen, the
 * host's verification queue).
 *
 * It deliberately does NOT embed the chat itself. The chat's home is the
 * Messages section, where both parties can expand it inline alongside their
 * conversations; this is the shortcut to it — one tap from the payment screen
 * straight into that specific conversation, expanded and ready to type into.
 * Embedding a second copy here would mean two live 4s polls of the same
 * transcript, two places to keep the retention state in sync, and a screen
 * that grows a full chat transcript inside a card about something else.
 */
export default function RefundDisputeEntry({ refundClaimId, amountVnd, eventName }) {
  const { state, T, openDisputeChatInInbox, loadDisputeChats } = useGoc();
  const s = state;
  const chat = s.disputeChats.find(c => c.refund_claim_id === refundClaimId) || null;
  const [tried, setTried] = useState(false);

  // The chat row is normally already in state (Messages keeps it fresh, and
  // raising the dispute refreshes it). If this screen is reached first —
  // deep link, notification, cold open — fetch once, then keep retrying on the
  // usual poll only while it's still missing, so a genuinely thread-less
  // claim can't spin a request forever.
  useEffect(() => {
    if (chat || tried) return;
    setTried(true);
    loadDisputeChats();
  }, [chat, tried, loadDisputeChats]);

  useEffect(() => {
    if (chat) return undefined;
    const id = setInterval(loadDisputeChats, POLL_MS);
    return () => clearInterval(id);
  }, [chat, loadDisputeChats]);

  const concluded = !!chat?.resolved_at;
  const iAmHost = chat?.viewer_role === 'organizer';

  return (
    <div
      style={{ borderRadius: 14, overflow: 'hidden', background: honeyBg, border: `1px solid ${honey}`, marginTop: 12 }}
      data-testid="refund-dispute-entry"
      data-kind="refund"
    >
      <div style={{ padding: '13px 15px' }}>
        <span style={{ fontSize: 13.5, fontWeight: 700, color: honey }} data-testid="refund-dispute-entry-title">
          {concluded
            ? T('Đã xác minh ▪︎ tranh chấp đã kết thúc', 'Verified ▪︎ this dispute has ended')
            : T('Chờ xác minh', 'Awaiting Verification')}
        </span>
        <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.75, margin: '6px 0 0' }}>
          {concluded
            ? T('Khoản hoàn đã được xử lý xong. Đoạn chat vẫn còn để đọc trong 7 ngày rồi tự xoá.',
                 "The refund is settled. The chat stays readable for 7 days, then deletes itself.")
            : T('Chưa thống nhất được về khoản hoàn này. Mở cuộc trò chuyện tạm thời để trao đổi trực tiếp với phía bên kia.',
                 "You and the other side aren't agreed on this refund yet. Open the temporary chat to sort it out directly.")}
        </p>
        {(eventName || amountVnd != null) && (
          <p style={{ fontSize: 11.5, color: ink, opacity: 0.6, margin: '4px 0 0' }}>
            {[eventName, amountVnd != null ? formatVnd(amountVnd) : null].filter(Boolean).join(' ▪︎ ')}
          </p>
        )}
        {chat?.last_message_body && (
          <p style={{ fontSize: 11.5, color: ink, opacity: 0.7, margin: '6px 0 0' }}>
            {T('Tin nhắn mới nhất: ', 'Latest message: ')}{chat.last_message_body}
          </p>
        )}
      </div>

      {/* The jump. Hidden rather than shown-disabled when the chat row hasn't
          resolved yet, so the entry never presents a dead control the way a
          disabled "Open chat" would. */}
      {chat && !concluded && (
        <div
          onClick={() => openDisputeChatInInbox(chat.thread_id)}
          style={{
            padding: '12px 15px', borderTop: `1px solid ${honey}`, fontSize: 12.5, fontWeight: 600,
            color: honey, cursor: 'pointer',
          }}
          data-testid="refund-dispute-open-chat"
        >
          {iAmHost
            ? T('Mở chat với khách ›', 'Open chat with the guest ›')
            : T('Mở chat với người tổ chức ›', 'Open chat with the organizer ›')}
        </div>
      )}
    </div>
  );
}
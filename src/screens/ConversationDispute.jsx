import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase.js';
import { useGoc } from '../state/GocContext.jsx';
import { rule, alert, cardGlass } from '../theme.js';
import DisputeChatPanel from './DisputeChatPanel.jsx';

const POLL_MS = 6000;
const LIVE_PAYMENT_STATES = ['pending_verification', 'holding', 'disputed'];

// Same rule as iOS DisputeChatSummary.isActiveDispute: a refund dispute is live
// until closed/settled, a payment one only while the booking is still unsettled.
export function isActiveDisputeChat(c) {
  if (!c) return false;
  return c.kind === 'refund'
    ? !c.dispute_closed_at && c.claim_status === 'disputed'
    : !c.resolved_at && LIVE_PAYMENT_STATES.includes(c.booking_payment_state || '');
}

/**
 * What dispute (if any) belongs to ONE booking conversation, resolved by the
 * exact conversation thread id (never an event-name match):
 *   refund  -> get_refund_dispute_for_conversation (open one, else a closed one
 *              still inside its 7-day window)
 *   payment -> the live 'payment' row of get_my_dispute_chats() for that thread
 *              (unresolved, booking pending_verification/holding/disputed)
 * Both load generation-guarded so a slow response for a previous conversation
 * can't paint the current one.
 */
export function useConversationDispute(threadId) {
  const [st, setSt] = useState({ threadId: null, refund: null, payment: null });
  useEffect(() => {
    if (!threadId) return undefined;
    let gen = 0;
    let cancelled = false;
    const load = async () => {
      const my = ++gen;
      const [r, list] = await Promise.all([
        supabase.rpc('get_refund_dispute_for_conversation', { p_thread: threadId }),
        supabase.rpc('get_my_dispute_chats'),
      ]);
      if (cancelled || my !== gen) return;
      const refund = r.data?.found ? r.data : null;
      const payment = (list.data || []).find(c => c.kind !== 'refund' && c.conversation_thread_id === threadId && isActiveDisputeChat(c)) || null;
      setSt({ threadId, refund, payment });
    };
    load();
    const id = setInterval(load, POLL_MS);
    return () => { cancelled = true; clearInterval(id); };
  }, [threadId]);
  return st.threadId === threadId ? st : { threadId, refund: null, payment: null };
}

/** The dispute hosted INSIDE a system card: payment chat under "Transfer not
 *  found", refund chat under "Booking cancelled". */
export function DisputeBlock({ kind, dispute }) {
  const { T } = useGoc();
  if (!dispute) return null;
  if (kind === 'payment') {
    return (
      <div style={{ borderTop: `1px solid ${rule}`, paddingTop: 4 }} data-testid="conversation-dispute" data-kind="payment">
        <span style={{ fontSize: 11.5, fontWeight: 700, color: alert }} data-testid="conversation-dispute-label">{T('Đang tranh chấp', 'Dispute in progress')}</span>
        <DisputeChatPanel bookingId={dispute.booking_id} />
      </div>
    );
  }
  return (
    <div style={{ borderTop: `1px solid ${rule}`, paddingTop: 4 }} data-testid="conversation-dispute" data-kind="refund">
      <DisputeChatPanel refundClaimId={dispute.refund_claim_id} />
    </div>
  );
}

export const disputeCardStyle = (active) => ({
  ...cardGlass({ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }),
  border: `1px solid ${active ? alert : rule}`,
});

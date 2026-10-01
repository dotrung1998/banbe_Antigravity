import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { formatCountdown, msUntil, useTicking } from '../lib/countdown.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, alert } from '../theme.js';
import DisputeChatPanel from './DisputeChatPanel.jsx';
import { supabase, supabaseUrl } from '../lib/supabase.js';

/** Point 2 of the refund-discoverability investigation — an explicit
 * opt-in diagnostic panel (NOT gated on import.meta.env.DEV, since the
 * person reproducing this is testing against the real deployed build on a
 * physical iPhone, where DEV is always false) that answers exactly the
 * questions that distinguish "hidden by a client gate," "still loading,"
 * "failed," and "genuinely empty" from each other, without ever logging a
 * JWT/refresh token/password/bank detail/email code or a full response
 * payload. Toggled by 5 taps on the "Hoàn tiền" section title — see
 * `titleTapRef` below — never visible by accident. */
function RefundDiagnosticsPanel({ s, T }) {
  const [authUserId, setAuthUserId] = useState('(checking…)');
  useEffect(() => {
    let active = true;
    // supabase.auth.getUser() re-verifies against the server (not just the
    // locally cached session) — this is what this ticket's own "use
    // supabase.auth.getUser() for web identity verification" line asks
    // for, specifically BECAUSE it's the one value a raw SQL Editor
    // `auth.uid()` can never actually confirm (that only proves what the
    // query editor's OWN session is, never this app's).
    supabase.auth.getUser().then(({ data, error }) => {
      if (!active) return;
      setAuthUserId(error ? `(error: ${error.message})` : (data?.user?.id || '(no session)'));
    });
    return () => { active = false; };
  }, []);

  const activeCount = s.refundQueue.filter(c => c.status === 'owed' || c.status === 'disputed').length;
  const pendingCount = s.refundQueue.filter(c => c.status === 'host_marked_sent').length;
  const hidingReason = s.verificationsFocusBookingId
    ? 'verifications-focus-booking-id-set (section hidden entirely — notification/Attendance "Check payment" deep link)'
    : 'not-hidden-by-focus';

  const row = (label, value) => (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10, fontSize: 11, fontFamily: 'monospace' }}>
      <span style={{ opacity: 0.6 }}>{label}</span>
      <span style={{ textAlign: 'right', wordBreak: 'break-all' }}>{String(value)}</span>
    </div>
  );

  return (
    <div data-testid="refund-diagnostics-panel" style={{ ...cardGlass({ padding: 12, display: 'flex', flexDirection: 'column', gap: 4 }), border: `1px dashed ${alert}` }}>
      <span style={{ fontSize: 10.5, fontWeight: 700, color: alert, marginBottom: 2 }}>DIAGNOSTICS (refund queue)</span>
      {row('supabase.auth.getUser() id', authUserId)}
      {row('app-state user id (s.user.id)', s.user?.id || '(null)')}
      {row('profile role (s.accountType)', s.accountType)}
      {row('organizerMode', s.organizerMode)}
      {row('supabase host', new URL(supabaseUrl).host)}
      {row('myOrganizerIdsStatus', s.myOrganizerIdsStatus)}
      {row('myOrganizerIds', JSON.stringify(s.myOrganizerIds))}
      {row('refundQueueLoading', s.refundQueueLoading)}
      {row('refundQueueGateReason', s.refundQueueGateReason || '(never set — loadRefundQueue never ran)')}
      {row('refundQueueError', s.refundQueueError || '(none)')}
      {row('refundQueue ids+status', JSON.stringify(s.refundQueue.map(c => ({ id: c.id, status: c.status, hasDestination: c.hasDestination }))))}
      {row('presentation result (active/pending)', `${activeCount} / ${pendingCount}`)}
      {row('verificationsFocusBookingId', s.verificationsFocusBookingId || '(null)')}
      {row('section-hiding condition', hidingReason)}
    </div>
  );
}

// The organizer's manual-verification queue — the fallback for every payment
// the bank webhook didn't reconcile on its own (a buyer who mistyped the
// reference, an account with no Casso/PayOS feed connected, a transfer from
// a bank that reports slowly).
//
// Ordered oldest-first, deliberately: this is a queue people are waiting in,
// and the person who has waited longest is the one closest to giving up.
export default function Verifications() {
  const {
    state, T, set, loadVerifications, approvePayment, rejectPayment, escalateDispute, loadDisputes, backFromVerifications,
    loadRefundQueue, markRefundSent,
  } = useGoc();
  const s = state;
  // Same documentBack-style pattern (07-notifications.md's 2026-09-18
  // follow-up) — the label follows verificationsBack too.
  const backLabel = s.verificationsBack === 'notifications' ? T('Thông báo', 'Notifications') : T('Tài khoản', 'Account');
  // { bookingId, kind: 'reject' | 'escalate' } while the reason form for
  // that row is open — one field, two possible destinations, so opening
  // one always closes the other.
  const [reasonFor, setReasonFor] = useState(null);
  const [reason, setReason] = useState('');
  const closeReasonForm = () => { setReasonFor(null); setReason(''); };
  const [openDisputeChat, setOpenDisputeChat] = useState(null);

  useEffect(() => { loadVerifications(); }, [loadVerifications]);
  // v_disputes is RLS-scoped the same way bookings always are — an
  // organizer querying it only ever sees their own events' disputes, admin
  // sees everyone's. Reused here (not just on the admin desk) so an
  // organizer can keep talking with the guest after escalating; once
  // escalated a booking leaves v_pending_verifications entirely, so without
  // this there would be nowhere on this screen to see it again at all.
  useEffect(() => { loadDisputes(); }, [loadDisputes]);
  const myOpenDisputes = s.disputes.filter(d => !d.dispute_resolved_at);

  // Flow 2 (host refund -> guest confirmation) — the smallest possible
  // queue inside this existing surface, per this ticket's own ask, not a
  // new navigation section. Same 6s cadence PaymentDetails.jsx's own poll
  // already uses elsewhere in this app, not a novel interval.
  const [refundNoteFor, setRefundNoteFor] = useState(null);
  const [refundNote, setRefundNote] = useState('');
  // Point 2 — diagnostics panel toggle (5 taps on the "Hoàn tiền" title,
  // within 1.2s of each other; resets on a pause so an ordinary stray tap
  // never accidentally opens it).
  const [diagOpen, setDiagOpen] = useState(false);
  const diagTapCountRef = useRef(0);
  const diagTapTimerRef = useRef(null);
  useEffect(() => { loadRefundQueue(); }, [loadRefundQueue]);
  useEffect(() => {
    const id = setInterval(() => loadRefundQueue(), 6000);
    return () => clearInterval(id);
  }, [loadRefundQueue]);
  // openNotification()'s refund_confirmed/_disputed/_overdue branches set
  // this so a tap lands scrolled to the specific claim, not just "somewhere
  // in the queue" — cleared once seen so it doesn't keep re-flashing on
  // every 6s poll re-render.
  const refundFocusRef = useRef(null);
  useEffect(() => {
    if (s.refundQueueFocusClaimId && refundFocusRef.current) {
      refundFocusRef.current.scrollIntoView({ block: 'center' });
      set({ refundQueueFocusClaimId: null });
    }
  }, [s.refundQueueFocusClaimId, s.refundQueue, set]);
  // Refund-discoverability fix — the dedicated "Refunds" entry
  // (openVerificationsRefunds) sets this so arriving here scrolls straight
  // to the "Hoàn tiền" section/title instead of landing at the top of the
  // payment-verification list this shared route is normally labeled for.
  // Fires once the section container is actually in the DOM (ref attaches
  // on every render once mounted, regardless of loading/error/empty/rows
  // state — see the section's own render below), then self-clears.
  const refundSectionRef = useRef(null);
  useEffect(() => {
    if (s.verificationsScrollToRefunds && refundSectionRef.current) {
      refundSectionRef.current.scrollIntoView({ block: 'start' });
      set({ verificationsScrollToRefunds: false });
    }
  }, [s.verificationsScrollToRefunds, s.refundQueue, s.refundQueueLoading, s.refundQueueError, set]);

  // Tapping a 'dispute_message' toast/notification (openNotification,
  // GocContext.jsx) lands an organizer here with s.chatHighlight set —
  // unlike PaymentDetails.jsx, this screen only mounts DisputeChatPanel
  // once its own local toggle is opened, so that has to happen here before
  // DisputeChatPanel can scroll to/highlight anything itself.
  useEffect(() => {
    if (s.chatHighlight?.bookingId) setOpenDisputeChat(s.chatHighlight.bookingId);
  }, [s.chatHighlight?.bookingId]);

  const overdue = s.verifications.filter(v => v.overdue).length;
  // Ticks only while the queue actually has SLA countdowns to show — an
  // empty queue has no business waking this screen every second.
  const tickNow = useTicking(s.verifications.length > 0);

  // 14-organizer-checkin.md: Attendance's "Check payment" button
  // (openVerificationDetail) sets this so the organizer lands on exactly
  // the one booking they tapped from — whether it's the only pending item
  // or buried far down a long queue — instead of the full list.
  const focusId = s.verificationsFocusBookingId;
  const visibleVerifications = focusId ? s.verifications.filter(v => v.booking_id === focusId) : s.verifications;
  const clearVerificationsFocus = () => set({ verificationsFocusBookingId: null });

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Verifications">
      <div onClick={backFromVerifications} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="verifications-back">
        ‹ {backLabel}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="verifications-title">
          {focusId ? T('Chi tiết thanh toán', 'Payment detail') : T('Chờ xác nhận', 'Awaiting verification')}
        </h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Khách đã báo chuyển khoản. Đối chiếu với sao kê rồi xác nhận: chỗ của họ đang được giữ và đồng hồ đã dừng.',
             "These guests reported a transfer. Check your statement, then confirm: their seat is held and their clock has stopped.")}
        </p>
        {!focusId && overdue > 0 && (
          <p style={{ fontSize: 12.5, fontWeight: 600, color: alert, margin: '10px 0 0' }} data-testid="verifications-overdue">
            {overdue} {T('khoản đã quá hạn xác nhận.', overdue === 1 ? 'is past its response window.' : 'are past their response window.')}
          </p>
        )}
        {focusId && (
          <div onClick={clearVerificationsFocus} data-testid="verifications-clear-focus"
               style={{ fontSize: 12, fontWeight: 600, color: ink, opacity: 0.7, cursor: 'pointer', marginTop: 10 }}>
            {T('‹ Xem tất cả', '‹ View all')}
          </div>
        )}
      </div>

      <div style={{ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {visibleVerifications.map(v => {
          const slaMsLeft = msUntil(v.verify_due_at, tickNow);
          const slaOverdue = !!v.verify_due_at && slaMsLeft === 0;
          return (
          <div key={v.booking_id} style={{ ...cardGlass({ padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="verification-row">
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <span style={{ ...display(16) }}>{v.guest_name || T('Khách', 'Guest')}</span>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{v.event_name} ▪︎ {v.qty} {T('vé', 'tix')}</span>
              </div>
              <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{formatVnd(v.total_vnd)}</span>
            </div>

            <div style={{ ...fieldGlass({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }}>
              <Line label={T('Nội dung CK', 'Reference')} value={v.payment_ref} mono />
              <Line label={T('Mã giao dịch', 'Transaction ID')} value={v.transaction_id || T('Không Có Thông Tin', 'Not Provided')} mono />
              <Line label={T('Đã chờ', 'Waiting')} value={waitLabel(v.proof_submitted_at, T)} />
              {v.verify_due_at && (
                <Line
                  label={slaOverdue ? T('Đã quá hạn', 'Past due') : T('Thời hạn phản hồi', 'Response window')}
                  value={slaOverdue ? T('Cần xử lý ngay', 'Needs action now') : formatCountdown(slaMsLeft)}
                  urgent={slaOverdue}
                  testid="verification-sla-countdown"
                />
              )}
            </div>

            {/* The actual receipt/transfer screenshot the guest submitted —
                this used to be invisible here entirely, leaving "Money
                received"/"Can't find it" a decision made on the reference
                and transaction ID text alone, never the evidence itself. */}
            {v.proof_path && (
              s.proofUrls[v.proof_path] ? (
                <img
                  src={s.proofUrls[v.proof_path]}
                  alt={T('Ảnh biên lai', 'Receipt image')}
                  data-testid="verification-proof-image"
                  style={{ width: '100%', maxHeight: 320, objectFit: 'contain', borderRadius: 10, background: 'rgba(27,25,22,0.04)' }}
                />
              ) : (
                <div style={{ ...fieldGlass({ padding: '20px 12px', textAlign: 'center' }) }} data-testid="verification-proof-loading">
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }}>{T('Đang tải ảnh biên lai…', 'Loading receipt image…')}</span>
                </div>
              )
            )}

            {v.escalated && (
              <span style={{ fontSize: 11, fontWeight: 600, color: alert }}>
                {T('Đã chuyển cảnh báo khẩn', 'Escalated as urgent')}
              </span>
            )}

            {/* v.dispute_reason means "Can't find it" already fired for this
                row — reject_payment (migration 034) now opens a
                dispute_threads row the moment that happens, not only once
                escalate_payment_dispute runs, so there's already a chat to
                reach here even though payment_state is still
                'pending_verification'. */}
            {v.dispute_reason && (
              openDisputeChat === v.booking_id ? (
                <DisputeChatPanel bookingId={v.booking_id} />
              ) : (
                <div onClick={() => setOpenDisputeChat(v.booking_id)}
                     data-testid="verification-open-not-found-chat"
                     style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
                  {T('Mở đoạn chat với khách ›', 'Open chat with guest ›')}
                </div>
              )
            )}

            {reasonFor?.bookingId === v.booking_id ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <input
                  value={reason} onChange={(e) => setReason(e.target.value)}
                  placeholder={reasonFor.kind === 'escalate'
                    ? T('Mô tả ngắn gọn vướng mắc cho banbe', 'Briefly describe the issue for banbe')
                    : T('Vì sao chưa xác nhận được?', "Why can't you confirm it?")}
                  data-testid="verification-reason"
                  style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
                />
                <p style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.7, margin: 0 }}>
                  {reasonFor.kind === 'escalate'
                    ? T('banbe sẽ xem xét và đưa ra quyết định. Chỗ của khách vẫn được giữ trong lúc chờ.',
                        "banbe will review and decide. The guest's seat stays held while you wait.")
                    : T('Lý do này được gửi thẳng cho khách qua tin nhắn để họ bổ sung, chỗ vẫn được giữ, banbe không tham gia ở bước này.',
                        "This reason goes straight to the guest by chat so they can follow up. The seat stays held, and banbe is not involved at this step.")}
                </p>
                <div style={{ display: 'flex', gap: 8 }}>
                  <Action label={T('Gửi', 'Submit')} testid="verification-reject-confirm"
                          onClick={() => {
                            if (reasonFor.kind === 'escalate') escalateDispute(v.booking_id, reason);
                            else rejectPayment(v.booking_id, reason);
                            closeReasonForm();
                          }} />
                  <Action label={T('Huỷ', 'Cancel')} ghost onClick={closeReasonForm} />
                </div>
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <div style={{ display: 'flex', gap: 8 }}>
                  <Action label={s.verificationBusy === v.booking_id ? T('Đang lưu…', 'Saving…') : T('Đã nhận tiền', 'Money received')}
                          testid="verification-approve" onClick={() => approvePayment(v.booking_id)} />
                  <Action label={T('Chưa thấy', "Can't find it")} ghost testid="verification-reject"
                          onClick={() => setReasonFor({ bookingId: v.booking_id, kind: 'reject' })} />
                </div>
                {/* Deliberately separate from "Can't find it" — that's just
                    feedback to the guest. This is the one action that
                    actually brings banbe in, for when the two of you
                    genuinely can't resolve it directly. */}
                <div
                  onClick={() => setReasonFor({ bookingId: v.booking_id, kind: 'escalate' })}
                  data-testid="verification-escalate"
                  style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.6, textAlign: 'center', cursor: 'pointer', padding: '2px 0' }}
                >
                  {T('Không tự giải quyết được ▪︎ chuyển cho banbe', "Can't resolve it directly ▪︎ escalate to banbe")}
                </div>
              </div>
            )}
          </div>
          );
        })}

        {visibleVerifications.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: 0 }} data-testid="verifications-empty">
            {s.verificationsLoading ? T('Đang tải…', 'Loading…')
              : focusId
              ? T('Khoản thanh toán này không còn trong danh sách chờ nữa.', 'This payment is no longer in the pending queue.')
              : T('Không có khoản nào đang chờ. Thanh toán khớp nội dung chuyển khoản sẽ được xác nhận tự động.',
                  'Nothing waiting. Payments that match their reference are confirmed automatically.')}
          </p>
        )}
      </div>

      {/* Escalated bookings leave the queue above entirely (they're no
          longer 'pending_verification') — this is the only place left on
          this screen to keep talking with the guest while banbe decides.
          Hidden while focused on one booking (14-organizer-checkin.md) —
          that view is meant to be exactly one booking's own detail. */}
      {!focusId && myOpenDisputes.length > 0 && (
        <div style={{ margin: '0 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7 }} data-testid="verifications-disputes-title">
            {T('Đang chờ banbe quyết định', "Awaiting banbe's decision")}
          </span>
          {myOpenDisputes.map(d => (
            <div key={d.booking_id} style={{ ...cardGlass({ padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 8 }) }} data-testid="verification-dispute-row">
              <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12 }}>
                <span style={{ fontSize: 14, color: ink }}>{d.guest_name || T('Khách', 'Guest')} ▪︎ {d.event_name}</span>
                <span style={{ ...display(16, { whiteSpace: 'nowrap' }) }}>{formatVnd(d.total_vnd)}</span>
              </div>
              {openDisputeChat === d.booking_id ? (
                <DisputeChatPanel bookingId={d.booking_id} />
              ) : (
                <div onClick={() => setOpenDisputeChat(d.booking_id)}
                     data-testid="verification-open-dispute-chat"
                     style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}>
                  {T('Mở đoạn chat tranh chấp ›', 'Open dispute chat ›')}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Flow 2 — refund queue (TASK A/B, 2026-09-30 pass): s.refundQueue now
          comes from the exact same get_host_refund_claims() RPC + the same
          refundClaimPresentation() mapper Attendance's Refund Center uses
          (src/lib/refundPresentation.js) — no more separate "what's
          actionable" logic that could drift out of sync and show a Mark-
          refund-sent CTA for a claim with no valid recipient snapshot
          (the actual TDK404 bug). `activeRows` mirrors Attendance's own
          visibleRows filter; host_marked_sent claims get their own
          non-actionable "Đang chờ xác nhận" section instead of being
          silently dropped. Hidden while focused on one verification
          booking, same reasoning as the dispute section above. */}
      {!focusId && (() => {
        const activeRows = s.refundQueue.filter(c => c.status === 'owed' || c.status === 'disputed');
        const pendingRows = s.refundQueue.filter(c => c.status === 'host_marked_sent');
        const hasRows = activeRows.length > 0 || pendingRows.length > 0;
        // Investigation fix — distinguish "still checking whether you
        // organize anything" / "that check failed" / "failed to load" /
        // "genuinely nothing to act on" / "here are the rows." Before this,
        // every one of the first four collapsed to the exact same "render
        // nothing," which is indistinguishable from the section simply not
        // existing — "do not show failed loading as empty."
        const awaitingOrganizerDiscovery = s.refundQueueGateReason === 'awaiting-organizer-discovery';
        const showLoading = (s.refundQueueLoading || awaitingOrganizerDiscovery) && !hasRows;
        const showError = !!s.refundQueueError && !hasRows;
        const showEmpty = !hasRows && !showLoading && !showError;
        return (
          <div ref={refundSectionRef} style={{ margin: '0 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <span
              onClick={() => {
                diagTapCountRef.current += 1;
                clearTimeout(diagTapTimerRef.current);
                diagTapTimerRef.current = setTimeout(() => { diagTapCountRef.current = 0; }, 1200);
                if (diagTapCountRef.current >= 5) { diagTapCountRef.current = 0; setDiagOpen(v => !v); }
              }}
              style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.7, cursor: 'default' }} data-testid="refund-queue-title"
            >
              {T('Hoàn tiền', 'Refunds')}
            </span>
            {diagOpen && <RefundDiagnosticsPanel s={s} T={T} />}
            {/* Point 1's own explicit requirement — the host does not
                create or hold any receiving payment method here; the GOER
                already chose/snapshotted their own destination, the host
                only reviews it and transfers externally, then marks sent. */}
            {(hasRows || showEmpty) && (
              <span style={{ fontSize: 11, color: ink, opacity: 0.6 }} data-testid="refund-queue-explainer">
                {T(
                  'Khách đã chọn tài khoản nhận hoàn tiền của họ. Bạn chuyển khoản trực tiếp cho khách rồi đánh dấu đã hoàn tiền — không cần tạo phương thức nhận tiền riêng.',
                  'The guest has already chosen their own refund destination. You transfer to them directly, then mark it sent — no receiving payment method of your own is needed here.'
                )}
              </span>
            )}
            {showLoading && (
              <span style={{ fontSize: 12.5, color: ink, opacity: 0.6 }} data-testid="refund-queue-loading">{T('Đang tải…', 'Loading…')}</span>
            )}
            {showError && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="refund-queue-error">
                <span style={{ fontSize: 12.5, color: alert }}>{s.refundQueueError}</span>
                <Action label={T('Thử lại', 'Retry')} onClick={loadRefundQueue} testid="refund-queue-retry" />
              </div>
            )}
            {showEmpty && (
              <span style={{ fontSize: 12.5, color: ink, opacity: 0.6 }} data-testid="refund-queue-empty">
                {T('Không có khoản hoàn tiền nào cần xử lý.', 'No refunds need action right now.')}
              </span>
            )}
            {activeRows.map(c => (
              <div
                key={c.id}
                ref={c.id === s.refundQueueFocusClaimId ? refundFocusRef : undefined}
                style={{ ...cardGlass({ padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 10 }) }}
                data-testid="refund-queue-row"
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                    <span style={{ ...display(16) }}>{c.guestName || T('Khách', 'Guest')}</span>
                    <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{c.eventName}</span>
                  </div>
                  <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{formatVnd(c.amount_vnd)}</span>
                </div>

                {c.status === 'disputed' ? (
                  // A disputed claim is not something the host can silently
                  // overwrite as "sent" — no action button here, just the
                  // visible state and whatever note trail exists.
                  <span style={{ fontSize: 12.5, fontWeight: 600, color: alert }} data-testid="refund-queue-disputed">
                    {T('Khách báo chưa nhận được tiền', 'Guest reports not receiving this refund')}
                  </span>
                ) : !c.hasDestination ? (
                  // TASK B — the actual fix for the reported bug: an owed
                  // claim with no valid recipient snapshot is NEVER
                  // actionable here, exactly like Attendance's own Refund
                  // Center — never a "Mark refund sent" CTA for it.
                  <span style={{ fontSize: 11, color: alert }} data-testid="refund-queue-needs-destination">
                    {T('Khách chưa chọn tài khoản nhận hoàn tiền.', "The guest hasn't chosen a refund destination yet.")}
                  </span>
                ) : refundNoteFor === c.id ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                    <input
                      value={refundNote} onChange={(e) => setRefundNote(e.target.value)}
                      placeholder={T('Ghi chú/mã tham chiếu (không bắt buộc)', 'Note/reference (optional)')}
                      data-testid="refund-queue-note"
                      style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
                    />
                    <div style={{ display: 'flex', gap: 8 }}>
                      <Action
                        label={s.refundActionBusy === c.id ? T('Đang lưu…', 'Saving…') : T('Xác nhận', 'Confirm')}
                        disabled={s.refundActionBusy === c.id}
                        testid="refund-queue-mark-sent-confirm"
                        onClick={async () => {
                          const note = refundNote;
                          setRefundNoteFor(null); setRefundNote('');
                          await markRefundSent(c.id, note);
                        }}
                      />
                      <Action label={T('Huỷ', 'Cancel')} ghost onClick={() => { setRefundNoteFor(null); setRefundNote(''); }} />
                    </div>
                  </div>
                ) : (
                  <Action
                    label={s.refundActionBusy === c.id ? T('Đang lưu…', 'Saving…') : T('Đã hoàn tiền', 'Mark refund sent')}
                    testid="refund-queue-mark-sent"
                    onClick={() => setRefundNoteFor(c.id)}
                  />
                )}
              </div>
            ))}
            {pendingRows.map(c => (
              <div
                key={c.id}
                ref={c.id === s.refundQueueFocusClaimId ? refundFocusRef : undefined}
                style={{ ...cardGlass({ padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 6 }) }}
                data-testid="refund-queue-row-pending"
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                    <span style={{ ...display(16) }}>{c.guestName || T('Khách', 'Guest')}</span>
                    <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{c.eventName}</span>
                  </div>
                  <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{formatVnd(c.amount_vnd)}</span>
                </div>
                <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>
                  {T('Đang chờ khách xác nhận đã nhận tiền.', 'Awaiting guest confirmation.')}
                </span>
              </div>
            ))}
          </div>
        );
      })()}
    </div>
  );
}

function waitLabel(since, T) {
  if (!since) return '—';
  const mins = Math.max(0, Math.round((Date.now() - new Date(since).getTime()) / 60000));
  if (mins < 60) return `${mins} ${T('phút', 'min')}`;
  return `${Math.floor(mins / 60)}${T(' giờ ', 'h ')}${mins % 60}${T(' phút', 'm')}`;
}

function Line({ label, value, mono, urgent, testid }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }} data-testid={testid}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, color: urgent ? alert : ink, letterSpacing: mono ? '0.06em' : 0, wordBreak: 'break-all', fontVariantNumeric: 'tabular-nums' }}>{value}</span>
    </div>
  );
}

function Action({ label, onClick, ghost, testid, disabled }) {
  return (
    <div onClick={disabled ? undefined : onClick} data-testid={testid}
         style={{
           flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px',
           borderRadius: 12, cursor: disabled ? 'default' : 'pointer',
           background: ghost ? 'transparent' : ink,
           color: ghost ? ink : paper,
           border: ghost ? `1px solid ${rule}` : 'none',
           opacity: disabled ? 0.5 : 1,
         }}>
      {label}
    </div>
  );
}

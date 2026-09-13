import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { formatCountdown, msUntil, useTicking } from '../lib/countdown.js';
import { paper, ink, rule, display, fieldGlass, cardGlass } from '../theme.js';

// The organizer's manual-verification queue — the fallback for every payment
// the bank webhook didn't reconcile on its own (a buyer who mistyped the
// reference, an account with no Casso/PayOS feed connected, a transfer from
// a bank that reports slowly).
//
// Ordered oldest-first, deliberately: this is a queue people are waiting in,
// and the person who has waited longest is the one closest to giving up.
export default function Verifications() {
  const {
    state, T, loadVerifications, approvePayment, rejectPayment, backFromDocuments,
  } = useGoc();
  const s = state;
  const [rejecting, setRejecting] = useState(null);
  const [reason, setReason] = useState('');

  useEffect(() => { loadVerifications(); }, [loadVerifications]);

  const overdue = s.verifications.filter(v => v.overdue).length;
  // Ticks only while the queue actually has SLA countdowns to show — an
  // empty queue has no business waking this screen every second.
  const tickNow = useTicking(s.verifications.length > 0);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Verifications">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="verifications-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="verifications-title">
          {T('Chờ xác nhận', 'Awaiting verification')}
        </h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Khách đã báo chuyển khoản. Đối chiếu với sao kê rồi xác nhận — chỗ của họ đang được giữ và đồng hồ đã dừng.',
             "These guests reported a transfer. Check your statement, then confirm — their seat is held and their clock has stopped.")}
        </p>
        {overdue > 0 && (
          <p style={{ fontSize: 12.5, fontWeight: 600, color: '#9A3E2D', margin: '10px 0 0' }} data-testid="verifications-overdue">
            {overdue} {T('khoản đã quá hạn xác nhận.', overdue === 1 ? 'is past its response window.' : 'are past their response window.')}
          </p>
        )}
      </div>

      <div style={{ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {s.verifications.map(v => {
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
              <Line label={T('Mã giao dịch', 'Transaction ID')} value={v.transaction_id || '—'} mono />
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

            {v.escalated && (
              <span style={{ fontSize: 11, fontWeight: 600, color: '#9A3E2D' }}>
                {T('Đã chuyển cảnh báo khẩn', 'Escalated as urgent')}
              </span>
            )}

            {rejecting === v.booking_id ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                <input
                  value={reason} onChange={(e) => setReason(e.target.value)}
                  placeholder={T('Vì sao chưa xác nhận được?', "Why can't you confirm it?")}
                  data-testid="verification-reason"
                  style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }}
                />
                <p style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.7, margin: 0 }}>
                  {T('Chỗ của khách vẫn được giữ và banbe sẽ xem xét — từ chối không huỷ vé ngay.',
                     "The guest's seat stays held and banbe will review it — rejecting does not cancel them outright.")}
                </p>
                <div style={{ display: 'flex', gap: 8 }}>
                  <Action label={T('Gửi', 'Submit')} testid="verification-reject-confirm"
                          onClick={() => { rejectPayment(v.booking_id, reason); setRejecting(null); setReason(''); }} />
                  <Action label={T('Huỷ', 'Cancel')} ghost onClick={() => { setRejecting(null); setReason(''); }} />
                </div>
              </div>
            ) : (
              <div style={{ display: 'flex', gap: 8 }}>
                <Action label={s.verificationBusy === v.booking_id ? T('Đang lưu…', 'Saving…') : T('Đã nhận tiền', 'Money received')}
                        testid="verification-approve" onClick={() => approvePayment(v.booking_id)} />
                <Action label={T('Chưa thấy', "Can't find it")} ghost testid="verification-reject"
                        onClick={() => setRejecting(v.booking_id)} />
              </div>
            )}
          </div>
          );
        })}

        {s.verifications.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: 0 }} data-testid="verifications-empty">
            {s.verificationsLoading ? T('Đang tải…', 'Loading…')
              : T('Không có khoản nào đang chờ. Thanh toán khớp nội dung chuyển khoản sẽ được xác nhận tự động.',
                  'Nothing waiting. Payments that match their reference are confirmed automatically.')}
          </p>
        )}
      </div>
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
      <span style={{ fontSize: 12, fontWeight: 600, color: urgent ? '#9A3E2D' : ink, letterSpacing: mono ? '0.06em' : 0, wordBreak: 'break-all', fontVariantNumeric: 'tabular-nums' }}>{value}</span>
    </div>
  );
}

function Action({ label, onClick, ghost, testid }) {
  return (
    <div onClick={onClick} data-testid={testid}
         style={{
           flex: 1, textAlign: 'center', fontSize: 13, fontWeight: 600, padding: '11px 12px',
           borderRadius: 12, cursor: 'pointer',
           background: ghost ? 'transparent' : ink,
           color: ghost ? ink : paper,
           border: ghost ? `1px solid ${rule}` : 'none',
         }}>
      {label}
    </div>
  );
}

import { useEffect, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, cardGlass } from '../theme.js';
import DisputeChatPanel from './DisputeChatPanel.jsx';

// Platform admin dispute desk: where a rejected payment goes to be decided by
// someone who is not one of the two parties.
//
// Shows the buyer's evidence and the full T1/T2/T3 trail side by side,
// because that trail is the only thing here that neither party could have
// edited after the fact.
export default function Disputes() {
  const {
    state, T, loadDisputes, resolveDispute, loadAuditTrail, backFromDocuments,
  } = useGoc();
  const s = state;
  const [note, setNote] = useState('');
  const [openChat, setOpenChat] = useState(null);

  useEffect(() => { loadDisputes(); }, [loadDisputes]);

  const open = s.disputes.filter(d => !d.dispute_resolved_at);
  const closed = s.disputes.filter(d => d.dispute_resolved_at);

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Disputes">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="disputes-back">
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="disputes-title">{T('Tranh chấp thanh toán', 'Payment disputes')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Khách khẳng định đã chuyển, người tổ chức không tìm thấy. Chỗ vẫn đang bị khoá cho tới khi có quyết định.',
             "The guest says they paid; the organizer can't find it. The seat stays locked until this is decided.")}
        </p>
      </div>

      <div style={{ margin: '18px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {open.map(d => (
          <div key={d.booking_id} style={{ ...cardGlass({ padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 10 }) }} data-testid="dispute-row">
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'flex-start' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <span style={{ ...display(16) }}>{d.guest_name || T('Khách', 'Guest')}</span>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{d.event_name} ▪︎ {d.organizer_name}</span>
              </div>
              <span style={{ ...display(19, { whiteSpace: 'nowrap' }) }}>{formatVnd(d.total_vnd)}</span>
            </div>

            <div style={{ ...fieldGlass({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 4 }) }}>
              <Line label={T('Nội dung CK', 'Reference')} value={d.payment_ref} />
              <Line label={T('Mã giao dịch khách khai', 'Buyer transaction ID')} value={d.transaction_id || '—'} />
              <Line label={T('Ảnh biên lai', 'Proof')} value={d.proof_path ? T('có', 'on file') : T('không có', 'none')} />
              <Line label={T('Lý do từ chối', 'Rejection reason')} value={d.dispute_reason || '—'} />
            </div>

            {/* The actual evidence, not just "on file" — an admin ruling on
                a dispute between two people who disagree needs to see the
                receipt itself, not take either side's word for its existence. */}
            {d.proof_path && (
              s.proofUrls[d.proof_path] ? (
                <img
                  src={s.proofUrls[d.proof_path]}
                  alt={T('Ảnh biên lai', 'Receipt image')}
                  data-testid="dispute-proof-image"
                  style={{ width: '100%', maxHeight: 320, objectFit: 'contain', borderRadius: 10, background: 'rgba(27,25,22,0.04)' }}
                />
              ) : (
                <div style={{ ...fieldGlass({ padding: '20px 12px', textAlign: 'center' }) }} data-testid="dispute-proof-loading">
                  <span style={{ fontSize: 11.5, color: ink, opacity: 0.6 }}>{T('Đang tải ảnh biên lai…', 'Loading receipt image…')}</span>
                </div>
              )
            )}

            <div onClick={() => loadAuditTrail(d.booking_id)}
                 style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}
                 data-testid="dispute-audit-open">
              {T('Xem nhật ký T1/T2/T3 ›', 'View T1/T2/T3 trail ›')}
            </div>

            {openChat === d.booking_id ? (
              <DisputeChatPanel bookingId={d.booking_id} />
            ) : (
              <div onClick={() => setOpenChat(d.booking_id)}
                   style={{ fontSize: 12, fontWeight: 600, color: ink, cursor: 'pointer' }}
                   data-testid="dispute-open-chat">
                {T('Xem đoạn chat giữa khách và người tổ chức ›', 'View the guest/organizer chat ›')}
              </div>
            )}

            {s.auditBookingId === d.booking_id && s.auditTrail.length > 0 && (
              <div style={{ ...fieldGlass({ padding: '10px 12px', display: 'flex', flexDirection: 'column', gap: 6 }) }} data-testid="dispute-audit-trail">
                {s.auditTrail.map(a => (
                  <div key={a.id} style={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                    <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{a.action}</span>
                    <span style={{ fontSize: 10.5, color: ink, opacity: 0.65 }}>
                      {new Date(a.at).toISOString().replace('T', ' ').replace('Z', '')}
                      {a.actor_kind ? ` ▪︎ ${a.actor_kind}` : ''}{a.ip ? ` ▪︎ ${a.ip}` : ''}
                    </span>
                  </div>
                ))}
              </div>
            )}

            <input value={note} onChange={(e) => setNote(e.target.value)}
                   placeholder={T('Ghi chú quyết định', 'Resolution note')}
                   data-testid="dispute-note"
                   style={{ ...fieldGlass({ padding: '11px 12px', border: 'none' }), fontSize: 13, color: ink, outline: 'none', fontFamily: 'inherit' }} />
            <div style={{ display: 'flex', gap: 8 }}>
              <Action label={s.disputeBusy === d.booking_id ? T('Đang lưu…', 'Saving…') : T('Khách đúng ▪︎ cấp vé', 'Buyer is right ▪︎ issue ticket')}
                      testid="dispute-uphold" onClick={() => { resolveDispute(d.booking_id, true, note); setNote(''); }} />
              <Action label={T('Mở lại chỗ', 'Release seat')} ghost testid="dispute-reject"
                      onClick={() => { resolveDispute(d.booking_id, false, note); setNote(''); }} />
            </div>
            {/* The confirmation email is best-effort, sent after the DB
                resolution already stands (see resolveDispute) — if it
                failed, the dispute thread is still soft-deleted (hidden,
                pending purge in 72h) so this is the one chance to notice
                and re-send before the transcript is gone for good. */}
            {s.disputeEmailError && (
              <p style={{ fontSize: 11.5, color: '#9A3E2D', margin: 0 }} data-testid="dispute-email-error">
                {T('Email xác nhận chưa gửi được: ', "Confirmation email didn't send: ") + s.disputeEmailError}
              </p>
            )}
          </div>
        ))}

        {open.length === 0 && (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: 0 }} data-testid="disputes-empty">
            {s.disputesLoading ? T('Đang tải…', 'Loading…') : T('Không có tranh chấp nào đang mở.', 'No open disputes.')}
          </p>
        )}

        {closed.length > 0 && (
          <>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, marginTop: 8 }}>{T('Đã xử lý', 'Resolved')}</span>
            {closed.map(d => (
              <div key={d.booking_id} style={{ ...fieldGlass({ padding: '12px 14px', display: 'flex', justifyContent: 'space-between', gap: 10 }) }}>
                <span style={{ fontSize: 12.5, color: ink, opacity: 0.75 }}>{d.payment_ref} ▪︎ {d.guest_name}</span>
                <span style={{ fontSize: 12, color: ink, opacity: 0.6 }}>{d.dispute_resolution || T('đã xử lý', 'resolved')}</span>
              </div>
            ))}
          </>
        )}
      </div>
    </div>
  );
}

function Line({ label, value }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 10 }}>
      <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 600, color: ink, wordBreak: 'break-all', textAlign: 'right' }}>{value}</span>
    </div>
  );
}

function Action({ label, onClick, ghost, testid }) {
  return (
    <div onClick={onClick} data-testid={testid}
         style={{
           flex: 1, textAlign: 'center', fontSize: 12.5, fontWeight: 600, padding: '11px 10px',
           borderRadius: 12, cursor: 'pointer', lineHeight: 1.3,
           background: ghost ? 'transparent' : ink, color: ghost ? ink : paper,
           border: ghost ? `1px solid ${rule}` : 'none',
         }}>
      {label}
    </div>
  );
}

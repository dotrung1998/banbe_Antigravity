import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, alert } from '../../theme.js';
import { downloadTicketPdfs } from '../../lib/ticketPdf.js';
import { newGiftKey, todayIso, validateRecipient, giftErrorMessage, giftTicketRpc, giftPdfData } from '../../lib/giftTicket.js';

// Bottom sheet to gift ONE seat: form -> review -> done (PDF downloads on success).
// Same slide-up frame as TicketImportSheet.

function SheetFrame({ onClose, title, testId, children }) {
  const [closing, setClosing] = useState(false);
  const close = () => { setClosing(true); setTimeout(onClose, 220); };
  const closeRef = useRef(close);
  closeRef.current = close;
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') closeRef.current(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  return (
    <div onClick={close} data-testid={testId} style={{ position: 'fixed', inset: 0, zIndex: 80, background: 'rgba(27,25,22,0.4)', display: 'flex', alignItems: 'flex-end', opacity: closing ? 0 : 1, transition: 'opacity .22s ease' }}>
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', maxHeight: '92%', overflowY: 'auto', background: paper, borderRadius: '24px 24px 0 0', padding: '12px 22px 30px', boxSizing: 'border-box',
          animation: closing ? 'none' : 'gocSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both',
          transform: closing ? 'translateY(100%)' : 'none', transition: closing ? 'transform .22s ease-in' : 'none',
        }}
      >
        <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, margin: '0 auto 14px' }} />
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
          <h2 style={{ ...display(22, { margin: 0 }) }}>{title}</h2>
          <span onClick={close} data-testid={`${testId}-close`} style={{ fontSize: 14, color: ink, cursor: 'pointer' }}>×</span>
        </div>
        {children}
      </div>
    </div>
  );
}

const inputStyle = { ...fieldGlass({ padding: '13px 14px', border: 'none' }), width: '100%', boxSizing: 'border-box', fontSize: 14, color: ink, outline: 'none' };
const labelStyle = { display: 'block', fontSize: 11.5, color: ink, margin: '14px 0 5px' };
const btn = (filled, busy) => ({ marginTop: 14, textAlign: 'center', fontSize: 15, fontWeight: 600, padding: 15, borderRadius: 999, background: filled ? ink : 'transparent', color: filled ? paper : ink, border: filled ? 'none' : `1px solid ${rule}`, cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.6 : 1 });

/**
 * @param {object} props
 * @param {string} props.bookingId @param {number} props.seats @param {string} props.eventName
 * @param {object} props.pdfBase  shared ticket-PDF fields (event, venue, language…)
 * @param {(res:object)=>void} props.onGifted  called with the RPC result after success
 * @param {()=>void} props.onClose
 */
export default function GiftTicketSheet({ bookingId, seats, eventName, pdfBase, onGifted, onClose }) {
  const { T } = useGoc();
  const [step, setStep] = useState('form');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [dob, setDob] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [pdfBusy, setPdfBusy] = useState(false);
  const [pdfFailed, setPdfFailed] = useState(false);
  const keyRef = useRef(newGiftKey()); // one key per sheet session: a double tap replays, never double-gifts
  const busyRef = useRef(false);

  const makePdf = (r) => giftPdfData(pdfBase, {
    recipientName: r.recipient_name, ticketCode: r.ticket_code, admissionToken: r.admission_token, claimCode: r.claim_code, reference: r.booking_id,
  });
  const download = async (r) => {
    setPdfBusy(true); setPdfFailed(false);
    try { await downloadTicketPdfs([makePdf(r)]); } catch (e) { console.warn('gift PDF failed:', e); setPdfFailed(true); }
    setPdfBusy(false);
  };

  const review = () => {
    const k = validateRecipient({ name, email, dob });
    if (k) return setErr(giftErrorMessage(k, T));
    setErr(''); setStep('review');
  };
  const confirm = async () => {
    if (busyRef.current) return;
    const k = validateRecipient({ name, email, dob });
    if (k) { setStep('form'); return setErr(giftErrorMessage(k, T)); }
    busyRef.current = true; setBusy(true); setErr('');
    const res = await giftTicketRpc({ bookingId, name, email, dob, key: keyRef.current });
    busyRef.current = false; setBusy(false);
    if (!res.ok) {
      setErr(res.error === 'NETWORK' ? T('Không thể tặng vé lúc này. Vui lòng thử lại sau.', "Couldn't gift the ticket right now. Please try again later.") : giftErrorMessage(res.error, T));
      return setStep('form');
    }
    setResult(res.data); setStep('done');
    onGifted?.(res.data);
    download(res.data);
  };

  return (
    <SheetFrame onClose={onClose} testId="gift-ticket-sheet" title={step === 'done' ? T('Đã tặng vé', 'Ticket gifted') : T('Tặng vé cho bạn bè', 'Gift a ticket to a friend')}>
      {step === 'form' && (
        <>
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: '14px 0 0' }}>
            {seats > 1
              ? T(`Bạn sẽ tặng 1 trong ${seats} vé của đơn này. Các vé còn lại vẫn thuộc về bạn.`, `You'll gift 1 of the ${seats} tickets in this booking. The rest stay with you.`)
              : T('Vé này sẽ chuyển hẳn cho người nhận.', 'This ticket will transfer to the recipient.')}
          </p>
          <label style={labelStyle}>{T('Họ tên người nhận', "Recipient's full name")}</label>
          <input value={name} onChange={(e) => { setName(e.target.value); setErr(''); }} autoComplete="off" style={inputStyle} data-testid="gift-name" />
          <label style={labelStyle}>{T('Email người nhận', "Recipient's email")}</label>
          <input value={email} onChange={(e) => { setEmail(e.target.value); setErr(''); }} type="email" inputMode="email" autoCapitalize="none" autoComplete="off" spellCheck={false} style={inputStyle} data-testid="gift-email" />
          <label style={labelStyle}>{T('Ngày sinh người nhận', "Recipient's date of birth")}</label>
          <input value={dob} onChange={(e) => { setDob(e.target.value); setErr(''); }} type="date" max={todayIso()} style={inputStyle} data-testid="gift-dob" />
          {err && <p style={{ fontSize: 12, color: alert, margin: '12px 0 0' }} data-testid="gift-error">{err}</p>}
          <div onClick={review} data-testid="gift-continue" style={btn(true, false)}>{T('Tiếp tục', 'Continue')}</div>
        </>
      )}
      {step === 'review' && (
        <>
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: '14px 0 0' }}>
            {T(`Xác nhận tặng 1 vé "${eventName}" cho:`, `Confirm gifting 1 ticket to "${eventName}" to:`)}
          </p>
          <div style={{ ...fieldGlass({ marginTop: 12, padding: '12px 14px' }), color: ink, fontSize: 14, lineHeight: 1.6 }}>
            <div style={{ fontWeight: 600 }}>{name.trim()}</div>
            <div>{email.trim()}</div>
            <div style={{ opacity: 0.7 }}>{dob}</div>
          </div>
          <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '12px 0 0' }}>
            {T('Vé này sẽ không còn là vé vào cửa của bạn. Bạn vẫn sở hữu giao dịch và quyền hoàn tiền nếu người tổ chức huỷ sự kiện.', 'This will no longer be your admission ticket. You still own the transaction and any refund right if the organizer cancels.')}
          </p>
          {err && <p style={{ fontSize: 12, color: alert, margin: '12px 0 0' }} data-testid="gift-error">{err}</p>}
          <div onClick={busy ? undefined : confirm} data-testid="gift-confirm" style={btn(true, busy)}>{busy ? T('Đang tặng…', 'Gifting…') : T('Tặng vé', 'Gift ticket')}</div>
          <div onClick={busy ? undefined : () => setStep('form')} data-testid="gift-back" style={btn(false, busy)}>{T('Sửa thông tin', 'Edit details')}</div>
        </>
      )}
      {step === 'done' && result && (
        <>
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: '14px 0 0' }}>
            {T(`Vé đã được chuyển cho ${result.recipient_name}.`, `The ticket now belongs to ${result.recipient_name}.`)}
          </p>
          <p style={{ fontSize: 12, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '10px 0 0' }}>
            {T('Gửi vé PDF cho người nhận. Họ dùng mã QR để vào cửa, và bấm "Mở trong banbe" trong PDF để nhập vé vào tài khoản nếu muốn.', 'Send the PDF to the recipient. They use the QR to get in, and can click "Open in banbe" in the PDF to import the ticket into an account.')}
          </p>
          {pdfFailed && <p style={{ fontSize: 12, color: alert, margin: '12px 0 0' }}>{T('Không tạo được tệp PDF. Hãy thử lại.', "The PDF couldn't be generated. Please try again.")}</p>}
          <div onClick={pdfBusy ? undefined : () => download(result)} data-testid="gift-download-pdf" style={btn(true, pdfBusy)}>
            {pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải vé PDF', 'Download PDF')}
          </div>
        </>
      )}
    </SheetFrame>
  );
}

import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useBanBe } from '../../state/BanBeContext.jsx';
import { paper, ink, rule, display, fieldGlass, alert } from '../../theme.js';
import { downloadTicketPdfs } from '../../lib/ticketPdf.js';

// Two bottom sheets that open and close like the profile share card:
//  - ImportSheet: enter a claim code (a gifted CLAIM-… code, or a group
//    ticket's ATT-… code — one entry point, the server tells them apart).
//  - ImportedTicketSheet: a ticket another account imported into this one —
//    the name, entry code and QR the door scans, and its PDF.

function SheetFrame({ onClose, title, testId, children }) {
  const [closing, setClosing] = useState(false);
  const close = () => { setClosing(true); setTimeout(onClose, 220); };
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') close(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  return (
    <div onClick={close} data-testid={testId} style={{ position: 'fixed', inset: 0, zIndex: 80, background: 'rgba(27,25,22,0.4)', display: 'flex', alignItems: 'flex-end', opacity: closing ? 0 : 1, transition: 'opacity .22s ease' }}>
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          width: '100%', maxHeight: '92%', overflowY: 'auto', background: paper, borderRadius: '24px 24px 0 0', padding: '12px 22px 30px', boxSizing: 'border-box',
          animation: closing ? 'none' : 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both',
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

export function ImportSheet() {
  const { state: s, T, closeTicketImport, setImportCode, claimTicket } = useBanBe();
  return (
    <SheetFrame onClose={closeTicketImport} testId="ticket-import-sheet" title={T('Nhập vé được tặng hoặc vé nhóm', 'Import a gift or group ticket')}>
      <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: '14px 0 0' }}>
        {T('Nhập mã nhận vé mà người tặng (hoặc người đặt vé nhóm) gửi cho bạn. Mã này khác với mã QR dùng điểm danh. Nếu bạn nhận được vé PDF, bấm nút "Mở trong banbe" trong PDF để mã tự điền.',
          'Enter the claim code the giver — or whoever booked the group — sent you. It is different from the check-in QR code. If you have the PDF, click its "Open in banbe" button and the code fills itself in.')}
      </p>
      <label style={{ display: 'block', fontSize: 11.5, color: ink, margin: '16px 0 5px' }}>{T('Mã nhận vé', 'Claim code')}</label>
      <input
        value={s.importCode} onChange={(e) => setImportCode(e.target.value)} placeholder="CLAIM-… / ATT-…"
        autoCapitalize="characters" autoComplete="off" spellCheck={false}
        style={{ ...fieldGlass({ padding: '13px 14px', border: 'none' }), width: '100%', boxSizing: 'border-box', fontSize: 14, color: ink, outline: 'none', letterSpacing: '0.04em' }}
        data-testid="ticket-import-code"
      />
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '12px 0 0' }}>
        {s.user?.email
          ? T(`Đang đăng nhập với ${s.user.email}. Vé được tặng chỉ nhập được bằng đúng email người nhận; vé nhóm (mã ATT-) chỉ cần mã và email đã xác minh.`,
              `Signed in as ${s.user.email}. A gifted ticket needs the recipient's email; a group ticket (ATT- code) needs only the code and a verified email.`)
          : T('Bạn sẽ được yêu cầu đăng nhập trước khi nhập.', "You'll be asked to sign in first.")}
      </p>
      {s.importError && <p style={{ fontSize: 12, color: alert, margin: '12px 0 0' }} data-testid="ticket-import-error">{s.importError}</p>}
      {s.importNotice && <p style={{ fontSize: 12.5, color: ink, margin: '12px 0 0' }} data-testid="ticket-import-notice">{s.importNotice}</p>}
      <div
        onClick={s.importBusy ? undefined : claimTicket} data-testid="ticket-import-submit"
        style={{ marginTop: 18, textAlign: 'center', fontSize: 15, fontWeight: 600, padding: 15, borderRadius: 999, background: ink, color: paper, cursor: s.importBusy ? 'default' : 'pointer', opacity: s.importBusy ? 0.6 : 1 }}
      >
        {s.importBusy ? T('Đang nhập…', 'Importing…') : T('Nhập vé', 'Import ticket')}
      </div>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '14px 0 0' }}>
        {T('Bạn không cần tài khoản để tham dự: mã QR trên vé PDF là đủ. Nhập vé chỉ để lưu vé vào tài khoản.', "You don't need an account to attend: the QR on the PDF is enough. Importing only saves the ticket to your account.")}
      </p>
    </SheetFrame>
  );
}

export function ImportedTicketSheet() {
  const { state: s, T, closeImportedTicket } = useBanBe();
  const t = s.importedTicketOpen;
  const [qr, setQr] = useState(null);
  const [busy, setBusy] = useState(false);
  const isVoid = t && (t.booking_status === 'cancelled' || t.booking_status === 'expired' || t.event_status === 'cancelled');
  useEffect(() => {
    let live = true;
    if (t && !isVoid) QRCode.toDataURL(t.admission_token, { margin: 1, width: 400 }).then(u => { if (live) setQr(u); }).catch(() => {});
    return () => { live = false; };
  }, [t, isVoid]);
  if (!t) return null;
  const when = t.starts_at ? new Date(t.starts_at).toLocaleString(s.lang === 'en' ? 'en-GB' : 'vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', dateStyle: 'full', timeStyle: 'short' }) : '';
  const download = async () => {
    if (busy) return;
    setBusy(true);
    try {
      await downloadTicketPdfs([{
        eventName: t.event_name, organizer: '', whenText: when, venue: '', holderName: t.name,
        ticketCode: t.ticket_code, qrValue: t.admission_token, reference: t.attendee_id, isEN: s.lang === 'en',
      }]);
    } catch (e) { console.warn('imported ticket PDF failed:', e); }
    setBusy(false);
  };
  return (
    <SheetFrame onClose={closeImportedTicket} testId="imported-ticket-sheet" title={t.event_name}>
      <div style={{ fontSize: 15, fontWeight: 600, color: ink, marginTop: 10 }}>{t.name}</div>
      {when && <div style={{ fontSize: 12.5, color: ink, opacity: 0.7, marginTop: 4 }}>{when}</div>}
      {isVoid ? (
        <p style={{ fontSize: 13, color: alert, margin: '18px 0 0' }}>{T('Vé này đã bị huỷ và không còn hiệu lực.', 'This ticket was cancelled and is no longer valid.')}</p>
      ) : (
        <>
          <div style={{ display: 'flex', justifyContent: 'center', marginTop: 18 }}>
            <div style={{ background: '#fff', padding: 10, borderRadius: 12 }}>
              {qr ? <img src={qr} alt="QR" style={{ width: 200, height: 200, display: 'block' }} /> : <div style={{ width: 200, height: 200 }} />}
            </div>
          </div>
          <div style={{ textAlign: 'center', fontSize: 13, fontWeight: 600, letterSpacing: '0.12em', color: ink, marginTop: 12 }}>{T('Mã vào cửa: ', 'Entry code: ')}{t.ticket_code}</div>
          {t.checked_in_at && <div style={{ textAlign: 'center', fontSize: 12, fontWeight: 700, color: alert, marginTop: 6 }}>{T('Đã vào cửa', 'Checked in')}</div>}
          <div onClick={download} data-testid="imported-ticket-download" style={{ ...fieldGlass({ marginTop: 18, padding: 14, textAlign: 'center', fontSize: 13.5, fontWeight: 600, color: ink, cursor: 'pointer', opacity: busy ? 0.6 : 1 }) }}>
            {busy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải vé PDF', 'Download PDF')}
          </div>
        </>
      )}
    </SheetFrame>
  );
}

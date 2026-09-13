import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, rule, display, cardGlass } from '../theme.js';

export default function Confirmed() {
  const { state, T, set, curEvent: ev, goHome, addToCalendar, giveTicket, openPaymentDetails } = useGoc();
  const s = state;

  // The QR/entry-code ticket is the thing an organizer's door scanner
  // trusts, so it has to gate on money actually having changed hands
  // (paid_marked_at, set only by confirm_payment) — never on booking.status.
  // Every seeded demo event is 'instant' approval, which marks a booking
  // 'confirmed' the moment it's created; gating on status alone is exactly
  // what let a guest reach the ticket screen before paying anything.
  const isPaid = !!s.booking?.paid_marked_at;
  const awaitingPayment = !!s.booking && !isPaid;
  const holdActive = !isPaid && s.booking?.status === 'pending' && s.holdDeadline && s.holdDeadline > s.now;
  const ms = Math.max(0, (s.holdDeadline || 0) - s.now);
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  const sec = Math.floor((ms % 60000) / 1000);
  const countdown = String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0') + ':' + String(sec).padStart(2, '0');

  // While a booking is sitting unpaid, poll for the organizer having
  // confirmed it — the guest may already be on this screen when that
  // happens, and shouldn't have to leave and come back via the
  // notification to see their ticket unlock.
  useEffect(() => {
    if (!s.booking?.id || s.booking.paid_marked_at) return undefined;
    const bookingId = s.booking.id;
    let active = true;
    const id = setInterval(async () => {
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (active && data?.paid_marked_at) {
        set(prev => (prev.booking?.id === bookingId ? { booking: data } : {}));
      }
    }, 6000);
    return () => { active = false; clearInterval(id); };
  }, [s.booking?.id, s.booking?.paid_marked_at, set]);

  const name = s.formName.trim() || T('Bạn', 'You');
  const confirmEyebrow = isPaid
    ? T('Đã xác nhận', 'Confirmed')
    : holdActive ? T('Đang giữ chỗ cho bạn', 'Holding your spot') : T('Đang chờ thanh toán', 'Awaiting payment');
  const confirmHeading = isPaid
    ? name + T(', vé của bạn đã sẵn sàng.', ', your ticket is ready.')
    : holdActive
      ? name + T(', chỗ của bạn đang được giữ.', ', your spot is being held.')
      : name + T(', hoàn tất thanh toán để nhận vé.', ', complete payment to get your ticket.');
  const confirmNote = T('banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.', 'banbe does not collect money. Pay the organizer directly using the instructions in chat; if they cancel, they are responsible for your refund.');

  const showQr = isPaid;
  const giveLabel = s.gaveTicket ? T('Đã gửi vé ▪︎ link qua Zalo', 'Ticket sent ▪︎ link via Zalo') : T('Tặng vé cho bạn bè', 'Give a ticket to a friend');
  const calendarLabel = s.calAdded ? T('Đã thêm vào lịch', 'Added to calendar') : T('Thêm vào lịch', 'Add to calendar');

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Confirmed">
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '60px 30px 0' }}>
        <span style={{ fontSize: 11.5, color: ink }}>{confirmEyebrow}</span>
        <h2 style={{ ...display(27, { lineHeight: 1.35, margin: '12px 0 0' }) }}>{confirmHeading}</h2>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '18px 0 0' }}>{confirmNote}</p>
        {holdActive && (
          <>
            <div style={{ ...cardGlass({ marginTop: 22, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }) }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Giữ chỗ còn', 'Hold expires in')}</span>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Trả trước khi hết giờ để xác nhận', 'Pay before it runs out to confirm')}</span>
              </div>
              <span style={{ ...display(30, { fontVariantNumeric: 'tabular-nums' }) }}>{countdown}</span>
            </div>
            <div style={{ marginTop: 10, fontSize: 12, lineHeight: 1.5, color: ink }}>{T('Chuyển khoản trực tiếp cho người tổ chức trước khi hết giờ để xác nhận.', 'Pay the organizer directly before the timer ends to confirm.')}</div>
          </>
        )}
        {awaitingPayment && s.booking?.id && (
          <div
            onClick={() => openPaymentDetails(s.booking.id, 'confirmed')}
            style={{ ...cardGlass({ marginTop: holdActive ? 12 : 22, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
            data-testid="confirmed-pay"
          >
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
              <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('Xem thông tin chuyển khoản', 'See payment details')}</span>
              <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Số tài khoản, số tiền và nội dung cần ghi.', 'Account number, amount and the reference to use.')}</span>
            </div>
            <span style={{ fontSize: 17, color: ink, flex: 'none', lineHeight: 1 }}>›</span>
          </div>
        )}
        <div style={{ marginTop: 28, borderTop: `1px solid ${rule}`, paddingTop: 14, display: 'flex', justifyContent: 'space-between', gap: 14, alignItems: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
            <span style={{ ...display(17) }}>{ev.name}</span>
            <span style={{ fontSize: 12, color: ink }}>{ev.where}</span>
            {showQr && s.booking?.code && <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.12em', color: ink }}>{T('Mã vào cửa: ', 'Entry code: ')}{s.booking.code}</span>}
            {!showQr && <span style={{ fontSize: 11.5, color: ink }}>{T('Vé sẽ hiện ở đây sau khi thanh toán được xác nhận.', 'Your ticket appears here once payment is confirmed.')}</span>}
            {showQr && <span style={{ fontSize: 10.5, color: ink }}>{T('Đưa mã này ở cửa', 'Show this code at the door')}</span>}
          </div>
          {showQr && <QrCode value={s.booking.id} />}
        </div>
      </div>
      {showQr && (
        <div onClick={() => giveTicket(ev)} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0', cursor: 'pointer' }}>{giveLabel}</div>
      )}
      <div onClick={addToCalendar} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0', cursor: 'pointer' }}>{calendarLabel}</div>
      <div onClick={goHome} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0 34px', cursor: 'pointer' }}>{T('Về trang chính', 'Back to home')}</div>
    </div>
  );
}

// A real, scannable QR — encodes the booking's own id, which
// check_in_guest() (the same RPC the manual check-in list already uses)
// accepts directly. Fixed black-on-white regardless of theme: it has to
// stay scannable by a phone camera, which doesn't know about --bb-fg/--bb-bg.
function QrCode({ value }) {
  const [src, setSrc] = useState(null);
  useEffect(() => {
    let active = true;
    QRCode.toDataURL(value, { margin: 1, width: 152, color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setSrc(url); })
      .catch(() => {});
    return () => { active = false; };
  }, [value]);

  return (
    <div style={{ flex: 'none', width: 76, height: 76, background: '#FFFFFF', padding: 6 }}>
      {src && <img src={src} alt="QR" style={{ width: '100%', height: '100%', display: 'block' }} />}
    </div>
  );
}

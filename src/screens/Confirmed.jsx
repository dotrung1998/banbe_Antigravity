import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { formatCountdown, msUntil, useTicking } from '../lib/countdown.js';
import { paper, ink, rule, display, cardGlass } from '../theme.js';

export default function Confirmed() {
  const { state, T, set, curEvent: ev, goHome, addToCalendar, giveTicket, openPaymentDetails, forfeitExpiredHold } = useGoc();
  const s = state;

  // payment_state is the source of truth for every phase distinction below;
  // paid_marked_at/status only exist as a fallback for a booking fetched
  // somewhere that hasn't picked up the new column yet (there shouldn't be
  // one, but a booking is the one object here worth a defensive read).
  const phase = s.booking?.payment_state
    || (s.booking?.paid_marked_at ? 'confirmed' : s.booking ? 'holding' : null);
  const isPaid = phase === 'confirmed';
  const isHolding = phase === 'holding';
  const isPendingVerification = phase === 'pending_verification';
  const isDisputed = phase === 'disputed';
  const awaitingPayment = !!s.booking && !isPaid;

  // The countdown only ticks while there is something to actually count
  // down — PHASE 2 shows an SLA reassurance number that ticks too, so both
  // phases need the clock, but PAID/DISPUTED/nothing don't.
  const holdDeadlineIso = s.booking?.hold_expires_at
    || (s.holdDeadline ? new Date(s.holdDeadline).toISOString() : null);
  const now = useTicking(isHolding || isPendingVerification);
  const holdCountdown = formatCountdown(msUntil(holdDeadlineIso, now));
  const verifyMsLeft = msUntil(s.booking?.verify_due_at, now);
  const verifyCountdown = formatCountdown(verifyMsLeft);
  const verifyOverdue = !!s.booking?.verify_due_at && verifyMsLeft === 0;

  // The moment this screen's own ticking clock notices the hold has lapsed,
  // forfeit it immediately rather than leave the ticket sitting in a stale
  // "still holding" state until the next poll or the minutely server sweep
  // gets to it — this is what makes "Going" and the ticket both drop the
  // instant the countdown reaches 00:00, not up to a minute later.
  useEffect(() => {
    // isHolding flips to false the instant forfeitExpiredHold's own local
    // state patch lands (phase is derived straight from booking.payment_state),
    // so this self-guards against firing more than once per lapse.
    if (isHolding && msUntil(holdDeadlineIso, now) === 0) {
      forfeitExpiredHold(s.booking);
    }
  }, [isHolding, holdDeadlineIso, now, s.booking, forfeitExpiredHold]);

  // While a booking is sitting unpaid, poll for a phase change — the
  // organizer confirming, the bank webhook matching, or the guest freezing
  // it from another tab. The guest may already be looking at this exact
  // screen when any of those happen, and shouldn't have to leave and come
  // back via a notification to see it update. Generalised to sync the whole
  // row (not just paid_marked_at) so PHASE 1 -> PHASE 2 shows up live too.
  useEffect(() => {
    if (!s.booking?.id || phase === 'confirmed') return undefined;
    const bookingId = s.booking.id;
    let active = true;
    const id = setInterval(async () => {
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (active && data && data.payment_state !== phase) {
        set(prev => (prev.booking?.id === bookingId ? { booking: data } : {}));
      }
    }, 6000);
    return () => { active = false; clearInterval(id); };
  }, [s.booking?.id, phase, set]);

  const name = s.formName.trim() || T('Bạn', 'You');
  const confirmEyebrow = isPaid
    ? T('Đã xác nhận', 'Confirmed')
    : isHolding ? T('Đang giữ chỗ cho bạn', 'Holding your spot')
    : isPendingVerification ? T('Đang chờ xác nhận', 'Awaiting confirmation')
    : isDisputed ? T('Đang được xem xét', 'Under review')
    : T('Đang chờ thanh toán', 'Awaiting payment');
  const confirmHeading = isPaid
    ? name + T(', vé của bạn đã sẵn sàng.', ', your ticket is ready.')
    : isHolding
      ? name + T(', chỗ của bạn đang được giữ.', ', your spot is being held.')
      : isPendingVerification
        ? name + T(', chỗ của bạn đã được khoá.', ', your seat is locked.')
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

        {/* PHASE 1: the buyer's own clock is running. */}
        {isHolding && (
          <>
            <div style={{ ...cardGlass({ marginTop: 22, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }) }} data-testid="confirmed-hold-countdown">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Giữ chỗ còn', 'Hold expires in')}</span>
                <span style={{ fontSize: 11.5, color: ink }}>{T('Trả trước khi hết giờ để xác nhận', 'Pay before it runs out to confirm')}</span>
              </div>
              <span style={{ ...display(30, { fontVariantNumeric: 'tabular-nums' }) }}>{holdCountdown}</span>
            </div>
            <div style={{ marginTop: 10, fontSize: 12, lineHeight: 1.5, color: ink }}>{T('Chuyển khoản trực tiếp cho người tổ chức trước khi hết giờ để xác nhận.', 'Pay the organizer directly before the timer ends to confirm.')}</div>
          </>
        )}

        {/* PHASE 2: the buyer's clock is GONE — replaced by a reassurance
            countdown for the organizer's own response window, framed so it
            never reads as a threat to the seat itself. */}
        {isPendingVerification && (
          <div style={{ ...cardGlass({ marginTop: 22, padding: '16px 18px' }) }} data-testid="confirmed-verify-countdown">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12 }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
                <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>
                  {T('Chỗ đã khoá ▪︎ không còn đếm ngược cho bạn', 'Seat locked ▪︎ no countdown against you')}
                </span>
                <span style={{ fontSize: 11.5, color: ink, opacity: 0.75 }}>
                  {verifyOverdue
                    ? T('Người tổ chức đang xử lý — có thể mất thêm chút thời gian', "The organizer is on it — may take a little longer")
                    : T('Người tổ chức thường phản hồi trong', "The organizer typically responds within")}
                </span>
              </div>
              {!verifyOverdue && s.booking?.verify_due_at && (
                <span style={{ ...display(24, { fontVariantNumeric: 'tabular-nums', flex: 'none' }) }}>{verifyCountdown}</span>
              )}
            </div>
          </div>
        )}

        {isDisputed && (
          <div style={{ ...cardGlass({ marginTop: 22, padding: '16px 18px' }) }} data-testid="confirmed-disputed">
            <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('banbe đang xem xét', 'banbe is reviewing this')}</span>
            <p style={{ fontSize: 12, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
              {T('Chỗ của bạn vẫn được giữ trong lúc chờ xem xét.', 'Your seat stays held while this is reviewed.')}
            </p>
          </div>
        )}

        {awaitingPayment && s.booking?.id && (
          <div
            onClick={() => openPaymentDetails(s.booking.id, 'confirmed')}
            style={{ ...cardGlass({ marginTop: (isHolding || isPendingVerification || isDisputed) ? 12 : 22, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
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

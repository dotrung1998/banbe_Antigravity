import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { supabase } from '../lib/supabase.js';
import { formatCountdown, msUntil, useTicking } from '../lib/countdown.js';
import { paper, ink, rule, display, cardGlass, alert } from '../theme.js';

export default function Confirmed() {
  const {
    state, T, set, curEvent: ev, goHome, openCalendarPicker, closeCalendarPicker, addToCalendarGoogle, addToCalendarICS, giveTicket, openPaymentDetails, forfeitExpiredHold, goReserve,
    loadReceiptStatus, requestReceipt, openDocumentFromNotification,
  } = useGoc();
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
  const isExpired = phase === 'expired';
  const awaitingPayment = !!s.booking && !isPaid && !isExpired;

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

  // "Xem Receipt" needs to know, per booking, whether a live
  // payment_documents row already exists — reset on every booking change
  // (not just once) since this screen can be reopened for a different
  // booking without unmounting (openBookingConfirmed just patches state).
  useEffect(() => {
    if (isPaid && s.booking?.id) loadReceiptStatus(s.booking.id);
    else set({ receiptDoc: undefined, receiptRequestSent: false, receiptRequestError: '' });
  }, [isPaid, s.booking?.id, loadReceiptStatus, set]);

  // Bug 1 (15-organizer-checkin.md follow-up): a guest sitting on this exact
  // screen while the organizer uploads (from Attendance's own poll picking
  // up a "Xem Receipt"/request_receipt() ask, or unprompted) previously had
  // to leave and come back for the control to notice — matches this app's
  // established polling convention elsewhere (Attendance's own 6s poll,
  // 41340ee; PaymentDetails' 6s poll). Stops once a receipt is actually
  // found — nothing left to poll for once it exists.
  useEffect(() => {
    if (!isPaid || !s.booking?.id || s.receiptDoc) return undefined;
    const bookingId = s.booking.id;
    const id = setInterval(() => loadReceiptStatus(bookingId), 6000);
    return () => clearInterval(id);
  }, [isPaid, s.booking?.id, s.receiptDoc, loadReceiptStatus]);

  // While a booking is sitting unpaid, poll for a phase change — the
  // organizer confirming, the bank webhook matching, or the guest freezing
  // it from another tab. The guest may already be looking at this exact
  // screen when any of those happen, and shouldn't have to leave and come
  // back via a notification to see it update. Generalised to sync the whole
  // row (not just paid_marked_at) so PHASE 1 -> PHASE 2 shows up live too.
  useEffect(() => {
    if (!s.booking?.id || phase === 'confirmed' || phase === 'expired') return undefined;
    const bookingId = s.booking.id;
    let active = true;
    const id = setInterval(async () => {
      const { data } = await supabase.from('bookings').select('*').eq('id', bookingId).maybeSingle();
      if (!active || !data) return;
      // The server row can still read 'holding' past its own deadline for a
      // moment — the sweep hasn't reached it yet, or this same client's own
      // forfeit RPC (fired the instant the local countdown hit 0) hasn't
      // landed. Blindly copying that stale row over would revive a ticket
      // this tab already forfeited every 6 seconds until the server catches
      // up. Treat it as expired here too instead, and let forfeitExpiredHold
      // retry the RPC rather than regressing local state backwards.
      if (data.payment_state === 'holding' && msUntil(data.hold_expires_at) === 0) {
        forfeitExpiredHold(data);
        return;
      }
      if (data.payment_state !== phase) {
        set(prev => (prev.booking?.id === bookingId ? { booking: data } : {}));
      }
    }, 6000);
    return () => { active = false; clearInterval(id); };
  }, [s.booking?.id, phase, set, forfeitExpiredHold]);

  // formName used to be a free-typed, never-persisted Reserve.jsx field —
  // s.user.name (real profiles.display_name, 01-hold-payment.md's
  // 2026-09-17 follow-up #6) is the actual identity now.
  const name = (s.user?.name || '').trim() || T('Bạn', 'You');
  const confirmEyebrow = isPaid
    ? T('Đã xác nhận', 'Confirmed')
    : isHolding ? T('Đang giữ chỗ cho bạn', 'Holding your spot')
    : isPendingVerification ? T('Đang chờ xác nhận', 'Awaiting confirmation')
    : isDisputed ? T('Đang được xem xét', 'Under review')
    : isExpired ? T('Đã hết hạn giữ chỗ', 'Hold expired')
    : T('Đang chờ thanh toán', 'Awaiting payment');
  const confirmHeading = isPaid
    ? name + T(', vé của bạn đã sẵn sàng.', ', your ticket is ready.')
    : isHolding
      ? name + T(', chỗ của bạn đang được giữ.', ', your spot is being held.')
      : isPendingVerification
        ? name + T(', chỗ của bạn đã được khoá.', ', your seat is locked.')
        : isExpired
          ? name + T(', chỗ giữ đã hết hạn và đã được mở lại.', ", your hold expired and the seat's been released.")
          : name + T(', hoàn tất thanh toán để nhận vé.', ', complete payment to get your ticket.');
  const confirmNote = isExpired
    ? T('Bạn chưa chuyển khoản trước khi hết giờ giữ chỗ, nên chỗ đã được mở lại cho người khác. Bạn có thể giữ chỗ lại nếu vẫn còn chỗ trống.', "You didn't complete payment before the hold ran out, so the seat was released back. You can reserve again if there's still room.")
    : T('banbe không thu tiền. Hãy chuyển khoản trực tiếp cho người tổ chức theo hướng dẫn trong tin nhắn; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.', 'banbe does not collect money. Pay the organizer directly using the instructions in chat; if they cancel, they are responsible for your refund.');

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

        {isExpired && (
          <div
            onClick={goReserve}
            style={{ ...cardGlass({ marginTop: 22, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
            data-testid="confirmed-expired-reserve"
          >
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
              <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>{T('Giữ chỗ lại', 'Reserve again')}</span>
              <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>{T('Nếu vẫn còn chỗ trống.', 'If there’s still room.')}</span>
            </div>
            <span style={{ fontSize: 17, color: ink, flex: 'none', lineHeight: 1 }}>›</span>
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
            {!showQr && (
              <span style={{ fontSize: 11.5, color: ink }}>
                {isExpired
                  ? T('Chỗ này đã được mở lại.', 'This seat has been released.')
                  : T('Vé sẽ hiện ở đây sau khi thanh toán được xác nhận.', 'Your ticket appears here once payment is confirmed.')}
              </span>
            )}
            {showQr && <span style={{ fontSize: 10.5, color: ink }}>{T('Đưa mã này ở cửa', 'Show this code at the door')}</span>}
          </div>
          {showQr && <QrCode value={s.booking.id} />}
        </div>
      </div>
      {showQr && (
        <div onClick={() => giveTicket(ev)} style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0', cursor: 'pointer' }}>{giveLabel}</div>
      )}
      <div onClick={openCalendarPicker} data-testid="confirmed-add-to-calendar" style={{ borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0', cursor: 'pointer' }}>{calendarLabel}</div>

      {s.calendarPickerFor === ev.key && (
        <div onClick={closeCalendarPicker} style={{ position: 'fixed', inset: 0, background: 'rgba(27,25,22,0.4)', display: 'flex', alignItems: 'flex-end', zIndex: 50 }}>
          <div onClick={(e) => e.stopPropagation()} style={{ background: paper, width: '100%', borderRadius: '18px 18px 0 0', padding: '10px 22px 28px' }}>
            <div style={{ width: 36, height: 4, background: rule, borderRadius: 2, margin: '6px auto 18px' }} />
            <p style={{ fontSize: 13, fontWeight: 600, color: ink, margin: '0 0 14px' }}>
              {T('Thêm vào lịch nào?', 'Add to which calendar?')}
            </p>
            <div onClick={() => addToCalendarGoogle(ev)} data-testid="calendar-pick-google"
                 style={{ ...cardGlass({ padding: '14px 16px', marginBottom: 10, cursor: 'pointer' }) }}>
              <span style={{ fontSize: 14, color: ink }}>Google Calendar</span>
            </div>
            <div onClick={() => addToCalendarICS(ev)} data-testid="calendar-pick-apple"
                 style={{ ...cardGlass({ padding: '14px 16px', marginBottom: 10, cursor: 'pointer' }) }}>
              <span style={{ fontSize: 14, color: ink }}>{T('Lịch Apple ▪︎ Ứng dụng khác', 'Apple Calendar ▪︎ Other apps')}</span>
              <div style={{ fontSize: 11, color: ink, opacity: 0.65, marginTop: 3 }}>
                {T('Tải file .ics — mở bằng Lịch hoặc bất kỳ ứng dụng lịch nào khác.', 'Downloads an .ics file — open it with Calendar or any other calendar app.')}
              </div>
            </div>
            <div onClick={closeCalendarPicker} style={{ textAlign: 'center', fontSize: 13, color: ink, opacity: 0.7, padding: '10px 0', cursor: 'pointer' }}>
              {T('Huỷ', 'Cancel')}
            </div>
          </div>
        </div>
      )}
      {/* 15-organizer-checkin.md follow-up: receipts are organizer-uploaded
          now (08-payment-documents.md), not auto-issued the moment a
          booking is confirmed — so this screen can't assume one exists yet.
          `receiptDoc` is `undefined` while the check is in flight, a real
          row once found, or `false` once confirmed absent. */}
      {showQr && s.receiptDoc !== undefined && (
        <div
          onClick={() => {
            if (s.receiptDoc) openDocumentFromNotification(s.receiptDoc.id, 'confirmed');
            else if (!s.receiptRequestSent) requestReceipt(s.booking.id);
          }}
          style={{
            borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, textAlign: 'center', padding: '17px 0',
            cursor: (s.receiptDoc || !s.receiptRequestSent) ? 'pointer' : 'default',
            opacity: s.receiptRequestSending ? 0.6 : 1,
          }}
          data-testid="confirmed-view-receipt"
        >
          {s.receiptDoc
            ? T('Xem Receipt', 'View Receipt')
            : s.receiptRequestSending
            ? T('Đang gửi yêu cầu…', 'Sending request…')
            : s.receiptRequestSent
            ? T('Đã gửi yêu cầu ▪︎ Đang chờ người tổ chức', 'Request sent ▪︎ waiting on the organizer')
            : T('Yêu cầu Receipt', 'Request Receipt')}
        </div>
      )}
      {s.receiptRequestError && (
        <p style={{ fontSize: 11, color: alert, textAlign: 'center', margin: '8px 22px 0' }}>{s.receiptRequestError}</p>
      )}
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

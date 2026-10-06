import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { formatCountdown, msUntil, useTicking } from '../lib/countdown.js';
import { paper, ink, rule, display, cardGlass, alert } from '../theme.js';
import { isBookingTicket } from '../lib/bookingTicket.js';
import BanbeLoadingVisual from './BanbeLoadingVisual.jsx';
import { downloadTicketPdfs, googleCalendarUrl } from '../lib/ticketPdf.js';
import GiftTicketSheet from './sheets/GiftTicketSheet.jsx';
import { giftPdfData, isAppleWalletBrowser, addToAppleWallet, walletErrorMessage } from '../lib/giftTicket.js';

export default function Confirmed() {
  const {
    state, T, trStatus, stripKm, set, curEvent: ev, backFromConfirmed, openCalendarPicker, closeCalendarPicker, addToCalendarGoogle, addToCalendarICS, openPaymentDetails, forfeitExpiredHold, goReserve,
    loadReceiptStatus, requestReceipt, openDocumentFromNotification, loadBookingAttendees,
  } = useBanBe();
  const s = state;

  // payment_state is the source of truth for every phase distinction below;
  // paid_marked_at/status only exist as a fallback for a booking fetched
  // somewhere that hasn't picked up the new column yet (there shouldn't be
  // one, but a booking is the one object here worth a defensive read).
  const phase = s.booking?.payment_state
    || (s.booking?.paid_marked_at ? 'confirmed' : s.booking ? 'holding' : null);
  // TASK B (2026-10-01 UX foundation pass) — the ticket/QR is only ever
  // real once BOTH booking.status AND payment_state read 'confirmed'; see
  // isBookingTicket()'s own doc comment (src/lib/bookingTicket.js).
  const isPaid = isBookingTicket(s.booking);
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

  // Named tickets (migration 151): one card per attendee, each with its own QR
  // and PDF. Empty for a booking made before per-attendee tickets, which keeps
  // its single booking-level QR.
  useEffect(() => { if (s.booking?.id) loadBookingAttendees(s.booking.id); }, [s.booking?.id, loadBookingAttendees]);
  const attendees = (s.bookingAttendees || []).filter(a => a.booking_id === s.booking?.id);
  const hasNamed = attendees.length > 0;
  const [selected, setSelected] = useState(() => new Set());
  const [pdfBusy, setPdfBusy] = useState(false);
  useEffect(() => { setSelected(new Set()); }, [s.booking?.id]);
  const [giftOpen, setGiftOpen] = useState(false);
  const [walletBusy, setWalletBusy] = useState(false);
  const [walletMsg, setWalletMsg] = useState('');
  const [giftedSeats, setGiftedSeats] = useState([]); // seats split off this booking and gifted away
  useEffect(() => { setGiftOpen(false); setWalletMsg(''); }, [s.booking?.id]);
  const reloadGiftedSeats = async (bookingId) => {
    const { data } = await supabase.from('bookings').select('*').eq('original_booking_id', bookingId).not('recipient_name', 'is', null).order('gifted_at', { ascending: true });
    setGiftedSeats(data || []);
  };
  useEffect(() => {
    let live = true;
    setGiftedSeats([]);
    if (isPaid && s.booking?.id) {
      supabase.from('bookings').select('*').eq('original_booking_id', s.booking.id).not('recipient_name', 'is', null).order('gifted_at', { ascending: true })
        .then(({ data }) => { if (live) setGiftedSeats(data || []); });
    }
    return () => { live = false; };
  }, [isPaid, s.booking?.id]);
  const toggleSel = (id) => setSelected(prev => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });

  const eventStart = ev.startDate || new Date();
  const calUrl = googleCalendarUrl({
    title: ev.name, start: eventStart, end: new Date(eventStart.getTime() + 2 * 3600 * 1000),
    location: ev.locationLabel || ev.where || '', description: ev.desc || '',
  });
  const pdfBase = {
    eventName: ev.name, organizer: ev.orgName || ev.host || '', whenText: ev.when, venue: ev.locationLabel || ev.where || '',
    isEN: s.lang === 'en', calendarUrl: calUrl,
  };
  const runDownload = async (list) => {
    if (!list.length || pdfBusy) return;
    setPdfBusy(true);
    try { await downloadTicketPdfs(list, `banbe-tickets-${s.booking?.code || 'booking'}.zip`); }
    catch (e) { console.warn('ticket PDF failed:', e); }
    setPdfBusy(false);
  };
  const attendeePdf = (a) => ({
    ...pdfBase, holderName: a.name, ticketCode: a.ticket_code, qrValue: a.admission_token, reference: a.id,
    importUrl: a.claim_code ? `${window.location.origin}/?claim=${encodeURIComponent(a.claim_code)}` : undefined,
  });
  const ownPdf = () => ({
    ...pdfBase, holderName: (s.user?.name || '').trim(), ticketCode: s.booking?.code || '', qrValue: s.booking?.admission_token || s.booking?.id, reference: s.booking?.id,
  });
  // This booking row IS a gifted seat (single-seat gift, or the split-off row).
  const isGifted = !!s.booking?.recipient_name;
  const giftPdfOf = (b) => giftPdfData(pdfBase, {
    recipientName: b.recipient_name, ticketCode: b.code, admissionToken: b.admission_token || b.id, claimCode: b.claim_code, reference: b.id,
  });
  // After a gift: refresh the open booking (qty drops for a multi-seat split; a
  // single seat becomes the gifted row) and the list of gifted seats.
  const onGifted = async () => {
    const id = s.booking?.id;
    if (!id) return;
    const { data } = await supabase.from('bookings').select('*').eq('id', id).maybeSingle();
    if (data) set(prev => (prev.booking?.id === id ? { booking: data } : {}));
    reloadGiftedSeats(id);
  };
  const walletEligible = isAppleWalletBrowser();
  const runWallet = async () => {
    if (walletBusy || !s.booking?.id) return;
    setWalletBusy(true); setWalletMsg('');
    const code = await addToAppleWallet(s.booking.id);
    setWalletBusy(false);
    if (code) setWalletMsg(walletErrorMessage(code, T));
  };
  const ageOf = (iso) => {
    if (!iso) return null;
    const d = new Date(iso); const n = new Date();
    let age = n.getFullYear() - d.getFullYear();
    if (n.getMonth() < d.getMonth() || (n.getMonth() === d.getMonth() && n.getDate() < d.getDate())) age -= 1;
    return age;
  };

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
  const calendarLabel = s.calAdded ? T('Đã thêm vào lịch', 'Added to calendar') : T('Thêm vào lịch', 'Add to calendar');

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper, display: 'flex', flexDirection: 'column' }} data-screen-label="Confirmed">
      {/* Back, top-left — where the thumb and the OS convention expect it. */}
      <div onClick={backFromConfirmed} data-testid="confirmed-back" style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '14px 30px 0', fontSize: 14, color: ink, cursor: 'pointer', alignSelf: 'flex-start' }}>
        <svg width="10" height="16" viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M8 1.5 2 8l6 6.5" /></svg>
        {s.confirmedBack === 'notifications' ? T('Thông báo', 'Notifications')
          : s.confirmedBack === 'accountGroup' ? T('Tài khoản', 'Account')
          : T('Quay lại', 'Back')}
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '24px 30px 0' }}>
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
                    ? T('Người tổ chức đang xử lý, có thể mất thêm chút thời gian', "The organizer is on it, may take a little longer")
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
        {isPaid && hasNamed ? (
          <div style={{ marginTop: 28, borderTop: `1px solid ${rule}`, paddingTop: 14, display: 'flex', flexDirection: 'column', gap: 12 }} data-testid="confirmed-attendee-tickets">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 10 }}>
              <span style={{ ...display(17) }}>{ev.name}</span>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.65, flex: 'none' }}>{attendees.length} {T('vé', attendees.length === 1 ? 'ticket' : 'tickets')}</span>
            </div>
            <span style={{ fontSize: 12, color: ink }}>{trStatus(stripKm(ev.where, ev))}</span>
            <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{T('Mỗi người có mã QR riêng — đưa mã của chính họ ở cửa.', 'Each person has their own QR — show their own code at the door.')}</span>
            {attendees.map(a => {
              const on = selected.has(a.id);
              const age = ageOf(a.date_of_birth);
              return (
                <div key={a.id} style={{ ...cardGlass({ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 12 }) }} data-testid={`confirmed-attendee-${a.seat_no}`}>
                  <span onClick={() => toggleSel(a.id)} role="checkbox" aria-checked={on} data-testid={`confirmed-attendee-select-${a.seat_no}`}
                    style={{ flex: 'none', width: 22, height: 22, borderRadius: 11, border: `1.5px solid ${ink}`, background: on ? ink : 'transparent', color: paper, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, cursor: 'pointer' }}>{on ? '✓' : ''}</span>
                  <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 3 }}>
                    <span style={{ fontSize: 14, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{a.name}</span>
                    {age != null && <span style={{ fontSize: 11.5, color: ink, opacity: 0.65 }}>{T(`${age} tuổi`, `Age ${age}`)}</span>}
                    <span style={{ fontSize: 11.5, fontWeight: 600, letterSpacing: '0.08em', color: ink }}>{a.ticket_code}</span>
                    {a.checked_in_at && <span style={{ fontSize: 10.5, fontWeight: 700, color: alert }}>{T('Đã vào cửa', 'Checked in')}</span>}
                  </div>
                  <QrCode value={a.admission_token} size={72} />
                  <span onClick={() => runDownload([attendeePdf(a)])} title={T('Tải vé PDF', 'Download PDF')} data-testid={`confirmed-attendee-download-${a.seat_no}`}
                    style={{ flex: 'none', width: 34, height: 34, borderRadius: 17, background: 'var(--bb-field)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: pdfBusy ? 0.5 : 1 }}>
                    <Icon kind="download" size={16} />
                  </span>
                </div>
              );
            })}
            <div style={{ display: 'flex', gap: 10 }}>
              <span onClick={() => runDownload(attendees.filter(a => selected.has(a.id)).map(attendeePdf))} data-testid="confirmed-download-selected"
                style={{ ...cardGlass({ flex: 1, padding: '12px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, cursor: selected.size ? 'pointer' : 'default', opacity: selected.size ? 1 : 0.45 }) }}>
                {T(`Tải đã chọn (${selected.size})`, `Download selected (${selected.size})`)}
              </span>
              <span onClick={() => runDownload(attendees.map(attendeePdf))} data-testid="confirmed-download-all"
                style={{ ...cardGlass({ flex: 1, padding: '12px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 600, color: ink, cursor: 'pointer' }) }}>
                {T('Tải tất cả', 'Download all')}
              </span>
            </div>
            {pdfBusy && <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{T('Đang tạo PDF…', 'Preparing PDF…')}</span>}
          </div>
        ) : (
        <div style={{ marginTop: 28, borderTop: `1px solid ${rule}`, paddingTop: 14, display: 'flex', justifyContent: 'space-between', gap: 14, alignItems: 'center' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, minWidth: 0 }}>
            <span style={{ ...display(17) }}>{ev.name}</span>
            <span style={{ fontSize: 12, color: ink }}>{trStatus(stripKm(ev.where, ev))}</span>
            {showQr && !isGifted && s.booking?.code && <span style={{ fontSize: 12, fontWeight: 600, letterSpacing: '0.12em', color: ink }}>{T('Mã vào cửa: ', 'Entry code: ')}{s.booking.code}</span>}
            {!showQr && (
              <span style={{ fontSize: 11.5, color: ink }}>
                {isExpired
                  ? T('Chỗ này đã được mở lại.', 'This seat has been released.')
                  : T('Vé sẽ hiện ở đây sau khi thanh toán được xác nhận.', 'Your ticket appears here once payment is confirmed.')}
              </span>
            )}
            {showQr && !isGifted && <span style={{ fontSize: 10.5, color: ink }}>{T('Đưa mã này ở cửa', 'Show this code at the door')}</span>}
          </div>
          {showQr && isGifted && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3, textAlign: 'right', minWidth: 0 }} data-testid="confirmed-gifted">
              <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.65 }}>{T('Đã tặng', 'Gifted')}</span>
              <span style={{ fontSize: 15, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.booking.recipient_name}</span>
            </div>
          )}
          {showQr && !isGifted && <QrCode value={s.booking.admission_token || s.booking.id} />}
        </div>
        )}
        {isPaid && giftedSeats.length > 0 && !isGifted && (
          <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 8 }} data-testid="confirmed-gifted-seats">
            {giftedSeats.map(g => (
              <div key={g.id} style={{ ...cardGlass({ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 12 }) }} data-testid={`confirmed-gifted-seat-${g.id}`}>
                <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.65 }}>{T('Đã tặng', 'Gifted')}</span>
                  <span style={{ fontSize: 14, fontWeight: 600, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{g.recipient_name}</span>
                </div>
                <span onClick={() => runDownload([giftPdfOf(g)])} title={T('Tải lại vé PDF', 'Re-download the PDF')} data-testid={`confirmed-gifted-seat-download-${g.id}`}
                  style={{ flex: 'none', width: 34, height: 34, borderRadius: 17, background: 'var(--bb-field)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', opacity: pdfBusy ? 0.5 : 1 }}>
                  <Icon kind="download" size={16} />
                </span>
              </div>
            ))}
          </div>
        )}
        {/* Real-device follow-up (2026-09-27) — fills the empty space below
            the ticket row (this container's own `flex:1` absorbs whatever
            room is left over after the fixed-size content above it) with
            the same shared Banbe loading GIF, at half its previous pixel
            size (public/banbe-loading.gif was resized 380x297 -> 190x148,
            not just displayed smaller) per this follow-up's own request. */}
        <div style={{ flex: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', paddingTop: 20, paddingBottom: 24 }}>
          <BanbeLoadingVisual size={190} />
        </div>
      </div>
      {showQr && isGifted && (
        <FooterRow icon="download" label={pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải lại vé PDF', 'Re-download the PDF')} onClick={() => runDownload([giftPdfOf(s.booking)])} testId="confirmed-gifted-pdf" />
      )}
      {showQr && !hasNamed && !isGifted && (
        <FooterRow icon="gift" label={T('Tặng vé cho bạn bè', 'Give a ticket to a friend')} onClick={() => setGiftOpen(true)} testId="confirmed-give-ticket" />
      )}
      {showQr && !hasNamed && !isGifted && walletEligible && (
        <FooterRow icon="wallet" label={walletBusy ? T('Đang tạo vé Wallet…', 'Preparing Wallet pass…') : T('Thêm vào Apple Wallet', 'Add to Apple Wallet')} onClick={runWallet} dim={walletBusy} testId="confirmed-add-to-wallet" />
      )}
      {showQr && !hasNamed && !isGifted && walletEligible && walletMsg && (
        <p style={{ fontSize: 11, color: alert, textAlign: 'center', margin: '8px 22px 0' }} data-testid="confirmed-wallet-error">{walletMsg}</p>
      )}
      {showQr && !hasNamed && !isGifted && (
        <FooterRow icon="download" label={pdfBusy ? T('Đang tạo PDF…', 'Preparing PDF…') : T('Tải vé PDF', 'Download PDF')} onClick={() => runDownload([ownPdf()])} testId="confirmed-download-pdf" />
      )}
      {/* Add to calendar: a glass popover that opens out of the row (like the
          iOS Menu) and closes on a tap anywhere outside it. */}
      <div style={{ position: 'relative' }}>
        <FooterRow
          icon={s.calAdded ? 'calendarCheck' : 'calendarPlus'} chip
          label={calendarLabel} onClick={openCalendarPicker} testId="confirmed-add-to-calendar"
        />
        {s.calendarPickerFor === ev.key && (
          <>
            <div onClick={closeCalendarPicker} style={{ position: 'fixed', inset: 0, zIndex: 49 }} data-testid="calendar-pick-scrim" />
            <div
              role="menu"
              style={{
                position: 'absolute', left: 22, right: 22, bottom: 'calc(100% - 6px)', zIndex: 50, transformOrigin: 'bottom center',
                animation: 'bbPopIn 0.2s cubic-bezier(.22,.61,.36,1) both',
                borderRadius: 22, padding: 8, overflow: 'hidden',
                background: 'rgba(250,248,244,0.72)', backdropFilter: 'blur(24px) saturate(170%)', WebkitBackdropFilter: 'blur(24px) saturate(170%)',
                border: '1px solid rgba(255,255,255,0.55)', boxShadow: '0 18px 40px rgba(27,25,22,0.22), inset 0 1px 0 rgba(255,255,255,0.7)',
              }}
            >
              <div role="menuitem" onClick={() => addToCalendarGoogle(ev)} data-testid="calendar-pick-google"
                   style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', borderRadius: 16, cursor: 'pointer', fontSize: 14, color: ink }}>
                <Icon kind="globe" size={18} /> Google Calendar
              </div>
              <div role="menuitem" onClick={() => addToCalendarICS(ev)} data-testid="calendar-pick-apple"
                   style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 14px', borderRadius: 16, cursor: 'pointer', fontSize: 14, color: ink }}>
                <Icon kind="calendar" size={18} />
                <span>{T('Lịch Apple ▪︎ Ứng dụng khác', 'Apple Calendar ▪︎ Other apps')}
                  <span style={{ display: 'block', fontSize: 11, opacity: 0.6, marginTop: 2 }}>{T('Tải file .ics', 'Downloads an .ics file')}</span>
                </span>
              </div>
            </div>
          </>
        )}
      </div>
      {/* Receipts are organizer-uploaded (08-payment-documents.md), so this
          screen can't assume one exists. `receiptDoc` is `undefined` while
          the check is in flight, a real row once found, `false` once absent. */}
      {showQr && s.receiptDoc !== undefined && (
        <FooterRow
          icon="doc" testId="confirmed-view-receipt"
          label={s.receiptDoc
            ? T('Xem Receipt', 'View Receipt')
            : s.receiptRequestSending
            ? T('Đang gửi yêu cầu…', 'Sending request…')
            : s.receiptRequestSent
            ? T('Đã gửi yêu cầu ▪︎ Đang chờ người tổ chức', 'Request sent ▪︎ waiting on the organizer')
            : T('Yêu cầu Receipt', 'Request Receipt')}
          dim={s.receiptRequestSending}
          onClick={(s.receiptDoc || !s.receiptRequestSent) ? () => {
            if (s.receiptDoc) openDocumentFromNotification(s.receiptDoc.id, 'confirmed');
            else requestReceipt(s.booking.id);
          } : undefined}
        />
      )}
      {s.receiptRequestError && (
        <p style={{ fontSize: 11, color: alert, textAlign: 'center', margin: '8px 22px 0' }}>{s.receiptRequestError}</p>
      )}
      <div style={{ height: 34 }} />
      {giftOpen && s.booking?.id && (
        <GiftTicketSheet
          bookingId={s.booking.id} seats={s.booking.qty || 1} eventName={ev.name} pdfBase={pdfBase}
          onGifted={onGifted} onClose={() => setGiftOpen(false)}
        />
      )}
    </div>
  );
}

// One footer row: a fixed-width icon column (so every icon and label lines up
// down the page), the label, and a quiet chevron. `chip` puts the icon on the
// soft round disc the iOS Settings button uses.
function FooterRow({ icon, label, onClick, testId, chip = false, dim = false }) {
  return (
    <div
      onClick={onClick} data-testid={testId}
      style={{
        borderTop: `1px solid ${rule}`, color: ink, fontSize: 13.5, display: 'flex', alignItems: 'center', gap: 14,
        padding: '10px 30px', minHeight: 54, boxSizing: 'border-box', cursor: onClick ? 'pointer' : 'default', opacity: dim ? 0.6 : 1,
      }}
    >
      <span style={{ flex: 'none', width: 34, height: 34, borderRadius: 17, display: 'flex', alignItems: 'center', justifyContent: 'center', background: chip ? 'var(--bb-field)' : 'transparent' }}>
        <Icon kind={icon} size={16} />
      </span>
      <span style={{ flex: 1, minWidth: 0 }}>{label}</span>
      <svg width="8" height="13" viewBox="0 0 8 13" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.35, flex: 'none' }}><path d="m1.5 1.5 5 5-5 5" /></svg>
    </div>
  );
}

const ICON_PATHS = {
  gift: <><rect x="3" y="9" width="18" height="12" rx="2" /><path d="M12 9v12M3 13h18M12 9c-2.5 0-4.5-1-4.5-3S9.5 3 12 6c2.5-3 4.5-1 4.5 0S14.5 9 12 9Z" /></>,
  download: <><path d="M6 3h9l4 4v14H6z" /><path d="M12 10v6m0 0-2.5-2.5M12 16l2.5-2.5" /></>,
  calendar: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
  calendarPlus: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4M12 13v5M9.5 15.5h5" /></>,
  calendarCheck: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4M9.5 15l2 2 3.5-3.5" /></>,
  globe: <><circle cx="12" cy="12" r="8.5" /><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.5 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.5-3.5-8.5s1-6 3.5-8.5Z" /></>,
  wallet: <><rect x="3" y="6" width="18" height="13" rx="2.5" /><path d="M3 10h18M16.5 14.5h.01" /></>,
  doc: <><path d="M6 3h9l4 4v14H6z" /><path d="M9 12h7M9 16h7" /></>,
};
function Icon({ kind, size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {ICON_PATHS[kind]}
    </svg>
  );
}

function QrCode({ value, size = 76 }) {
  const [src, setSrc] = useState(null);
  useEffect(() => {
    let active = true;
    QRCode.toDataURL(value, { margin: 1, width: Math.max(152, size * 2), color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setSrc(url); })
      .catch(() => {});
    return () => { active = false; };
  }, [value]);

  // A4 (Pulse/loading UX pass, 2026-09-27) — "the currently blank region
  // beneath 'View Your Ticket' ONLY when ticket content is actually
  // loading": `QRCode.toDataURL` above is async — `src` is genuinely null
  // for one tick while it resolves, and this exact block used to render
  // nothing at all during that gap (an honest-but-blank region, reached by
  // tapping "Xem vé của bạn" on Event Detail). Now shows the shared Banbe
  // loading GIF for that gap instead of a blank box. iOS's own QR
  // (`QRCodeImage` in Components.swift) generates synchronously via
  // CoreImage inside `body` — no equivalent async gap exists there, so no
  // iOS change was needed for this specific item (confirmed by reading
  // that component, not assumed).
  return (
    <div style={{ flex: 'none', width: size, height: size, background: '#FFFFFF', padding: 6, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      {src ? <img src={src} alt="QR" style={{ width: '100%', height: '100%', display: 'block' }} /> : <BanbeLoadingVisual size={40} />}
    </div>
  );
}

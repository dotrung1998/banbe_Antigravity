import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { findEvent } from '../data/events.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';

export default function Attendance() {
  const {
    state, set, T, trStatus, goDashboard, toggleCheckin, openQrScan, openCancelBooking, markGuestPaid, uploadPaymentDocument,
    openVerificationDetail, openRejectGuest,
  } = useGoc();
  const s = state;
  const fileInputRef = useRef(null);
  const [uploadingFor, setUploadingFor] = useState(null);
  const [uploadErrorFor, setUploadErrorFor] = useState(null);
  // request_receipt() (migration 061) deep-links here via openNotification()
  // — the guest's own "Xem Receipt" asked for one that doesn't exist yet.
  // Mirrors DisputeChatPanel.jsx's chatHighlight scroll/flash pattern: a
  // ref per booking id, scroll the matching one into view, flash it
  // briefly, then clear the request so it doesn't refire on every render.
  const uploadRefs = useRef({});
  const [highlightedBookingId, setHighlightedBookingId] = useState(null);
  useEffect(() => {
    const targetId = s.attendanceHighlightBookingId;
    if (!targetId) return;
    const node = uploadRefs.current[targetId];
    if (!node) return; // guests list may still be loading — try again once it renders
    node.scrollIntoView({ behavior: 'smooth', block: 'center' });
    setHighlightedBookingId(targetId);
    set({ attendanceHighlightBookingId: null });
    const timeout = setTimeout(() => setHighlightedBookingId(null), 2200);
    return () => clearTimeout(timeout);
  }, [s.attendanceHighlightBookingId, s.attendanceGuests, set]);

  const pickReceiptFile = (bookingId) => {
    setUploadErrorFor(null);
    fileInputRef.current.dataset.bookingId = bookingId;
    fileInputRef.current.click();
  };
  const onReceiptFileChosen = async (e) => {
    const file = e.target.files?.[0];
    const bookingId = fileInputRef.current.dataset.bookingId;
    e.target.value = '';
    if (!file || !bookingId) return;
    setUploadingFor(bookingId);
    const result = await uploadPaymentDocument(bookingId, 'receipt', file);
    setUploadingFor(null);
    if (!result.success) setUploadErrorFor(bookingId);
  };

  const attKey = s.attendanceEventKey;
  const attEv = attKey ? findEvent(attKey) : null;

  if (!attEv) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
        <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      </div>
    );
  }

  // The guest list is whoever actually holds a real booking for this event
  // (GocContext's loadAttendanceGuests), not a generated placeholder list.
  const guests = s.attendanceGuests;
  const checkedCount = guests.filter(g => g.checkedIn).length;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
      <div onClick={goDashboard} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Trang của bạn', 'Your dashboard')}</div>
      <div style={{ padding: '14px 22px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ minWidth: 0 }}>
          <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Điểm danh khách', 'Guest check-in')}</span>
          <h1 style={{ ...display(24, { margin: '8px 0 0' }) }}>{attEv.name}</h1>
          <div style={{ fontSize: 12.5, color: ink, marginTop: 4 }}>{trStatus(attEv.when)}</div>
        </div>
        <div onClick={openQrScan} style={{ flex: 'none', fontSize: 12, fontWeight: 600, color: paper, background: ink, borderRadius: 12, padding: '9px 14px', cursor: 'pointer', whiteSpace: 'nowrap' }}>{T('Quét QR', 'Scan QR')}</div>
      </div>
      <div style={{ margin: '18px 22px 0', background: ink, padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 12.5, color: paper }}>{T('Đã đến', 'Checked in')}</span>
        <span style={{ fontFamily: "'Be Vietnam Pro', sans-serif", fontWeight: 600, letterSpacing: '-0.02em', fontSize: 24, color: paper }}>{checkedCount} / {guests.length}</span>
      </div>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, margin: '10px 22px 0' }}>{T('Chạm vào tên khách hoặc quét mã QR vé khi họ tới nơi.', "Tap a guest's name, or scan their ticket QR, when they arrive.")}</p>
      <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '6px 22px 0' }}>{T('Đánh dấu "Đã thanh toán" khi bạn thấy tiền vào tài khoản, rồi tải lên hoá đơn/biên nhận thật của bạn cho khách.', 'Mark a guest paid once you see the money arrive, then upload your own real invoice/receipt for them.')}</p>
      <input ref={fileInputRef} type="file" accept="image/jpeg,image/png,image/webp,application/pdf" style={{ display: 'none' }} onChange={onReceiptFileChosen} data-testid="attendance-receipt-input" />
      <div style={{ ...fieldGlass({ margin: '14px 22px 40px', display: 'flex', flexDirection: 'column' }) }}>
        {guests.map(g => {
          const meta = g.qty > 1 ? (g.qty + T(' vé', ' tickets')) : T('1 vé', '1 ticket');
          // 14-organizer-checkin.md (Bugs 2a/3): check-in only makes sense
          // once payment is actually confirmed — an unpaid guest's row is
          // no longer tap-to-check-in at all (it used to be, regardless of
          // payment state, which is what made "đã đến chưa" reachable on a
          // guest whose payment hadn't even been reviewed yet).
          const rowClickable = g.paid;
          return (
            <div key={g.id} onClick={rowClickable ? () => toggleCheckin(g.id, g.checkedIn) : undefined}
                 style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '13px 16px', borderBottom: `1px solid ${rule}`, cursor: rowClickable ? 'pointer' : 'default', background: g.checkedIn ? 'rgba(27,25,22,0.16)' : 'transparent' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
                <span style={{ ...display(15) }}>{g.name}</span>
                <span style={{ fontSize: 11.5, color: ink }}>{meta} ▪︎ {formatVnd(g.totalVnd)}</span>
                {g.paid ? (
                  <>
                    <span style={{ fontSize: 11, color: ink, opacity: 0.7 }} data-testid="guest-paid">
                      {T('Đã thanh toán ✓', 'Paid ✓')}
                    </span>
                    <span
                      ref={(node) => { uploadRefs.current[g.id] = node; }}
                      onClick={(e) => { e.stopPropagation(); pickReceiptFile(g.id); }}
                      style={{
                        fontSize: 11, fontWeight: 600, color: ink, width: 'fit-content',
                        cursor: uploadingFor === g.id ? 'default' : 'pointer', borderRadius: 10, padding: '4px 8px', marginTop: 2,
                        opacity: uploadingFor === g.id ? 0.6 : 1,
                        border: highlightedBookingId === g.id ? `1px solid ${alert}` : '1px solid rgba(27,25,22,0.16)',
                        boxShadow: highlightedBookingId === g.id ? `0 0 0 3px ${alert}33` : 'none',
                        transition: 'box-shadow 0.3s ease, border-color 0.3s ease',
                      }}
                      data-testid="guest-upload-receipt"
                    >
                      {uploadingFor === g.id ? T('Đang tải lên…', 'Uploading…') : T('Tải lên biên nhận', 'Upload receipt')}
                    </span>
                    {uploadErrorFor === g.id && (
                      <span style={{ fontSize: 10.5, color: alert }}>{T('Không tải lên được. Thử lại nhé.', "Couldn't upload. Please try again.")}</span>
                    )}
                  </>
                ) : (
                  <>
                    <span style={{ fontSize: 11, fontWeight: 600, color: ink, opacity: 0.8, marginTop: 2 }}>
                      {T('Có nhận khách này không?', 'Accept this guest?')}
                    </span>
                    <div style={{ display: 'flex', gap: 6, marginTop: 2 }}>
                      <span
                        onClick={(e) => { e.stopPropagation(); markGuestPaid(g.id); }}
                        style={{ fontSize: 11, fontWeight: 600, color: ink, cursor: 'pointer', border: '1px solid rgba(27,25,22,0.16)', borderRadius: 10, padding: '4px 8px' }}
                        data-testid="guest-accept"
                      >
                        {/* The screenshot the guest already sent is the
                            strongest signal there is that this is the right
                            guest to accept. */}
                        {g.hasProof ? T('Khách đã gửi biên lai ▪︎ Nhận', 'Guest sent proof ▪︎ Accept') : T('Nhận', 'Accept')}
                      </span>
                      <span
                        onClick={(e) => { e.stopPropagation(); openRejectGuest(g.id); }}
                        style={{ fontSize: 11, fontWeight: 600, color: alert, opacity: 0.8, cursor: 'pointer', border: `1px solid ${alert}33`, borderRadius: 10, padding: '4px 8px' }}
                        data-testid="guest-reject"
                      >
                        {T('Từ chối', 'Reject')}
                      </span>
                    </div>
                    {/* Same muted-alert convention already used for "Huỷ vé"
                        below — distinct from "Từ chối" (a same-color pill,
                        not harsh) but not a new color either. Only shown once
                        there's something concrete to go check — a guest who
                        hasn't even submitted proof yet has nothing to review
                        in Verifications. */}
                    {g.hasProof && (
                      <span
                        onClick={(e) => { e.stopPropagation(); openVerificationDetail(g.id, attKey); }}
                        style={{ fontSize: 11, fontWeight: 600, color: alert, opacity: 0.8, width: 'fit-content', cursor: 'pointer', marginTop: 4 }}
                        data-testid="guest-check-payment"
                      >
                        {T('Kiểm tra thanh toán ›', 'Check payment ›')}
                      </span>
                    )}
                  </>
                )}
                <span
                  onClick={(e) => { e.stopPropagation(); openCancelBooking(g.id); }}
                  style={{ fontSize: 11, color: alert, opacity: 0.8, width: 'fit-content', cursor: 'pointer', marginTop: 2 }}
                >
                  {T('Huỷ vé', 'Cancel booking')}
                </span>
              </div>
              <span style={{ fontSize: 11.5, fontWeight: 600, flex: 'none', padding: '5px 10px', color: g.checkedIn ? paper : ink, background: g.checkedIn ? ink : 'rgba(27,25,22,0.16)' }}>
                {g.checkedIn ? T('Đã đến ✓', 'Here ✓') : g.paid ? T('Chưa đến', 'Not yet') : T('Chưa thanh toán', 'Not paid yet')}
              </span>
            </div>
          );
        })}
        {guests.length === 0 && (
          <p style={{ fontSize: 12.5, color: ink, padding: '14px 16px', margin: 0 }}>{s.attendanceLoading ? T('Đang tải danh sách khách…', 'Loading guest list…') : T('Chưa có ai đặt chỗ cho sự kiện này.', 'No one has booked this event yet.')}</p>
        )}
      </div>
    </div>
  );
}

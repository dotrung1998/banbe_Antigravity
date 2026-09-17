import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { findEvent } from '../data/events.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, alert } from '../theme.js';

export default function Attendance() {
  const {
    state, set, T, trStatus, goDashboard, toggleCheckin, openQrScan, openCancelBooking, markGuestPaid, uploadPaymentDocument,
    openVerificationDetail, openRejectGuest, loadAttendanceGuests,
  } = useGoc();
  const s = state;
  const fileInputRef = useRef(null);
  const [uploadingFor, setUploadingFor] = useState(null);
  const [uploadErrorFor, setUploadErrorFor] = useState(null);
  // Replacing an existing live receipt requires a reason
  // (upload_payment_document()'s own REASON_REQUIRED gate, migration 056) —
  // pendingReplace holds the picked file until the organizer actually
  // supplies one. Only entered when the guest already hasReceipt; a first
  // upload skips straight to uploadPaymentDocument() with no reason needed,
  // matching the RPC's own condition exactly.
  const [pendingReplace, setPendingReplace] = useState(null); // { bookingId, file } | null
  const [replaceReason, setReplaceReason] = useState('');

  const UPLOAD_ERROR_MESSAGES = {
    REASON_REQUIRED: T('Cần nêu lý do khi thay thế biên nhận đã có.', 'A reason is required to replace an existing receipt.'),
    FILE_REQUIRED: T('Vui lòng chọn tệp.', 'Please choose a file.'),
    NOT_AUTHORIZED: T('Bạn không có quyền tải lên cho đơn này.', "You're not authorized to upload for this booking."),
    INVALID_PATH: T('Có lỗi khi tải tệp lên. Thử lại nhé.', 'Something went wrong uploading the file. Please try again.'),
    BOOKING_NOT_FOUND: T('Không tìm thấy đơn đặt chỗ này.', "Couldn't find that booking."),
  };
  const uploadErrorMessage = (code) => UPLOAD_ERROR_MESSAGES[code] || T('Không tải lên được. Thử lại nhé.', "Couldn't upload. Please try again.");

  // 15-organizer-checkin.md follow-up: this screen only ever reloaded on
  // mount (openAttendance) or right after the organizer's own actions
  // (accept/reject/check-in) — a guest holding a NEW slot or submitting
  // payment while the organizer already has this screen open never showed
  // up until the organizer left and reopened it. Matches this app's own
  // established polling convention elsewhere (PaymentDetails' 6s,
  // DisputeChatPanel's 4s — no realtime subscription exists anywhere in
  // this codebase, see 03-dispute-chat.md).
  useEffect(() => {
    const key = s.attendanceEventKey;
    if (!key) return undefined;
    const id = setInterval(() => loadAttendanceGuests(key), 6000);
    return () => clearInterval(id);
  }, [s.attendanceEventKey, loadAttendanceGuests]);
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
  const runUpload = async (bookingId, file, reason = '') => {
    setUploadingFor(bookingId);
    const result = await uploadPaymentDocument(bookingId, 'receipt', file, reason);
    setUploadingFor(null);
    if (!result.success) {
      setUploadErrorFor({ bookingId, code: result.error });
      return false;
    }
    setUploadErrorFor(null);
    await loadAttendanceGuests(s.attendanceEventKey);
    return true;
  };
  const onReceiptFileChosen = async (e) => {
    const file = e.target.files?.[0];
    const bookingId = fileInputRef.current.dataset.bookingId;
    e.target.value = '';
    if (!file || !bookingId) return;
    setUploadErrorFor(null);
    // Matches upload_payment_document()'s own condition exactly: a reason is
    // required only when a live document already exists for this
    // booking+kind (loadAttendanceGuests() populates hasReceipt for this).
    const guest = s.attendanceGuests.find(g => g.id === bookingId);
    if (guest?.hasReceipt) {
      setPendingReplace({ bookingId, file });
      setReplaceReason('');
      return;
    }
    await runUpload(bookingId, file);
  };
  const submitReplace = async () => {
    if (!pendingReplace) return;
    if (!replaceReason.trim()) return; // button below is disabled in this case too
    const ok = await runUpload(pendingReplace.bookingId, pendingReplace.file, replaceReason.trim());
    if (ok) { setPendingReplace(null); setReplaceReason(''); }
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
                      {uploadingFor === g.id
                        ? T('Đang tải lên…', 'Uploading…')
                        : (g.hasReceipt ? T('Thay biên nhận', 'Replace receipt') : T('Tải lên biên nhận', 'Upload receipt'))}
                    </span>
                    {/* Surfaces the 24h soft-delete window (upload_payment_document(),
                        migration 056) — only shown when there's actually something
                        pending, so the far more common single-upload case stays
                        uncluttered. */}
                    {g.receiptPendingDelete > 0 && (
                      <span style={{ fontSize: 10.5, color: ink, opacity: 0.6, marginTop: 2 }} data-testid="guest-receipt-version">
                        {T(
                          `Phiên bản hiện tại (${g.receiptVersionCount}) · ${g.receiptPendingDelete} bản cũ sẽ xoá trong 24h`,
                          `Current version (${g.receiptVersionCount}) · ${g.receiptPendingDelete} old version${g.receiptPendingDelete > 1 ? 's' : ''} will be deleted within 24h`,
                        )}
                      </span>
                    )}
                    {pendingReplace?.bookingId === g.id ? (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 4 }} onClick={(e) => e.stopPropagation()}>
                        <textarea
                          value={replaceReason}
                          onChange={(e) => setReplaceReason(e.target.value)}
                          placeholder={T('Vì sao thay thế bản cũ?', 'Why are you replacing the old one?')}
                          rows={2}
                          data-testid="guest-replace-reason"
                          style={{ fontSize: 11.5, padding: 8, borderRadius: 10, border: '1px solid rgba(27,25,22,0.16)', fontFamily: "'Be Vietnam Pro', sans-serif", resize: 'vertical' }}
                        />
                        <div style={{ display: 'flex', gap: 6 }}>
                          <span
                            onClick={() => { setPendingReplace(null); setReplaceReason(''); }}
                            style={{ flex: 1, fontSize: 11, textAlign: 'center', color: ink, opacity: 0.7, padding: '6px 0', cursor: 'pointer' }}
                          >
                            {T('Huỷ', 'Cancel')}
                          </span>
                          <span
                            onClick={replaceReason.trim() ? submitReplace : undefined}
                            data-testid="guest-replace-submit"
                            style={{
                              flex: 1, fontSize: 11, fontWeight: 600, textAlign: 'center', color: paper,
                              background: replaceReason.trim() ? ink : 'rgba(27,25,22,0.35)',
                              borderRadius: 10, padding: '6px 0', cursor: replaceReason.trim() ? 'pointer' : 'default',
                            }}
                          >
                            {uploadingFor === g.id ? T('Đang tải lên…', 'Uploading…') : T('Xác nhận thay thế', 'Confirm replacement')}
                          </span>
                        </div>
                      </div>
                    ) : uploadErrorFor?.bookingId === g.id && (
                      <span style={{ fontSize: 10.5, color: alert }} data-testid="guest-upload-error">{uploadErrorMessage(uploadErrorFor.code)}</span>
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

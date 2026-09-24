import { useEffect, useRef, useState } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { findEvent } from '../data/events.js';
import { formatVnd } from '../lib/paymentDocument.js';
import { liveEventOverrides } from '../lib/countdown.js';
import { formatShortDate } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton, alert } from '../theme.js';

const REFUND_STATUS_LABEL = {
  needsDestination: ['Cần tài khoản nhận tiền', 'Needs destination'],
  owed: ['Đang chờ hoàn', 'Owed'],
  host_marked_sent: ['Đã gửi ▪︎ chờ xác nhận', 'Sent ▪︎ awaiting confirmation'],
  disputed: ['Đang tranh chấp', 'Disputed'],
  guest_confirmed: ['Đã xác nhận', 'Confirmed'],
  overdue: ['Quá hạn', 'Overdue'],
};
function maskAccountNumber(number) {
  const s = String(number || '');
  if (s.length <= 4) return s;
  return '•'.repeat(Math.max(0, s.length - 4)) + s.slice(-4);
}

export default function Attendance() {
  const {
    state, set, T, trStatus, backFromAttendance, toggleCheckin, openQrScan, openCancelBooking, markGuestPaid, uploadPaymentDocument,
    openVerificationDetail, openRejectGuest, loadAttendanceGuests, openDocumentFromNotification, loadHomeLiveEvents,
    loadRefundCenter, toggleRefundCenterSelect, selectAllEligibleRefundCenter, clearRefundCenterSelection, confirmRefundBatch, resendRefundTransferInfo, markRefundSent,
  } = useGoc();
  const s = state;
  // Same documentBack-style pattern (07-notifications.md's 2026-09-18
  // follow-up): the back link's own label follows attendanceBack too, so
  // "‹ Notifications" doesn't read "‹ Your dashboard" when that's not
  // actually where the tap goes.
  const backLabel = s.attendanceBack === 'notifications' ? T('Thông báo', 'Notifications') : T('Trang của bạn', 'Your dashboard');
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

  // Refund MVP — Host Event Refund Center: review screen before the actual
  // batch confirm, and per-row "Gửi lại thông tin chuyển khoản" form.
  const [refundReviewOpen, setRefundReviewOpen] = useState(false);
  const [refundBulkConfirmed, setRefundBulkConfirmed] = useState(false);
  const [resendFormFor, setResendFormFor] = useState(null);
  const [resendReference, setResendReference] = useState('');
  const [resendBank, setResendBank] = useState('');
  const [copiedFor, setCopiedFor] = useState(null);

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
    // TASK 3 point 5 — also refresh the same batched live-status fetch
    // Home/Dashboard use (loadHomeLiveEvents) on this same poll, so a host
    // who stays on this screen while the event transitions to ended sees
    // guest controls actually disappear (see eventEnded below) rather than
    // only ever picking that up on next screen mount.
    loadHomeLiveEvents();
    loadRefundCenter(key);
    const id = setInterval(() => { loadAttendanceGuests(key); loadHomeLiveEvents(); loadRefundCenter(key); }, 6000);
    return () => clearInterval(id);
  }, [s.attendanceEventKey, loadAttendanceGuests, loadHomeLiveEvents, loadRefundCenter]);
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
        <div onClick={backFromAttendance} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {backLabel}</div>
      </div>
    );
  }

  // TASK 3 point 5 — real, live-status-derived "has this event actually
  // ended/been cancelled while the host was sitting on this screen", same
  // `liveEventOverrides` merge Dashboard/Home use, not a separate
  // calculation. When true, no actionable guest control below is reachable
  // any more — server-side RPCs would reject them anyway (BOOKING_CANNOT_
  // BE_CANCELLED, etc.) but this keeps the host from even seeing them.
  const attEvLiveOverrides = liveEventOverrides(s.homeLiveEvents[attKey], attEv);
  const attEvLive = attEvLiveOverrides ? { ...attEv, ...attEvLiveOverrides } : attEv;
  const eventEnded = !!attEvLive.cancelled || attEvLive.endedHoursAgo != null;

  if (eventEnded) {
    return (
      <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
        <div onClick={backFromAttendance} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {backLabel}</div>
        <p style={{ padding: '40px 22px', fontSize: 13, color: ink }}>{T('Sự kiện đã kết thúc.', 'This event has ended.')}</p>
      </div>
    );
  }

  // The guest list is whoever actually holds a real booking for this event
  // (GocContext's loadAttendanceGuests), not a generated placeholder list.
  const guests = s.attendanceGuests;
  const checkedCount = guests.filter(g => g.checkedIn).length;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Attendance">
      <div onClick={backFromAttendance} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {backLabel}</div>
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
      <div style={{ ...fieldGlass({ margin: '14px 22px 0', display: 'flex', flexDirection: 'column' }) }}>
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
                    {/* Was a bare count with no way to actually open either
                        file (08-payment-documents.md's 2026-09-17 follow-up
                        #7 — BUG 1) — now each version is its own tappable
                        row, opening straight into DocumentView the same way
                        Documents.jsx's own rows do. Only rendered once
                        there's more than the trivial single-current-receipt
                        case to show, keeping the far more common
                        single-upload row uncluttered — but the moment a
                        superseded copy is still live, both become visible
                        and individually openable, not just counted. */}
                    {g.receiptPendingDelete > 0 && (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 3, marginTop: 3 }}>
                        <span style={{ fontSize: 10, color: ink, opacity: 0.5 }} data-testid="guest-receipt-version">
                          {T(`Phiên bản hiện tại (${g.receiptVersionCount})`, `Current version (${g.receiptVersionCount})`)}
                        </span>
                        {g.receipts.map((r) => (
                          <span
                            key={r.id}
                            onClick={(e) => { e.stopPropagation(); openDocumentFromNotification(r.id, 'attendance', 'host'); }}
                            style={{ fontSize: 10.5, fontWeight: 600, color: r.isLive ? ink : ink, opacity: r.isLive ? 0.85 : 0.6, cursor: 'pointer', width: 'fit-content', textDecoration: 'underline', textUnderlineOffset: 2 }}
                            data-testid={r.isLive ? 'guest-receipt-current' : 'guest-receipt-old'}
                          >
                            {r.isLive ? T('Bản hiện tại ›', 'Current copy ›') : T('Bản cũ · xoá sau 24h ›', 'Old copy · deletes in 24h ›')}
                          </span>
                        ))}
                      </div>
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
                {/* TASK 3 — UX guard only (server-side BOOKING_CANNOT_BE_CANCELLED
                    stays authoritative): a checked-in booking is the one
                    client-known-ineligible state actually reachable here —
                    cancelled/expired bookings never appear in this list at
                    all (loadAttendanceGuests() only queries status IN
                    ('pending','confirmed','attended')). */}
                {!g.checkedIn && (
                  <span
                    onClick={(e) => { e.stopPropagation(); openCancelBooking(g.id); }}
                    style={{ fontSize: 11, color: alert, opacity: 0.8, width: 'fit-content', cursor: 'pointer', marginTop: 2 }}
                  >
                    {T('Huỷ vé', 'Cancel booking')}
                  </span>
                )}
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

      {/* Refund MVP — Host Event Refund Center. Only rendered once there's
          actually something to refund for this event. */}
      {s.refundCenterClaims.length > 0 && (() => {
        const claims = s.refundCenterClaims;
        const refundedClaims = claims.filter(c => c.status === 'host_marked_sent' || c.status === 'guest_confirmed');
        const totalVnd = claims.reduce((sum, c) => sum + (c.amount_vnd || 0), 0);
        const refundedVnd = refundedClaims.reduce((sum, c) => sum + (c.amount_vnd || 0), 0);
        const selected = s.refundCenterSelected;
        const selectedClaims = claims.filter(c => selected.includes(c.id));
        const selectedTotalVnd = selectedClaims.reduce((sum, c) => sum + (c.amount_vnd || 0), 0);
        const eligibleCount = claims.filter(c => c.eligible).length;
        const statusKey = (c) => (c.overdue ? 'overdue' : c.needsDestination ? 'needsDestination' : c.status);

        return (
          <div style={{ margin: '22px 22px 40px', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Trung tâm hoàn tiền', 'Refund Center')}</span>
              <span style={{ fontSize: 10.5, color: ink, opacity: 0.7 }}>
                {T(`${refundedClaims.length}/${claims.length} đã gửi ▪︎ ${formatVnd(refundedVnd)} / ${formatVnd(totalVnd)}`,
                   `${refundedClaims.length}/${claims.length} sent ▪︎ ${formatVnd(refundedVnd)} / ${formatVnd(totalVnd)}`)}
              </span>
            </div>

            {!refundReviewOpen && (
              <>
                <div style={{ display: 'flex', gap: 8 }}>
                  <span
                    onClick={() => (selected.length === eligibleCount ? clearRefundCenterSelection() : selectAllEligibleRefundCenter())}
                    style={{ fontSize: 11.5, color: ink, textDecoration: 'underline', cursor: eligibleCount ? 'pointer' : 'default', opacity: eligibleCount ? 1 : 0.4 }}
                  >
                    {selected.length === eligibleCount && eligibleCount > 0 ? T('Bỏ chọn tất cả', 'Deselect all') : T('Chọn tất cả', 'Select all eligible')}
                  </span>
                </div>

                <div style={{ ...fieldGlass({ display: 'flex', flexDirection: 'column' }) }}>
                  {claims.map(c => {
                    const label = REFUND_STATUS_LABEL[statusKey(c)] || REFUND_STATUS_LABEL[c.status] || ['—', '—'];
                    return (
                      <div key={c.id} style={{ padding: '12px 14px', borderBottom: `1px solid ${rule}`, display: 'flex', flexDirection: 'column', gap: 6 }} data-testid="refund-center-row">
                        <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
                          <input
                            type="checkbox"
                            checked={selected.includes(c.id)}
                            disabled={!c.eligible}
                            onChange={() => toggleRefundCenterSelect(c.id)}
                            style={{ marginTop: 3 }}
                            data-testid="refund-center-checkbox"
                          />
                          <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 2 }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8 }}>
                              <span style={{ ...display(14) }}>{c.guestName}</span>
                              <span style={{ fontSize: 13, fontWeight: 600, color: ink, whiteSpace: 'nowrap' }}>{formatVnd(c.amount_vnd)}</span>
                            </div>
                            {c.destination ? (
                              <span style={{ fontSize: 11, color: ink, opacity: 0.7 }}>
                                {c.destination.bank_name} ▪︎ {maskAccountNumber(c.destination.account_number)} ▪︎ {c.destination.account_holder_name}
                              </span>
                            ) : (
                              <span style={{ fontSize: 11, color: alert }}>{T('Khách chưa cung cấp tài khoản nhận hoàn tiền.', "The guest hasn't provided a refund destination yet.")}</span>
                            )}
                            {c.transfer_reference && <span style={{ fontSize: 10.5, color: ink, opacity: 0.6 }}>REF {c.transfer_reference}</span>}
                            <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 2 }}>
                              <span style={{ fontSize: 10.5, fontWeight: 600, color: c.overdue ? alert : ink, opacity: c.overdue ? 1 : 0.7 }}>{T(...label)}</span>
                              {c.destination && (
                                <span
                                  onClick={async () => {
                                    try {
                                      await navigator.clipboard.writeText(`${c.destination.bank_name} - ${c.destination.account_number} - ${c.destination.account_holder_name}${c.transfer_reference ? ' - REF ' + c.transfer_reference : ''}`);
                                      setCopiedFor(c.id);
                                      setTimeout(() => setCopiedFor(cur => (cur === c.id ? null : cur)), 1500);
                                    } catch { /* clipboard unavailable — no-op */ }
                                  }}
                                  style={{ fontSize: 10.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
                                  data-testid="refund-center-copy"
                                >
                                  {copiedFor === c.id ? T('Đã sao chép', 'Copied') : T('Sao chép', 'Copy')}
                                </span>
                              )}
                              {c.status === 'disputed' && (
                                <span
                                  onClick={() => { setResendFormFor(resendFormFor === c.id ? null : c.id); setResendReference(''); setResendBank(''); }}
                                  style={{ fontSize: 10.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
                                >
                                  {T('Gửi lại thông tin chuyển khoản', 'Resend transfer info')}
                                </span>
                              )}
                              {c.status === 'disputed' && (
                                <span
                                  onClick={() => s.refundActionBusy !== c.id && markRefundSent(c.id, T('Hoàn lại lần nữa', 'Sent again'))}
                                  style={{ fontSize: 10.5, color: ink, textDecoration: 'underline', cursor: 'pointer' }}
                                >
                                  {T('Hoàn lại lần nữa', 'Send again')}
                                </span>
                              )}
                            </div>
                            {resendFormFor === c.id && (
                              <div style={{ marginTop: 6, display: 'flex', flexDirection: 'column', gap: 6 }}>
                                <input
                                  value={resendBank} onChange={(e) => setResendBank(e.target.value)}
                                  placeholder={T('Ngân hàng', 'Bank')}
                                  style={{ ...fieldGlass({ padding: '9px 10px', border: 'none' }), fontSize: 12, color: ink, outline: 'none', fontFamily: 'inherit' }}
                                />
                                <input
                                  value={resendReference} onChange={(e) => setResendReference(e.target.value)}
                                  placeholder={T('Mã tham chiếu', 'Reference')}
                                  style={{ ...fieldGlass({ padding: '9px 10px', border: 'none' }), fontSize: 12, color: ink, outline: 'none', fontFamily: 'inherit' }}
                                />
                                <div
                                  onClick={async () => {
                                    const ok = await resendRefundTransferInfo(attKey, c.id, { reference: resendReference, bankName: resendBank, transferredAt: new Date().toISOString() });
                                    if (ok) { setResendFormFor(null); }
                                  }}
                                  style={{ ...inkButton({ borderRadius: 10, padding: 10, fontSize: 12, textAlign: 'center' }) }}
                                >
                                  {s.refundResendBusy === c.id ? T('Đang gửi…', 'Sending…') : T('Gửi', 'Send')}
                                </div>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>

                <div
                  onClick={() => { if (selected.length) { setRefundBulkConfirmed(false); setRefundReviewOpen(true); } }}
                  style={{ ...inkButton({ borderRadius: 12, padding: 13, fontSize: 13, textAlign: 'center', opacity: selected.length ? 1 : 0.4 }) }}
                  data-testid="refund-center-review"
                >
                  {selected.length
                    ? T(`Xem lại ${selected.length} khoản hoàn (${formatVnd(selectedTotalVnd)})`, `Review ${selected.length} refunds (${formatVnd(selectedTotalVnd)})`)
                    : T('Chọn ít nhất một khoản để hoàn tiền', 'Select at least one refund')}
                </div>
              </>
            )}

            {refundReviewOpen && (
              <div style={{ ...cardGlass({ padding: '16px 18px', display: 'flex', flexDirection: 'column', gap: 12 }) }} data-testid="refund-center-review-panel">
                <span style={{ ...display(16) }}>{T('Xác nhận đã chuyển tiền', 'Confirm transfers sent')}</span>
                <p style={{ fontSize: 12.5, color: ink, margin: 0 }}>
                  {T(`${selectedClaims.length} khách ▪︎ tổng ${formatVnd(selectedTotalVnd)}`, `${selectedClaims.length} guests ▪︎ total ${formatVnd(selectedTotalVnd)}`)}
                </p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 4, maxHeight: 160, overflowY: 'auto' }}>
                  {selectedClaims.map(c => (
                    <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, color: ink }}>
                      <span>{c.guestName}</span>
                      <span>{formatVnd(c.amount_vnd)}</span>
                    </div>
                  ))}
                </div>
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: ink, cursor: 'pointer' }}>
                  <input type="checkbox" checked={refundBulkConfirmed} onChange={(e) => setRefundBulkConfirmed(e.target.checked)} data-testid="refund-center-bulk-checkbox" />
                  {T(`Tôi xác nhận đã chuyển tổng ${formatVnd(selectedTotalVnd)} cho ${selectedClaims.length} khách.`,
                     `I confirm I've transferred a total of ${formatVnd(selectedTotalVnd)} to ${selectedClaims.length} guests.`)}
                </label>
                {s.refundBatchError && <p style={{ fontSize: 12, color: alert, margin: 0 }}>{s.refundBatchError}</p>}
                {s.refundBatchResult?.skipped_count > 0 && (
                  <p style={{ fontSize: 12, color: alert, margin: 0 }}>
                    {T(`${s.refundBatchResult.skipped_count} khoản đã bị bỏ qua vì không còn đủ điều kiện.`, `${s.refundBatchResult.skipped_count} refund(s) were skipped — no longer eligible.`)}
                  </p>
                )}
                <div style={{ display: 'flex', gap: 10 }}>
                  <div
                    onClick={() => setRefundReviewOpen(false)}
                    style={{ flex: 1, textAlign: 'center', padding: 12, borderRadius: 12, border: `1px solid ${rule}`, fontSize: 13, color: ink, cursor: 'pointer' }}
                  >
                    {T('Quay lại', 'Back')}
                  </div>
                  <div
                    onClick={async () => {
                      if (!refundBulkConfirmed || s.refundBatchBusy) return;
                      const result = await confirmRefundBatch(attKey, '');
                      if (result) { setRefundReviewOpen(false); setRefundBulkConfirmed(false); }
                    }}
                    style={{ ...inkButton({ flex: 1, borderRadius: 12, padding: 12, fontSize: 13, opacity: (!refundBulkConfirmed || s.refundBatchBusy) ? 0.5 : 1 }) }}
                    data-testid="refund-center-confirm"
                  >
                    {s.refundBatchBusy ? T('Đang xử lý…', 'Processing…') : T('Xác nhận đã chuyển tiền', 'Confirm transfers sent')}
                  </div>
                </div>
              </div>
            )}
          </div>
        );
      })()}
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton } from '../theme.js';

// The buyer's side of the two-phase machine.
//
// PHASE 1 ('holding')              — a running countdown, a scannable VietQR
//                                    with the exact amount and reference
//                                    baked in, and the "I have transferred"
//                                    form.
// PHASE 2 ('pending_verification') — NO countdown. The most important thing
//                                    this screen communicates is that the
//                                    clock has stopped and the seat is safe,
//                                    because a buyer who still sees a timer
//                                    after paying will assume they are about
//                                    to lose the seat they just paid for.
export default function PaymentDetails() {
  const {
    state, T, loadPaymentBookings, backFromPaymentDetails,
    copyPayField, submitPaymentProof, paymentTxnType, vietQrFor,
    openBilling, openDocuments, forfeitExpiredHold,
  } = useGoc();
  const s = state;
  const fileRef = useRef(null);
  const [file, setFile] = useState(null);
  const [tick, setTick] = useState(Date.now());

  useEffect(() => { loadPaymentBookings(); }, [loadPaymentBookings]);

  const booking = s.paymentBookings.find(b => b.id === s.paymentBookingId) || null;
  const phase = booking?.payment_state || 'holding';
  const isHolding = phase === 'holding';
  const isPending = phase === 'pending_verification';
  const isConfirmed = phase === 'confirmed';
  const isDisputed = phase === 'disputed';
  const isExpired = phase === 'expired';

  // The countdown ticks only in PHASE 1. Running it in PHASE 2 would be
  // actively misleading, and running it always would spin the CPU forever.
  useEffect(() => {
    if (!isHolding) return undefined;
    const id = setInterval(() => setTick(Date.now()), 1000);
    return () => clearInterval(id);
  }, [isHolding]);

  const msLeft = booking?.hold_expires_at
    ? Math.max(0, new Date(booking.hold_expires_at).getTime() - tick) : 0;
  const mm = String(Math.floor(msLeft / 60000)).padStart(2, '0');
  const ss = String(Math.floor((msLeft % 60000) / 1000)).padStart(2, '0');

  // The moment this screen's own ticking clock notices the hold has lapsed,
  // forfeit it immediately — self-guards against firing twice, since the
  // local patch flips booking.payment_state to 'expired' on the very next
  // render, and isHolding follows straight from that.
  useEffect(() => {
    if (isHolding && !!booking?.hold_expires_at && msLeft === 0) {
      forfeitExpiredHold(booking);
    }
  }, [isHolding, booking, msLeft, forfeitExpiredHold]);

  if (!booking) {
    return (
      <Frame onBack={backFromPaymentDetails} T={T}>
        <p style={{ fontSize: 13, color: ink, margin: '18px 22px 0', lineHeight: 1.55 }}>
          {s.paymentsLoading ? T('Đang tải…', 'Loading…') : T('Không tìm thấy khoản thanh toán này.', "Couldn't find that payment.")}
        </p>
      </Frame>
    );
  }

  const org = booking.events?.organizers || null;
  const qrPayload = vietQrFor(booking);
  const reference = booking.payment_ref || booking.code || '';
  const canSubmit = !!file && s.paymentTxnId.trim().length > 0 && !s.paymentSubmitting;

  const rows = [
    org?.bank_name && [T('Ngân hàng', 'Bank'), org.bank_name, 'bank_name'],
    org?.bank_account_no && [T('Số tài khoản', 'Account number'), org.bank_account_no, 'bank_no'],
    org?.bank_account_name && [T('Chủ tài khoản', 'Account name'), org.bank_account_name, 'holder'],
    org?.momo_phone && ['MoMo', org.momo_phone, 'momo'],
  ].filter(Boolean);

  return (
    <Frame onBack={backFromPaymentDetails} T={T}>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>
          {isConfirmed ? T('Đã thanh toán', 'Paid')
            : isPending ? T('Đang chờ xác nhận', 'Awaiting confirmation')
            : isDisputed ? T('Đang được xem xét', 'Under review')
            : isExpired ? T('Đã hết hạn giữ chỗ', 'Hold expired')
            : T('Thanh toán', 'Payment')}
        </h1>
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '6px 0 0' }}>{booking.events?.name}</p>
      </div>

      {/* PHASE 1: the clock is running. */}
      {isHolding && (
        <div style={{ ...cardGlass({ margin: '16px 22px 0', padding: '16px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 14 }) }} data-testid="payment-countdown">
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0 }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Giữ chỗ còn', 'Seat held for')}</span>
            <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>
              {T('Chuyển khoản rồi bấm "Tôi đã chuyển khoản" trước khi hết giờ.',
                 'Transfer, then tap "I have transferred" before this runs out.')}
            </span>
          </div>
          <span style={{ ...display(30, { fontVariantNumeric: 'tabular-nums' }) }}>{mm}:{ss}</span>
        </div>
      )}

      {/* PHASE 2: the clock is GONE, and the screen says so in as many words. */}
      {isPending && (
        <div style={{ ...cardGlass({ margin: '16px 22px 0', padding: '16px 18px' }) }} data-testid="payment-frozen">
          <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>
            {T('Chỗ của bạn đã được khoá ▪︎ không còn đếm ngược',
               'Your seat is locked ▪︎ the countdown has stopped')}
          </span>
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
            {T('Người tổ chức đang đối chiếu khoản chuyển khoản của bạn. Chỗ sẽ không bị huỷ trong lúc chờ.',
               'The organizer is checking your transfer against their statement. The seat will not be released while you wait.')}
          </p>
          {booking.transaction_id && (
            <p style={{ fontSize: 11.5, color: ink, opacity: 0.7, margin: '8px 0 0' }}>
              {T('Mã giao dịch đã gửi: ', 'Transaction ID submitted: ')}<strong>{booking.transaction_id}</strong>
            </p>
          )}
        </div>
      )}

      {isDisputed && (
        <div style={{ ...cardGlass({ margin: '16px 22px 0', padding: '16px 18px' }) }} data-testid="payment-disputed">
          <span style={{ fontSize: 13.5, fontWeight: 600, color: ink }}>
            {T('banbe đang xem xét', 'banbe is reviewing this')}
          </span>
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
            {T('Người tổ chức chưa đối chiếu được khoản này. Chỗ của bạn vẫn được giữ trong lúc banbe xem xét — bằng chứng bạn đã gửi được lưu lại.',
               "The organizer couldn't match this against their statement. Your seat stays held while banbe reviews it — the evidence you submitted is on file.")}
          </p>
        </div>
      )}

      <div style={{ ...cardGlass({ margin: '14px 22px 0', padding: '18px 20px' }) }}>
        <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Số tiền', 'Amount')}</span>
        <div style={{ ...display(30, { marginTop: 4 }) }} data-testid="payment-amount">{formatVnd(booking.total_vnd)}</div>
        <div style={{ fontSize: 11.5, color: ink, opacity: 0.7, marginTop: 4 }}>
          {booking.qty} {T('vé', booking.qty === 1 ? 'ticket' : 'tickets')}
        </div>
      </div>

      {isConfirmed ? (
        <div style={{ ...fieldGlass({ margin: '14px 22px 0', padding: '14px 16px' }) }}>
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: 0 }}>
            {T('Đã xác nhận. Vé và biên nhận của bạn đã sẵn sàng.', 'Confirmed. Your ticket and receipt are ready.')}
          </p>
          <div onClick={() => openDocuments('receipt', 'guest')}
               style={{ ...inkButton({ marginTop: 12, borderRadius: 14, padding: 13, fontSize: 13.5 }) }}>
            {T('Xem biên nhận', 'View receipt')}
          </div>
        </div>
      ) : (isHolding || isPending) && (
        <>
          {qrPayload && (
            <div style={{ margin: '20px 22px 0' }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Quét để chuyển khoản', 'Scan to pay')}</span>
              <div style={{ ...cardGlass({ marginTop: 10, padding: 18, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }) }}>
                <VietQr payload={qrPayload} />
                <span style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.7, textAlign: 'center' }}>
                  {T('Mở app ngân hàng, quét mã — số tiền và nội dung đã được điền sẵn.',
                     'Open your banking app and scan — the amount and reference are filled in already.')}
                </span>
              </div>
            </div>
          )}

          {rows.length > 0 && (
            <div style={{ margin: '20px 22px 0' }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Hoặc chuyển thủ công', 'Or transfer manually')}</span>
              <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
                {rows.map(([label, value, key], i) => (
                  <CopyRow key={key} label={label} value={value} T={T}
                           copied={s.paymentCopied === key} onCopy={() => copyPayField(key, value)}
                           last={i === rows.length - 1} />
                ))}
              </div>
            </div>
          )}

          <div style={{ margin: '16px 22px 0' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Nội dung chuyển khoản', 'Transfer reference')}</span>
            <div onClick={() => copyPayField('reference', reference)}
                 style={{ ...cardGlass({ marginTop: 10, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
                 data-testid="payment-reference">
              <span style={{ ...display(20, { letterSpacing: '0.14em' }) }}>{reference}</span>
              <span style={{ flex: 'none', fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.75 }}>
                {s.paymentCopied === 'reference' ? T('Đã chép', 'Copied') : T('Chép', 'Copy')}
              </span>
            </div>
            <p style={{ fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.7, margin: '8px 2px 0' }}>
              {T('Ghi đúng mã này — hệ thống đối soát tự động dựa vào nó để xác nhận ngay khi tiền tới.',
                 'Use this exact reference — automatic reconciliation uses it to confirm you the moment the money lands.')}
            </p>
          </div>

          {org?.pay_note ? (
            <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: '16px 22px 0' }}>{org.pay_note}</p>
          ) : null}

          {/* The PHASE 1 -> PHASE 2 form. Both fields are required, because a
              receipt with no transaction id is not reconcilable. */}
          {isHolding && (
            <div style={{ margin: '22px 22px 0' }}>
              <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sau khi chuyển', 'After you transfer')}</span>
              <div style={{ ...fieldGlass({ marginTop: 10, padding: '14px 16px', display: 'flex', flexDirection: 'column', gap: 12 }) }}>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
                  <label style={{ fontSize: 11.5, color: ink }}>{T('Mã giao dịch', 'Transaction ID')}</label>
                  <input
                    value={s.paymentTxnId} onChange={paymentTxnType}
                    placeholder={T('Ví dụ FT24123456789', 'e.g. FT24123456789')}
                    data-testid="payment-txn-id"
                    style={{ ...fieldGlass({ padding: '13px 14px', border: 'none' }), fontSize: 14, color: ink, outline: 'none', fontFamily: 'inherit' }}
                  />
                  <span style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.65 }}>
                    {T('Tìm trong biên lai của app ngân hàng.', 'Find it on the receipt in your banking app.')}
                  </span>
                </div>

                <input ref={fileRef} type="file" accept="image/*,application/pdf" style={{ display: 'none' }}
                       onChange={(e) => { setFile(e.target.files?.[0] || null); }} />
                <div onClick={() => fileRef.current?.click()}
                     style={{ ...fieldGlass({ padding: '13px 14px', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }) }}
                     data-testid="payment-proof-pick">
                  <span style={{ fontSize: 13.5, color: ink, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {file ? file.name : T('Chọn ảnh biên lai', 'Choose a receipt image')}
                  </span>
                  <span style={{ flex: 'none', fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.75 }}>
                    {file ? T('Đổi', 'Change') : T('Chọn', 'Choose')}
                  </span>
                </div>

                <div
                  onClick={() => canSubmit && submitPaymentProof(booking.id, file, s.paymentTxnId)}
                  style={{ ...inkButton({ borderRadius: 14, padding: 14, fontSize: 14, opacity: canSubmit ? 1 : 0.45, cursor: canSubmit ? 'pointer' : 'default' }) }}
                  data-testid="payment-submit-proof"
                >
                  {s.paymentSubmitting ? T('Đang gửi…', 'Sending…') : T('Tôi đã chuyển khoản', "I have transferred")}
                </div>
                <span style={{ fontSize: 11, lineHeight: 1.45, color: ink, opacity: 0.65 }}>
                  {T('Bấm nút này sẽ dừng đồng hồ và khoá chỗ của bạn cho tới khi người tổ chức xác nhận.',
                     'Tapping this stops the clock and locks your seat until the organizer confirms.')}
                </span>
                {s.paymentSubmitError && (
                  <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: 0 }} data-testid="payment-submit-error">
                    {s.paymentSubmitError}
                  </p>
                )}
              </div>
            </div>
          )}
        </>
      )}

      <div onClick={openBilling}
           style={{ ...fieldGlass({ margin: '20px 22px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
           data-testid="payment-billing-link">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 3, minWidth: 0, paddingRight: 12 }}>
          <span style={{ fontSize: 14, color: ink }}>{T('Thông tin xuất hoá đơn', 'Billing details')}</span>
          <span style={{ fontSize: 11.5, lineHeight: 1.45, color: ink, opacity: 0.7 }}>
            {T('Tên và địa chỉ in trên hoá đơn, biên nhận.', 'The name and address printed on your documents.')}
          </span>
        </div>
        <span style={{ fontSize: 15, color: ink, lineHeight: 1, flex: 'none' }}>›</span>
      </div>

      <p style={{ fontSize: 11.5, lineHeight: 1.6, color: ink, opacity: 0.65, margin: '20px 22px 40px' }}>
        {T('banbe không thu tiền và không giữ tiền. Bạn chuyển trực tiếp cho người tổ chức; nếu họ hủy, họ có trách nhiệm hoàn tiền cho bạn.',
           'banbe does not collect or hold money. You pay the organizer directly; if they cancel, they are responsible for refunding you.')}
      </p>
    </Frame>
  );
}

// Fixed black-on-white, like the ticket QR: a banking app's camera does not
// know about the app's palette and a themed QR is an unscannable QR.
function VietQr({ payload }) {
  const [src, setSrc] = useState(null);
  useEffect(() => {
    let active = true;
    QRCode.toDataURL(payload, { margin: 1, width: 460, errorCorrectionLevel: 'M',
                                color: { dark: '#000000', light: '#FFFFFF' } })
      .then(url => { if (active) setSrc(url); })
      .catch(() => {});
    return () => { active = false; };
  }, [payload]);
  return (
    <div style={{ width: 230, height: 230, background: '#FFFFFF', padding: 10, borderRadius: 12 }}>
      {src && <img src={src} alt="VietQR" data-testid="payment-vietqr" style={{ width: '100%', height: '100%', display: 'block' }} />}
    </div>
  );
}

function Frame({ children, onBack, T }) {
  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Payment">
      <div onClick={onBack} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="payment-back">
        ‹ {T('Quay lại', 'Back')}
      </div>
      {children}
    </div>
  );
}

function CopyRow({ label, value, copied, onCopy, last, T }) {
  return (
    <div onClick={onCopy}
         style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '13px 16px', borderBottom: last ? 'none' : `1px solid ${rule}`, cursor: 'pointer' }}>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2, minWidth: 0 }}>
        <span style={{ fontSize: 11, color: ink, opacity: 0.65 }}>{label}</span>
        <span style={{ fontSize: 14, fontWeight: 600, color: ink, wordBreak: 'break-all' }}>{value}</span>
      </div>
      <span style={{ flex: 'none', fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.75 }}>
        {copied ? T('Đã chép', 'Copied') : T('Chép', 'Copy')}
      </span>
    </div>
  );
}

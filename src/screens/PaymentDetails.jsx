import { useEffect, useRef } from 'react';
import { useGoc } from '../state/GocContext.jsx';
import { formatVnd } from '../lib/paymentDocument.js';
import { paper, ink, rule, display, fieldGlass, cardGlass, inkButton } from '../theme.js';

// Where a guest is told how to pay, and how they say they have.
//
// banbe is not in the middle of this transfer and this screen says so
// plainly rather than looking like a checkout — the difference matters, both
// because it is true and because a guest who thinks the app took their money
// will come to the app when something goes wrong.
export default function PaymentDetails() {
  const {
    state, T, loadPaymentBookings, backFromPaymentDetails,
    copyPayField, uploadPaymentProof, openBilling, openDocuments,
  } = useGoc();
  const s = state;
  const fileRef = useRef(null);

  useEffect(() => { loadPaymentBookings(); }, [loadPaymentBookings]);

  const booking = s.paymentBookings.find(b => b.id === s.paymentBookingId) || null;
  const ev = booking?.events || null;
  const org = ev?.organizers || null;

  if (!booking) {
    return (
      <Frame onBack={backFromPaymentDetails} T={T}>
        <p style={{ fontSize: 13, color: ink, margin: '18px 22px 0', lineHeight: 1.55 }}>
          {s.paymentsLoading
            ? T('Đang tải…', 'Loading…')
            : T('Không tìm thấy khoản thanh toán này.', "Couldn't find that payment.")}
        </p>
      </Frame>
    );
  }

  const paid = !!booking.paid_marked_at;
  const total = booking.total_vnd || 0;
  const methods = org?.pay_methods || [];
  const hasBank = methods.includes('bank') && org?.bank_account_no;
  const hasMomo = methods.includes('momo') && org?.momo_phone;
  const nothingSetUp = !hasBank && !hasMomo;

  // The transfer reference. In Vietnam this is how an organizer matches an
  // incoming transfer to a person at all — so it gets the same weight as the
  // amount, not a footnote.
  const reference = booking.code || '';

  const rows = [
    hasBank && [T('Ngân hàng', 'Bank'), org.bank_name, 'bank_name'],
    hasBank && [T('Số tài khoản', 'Account number'), org.bank_account_no, 'bank_no'],
    hasBank && [T('Chủ tài khoản', 'Account name'), org.bank_account_name, 'bank_name_holder'],
    hasMomo && [T('MoMo', 'MoMo'), org.momo_phone, 'momo'],
  ].filter(Boolean);

  return (
    <Frame onBack={backFromPaymentDetails} T={T}>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>
          {paid ? T('Đã thanh toán', 'Paid') : T('Thanh toán', 'Payment')}
        </h1>
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '6px 0 0', lineHeight: 1.5 }}>{ev?.name}</p>
      </div>

      <div style={{ ...cardGlass({ margin: '18px 22px 0', padding: '18px 20px' }) }}>
        <span style={{ fontSize: 11.5, color: ink, opacity: 0.7 }}>{T('Số tiền', 'Amount')}</span>
        <div style={{ ...display(30, { marginTop: 4 }) }} data-testid="payment-amount">{formatVnd(total)}</div>
        <div style={{ fontSize: 11.5, color: ink, opacity: 0.7, marginTop: 4 }}>
          {booking.qty} {T('vé', booking.qty === 1 ? 'ticket' : 'tickets')}
        </div>
      </div>

      {paid ? (
        <div style={{ ...fieldGlass({ margin: '14px 22px 0', padding: '14px 16px' }) }} data-testid="payment-paid-note">
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: 0 }}>
            {T('Người tổ chức đã xác nhận nhận được tiền. Biên nhận của bạn đã sẵn sàng.',
               'The organizer confirmed the money arrived. Your receipt is ready.')}
          </p>
          <div
            onClick={() => openDocuments('receipt', 'guest')}
            style={{ ...inkButton({ marginTop: 12, borderRadius: 14, padding: 13, fontSize: 13.5 }) }}
          >
            {T('Xem biên nhận', 'View receipt')}
          </div>
        </div>
      ) : nothingSetUp ? (
        <div style={{ ...fieldGlass({ margin: '14px 22px 0', padding: '14px 16px' }) }} data-testid="payment-no-details">
          <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: 0 }}>
            {T('Người tổ chức chưa thêm thông tin nhận tiền. Nhắn cho họ trong phần Tin nhắn để hỏi cách chuyển khoản.',
               "The organizer hasn't added payment details yet. Message them to ask how to transfer.")}
          </p>
        </div>
      ) : (
        <>
          <div style={{ margin: '20px 22px 0' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Chuyển khoản tới', 'Transfer to')}</span>
            <div style={{ ...fieldGlass({ marginTop: 10, display: 'flex', flexDirection: 'column' }) }}>
              {rows.map(([label, value, key], i) => (
                <CopyRow
                  key={key} label={label} value={value}
                  copied={s.paymentCopied === key}
                  onCopy={() => copyPayField(key, value)}
                  last={i === rows.length - 1}
                  T={T}
                />
              ))}
            </div>
          </div>

          <div style={{ margin: '16px 22px 0' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Nội dung chuyển khoản', 'Transfer reference')}</span>
            <div
              onClick={() => copyPayField('reference', reference)}
              style={{ ...cardGlass({ marginTop: 10, padding: '14px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, cursor: 'pointer' }) }}
              data-testid="payment-reference"
            >
              <span style={{ ...display(20, { letterSpacing: '0.14em' }) }}>{reference}</span>
              <span style={{ flex: 'none', fontSize: 11.5, fontWeight: 600, color: ink, opacity: 0.75 }}>
                {s.paymentCopied === 'reference' ? T('Đã chép', 'Copied') : T('Chép', 'Copy')}
              </span>
            </div>
            <p style={{ fontSize: 11.5, lineHeight: 1.55, color: ink, opacity: 0.7, margin: '8px 2px 0' }}>
              {T('Ghi đúng mã này khi chuyển khoản — người tổ chức dựa vào nó để biết ai đã trả.',
                 'Use this exact reference — it is how the organizer knows the transfer is yours.')}
            </p>
          </div>

          {org?.pay_note ? (
            <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: '16px 22px 0' }}>{org.pay_note}</p>
          ) : null}

          <div style={{ margin: '22px 22px 0' }}>
            <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Sau khi chuyển', 'After you transfer')}</span>
            <div style={{ ...fieldGlass({ marginTop: 10, padding: '14px 16px' }) }}>
              {booking.proof_uploaded_at ? (
                <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: 0 }} data-testid="payment-proof-sent">
                  {T('Đã gửi xác nhận. Người tổ chức sẽ kiểm tra và đánh dấu đã thanh toán.',
                     'Confirmation sent. The organizer will check and mark it paid.')}
                </p>
              ) : (
                <p style={{ fontSize: 13, lineHeight: 1.55, color: ink, margin: 0 }}>
                  {T('Gửi ảnh chụp biên lai để người tổ chức xác nhận nhanh hơn.',
                     'Send a screenshot of your transfer so the organizer can confirm faster.')}
                </p>
              )}
              <input
                ref={fileRef} type="file" accept="image/*,application/pdf" style={{ display: 'none' }}
                onChange={(e) => {
                  const file = e.target.files?.[0];
                  if (file) uploadPaymentProof(booking.id, file);
                  e.target.value = '';
                }}
              />
              <div
                onClick={() => !s.paymentProofUploading && fileRef.current?.click()}
                style={{ ...inkButton({ marginTop: 12, borderRadius: 14, padding: 13, fontSize: 13.5, opacity: s.paymentProofUploading ? 0.6 : 1 }) }}
                data-testid="payment-proof-upload"
              >
                {s.paymentProofUploading
                  ? T('Đang gửi…', 'Sending…')
                  : booking.proof_uploaded_at
                    ? T('Gửi ảnh khác', 'Send another')
                    : T('Tôi đã chuyển khoản', "I've transferred")}
              </div>
              {s.paymentProofError && (
                <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '10px 0 0' }}>{s.paymentProofError}</p>
              )}
            </div>
          </div>
        </>
      )}

      <div
        onClick={openBilling}
        style={{ ...fieldGlass({ margin: '20px 22px 0', padding: '15px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }) }}
        data-testid="payment-billing-link"
      >
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
    <div
      onClick={onCopy}
      style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, padding: '13px 16px', borderBottom: last ? 'none' : `1px solid ${rule}`, cursor: 'pointer' }}
    >
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

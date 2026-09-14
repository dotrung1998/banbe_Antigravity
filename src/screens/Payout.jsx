import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, FACE, display, fieldGlass, inkButton, alert } from '../theme.js';

// Where the organizer says how they want to be paid. Without this filled in,
// a guest's payment screen has nothing to show them — so this is the one
// hosting setting that actually blocks money moving.
export default function Payout() {
  const { state, T, backFromDocuments, payoutField, savePayoutDetails } = useGoc();
  const s = state;

  // Either rail is enough. save_organizer_payment() derives pay_methods from
  // whichever fields are non-empty, so a half-filled bank block can never
  // advertise itself to a guest.
  const canSave = (s.payoutAccountNo.trim() || s.payoutMomo.trim()) && !s.payoutSaving;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Payout">
      <div onClick={backFromDocuments} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>
        ‹ {T('Tài khoản', 'Account')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>{T('Nhận thanh toán', 'Getting paid')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Khách chuyển khoản thẳng cho bạn. banbe không giữ tiền và không thu phí.',
             'Guests transfer straight to you. banbe never holds the money and takes no cut.')}
        </p>
      </div>

      <div style={{ margin: '20px 22px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Ngân hàng', 'Bank')}</span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 10 }}>
          <Field label={T('Tên ngân hàng', 'Bank name')} value={s.payoutBankName} onChange={payoutField('payoutBankName')} placeholder="Vietcombank" testid="payout-bank" />
          <Field label={T('Số tài khoản', 'Account number')} value={s.payoutAccountNo} onChange={payoutField('payoutAccountNo')} placeholder="0071000…" testid="payout-account-no" />
          <Field label={T('Chủ tài khoản', 'Account name')} value={s.payoutAccountName} onChange={payoutField('payoutAccountName')} placeholder="NGUYEN VAN A" testid="payout-account-name" />
        </div>
      </div>

      <div style={{ margin: '20px 22px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Ví MoMo', 'MoMo wallet')}</span>
        <div style={{ marginTop: 10 }}>
          <Field label={T('Số điện thoại MoMo', 'MoMo phone')} value={s.payoutMomo} onChange={payoutField('payoutMomo')} placeholder="09xx xxx xxx" testid="payout-momo" />
        </div>
      </div>

      <div style={{ margin: '20px 22px 0' }}>
        <span style={{ fontSize: 11.5, fontWeight: 600, color: ink }}>{T('Trên chứng từ', 'On your documents')}</span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 10 }}>
          <Field label={T('Địa chỉ', 'Address')} value={s.payoutAddress} onChange={payoutField('payoutAddress')}
                 placeholder={T('Số nhà, đường, phường, quận, thành phố', 'Street, ward, district, city')} testid="payout-address" multiline />
          <Field label={T('Mã số thuế (nếu có)', 'Tax code (optional)')} value={s.payoutTaxCode} onChange={payoutField('payoutTaxCode')}
                 placeholder={T('Dành cho hộ kinh doanh, công ty', 'For registered businesses')} testid="payout-tax" />
          <Field label={T('Ghi chú cho khách', 'Note to guests')} value={s.payoutNote} onChange={payoutField('payoutNote')}
                 placeholder={T('Ví dụ: chuyển trước 24h để giữ chỗ', 'e.g. transfer 24h ahead to keep your seat')} testid="payout-note" multiline />
        </div>
      </div>

      <div
        onClick={() => canSave && savePayoutDetails()}
        style={{ ...inkButton({ margin: '20px 22px 0', borderRadius: 18, padding: 15, fontSize: 14.5, opacity: canSave ? 1 : 0.45, cursor: canSave ? 'pointer' : 'default' }) }}
        data-testid="payout-save"
      >
        {s.payoutSaving ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
      </div>

      {s.payoutSaved && (
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '12px 22px 0' }} data-testid="payout-saved">
          {T('Đã lưu. Khách sẽ thấy thông tin này khi thanh toán.', 'Saved. Guests will see this when they pay.')}
        </p>
      )}
      {s.payoutError && (
        <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '12px 22px 0' }}>{s.payoutError}</p>
      )}

      <div style={{ height: 40 }} />
    </div>
  );
}

function Field({ label, value, onChange, placeholder, testid, multiline }) {
  const style = {
    ...fieldGlass({ padding: '13px 14px', border: 'none' }),
    fontSize: 14, fontFamily: FACE, color: ink, outline: 'none', resize: 'none',
  };
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
      <label style={{ fontSize: 11.5, color: ink }}>{label}</label>
      {multiline
        ? <textarea rows={2} value={value} onChange={onChange} placeholder={placeholder} style={style} data-testid={testid} />
        : <input value={value} onChange={onChange} placeholder={placeholder} style={style} data-testid={testid} />}
    </div>
  );
}

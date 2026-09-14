import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, FACE, display, fieldGlass, inkButton, alert } from '../theme.js';

// The buyer block on every invoice and receipt this account is ever issued.
// Kept apart from "Rename" on purpose: what you are called in the app and
// what belongs on a document are frequently not the same thing — the second
// one is often a company.
export default function Billing() {
  const {
    state, T, backFromBilling,
    billingNameType, billingAddressType, billingPhoneType, billingTaxCodeType, saveBillingDetails,
  } = useGoc();
  const s = state;

  // An address is what a document actually needs and the one field a person
  // is most likely to skip, so it — not the name — gates saving.
  const canSave = s.billingName.trim().length > 0 && s.billingAddress.trim().length > 0 && !s.billingSaving;

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Billing">
      <div onClick={backFromBilling} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>
        ‹ {T('Quay lại', 'Back')}
      </div>
      <div style={{ padding: '14px 22px 0' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }}>{T('Thông tin xuất hoá đơn', 'Billing details')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Được in vào phần "Bên mua" trên hoá đơn và biên nhận của bạn.',
             'Printed in the "Buyer" block of your invoices and receipts.')}
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, margin: '20px 22px 0' }}>
        <Field label={T('Tên người mua', 'Buyer name')} value={s.billingName} onChange={billingNameType}
               placeholder={T('Cá nhân hoặc công ty', 'Person or company')} testid="billing-name" />
        <Field label={T('Địa chỉ', 'Address')} value={s.billingAddress} onChange={billingAddressType}
               placeholder={T('Số nhà, đường, phường, quận, thành phố', 'Street, ward, district, city')} testid="billing-address" multiline />
        <Field label={T('Điện thoại', 'Phone')} value={s.billingPhone} onChange={billingPhoneType}
               placeholder="09xx xxx xxx" testid="billing-phone" />
        <Field label={T('Mã số thuế (nếu có)', 'Tax code (optional)')} value={s.billingTaxCode} onChange={billingTaxCodeType}
               placeholder={T('Dành cho công ty', 'For companies')} testid="billing-tax" />
      </div>

      <div
        onClick={() => canSave && saveBillingDetails()}
        style={{ ...inkButton({ margin: '20px 22px 0', borderRadius: 18, padding: 15, fontSize: 14.5, opacity: canSave ? 1 : 0.45, cursor: canSave ? 'pointer' : 'default' }) }}
        data-testid="billing-save"
      >
        {s.billingSaving ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
      </div>

      {s.billingSaved && (
        <p style={{ fontSize: 12.5, color: ink, opacity: 0.75, margin: '12px 22px 0' }} data-testid="billing-saved">
          {T('Đã lưu.', 'Saved.')}
        </p>
      )}
      {s.billingError && (
        <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '12px 22px 0' }}>{s.billingError}</p>
      )}

      <p style={{ fontSize: 11.5, lineHeight: 1.6, color: ink, opacity: 0.65, margin: '20px 22px 40px' }}>
        {T('Thay đổi ở đây chỉ áp dụng cho chứng từ phát hành sau đó. Hoá đơn đã thanh toán giữ nguyên thông tin lúc phát hành.',
           'Changes apply to documents issued afterwards. Anything already paid keeps the details it was issued with.')}
      </p>
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

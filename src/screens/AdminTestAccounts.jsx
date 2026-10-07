import { useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';

// Admin > Test accounts (migration 159). Pick an existing account by email,
// store its contact phone in profiles.phone, grant/revoke the server-side
// "no SMS OTP" TEST exemption and, if it has none, seed a date of birth.
// All authority is enforced by the two admin_* RPCs (profiles.role = 'admin'
// checked server-side); this screen only calls them. The phone is NEVER marked
// verified and no SMS is sent. An existing DOB is never changed. The DOB is
// write-only here: the server never returns it.
const ERRORS = {
  NOT_AUTHORIZED: ['Bạn không có quyền.', 'You are not allowed to do this.'],
  USER_NOT_FOUND: ['Không tìm thấy tài khoản với email này.', 'No account with that email.'],
  INVALID_TARGET: ['Không thể áp dụng cho chính bạn.', "You can't change your own account here."],
  INVALID_PHONE: ['Số điện thoại phải theo định dạng quốc tế, ví dụ +4917656035288.', 'Phone must be international format, e.g. +4917656035288.'],
  PHONE_IN_USE: ['Số này đã gắn với tài khoản khác.', 'That number already belongs to another account.'],
  INVALID_DOB: ['Ngày sinh không hợp lệ.', 'Invalid date of birth.'],
  DOB_ALREADY_SET: ['Tài khoản đã có ngày sinh khác — không được ghi đè.', 'This account already has a different date of birth — it is never overwritten.'],
};

export default function AdminTestAccounts() {
  const { state: s, T, set } = useBanBe();
  const [email, setEmail] = useState('');
  const [found, setFound] = useState(null);
  const [phone, setPhone] = useState('');
  const [dob, setDob] = useState('');
  const [grant, setGrant] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState({ text: '', bad: false });

  if (s.accountType !== 'admin') return null;

  const say = (text, bad = false) => setMsg({ text, bad });
  const fail = (code) => { const e = ERRORS[code]; say(e ? T(e[0], e[1]) : T('Không thực hiện được. Thử lại.', "Couldn't do that. Try again."), true); };
  const fieldStyle = { ...fieldGlass({ marginTop: 10, padding: 14, border: 'none', width: '100%', boxSizing: 'border-box' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' };

  const lookup = async () => {
    setBusy(true); say(''); setFound(null);
    const { data, error } = await supabase.rpc('admin_phone_exempt_lookup', { p_email: email });
    setBusy(false);
    if (error || !data?.success) { fail(data?.error); return; }
    setFound(data); setPhone(data.profile_phone || ''); setDob(''); setGrant(!data.grandfathered);
  };

  const save = async () => {
    setBusy(true); say('');
    const { data, error } = await supabase.rpc('admin_set_phone_exemption', {
      p_user_id: found.user_id, p_phone: phone.trim() || null, p_dob: dob || null, p_grant: grant,
    });
    setBusy(false);
    if (error || !data?.success) { fail(data?.error); return; }
    say(T('Đã lưu. Số điện thoại vẫn CHƯA được xác minh.', 'Saved. The phone number is still NOT verified.'));
    lookup();
  };

  return (
    <div style={{ animation: 'banbeIn 0.32s cubic-bezier(.22,.61,.36,1) both', minHeight: '100%', background: paper }} data-screen-label="Admin test accounts">
      <div onClick={() => set({ screen: 'accountGroup', accountGroupKey: 'adminReview' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }} data-testid="admin-test-accounts-back">
        ‹ {T('Duyệt & Kiểm Duyệt', 'Review & Moderation')}
      </div>
      <div style={{ padding: '14px 30px 42px' }}>
        <h1 style={{ ...display(24, { margin: 0 }) }} data-testid="admin-test-accounts-title">{T('Tài khoản thử nghiệm', 'Test accounts')}</h1>
        <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '8px 0 0' }}>
          {T('Miễn bước SMS cho tài khoản thử nghiệm. Số điện thoại KHÔNG được đánh dấu đã xác minh, không gửi SMS, và vẫn phải nhập/xác nhận ngày sinh.',
             'Waive the SMS step for a test account. The phone is NOT marked verified, no SMS is sent, and the date-of-birth steps still apply.')}
        </p>
        <input value={email} onChange={e => setEmail(e.target.value)} placeholder="email@example.com" autoCapitalize="none" inputMode="email" data-testid="admin-test-email" style={fieldStyle} />
        <div onClick={() => !busy && email.trim() && lookup()} style={{ ...inkButton({ marginTop: 12, borderRadius: 18, padding: 14, fontSize: 14 }), opacity: !busy && email.trim() ? 1 : 0.45, cursor: 'pointer' }} data-testid="admin-test-find">
          {T('Tìm tài khoản', 'Find account')}
        </div>

        {found && (
          <div style={{ ...fieldGlass({ marginTop: 18, padding: 16 }) }} data-testid="admin-test-card">
            <div style={{ fontSize: 14, fontWeight: 600 }}>{found.display_name || found.email}</div>
            <div style={{ fontSize: 12, opacity: 0.75, marginTop: 2 }}>{found.email} · {found.role}</div>
            <div style={{ fontSize: 12, lineHeight: 1.6, marginTop: 8 }}>
              {T('Xác minh SMS', 'SMS verified')}: {found.phone_verified ? T('Có', 'Yes') : T('Chưa', 'No')}<br />
              {T('Miễn SMS thử nghiệm', 'SMS test exemption')}: {found.test_exempt ? T('Có', 'Yes') : T('Không', 'No')}<br />
              {T('Nhóm người dùng cũ (đã miễn)', 'Legacy grandfathered')}: {found.grandfathered ? T('Có', 'Yes') : T('Không', 'No')}<br />
              {T('Đã có ngày sinh', 'Has date of birth')}: {found.has_dob ? T('Có', 'Yes') : T('Chưa', 'No')}
            </div>
            <input value={phone} onChange={e => setPhone(e.target.value)} placeholder="+4917656035288" inputMode="tel" data-testid="admin-test-phone" style={fieldStyle} />
            {!found.has_dob && (
              <>
                <div style={{ fontSize: 11.5, opacity: 0.7, marginTop: 10 }}>{T('Ngày sinh (chỉ ghi, không bao giờ ghi đè)', 'Date of birth (write-only, never overwritten)')}</div>
                <input type="date" value={dob} onChange={e => setDob(e.target.value)} data-testid="admin-test-dob" style={{ ...fieldStyle, marginTop: 4 }} />
              </>
            )}
            {!found.grandfathered && (
              <label style={{ display: 'flex', gap: 8, alignItems: 'center', fontSize: 13, marginTop: 12, cursor: 'pointer' }}>
                <input type="checkbox" checked={grant} onChange={e => setGrant(e.target.checked)} data-testid="admin-test-grant" />
                {T('Miễn SMS OTP (tài khoản thử nghiệm)', 'Waive SMS OTP (test account)')}
              </label>
            )}
            <div onClick={() => !busy && save()} style={{ ...inkButton({ marginTop: 14, borderRadius: 18, padding: 14, fontSize: 14 }), opacity: busy ? 0.45 : 1, cursor: 'pointer' }} data-testid="admin-test-save">
              {busy ? T('Đang lưu…', 'Saving…') : T('Lưu', 'Save')}
            </div>
            <p style={{ fontSize: 11.5, lineHeight: 1.5, opacity: 0.65, margin: '10px 0 0' }}>
              {T('Số chỉ lưu trong hồ sơ, không có trong Auth nên không dùng được cho tin nhắn quảng bá.', 'The number is stored on the profile only (not in Auth), so it does not enable promo texting.')}
            </p>
          </div>
        )}
        {msg.text && <p style={{ fontSize: 12.5, lineHeight: 1.55, color: msg.bad ? alert : ink, margin: '14px 0 0' }} data-testid="admin-test-msg">{msg.text}</p>}
      </div>
    </div>
  );
}

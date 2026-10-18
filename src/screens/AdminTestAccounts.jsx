import { useEffect, useState } from 'react';
import { useBanBe } from '../state/BanBeContext.jsx';
import { supabase } from '../lib/supabase.js';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';
import GlassSwitch from '../components/ui/GlassSwitch.jsx';

// Admin > Test accounts (migration 159). Pick an existing account by email,
// store its contact phone in profiles.phone, grant/revoke the server-side
// "no SMS OTP" TEST exemption and, if it has none, seed a date of birth.
// All authority is enforced by the two admin_* RPCs (profiles.role = 'admin'
// checked server-side); this screen only calls them. The phone is NEVER marked
// verified and no SMS is sent. An existing DOB is never changed. The DOB is
// write-only here: the server never returns it.
const ERRORS = {
  INVALID_VALUE: ['Giá trị không hợp lệ.', 'Invalid value.'],
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
  const [nameQuery, setNameQuery] = useState('');
  const [matches, setMatches] = useState([]);
  const [phone, setPhone] = useState('');
  const [dob, setDob] = useState('');
  const [grant, setGrant] = useState(true);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState({ text: '', bad: false });
  // Global "waive SMS for everyone" switch (migration 181). null = not loaded.
  const [bypassAll, setBypassAll] = useState(null);
  const [bypassBusy, setBypassBusy] = useState(false);
  const [confirmTo, setConfirmTo] = useState(null); // the value being confirmed, or null

  useEffect(() => {
    if (s.accountType !== 'admin') return undefined;
    let live = true;
    supabase.rpc('admin_get_phone_bypass_all').then(({ data, error }) => {
      if (live && !error && data?.success) setBypassAll(!!data.enabled);
    });
    return () => { live = false; };
  }, [s.accountType]);

  // Search by display name (migration 161): debounced, picks an account by email.
  useEffect(() => {
    const q = nameQuery.trim();
    if (s.accountType !== 'admin' || q.length < 2) { setMatches([]); return undefined; }
    let live = true;
    const t = setTimeout(async () => {
      const { data, error } = await supabase.rpc('admin_phone_exempt_search', { p_query: q });
      if (live) setMatches(!error && data?.success ? (data.results || []) : []);
    }, 300);
    return () => { live = false; clearTimeout(t); };
  }, [nameQuery, s.accountType]);

  if (s.accountType !== 'admin') return null;

  const say = (text, bad = false) => setMsg({ text, bad });
  const fail = (code) => { const e = ERRORS[code]; say(e ? T(e[0], e[1]) : T('Không thực hiện được. Thử lại.', "Couldn't do that. Try again."), true); };
  const fieldStyle = { ...fieldGlass({ marginTop: 10, padding: 14, border: 'none', width: '100%', boxSizing: 'border-box' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' };

  const applyBypass = async () => {
    const next = confirmTo;
    setBypassBusy(true); say('');
    const { data, error } = await supabase.rpc('admin_set_phone_bypass_all', { p_enabled: next });
    setBypassBusy(false); setConfirmTo(null);
    if (error || !data?.success) { fail(data?.error); return; }
    setBypassAll(!!data.enabled);
    say(data.enabled
      ? T('Đã BẬT: mọi người dùng được bỏ qua bước SMS.', 'Turned ON: every user can skip the SMS step.')
      : T('Đã TẮT: bước SMS được áp dụng lại.', 'Turned OFF: the SMS step applies again.'));
  };

  const lookup = async (target = email) => {
    setBusy(true); say(''); setFound(null);
    const { data, error } = await supabase.rpc('admin_phone_exempt_lookup', { p_email: target });
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
    await lookup(found.email);
    say(T('Đã lưu. Số điện thoại vẫn CHƯA được xác minh.', 'Saved. The phone number is still NOT verified.'));
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
        <div style={{ ...fieldGlass({ marginTop: 14, padding: '14px 16px', borderRadius: 20 }), display: 'flex', alignItems: 'center', gap: 14 }} data-testid="admin-bypass-card">
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>{T('Bỏ qua SMS cho tất cả', 'Bypass SMS for everyone')}</div>
            <div style={{ fontSize: 11.5, lineHeight: 1.5, opacity: 0.7, marginTop: 2 }}>
              {bypassAll === null ? T('Đang tải…', 'Loading…')
                : bypassAll ? T('ĐANG BẬT — không ai phải xác minh SMS.', 'ON — nobody has to verify by SMS.')
                : T('Đang tắt — người dùng phải xác minh SMS.', 'Off — users must verify by SMS.')}
            </div>
          </div>
          <GlassSwitch on={!!bypassAll} busy={bypassBusy || bypassAll === null} testId="admin-bypass-switch" onPress={() => setConfirmTo(!bypassAll)} />
        </div>
        <input value={email} onChange={e => setEmail(e.target.value)} placeholder="email@example.com" autoCapitalize="none" inputMode="email" data-testid="admin-test-email" style={fieldStyle} />
        <div onClick={() => !busy && email.trim() && lookup()} style={{ ...inkButton({ marginTop: 12, borderRadius: 18, padding: 14, fontSize: 14 }), opacity: !busy && email.trim() ? 1 : 0.45, cursor: 'pointer' }} data-testid="admin-test-find">
          {T('Tìm tài khoản', 'Find account')}
        </div>

        <input value={nameQuery} onChange={e => setNameQuery(e.target.value)} placeholder={T('Hoặc tìm theo tên hiển thị', 'Or search by display name')} data-testid="admin-test-name" style={fieldStyle} />
        {matches.length > 0 && (
          <div style={{ ...fieldGlass({ marginTop: 8, padding: 6 }) }} data-testid="admin-test-matches">
            {matches.map(m => (
              <div key={m.user_id} onClick={() => { setEmail(m.email); setNameQuery(''); setMatches([]); lookup(m.email); }}
                style={{ padding: '9px 10px', cursor: 'pointer', fontSize: 13 }} data-testid="admin-test-match">
                <b>{m.display_name || '—'}</b> <span style={{ opacity: 0.7 }}>· {m.email} · {m.role}</span>
              </div>
            ))}
          </div>
        )}

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
        {confirmTo !== null && (
          <div onClick={() => !bypassBusy && setConfirmTo(null)} data-testid="admin-bypass-confirm"
            style={{ position: 'fixed', inset: 0, zIndex: 50, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 24, background: 'rgba(27,25,22,0.32)', backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)', animation: 'banbeIn 0.25s cubic-bezier(.22,.61,.36,1) both' }}>
            <div onClick={e => e.stopPropagation()} role="alertdialog" style={{ ...fieldGlass({ padding: 22, borderRadius: 26, maxWidth: 340, width: '100%', background: 'linear-gradient(168deg, rgba(255,255,255,0.7), rgba(255,255,255,0.25)), var(--bb-card)', backdropFilter: 'blur(28px) saturate(1.7)', WebkitBackdropFilter: 'blur(28px) saturate(1.7)', boxShadow: 'inset 0 1px 1px #fff, 0 24px 60px rgba(27,25,22,0.35)' }), animation: 'banbeSheetIn 0.32s cubic-bezier(.22,.61,.36,1) both' }}>
              <div style={{ ...display(19, { margin: 0 }) }}>
                {confirmTo ? T('Bật bỏ qua SMS cho tất cả?', 'Bypass SMS for everyone?') : T('Tắt bỏ qua SMS?', 'Turn the SMS bypass off?')}
              </div>
              <p style={{ fontSize: 12.5, lineHeight: 1.55, opacity: 0.8, margin: '8px 0 0' }}>
                {confirmTo
                  ? T('Mọi người dùng trên web và iOS sẽ không phải xác minh số điện thoại bằng SMS. Ngày sinh vẫn bắt buộc.', 'Every user on web and iOS will be able to continue without SMS phone verification. Date of birth is still required.')
                  : T('Người dùng chưa xác minh sẽ phải xác minh số điện thoại bằng SMS trở lại.', 'Users who are not verified will have to verify their phone by SMS again.')}
              </p>
              <div style={{ display: 'flex', gap: 10, marginTop: 18 }}>
                <div onClick={() => !bypassBusy && setConfirmTo(null)} style={{ ...fieldGlass({ flex: 1, padding: 13, borderRadius: 16, textAlign: 'center', fontSize: 14, cursor: 'pointer' }) }} data-testid="admin-bypass-cancel">{T('Huỷ', 'Cancel')}</div>
                <div onClick={() => !bypassBusy && applyBypass()} style={{ ...inkButton({ flex: 1, padding: 13, borderRadius: 16, fontSize: 14 }), opacity: bypassBusy ? 0.5 : 1 }} data-testid="admin-bypass-ok">
                  {bypassBusy ? T('Đang lưu…', 'Saving…') : confirmTo ? T('Bật', 'Turn on') : T('Tắt', 'Turn off')}
                </div>
              </div>
            </div>
          </div>
        )}
        {msg.text && <p style={{ fontSize: 12.5, lineHeight: 1.55, color: msg.bad ? alert : ink, margin: '14px 0 0' }} data-testid="admin-test-msg">{msg.text}</p>}
      </div>
    </div>
  );
}

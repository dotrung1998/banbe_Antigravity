import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, inkButton, alert } from '../theme.js';

// Landed on only via a real Supabase "recovery" session (the emailed
// password-reset link) — see the PASSWORD_RECOVERY branch of
// onAuthStateChange in GocContext.jsx. There's no "back" here on purpose:
// this session is only good for setting a new password.
export default function ResetPassword() {
  const { state, T, newPasswordType, newPasswordConfirmType, submitNewPassword } = useGoc();
  const s = state;
  const valid = s.newPassword.length >= 8 && s.newPassword === s.newPasswordConfirm;

  const btnStyle = inkButton({
    marginTop: 14, padding: '15px 0', borderRadius: 18,
    cursor: valid && !s.resetPasswordBusy ? 'pointer' : 'default',
    ...(valid ? {} : { background: 'rgba(var(--bb-fg-rgb), 0.16)', color: ink, boxShadow: 'none', border: 'none', textShadow: 'none' }),
  });
  const fieldStyle = { width: '100%', boxSizing: 'border-box', padding: 13, borderRadius: 12, border: 'none', background: 'var(--bb-field)', fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', overflowY: 'auto', boxSizing: 'border-box', padding: '66px 26px 40px', background: paper, color: ink }} data-screen-label="ResetPassword">
      <h2 style={{ ...display(25, { lineHeight: 1.2, margin: '34px 0 0' }) }}>{T('Đặt mật khẩu mới', 'Set a new password')}</h2>
      <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>
        {T('Chọn một mật khẩu mới cho tài khoản banbe của bạn.', 'Choose a new password for your banbe account.')}
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 18 }}>
        <input value={s.newPassword} onChange={newPasswordType} type="password" placeholder={T('Mật khẩu mới', 'New password')} style={fieldStyle} />
        <input value={s.newPasswordConfirm} onChange={newPasswordConfirmType} type="password" placeholder={T('Nhập lại mật khẩu mới', 'Confirm new password')} style={fieldStyle} />
      </div>
      <div onClick={valid && !s.resetPasswordBusy ? submitNewPassword : undefined} style={btnStyle}>
        {s.resetPasswordBusy ? T('Đang lưu…', 'Saving…') : T('Lưu mật khẩu mới', 'Save new password')}
      </div>
      {s.resetPasswordError && <p style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '12px 0 0', textAlign: 'center' }}>{s.resetPasswordError}</p>}
    </div>
  );
}

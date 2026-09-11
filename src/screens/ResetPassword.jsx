import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, fieldGlass } from '../theme.js';

// Landed on only via a real Supabase "recovery" session (the emailed
// password-reset link) — see the PASSWORD_RECOVERY branch of
// onAuthStateChange in GocContext.jsx. There's no "back" here on purpose:
// this session is only good for setting a new password.
export default function ResetPassword() {
  const { state, T, newPasswordType, newPasswordConfirmType, submitNewPassword } = useGoc();
  const s = state;
  const valid = s.newPassword.length >= 8 && s.newPassword === s.newPasswordConfirm;

  const btnStyle = {
    marginTop: 14, fontSize: 15, fontWeight: 600, textAlign: 'center', padding: 15,
    cursor: valid && !s.resetPasswordBusy ? 'pointer' : 'default',
    background: valid ? ink : 'rgba(27,25,22,0.16)',
    color: valid ? paper : ink,
    transition: 'background .15s',
  };

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', display: 'flex', flexDirection: 'column', background: paper }} data-screen-label="ResetPassword">
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '0 26px' }}>
        <h2 style={{ ...display(25, { lineHeight: 1.3, margin: 0 }) }}>{T('Đặt mật khẩu mới', 'Set a new password')}</h2>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>
          {T('Chọn một mật khẩu mới cho tài khoản banbe của bạn.', 'Choose a new password for your banbe account.')}
        </p>
        <input
          value={s.newPassword} onChange={newPasswordType} type="password"
          placeholder={T('Mật khẩu mới', 'New password')}
          style={{ ...fieldGlass({ marginTop: 18, padding: 14, border: 'none' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
        />
        <input
          value={s.newPasswordConfirm} onChange={newPasswordConfirmType} type="password"
          placeholder={T('Nhập lại mật khẩu mới', 'Confirm new password')}
          style={{ ...fieldGlass({ marginTop: 10, padding: 14, border: 'none' }), fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none' }}
        />
        <div onClick={valid && !s.resetPasswordBusy ? submitNewPassword : undefined} style={btnStyle}>
          {s.resetPasswordBusy ? T('Đang lưu…', 'Saving…') : T('Lưu mật khẩu mới', 'Save new password')}
        </div>
        {s.resetPasswordError && <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '12px 0 0', textAlign: 'center' }}>{s.resetPasswordError}</p>}
      </div>
    </div>
  );
}

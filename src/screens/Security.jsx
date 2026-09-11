import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, display, fieldGlass, inkButton } from '../theme.js';

// Account > Security — this account's password. The iOS app's version of
// this screen (apps/ios/BanbeApp/Views/SecurityView.swift) also carries the
// Face ID app-lock; there's deliberately no web equivalent of that, since
// it gates a device that's already signed in rather than the account.
export default function Security() {
  const {
    state: s, T, set, securityPasswordType, securityPasswordConfirmType,
    saveSecurityPassword, sendSecurityPasswordReset,
  } = useGoc();

  const fieldStyle = {
    ...fieldGlass({ marginTop: 10, padding: 14, border: 'none', width: '100%', boxSizing: 'border-box' }),
    fontSize: 14, fontFamily: "'Be Vietnam Pro', sans-serif", color: ink, outline: 'none',
  };
  const tooShort = s.securityPassword.length > 0 && s.securityPassword.length < 8;
  const canSave = !s.securityBusy && s.securityPassword.length >= 8 && s.securityPassword === s.securityPasswordConfirm;

  return (
    <div style={{ animation: 'gocFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="Security">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: '66px 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2 }) }}>{T('Bảo mật', 'Security')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
          {T('Mật khẩu tài khoản của bạn.', 'Your account password.')}
        </p>

        {s.user ? (
          <>
            <div style={{ fontSize: 11.5, fontWeight: 600, color: ink, margin: '28px 0 0' }}>{T('Mật khẩu', 'Password')}</div>
            <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '10px 0 0' }}>
              {T(
                'Đặt mật khẩu để đăng nhập bằng email và mật khẩu, thay vì chờ mã gửi qua email mỗi lần.',
                'Set a password so you can sign in with your email and password instead of waiting for a code every time.'
              )}
            </p>

            <input
              value={s.securityPassword}
              onChange={securityPasswordType}
              type="password"
              autoComplete="new-password"
              placeholder={T('Mật khẩu mới', 'New password')}
              style={fieldStyle}
            />
            <input
              value={s.securityPasswordConfirm}
              onChange={securityPasswordConfirmType}
              onKeyDown={(e) => { if (e.key === 'Enter' && canSave) saveSecurityPassword(); }}
              type="password"
              autoComplete="new-password"
              placeholder={T('Nhập lại mật khẩu', 'Re-enter password')}
              style={fieldStyle}
            />

            {s.securityError ? (
              <p style={{ fontSize: 12, lineHeight: 1.5, color: '#9A3E2D', margin: '10px 0 0' }}>{s.securityError}</p>
            ) : s.securitySaved ? (
              <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, margin: '10px 0 0' }}>{T('Đã lưu mật khẩu mới.', 'New password saved.')}</p>
            ) : tooShort ? (
              <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '10px 0 0' }}>{T('Mật khẩu cần ít nhất 8 ký tự.', 'Passwords need at least 8 characters.')}</p>
            ) : null}

            <div
              onClick={canSave ? saveSecurityPassword : undefined}
              style={{
                ...inkButton({ marginTop: 14, borderRadius: 18, padding: 14, fontSize: 14 }),
                opacity: canSave ? 1 : 0.45,
                cursor: canSave ? 'pointer' : 'default',
              }}
            >
              {s.securityBusy ? T('Đang lưu…', 'Saving…') : T('Lưu mật khẩu', 'Save password')}
            </div>

            {s.securityResetSent ? (
              // Same message whether or not that address has an account —
              // the endpoint won't say, on purpose.
              <p style={{ fontSize: 12, lineHeight: 1.55, color: ink, margin: '16px 0 0' }}>
                {T(
                  'Đã gửi email đặt lại mật khẩu. Mở link trong email để chọn mật khẩu mới.',
                  'Password reset email sent. Open the link in it to choose a new password.'
                )}
              </p>
            ) : (
              <>
                <div onClick={sendSecurityPasswordReset} style={{ fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer', marginTop: 18 }}>
                  {T('Quên mật khẩu hiện tại?', 'Forgotten your current password?')}
                </div>
                <p style={{ fontSize: 11.5, lineHeight: 1.5, color: ink, opacity: 0.65, margin: '8px 0 0' }}>
                  {T('Chúng tôi sẽ gửi link đặt lại mật khẩu tới email của bạn.', "We'll email you a link to reset it.")}
                </p>
              </>
            )}
          </>
        ) : (
          <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.7, margin: '28px 0 0' }}>
            {T('Đăng nhập để đặt mật khẩu cho tài khoản.', 'Sign in to set a password for your account.')}
          </p>
        )}
      </div>
    </div>
  );
}

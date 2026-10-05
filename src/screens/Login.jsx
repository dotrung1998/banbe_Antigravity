import { useGoc } from '../state/GocContext.jsx';
import { paper, ink, rule, display, fieldGlass, inkButton, alert } from '../theme.js';

export default function Login() {
  const {
    state, T, set,
    loginEmailType, loginNicknameType, loginEmailKey, loginPhoneType, loginCodeType, loginEmailCodeType,
    loginPasswordType, loginPasswordConfirmType, toggleLang, pickTheme, verifyLoginCode, loginZalo, loginPhone, loginFacebook, loginGoogle, loginInstagram,
    emailValid, passwordValid, setAuthMethod, requestPasswordResetSubmit, submitCurrentForm,
    togglePolicyConsent, openPolicy,
  } = useGoc();
  const s = state;
  const isSignup = s.authMode === 'signup';
  const isPassword = s.authMethod === 'password';
  const awaitingCode = s.loginSentVia === 'email';
  const nicknameValid = !isSignup || s.loginNickname.trim().length > 0;

  // Gated on the consent checkbox below — banbe_User_Policy.md B1/B3 (PDPL
  // consent) — but only for Signup: that's the only path that creates a
  // brand-new profile with policy_accepted_at still NULL. An existing
  // account signing back in already has that column set from when it
  // signed up, so `consentOk` is trivially true on the Login tab rather
  // than asking a returning user to tick the box again. Only for the
  // initial request/submit, not the code-verify step: reaching
  // `awaitingCode` at all already required checking it once (on Signup).
  const consentOk = !isSignup || s.policyConsent;
  const valid = awaitingCode
    ? s.loginEmailCode.trim().length > 0
    : isPassword
      ? consentOk && emailValid(s.loginEmail) && nicknameValid && (isSignup
        ? passwordValid(s.loginPassword) && s.loginPassword === s.loginPasswordConfirm
        : s.loginPassword.length > 0)
      : consentOk && emailValid(s.loginEmail) && nicknameValid;

  // The submit button only exists once the address could actually be sent
  // to. An empty field isn't an error yet — it's just unfinished — so it
  // hides the button without complaining; something typed that isn't an
  // address does say so, right under the field it's about.
  const emailEntered = s.loginEmail.trim().length > 0;
  const emailFormatOk = emailValid(s.loginEmail);
  const showEmailFormatError = !awaitingCode && emailEntered && !emailFormatOk;
  // Once a code has been sent the address is already settled and this
  // button verifies the code instead, so the email check doesn't apply.
  const showSubmit = awaitingCode || emailFormatOk;

  const changeAuthMode = (authMode) => set({ authMode, reserveError: '', loginSent: false, loginSentVia: null, loginEmailCode: '', resetRequested: false });

  const submitLabel = awaitingCode
    ? T('Xác nhận', 'Verify')
    : isPassword
      ? (isSignup ? T('Tạo tài khoản', 'Create account') : T('Đăng nhập', 'Log in'))
      : (isSignup ? T('Gửi mã đăng ký', 'Send sign-up code') : T('Gửi mã đăng nhập', 'Send sign-in code'));

  const FF = "'Be Vietnam Pro', sans-serif";
  // iOS BanbeField: 14pt text, 13pt padding, radius 12, flat field fill.
  const fieldStyle = (extra) => ({ width: '100%', boxSizing: 'border-box', padding: 13, borderRadius: 12, border: 'none', background: 'var(--bb-field)', fontSize: 14, fontFamily: FF, color: ink, outline: 'none', ...extra });
  const note = (extra) => ({ fontSize: 12, lineHeight: 1.5, color: ink, margin: '12px 0 0', textAlign: 'center', ...extra });
  const oauthBtn = { width: '100%', boxSizing: 'border-box', padding: '13px 0', borderRadius: 12, background: 'var(--bb-field)', color: ink, fontSize: 14, fontWeight: 600, textAlign: 'center', cursor: 'pointer' };
  const pref = { padding: '0 12px', minHeight: 34, display: 'inline-flex', alignItems: 'center', borderRadius: 999, background: 'var(--bb-field)', border: `1px solid ${rule}`, fontSize: 13, fontWeight: 600, color: ink, cursor: 'pointer' };
  const methodTabStyle = (method) => ({
    flex: 1, textAlign: 'center', fontSize: 12, fontWeight: s.authMethod === method ? 600 : 400,
    color: ink, padding: '9px 0', cursor: 'pointer', borderRadius: 999,
    background: s.authMethod === method ? 'rgba(var(--bb-fg-rgb), 0.1)' : 'transparent',
  });
  const submitStyle = inkButton({
    marginTop: 14, padding: '15px 0', borderRadius: 18, cursor: valid ? 'pointer' : 'default',
    ...(valid ? {} : { background: 'rgba(var(--bb-fg-rgb), 0.16)', color: ink, boxShadow: 'none', border: 'none', textShadow: 'none' }),
  });
  const smallBtn = { flex: 1, padding: '10px 4px', borderRadius: 12, background: 'var(--bb-field)', color: ink, fontSize: 12, fontWeight: 500, textAlign: 'center', cursor: 'pointer' };
  const dark = s.theme === 'dark';

  return (
    <div style={{ animation: 'gocIn 0.32s cubic-bezier(.22,.61,.36,1) both', height: '100%', overflowY: 'auto', boxSizing: 'border-box', padding: '66px 26px 40px', background: paper, color: ink }} data-screen-label="Login">
      {/* Back link is hidden when login was reached by force (mandatory
          gate); the row stays so the pills keep their place. Language and
          theme pills mirror iOS LoginView's prefPill pair. */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, minHeight: 34, fontSize: 12, color: ink }}>
        {!s.authMandatory && <span onClick={() => set({ screen: s.authBackScreen })} style={{ cursor: 'pointer' }}>‹ {T('Quay lại', 'Back')}</span>}
        <span style={{ flex: 1 }} />
        <span onClick={toggleLang} data-testid="login-lang" style={pref}>{T('EN', 'VN')}</span>
        <span onClick={() => pickTheme(dark ? 'light' : 'dark')} data-testid="login-theme" style={pref}>{dark ? T('Sáng', 'Light') : T('Tối', 'Dark')}</span>
      </div>

      <div style={{ display: 'flex', gap: 16, marginTop: 24, borderBottom: `1px solid ${rule}` }}>
        {['login', 'signup'].map(mode => <span key={mode} onClick={() => changeAuthMode(mode)} style={{ fontSize: 11.5, color: ink, fontWeight: s.authMode === mode ? 600 : 400, borderBottom: s.authMode === mode ? `2px solid ${ink}` : '2px solid transparent', paddingBottom: 6, marginBottom: -1, cursor: 'pointer' }}>{mode === 'login' ? T('Đăng nhập', 'Log in') : T('Đăng ký', 'Sign up')}</span>)}
      </div>
      <h2 style={{ ...display(25, { lineHeight: 1.2, margin: '16px 0 0' }) }}>{s.authMode === 'signup' ? T('Tạo tài khoản banbe', 'Create your banbe account') : T('Chào mừng trở lại', 'Welcome back')}</h2>
      <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '12px 0 0' }}>{T('Một tài khoản cho tất cả. Muốn tổ chức sự kiện, bạn chỉ cần bật chế độ tổ chức trong Tài khoản.', 'One account for everything. To host events, just switch on organizer mode from your Account.')}</p>

      {/* Real Supabase OAuth, not gated on the consent checkbox (note 10). */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 16 }}>
        <div onClick={loginGoogle} data-testid="login-google" style={oauthBtn}>{T('Tiếp tục với Google', 'Continue with Google')}</div>
        <div onClick={loginFacebook} data-testid="login-facebook" style={oauthBtn}>{T('Tiếp tục với Facebook', 'Continue with Facebook')}</div>
      </div>

      {awaitingCode ? (
        <input value={s.loginEmailCode} onChange={loginEmailCodeType} onKeyDown={loginEmailKey} placeholder={T('Mã 8 số', '8-digit code')} inputMode="numeric" autoFocus style={{ ...fieldStyle({ marginTop: 22 }), letterSpacing: '0.2em', textAlign: 'center', fontSize: 20 }} />
      ) : (
        <>
          <div style={{ display: 'flex', padding: 3, marginTop: 20, borderRadius: 999, background: 'var(--bb-field)' }}>
            <div onClick={() => setAuthMethod('code')} style={methodTabStyle('code')}>{T('Mã qua email', 'Email code')}</div>
            <div onClick={() => setAuthMethod('password')} style={methodTabStyle('password')}>{T('Mật khẩu', 'Password')}</div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12, marginTop: 14 }}>
            {isSignup && <input value={s.loginNickname} onChange={loginNicknameType} placeholder={T('Tên hiển thị của bạn', 'Your display name')} style={fieldStyle()} />}
            <input value={s.loginEmail} onChange={loginEmailType} onKeyDown={loginEmailKey} placeholder="ban@email.com" data-testid="login-email" style={fieldStyle()} />
            {showEmailFormatError && (
              <p data-testid="login-email-error" style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: 0 }}>
                {T('Email chưa đúng định dạng (ví dụ: ban@email.com)', "That doesn't look like an email address (e.g. ban@email.com)")}
              </p>
            )}
            {isPassword && <input value={s.loginPassword} onChange={loginPasswordType} onKeyDown={loginEmailKey} type="password" placeholder={T('Mật khẩu', 'Password')} style={fieldStyle()} />}
            {isPassword && isSignup && <input value={s.loginPasswordConfirm} onChange={loginPasswordConfirmType} onKeyDown={loginEmailKey} type="password" placeholder={T('Nhập lại mật khẩu', 'Confirm password')} style={fieldStyle()} />}
          </div>
          {isPassword && !isSignup && (
            <div onClick={requestPasswordResetSubmit} style={{ fontSize: 12, color: ink, opacity: 0.75, textAlign: 'right', marginTop: 8, cursor: 'pointer' }}>{T('Quên mật khẩu?', 'Forgot password?')}</div>
          )}
        </>
      )}

      {!awaitingCode && isSignup && (
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginTop: 14 }}>
          <input
            type="checkbox" checked={s.policyConsent} onChange={togglePolicyConsent}
            data-testid="login-policy-consent"
            style={{ marginTop: 2, flex: 'none', width: 16, height: 16, cursor: 'pointer', accentColor: 'var(--bb-fg)' }}
          />
          <span onClick={togglePolicyConsent} style={{ fontSize: 12, lineHeight: 1.5, color: ink, cursor: 'pointer' }}>
            {T('Tôi đồng ý với ', 'I agree to the ')}
            <span onClick={(e) => { e.stopPropagation(); openPolicy(); }} style={{ textDecoration: 'underline', fontWeight: 600 }} data-testid="login-policy-link">
              {T('Điều khoản sử dụng và Thông báo quyền riêng tư', 'Terms of Service and Privacy Notice')}
            </span>
          </span>
        </div>
      )}

      {showSubmit && <div onClick={submitCurrentForm} data-testid="login-submit" style={submitStyle}>{submitLabel}</div>}

      {s.resetRequested && !s.reserveError && <p style={note()}>{T('Nếu email này có tài khoản, một email đặt lại mật khẩu vừa được gửi.', 'If that email has an account, a password reset email was just sent.')}</p>}
      {awaitingCode && <p style={note()}>{T('Đã gửi mã tới email của bạn. Nhập mã để tiếp tục.', 'A code was sent to your email. Enter it to continue.')}</p>}
      {s.loginSentVia === 'phone' && <p style={note()}>{T('Đã gửi mã OTP. Hãy nhập mã để tiếp tục.', 'OTP sent. Enter the code to continue.')}</p>}
      {s.reserveError && <p style={note({ color: alert })}>{s.reserveError}</p>}

      {/* Web-only extras with no iOS counterpart (Zalo / phone OTP /
          Instagram are still stubs; kept for behaviour + tests), pushed
          below the main iOS-shaped form and kept visually quiet. */}
      <div style={{ marginTop: 22, paddingTop: 14, borderTop: `1px solid ${rule}` }}>
        {!awaitingCode && (
          <input value={s.loginPhoneNumber} onChange={loginPhoneType} placeholder="+84 901 234 567" inputMode="tel" style={fieldStyle()} />
        )}
        {s.loginSentVia === 'phone' && (
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            <input value={s.loginCode} onChange={loginCodeType} placeholder={T('Mã OTP', 'OTP code')} inputMode="numeric" style={fieldStyle({ flex: 1, width: 'auto' })} />
            <div onClick={verifyLoginCode} style={{ ...smallBtn, flex: 'none', padding: '14px 14px', fontWeight: 600 }}>{T('Xác nhận', 'Verify')}</div>
          </div>
        )}
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <div onClick={loginPhone} style={smallBtn}>{T('Gửi OTP', 'Send OTP')}</div>
          <div onClick={loginZalo} style={smallBtn}>{T('Tiếp tục với Zalo', 'Continue with Zalo')}</div>
          <div onClick={loginInstagram} style={smallBtn}>Instagram</div>
        </div>
      </div>
      <p style={{ fontSize: 11, lineHeight: 1.5, color: ink, margin: '16px 0 0', textAlign: 'center', opacity: 0.8 }}>{T('Đã giữ chỗ sự kiện nào thì bạn đã đăng nhập sẵn.', "If you've already reserved a spot, you're already logged in.")}</p>
    </div>
  );
}

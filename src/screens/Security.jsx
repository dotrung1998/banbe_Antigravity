import { useBanBe } from '../state/BanBeContext.jsx';
import { paper, ink, display, fieldGlass, inkButton, alert } from '../theme.js';
import { PromoConsentSection } from '../components/HostPromo.jsx'; // account gate (web parity)
import { useAccountGate } from '../lib/accountGate.js';
import { passwordChangeBlocker } from '../lib/passwordChange.js';
import PasswordChecklist from '../components/PasswordChecklist.jsx';

// Account > Security — this account's password. The iOS app's version of
// this screen (apps/ios/BanbeApp/Views/SecurityView.swift) also carries the
// Face ID app-lock; there's deliberately no web equivalent of that, since
// it gates a device that's already signed in rather than the account.
export default function Security() {
  const {
    state: s, T, set, securityPasswordType, securityPasswordConfirmType,
    securityCurrentPasswordType, securityCodeType, setSecurityProofMode, sendSecurityReauthCode,
    saveSecurityPassword,
  } = useBanBe();
  const { status: gateStatus } = useAccountGate();

  const fieldStyle = {
    ...fieldGlass({ marginTop: 10, padding: 14, border: 'none', width: '100%', boxSizing: 'border-box' }),
    fontSize: 14, fontFamily: "var(--bb-face, 'Be Vietnam Pro'), sans-serif", color: ink, outline: 'none',
  };
  const labelStyle = { display: 'block', fontSize: 12.5, fontWeight: 600, color: ink, marginTop: 16 };
  const linkStyle = { fontSize: 12.5, fontWeight: 600, color: ink, textDecoration: 'underline', cursor: 'pointer', marginTop: 12, background: 'none', border: 'none', padding: 0, fontFamily: 'inherit', textAlign: 'left' };
  const codeMode = s.securityProofMode === 'code';
  const blocker = passwordChangeBlocker({
    mode: s.securityProofMode, current: s.securityCurrentPassword, code: s.securityCode,
    password: s.securityPassword, confirm: s.securityPasswordConfirm,
  });
  const canSave = !s.securityBusy && !blocker;
  // Quiet hints only once the person has typed into the field they concern.
  const hint = blocker === 'same' && s.securityPassword
    ? T('Mật khẩu mới phải khác mật khẩu hiện tại.', 'Your new password must be different from the current one.')
    : blocker === 'confirm' && s.securityPasswordConfirm
      ? T('Mật khẩu xác nhận không khớp.', 'Passwords do not match.')
      : '';
  const onEnter = (e) => { if (e.key === 'Enter' && !e.isComposing && e.keyCode !== 229 && canSave) saveSecurityPassword(); };

  return (
    <div style={{ animation: 'banbeFade 0.32s ease both', minHeight: '100%', background: paper }} data-screen-label="Security">
      <div onClick={() => set({ screen: 'profile' })} style={{ padding: 'max(14px, calc(66px - var(--bb-status-trim, 0px))) 22px 0', fontSize: 12, color: ink, cursor: 'pointer' }}>‹ {T('Tài khoản', 'Account')}</div>
      <div style={{ padding: '16px 30px 42px' }}>
        <h1 style={{ ...display(27, { margin: 0, lineHeight: 1.2 }) }}>{T('Bảo Mật', 'Security')}</h1>
        <p style={{ fontSize: 13.5, lineHeight: 1.55, color: ink, margin: '10px 0 0' }}>
          {T('Mật khẩu tài khoản của bạn.', 'Your account password.')}
        </p>

        {s.user ? (
          <>
            <div style={{ fontSize: 'var(--bb-text-meta)', fontWeight: 600, color: ink, margin: '28px 0 0' }}>{T('Đổi mật khẩu', 'Change password')}</div>
            <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, opacity: 0.75, margin: '10px 0 0' }}>
              {T(
                'Để bảo vệ tài khoản, hãy xác nhận đó là bạn trước khi đặt mật khẩu mới.',
                'To protect your account, confirm it is you before setting a new password.'
              )}
            </p>

            {codeMode ? (
              <div data-testid="security-code-proof">
                <p style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: '14px 0 0' }}>
                  {s.securityCodeSent
                    ? T(`Đã gửi mã 6 số tới ${s.user.email || 'email của bạn'}.`, `We sent a 6-digit code to ${s.user.email || 'your email'}.`)
                    : T('Chúng tôi sẽ gửi mã 6 số tới email của tài khoản.', "We'll send a 6-digit code to this account's email.")}
                </p>
                {s.securityCodeSent ? (
                  <>
                    <label htmlFor="security-code" style={labelStyle}>{T('Mã xác nhận', 'Confirmation code')}</label>
                    <input
                      id="security-code"
                      value={s.securityCode}
                      onChange={securityCodeType}
                      onKeyDown={onEnter}
                      inputMode="numeric"
                      autoComplete="one-time-code"
                      maxLength={6}
                      placeholder="123456"
                      style={fieldStyle}
                    />
                  </>
                ) : null}
                <button type="button" onClick={s.securityBusy ? undefined : sendSecurityReauthCode} disabled={s.securityBusy} style={linkStyle}>
                  {s.securityCodeSent ? T('Gửi lại mã', 'Send a new code') : T('Gửi mã qua email', 'Email me a code')}
                </button>
                <br />
                <button type="button" onClick={() => setSecurityProofMode('password')} style={linkStyle}>
                  {T('Dùng mật khẩu hiện tại', 'Use my current password')}
                </button>
              </div>
            ) : (
              <div data-testid="security-password-proof">
                <label htmlFor="security-current" style={labelStyle}>{T('Mật khẩu hiện tại', 'Current password')}</label>
                <input
                  id="security-current"
                  value={s.securityCurrentPassword}
                  onChange={securityCurrentPasswordType}
                  onKeyDown={onEnter}
                  type="password"
                  autoComplete="current-password"
                  style={fieldStyle}
                />
                <button type="button" onClick={() => setSecurityProofMode('code')} style={linkStyle}>
                  {T('Chưa có hoặc quên mật khẩu? Xác nhận bằng mã qua email', 'No password or forgot it? Confirm with an email code')}
                </button>
              </div>
            )}

            <label htmlFor="security-new" style={labelStyle}>{T('Mật khẩu mới', 'New password')}</label>
            <input
              id="security-new"
              value={s.securityPassword}
              onChange={securityPasswordType}
              onKeyDown={onEnter}
              type="password"
              autoComplete="new-password"
              aria-describedby="security-new-rules"
              style={fieldStyle}
            />
            <div id="security-new-rules"><PasswordChecklist password={s.securityPassword} T={T} /></div>
            <label htmlFor="security-confirm" style={labelStyle}>{T('Nhập lại mật khẩu mới', 'Re-enter new password')}</label>
            <input
              id="security-confirm"
              value={s.securityPasswordConfirm}
              onChange={securityPasswordConfirmType}
              onKeyDown={onEnter}
              type="password"
              autoComplete="new-password"
              style={fieldStyle}
            />

            <div aria-live="polite">
              {s.securityError ? (
                <p role="alert" style={{ fontSize: 12, lineHeight: 1.5, color: alert, margin: '10px 0 0' }}>{s.securityError}</p>
              ) : s.securitySaved ? (
                <p data-testid="security-saved" style={{ fontSize: 12, lineHeight: 1.5, color: ink, margin: '10px 0 0' }}>
                  {s.securitySaved === 'only_here'
                    ? T('Đã đổi mật khẩu. Chưa đăng xuất được các thiết bị khác, hãy thử lại sau.', 'Password changed. We could not sign out your other devices yet, try again later.')
                    : T('Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.', 'Password changed. Other devices have been signed out.')}
                </p>
              ) : hint ? (
                <p style={{ fontSize: 12, lineHeight: 1.5, color: ink, opacity: 0.7, margin: '10px 0 0' }}>{hint}</p>
              ) : null}
            </div>

            <button
              type="button"
              onClick={canSave ? saveSecurityPassword : undefined}
              disabled={!canSave}
              data-testid="security-save"
              style={{
                ...inkButton({ marginTop: 14, borderRadius: 18, padding: 14, fontSize: 14 }),
                width: '100%', fontFamily: 'inherit',
                opacity: canSave ? 1 : 0.45,
                cursor: canSave ? 'pointer' : 'default',
              }}
            >
              {s.securityBusy ? T('Đang lưu…', 'Saving…') : T('Đổi mật khẩu', 'Change password')}
            </button>

            {gateStatus?.phone_verified ? (
              <p data-testid="security-phone-verified" style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: '22px 0 0' }}>
                ✓ {T('Số điện thoại đã được xác minh.', 'Your phone number is verified.')}
              </p>
            ) : gateStatus?.phone_test_exempt ? (
              // Distinct from "verified": the server waived the SMS step for a test
              // account (migration 159). The number is NOT confirmed — no checkmark.
              <p data-testid="security-phone-test-exempt" style={{ fontSize: 12.5, lineHeight: 1.55, color: ink, margin: '22px 0 0' }}>
                {T('Tài khoản thử nghiệm: bước xác minh SMS được miễn. Số điện thoại CHƯA được xác minh.', 'Test account: SMS verification is waived. Your phone number is NOT verified.')}
              </p>
            ) : null}
            <PromoConsentSection />{/* account gate (web parity) */}
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

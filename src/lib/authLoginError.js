// Password login: turn a Supabase auth error into the reason the person
// actually needs to see. Before this, every failure read "Wrong email or
// password", which hid a server-side CAPTCHA block (2026-11-26) behind a
// message that sent people hunting for a password that was never wrong.
//
// A wrong password and an unknown email still share one message (a login
// form should not say which). Twin: apps/ios/BanbeApp/Lib/AuthLoginError.swift.

const RATE_LIMIT_CODES = new Set(['over_request_rate_limit', 'over_email_send_rate_limit', 'over_sms_send_rate_limit']);

export function passwordLoginErrorKind(error) {
  if (!error) return null;
  const code = String(error.code || '');
  const status = Number(error.status) || 0;
  if (code === 'invalid_credentials' || code === 'user_not_found') return 'credentials';
  if (code === 'email_not_confirmed') return 'email_not_confirmed';
  if (code === 'captcha_failed') return 'captcha';
  if (code === 'user_banned') return 'banned';
  if (RATE_LIMIT_CODES.has(code) || status === 429) return 'rate_limit';
  if (error.name === 'AuthRetryableFetchError' || (status === 0 && !code)) return 'network';
  // Older GoTrue answers carry no code: a 400 on the password grant is the credentials case.
  if (!code && status === 400) return 'credentials';
  return 'other';
}

export function passwordLoginErrorText(error, T) {
  const kind = passwordLoginErrorKind(error);
  switch (kind) {
    case null:
      return '';
    case 'credentials':
      return T('Sai email hoặc mật khẩu.', 'Wrong email or password.');
    case 'email_not_confirmed':
      return T('Email này chưa được xác nhận. Hãy đăng nhập bằng mã qua email để xác nhận.', 'This email is not confirmed yet. Log in with an email code to confirm it.');
    case 'captcha':
      return T('Kiểm tra bảo mật đang chặn đăng nhập. Vui lòng thử lại sau.', 'A security check is blocking sign-in right now. Please try again later.');
    case 'banned':
      return T('Tài khoản này đang bị khoá. Hãy liên hệ banbe.', 'This account is locked. Please contact banbe.');
    case 'rate_limit':
      return T('Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.', 'Too many attempts. Wait a few minutes and try again.');
    case 'network':
      return T('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.', 'Could not reach the server. Check your connection and try again.');
    default: {
      const code = error.code || (error.status ? `HTTP ${error.status}` : '');
      const suffix = code ? ` (${code})` : '';
      return T(`Không thể đăng nhập lúc này. Vui lòng thử lại sau.${suffix}`, `We could not log you in right now. Please try again later.${suffix}`);
    }
  }
}

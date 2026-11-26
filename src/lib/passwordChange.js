// Account › Security "change password": the pure rules (when Save may run, and
// what a failed step tells the person). Kept apart from the screen so the web
// unit tests can pin them. Twin: apps/ios/BanbeApp/Lib/PasswordChange.swift.
import { passwordMeetsRules } from './passwordRules.js';

const RATE_LIMIT_CODES = new Set(['over_request_rate_limit', 'over_email_send_rate_limit', 'over_sms_send_rate_limit']);

function isNetwork(error) {
  const status = Number(error?.status) || 0;
  return error?.name === 'AuthRetryableFetchError' || (status === 0 && !error?.code);
}

/**
 * Why Save is still off, or null when it may run.
 * mode: 'password' (proves it with the current password) | 'code' (emailed reauthentication code).
 */
export function passwordChangeBlocker({ mode, current, code, password, confirm }) {
  if (mode === 'code') {
    if (!/^\d{6}$/.test(String(code || '').trim())) return 'proof';
  } else if (!current) {
    return 'proof';
  }
  if (!passwordMeetsRules(password)) return 'rules';
  if (mode !== 'code' && password === current) return 'same';
  if (password !== confirm) return 'confirm';
  return null;
}

/** Text for checking the current password on the throwaway client. */
export function currentPasswordErrorText(error, T) {
  if (!error) return '';
  const code = String(error.code || '');
  const status = Number(error.status) || 0;
  if (code === 'invalid_credentials' || (!code && status === 400)) {
    return T('Mật khẩu hiện tại không đúng.', 'Your current password is not correct.');
  }
  if (RATE_LIMIT_CODES.has(code) || status === 429) {
    return T('Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.', 'Too many attempts. Wait a few minutes and try again.');
  }
  if (code === 'captcha_failed') {
    return T('Kiểm tra bảo mật đang chặn bước này. Hãy xác nhận bằng mã qua email.', 'A security check is blocking this step. Confirm with an email code instead.');
  }
  if (isNetwork(error)) {
    return T('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.', 'Could not reach the server. Check your connection and try again.');
  }
  const suffix = code ? ` (${code})` : status ? ` (HTTP ${status})` : '';
  return T(`Không kiểm tra được mật khẩu hiện tại.${suffix}`, `We could not check your current password.${suffix}`);
}

/** Text for a failed updateUser({ password }) or reauthenticate(). */
export function passwordUpdateErrorText(error, T) {
  if (!error) return '';
  const code = String(error.code || '');
  const status = Number(error.status) || 0;
  if (code === 'same_password') {
    return T('Mật khẩu mới phải khác mật khẩu hiện tại.', 'Your new password must be different from the current one.');
  }
  if (code === 'weak_password') {
    return T('Mật khẩu này quá yếu hoặc đã bị lộ ở nơi khác. Hãy chọn mật khẩu khác.', 'This password is too weak or has appeared in a data leak. Choose a different one.');
  }
  if (code === 'reauthentication_needed') {
    return T('Cần xác nhận lại. Hãy xác nhận bằng mã qua email.', 'Please confirm it is you again. Use an email code.');
  }
  if (code === 'reauthentication_not_valid') {
    return T('Mã xác nhận không đúng hoặc đã hết hạn.', 'That confirmation code is wrong or has expired.');
  }
  if (RATE_LIMIT_CODES.has(code) || status === 429) {
    return T('Bạn đã thử quá nhiều lần. Hãy đợi vài phút rồi thử lại.', 'Too many attempts. Wait a few minutes and try again.');
  }
  if (isNetwork(error)) {
    return T('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.', 'Could not reach the server. Check your connection and try again.');
  }
  const suffix = code ? ` (${code})` : status ? ` (HTTP ${status})` : '';
  return T(`Không lưu được mật khẩu lúc này. Vui lòng thử lại.${suffix}`, `We could not save that password right now. Please try again.${suffix}`);
}

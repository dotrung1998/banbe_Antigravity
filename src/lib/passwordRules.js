// One password rule for every place a password is chosen: sign-up, Account ›
// Security (change), and the reset-link "choose a new password" screen. The
// checklist under the field renders these items in order; the submit button
// stays off until every item is met. Logging in never checks these (older
// accounts may have shorter passwords and must still get in).
// Twin: apps/ios/BanbeApp/Lib/PasswordRules.swift (same ids, order, copy).

export const PASSWORD_MIN_LENGTH = 8;

const RULES = [
  { id: 'length', test: (pw) => [...pw].length >= PASSWORD_MIN_LENGTH, vi: 'Ít nhất 8 ký tự', en: 'At least 8 characters' },
  { id: 'lower', test: (pw) => /\p{Ll}/u.test(pw), vi: 'Một chữ thường', en: 'One lowercase letter' },
  { id: 'upper', test: (pw) => /\p{Lu}/u.test(pw), vi: 'Một chữ hoa', en: 'One uppercase letter' },
  { id: 'number', test: (pw) => /\p{Nd}/u.test(pw), vi: 'Một chữ số', en: 'One number' },
];

/** [{ id, ok, vi, en }] in display order. */
export function passwordChecks(password) {
  const pw = typeof password === 'string' ? password : '';
  return RULES.map(({ id, test, vi, en }) => ({ id, ok: test(pw), vi, en }));
}

export function passwordMeetsRules(password) {
  return passwordChecks(password).every((c) => c.ok);
}

// When the Login / Sign up email field may say "that's not an email address".
// Complaining while someone is still typing reads as nagging, so the check only
// "arms" once they leave the field (blur) or press submit / Enter, and typing
// again disarms it until the next leave or submit. A valid address never shows
// the error, so fixing it clears the message on the keystroke that fixes it.
// Twin: apps/ios/BanbeApp/Views/LoginView.swift (emailChecked + @FocusState).

/** @param {'type'|'blur'|'submit'} event */
export function emailCheckedAfter(event) {
  return event === 'blur' || event === 'submit';
}

export function showEmailFormatError({ email, valid, checked }) {
  const entered = String(email ?? '').trim().length > 0;
  return Boolean(checked) && entered && !valid;
}

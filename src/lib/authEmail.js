async function postJson(path, body) {
  const response = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error || payload.message || 'AUTH_REQUEST_FAILED');
    error.code = payload.error || payload.code;
    if (payload.message) error.message = payload.message;
    throw error;
  }
  return payload;
}

// Sends a 6-digit sign-in/sign-up code by email. The caller still has to
// finish the flow with supabase.auth.verifyOtp({ email, token, type }) —
// this only triggers the email, it never returns a session. `locale` only
// actually matters for a brand-new signup (an existing login's email
// follows that account's own saved profiles.locale instead) — see
// api/auth/index.js (dispatched by `type` — consolidated from three
// standalone functions to fit the Vercel Hobby-plan serverless function cap).
export async function requestAuthEmail({ email, mode, displayName, locale }) {
  return postJson('/api/auth', { type: 'send_email_code', email, mode, locale, ...(displayName ? { displayName } : {}) });
}

// Password-based sign-up. Also finishes with
// supabase.auth.verifyOtp({ email, token, type: 'signup' }) once the emailed
// confirmation code comes back — this only creates the (unconfirmed) account
// and sends that code.
export async function requestPasswordSignup({ email, password, displayName, locale }) {
  return postJson('/api/auth', { type: 'signup_password', email, password, displayName, locale });
}

// "Forgot password" — always resolves the same way whether or not the
// account exists (the server intentionally doesn't say), so the caller
// should show a generic "if that email has an account, check it" message
// rather than branching on the response.
export async function requestPasswordReset({ email }) {
  return postJson('/api/auth', { type: 'send_password_reset', email });
}

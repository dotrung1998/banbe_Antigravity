export async function requestAuthEmail({ email, mode, accountType }) {
  const response = await fetch('/api/auth/send-email-link', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, mode, accountType }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error || payload.message || 'AUTH_EMAIL_SEND_FAILED');
    error.code = payload.error || payload.code;
    if (payload.message) error.message = payload.message;
    throw error;
  }
  return payload;
}
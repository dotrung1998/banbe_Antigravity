export async function requestAuthEmail({ email, mode, accountType }) {
  const response = await fetch('/api/auth/send-email-link', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, mode, accountType }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || 'AUTH_EMAIL_SEND_FAILED');
  return payload;
}
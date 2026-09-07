export async function sendEmail({ to, subject, text, html }) {
  const response = await fetch('/api/send-email', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ to, subject, text, html }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || 'EMAIL_SEND_FAILED');
  }

  return payload;
}
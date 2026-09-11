import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration } from '../_lib/authLookup.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

// Password-based sign-up. Creates the auth user with the password the
// person actually chose (unlike the code-based sign-up in
// send-email-code.js, which sets an unguessable placeholder password since
// that flow never needs one) and emails a 6-digit confirmation code, the
// same way send-email-code.js does — the client still finishes with
// supabase.auth.verifyOtp({ email, token, type: 'signup' }), establishing
// the session itself; this endpoint never sees or issues a session.
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  const admin = getSupabaseAdmin();
  const missing = [
    ...getMissingEmailVariables(),
    !admin && 'SUPABASE_SERVICE_ROLE_KEY',
  ].filter(Boolean);
  if (missing.length) {
    return res.status(503).json({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing });
  }

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const email = getText(body.email).toLowerCase();
  const password = typeof body.password === 'string' ? body.password : '';
  const displayName = getText(body.displayName).slice(0, 60);

  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });
  if (!displayName) return res.status(400).json({ error: 'VALID_NAME_REQUIRED' });
  if (password.length < 8) return res.status(400).json({ error: 'VALID_PASSWORD_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }
  if (authUserId) {
    await linkRegistration(admin, email, authUserId);
    return res.status(409).json({ error: 'AUTH_ACCOUNT_EXISTS' });
  }

  try {
    const { data, error } = await admin.auth.admin.generateLink({
      type: 'signup',
      email,
      password,
      options: { data: { display_name: displayName } },
    });
    const code = data?.properties?.email_otp;

    if (error || !code) {
      console.error('Supabase signup OTP generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    await linkRegistration(admin, email, data?.user?.id || null);

    const subject = 'Confirm your banbe account';
    try {
      await sendWithGmail({
        to: email,
        subject,
        text: `${subject}\n\nEnter this code in the app: ${code}\n\nThis code expires shortly. If you did not request this, you can ignore it.`,
        html: `<p>${subject}</p><p style="font-size:28px;font-weight:700;letter-spacing:4px;">${code}</p><p>Enter this code in the app. It expires shortly. If you did not request this, you can ignore it.</p>`,
      });
    } catch (error) {
      console.error('Gmail auth email delivery failed:', error);
      return res.status(502).json({ error: 'AUTH_EMAIL_DELIVERY_FAILED' });
    }

    return res.status(200).json({ sent: true });
  } catch (error) {
    console.error('Signup password request failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_REQUEST_FAILED' });
  }
}

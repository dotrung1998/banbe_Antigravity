import { getMissingEmailVariables, sendWithGmail } from '../_lib/email.js';
import { getSupabaseAdmin, resolveAuthUserId, linkRegistration, getRedirectUrl } from '../_lib/authLookup.js';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[character]));
}

// "Automatic" password reset: unlike sign-in/sign-up, this stays a link
// rather than a code — clicking it lands the browser back on the app with
// a Supabase "recovery" session already established (src/lib/supabase.js
// has detectSessionInUrl on; GocContext's onAuthStateChange listens for the
// PASSWORD_RECOVERY event and routes to the reset-password screen), where
// the person sets a new password with supabase.auth.updateUser({ password })
// directly — no code to type in by hand.
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
  if (!EMAIL_PATTERN.test(email)) return res.status(400).json({ error: 'VALID_EMAIL_REQUIRED' });

  const { userId: authUserId, resolved, sources } = await resolveAuthUserId(admin, email);
  if (!resolved) {
    console.error('Account lookup could not be completed:', sources);
    return res.status(502).json({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' });
  }

  // Deliberately the same 200 response whether or not the account exists —
  // a password-reset form is exactly the wrong place to let someone probe
  // which emails have an account. Only actually send the email if one does.
  if (!authUserId) return res.status(200).json({ sent: true });
  await linkRegistration(admin, email, authUserId);

  try {
    const { data, error } = await admin.auth.admin.generateLink({
      type: 'recovery',
      email,
      options: { redirectTo: getRedirectUrl(req) },
    });

    if (error || !data?.properties?.action_link) {
      console.error('Supabase recovery link generation failed:', error);
      return res.status(502).json({ error: 'AUTH_LINK_GENERATION_FAILED' });
    }

    const actionLink = data.properties.action_link;
    const subject = 'Reset your banbe password';
    const safeLink = escapeHtml(actionLink);
    try {
      await sendWithGmail({
        to: email,
        subject,
        text: `${subject}\n\nOpen this link to choose a new password: ${actionLink}\n\nIf you did not request this, you can ignore it.`,
        html: `<p>${subject}</p><p><a href="${safeLink}">Choose a new password</a></p><p>If you did not request this, you can ignore it.</p>`,
      });
    } catch (error) {
      console.error('Gmail auth email delivery failed:', error);
      return res.status(502).json({ error: 'AUTH_EMAIL_DELIVERY_FAILED' });
    }

    return res.status(200).json({ sent: true });
  } catch (error) {
    console.error('Password reset request failed:', error);
    return res.status(502).json({ error: 'AUTH_EMAIL_REQUEST_FAILED' });
  }
}
